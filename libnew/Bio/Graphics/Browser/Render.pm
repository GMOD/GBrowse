package Bio::Graphics::Browser::Render;

use strict;	
use warnings;

use JSON;
use Digest::MD5 'md5_hex';
use CGI qw(:standard param request_method header url iframe img span div br center);
use Carp 'croak';

use Bio::Graphics::Browser::I18n;
use Bio::Graphics::Browser::PluginSet;
use Bio::Graphics::Browser::UploadSet;
use Bio::Graphics::Browser::RemoteSet;
use Bio::Graphics::Browser::Shellwords;
use Bio::Graphics::Browser::Region;
use Bio::Graphics::Browser::RenderPanels;

use constant VERSION => 2.0;
use constant DEBUG   => 0;


my %PLUGINS; # cache initialized plugins

# new() can be called with two arguments: ($data_source,$session)
# or with one argument: ($globals)
# in the latter case, it will invoke this code:
#   $session = $globals->session()
#   $globals->update_data_source($session)
#   $source = $globals->create_data_source($session->source)

sub new {
  my $class = shift;

  my ($data_source,$session);

  if (@_ == 2) {
    ($data_source,$session) = @_;
  } elsif (@_ == 1) {
    my $globals = shift;
    $session = $globals->session();
    $globals->update_data_source($session);
    $data_source = $globals->create_data_source($session->source);
  } else {
    croak "usage: ".__PACKAGE__."->new(\$globals) or ->new(\$data_source,\$session)";
  }

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

sub db {
  my $self = shift;
  my $d = $self->{db};
  $self->{db} = shift if @_;
  $d;
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
  my $fh   = shift || \*STDOUT;
  my $old_fh = select($fh);

  return if $self->asynchronous_event;

  my $source = $self->session->source;
  if (CGI::path_info() ne "/$source") {
    my $args = CGI::query_string();
    my $url  = CGI::url(-absolute=>1);
    $url .= "/$source";
    $url .= "?$args" if $args;
    print CGI::redirect($url);
    warn "redirecting from $ENV{REQUEST_URI} to $url";
    return;
  }

  $self->init_database();
  $self->init_plugins();
  $self->init_remote_sources();
  $self->update_state();
  $self->render();
  $self->clean_up();
  select($old_fh);
  $self->session->flush;
}

# handle asynchronous events
#
# asynchronous requests:
#
# div_visible_<label>=bool              Turn on/off visibility of track with <label>
# track_collapse_<label>=bool           Collapse/uncollapse track with <label>
# label[]=<label1>,label[]=<label2>...  Change track order
# render=<label1>,render=<label2>...    Render the specified tracks
sub asynchronous_event {
  my $self = shift;
  my $settings = $self->state;
  my $events;

  # toggle the visibility of sections by looking for "div_visible_*" parameters
  for my $p (grep {/^div_visible_/} param()) {
    my $visibility = param($p);
    $p =~ s/^div_visible_//;
    $settings->{section_visible}{$p} = $visibility;
    $events++;
  }

  # toggle the visibility of individual tracks
  for my $p (grep {/^track_collapse_/} param()) {
    my $collapsed = param($p);
    $p =~ s/^track_collapse_//;
    $settings->{track_collapsed}{$p} = $collapsed;
    $events++;
  }

  # Change the order of tracks if any "label[]" parameters are present
  if (my @labels = param('label[]')) {
    my %seen;
    @{$settings->{tracks}} = grep {length()>0 && !$seen{$_}++} (@labels,@{$settings->{tracks}});
    $events++;
  }

  # Slightly different -- process a tracks request in the background.
  if (my @labels  = param('render')) { # deferred rendering requested
      $self->init_database();
      $self->init_plugins();
      $self->init_remote_sources();
      my $features      = $self->fetch_features;
      my $seg           = $self->features2segments($features)->[0]; # likely wrong

      $self->set_segment($seg);

      my $deferred_data = $self->request_tracks(\@labels);

      print CGI::header('application/json'),
            JSON::objToJson($deferred_data);
      $self->session->flush;
      return 1;
  }

  return unless $events;
  warn "processing asynchronous event(s)";
  print CGI::header('204 No Content');
  $self->session->flush;
  1;
}

# This asynchronous method accepts a list of track names and returns a 
# hash which maps the track name to the URL at which the data will be cached
sub request_tracks {
    my $self         = shift;
    my $track_labels = shift;
    my $segment      = $self->segment;
    my $renderer     = $self->get_panel_renderer($segment);
    my $pending_data = $renderer->render_panels(
	{
	    labels           => $track_labels,
	    feature_files    => $self->remote_sources,
	    deferred         => 1,
	}
	);
    return $pending_data;
}

sub render {
  my $self           = shift;

  # NOTE: these handle_* methods will return true
  # if they want us to exit before printing the header
  $self->handle_plugins()   && return;
  $self->handle_downloads() && return;
  $self->handle_uploads()   && return;

  $self->render_header();
  $self->render_body();
}

sub render_header {
  my $self    = shift;
  my $session = $self->session;
  my $cookie = CGI::Cookie->new(-name => $CGI::Session::NAME,
				-value => $session->id,
				-path   => url(-absolute=>1),
				-expires => $self->globals->remember_settings_time
				);
  print header(-cookie  => $cookie,
	       -charset => $self->tr('CHARSET')
	      );
}

# For debugging
sub allparams {
  my $args = {};
  for my $key (param()) {
    $args->{$key} = param($key)
  }
  "<pre>".Data::Dumper::Dumper($args)."</pre>";
}
#print "All params:<br>\n".dumperonscreen($self->allparams);

sub render_body {
  my $self     = shift;

  my $region   = $self->region;
  my $features = $region->features;

  my $title = $self->render_top($features);
  $self->render_instructions($title);

  if ($region->feature_count > 1) {
    #search not implemented yet
    $self->render_multiple_choices($features);
  }

  elsif (my $seg = $region->seg) {
      $self->render_navbar($seg);
      $self->render_panels($seg,{overview=>1,regionview=>1,detailview=>1});
      $self->render_config($seg);
  }
  else {
      $self->render_navbar();
      $self->render_config();
  }

  $self->render_bottom($features);
}

# never called, method in HTML.pm with same name is run instead
sub render_top    {
  my $self     = shift;
  my $features = shift;
  croak "render_top() should not be called in parent class";
}

#never called, method in HTML.pm with same name is run instead
sub render_navbar {
  my $self = shift;
  my $seg  = shift;
  croak "render_top() should not be called in parent class";
}

sub render_panels {
  my $self = shift;
  my $seg     = shift;
  my $section = shift;

  $self->render_overview($seg)   if $section->{overview};
  $self->render_regionview($seg) if $section->{regionview};
  $self->render_detailview($seg) if $section->{detailview};
}

sub render_overview {
  my $self = shift;
  my $seg  = shift;

  my $source			= $self->data_source;
  my $whole_segment 	        = $self->whole_seg;
  my $segment			= $self->seg || return;
  my $state				= $self->state;
  my $features			= $self->fetch_features;
  my $feature_files		= {};		#fill in code later, is usually blank anyways

  my $renderer = Bio::Graphics::Browser::RenderPanels->new(-segment  => $seg,
							   -source   => $source,
							   -settings => $state,
							   -renderer => $self);
  my $image   = $renderer->render_overview(('Overview',
  					   $whole_segment,
  					   $seg,
  					   $state,
  					   $feature_files));
  
  print $self->toggle('Overview',
		table({-border=>0,-width=>'100%'},
		      TR({-class=>'databody'},
			 td({-align=>'center'},$image)
			)
		     )
	       );
  
  
  
}

sub render_regionview {
  my $self = shift;
  my $seg = shift;
}

sub render_config {
  my $self = shift;
  my $seg = shift;
  $self->render_track_table();
  $self->render_global_config();
  $self->render_uploads();
}

#never called, method in HTML.pm with same name is run instead
sub render_track_table {
  my $self = shift;
}

sub render_instructions {
  my $self = shift;
}
sub render_multiple_choices {
  my $self = shift;
}

sub render_global_config {
  my $self = shift;
}

sub render_uploads {
  my $self = shift;
}

sub render_bottom {
  my $self = shift;
  my $features = shift;
  croak "render_top() should not be called in parent class";
}


sub init_database {
  my $self = shift;
  my $dsn = $self->data_source;
  my $db  = $dsn->open_database();

  # I don't know what this is for, but it was there in gbrowse and looks like an important hack.
  eval {$db->biosql->version($self->state->{version})};

  $self->db($db);
  $db;
}

sub region {
    my $self     = shift;
    return $self->{region} if exists $self->{region};

    my $region   = Bio::Graphics::Browser::Region->new(
	{ source => $self->data_source,
	  state  => $self->state,
	  db     => $self->db }
	) or die;

    # run any "find" plugins
    my $plugin_action  = $self->plugin_action || '';
    my $current_plugin = $self->current_plugin;
    if ($current_plugin && $plugin_action eq $self->tr('Find') || 
	$plugin_action eq 'Find') {
	$region->features($self->plugin_find($current_plugin,$self->state->{name}));
    }
    else {
	$region->search_features();
    }

    $self->plugins->set_segments($region->segments);
    return $self->{region} = $region;
}

sub segment {
    my $self   = shift;
    my $region = $self->region;
    return $region->seg;
}

# ========================= plugins =======================
sub init_plugins {
  my $self        = shift;
  my $source      = $self->data_source->name;
  my @plugin_path = shellwords($self->data_source->globals->plugin_path);

  my $plugins = $PLUGINS{$source} 
    ||= Bio::Graphics::Browser::PluginSet->new($self->data_source,
					       $self->state,
					       $self->language,
					       @plugin_path);
  $self->fatal_error("Could not initialize plugins") unless $plugins;
  $plugins->configure($self->db,$self->state,$self->language,$self->session);
  $self->plugins($plugins);
  $plugins;
}

# for activating plugins
sub plugin_action {
  my $self = shift;
  my $action;

  # the logic of this is obscure to me, but seems to have to do with activating plugins
  # via the URL versus via fill-out forms, which may go through a translation.
  if (param('plugin_do')) {
    $action = $self->tr(param('plugin_do')) || $self->tr('Go');
  }
  $action ||= param('plugin_action');
  return $action;
}

sub current_plugin {
  my $self = shift;
  my $plugin_name = param('plugin') or return;
  $self->plugins->plugin($plugin_name);
}

sub plugin_find {
  my $self = shift;
  my ($plugin,$search_string) = @_;

  my $settings = $self->state;
  my $plugin_name = $plugin->name;
  my $results = $plugin->can('auto_find') && defined $search_string
              ? $plugin->auto_find($search_string)
              : $plugin->find();
  return unless $results;
  return unless @$results;

  $settings->{name} = defined($search_string) ? $self->tr('Plugin_search_1',$search_string,$plugin_name)
                                              : $self->tr('Plugin_search_2',$plugin_name);
  $self->write_auto($results);
  return $results;
}

sub handle_plugins {
  my $self = shift;
  return;
}

#======================== remote sources ====================
sub init_remote_sources {
  my $self = shift;
  my $uploaded_sources = Bio::Graphics::Browser::UploadSet->new($self->data_source,$self->state);
  my $remote_sources   = Bio::Graphics::Browser::RemoteSet->new($self->data_source,$self->state);
  $self->uploaded_sources($uploaded_sources);
  $self->remote_sources($remote_sources);
  return $uploaded_sources && $remote_sources;  # true if both defined
}

sub clean_up {
  my $self = shift;
}

sub fatal_error {
  my $self = shift;
  my @msg  = @_;
  croak 'Please call fatal_error() for a subclass of Bio::Graphics::Browser::Render';
}

# not implemented
sub write_auto {
  my $self = shift;
  my $result_set = shift;
  return;   
}

sub handle_downloads {
  my $self = shift;
  # return 1 to exit
  return;
}

sub handle_uploads {
  my $self = shift;
  # return 1 to exit
  return;
}


###################################################################################
#
# SETTINGS CODE HERE
#
###################################################################################

sub globals {
  my $self = shift;
  $self->data_source->globals;
}

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

=head2 plugin_setting()

   $value = = $browser->plugin_setting("option_name");

When called in the context of a plugin, returns the setting for the
requested option.  The option must be placed in a [PluginName:plugin]
configuration file section:

  [MyPlugin:plugin]
  foo = bar

Now within the MyPlugin.pm plugin, you may call
$browser->plugin_setting('foo') to return value "bar".

=cut

sub plugin_setting {
  my $self           = shift;
  my $caller_package = caller();
  my ($last_name)    = $caller_package =~ /(\w+)$/;
  my $option_name    = "${last_name}:plugin";
  $self->setting($option_name => @_);
}

# dealing with external DAS sources?
sub get_external_presets {
  my $self = shift;
  my $presets  = $self->setting('remote sources') or return;
  my @presets  = shellwords($presets||'');
  my (@labels,@urls);
  while (@presets) {
    my ($label,$url) = splice(@presets,0,2);
    next unless $url && $url =~ /^(http|ftp)/;
    push @labels,$label;
    push @urls,$url;
  }
  return unless @labels;
  return (\@labels,\@urls) if wantarray;
  my %presets;
  @presets{@urls} = @labels;
  return \%presets;
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
  $self->update_external_sources();
}

sub update_options {
  my $self  = shift;
  my $state = shift || $self->state;

  #  return unless param('width'); # not submitted
  $state->{width} ||= $self->setting('default width');  # working around a bug during development

  $state->{grid} = 1 unless exists $state->{grid};  # to upgrade from older settings
  $state->{flip} = 0;  # obnoxious for this to persist

  $state->{version} ||= param('version') || '';
  do {$state->{$_} = param($_) if defined param($_) } 
    foreach qw(name source plugin stp ins head ks sk version grid flip width);

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
  $self->session->modified;
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

# update coordinates logic
# 1. A fresh session will have a null {ref,start,stop} state, a previous session will have {ref,start,stop,seg_min,seg_max} defined
# 2. If param('ref'),param('start') and param('stop') are defined, or if param('q') is defined, then we
#    reset {ref,start,stop}
# 3. Otherwise, if {ref,start,stop} are defined, then
#    2a. interrogate param('span'). If span != (stop-start+1) then user has changed the zoom popup menu and we do a zoom.
#    2b. interrogate /left|right|zoom|nav|regionview|overview/, which define the various zoom and scroll buttons.
#        If any of them exist, then we do the appropriate coordinate adjustment
# 3. If we did NOT change the coordinates, then we look for param('name') and use that to set the coordinates
#    using a database search.
# 4. set {name} to "ref:start..stop"

sub update_coordinates {
  my $self  = shift;
  my $state = shift || $self->state;

  delete $self->{region}; # clear cached region
  my $position_updated;

  # I really don't know if this belongs here. Divider should only be used for displaying
  # numbers, not for doing calculations with them.
  # my $divider  = $self->setting('unit_divider') || 1;
  if (param('ref')) {
    $state->{ref}   = param('ref');
    $state->{start} = param('start') if defined param('start') && param('start') =~ /^[\d-]+/;
    $state->{stop}  = param('stop')  if defined param('stop')  && param('stop')  =~ /^[\d-]+/;
    $state->{stop}  = param('end')   if defined param('end')   && param('end')   =~ /^[\d-]+/;
    $position_updated++;
  }

  elsif (param('q')) {
    @{$state}{'ref','start','stop'} = $self->parse_feature_name(param('q'));
    $position_updated++;
  }

  my $current_span = length $state->{stop} ? ($state->{stop} - $state->{start} + 1) : 0;
  my $new_span     = param('span');
  if ($new_span && $current_span != $new_span) {
    $self->zoom_to_span($state,$new_span);
    $position_updated++;
  }
  elsif (my ($scroll_data) = grep {/^(?:left|right) \S+/} param()) {
    $self->scroll($state,$scroll_data);
    $position_updated++;
  }
  elsif (my ($zoom_data)   = grep {/^zoom (?:out|in) \S+/} param()) {
    $self->zoom($state,$zoom_data);
    $position_updated++;
  }
  elsif (my $position_data = param('overview.x')) {
    $self->position_from_overview($state,$position_data);
    $position_updated++;
  }
  elsif ($position_data = param('regionview.x')) {
    $self->position_from_regionview($state,$position_data);
    $position_updated++;
  }

  if ($position_updated) { # clip and update param
    if (defined $state->{seg_min} && $state->{start} < $state->{seg_min}) {
      my $delta = $state->{seg_min} - $state->{start};
      $state->{start} += $delta;
      $state->{stop}  += $delta;
    }

    if (defined $state->{seg_max} && $state->{stop}  > $state->{seg_max}) {
      my $delta = $state->{stop} - $state->{seg_max};
      $state->{start} -= $delta;
      $state->{stop}  -= $delta;
    }

    # update our "name" state and the CGI parameter
    $state->{name} = "$state->{ref}:$state->{start}..$state->{stop}";
    param(name => $state->{name});
  }
  elsif (param('name')) {
    $state->{name} = param('name');
  }

  return $position_updated;
}

sub zoom_to_span {
  my $self = shift;
  my ($state,$new_span) = @_;

  my $current_span = $state->{stop} - $state->{start} + 1;
  my $center	    = int(($current_span / 2)) + $state->{start};
  my $range	    = int(($new_span)/2);
  $state->{start}   = $center - $range;
  $state->{stop }   = $state->{start} + $new_span - 1;
}

sub scroll {
  my $self = shift;
  my $state       = shift;
  my $scroll_data = shift;

  my $flip        = $state->{flip} ? -1 : 1;

  $scroll_data    =~ s/\.[xy]$//; # get rid of imagemap button cruft
  my $scroll_distance = $self->unit_to_value($scroll_data);

  $state->{start} += $flip * $scroll_distance;
  $state->{stop}  += $flip * $scroll_distance;
}

sub zoom {
  my $self = shift;
  my $state     = shift;
  my $zoom_data = shift;

  $zoom_data    =~ s/\.[xy]$//; # get rid of imagemap button cruft
  my $zoom_distance = $self->unit_to_value($zoom_data);
  my $span          = $state->{stop} - $state->{start} + 1;
  my $center	    = int($span / 2) + $state->{start};
  my $range	    = int($span * (1-$zoom_distance)/2);
  $range            = 1 if $range < 1;

  $state->{start}   = $center - $range;
  $state->{stop}    = $center + $range - 1;
}

sub position_from_overview {
  my $self = shift;
  my $state         = shift;
  my $position_data = shift;

  return unless defined $state->{seg_max} && defined $state->{seg_min};

  my $segment_length = $state->{seg_max} - $state->{seg_min} + 1;
  return unless $segment_length > 0;

  my @overview_tracks = grep {$state->{features}{$_}{visible}} 
    $self->data_source->overview_tracks;

  my ($padl,$padr)   = $self->overview_pad(\@overview_tracks);
  my $overview_width = $state->{width} * $self->overview_ratio;

  my $click_position = $state->{seg_min} + $segment_length * ($position_data-$padl)/$overview_width;
  my $span           = $state->{stop} - $state->{start} + 1;

  $state->{start}    = int($click_position - $span/2);
  $state->{stop}     = $state->{start} + $span - 1;
}

sub position_from_regionview {
  my $self = shift;
  my $state         = shift;
  my $position_data = shift;
  return unless defined $state->{seg_max} && defined $state->{seg_min};
  return unless $state->{region_size};

  my @regionview_tracks = grep {$state->{features}{$_}{visible}}
    $self->data_source->regionview_tracks;

  my ($padl,$padr) = $self->overview_pad(\@regionview_tracks) or return;
  my $regionview_width = ($state->{width} * $self->overview_ratio);

  my $click_position = $state->{region_size}  * ($position_data-$padl)/$regionview_width;
  my $span           = $state->{stop} - $state->{start} + 1;

  my ($regionview_start, $regionview_end) = $self->regionview_bounds();

  $state->{start} = int($click_position - $span/2 + $regionview_start);
  $state->{stop}  = $state->{start} + $span - 1;
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

sub update_external_sources {
  my $self = shift;
  $self->remote_sources->set_sources([param('eurl')]) if param('eurl');
}

##################################################################3
#
# SHARED RENDERING CODE HERE
#
##################################################################3

# overview_ratio and overview_pad moved to RenderPanels.pm

sub set_language {
  my $self = shift;

  my $data_source = $self->data_source;

  my $lang             = Bio::Graphics::Browser::I18n->new($data_source->globals->language_path);
  my $default_language = $data_source->setting('language') || 'POSIX';

  my $accept           = CGI::http('Accept-language') || '';
  my @languages        = $accept =~ /([a-z]{2}-?[a-z]*)/ig;
  push @languages,$default_language if $default_language;

  return unless @languages;
  $lang->language(@languages);
  $self->language($lang);
}

sub language {
  my $self = shift;
  my $d = $self->{lang};
  $self->{lang} = shift if @_;
  $d;
}

# Returns the language code, but only if we have a translate table for it.
sub language_code {
  my $self = shift;
  my $lang = $self->language;
  my $table= $lang->tr_table($lang->language);
  return unless %$table;
  return $lang->language;
}

##### language stuff
sub label2key {
  my $self  = shift;
  my $label = shift;
  my $source = $self->data_source;
  my $key;
  my $presets = $self->get_external_presets || {};
  for my $l ($self->language->language) {
    $key     ||= $source->setting($label=>"key:$l");
  }
  $key     ||= $source->setting($label => 'key');
  $key     ||= $key if defined $key;
  $key     ||= $label;
  $key;
}

####################################
# Unit conversion
####################################
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
  my ($value,$units) = $string =~ /([\d.]+)(\s*\S+)?/;
  return unless defined $value;
  $units ||= 'bp';
  $value /= 100   if $units eq '%';  # percentage;
  $value *= 1000  if $units =~ /kb/i;
  $value *= 1e6   if $units =~ /mb/i;
  $value *= 1e9   if $units =~ /gb/i;
  return "$sign$value";
}

sub get_zoomincrement {
  my $self = shift;
  my $zoom = $self->setting('fine zoom');
  return $zoom;
}


#############################################################################
#
# HANDLING SEGMENTS
#
#############################################################################
sub regionview_bounds {
  my $self  = shift;

  my $state             = $self->state;
  my $regionview_length = $state->{region_size};

  my ($detail_start,$detail_stop) = (@{$state}{'start','stop'})      or return;
  my ($whole_start,$whole_stop)   = (@{$state}{'seg_min','seg_max'}) or return;


  if ($detail_stop - $detail_start + 1 > $regionview_length) { # region can't be smaller than detail
    $regionview_length = $detail_stop - $detail_start + 1;
  }
  my $midpoint = ($detail_stop + $detail_start) / 2;
  my $regionview_start = int($midpoint - $regionview_length/2 + 1);
  my $regionview_end = int($midpoint + $regionview_length/2);

  if ($regionview_start < $whole_start) {
    $regionview_start = 1;
    $regionview_end   = $regionview_length;
  }
  if ($regionview_end > $whole_stop) {
    $regionview_start = $whole_stop - $regionview_length + 1;
    $regionview_end   = $whole_stop;
  }
  return ($regionview_start, $regionview_end);
}

sub split_labels {
  my $self = shift;
  map {/^(http|ftp|das)/ ? $_ : split /[+-]/} @_;
}

sub detail_tracks {
  my $self = shift;
  my $state = $self->state;
  return grep {$state->{features}{$_}{visible} && !/:(overview|region)$/ }
    @{$state->{tracks}};
}

################## get renderer for this segment #########
sub get_panel_renderer {
  my $self = shift;
  my $seg  = shift or die "usage: \$self->get_panel_renderer(\$segment)";
  return Bio::Graphics::Browser::RenderPanels->new(-segment  => $seg,
						   -source   => $self->data_source,
						   -settings => $self->state,
						   -language => $self->language,
						  );}

################## image rendering code #############

sub render_detailview {
  my $self = shift;
  my $seg  = shift or return;

  my @labels   = $self->detail_tracks;
  my $renderer = $self->get_panel_renderer($seg);
  my $panels   = $renderer->render_panels({
					   labels           => \@labels,
					   feature_files    => $self->remote_sources,
					   section          => 'detail',
					  }
					 );

  my @panels   = map {$panels->{$_}} @labels;

  my $drag_script = $self->drag_script('panels','track');
  print div($self->toggle('Details',
			  div({-id=>'panels',-class=>'track'},
			      @panels
			  )
	    )
      ).$drag_script;
}


# returns the fragment we need to use the scriptaculous drag 'n drop code
sub drag_script {
  my $self       = shift;
  my $div_name   = shift;
  my $div_part = shift;

  return <<END;
  <script type="text/javascript">
 // <![CDATA[
   create_drag('$div_name','$div_part');
 // ]]>
 </script>
END
}

##################### utilities #####################

sub categorize_track {
  my $self  = shift;
  my $label = shift;
  return $self->tr('OVERVIEW') if $label =~ /:overview$/;
  return $self->tr('REGION')   if $label =~ /:region$/;
  return $self->tr('EXTERNAL') if $label =~ /^(http|ftp|file):/;
  return $self->tr('ANALYSIS') if $label =~ /^plugin:/;

  my $category;
  for my $l ($self->language->language) {
    $category      ||= $self->setting($label=>"category:$l");
  }
  $category        ||= $self->setting($label => 'category');
  $category        ||= '';  # prevent uninit variable warnings
  $category         =~ s/^["']//;  # get rid of leading quotes
  $category         =~ s/["']$//;  # get rid of trailing quotes
  return $category ||= $self->tr('GENERAL');
}

sub is_safari {
  return (CGI::user_agent||'') =~ /safari/i;
}

sub citation {
  my $self = shift;
  my $label     = shift;
  my $language  = shift;
  my $source = $self->data_source;
  my $c;
  if ($language) {
    for my $l ($language->language) {
      $c ||= $source->setting($label=>"citation:$l");
    }
  }
  $c ||= $source->setting($label=>'citation');
  $c;
}


sub DESTROY {
   my $self = shift;
   if ($self->session) { $self->session->flush; }
}

########## note: "sub tr()" makes emacs' syntax coloring croak, so place this function at end
sub tr {
  my $self = shift;
  my $lang = $self->language or return @_;
  $lang->tr(@_);
}

1;

