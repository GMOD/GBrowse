package Bio::Graphics::Browser::DataSource;

use strict;
use warnings;
use base 'Bio::Graphics::FeatureFile';

use Bio::Graphics::Browser::Shellwords;
use Bio::Graphics::Browser::Util 'modperl_request';
use File::Basename 'dirname';
use File::Path 'mkpath';
use Data::Dumper 'Dumper';
use Digest::MD5 'md5_hex';
use Carp 'croak';
use Socket 'AF_INET','inet_aton';  # for inet_aton() call
use CGI '';

my %CONFIG_CACHE; # cache parsed config files
my %DB_SETTINGS;  # cache database settings
my %DB;           # cache opened database connections

=head1 SYNOPSIS

=head1 DESCRIPTION

=head2 METHODS

=over 4

=cut

sub new {
  my $class            = shift;
  my $config_file_path = shift;
  my ($name,$description,$globals) = @_;

  # this code caches the config info so that we don't need to reparse in persistent (e.g. modperl) environment
  my $mtime            = (stat($config_file_path))[9];
  if (exists $CONFIG_CACHE{$config_file_path}
      && $CONFIG_CACHE{$config_file_path}{mtime} >= $mtime) {
    return $CONFIG_CACHE{$config_file_path}{object};
  }

  my $self = $class->SUPER::new(-file=>$config_file_path,-safe=>1);
  $self->name($name);
  $self->description($description);
  $self->globals($globals);
  $self->dir(dirname($config_file_path));
  $self->add_scale_tracks();
  $CONFIG_CACHE{$config_file_path}{object} = $self;
  $CONFIG_CACHE{$config_file_path}{mtime}  = $mtime;
  return $self;
}

sub name {
  my $self = shift;
  my $d    = $self->{name};
  $self->{name} = shift if @_;
  $d;
}
sub description {
  my $self = shift;
  my $d    = $self->{description};
  $self->{description} = shift if @_;
  $d;
}

sub dir {
  my $self = shift;
  my $d    = $self->{dir};
  $self->{dir} = shift if @_;
  $d;
}

sub globals {
  my $self = shift;
  my $d    = $self->{globals};
  $self->{globals} = shift if @_;
  $d;
}

=head2 global_setting()

  $setting = $source->global_setting('option')

Like setting() except that it is only for 'general' options. If the
option is not found in the datasource config file, then looks in the
global file.

=cut

sub global_setting {
  my $self   = shift;
  my $option = shift;
  my $value  = $self->setting(general=>$option);
  return $value if defined $value;
  return $self->globals->setting(general=>$option);
}

# format for time can be in any of the forms...
# "now" -- 0 seconds
# "+180s" -- in 180 seconds
# "+2m" -- in 2 minutes
# "+12h" -- in 12 hours
# "+1d"  -- in 1 day
# "+3M"  -- in 3 months
# "+2y"  -- in 2 years
# "-3m"  -- 3 minutes ago(!)
# If you don't supply one of these forms, we assume you are
# specifying the date yourself

sub global_time {
    my $self   = shift;
    my $option = shift;

    my $time = $self->global_setting($option);
    return unless defined($time);

    $time =~ s/\s*#.*$//; # strip comments

    my(%mult) = ('s'=>1,
                 'm'=>60,
                 'h'=>60*60,
                 'd'=>60*60*24,
                 'M'=>60*60*24*30,
                 'y'=>60*60*24*365);
    my $offset = $time;
    if (!$time || (lc($time) eq 'now')) {
	$offset = 0;
    } elsif ($time=~/^([+-]?(?:\d+|\d*\.\d*))([smhdMy])/) {
	$offset = ($mult{$2} || 1)*$1;
    }
    return $offset;
}

# this method is for compatibility with some plugins
sub config {
  my $self = shift;
  return $self;
}

