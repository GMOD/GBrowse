package Bio::Graphics::Browser::Render;

use strict;	
use warnings;
use Bio::Graphics::Browser::I18n;
use Bio::Graphics::Browser::PluginSet;
use Bio::Graphics::Browser::UploadSet;
use Bio::Graphics::Browser::RemoteSet;
use Bio::Graphics::Browser::Shellwords;
use Digest::MD5 'md5_hex';
use CGI qw(:standard param request_method header url iframe img span div br center start_table end_table);
use Carp 'croak';

use Data::Dumper;

use constant VERSION => 2.0;
use constant DEBUG   => 0;
use constant PAD_OVERVIEW_BOTTOM => 5;


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

sub language {
  my $self = shift;
  my $d = $self->{lang};
  $self->{lang} = shift if @_;
  $d;
}

sub db {
  my $self = shift;
  my $d = $self->{db};
  $self->{db} = shift if @_;
  $d;
}

# DEPRECATED! We will not hold a series of segments, but features and current segment
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
  return wantarray ? @$d : $d;
}

sub set_segment {
  my $self = shift;
  my $seg  = shift;

  my $whole_seg  = $self->get_whole_segment($seg);
  $self->seg($seg);
  $self->whole_seg($whole_seg);

  my $state = $self->state;
  $state->{ref}   = $seg->seq_id;
  $state->{start} = $seg->start;
  $state->{stop}  = $seg->end;

  $state->{seg_min} = $whole_seg->start;
  $state->{seg_max} = $whole_seg->end;
}


# this holds the segment we're currently working on
sub seg {
  my $self = shift;
  my $d    = $self->{segment};
  $self->{segment} = shift if @_;
  $d;
}

# this holds the segment object corresponding to the seqid of the segment we're currently working on
sub whole_seg {
  my $self = shift;
  my $d    = $self->{whole_segment};
  $self->{whole_segment} = shift if @_;
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
    exit 0;
  }

  $self->init_database();
  $self->init_plugins();
  $self->init_remote_sources();
  $self->update_state();
  my $features = $self->fetch_features;
  $self->render($features);
  $self->clean_up();
  select($old_fh);
  $self->session->flush;
}

sub asynchronous_event {
  my $self = shift;
  my $settings = $self->state;
  my $events;

  for my $p (grep {/^div_visible_/} param()) {
    my $visibility = param($p);
    $p =~ s/^div_visible_//;
    $settings->{section_visible}{$p} = $visibility;
    $events++;
  }

  if (my @labels = param('label[]')) {
    my %seen;
    @{$settings->{tracks}} = grep {length()>0 && !$seen{$_}++} (@labels,@{$settings->{tracks}});
    $events++;
  }

  return unless $events;
  warn "processing asynchronous event(s)";
  print CGI::header('204 No Content');
  $self->session->flush;
  1;
}

