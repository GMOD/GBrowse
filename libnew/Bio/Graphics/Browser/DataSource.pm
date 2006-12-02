package Bio::Graphics::Browser::DataSource;

use strict;
use warnings;
use base 'Bio::Graphics::FeatureFile';
use Text::ParseWords 'shellwords';
use Carp 'croak';
use CGI '';
use Socket;  # for inet_aton() call

my %CONFIG_CACHE;

sub new {
  my $class            = shift;
  my $config_file_path = shift;
  my ($name,$description) = @_;

  # this code caches the config info so that we don't need to reparse in persistent (e.g. modperl) environment
  my $mtime            = (stat($config_file_path))[9];
  if (exists $CONFIG_CACHE{$config_file_path}
      && $CONFIG_CACHE{$config_file_path}{mtime} >= $mtime) {
    return $CONFIG_CACHE{$config_file_path}{object};
  }

  my $self = $class->SUPER::new(-file=>$config_file_path);
  $self->name($name);
  $self->description($description);
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

sub overview_bgcolor { shift->setting(general=>'overview bgcolor')         }
sub detailed_bgcolor { shift->setting(general=>'detailed bgcolor')         }
sub key_bgcolor      { shift->setting(general=>'key bgcolor')              }
sub image_widths     { shellwords(shift->setting(general=>'image widths')) }
sub default_width    { shift->setting(general=>'default width')            }

sub head_html        { shift->setting(general=>'head')                     }
sub header_html      { shift->setting(general=>'header')                   }
sub footer_html      { shift->setting(general=>'footer')                   }
sub html1            { shift->setting(general=>'html1')                    }
sub html2            { shift->setting(general=>'html2')                    }
sub html3            { shift->setting(general=>'html3')                    }
sub html4            { shift->setting(general=>'html4')                    }
sub html5            { shift->setting(general=>'html5')                    }
sub html6            { shift->setting(general=>'html6')                    }

sub max_segment      { shift->setting(general=>'max segment')              }
sub default_segment  { shift->setting(general=>'max segment')              }

sub plugins        { shellwords(shift->setting(general=>'plugins'))      }


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

sub overview_tracks {
  my $self = shift;
  grep { ($_ eq 'overview' || /:overview$/) && $self->authorized($_) } $self->configured_types;
}

sub regionview_tracks {
  my $self = shift;
  grep { ($_ eq 'region' || /:region$/) && $self->authorized($_) } $self->configured_types;
}

sub karyotype_tracks {
  my $self = shift;
  grep { ($_ eq 'karyotype' || /:karyotype$/) && $self->authorized($_) } $self->configured_types;
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
  my @tokens = split /\s*(satisfy|order|allow from|deny from|require user|require group|require valid-user)\s+/i,$restrict;
  shift @tokens unless $tokens[0] =~ /\S/;
  my $mode    = 'allow,deny';
  my $satisfy = 'all';
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
      foreach (@values) {
	if ($_ eq 'valid-user' && defined $user) {
	  $users{$user}++;  # ensures that this user will match
	} else {
	  $users{$_}++;
	}
      }
      next;
    }
    if ($user && $directive eq 'require valid-user') {
      $users{$user}++;
    }
    if ($directive eq 'require group') {
      croak "Sorry, but gbrowse does not support the require group limit.  Use a subroutine to implement role-based authentication.";
    }
  }

  my $allow = $mode eq  'allow,deny' ? match_host(\@allow,$host,$addr) && !match_host(\@deny,$host,$addr)
                      : 'deny,allow' ? !match_host(\@deny,$host,$addr) ||  match_host(\@allow,$host,$addr)
		      : croak "$mode is not a valid authorization mode";
  return $allow unless %users;
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

sub label2type {
  my ($self,$label,$length) = @_;
  my $l = $self->semantic_label($label,$length);
  return shellwords($self->setting($l,'feature')||$self->setting($label,'feature')||'');
}

sub style {
  my ($self,$label,$length) = @_;
  my $l = $self->semantic_label($label,$length);
  return $l eq $label ? $self->SUPER::style($l) : ($self->SUPER::style($label),$self->SUPER::style($l));
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
      my ($label_base,$minlength) = $label =~ /([^:]+)(?::(\d+))?/;
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
    next if $label=~/:?(overview|region)$/;   # special case
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
  return shellwords($defaults||'');
}

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