sub unit_label {
  my $self  = shift;
  my $value = shift;

  my $unit     = $self->setting('units')        || 'bp';
  my $divider  = $self->setting('unit_divider') || 1;
  $value /= $divider;
  my $abs = abs($value);

  my $label;
  $label = $abs >= 1e9  ? sprintf("%.4g G%s",$value/1e9,$unit)
         : $abs >= 1e6  ? sprintf("%.4g M%s",$value/1e6,$unit)
         : $abs >= 1e3  ? sprintf("%.4g k%s",$value/1e3,$unit)
	 : $abs >= 1    ? sprintf("%.4g %s", $value,    $unit)
	 : $abs >= 1e-2 ? sprintf("%.4g c%s",$value*100,$unit)
	 : $abs >= 1e-3 ? sprintf("%.4g m%s",$value*1e3,$unit)
	 : $abs >= 1e-6 ? sprintf("%.4g u%s",$value*1e6,$unit)
	 : $abs >= 1e-9 ? sprintf("%.4g n%s",$value*1e9,$unit)
         : sprintf("%.4g p%s",$value*1e12,$unit);
  if (wantarray) {
    return split ' ',$label;
  } else {
    return $label;
  }
}

sub commas {
    my $self = shift;
    my $i = shift;
    return $i if $i=~ /\D/;
    $i = reverse $i;
    $i =~ s/(\d{3})/$1,/g;
    chop $i if $i=~/,$/;
    $i = reverse $i;
    $i;
}

#copy over from Render.pm to provide wider availability?
#sub overview_ratio {
#  my $self = shift;
#  return 1.0;   # for now
#}

#copied from lib/ .. / Browser.pm
sub gd_cache_path {
  my $self = shift;
  my ($cache_name,@keys) = @_;
  return unless $self->setting(general=>$cache_name);
  my $signature = md5_hex(@keys);
  my ($uri,$path) = $self->tmpdir($self->source.'/cache_overview');
  my $extension   = 'gd';
  return "$path/$signature.$extension";
}

##untested
sub gd_cache_check {
  my $self = shift;
  my ($cache_name,$path) = @_;
  return if param('nocache');
  my $cache_file_mtime   = (stat($path))[9] || 0;
  my $conf_file_mtime    = $self->mtime;
  my $cache_expiry       = $self->config->setting(general=>$cache_name) * 60*60;  # express expiry time as seconds
  if ($cache_file_mtime && ($cache_file_mtime > $conf_file_mtime) && (time() - $cache_file_mtime < $cache_expiry)) {
    my $gd = GD::Image->newFromGd($path);
    return $gd;
  }
  else {
    return;
  }
}


sub gd_cache_write {
  my $self = shift;
  my $path = shift or return;
  my $gd   = shift;
  my $file = IO::File->new(">$path") or return;
  print $file $gd->gd;
  close $file;
}

sub tmpdir {
  my $self = shift;
  my $path = shift || '';

  my ($tmpuri,$tmpdir) = shellwords($self->global_setting('tmpimages'))
    or die "no tmpimages option defined, can't generate a picture";

  $tmpuri .= "/$path" if $path;

  if ($ENV{MOD_PERL} ) {
    my $r          = modperl_request();
    my $subr       = $r->lookup_uri($tmpuri);
    $tmpdir        = $subr->filename;
    my $path_info  = $subr->path_info;
    $tmpdir       .= $path_info if $path_info;
  } elsif ($tmpdir) {
    $tmpdir .= "/$path" if $path;
  }
  else {
    $tmpdir = "$ENV{DOCUMENT_ROOT}/$tmpuri";
  }

  # we need to untaint tmpdir before calling mkpath()
  return unless $tmpdir =~ /^(.+)$/;
  $path = $1;

  mkpath($path,0,0777) unless -d $path;
  return ($tmpuri,$path);
}

sub overview_bgcolor { shift->global_setting('overview bgcolor')         }
sub detailed_bgcolor { shift->global_setting('detailed bgcolor')         }
sub key_bgcolor      { shift->global_setting('key bgcolor')              }
sub image_widths     { shellwords(shift->global_setting('image widths')) }
sub default_width    { shift->global_setting('default width')            }

sub head_html        { shift->global_setting('head')                     }
sub header_html      { shift->global_setting('header')                   }
sub footer_html      { shift->global_setting('footer')                   }
sub html1            { shift->global_setting('html1')                    }
sub html2            { shift->global_setting('html2')                    }
sub html3            { shift->global_setting('html3')                    }
sub html4            { shift->global_setting('html4')                    }
sub html5            { shift->global_setting('html5')                    }
sub html6            { shift->global_setting('html6')                    }

