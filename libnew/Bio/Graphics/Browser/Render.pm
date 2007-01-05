package Bio::Graphics::Browser::Render;

use strict;
use warnings;
use Bio::Graphics::Browser::I18n;
use Bio::Graphics::Browser::PluginSet;
use Bio::Graphics::Browser::UploadSet;
use Bio::Graphics::Browser::RemoteSet;
use Text::ParseWords 'shellwords';
use CGI qw(param request_method);
use Carp 'croak';

use constant VERSION => 2.0;
use constant DEBUG   => 0;

my %DB;      # cache opened database connections
my %PLUGINS; # cache initialized plugins

sub new {
  my $class = shift;
  my ($data_source,$session) = @_;
  my $self = bless {},ref $class || $class;
  $self->data_source($data_source);
  $self->session($session);
  $self->state($session->page_settings);
  $self->set_language();
  $self;
}

sub data_source {
  my $self = shift;
  my $d = $self->{data_source};
  $self->{data_source} = shift if @_;
  $d;
}

sub session {
  my $self = shift;
  my $d = $self->{session};
  $self->{session} = shift if @_;
  $d;
}

sub state {
  my $self = shift;
  my $d = $self->{state};
  $self->{state} = shift if @_;
  $d;
}

sub uploaded_sources {
  my $self = shift;
  my $d = $self->{uploaded_sources};
  $self->{uploaded_sources} = shift if @_;
  $d;
}

sub remote_sources {
  my $self = shift;
  my $d = $self->{remote_sources};
  $self->{remote_sources} = shift if @_;
  $d;
}

sub language {
  my $self = shift;
  my $d = $self->{language};
  $self->{language} = shift if @_;
  $d;
}

sub db {
  my $self = shift;
  my $d = $self->{db};
  $self->{db} = shift if @_;
  $d;
}

sub segments {
  my $self = shift;
  my $d = $self->{segments} ||= [];
  if (@_) {
    if (ref $_[0] && ref $_[0] eq 'ARRAY') {
      $self->{segments} = shift;
    } else {
      $self->{segments} = \@_;
    }
  }
  return @$d;
}

sub plugins {
  my $self = shift;
  my $d = $self->{plugins};
  $self->{plugins} = shift if @_;
  $d;
}


###################################################################################
#
# RUN CODE HERE
#
###################################################################################
sub run {
  my $self = shift;
  $self->update_state();
  $self->init_database();
  $self->init_plugins();
  $self->init_remote_sources();
  $self->render();
  $self->clean_up();
}

sub init_database {
  my $self = shift;
  my ($adaptor,@argv) = $self->db_settings;
  my $key             = join ':',$adaptor,@argv;
  return $DB{$key}    if exists $DB{$key};

  my $state = $self->state;

  $DB{$key} = eval {$adaptor->new(@argv)} or warn $@;
  $self->fatal_error("Could not open database: ",pre("$@")) unless $DB{$key};

  if (my $refclass = $self->setting('reference class')) {
    eval {$DB{$key}->default_class($refclass)};
  }

  $DB{$key}->strict_bounds_checking(1) if $DB{$key}->can('strict_bounds_checking');
  $DB{$key}->absolute(1)               if $DB{$key}->can('absolute');

  # I don't know what this is for, but it was there in gbrowse and looks
  # like an important hack.
  eval {$DB{$key}->biosql->version($state->{version})};

  $self->db($DB{$key});
  $DB{$key};
}

sub init_plugins {
  my $self        = shift;
  my $source      = $self->data_source->name;
  my @plugin_path = shellwords($self->data_source->globals->plugin_path);

  my $plugins = $PLUGINS{$source} 
    ||= Bio::Graphics::Browser::PluginSet->new($self->data_source,$self->state,@plugin_path);
  $self->fatal_error("Could not initialize plugins") unless $plugins;
  $plugins->configure($self->db,$self->state,$self->session);
  $self->plugins($plugins);
  $plugins;
}

