package Bio::Graphics::Browser2::DataSource;

use strict;
use warnings;
use base 'Bio::Graphics::Browser2::AuthorizedFeatureFile';

use Bio::Graphics::Browser2::Shellwords;
use Bio::Graphics::Browser2::Util 'modperl_request';
use Bio::Graphics::Browser2::DataBase;
use File::Basename 'dirname';
use File::Path 'mkpath';
use File::Spec;
use Data::Dumper 'Dumper';
use Digest::MD5 'md5_hex';
use Carp 'croak';
use CGI 'pre';
use Storable 'lock_store','lock_retrieve';

my %CONFIG_CACHE; # cache parsed config files
my %DB_SETTINGS;  # cache database settings
my %LOADED_GLYPHS;
my $SQLITE_FIXED;

BEGIN {
    if( $ENV{MOD_PERL} &&
	exists $ENV{MOD_PERL_API_VERSION} &&
	$ENV{MOD_PERL_API_VERSION} >= 2) {
	require Apache2::SubRequest;
	require Apache2::RequestUtil;
	require Apache2::ServerUtil;
    }
}

=head1 SYNOPSIS

=head1 DESCRIPTION

=head2 METHODS

=over 4

=cut

sub new {
  my $class            = shift;
  my $config_file_path = shift;
  my ($name,$description,$globals) = @_;

  # we expire what's in the config file path if the global
  # modification time of the path has changed

  my $cache_age   = time() - ($CONFIG_CACHE{$config_file_path}{ctime}||0);

  # this code caches the config info so that we don't need to 
  # reparse in persistent (e.g. modperl) environment
  my $mtime            = $class->file_mtime($config_file_path);
  if (exists $CONFIG_CACHE{$config_file_path}{mtime}
      && $CONFIG_CACHE{$config_file_path}{mtime} >= $mtime) {
      my $object = $CONFIG_CACHE{$config_file_path}{object};
      $object->clear_cached_dbids;
      $object->clear_usertracks;
      return $object;
  }

  my @args = (-file=>$config_file_path,-safe=>1);
  my $self = $class->can('new_from_cache') && !$ENV{GBROWSE_NOCACHE} && ($config_file_path !~ /\|$/)
             ? $class->new_from_cache(@args)
	     : $class->_new(@args);

  $self->name($name);
  $self->description($description);
  $self->globals($globals);
  $self->dir(dirname($config_file_path));
  $self->config_file($config_file_path);
  $self->add_scale_tracks();
  $self->precompile_glyphs;

  # this generates the invert_types data structure which will then get cached to disk
  $self->type2label('foo',0,'bar');

  $CONFIG_CACHE{$config_file_path}{object} = $self;
  $CONFIG_CACHE{$config_file_path}{mtime}  = $mtime;
  $CONFIG_CACHE{$config_file_path}{ctime}  = time();
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

sub config_file {
  my $self = shift;
  my $d    = $self->{config_file};
  $self->{config_file} = shift if @_;
  $d;
}

sub add_conf_files {
    my $self        = shift;
    my $expression  = shift;
    while (my $conf = glob($expression)) {
	$self->parse_file($conf);
    }
}

sub globals {
  my $self = shift;
  my $d    = $self->{globals};
  $self->{globals} = shift if @_;
  $d;
}

sub clear_cached_dbids {
    my $self = shift;
    delete $self->{feature2dbid};
}

sub precompile_glyphs {
    my $self = shift;
    for my $l ($self->labels) {
	my $glyph = $self->setting($l=>'glyph');
	next unless $glyph;
	next if ref($glyph) eq 'CODE';
	next if $LOADED_GLYPHS{$glyph}++;
	eval "use Bio::Graphics::Glyph::$glyph" unless
	    "Bio::Graphics::Glyph\:\:$glyph"->can('new');
    }
}

sub clear_cached_config {
    my $self             = shift;
    delete $CONFIG_CACHE{$self->config_file};
}

=head2 userdata()

  $path = $source->userdata(@path_components)

  Returns a path to somewhere in the tmp file system for the 
  indicated userdata.

=cut

sub userdata {
    my $self = shift;
    my @path = @_;
    my $globals = $self->globals;
    return $globals->user_dir($self->name,@path);
}

sub admindata {
    my $self = shift;
    my @path = @_;
    my $globals = $self->globals;
    return $self->userdata(@path) unless $globals->admin_dbs;
    return $globals->admin_dir($self->name,@path);
}

sub taxon_id {
    my $self = shift;
    my $meta = $self->metadata or return;
    return $meta->{taxid};
}

sub build_id {
    my $self = shift;
    my $meta = $self->metadata or return;
    my $authority = $meta->{authority}           or return;
    my $version   = $meta->{coordinates_version} or return;
    return "$authority$version";
}

sub species {
    my $self = shift;
    my $meta = $self->metadata or return;
    return $meta->{species};
}

=head2 global_setting()

  $setting = $source->global_setting('option')

Like code_setting() except that it is only for 'general' options. If the
option is not found in the datasource config file, then looks in the
global file.

=cut

sub global_setting {
  my $self   = shift;
  my $option = shift;
  my $value  = $self->code_setting(general=>$option);
  return $value if defined $value;
  my $globals = $self->globals or return;
  return $globals->code_setting(general=>$option);
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
    return $self->globals->time2sec($time);
}

sub cache_time {
    my $self = shift;
    if (@_) {
        $self->{cache_time} = shift;
    }
    return $self->{cache_time} if exists $self->{cache_time};
    my $globals = $self->globals;
    my $ct = $globals->time2sec($globals->cache_time);
    return $self->{cache_time} = $ct;
}

# this method is for compatibility with some plugins
sub config {
  my $self = shift;
  return $self;
}

sub must_authenticate {
    my $self = shift;
    my $restrict = $self->global_setting('restrict') ||
	           $self->globals->data_source_restrict($self->name)
		   or return;
    return $restrict =~ /require\s+(valid-user|user|group)/;
}

sub auth_plugin { shift->globals->auth_plugin }

sub details_multiplier {
    my $self  = shift;
    my $state = shift;

    my $value = $self->global_setting('details multiplier') || 1;
    $value = 1  if ($value < 1);  #lower limit 
    $value = 25 if ($value > 25); #set upper limit for performance reasons (prevent massive image files)
    
    return $value unless $state;
    foreach (qw(seg_min seg_max view_start view_stop)) {
	return $value unless defined $state->{$_};
    }

    my $max_length     = $state->{seg_max}   - $state->{seg_min};
    my $request_length = $state->{view_stop} - $state->{view_start};
    if (($max_length > 0) && ($request_length > 0) && (($request_length * $value) > $max_length)) {
	return $max_length / $request_length; #limit details multiplier so that region does not go out of bounds
    }

    return $value;
}

sub unit_label {
  my $self  = shift;
  my $value = shift || 0;

  my $unit     = $self->setting('units')        || 'bp';
  my $divider  = $self->setting('unit_divider') || 1;
  $value /= $divider;
  my $abs = abs($value);

  my $label;
  $label = $unit =~ /^[kcM]/ ? sprintf("%.4g %s",$value,$unit)
         : $abs >= 1e9  ? sprintf("%.4g G%s",$value/1e9,$unit)
         : $abs >= 1e6  ? sprintf("%.4g M%s",$value/1e6,$unit)
         : $abs >= 1e3  ? sprintf("%.4g k%s",$value/1e3,$unit)
	 : $abs >= 1    ? sprintf("%.4g %s", $value,    $unit)
	 : $abs == 0    ? sprintf("%.4g %s", $value,    $unit)
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

sub too_many_landmarks { shift->global_setting('too many landmarks') || 100 }

sub plugins          { shellwords(shift->global_setting('plugins'))      }

sub remote_renderer {
    my $self  = shift;
    my $label = shift;
    my $url   = $self->fallback_setting($label => 'remote renderer');
    return $url if defined $url;
    return $self->global_setting('remote renderer');
}

sub labels {
  my $self   = shift;

  # filter out all configured types that correspond to the overview, overview details
  # plugins, or other name:value types
  my @labels =  grep {
    !( $_ eq 'TRACK DEFAULTS'                         # general track config
       || $_ eq 'TOOLTIPS'                            # ajax balloon config
       || /SELECT MENU/                               # rubberband selection menu config
       || /:(\d+|plugin|DETAILS|details|database)$/)  # plugin, etc config
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
  grep { ($_ eq 'plugin' || m!plugin:!) && $self->authorized($_) } $self->configured_types;
}

sub label2type {
  my ($self,$label,$length) = @_;
  my $l = $self->semantic_label($label,$length);
  return shellwords($self->setting($l,'feature')||$self->setting($label,'feature')||'');
}

sub track_listing_class {
    my $self = shift;
    my $style    =  lc($self->global_setting('track listing style') || 'categories');
    my $subclass =   $style eq 'categories' ? 'Categories'
	           : $style eq 'facets'     ? 'Facets'
		   : die "invalid track listing style '$style'";
    return 'Bio::Graphics::Browser2::Render::HTML::TrackListing::'.$subclass;
}

sub seqid_prefix { shift->fallback_setting(general=>'seqid_prefix') }

sub default_style {
  my $self = shift;
  return $self->SUPER::style('TRACK DEFAULTS');
}

sub summary_style {
  my $self = shift;
  my $type = shift;
  $type   .= ":summary";

  local $self->{config} = $self->{_user_tracks}{config}
      if exists $self->{_user_tracks}{config}{$type};

  my $config  = $self->{config}  or return;
  my $hashref = $config->{$type};
  unless ($hashref) {
    $hashref = $config->{$type} or return;
  }
  return map {("-$_" => $hashref->{$_})} keys %$hashref;
}

sub style {
  my ($self,$label,$length) = @_;
  my $l = $self->semantic_label($label,$length);
  return $l eq $label ? $self->user_style($l) 
                      : ($self->user_style($label),$self->user_style($l));
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
      map { my ($option,undef,$lang) = 
		/^(-[^:]+)(:(\w+))?$/; [$_ => $option, $priority{$lang||''}||99] }
	keys %options;
  %lang_options;
}

# return true if we should show a coverage summary for this
# track at the current length
sub show_summary {
    my $self = shift;
    my ($label,$length,$settings) = @_;

    $settings ||= {};
    return 0 if defined $settings->{features}{$label}{summary_mode_len} &&
	!$settings->{features}{$label}{summary_mode_len};
    my $c  = $settings->{features}{$label}{summary_mode_len}
          || $self->semantic_fallback_setting($label=>'show summary',$length);
    my $g  = $self->semantic_fallback_setting($label=>'glyph',$length);
    my $class = 'Bio::Graphics::Glyph::'.$g;
    eval "require $class" unless $class->can('new');
    return 0 if    $class->isa('Bio::Graphics::Glyph::xyplot')
	        or $class->isa('Bio::Graphics::Glyph::minmax');
    return 0 if $self->semantic_fallback_setting($label=>'global feature',$length);
    return 0 unless $c;

    my $section =  $self->get_section_from_label($label) || 'detail';
    $length /= $self->details_multiplier if $section eq 'detail';

    $c =~ s/_//g;  
    return 0 unless $c <= $length;
    my $db = $self->open_database($label,$length) or return;
    return 0 unless $db->can('feature_summary');
    return 1;
}

sub can_summarize {
   my $self = shift;
   my $label = shift;
   my $g  = $self->fallback_setting($label=>'glyph');
   return if $g =~ /wiggle|xyplot|density/;  # don't summarize wiggles or xyplots
   my $db = $self->open_database($label) or return;
   return unless $db->can('feature_summary');
}

sub clear_usertracks {
    my $self = shift;
    delete $self->{_user_tracks};
}

sub usertrack_labels {
    my $self = shift;
    return keys %{$self->{_user_tracks}{config}};
}

sub is_usertrack {
    my $self  = shift;
    my $label = shift;
    return exists $self->{_user_tracks}{config}{$label};
}

sub is_remotetrack {
    my $self  = shift;
    my $label = shift;
    (my $base = $label) =~ s/:\w+$//;
    return exists $self->{config}{$base}{'remote feature'} 
        || exists $self->{config}{$label}{'remote feature'};
}

sub category_open {
    my $self = shift;
    my $categories = $self->setting('category state') or return {};
    my %settings   = shellwords($categories);
    my %c;
    while (my ($key,$value) = each %settings) {
	$key  .= "_section" unless $key =~ /_section$/;
	$value = 1 if $value eq 'open';
	$value = 0 if $value eq 'closed';
	$c{$key} = $value;
    }
    return \%c;
}

sub category_default {
    my $self = shift;
    my $open = $self->setting('category default state') || 'open';
    return $open eq 'open' ? 1 : 0;
}

sub user_style {
    my $self = shift;
    my $type = shift;
    local $self->{config} = $self->{_user_tracks}{config}
      if exists $self->{_user_tracks}{config}{$type};
    return $self->SUPER::style($type);
}

# like setting, but falls back to 'track defaults' and then to 'general'
sub fallback_setting {
  my $self = shift;
  my ($label,$option,@rest) = @_;
  my $setting = $self->SUPER::setting($label,$option,@rest);
  return $setting if defined $setting;
  $setting = $self->SUPER::setting('TRACK DEFAULTS',$option,@rest);
  return $setting if defined $setting;
  $setting = $self->SUPER::setting('general',$option,@rest);
  return $setting;
}

sub plugin_setting {
  my $self           = shift;
  my $caller_package = caller();
  my ($last_name)    = $caller_package =~ /(\w+)$/;
  my $option_name    = "${last_name}:plugin";
  return $self->label_options($option_name) unless @_;
  return $self->setting($option_name => @_);
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
  my $val    = $self->code_setting($slabel => $option) if defined $slabel;

  return $val if defined $val;
  return $self->code_setting($label => $option);
}

sub semantic_label {
  my ($self,$label,$length) = @_;
  return $label unless defined $length && $length > 0;

  # adjust for details_mult of we are on a 'details' label
  my $section =  $self->get_section_from_label($label) || 'detail';
  $length    /= $self->details_multiplier if $section eq 'detail';

  # look for:
  # 1. a section like "Gene:100000" where the cutoff is <= the length of the segment
  #    under display.
  # 2. a section like "Gene" which has no cutoff to use.
  if (my @lowres = map {[split ':']}
      grep {/^$label:(\d+)/ && $1 <= $length}
      $self->configured_types)
    {
      ($label) = map {join ':',@$_} sort {$b->[1] <=> $a->[1]} @lowres;
    }
  $label
}

sub semantic_fallback_setting {
    my $self = shift;
    my ($label,$option,$length) = @_;
    my $setting = $self->semantic_setting($label,$option,$length);
    return $setting if defined $setting;
    return $self->fallback_setting($label,$option);
}

sub button_url {
    my $self = shift;
    my $globals = $self->globals;
    my $path    = $self->global_setting('buttons');
    return $globals->resolve_path($path,'url');
}

=head2 $section_setting = $data_source->section_setting($section_name)

Returns "open" "closed" or "off" for the named section. Named sections are:

 instructions
 search
 overview
 details
 tracks
 display
 upload_tracks

=cut

sub section_setting {
  my $self = shift;
  my $section = shift;
  my $config_setting = "\L$section\E section";
  my $s = $self->global_setting($config_setting);
  return 'open' unless defined $s;
  return $s;
}

sub show_section {  # one of instructions, upload_tracks, search, overview, region, detail, tracks, or display_settings
    my $self    = shift;
    my $setting = $self->section_setting(@_);
    return $setting eq 'hide' || $setting eq 'off' ? 0 : 1;
}

sub unit_divider {
    my $self = shift;
    return $self->global_setting('unit_divider') || 1;    
}

sub get_ranges {
  my $self      = shift;
  my $divisor   = $self->unit_divider;
  my $rangestr  = $self->global_setting('zoom levels')  || '100 1000 10000 100000 1000000 10000000';
  if ($divisor == 1 ) {
    return split /\s+/,$rangestr;
  } else {
    return map {$_ * $divisor} split /\s+/,$rangestr;
  }
}

# override inherited in order to be case insensitive
# and to account for semantic zooming
sub type2label {
  my $self  = shift;
  my ($type,$length,$dbid) = @_;
  $dbid   ||= '';
  $type   ||= '';
  $length ||= 0;
  $type = lc $type;
  $dbid =~ s/:database//;

  if (exists $self->{_type2label}{$type,$length,$dbid}) {
      my @labels = @{$self->{_type2label}{$type,$length,$dbid}};
      return wantarray ? @labels : $labels[0];
  }

  my %labels;
  my $main_inverted = $self->invert_types($self->{config});
  my $user_inverted = $self->invert_types($self->{_user_tracks}{config});

  for my $i ($main_inverted,$user_inverted) {
      my @lengths = grep {$length >= $_} keys %{$i->{$type}{$dbid}};
      $labels{$_}++ foreach map {keys %{$i->{$type}{$dbid}{$_}}} @lengths;
  }
  my @labels = keys %labels;
  $self->{_type2label}{$type,$length,$dbid} = \@labels; #cache in memory
  return wantarray ? @labels : $labels[0];
}

# override inherited in order to allow for semantic zooming
sub feature2label {
  my $self = shift;
  my ($feature,$length) = @_;
  my $type  = eval {$feature->type}
    || eval{$feature->source_tag} || eval{$feature->primary_tag} or return;
  my $dbid = eval{$feature->gbrowse_dbid};
  
  (my $basetype = $type) =~ s/:.+$//;
  my %label;

  $label{$_}++ foreach $self->type2label($type,$length,$dbid);
  $label{$_}++ foreach $self->type2label($basetype,$length,$dbid);

  my @label = keys %label;
  wantarray ? @label : $label[0];
}

sub invert_types {
    my $self   = shift;
    my $config = shift;
    return unless $config;

    my $keys         = md5_hex(keys %$config);

    # check in-memory cache
    if (exists $self->{_inverted}{$keys}) {
	return $self->{_inverted}{$keys};
    }

    # check for a valid cache file
    (my $cache_name     = $self->config_file) =~ s!/!_!g;
    my $master_cache = $self->cachefile($cache_name);  # inherited
    $master_cache   or die "no bio::graphics cache file found at $master_cache? Shouldn't happen..";

    my $inv_path     = $master_cache . ".${keys}.inverted";
    if (-e $inv_path && -M $master_cache >= -M $inv_path) {
	return $self->{_inverted}{$keys} = lock_retrieve($inv_path);
    }

    my $multiplier = $self->global_setting('details multiplier') || 1;

    my %inverted;
    for my $label (sort keys %{$config}) {
	my $length = 0;
	if ($label =~ /^(.+):(\d+)$/) {
	    $label  = $1;
	    $length = $2;
	}

	my $section =  $self->get_section_from_label($label) || 'detail';
	$length    *= $multiplier if $section eq 'detail';

	my $feature = $self->semantic_setting($label => 'feature',$length) or next;
	my ($dbid)  = $self->db_settings($label      => $length) or next;
	$dbid =~ s/:database$//;
	foreach (shellwords($feature||'')) {
	    $inverted{lc $_}{$dbid}{$length}{$label}++;
	}
    }
    lock_store(\%inverted,$inv_path);
    return  $self->{_inverted}{$keys} = \%inverted;
}

sub default_labels {
  my $self = shift;
  my $defaults  = $self->setting('general'=>'default tracks');
  $defaults   ||= $self->setting('general'=>'default features'); # backward compatibility
  return $self->scale_tracks,shellwords($defaults||'');
}

sub metadata {
    my $self = shift;
    return $self->{metadata} if exists $self->{metadata};

    my $metadata = $self->fallback_setting(general => 'metadata');
    return unless $metadata;

    my %a = $metadata =~ m/-(\w+)\s+([^-].*?(?= -[a-z]|$))/g;

    my %metadata;
    for (keys %a) { 
	$a{$_} =~ s/\s+$// ;
	$metadata{lc $_} = $a{$_};
    }; # trim
    
    return $self->{metadata} = \%metadata;
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
	    key            => '',
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

sub make_link {
  croak "Do not call make_link() on the DataSource. Call it on the Render object";
}

=item $db = $dsn->databases

Return all named databases from [name:database] tracks.

=cut

sub databases {
    my $self = shift;
    my @dbs  = map {s/:database//; $_ } grep {/:database$/} $self->configured_types;
    return @dbs;
}

=item ($adaptor,@argv) = $dsn->db2args('databasename')

Given a database named by ['databasename':database], return its
adaptor and arguments.

=cut

sub db2args {
    my $self   = shift;
    my $dbname = shift;
    return $self->db_settings("$dbname:database");
}

=item ($dbid,$adaptor,@argv) = $dsn->db_settings('track_label')

Return the adaptor and arguments suitable for the database identified
by the given track label. If no track label is given then the
"general" default database is used.

=cut

# get the db settings for a track or from [general]
sub db_settings {
  my $self  = shift;
  my $track = shift;
  my $length= shift;

  $track ||= 'general';

  if ($track =~ /(.+):(\d+)$/) {  # in the case that we get called with foo:499
      $track  = $1;
      $length = $2;
  }

  # caching to avoid calling setting() too many times
  my $semantic_label = $self->semantic_label($track,$length);

  return @{$DB_SETTINGS{$self,$semantic_label}} if defined $DB_SETTINGS{$self,$semantic_label};

  my $symbolic_db_name;

  if ($track =~ /:database$/) {
      $symbolic_db_name = $track
  } elsif (my $d  = $self->semantic_fallback_setting($track => 'database', $length)) {
      $symbolic_db_name = "$d:database";
  } elsif ($self->semantic_setting($track=>'db_adaptor',$length)) {
      $symbolic_db_name = $track;
  } elsif ($self->semantic_fallback_setting($track => 'db_adaptor', $length)) {
      $symbolic_db_name = 'general';
  }

  if (defined $DB_SETTINGS{$self,$symbolic_db_name}) {
      return @{$DB_SETTINGS{$self,$semantic_label} ||= $DB_SETTINGS{$self,$symbolic_db_name}};
  }

  my $adaptor = $self->semantic_setting($symbolic_db_name => 'db_adaptor', $length);
  unless ($adaptor) {
      warn "Unknown database defined for $track";
      return;
  }
  eval "require $adaptor; 1" or die $@;

  my $args    = $self->semantic_fallback_setting($symbolic_db_name => 'db_args', $length);
  my @argv    = ref $args eq 'CODE'
        ? $args->()
	: shellwords($args||'');

  # Do environment substitutions in the args. Assume that the environment is safe.
  foreach (@argv) {
      s/\$ENV{(\w+)}/$ENV{$1}||''/ge;
      s/\$HTDOCS/Bio::Graphics::Browser2->htdocs_base/ge;
      s/\$DB/Bio::Graphics::Browser2->db_base/ge;
      s/\$CONF/Bio::Graphics::Browser2->config_base/ge;
      s/\$ROOT/Bio::Graphics::Browser2->url_base/ge;
  }

  if (defined (my $a = 
	       $self->semantic_setting($symbolic_db_name => 'aggregators',$length))) {
    my @aggregators = shellwords($a||'');
    push @argv,(-aggregator => \@aggregators);
  }
  
  # uniquify dbids
  my $key    = Dumper($adaptor,@argv);
  $self->{arg2dbid}{$key} ||= $symbolic_db_name;

  my @result = ($self->{arg2dbid}{$key},$adaptor,@argv);

  # cache settings
  $DB_SETTINGS{$self,$symbolic_db_name}   ||= \@result;
  $DB_SETTINGS{$self,$semantic_label  }   ||= \@result;

  return @result;
}

=item $db = $dsn->open_database('track')

Return the database handle specified by the given track label or
'general' if not given. The databases are cached and so it is ok to
call repeatedly.

=cut

sub open_database {
  my $self  = shift;
  my $track  = shift;
  my $length = shift;

  $track  ||= 'general';

  my ($dbid,$adaptor,@argv) = $self->db_settings($track,$length);
  my $db                    = Bio::Graphics::Browser2::DataBase->open_database($adaptor,@argv);
  $self->fix_sqlite if $adaptor eq 'Bio::DB::SeqFeature::Store' && "@argv" =~ /SQLite/;  # work around broken bioperl
  
  # do a little extra stuff the first time we see a new database
  unless ($self->{databases_seen}{$db}++) {
      my $refclass = $self->setting('reference class');
      $db->default_class($refclass) if $refclass && $db->can('default_class');
      $db->strict_bounds_checking(1) if $db->can('strict_bounds_checking');
      $db->absolute(1)               if $db->can('absolute');

      unless ($track eq 'general') {
	  my $default = $self->open_database();  # I hope we don't get into a loop here
	  $db->dna_accessor($default) if $default ne $db && $db->can('dna_accessor');
      }

  }

  # remember mapping of this database to this track
  $self->{db2track}{$db}{$dbid}++;

  return $db;
}

sub default_dbid {
    my $self = shift;
    return $self->db2id($self->open_database);
}


sub search_options {
    my $self = shift;
    my $dbid = shift;
    return $self->setting($dbid => 'search options')
	|| $self->setting($dbid => 'search_options')
	|| 'default';
}

sub exclude_types {
    my $self = shift;
    my $dbid = shift;
    return shellwords($self->setting($dbid => 'exclude types')||'');
}

=item @ids   = $dsn->db2id($db)

=item $dbid  = $dsn->db2id($db)

Given a database handle, return all dbids that correspond to that
database. In a scalar context, returns just the first dbid that uses
it. It is less confusing to call in a scalar context.

=cut

sub db2id {
    my $self = shift;
    my $db   = shift;
    my @tracks = keys %{$self->{db2track}{$db}} or return;
    my (@symbolic,@general,@rest);
    for (@tracks) {
	if (/:database$/i) {
	    push @symbolic,$_;
	} elsif (lc $_ eq 'general') {
	    push @general,$_;
	} else {
	    push @rest,$_;
	}
    }
    @tracks = (@symbolic,@general,@rest); # triage
    return wantarray ? @tracks : $tracks[0];
}

=item @ids   = $dsn->dbs

Return the names of all the sections that define dbs in the datasource: both track sections
that define dbargs and named database sections. Note that we do not
uniquify the case in which the same adaptor and dbargs are defined twice in two different
sections.

=cut

sub dbs {
    my $self = shift;
    my @labels     = ('general',$self->configured_types);
    my %named      = map {$_=>1} grep {/:database/} @labels;
    my @anonymous  = grep {!$named{$_} && $self->setting($_=>'db_adaptor')} @labels;
    return (keys %named,@anonymous);
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

=item $dsn->clear_cache

Empty out our cache of database settings and fetch anew from config file

=cut

sub clear_cache {
    my $self = shift;
    %DB_SETTINGS = ();
}

=head2 generate_image

  ($url,$path) = generate_image($gd);

Given a GD::Image object, this method calls its png() or gif() methods
(depending on GD version), stores the output into the temporary
"images" subdirectory of the directory given by the "tmp_base" option
in the configuration file. It returns a two element list consisting of
the URL to the image and the physical path of the image.

=cut

sub generate_image {
  my $self   = shift;
  my $image  = shift;

  if ($self->global_setting('truecolor') 
      && $image->can('saveAlpha')) {
      $image->trueColor(1);
      $image->saveAlpha(1);
  }

  my $extension = $image->can('png') ? 'png' : 'gif';
  my $data      = $image->can('png') ? $image->png : $image->gif;
  my $signature = md5_hex($data);

  # untaint signature for use in open
  $signature =~ /^([0-9A-Fa-f]+)$/g or return;
  $signature = $1;

  my $self_name = $self->name;
  $self_name =~ s/\\/_/g; # Because Safari and Chrome translate backslash to forward slash
  my $path        = $self->globals->tmpimage_dir($self_name);

  my $image_url   = $self->globals->image_url;
  my $url         = sprintf("%s/%s/%s.%s",$image_url,$self_name,$signature,$extension);
  my $imagefile   = sprintf("%s/%s.%s",$path,$signature,$extension);
  open (my $f,'>',$imagefile) 
      || die("Can't open image file $imagefile for writing: $!\n");
  binmode($f);
  print $f $data;
  close $f;
  return $url;
}

=head2 $source->add_dbid_to_feature($feature,$dbid_hashref)

This adds a new method called gbrowse_dbid() to a feature. Do not call
it if the method is already in the feature's class. The hashref should
be populated by feature memory locations (overload::StrVal($feature))
as keys and database symbolic IDs as values.

=cut

sub add_dbid_to_feature {
    my $self           = shift;
    my ($feature,$dbid) = @_;
    return unless $feature;

    no strict 'refs';

    if ($feature->isa('HASH')) {
	$feature->{__gbrowse_dbid} = $dbid;
	my $class = ref $feature;
	return if $class->can('gbrowse_dbid');
	my $method = sub {
	    my $f = shift;
	    return $f->{__gbrowse_dbid};
	  };
	*{"${class}::gbrowse_dbid"} = $method;
    }

    else {
	$self->{feature2dbid}{overload::StrVal($feature)} = $dbid;
	my $class = ref $feature;
	return if $class->can('gbrowse_dbid');
	my $method = sub { my $f = shift;
			   return $self->{feature2dbid}{overload::StrVal($f)}
	  };
	*{"${class}::gbrowse_dbid"} = $method;
    }
}


=head2 @labels = $source->data_source_to_label(@data_sources)

Search through all stanzas for those with a matching "data source"
option. Data sources look like this:

 [stanzaLabel1]
 data source = FlyBase

 [stanzaLabel2]
 data source = FlyBase

Now searching for $source->data_source_to_label('FlyBase') will return
"stanzaLabel1" and "stanzaLabel2" along with others that match. A
track may have several data sources, separated by spaces.

=cut


sub data_source_to_label {
    my $self = shift;
    return $self->_secondary_key_to_label('data source',@_);
}

=head2 @labels = $source->track_source_to_label(@track_sources)

Search through all stanzas for those with a matching "track source"
option. Track sources look like this:

 [stanzaLabel]
 track source = UCSC EBI NCBI

Now searching for $source->track_source_to_label('UCSC','EBI') will
return "stanzaLabel" along with others that match. A track may have
several space-delimited track sources.

=cut
sub track_source_to_label {
    my $self = shift;
    return $self->_secondary_key_to_label('track source',@_);
}

sub _secondary_key_to_label {
    my $self   = shift;
    my $field  = shift;
    my $index  = $self->{'.secondary_key'};
    if (!exists $index->{$field}) {
	for my $label ($self->labels) {
	    my @sources = shellwords $self->setting($label=>$field) or next;
	    push @{$index->{$field}{lc $_}},$label foreach @sources;
	}
    }

    my %seenit;
    return grep {!$seenit{$_}++} 
           map  {exists $index->{$field}{lc $_} ? @{$index->{$field}{lc $_}} : () } @_;
}


######### experimental code to manage user-specific tracks ##########
sub add_user_type {
    my $self = shift;
    my ($type,$type_configuration) = @_;

    my $cc = ($type =~ /^(general|default)$/i) ? 'general' : $type;  # normalize

    my $base = $self->{_user_tracks} ||= {};
    
    push @{$base->{types}},$cc 
	unless $cc eq 'general' or $base->{config}{$cc};

    if (defined $type_configuration) {
	for my $tag (keys %$type_configuration) {
	    $base->{config}{$cc}{lc $tag} = $type_configuration->{$tag};
	}
    }
}

sub configured_types {
    my $self  = shift;
    my @types       = $self->SUPER::configured_types;
    my @user_types  = @{$self->{_user_tracks}{types}}
         if exists $self->{_user_tracks}{types};
    return (@types,@user_types);
}

sub usertype2label {
    my $self = shift;
    my ($type,$length) = @_;
    return unless $self->{_user_tracks}{types};
    my @userlabels = @{$self->{_user_tracks}{types}} or return;

    my %labels;
    for my $label (@userlabels) {
	my ($label_base,$minlength) = $label =~ /(.+)(?::(\d+))?/;
	$minlength ||= 0;
	next if defined $length && $minlength > $length;
	my @types = shellwords($self->{_user_tracks}{config}{$label}{feature});
	@types    = $label unless @types;
	next unless grep {/$type/i} @types;
	$labels{$label}++;
    }
    return keys %labels;
}

sub _setting {
    my $self = shift;
    my $base = $self->{_user_tracks};
    if ($base && defined $_[0] && exists $base->{config}{$_[0]}) {
	return $base->{config}{$_[0]}{$_[1]}  if @_ == 2;
	return keys %{$base->{config}{$_[0]}} if @_ == 1;
    }
    return $self->SUPER::_setting(@_);
}

sub code_setting {
    my $self    = shift;
    my $base = $self->{_user_tracks};
    if ($base && exists $base->{config}{$_[0]||''}) {
	return $self->_setting(@_);  # don't allow code_setting on user tracks
    } else {
 	return $self->SUPER::code_setting(@_);
    }
}

sub parse_user_file {
    my $self = shift;

    $self->{_user_tracks}{types}  ||= [];
    $self->{_user_tracks}{config} ||= {};

    local $self->{types}  = $self->{_user_tracks}{types};
    local $self->{config} = $self->{_user_tracks}{config};
    $self->SUPER::parse_file(@_);
}

sub parse_user_fh {
    my $self = shift;
    local $self->{types}  = $self->{_user_tracks}{types};
    local $self->{config} = $self->{_user_tracks}{config};
    $self->SUPER::parse_fh(@_);
}


sub subtrack_scan_list {
    my $self  = shift;
    my $label = shift;
    my $stt   = Bio::Graphics::Browser2::Render->create_subtrack_manager($label,$self,{}) or return;
    my @ids   = keys %{$stt->elements};
    return \@ids;
}

sub fix_sqlite {
    return if $SQLITE_FIXED++;
    no warnings;
    *Bio::DB::SeqFeature::Store::DBI::SQLite::_has_spatial_index = sub { return };
}

sub get_section_from_label {
    my $self   = shift;
    my $label  = shift;

    return 'detail' if ref $label;  # work around a DAS bug

    if ($label eq 'overview' || $label =~ /:overview$/){
        return 'overview';
    }
    elsif ($label eq 'region' || $label =~  /:region$/){
        return 'region';
    }
    return 'detail'
}

=head2 $boolean = $source->use_inline_imagemap($label=>$length)

Given a track label and length (for semantic zooming) return true
if we should generate an inline clickable imagemap vs one in which
the actions are generated by Ajax callbacks

=cut

sub use_inline_imagemap {
    my $self = shift;
    my ($label,$length) = @_;
    my $inline = $self->semantic_fallback_setting($label=>'inline imagemaps',$length) 
	       ||$self->semantic_fallback_setting($label=>'inline imagemap', $length);
    return $inline if defined $inline;
    return 1 if not (Bio::Graphics::Browser2::Render->fcgi_request()
		     ||
		     $ENV{MOD_PERL_API_VERSION}
	);
    my $db = $self->open_database($label,$length) or return 1;
    return !$db->can('get_feature_by_id');
}

1;