sub max_segment      { shift->global_setting('max segment')              }
sub default_segment  { shift->global_setting('max segment')              }
sub min_overview_pad { shift->global_setting('min overview pad') || 10    }

sub plugins          { shellwords(shift->global_setting('plugins'))      }


sub labels {
  my $self   = shift;

  # filter out all configured types that correspond to the overview, overview details
  # plugins, or other name:value types
  my @labels =  grep {
    !($_ eq 'TRACK DEFAULTS' || /:(\d+|plugin|DETAILS|details)$/)
       } $self->configured_types;
  # apply restriction rules
  return grep { $self->authorized($_)} @labels;
}

sub detail_tracks {
  my $self = shift;
  return grep { !/:.+$/ } $self->labels;
}

sub overview_tracks {
  my $self = shift;
  grep { ($_ eq 'overview' || /:overview$/ && !/^_/) && $self->authorized($_) } $self->configured_types;
}

sub regionview_tracks {
  my $self = shift;
  grep { ($_ eq 'region' || /:region$/) &&   !/^_/ && $self->authorized($_) } $self->configured_types;
}

sub karyotype_tracks {
  my $self = shift;
  grep { ($_ eq 'karyotype' || /:karyotype$/) && $self->authorized($_) } $self->configured_types;
}

sub plugin_tracks {
  my $self = shift;
  grep { ($_ eq 'plugin' || /plugin:/) && $self->authorized($_) } $self->configured_types;
}

sub label2type {
  my ($self,$label,$length) = @_;
  my $l = $self->semantic_label($label,$length);
  return shellwords($self->setting($l,'feature')||$self->setting($label,'feature')||'');
}

sub default_style {
  my $self = shift;
  return $self->SUPER::style('TRACK DEFAULTS');
}

sub style {
  my ($self,$label,$length) = @_;
  my $l = $self->semantic_label($label,$length);
  return $l eq $label ? $self->SUPER::style($l) : ($self->SUPER::style($label),$self->SUPER::style($l));
}

# return language-specific options
sub i18n_style {
  my $self      = shift;
  my ($label,$lang,$length) = @_;

  return $self->style($label,$length) unless $lang;

  my $charset   = $lang->tr('CHARSET');

  # GD can't handle non-ASCII/LATIN scripts transparently
  return $self->style($label,$length) 
    if $charset && $charset !~ /^(us-ascii|iso-8859)/i;

  my @languages = $lang->language;

  push @languages,'';
  # ('fr_CA','fr','en_BR','en','')

  my $idx = 1;
  my %priority = map {$_=>$idx++} @languages;
  # ('fr-ca'=>1, 'fr'=>2, 'en-br'=>3, 'en'=>4, ''=>5)

  my %options  = $self->style($label,$length);
  my %lang_options = map { $_->[1] => $options{$_->[0]} }
    sort { $b->[2]<=>$a->[2] }
      map { my ($option,undef,$lang) = /^(-[^:]+)(:(\w+))?$/; [$_ => $option, $priority{$lang||''}||99] }
	keys %options;
  %lang_options;
}


sub setting {
  my $self = shift;
  my ($label,$option,@rest) = @_ >= 2 ? @_ : ('general',@_);
  $self->SUPER::setting($label,$option,@rest);
}

# like setting, but defaults to 'general'
sub fallback_setting {
  my $self = shift;
  my ($label,$option,@rest) = @_;
  my $setting = $self->SUPER::setting($label,$option,@rest);
  return $setting if defined $setting;
  return $self->SUPER::setting('general',$option,@rest);
}

sub plugin_setting {
  my $self           = shift;
  my $caller_package = caller();
  my ($last_name)    = $caller_package =~ /(\w+)$/;
  my $option_name    = "${last_name}:plugin";
  $self->setting($option_name => @_);
}

sub karyotype_setting {
  my $self           = shift;
  my $caller_package = caller();
  $self->setting('builtin:karyotype' => @_);
}

# like code_setting, but obeys semantic hints
sub semantic_setting {
  my ($self,$label,$option,$length) = @_;
  my $slabel = $self->semantic_label($label,$length);
  my $val = $self->code_setting($slabel => $option) if defined $slabel;

  return $val if defined $val;
  return $self->code_setting($label => $option);
}