sub init_remote_sources {
  my $self = shift;
  my $uploaded_sources = Bio::Graphics::Browser::UploadSet->new($self->data_source,$self->state);
  my $remote_sources   = Bio::Graphics::Browser::RemoteSet->new($self->data_source,$self->state);
  $self->uploaded_sources($uploaded_sources);
  $self->remote_sources($remote_sources);
  $uploaded_sources && $remote_sources;
}

sub render {
  my $self = shift;
  croak 'Please call render() for a subclass of Bio::Graphics::Browser::Render';
}

sub clean_up {
  my $self = shift;
}

sub fatal_error {
  my $self = shift;
  my @msg  = @_;
  croak 'Please call fatal_error() for a subclass of Bio::Graphics::Browser::Render';
}


###################################################################################
#
# SETTINGS CODE HERE
#
###################################################################################

# the setting method either calls the DATA_SOURCE's global_setting or setting(), depending
# on the number of arguments used.
sub setting {
  my $self = shift;

  my $data_source = $self->data_source;

  if (@_ == 1) {
    return $data_source->global_setting(@_);
  }

  else {
    # otherwise we get the data_source-specific settings
    return $data_source->setting(@_);
  }
}

sub db_settings {
  my $self = shift;

  my $adaptor = $self->setting('db_adaptor') or die "No db_adaptor specified";
  eval "require $adaptor; 1" or die $@;

  my $args    = $self->setting('db_args');
  my @argv = ref $args eq 'CODE'
        ? $args->()
	: shellwords($args||'');

  # for compatibility with older versions of the browser, we'll hard-code some arguments
  if (my $adaptor = $self->setting('adaptor')) {
    push @argv,(-adaptor => $adaptor);
  }

  if (my $dsn = $self->setting('database')) {
    push @argv,(-dsn => $dsn);
  }

  if (my $fasta = $self->setting('fasta_files')) {
    push @argv,(-fasta=>$fasta);
  }

  if (my $user = $self->setting('user')) {
    push @argv,(-user=>$user);
  }

  if (my $pass = $self->setting('pass')) {
    push @argv,(-pass=>$pass);
  }

  if (defined (my $a = $self->setting('aggregators'))) {
    my @aggregators = shellwords($a||'');
    push @argv,(-aggregator => \@aggregators);
  }

  ($adaptor,@argv);
}

##################################################################3
#
# STATE CODE HERE
#
##################################################################3

sub update_state {
  my $self = shift;
  my $state = $self->state;
  $self->default_state if !%$state or param('reset');
  $self->update_state_from_cgi;
  $self->fetch_segments();
}

sub default_state {
  my $self  = shift;
  my $state = $self->state;
  %$state = ();
  @$state{'name','ref','start','stop','flip','version'} = ('','','','','',100);
  $state->{width}        = $self->setting('default width');
  $state->{source}       = $self->data_source->name;
  $state->{region_size}  = $self->setting('region segment');
  $state->{v}            = VERSION;
  $state->{stp}          = 1;
  $state->{ins}          = 1;
  $state->{head}         = 1;
  $state->{ks}           = 'between';
  $state->{grid}         = 1;
  $state->{sk}           = $self->setting("default varying") ? "unsorted" : "sorted";

  # if no name is specified but there is a "initial landmark" defined in the
  # config file, then we default to that.
  $state->{name} = $self->setting('initial landmark') 
    if defined $self->setting('initial landmark');

  $self->default_tracks();
}

sub default_tracks {
  my $self  = shift;
  my $state  = $self->state;
  my @labels = $self->data_source->labels;

  $state->{tracks}   = \@labels;
  warn "order = @labels" if DEBUG;
  foreach (@labels) {
    $state->{features}{$_} = {visible=>0,options=>0,limit=>0};
  }
  foreach ($self->data_source->default_labels) {
    $state->{features}{$_}{visible} = 1;
  }
}