sub render {
  my $self           = shift;
  my $features       = shift;

  # NOTE: these handle_* methods will return true
  # if they want us to exit before printing the header
  $self->handle_plugins()   && return;
  $self->handle_downloads() && return;
  $self->handle_uploads()   && return;

  $self->render_header();
  $self->render_body($features);
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
  my $features = shift;

#print "All params:<br>\n".allparams;
  
  my $segments;
  if ($features && @$features == 1) {
    $segments = $self->features2segments($features);
    $self->set_segment($segments->[0]);
  }

    my $title = $self->render_top($features);

  # THIS IS AN ASYNCHRONOUS CALL AND NEEDS TO BE MOVED OUT OF THE RENDER_* TREE
  if (param('render') && param('render') eq 'detailview') {
    warn "calling render tracks...";
    $self->render_tracks($self->seg);
#print div({-id=>'Overview'},[2,4,8]),$self->drag_script('tracks'),$self->update_controls_script;
    print "</html>";
    return;
  }

  $self->render_instructions($title);
  
  if ($features && @$features > 1) {
  	#search not implemented yet
    $self->render_multiple_choices($features);
  }

  elsif (my $seg = $self->seg) {
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

sub render_top    {
  my $self     = shift;
  my $features = shift;
}

#never called, method in HTML.pm with same name is run instead
sub render_navbar {
  my $self = shift;
  my $seg  = shift;
}
sub render_panels {
  my $self = shift;
  my $seg  = shift;
  my $section = shift;

  $self->render_overview($seg)   if $section->{overview};
  $self->render_regionview($seg) if $section->{regionview};
  $self->render_detailview($seg) if $section->{detailview};
}

sub render_overview {
  my $self = shift;
  my $seg  = shift;
  
#  my $source			= $self->source;
  my $whole_segment 	= $self->whole_seg;
  my $segment			= $self->seg || return;
  my $state				= $self->state;
  my $features			= $self->fetch_features;
  my $feature_files		= {};						#fill in code later, is usually blank anyways
  
  
  #warn"args:\n".Dumper($whole_segment, $segment, $state, $features, $feature_files);
  
  #my ($image, $length) = _overview('overview', $whole_segment, $segment, $features, $feature_files)
  
#print"page settings:\n".Dumper($state);
  
  #return '' unless $state->{'section_visible'}->{'overview_panel'};
  
  
  #run from RenderTracks??  <- problems with accessing some methods: overview_pad, etc.
#  my $renderer = Bio::Graphics::Browser::RenderTracks->new(-segment  => $seg,
#							   -source   => $self->data_source,
#							   -settings => $state,
#							   -renderer => $self);
#  my $image   = $renderer->render_overview(('Overview',
#  					   $whole_segment,
#  					   $seg,
#  					   $state,
#  					   $feature_files));
  
  
  
  
  #my ($region_name,$segment,$partial_segment,$track_options,$feature_files) = @_;
  my $region_name = 'Overview';
  my $gd;
  
  #track option is same as state
  
  # Temporary kludge until I can figure out a more
  # sane way of rendering overview with SVG...
  my $image_class = 'GD';
  eval "use $image_class";
  
  my $source         = $self->data_source;
  my $width          = $state->{'width'} * $self->overview_ratio();
  my @tracks         = grep {$state->{'features'}{$_}{visible}} 
    $region_name eq 'region' ? $source->regionview_tracks : $source->overview_tracks;

  my ($padl,$padr)   = $self->overview_pad(\@tracks);
  
  my $panel = Bio::Graphics::Panel->new(-segment => $whole_segment,
					-width   => $width,
					-bgcolor => $self->setting('overview bgcolor')
					|| 'wheat',
					-key_style => 'left',
					-pad_left  => $padl,
					-pad_right => $padr,
					-pad_bottom => PAD_OVERVIEW_BOTTOM,
					-image_class=> $image_class,
					-auto_pad   => 0,
				       );
  
  # cache check so that we can cache the overview images
  my $cache_path;
  $cache_path = $source->gd_cache_path('cache_overview',$whole_segment,
				     @tracks,$width,
				     map {@{$state->{'features'}{$_}}{'options','limit','visible'}
					} @tracks);

  # no cached data, so do it ourselves
  unless ($gd) {
    my $units         = $source->setting(general=>'units') || '';
    my $no_tick_units = $source->setting(general=>'no tick units');
    
    
    $panel->add_track($whole_segment,
		      -glyph     => 'arrow',
		      -double    => 1,
		      -label     => "\u$region_name\E of ".$whole_segment->seq_id,
		      -label_font => $image_class->gdMediumBoldFont,
		      -tick      => 2,
		      -units_in_label => $no_tick_units,
		      -units     => $units,
		      -unit_divider => $source->setting(general=>'unit_divider') || 1,
		     );
    
    
    $self->_add_landmarks(\@tracks,$panel,$whole_segment,$state);
    
    # add uploaded files that have the "(over|region)view" option set
    if ($feature_files) {
      my $select = sub {
	my $file  = shift;
	my $type  = shift;
	my $section = $file->setting($type=>'section')  || $file->setting(general=>'section') || '';
	return defined $section && $section =~ /$region_name/;
      };
      foreach (keys %$feature_files) {
	my $ff = $feature_files->{$_};
	next unless $ff->isa('Bio::Graphics::FeatureFile'); #only FeatureFile supports this
	$ff->render($panel,-1,$state->{'features'}{$_},undef,undef,$select);
      }
    }

    $gd = $panel->gd;
    $self->gd_cache_write($cache_path,$gd) if $cache_path;
  } 
  
  #warn $self->setting(general=>'solection rectangle color') ." and ". $source->setting(general=>'solection rectangle color');
  
  my $rect_color = $panel->translate_color(
                      $self->setting('selection rectangle color' )||'red');
  my ($x1,$x2) = $panel->map_pt($segment->start,$segment->end);
  my ($y1,$y2) = (0,($gd->getBounds)[1]);
  $x2 = $panel->right-1 if $x2 >= $panel->right;
  my $pl = $panel->can('auto_pad') ? $panel->pad_left : 0;
  
  
  $gd->rectangle($pl+$x1,$y1,
		 $pl+$x2,$y2-1,
		 $rect_color);

  eval {$panel->finished};  # should quash memory leaks when used in conjunction with bioperl 1.4
  
  my $url       = $self->generate_image($gd);

  my $image = img({-src=>$url,-border=>0});#,-usemap=>"#${label}_map"});7;#overview($whole_segment,$segment,$page_settings,$feature_files);
  print $self->toggle('Overview',
		table({-border=>0,-width=>'100%'},
		      TR({-class=>'databody'},
			 td({-align=>'center'},$image)
			)
		     )
	       );
  
  
  
  #print 'd' . div({-id=>"vvvvv"});#warn div($self->toggle('Details',div({-id=>'panels'},'Loading...'))),$load_script;
  #print div($self->toggle('Overview',div({-id=>'overview'},'Loading...'))),$load_script;
  
  
}


#$self->_add_landmarks(\@tracks,$panel,$whole_segment,$state);
sub _add_landmarks {
  my $self = shift;
  my ($tracks_to_add,$panel,$segment,$options) = @_;
  my $conf = $self->data_source;
  my @tracks = grep {$options->{'features'}{$_}{visible}} @$tracks_to_add;

  my (@feature_types,%type2track,%track);

  for my $overview_track (@tracks) {
    my @types = $conf->label2type($overview_track);
    my $track = $panel->add_track(-glyph  => 'generic',
				  -height  => 3,
				  -fgcolor => 'black',
				  -bgcolor => 'black',
				  $conf->style($overview_track),
				 );
    foreach (@types) {
      $type2track{lc $_} = $overview_track
    }
    $track{$overview_track} = $track;
    push @feature_types,@types;
  }
  return unless @feature_types;

  my $iterator = $segment->features(-type=>\@feature_types,-iterator=>1,-rare=>1);

  my %count;
  my (%group_on,%group_on_field);
  while (my $feature = $iterator->next_seq) {

    my $track_name = eval{$type2track{lc $feature->type}}
      || $type2track{lc $feature->primary_tag}
	|| eval{$type2track{lc $feature->method}}
	  || next;

    my $track = $track{$track_name} or next;

    # copy-and-pasted from details method. Not very efficient coding.
    exists $group_on_field{$track_name} or $group_on_field{$track_name} = $conf->code_setting($track_name => 'group_on');

    if (my $field = $group_on_field{$track_name}) {
      my $base = eval{$feature->$field};
      if (defined $base) {
	my $group_on_object = $group_on{$track_name}{$base} ||= Bio::Graphics::Feature->new(-start=>$feature->start,
											    -end  =>$feature->end,
											    -strand => $feature->strand,
											    -type =>$feature->primary_tag);
	$group_on_object->add_SeqFeature($feature);
	next;
      }
    }

    $track->add_feature($feature);
    $count{$track_name}++;
  }

  # fix up group-on fields
  for my $track_name (keys %group_on) {
    my $track = $track{$track_name};
    my $group_on = $group_on{$track_name} or next;
    $track->add_feature($_) foreach values %$group_on;
  }

  my $max_bump   = $self->bump_density;
  my $max_label  = $self->label_density;

  for my $track_name (keys %count) {
    my $track = $track{$track_name};

#    my $bump  = $self->do_bump($track_name,$options->{'features'}{$track_name}{options},$count{$track_name},$max_bump);
#    my $label = $self->do_label($track_name,$options->{'features'}{$track_name}{options},$count{$track_name},
#				$max_label,$segment->length);
#    my $description = $self->do_description($track_name,$options->{'features'}{$track_name}{options},$count{$track_name},
#				$max_label,$segment->length);
     
    #very ugly and kludgish, need to move to move all of render overview to RenderTracks.pm
    my $bump  = Bio::Graphics::Browser::RenderTracks::do_bump(undef,$track_name,$options->{'features'}{$track_name}{options},$count{$track_name},$max_bump,0,$conf);
    my $label = Bio::Graphics::Browser::RenderTracks::do_label(undef,$track_name,$options->{'features'}{$track_name}{options},$count{$track_name},
				$max_label,$segment->length,$conf);
    my $description = Bio::Graphics::Browser::RenderTracks::do_description(undef,$track_name,$options->{'features'}{$track_name}{options},$count{$track_name},
				$max_label,$segment->length,$conf);

    $track->configure(-bump  => $bump,
		      -label => $label,
		      -description => $description,
		     );
  }
  return \%track;
}


sub bump_density {
  my $self = shift;
  my $conf = $self->data_source;
  return $conf->setting(general=>'bump density')
      || $conf->setting('TRACK DEFAULTS' =>'bump density')
      || 50;
}

sub label_density {
  my $self = shift;
  my $conf = $self->data_source;
  return $conf->setting(general=>'label density')
      || $conf->setting('TRACK DEFAULTS' =>'label density')
      || 10;
}

#####MERGING PASTED CODE #######

sub _overview {
  my $self = shift;
  my ($region_name,$segment,$partial_segment,$track_options,$feature_files) = @_;
  my $gd;

  # Temporary kludge until I can figure out a more
  # sane way of rendering overview with SVG...
  my $image_class = 'GD';
  eval "use $image_class";
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

sub render_global_config {
  my $self = shift;
}

sub render_uploads {
  my $self = shift;
}

sub render_bottom {
  my $self = shift;
  my $features = shift;
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

# ========================= plugins =======================
sub init_plugins {
  my $self        = shift;
  my $source      = $self->data_source->name;
  my @plugin_path = shellwords($self->data_source->globals->plugin_path);

  my $plugins = $PLUGINS{$source} 
    ||= Bio::Graphics::Browser::PluginSet->new($self->data_source,$self->state,$self->language,@plugin_path);
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

sub write_auto {
  my $self = shift;
  my $result_set = shift;
  warn "write_auto() not implemented\n";
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

  my $current_span = defined $state->{stop} ? $state->{stop} - $state->{start} + 1 : 0;
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

# fetch_segments() actually should be deprecated, but it is stuck here
# because it is convenient for the regression tests
sub fetch_segments {
  my $self = shift;
  my $features = $self->fetch_features;
  my $segments = $self->features2segments($features);
  $self->plugins->set_segments($segments) if $self->plugins;
  $self->segments($segments);
}

sub features2segments {
  my $self     = shift;
  my $features = shift;
  my $refclass = $self->setting('reference class');
  my $db       = $self->db;
  my @segments = map {
    my $version = $_->isa('Bio::SeqFeatureI') ? undef : $_->version;
    $db->segment(-class => $refclass,
		 -name  => $_->ref,
		 -start => $_->start,
		 -stop  => $_->end,
		 -absolute => 1,
		 defined $version ? (-version => $version) : ())} @$features;
  return \@segments;
}

sub get_whole_segment {
  my $self = shift;

  my $segment = shift;
  my $factory = $segment->factory;

  # the segment class has been deprecated, but we still must support it
  my $class   = eval {$segment->seq_id->class} || eval{$factory->refclass};

  my ($whole_segment) = $factory->segment(-class=>$class,
					  -name=>$segment->seq_id);
  $whole_segment   ||= $segment;  # just paranoia
  $whole_segment;
}

sub fetch_features {
  my $self  = shift;
  my $db    = $self->db;
  my $state = $self->state;

  # avoid doing anything if no parameters and no autosearch set
  return if $self->setting('no autosearch') && !param();

  return unless defined $state->{name};
  my $features;

  # run any "find" plugins
  my $plugin_action  = $self->plugin_action || '';
  my $current_plugin = $self->current_plugin;
  if ($current_plugin && $plugin_action eq $self->tr('Find') || $plugin_action eq 'Find') {
    $features = $self->plugin_find($current_plugin,$state->{name});
  }
  else {
    $features = $self->search_db($state->{name});
  }
  return $features;
}

sub search_db {
  my $self = shift;
  my $name = shift;

  my $db    = $self->db;

  my ($ref,$start,$stop,$class) = $self->parse_feature_name($name);

  my $features = $self->lookup_features($ref,$start,$stop,$class,$name);
  return $features;
}

sub lookup_features {
  my $self  = shift;
  my ($name,$start,$stop,$class,$literal_name) = @_;
  my $refclass = $self->setting('reference class') || 'Sequence';

  my $db     = $self->db;
  my $divisor = $self->setting('unit_divider') || 1;
  $start *= $divisor if defined $start;
  $stop  *= $divisor if defined $stop;

  # automatic classes to try
  my @classes = $class ? ($class) : (split /\s+/,$self->setting('automatic classes')||'');

  my $features;

 SEARCHING:
  for my $n ([$name,$class,$start,$stop],[$literal_name,$refclass,undef,undef]) {

    my ($name_to_try,$class_to_try,$start_to_try,$stop_to_try) = @$n;

    # first try the non-heuristic search
    $features  = $self->_feature_get($db,$name_to_try,$class_to_try,$start_to_try,$stop_to_try);
    last SEARCHING if @$features;

    # heuristic fetch. Try various abbreviations and wildcards
    my @sloppy_names = $name_to_try;
    if ($name_to_try =~ /^([\dIVXA-F]+)$/) {
      my $id = $1;
      foreach (qw(CHROMOSOME_ Chr chr)) {
	my $n = "${_}${id}";
	push @sloppy_names,$n;
      }
    }

    # try to remove the chr CHROMOSOME_I
    if ($name_to_try =~ /^(chromosome_?|chr)/i) {
      (my $chr = $name_to_try) =~ s/^(chromosome_?|chr)//i;
      push @sloppy_names,$chr;
    }

    # try the wildcard  version, but only if the name is of significant length
    # IMPORTANT CHANGE: we used to put stars at the beginning and end, but this killed performance!
    push @sloppy_names,"$name_to_try*" if length $name_to_try > 3 and $name_to_try !~ /\*$/;

    for my $n (@sloppy_names) {
      for my $c (@classes) {
	$features = $self->_feature_get($db,$n,$c,$start_to_try,$stop_to_try);
	last SEARCHING if @$features;
      }
    }

  }

  unless (@$features) {
    # if we get here, try the keyword search
    $features = $self->_feature_keyword_search($literal_name);
  }

  return $features;
}

sub _feature_get {
  my $self = shift;
  my ($db,$name,$class,$start,$stop) = @_;

  my $refclass = $self->setting('reference class') || 'Sequence';
  $class ||= $refclass;

  my @argv = (-name  => $name);
  push @argv,(-class => $class) if defined $class;
  push @argv,(-start => $start) if defined $start;
  push @argv,(-end   => $stop)  if defined $stop;

  my @features;
  @features  = grep {$_->length} $db->get_feature_by_name(@argv)   if !defined($start) && !defined($stop);
  @features  = grep {$_->length} $db->get_features_by_alias(@argv) if !@features &&
    !defined($start) &&
      !defined($stop) &&
	$db->can('get_features_by_alias');

  @features  = grep {$_->length} $db->segment(@argv)               if !@features && $name !~ /[*?]/;
  return [] unless @features;

  # Deal with multiple hits.  Winnow down to just those that
  # were mentioned in the config file.
  my $types = $self->data_source->_all_types($db);
  my @filtered = grep {
    my $type    = $_->type;
    my $method  = eval {$_->method} || '';
    my $fclass  = eval {$_->class}  || '';
    $type eq 'Segment'      # ugly stuff accomodates loss of "class" concept in GFF3
      || $type eq 'region'
	|| $types->{$type}
	  || $types->{$method}
	    || !$fclass
	      || $fclass eq $refclass
		|| $fclass eq $class;
  } @features;

  # consolidate features that have same name and same reference sequence
  # and take the largest one.
  my %longest;
  foreach (@filtered) {
    my $n = $_->display_name.$_->abs_ref.(eval{$_->version}||'').(eval{$_->class}||'');
    $longest{$n} = $_ if !defined($longest{$n}) || $_->length > $longest{$n}->length;
  }

  return [values %longest];
}

sub _feature_keyword_search {
  my $self       = shift;
  my $searchterm = shift;

  # if they wanted something specific, don't give them non-specific results.
  return if $searchterm =~ /^[\w._-]+:/;

  # Need to untaint the searchterm.  We are very lenient about
  # what is accepted here because we wil be quote-metaing it later.
  $searchterm =~ /([\w .,~!@\#$%^&*()-+=<>?\/]+)/;
  $searchterm = $1;

  my $db = $self->db;
  my $max_keywords = $self->setting('max keyword results');
  my @matches;
  if ($db->can('search_attributes')) {
    my @attribute_names = shellwords ($self->setting('search attributes'));
    @attribute_names = ('Note') unless @attribute_names;
    @matches = $db->search_attributes($searchterm,\@attribute_names,$max_keywords);
  } elsif ($db->can('search_notes')) {
    @matches = $db->search_notes($searchterm,$max_keywords);
  }

  my @results;
  for my $r (@matches) {
    my ($name,$description,$score) = @$r;
    my ($seg) = $db->segment($name) or next;
    push @results,Bio::Graphics::Feature->new(-name   => $name,
					      -class  => $name->class,
					      -type   => $description,
					      -score  => $score,
					      -ref    => $seg->abs_ref,
					      -start  => $seg->abs_start,
					      -end    => $seg->abs_end,
					      -factory=> $db);

  }
  return \@results;
}

##################################################################3
#
# SHARED RENDERING CODE HERE
#
##################################################################3

#move to Datasource.pm along with overview_pad??
sub overview_ratio {
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

##### language stuff
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

# Returns the language code, but only if we have a translate table for it.
sub language_code {
  my $self = shift;
  my $lang = $self->language;
  my $table= $lang->tr_table($lang->language);
  return unless %$table;
  return $lang->language;
}

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
# my $zoom = $self->setting('fine zoom');
  my $zoom = $self->setting('default fine zoom');
  $zoom;
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


sub parse_feature_name {
  my $self = shift;
  my $name = shift;

  my ($class,$ref,$start,$stop);
  if ( ($name !~ /\.\./ and $name =~ /([\w._\/-]+):(-?[-e\d.]+),(-?[-e\d.]+)$/) or
      $name =~ /([\w._\/-]+):(-?[-e\d,.]+?)(?:-|\.\.)(-?[-e\d,.]+)$/) {
    $ref  = $1;
    $start = $2;
    $stop  = $3;
    $start =~ s/,//g; # get rid of commas
    $stop  =~ s/,//g;
  }

  elsif ($name =~ /^(\w+):(.+)$/) {
    $class = $1;
    $ref   = $2;
  }

  else {
    $ref = $name;
  }
  return ($ref,$start,$stop,$class);
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

################## image rendering code #############
sub render_detailview {
  my $self   = shift;
  my $seg    = shift;


  my $load_script = <<END;
  <script type="text/javascript"> // <![CDATA[
update_segment();
// ]]>
</script>
END

  print div($self->toggle('Details',div({-id=>'panels'},'Loading...'))),$load_script;
  
}


sub render_tracks {
  my $self = shift;
  my ($seg,$options) = @_;
  return unless $seg;
  my @labels = $self->detail_tracks;

  my $buttons = $self->globals->button_url;
  my $plus   = "$buttons/plus.png";
  my $minus  = "$buttons/minus.png";

  my $renderer = Bio::Graphics::Browser::RenderTracks->new(-segment  => $seg,
							   -source   => $self->data_source,
							   -settings => $self->state,
							   -renderer => $self);
  my $tracks   = $renderer->render_tracks(-tracks       => \@labels,
					  -third_party  => $self->remote_sources);

  my @results;
  for my $label ('__scale__',@labels) {
    my $title    = $self->setting($label=>'key');
    my $titlebar = $label eq '__scale__' ? ""
    	:	span({-class=>'titlebar'},
			img({-src=>$plus},img({-src=>$minus}),
			    $title." $seg"));
    next unless $tracks->{$label}; # not there for some reason
    my $gd        = $tracks->{$label}{gd};
    my $imagemap  = $tracks->{$label}{map};
    my $url       = $self->generate_image($gd);

    my $class   = $label eq '__scale__' ? 'scale' : 'track';
    push @results,div({id=>"track_${label}",-class=>$class},
		      center(
			     $titlebar,
			     img({-src=>$url,-border=>0,-usemap=>"#${label}_map"}),
			     $imagemap,
			    ),
		     );
    ##warn "results = @results";
  }
  my $state = $self->state;
  
  print div({-id=>'tracks'},@results),$self->drag_script('tracks'),$self->update_controls_script;
}


# returns the fragment we need to use the scriptaculous drag 'n drop code
sub drag_script {
  my $self = shift;
  my $div_name = shift;

  return <<END;
  <script type="text/javascript">
 // <![CDATA[
   Sortable.create(
     "$div_name",
     {
      constraint: 'vertical',
      tag: 'div',
      only: 'track',
      handle: 'titlebar',
      onUpdate: function() {
         var postData = Sortable.serialize('$div_name',{name:'label'});
         new Ajax.Request(document.URL,{method:'post',postBody:postData});
      }
     }
   );
 // ]]>
 </script>
END
}

sub update_controls_script {
  my $self = shift;
  my $state = $self->state;
  my $title = $self->data_source->description;
  $title   .= ": ".$self->seg->seq_id . ' ('.$self->unit_label($self->seg->length).')' if $self->seg;
  my $zoom = $self->zoomBar($self->seg,$self->whole_seg);
  $zoom =~ s/\n//g;

  return <<END;
  <script type="text/javascript">
 // <![CDATA[
document.searchform.name.value='$state->{name}';
document.getElementById('page_title').innerHTML='$title';
var zoom_menu = document.sliderform.span;
zoom_menu.parentElement.innerHTML='$zoom';
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

=head2 generate_image

  ($url,$path) = $browser->generate_image($gd)

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

  warn ((CGI::param('ref')||'')   . ':' .
	(CGI::param('start')||'') . '..'.
	(CGI::param('stop')||'')
	,
	" sig $signature\n") if DEBUG;

  # untaint signature for use in open
  $signature =~ /^([0-9A-Fa-f]+)$/g or return;
  $signature = $1;

  my ($uri,$path) = $self->globals->tmpdir($self->data_source->name.'/img');
  my $url         = sprintf("%s/%s.%s",$uri,$signature,$extension);
  my $imagefile   = sprintf("%s/%s.%s",$path,$signature,$extension);
  open (F,">$imagefile") || die("Can't open image file $imagefile for writing: $!\n");
  binmode(F);
  print F $data;
  close F;
  return $url;
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