sub semantic_label {
  my ($self,$label,$length) = @_;
  return $label unless defined $length && $length > 0;
  # look for:
  # 1. a section like "Gene:100000" where the cutoff is less than the length of the segment
  #    under display.
  # 2. a section like "Gene" which has no cutoff to use.
  if (my @lowres = map {[split ':']}
      grep {/$label:(\d+)/ && $1 <= $length}
      $self->configured_types)
    {
      ($label) = map {join ':',@$_} sort {$b->[1] <=> $a->[1]} @lowres;
    }
  $label
}

=head2 $section_setting = $data_source->section_setting($section_name)

Returns "open" "closed" or "off" for the named section. Named sections are:

 instructions
 search
 overview
 details
 tracks
 display
 add tracks

=cut

sub section_setting {
  my $self = shift;
  my $section = shift;
  my $config_setting = "\L$section\E section";
  my $s = $self->setting($config_setting);
  return 'open' unless defined $s;
  return $s;
}

sub get_ranges {
  my $self      = shift;
  my $divisor   = $self->setting('unit_divider') || 1;
  my $rangestr  = $self->setting('zoom levels')  || '100 1000 10000 100000 1000000 10000000';
  if ($divisor == 1 ) {
    return split /\s+/,$rangestr;
  } else {
    return map {$_ * $divisor} split /\s+/,$rangestr;
  }
}

# override inherited in order to be case insensitive
# and to account for semantic zooming
sub type2label {
  my $self           = shift;
  my ($type,$length) = @_;
  $type   ||= '';
  $length ||= 0;

  my @labels;

  @labels = @{$self->{_type2labelmemo}{$type,$length}}
    if defined $self->{_type2labelmemo}{$type,$length};

  unless (@labels) {
    my @array  = $self->SUPER::type2label(lc $type) or return;
    my %label_groups;
    for my $label (@array) {
      my ($label_base,$minlength) = $label =~ /(.+)(?::(\d+))?/;
      $minlength ||= 0;
      next if defined $length && $minlength > $length;
      $label_groups{$label_base}++;
    }
    @labels = keys %label_groups;
    $self->{_type2labelmemo}{$type,$length} = \@labels;
  }
  return wantarray ? @labels : $labels[0];
}

# override inherited in order to allow for semantic zooming
sub feature2label {
  my $self = shift;
  my ($feature,$length) = @_;
  my $type  = eval {$feature->type}
    || eval{$feature->source_tag} || eval{$feature->primary_tag} or return;

  (my $basetype = $type) =~ s/:.+$//;
  my @label = $self->type2label($type,$length);

  # WARNING: if too many features start showing up in tracks, uncomment
  # the following line and comment the one after that.
  #@label    = $self->type2label($basetype,$length) unless @label;
  push @label,$self->type2label($basetype,$length);

  @label    = ($type) unless @label;

  # remove duplicate labels
  my %seen;
  @label = grep {! $seen{$_}++ } @label; 

  wantarray ? @label : $label[0];
}

sub invert_types {
  my $self = shift;
  my $config  = $self->{config} or return;
  my %inverted;
  for my $label (keys %{$config}) {
#    next if $label=~/:?(overview|region)$/;   # special case
    my $feature = $config->{$label}{'feature'} or next;
    foreach (shellwords($feature||'')) {
      $inverted{lc $_}{$label}++;
    }
  }
  \%inverted;
}

sub default_labels {
  my $self = shift;
  my $defaults = $self->setting('general'=>'default features');
  return $self->scale_tracks,shellwords($defaults||'');
}

=head2 add_scale_tracks()

This is called at initialization time to add track configs
for the automatic "scale" (arrow) tracks for details, overview and regionview

=cut

sub add_scale_tracks {
    my $self = shift;
    my @scale_tracks = $self->scale_tracks;

    for my $label (@scale_tracks) {
	$self->add_type($label,{
	    'global feature' => 1,
	    glyph          => 'arrow',
	    fgcolor        => 'black',
	    double         => 1,
	    tick           => 2,
	    label          => 1,
	    key            => 'none',
			});
    }
    # Sort of a bug here. We want the scale tracks to start out on the
    # top of the others. But add_type puts the labels on the bottom. So
    # we reorder so these guys come first. This breaks encapsulation.
    my @types            = @{$self->{types}};
    my $items_to_reorder = @scale_tracks;
    my @items            = splice(@types,-$items_to_reorder);

    splice(@types,0,0,@items);
    $self->{types} = \@types;
}