sub update_state_from_cgi {
  my $self  = shift;
  my $state = $self->state;

  $self->update_options($state);
  if (param('revert')) {
    $self->default_tracks($state);
  }
  else {
    $self->update_tracks($state);
  }
  $self->update_coordinates($state);
  $self->update_region($state);
  $self->update_external_annotations($state);
  $self->update_section_visibility($state);
}

sub update_options {
  my $self  = shift;
  my $state = shift || $self->state;
  return unless param('width'); # not submitted

  $state->{grid} = 1 unless exists $state->{grid};  # to upgrade from older settings
  $state->{flip} = 0;  # obnoxious for this to persist

  $state->{version} ||= param('version') || '';
  do {$state->{$_} = param($_) if defined param($_) } 
    foreach qw(name source plugin stp ins head  ks sk version grid flip width);

  # Process the magic "q" parameter, which overrides everything else.
  if (my @q = param('q')) {
    delete $state->{$_} foreach qw(name ref h_feat h_region);
    $state->{q} = [map {split /[+-]/} @q];
  }

  else  {
    $state->{name} ||= '';
    $state->{name} =~ s/^\s+//; # strip leading
    $state->{name} =~ s/\s+$//; # and trailing whitespace
  }
}

sub update_tracks {
  my $self = shift;
  my $state = shift;

  if (my @selected = $self->split_labels (param('label'))) {
    $state->{features}{$_}{visible} = 0 foreach $self->data_source->labels;
    $state->{features}{$_}{visible} = 1 foreach @selected;
  }

  if (my @selected = split_labels(param('enable'))) {
    $state->{features}{$_}{visible} = 1 foreach @selected;
  }

  if (my @selected = split_labels(param('disable'))) {
    $state->{features}{$_}{visible} = 0 foreach @selected;
  }

  $self->update_track_options($state) if param('adjust_order') && !param('cancel');
}

sub update_coordinates {
  my $self  = shift;
  my $state = shift || $self->state;

  my $divider  = $self->setting('unit_divider') || 1;

  # Update coordinates.
  $state->{ref}   = param('ref');
  $state->{start} = param('start') if defined param('start') && param('start') =~ /^[\d-]+/;
  $state->{stop}  = param('stop')  if defined param('stop')  && param('stop')  =~ /^[\d-]+/;
  $state->{stop}  = param('end')   if defined param('end')   && param('end')   =~ /^[\d-]+/;

  if ( (request_method() eq 'GET' && param('ref'))
       ||
       (param('span') && $divider*$state->{stop}-$divider*$state->{start}+1 != param('span'))
       ||
       grep {/left|right|zoom|nav|regionview\.[xy]|overview\.[xy]/} param()
     )
    {
      $self->zoomnav($state);
      $state->{name} = "$state->{ref}:$state->{start}..$state->{stop}";
      param(name => $state->{name});
    }
}

sub update_region {
  my $self  = shift;
  my $state = shift || $self->state;

  if (my @features = shellwords(param('h_feat'))) {
    $state->{h_feat} = {};
    for my $hilight (@features) {
      last if $hilight eq '_clear_';
      my ($featname,$color) = split '@',$hilight;
      $state->{h_feat}{$featname} = $color || 'yellow';
    }
  }

  if (my @regions = shellwords(param('h_region'))) {
    $state->{h_region} = [];
    foreach (@regions) {
      last if $_ eq '_clear_';
      $_ = "$state->{ref}:$_" unless /^[^:]+:-?\d/; # add reference if not there
      push @{$state->{h_region}},$_;
    }
  }

  if ($self->setting('region segment')) {
    $state->{region_size} = param('region_size') if defined param('region_size');
    $state->{region_size} = $self->setting('region segment') unless defined $state->{region_size};
  }
  else {
    delete $state->{region_size};
  }
}