# override make_link to allow for code references
sub make_link {
  my $self     = shift;
  my ($feature,$panel,$label,$data_source,$track)  = @_;

  if ($feature->can('url')) {
    my $link = $feature->url;
    return $link if defined $link;
  }
  return $label->make_link($feature) if $label && $label->isa('Bio::Graphics::FeatureFile');

  $panel ||= 'Bio::Graphics::Panel';
  $label ||= $self->feature2label($feature);

  # most specific -- a configuration line
  my $link     = $self->code_setting($label,'link');

  # less specific - a smart feature
  $link        = $feature->make_link if $feature->can('make_link') && !defined $link;

  # general defaults
  $link        = $self->code_setting('TRACK DEFAULTS'=>'link') unless defined $link;
  $link        = $self->code_setting(general=>'link')          unless defined $link;

  return unless $link;

  if (ref($link) eq 'CODE') {
    my $val = eval {$link->($feature,$panel,$track)};
    $self->_callback_complain($label=>'link') if $@;
    return $val;
  }
  elsif (!$link || $link eq 'AUTO') {
    my $n     = $feature->display_name;
    my $c     = $feature->seq_id;
    my $name  = CGI::escape("$n");  # workaround CGI.pm bug
    my $class = eval {CGI::escape($feature->class)}||'';
    my $ref   = CGI::escape("$c");  # workaround again
    my $start = CGI::escape($feature->start);
    my $end   = CGI::escape($feature->end);
    my $src   = CGI::escape(eval{$feature->source} || '');
    return "../../gbrowse_details/$data_source?name=$name;class=$class;ref=$ref;start=$start;end=$end";
  }
  return $self->link_pattern($link,$feature,$panel);
}

# make the title for an object on a clickable imagemap
sub make_title {
  my $self = shift;
  my ($feature,$panel,$label,$track) = @_;
  local $^W = 0;  # tired of uninitialized variable warnings

  my ($title,$key) = ('','');

 TRY: {
    if ($label && $label->isa('Bio::Graphics::FeatureFile')) {
      $key = $label->name;
      $title = $label->make_title($feature) or last TRY;
      return $title;
    }

    else {
      $label     ||= $self->feature2label($feature) or last TRY;
      $key       ||= $self->setting($label,'key') || $label;
      $key         =~ s/s$//;
      $key         = $feature->segment->dsn if $feature->isa('Bio::Das::Feature');  # for DAS sources

      my $link     = $self->code_setting($label,'title')
	|| $self->code_setting('TRACK DEFAULTS'=>'title')
	  || $self->code_setting(general=>'title');
      if (defined $link && ref($link) eq 'CODE') {
	$title       = eval {$link->($feature,$panel,$track)};
	$self->_callback_complain($label=>'title') if $@;
	return $title if defined $title;
      }
      return $self->link_pattern($link,$feature) if $link && $link ne 'AUTO';
    }
  }

  # otherwise, try it ourselves
  $title = eval {
    if ($feature->can('target') && (my $target = $feature->target)) {
      join (' ',
	    "$key:",
	    $feature->seq_id.':'.
	    $feature->start."..".$feature->end,
	    $feature->target->seq_id.':'.
	    $feature->target->start."..".$feature->target->end);
    } else {
      my ($start,$end) = ($feature->start,$feature->end);
      ($start,$end)    = ($end,$start) if $feature->strand < 0;
      join(' ',
	   "$key:",
	   $feature->can('display_name') ? $feature->display_name : $feature->info,
	   ($feature->can('seq_id')      ? $feature->seq_id : $feature->location->seq_id)
	   .":".
	   (defined $start ? $start : '?')."..".(defined $end ? $end : '?')
	  );
    }
  };
  warn $@ if $@;

  return $title;
}

sub make_link_target {
  my $self = shift;
  my ($feature,$panel,$label,$track) = @_;

  if ($feature->isa('Bio::Das::Feature')) { # new window
    my $dsn = $feature->segment->dsn;
    $dsn =~ s/^.+\///;
    return $dsn;
  }

  $label    ||= $self->feature2label($feature) or return;
  my $link_target = $self->code_setting($label,'link_target')
    || $self->code_setting('LINK DEFAULTS' => 'link_target')
    || $self->code_setting(general => 'link_target');
  $link_target = eval {$link_target->($feature,$panel,$track)} if ref($link_target) eq 'CODE';
  $self->_callback_complain($label=>'link_target') if $@;
  return $link_target;
}

sub default_style {
  my $self = shift;
  return $self->SUPER::style('TRACK DEFAULTS');
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

1;