sub scale_tracks { return qw(_scale _scale:overview _scale:region); }

# return a hashref in which keys are the thresholds, and values are the list of
# labels that should be displayed
sub summary_mode {
  my $self = shift;
  my $summary = $self->settings(general=>'summary mode') or return {};
  my %pairs = $summary =~ /(\d+)\s+{([^\}]+?)}/g;
  foreach (keys %pairs) {
    my @l = shellwords($pairs{$_}||'');
    $pairs{$_} = \@l
  }
  \%pairs;
}


# implement the "restrict" option
sub authorized {
  my $self  = shift;
  my $label = shift;

  my $restrict = $self->code_setting($label=>'restrict')
    || ($label ne 'general' && $self->code_setting('TRACK DEFAULTS' => 'restrict'));

  return 1 unless $restrict;
  my $host     = CGI->remote_host;
  my $user     = CGI->remote_user;
  my $addr     = CGI->remote_addr;

  undef $host if $host eq $addr;
  return $restrict->($host,$addr,$user) if ref $restrict eq 'CODE';
  my @tokens = split /\s*(satisfy|order|allow from|deny from|require user|require group|require valid-user)\s*/i,$restrict;
  shift @tokens unless $tokens[0] =~ /\S/;
  my $mode    = 'allow,deny';
  my $satisfy = 'all';
  my $user_directive;

  my (@allow,@deny,%users);
  while (@tokens) {
    my ($directive,$value) = splice(@tokens,0,2);
    $directive = lc $directive;
    $value ||= '';
    if ($directive eq 'order') {
      $mode = $value;
      next;
    }
    my @values = split /[^\w.-]/,$value;

    if ($directive eq 'allow from') {
      push @allow,@values;
      next;
    }
    if ($directive eq 'deny from') {
      push @deny,@values;
      next;
    }
    if ($directive eq 'satisfy') {
      $satisfy = $value;
      next;
    }
    if ($directive eq 'require user') {
      $user_directive++;
      foreach (@values) {
	if ($_ eq 'valid-user' && defined $user) {
	  $users{$user}++;  # ensures that this user will match
	} else {
	  $users{$_}++;
	}
      }
      next;
    }
    if ($directive eq 'require valid-user') {
      $user_directive++;
      $users{$user}++ if defined $user;
    }
    if ($directive eq 'require group') {
      croak "Sorry, but gbrowse does not support the require group limit.  Use a subroutine to implement role-based authentication.";
    }
  }
  my $allow = $mode eq  'allow,deny' ? match_host(\@allow,$host,$addr) && !match_host(\@deny,$host,$addr)
                      : 'deny,allow' ? !match_host(\@deny,$host,$addr) ||  match_host(\@allow,$host,$addr)
		      : croak "$mode is not a valid authorization mode";
  return $allow unless $user_directive;
  $satisfy = 'any'  if !@allow && !@deny;  # no host restrictions

  # prevent unint variable warnings
  $user         ||= '';
  $allow        ||= '';
  $users{$user} ||= '';

  return $satisfy eq 'any' ? $allow || $users{$user}
                           : $allow && $users{$user};
}

sub match_host {
  my ($matches,$host,$addr) = @_;
  my $ok;
  for my $candidate (@$matches) {
    if ($candidate eq 'all') {
      $ok ||= 1;
    } elsif ($candidate =~ /^[\d.]+$/) { # ip match
      $addr      .= '.' unless $addr      =~ /\.$/;  # these lines ensure subnets match correctly
      $candidate .= '.' unless $candidate =~ /\.$/;
      $ok ||= $addr =~ /^\Q$candidate\E/;
    } else {
      $host ||= gethostbyaddr(inet_aton($addr),AF_INET);
      next unless $host;
      $candidate = ".$candidate" unless $candidate =~ /^\./; # these lines ensure domains match correctly
      $host      = ".$host"      unless $host      =~ /^\./;
      $ok ||= $host =~ /\Q$candidate\E$/;
    }
    return 1 if $ok;
  }
  $ok;
}

sub make_link {
  croak "Do not call make_link() on the DataSource. Call it on the Render object";
}