sub update_external_annotations {
  my $self  = shift;
  my $state = shift || $self->state;

  my @external = param('eurl') or return;

  my %external = map {$_=>1} @external;
  foreach (@external) {
    next if exists $state->{features}{$_};
    $state->{features}{$_} = {visible=>1,options=>0,limit=>0};
    push @{$state->{tracks}},$_;
  }

  # remove any URLs that aren't on the list
  foreach (keys %{$state->{features}}) {
    next unless /^(http|ftp):/;
    delete $state->{features}{$_} unless exists $external{$_};
  }
}

sub update_section_visibility {
  my $self = shift;
  my $state = shift;

  for my $div (grep {/^div_visible_/} CGI::cookie()) {
    my ($section)   = $div =~ /^div_visible_(\w+)/ or next;
    my $visibility  = CGI::cookie($div);
    $state->{section_visible}{$section} = $visibility;
  }
}

sub zoomnav {
  my $self  = shift;
  my $state = shift || $self->state;

  my $config = $self->data_source;

  return unless $state->{ref};
  my $start = $state->{start};
  my $stop  = $state->{stop};
  my $span  = $stop - $start + 1;
  my $divisor = $self->setting(general=>'unit_divider') || 1;

  warn "before adjusting, start = $start, stop = $stop, span=$span" if DEBUG;
  my $flip  = $state->{flip} ? -1 : 1;

  # get zoom parameters
  my $selected_span    = param('span');
  my ($zoom)           = grep {/^zoom (out|in) \S+/} param();
  my ($nav)            = grep {/^(left|right) \S+/}  param();
  my $overview_x       = param('overview.x');
  my $regionview_x     = param('regionview.x');
  my $regionview_size  = $state->{region_size};
  my $seg_min          = param('seg_min');
  my $seg_max          = param('seg_max');
  my $segment_length   = $seg_max - $seg_min + 1 if defined $seg_min && defined $seg_max;

  my $zoomlevel = $self->unit_to_value($1) if $zoom && $zoom =~ /((?:out|in) .+)\.[xy]/;
  my $navlevel  = $self->unit_to_value($1) if $nav  && $nav  =~ /((?:left|right) .+)/;

  if (defined $zoomlevel) {
    warn "zoom = $zoom, zoomlevel = $zoomlevel" if DEBUG;
    my $center	    = int($span / 2) + $start;
    my $range	    = int($span * (1-$zoomlevel)/2);
    $range          = 1 if $range < 1;
    ($start, $stop) = ($center - $range , $center + $range - 1);
  }

  elsif (defined $navlevel){
    $start += $flip * $navlevel;
    $stop  += $flip * $navlevel;
  }

  elsif (defined $overview_x && defined $segment_length) {
    my @overview_tracks = grep {$state->{features}{$_}{visible}} 
         $self->data_source->overview_tracks;

    my ($padl,$padr) = $self->overview_pad(\@overview_tracks);

    my $overview_width = $state->{width} * $self->overview_ratio;

    # adjust for padding in pre 1.6 versions of bioperl
    $overview_width -= ($padl+$padr) unless Bio::Graphics::Panel->can('auto_pad');

    my $click_position = $seg_min + $segment_length * ($overview_x-$padl)/$overview_width;

    $span = $config->default_segment if $span > $config->max_segment;
    $start = int($click_position - $span/2);
    $stop  = $start + $span - 1;
  }

  elsif (defined $regionview_x) {
    my $whole_start = param('seg_min');
    my $whole_stop  = param('seg_max');
    my ($regionview_start, $regionview_end) = get_regionview_seg($state,$start, $stop, $whole_start,$whole_stop);
    my @regionview_tracks = grep {$state->{features}{$_}{visible}} 
      $$config->regionview_tracks;
    my ($padl,$padr) = $self->overview_pad(\@regionview_tracks);

    my $regionview_width = ($state->{width} * $self->overview_ratio);

    # adjust for padding in pre 1.6 versions of bioperl
    $regionview_width -= ($padl+$padr) unless Bio::Graphics::Panel->can('auto_pad');
    my $click_position = $regionview_size  * ($regionview_x-$padl)/$regionview_width;

    $span = $config->default_segment if $span > $config->max_segment;
    $start = int($click_position - $span/2 + $regionview_start);
    $stop  = $start + $span - 1;
  }

  elsif ($selected_span) {
    warn "selected_span = $selected_span" if DEBUG;
    my $center	    = int(($span / 2)) + $start;
    my $range	    = int(($selected_span)/2);
    $start          = $center - $range;
    $stop           = $start + $selected_span - 1;
  }

  warn "after adjusting for navlevel, start = $start, stop = $stop, span=$span" if DEBUG;

  # to prevent from going off left end
  if (defined $seg_min && $start < $seg_min) {
    warn "adjusting left because $start < $seg_min" if DEBUG;
    ($start,$stop) = ($seg_min,$seg_min+$stop-$start);
  }

  # to prevent from going off right end
  if (defined $seg_max && $stop > $seg_max) {
    warn "adjusting right because $stop > $seg_max" if DEBUG;
    ($start,$stop) = ($seg_max-($stop-$start),$seg_max);
  }

  # to prevent divide-by-zero errors when zoomed down to a region < 2 bp
  # $stop  = $start + ($span > 4 ? $span - 1 : 4) if $stop <= $start+2;

  warn "start = $start, stop = $stop\n" if DEBUG;

  $state->{start} = $start/$divisor;
  $state->{stop}  = $stop/$divisor;
}

sub fetch_segments {
  my $self  = shift;
  my $db    = $self->db;
  my $state = $self->state;

  # do something
}

##################################################################3
#
# SHARED RENDERING CODE HERE
#
##################################################################3

sub overview_ration {
  my $self = shift;
  return 1.0;   # for now
}

sub overview_pad {
  my $self = shift;
  my $tracks = shift;

  my $config = $self->data_source;

  $tracks ||= [$config->overview_tracks];
  my $max = 0;
  foreach (@$tracks) {
    my $key = $self->setting($_=>'key');
    next unless defined $key;
    $max = length $key if length $key > $max;
  }
  foreach (@_) {  #extra
    $max = length if length > $max;
  }

  # Tremendous kludge!  Not able to generate overview maps in GD yet
  # This needs to be cleaned...
  my $image_class = 'GD';
  eval "use $image_class";
  my $pad = $config->min_overview_pad;
  return ($pad,$pad) unless $max;
  return ($max * $image_class->gdMediumBoldFont->width + 3,$pad);
}

# override make_link to allow for code references
sub make_link {
  my $self     = shift;
  my ($feature,$panel,$label,$track)  = @_;

  my $data_source = $self->data_source;
  my $ds_name     = $data_source->name;

  if ($feature->can('url')) {
    my $link = $feature->url;
    return $link if defined $link;
  }
  return $label->make_link($feature) if $label && $label->isa('Bio::Graphics::FeatureFile');

  $panel ||= 'Bio::Graphics::Panel';
  $label ||= $data_source->feature2label($feature);

  # most specific -- a configuration line
  my $link     = $data_source->code_setting($label,'link');

  # less specific - a smart feature
  $link        = $feature->make_link if $feature->can('make_link') && !defined $link;

  # general defaults
  $link        = $data_source->code_setting('TRACK DEFAULTS'=>'link') unless defined $link;
  $link        = $data_source->code_setting(general=>'link')          unless defined $link;

  return unless $link;

  if (ref($link) eq 'CODE') {
    my $val = eval {$link->($feature,$panel,$track)};
    $data_source->_callback_complain($label=>'link') if $@;
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
    my $url   = CGI->request_uri || '../..';
    $url      =~ s!/gbrowse.*!!;
    $url      .= "/gbrowse_details/$ds_name?name=$name;class=$class;ref=$ref;start=$start;end=$end";
    return $url;
  }
  return $data_source->link_pattern($link,$feature,$panel);
}