=item ($adaptor,@argv) = $dsn->db_settings('track_label')

Return the adaptor and arguments suitable for the database identified
by the given track label. If no track label is given then the
"general" default database is used.

=cut

# get the db settings for a track or from [general]
sub db_settings {
  my $self  = shift;
  my $track = shift;

  $track ||= 'general';

  # caching to avoid calling setting() too many times
  return @{$DB_SETTINGS{$self,$track}} if $DB_SETTINGS{$self,$track};

  my $adaptor = $self->fallback_setting($track => 'db_adaptor') or die "No db_adaptor specified";
  eval "require $adaptor; 1" or die $@;

  my $args    = $self->fallback_setting($track => 'db_args');
  my @argv = ref $args eq 'CODE'
        ? $args->()
	: shellwords($args||'');

  # for compatibility with older versions of the browser, we'll hard-code some arguments
  if (my $adaptor = $self->fallback_setting($track => 'adaptor')) {
    push @argv,(-adaptor => $adaptor);
  }

  if (my $dsn = $self->fallback_setting($track => 'database')) {
    push @argv,(-dsn => $dsn);
  }

  if (my $fasta = $self->fallback_setting($track => 'fasta_files')) {
    push @argv,(-fasta=>$fasta);
  }

  if (my $user = $self->fallback_setting($track => 'user')) {
    push @argv,(-user=>$user);
  }

  if (my $pass = $self->fallback_setting($track => 'pass')) {
    push @argv,(-pass=>$pass);
  }

  if (defined (my $a = $self->fallback_setting($track => 'aggregators'))) {
    my @aggregators = shellwords($a||'');
    push @argv,(-aggregator => \@aggregators);
  }

  my @result = ($adaptor,@argv);

  # cache settings
  $DB_SETTINGS{$self,$track} = \@result;

  return @result;
}

=item $db = $dsn->open_database('track')

Return the database handle specified by the given track label or
'general' if not given. The databases are cached and so it is ok to
call repeatedly.

=cut

sub open_database {
  my $self  = shift;
  my $track = shift;

  my ($adaptor,@argv) = $self->db_settings($track);
  my $key             = Dumper($adaptor,@argv);
  return $DB{$key}    if exists $DB{$key};

  $DB{$key} = eval {$adaptor->new(@argv)} or warn $@;
  $self->fatal_error("Could not open database: ",pre("$@")) unless $DB{$key};

  if (my $refclass = $self->setting('reference class')) {
    eval {$DB{$key}->default_class($refclass)};
  }

  $DB{$key}->strict_bounds_checking(1) if $DB{$key}->can('strict_bounds_checking');
  $DB{$key}->absolute(1)               if $DB{$key}->can('absolute');

  $DB{$key};
}

# this is an aggregator-aware way of retrieving all the named types
sub _all_types {
  my $self  = shift;
  my $db    = shift;
  return $self->{_all_types} if exists $self->{_all_types}; # memoize
  my %types = map {$_=>1} (
			   (map {$_->get_method}        eval {$db->aggregators}),
			   (map {$self->label2type($_)} $self->labels)
			   );
  return $self->{_all_types} = \%types;
}

=head2 generate_image

  ($url,$path) = generate_image($gd);

Given a GD::Image object, this method calls its png() or gif() methods
(depending on GD version), stores the output into the temporary
directory given by the "tmpimages" option in the configuration file,
and returns a two element list consisting of the URL to the image and
the physical path of the image.

=cut

sub generate_image {
  my $self   = shift;
  my $image  = shift;

  my $extension = $image->can('png') ? 'png' : 'gif';
  my $data      = $image->can('png') ? $image->png : $image->gif;
  my $signature = md5_hex($data);

  # untaint signature for use in open
  $signature =~ /^([0-9A-Fa-f]+)$/g or return;
  $signature = $1;

  my ($uri,$path) = $self->globals->tmpdir($self->name.'/img');
  my $url         = sprintf("%s/%s.%s",$uri,$signature,$extension);
  my $imagefile   = sprintf("%s/%s.%s",$path,$signature,$extension);
  open (my $f,'>',$imagefile) || die("Can't open image file $imagefile for writing: $!\n");
  binmode($f);
  print $f $data;
  close $f;
  return $url;
}

1;