# make the title for an object on a clickable imagemap
sub make_title {
  my $self = shift;
  my ($feature,$panel,$label,$track) = @_;
  local $^W = 0;  # tired of uninitialized variable warnings
  my $data_source = $self->data_source;

  my ($title,$key) = ('','');

 TRY: {
    if ($label && $label->isa('Bio::Graphics::FeatureFile')) {
      $key = $label->name;
      $title = $label->make_title($feature) or last TRY;
      return $title;
    }

    else {
      $label     ||= $data_source->feature2label($feature) or last TRY;
      $key       ||= $data_source->setting($label,'key') || $label;
      $key         =~ s/s$//;
      $key         = $feature->segment->dsn if $feature->isa('Bio::Das::Feature');  # for DAS sources

      my $link     = $data_source->code_setting($label,'title')
	|| $data_source->code_setting('TRACK DEFAULTS'=>'title')
	  || $data_source->code_setting(general=>'title');
      if (defined $link && ref($link) eq 'CODE') {
	$title       = eval {$link->($feature,$panel,$track)};
	$self->_callback_complain($label=>'title') if $@;
	return $title if defined $title;
      }
      return $data_source->link_pattern($link,$feature) if $link && $link ne 'AUTO';
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
  my $data_source = $self->data_source;

  if ($feature->isa('Bio::Das::Feature')) { # new window
    my $dsn = $feature->segment->dsn;
    $dsn =~ s/^.+\///;
    return $dsn;
  }

  $label    ||= $data_source->feature2label($feature) or return;
  my $link_target = $data_source->code_setting($label,'link_target')
    || $data_source->code_setting('LINK DEFAULTS' => 'link_target')
    || $data_source->code_setting(general => 'link_target');
  $link_target = eval {$link_target->($feature,$panel,$track)} if ref($link_target) eq 'CODE';
  $data_source->_callback_complain($label=>'link_target') if $@;
  return $link_target;
}

sub default_style {
  my $self = shift;
  return $self->SUPER::style('TRACK DEFAULTS');
}

##### language stuff
sub set_language {
  my $self = shift;

  my $data_source = $self->data_source;

  my $lang        = Bio::Graphics::Browser::I18n->new($data_source->globals->language_path);
  my $default_language = $data_source->setting('language') || 'POSIX';

  my $accept           = CGI::http('Accept-language') || '';
  my @languages        = $accept =~ /([a-z]{2}-?[a-z]*)/ig;
  push @languages,$default_language if $default_language;

  return unless @languages;
  $lang->language(@languages);
  $self->language($lang);
}

# return language-specific options
sub i18n_style {
  my $self      = shift;
  my ($label,$lang,$length) = @_;

  my $data_source = $self->data_source;

  return $data_source->style($label,$length) unless $lang;

  my $charset   = $lang->tr('CHARSET');

  # GD can't handle non-ASCII/LATIN scripts transparently
  return $data_source->style($label,$length) 
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

sub tra {
  my $self = shift;
  my $lang = $self->language or return @_;
  $lang->tr(@_);
}

####################################333
# Unit conversion
####################################333
# convert bp into nice Mb/Kb units
sub unit_label {
  my $self = shift;
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

# convert Mb/Kb back into bp... or a ratio
sub unit_to_value {
  my $self = shift;
  my $string = shift;
  my $sign           = $string =~ /out|left/ ? '-' : '+';
  my ($value,$units) = $string =~ /([\d.]+) ?(\S+)/;
  return unless defined $value;
  $units ||= 'bp';
  $value /= 100   if $units eq '%';  # percentage;
  $value *= 1000  if $units =~ /kb/i;
  $value *= 1e6   if $units =~ /mb/i;
  $value *= 1e9   if $units =~ /gb/i;
  return "$sign$value";
}

1;

