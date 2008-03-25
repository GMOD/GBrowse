package Bio::Graphics::Browser::RenderPanels;

use strict;
use warnings;

use Bio::Graphics;
use Digest::MD5 'md5_hex';
use Text::Shellwords 'shellwords';
use IO::File;

use CGI qw(:standard param escape unescape);

use constant GBROWSE_RENDER => 'gbrowse_render';  # name of the CGI-based image renderer
use constant TRUE => 1;
use constant DEBUG => 0;

use constant DEFAULT_KEYSTYLE => 'between';
use constant DEFAULT_EMPTYTRACKS => 0;
use constant PAD_DETAIL_SIDES    => 10;
use constant RULER_INTERVALS     => 20;
use constant PAD_OVERVIEW_BOTTOM => 5;

# when we load, we set a global indicating the LWP::Parallel::UserAgent is available
my $LPU_AVAILABLE;
my $STO_AVAILABLE;

sub new {
  my $class       = shift;
  my %options     = @_;
  my $segment       = $options{-segment};
  my $data_source   = $options{-source};
  my $page_settings = $options{-settings};
  my $renderer      = $options{-renderer};

  my $self  = bless {},ref $class || $class;
  $self->segment($segment);
  $self->source($data_source);
  $self->settings($page_settings);
  $self->page_renderer($renderer);
  return $self;
}

sub segment {
  my $self = shift;
  my $d = $self->{segment};
  $self->{segment} = shift if @_;
  return $d;
}

sub source {
  my $self = shift;
  my $d = $self->{source};
  $self->{source} = shift if @_;
  return $d;
}

sub page_renderer {
  my $self = shift;
  my $d    =$self->{renderer};
  $self->{renderer} = shift if @_;
  return $self->{renderer};
}

sub settings {
  my $self = shift;
  my $d = $self->{settings};
  $self->{settings} = shift if @_;
  return $d;
}

# NOTE: This is essentially the same as render_panels() in the 'stable' Browser.pm
# This renders the named tracks and returns the HTML needed to display them.
# Caching and distribution across multiple databases is implemented.
#
# input args:
#           (-labels         => [array of track labels],
#            -feature_files  => [third party annotations (Bio::DasI objects)],
#            -drag_and_drop  => turn on or off drag and drop tracks
#            -noscale        => suppress drawing the ruler
#           );
sub render_panels {
  my $self    = shift;
  my $args    = shift;

  my $source   = $self->source;
  my $settings = $self->settings;

  my $drag_n_drop         = $self->drag_and_drop($args->{drag_and_drop});
  $drag_n_drop            = 1;

  my $panels = $self->generate_panels($args);

  return $drag_n_drop ? $self->render_draggable_tracks($args,$panels)
                      : $self->render_composite_track($args,$panels);
}

sub use_renderfarm {
  my $self   = shift;

  $self->source->global_setting('renderfarm') or return;	#comment out to force remote rendering (kludge)

  $LPU_AVAILABLE = eval { require LWP::Parallel::UserAgent; } unless defined $LPU_AVAILABLE;
  $STO_AVAILABLE = eval { require Storable; 1; }              unless defined $STO_AVAILABLE;
  return 1 if $LPU_AVAILABLE && $STO_AVAILABLE;
  warn "The renderfarm setting requires the LWP::Parallel::UserAgent and Storable modules,
but one or both are missing. Reverting to local rendering.\n";
  return;
}

sub drag_and_drop {
  my $self     = shift;
  my $override = shift;
  return if defined $override && !$override;
  my $renderer = $self->page_renderer;
  return unless $renderer->setting('drag and drop'); # drag and drop turned off
  return if     $renderer->setting('postgrid');      # postgrid forces drag and drop off
  1;
}

sub generate_panels_remotely {
  my $self    = shift;
  my $tracks  = shift;
  my $options = shift;

  my $source = $self->source;

  my %remote;
  for my $track (@$tracks) {
    my $host  = $source->semantic_setting($track => 'remote renderer');
    $host   ||= $self->local_renderer_url;
    $remote{$host}{$track}++;
  }

  return $self->call_remote_renderers(\%remote);
}

sub render_draggable_tracks {
  my $self = shift;
  my ($args,$panels) = @_;

  my $globals  = $self->source->globals;

  my $buttons  = $globals->button_url;
  my $tmpdir   = $globals->tmpdir_path;
  my $settings = $self->settings;
  my $source   = $self->source;

  my $do_map   = $args->{do_map};
  my $button   = $args->{image_button};
  my $section  = $args->{section} || 'detail';

  my $plus     = "$buttons/plus.png";
  my $minus    = "$buttons/minus.png";
  my $help     = "$buttons/query.png";

  # get the pad image, which we use to fill up space between collapsed tracks
  my $pad_url  = $panels->{__pad__}{image};
  my ($pw,$ph) = @{$panels->{__pad__}}{'width','height'};

  my @result;
  for my $label ('__scale__',@{$args->{labels}}) {
    my ($url,$img_map,$width,$height) = @{$panels->{$label}}{qw(image map width height)};

    my $collapsed    = $settings->{track_collapsed}{$label};
    my $img_style    = $collapsed ? "display:none" : "display:inline";

    my $img = $button
      ? image_button(-src   => $url,
		     -name  => $section,
		     -id    => "${label}_image",
		     -style => $img_style
		    )
      : img({-src=>$url,
	     -usemap=>"#${label}_map",
	     -width => $width,
	     -id    => "${label}_image",
	     -height=> $height,
	     -border=> 0,
	     -name  => "${section}_${label}",
	     -alt   => "${label} $section",
	     -style => $img_style});

    my $class     = $label eq '__scale__' ? 'scale' : 'track';
    my $icon      = $collapsed ? $plus : $minus;

    if ($img_map) {
      my $config_click;
      if ($label =~ /^plugin:/) {
	my $help_url = "url:?plugin=".CGI::escape($label).';plugin_do=Configure';
	$config_click = "balloon.delayTime=0; balloon.showTooltip(event,'$help_url',1)";
      }

      elsif ($label =~ /^file:/) {
	my $url  = "?modify.${label}=".$self->tr('Edit');
	$config_click = "window.location='$url'";
      }

      else {
	my $help_url = "url:?configure_track=".CGI::escape($label);
	$help_url   .= ";rand=".rand(); # work around caching bugs... # if CGI->user_agent =~ /MSIE/;
	$config_click = "balloon.delayTime=0; balloon.showTooltip(event,'$help_url',1)";
      }


      my $title       = $label =~ /\w+:(.+)/ && $label !~ /:(overview|region)/  # a plugin
                        ? $1
                        : $source->setting($label=>'key') || $label; # configured

      my $titlebar    = span({-class=>$collapsed ? 'titlebar_inactive' : 'titlebar',-id=>"${label}_title"},
			     img({-src         =>$icon,
				  -id          => "${label}_icon",
				  -onClick     =>"collapse('$label')",
				  -style       => 'cursor:pointer',
				 }),
			     img({-src         => $help,
				  -style       => 'cursor:pointer',
				  -onmousedown => $config_click
				 }),
			     span({-class=>'draghandle'},$title)
			    );

      my $pad_img  = img({-src   => $pad_url,
			  -width => $pw,
			  -height=> $ph,
			  -border=> 0,
			  -id    => "${label}_pad",
			  -style => $collapsed ? "display:inline" : "display:none",
			 });

      (my $munge_label = $label) =~ s/_/%5F/g;  # freakin' scriptaculous uses _ as a delimiter!!!

      push @result, ($self->page_renderer->is_safari()
		     ?
		     "\n".div({-id=>"${section}_track_${munge_label}",-class=>$class},
			      $titlebar,
			      div({-align=>'center',-style=>'margin-top: -18px'},$img.$pad_img),
			      $img_map||'')
		     :
		     "\n".div({-id=>"${section}_track_${munge_label}",-class=>$class},
			      div({-align=>'center'},$titlebar.$img.$pad_img),
			      $img_map||'')
		     );

    }

    else {
      push @result,div({-id=>"track_${label}",-class=>$class},$img);
    }

  }

  return wantarray ? @result : join '',@result;
}

# BUG: This method should integrate all panels into a single image, but it doesn't.
sub render_composite_track {
  my $self   = shift;
  my ($args,$panels) = @_;
  die "Not implemented";

}

# This routine is called to hand off the rendering to a remote renderer. 
# The remote processor does not have to have a copy of the config file installed;
#  the entire DataSource object is sent to it in serialized form via
# POST. It returns a serialized hash consisting of the GD object and the imagemap.
# INPUT $renderers_hashref
#    $renderers_hashref->{$remote_url}{$track}
#
# RETURN
#    hash of { $track_label => { gd => $gd object, map => $imagemap } }
#
#
# POST outgoing arguments:
#    datasource => serialized Bio::Graphics::Browser::DataSource
#    settings   => serialized state hash (from the session)
#    tracks     => serialized list of track names to render
#
# POST incoming arguments
#    [[$track,$gd,$imagemap],[$track,$gd,$imagemap],...]
#
# reminder: segment can be found in the settings as $settings->{ref,start,stop,flip}
sub call_remote_renderers {
  my $self    = shift;
  my $renderers = shift;

  #eval { require 'HTTP::Request::Common' } unless HTTP::Request::Common->can('POST');
  eval { use HTTP::Request::Common; } unless HTTP::Request::Common->can('POST');

  my $dsn      = $self->source;
  my $settings = $self->settings;
  my $lang     = $self->page_renderer->language->{lang};

  # serialize the data source and settings
  my $s_dsn	= Storable::freeze($dsn);
  my $s_set	= Storable::freeze($settings);
  my $s_lang	= Storable::freeze($lang);

  my $ua = LWP::Parallel::UserAgent->new;
  $ua->in_order(0);
  $ua->nonblock(1);

  for my $url (keys %$renderers) {
    my @tracks  = keys %{$renderers->{$url}};
    #$url .= ".pl/";
    #$url = "http://cgi.sfu.ca/~hmokada/cgi-bin/gsoc/render.cgi";

    warn"calling remote rendering $url for tracks: @tracks";
    my $s_track  = Storable::freeze(\@tracks);

    my $request = POST ($url,
    		       [tracks     => $s_track,
			settings   => $s_set,
			datasource => $s_dsn,
			language   => $s_lang
    ]);

    my $error = $ua->register($request);
    if ($error) { warn "Could not send request to $url: ",$error->as_string }
  }

  my $timeout = $dsn->global_setting('timeout') || 20;
  my $results = $ua->wait($timeout);

  my %track_results;
  foreach (keys %$results) {
    my $response = $results->{$_}->response;
    unless ($response->is_success) {
      warn $results->request->uri,"; fetch failed: ",$response->status_line;
      next;
    }
    my $content = $response->content;
    my $tracks = Storable::thaw($content);
    for my $track_tuple (@$tracks) {
      my ($track_name,$gd,$imagemap) = @$track_tuple;
      $track_results{$track_name}{gd} = $gd;
      $track_results{$track_name}{map} = $imagemap;
    }
  }

  return \%track_results;
}

#moved from Render.pm
sub overview_ratio {
  my $self = shift;
  return 1.0;   # for now
}

sub overview_pad {
  my $self = shift;
  my $tracks = shift;

  my $source = $self->source;

  $tracks ||= [$source->overview_tracks];
  my $max = 0;
  foreach (@$tracks) {
    my $key = $source->setting($_=>'key');
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
  my $pad = $source->min_overview_pad;
  return ($pad,$pad) unless $max;
  return ($max * $image_class->gdMediumBoldFont->width + 3,$pad);
}

sub render_overview {
  my $self = shift;
  my ($region_name,$whole_segment,$segment,$state,$feature_files) = @_;
  my $gd;

  my $source   = $self->source;
  my $renderer = $self->page_renderer;

  #track option is same as state

  # Temporary kludge until I can figure out a more
  # sane way of rendering overview with SVG...
  my $image_class = 'GD';
  eval "use $image_class";

  my $width          = $state->{'width'} * $self->overview_ratio();
  my @tracks         = grep {$state->{'features'}{$_}{visible}} 
    $region_name eq 'region' ? $source->regionview_tracks : $source->overview_tracks;

  my ($padl,$padr)   = $self->overview_pad(\@tracks);

  my $panel = Bio::Graphics::Panel->new(-segment => $whole_segment,
					-width   => $width,
					-bgcolor => $source->global_setting('overview bgcolor')
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
    my $units         = $source->global_setting('units') || '';
    my $no_tick_units = $source->global_setting('no tick units');

    $panel->add_track($whole_segment,
		      -glyph     => 'arrow',
		      -double    => 1,
		      -label     => "\u$region_name\E of ".$whole_segment->seq_id,
		      -label_font => $image_class->gdMediumBoldFont,
		      -tick      => 2,
		      -units_in_label => $no_tick_units,
		      -units     => $units,
		      -unit_divider => $source->global_setting('unit_divider') || 1,
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
    $source->gd_cache_write($cache_path,$gd) if $cache_path;
  }

  my $rect_color = $panel->translate_color(
					   $source->global_setting('selection rectangle color' )||'red');
  my ($x1,$x2) = $panel->map_pt($segment->start,$segment->end);
  my ($y1,$y2) = (0,($gd->getBounds)[1]);
  $x2 = $panel->right-1 if $x2 >= $panel->right;
  my $pl = $panel->can('auto_pad') ? $panel->pad_left : 0;

  $gd->rectangle($pl+$x1,$y1,
		 $pl+$x2,$y2-1,
		 $rect_color);

  eval {$panel->finished};  # should quash memory leaks when used in conjunction with bioperl 1.4

  my $url       = $renderer->generate_image($gd);

  my $image = img({-src=>$url,-border=>0});#,-usemap=>"#${label}_map"});7;#overview($whole_segment,$segment,$page_settings,$feature_files);
  
}

#$self->_add_landmarks(\@tracks,$panel,$whole_segment,$state);
sub _add_landmarks {
  my $self = shift;
  my ($tracks_to_add,$panel,$segment,$options) = @_;
  my $source = $self->source;
  my @tracks = grep {$options->{'features'}{$_}{visible}} @$tracks_to_add;

  my (@feature_types,%type2track,%track);

  for my $overview_track (@tracks) {
    my @types = $source->label2type($overview_track);
    my $track = $panel->add_track(-glyph  => 'generic',
				  -height  => 3,
				  -fgcolor => 'black',
				  -bgcolor => 'black',
				  $source->style($overview_track),
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

    my $label = eval{$type2track{lc $feature->type}}
      || $type2track{lc $feature->primary_tag}
	|| eval{$type2track{lc $feature->method}}
	  || next;

    my $track = $track{$label} or next;

    # copy-and-pasted from details method. Not very efficient coding.
    exists $group_on_field{$label} or $group_on_field{$label} = $source->code_setting($label => 'group_on');

    if (my $field = $group_on_field{$label}) {
      my $base = eval{$feature->$field};
      if (defined $base) {
	my $group_on_object = $group_on{$label}{$base}
	  ||= Bio::Graphics::Feature->new(-start=>$feature->start,
					  -end  =>$feature->end,
					  -strand => $feature->strand,
					  -type =>$feature->primary_tag);
	$group_on_object->add_SeqFeature($feature);
	next;
      }
    }

    $track->add_feature($feature);
    $count{$label}++;
  }

  # fix up group-on fields
  for my $label (keys %group_on) {
    my $track = $track{$label};
    my $group_on = $group_on{$label} or next;
    $track->add_feature($_) foreach values %$group_on;
  }

  my $max_bump   = $self->bump_density;
  my $max_label  = $self->label_density;

  for my $label (keys %count) {
    my $track = $track{$label};

    my $do_bump  = $self->do_bump($label,$options->{'features'}{$label}{options},$count{$label},$max_bump);
    my $do_label = $self->do_label($label,$options->{'features'}{$label}{options},$count{$label},
				   $max_label,$segment->length);
    my $do_description = $self->do_description($label,$options->{'features'}{$label}{options},$count{$label},
					       $max_label,$segment->length);

    $track->configure(-bump  => $do_bump,
		      -label => $do_label,
		      -description => $do_description,
		     );
  }
  return \%track;
}

sub bump_density {
  my $self     = shift;
  my $conf = $self->source;
  return $conf->global_setting('bump density')
      || $conf->setting('TRACK DEFAULTS' =>'bump density')
      || 50;
}

sub label_density {
  my $self = shift;
  my $conf = $self->source;
  return $conf->global_setting('label density')
      || $conf->setting('TRACK DEFAULTS' =>'label density')
      || 10;
}

sub local_renderer_url {
  my $self     = shift;
  #my $self_uri = CGI::url(-absolute=>1);
  my $self_uri  = CGI::url(-full=>1);
  my $render    = GBROWSE_RENDER;
  $self_uri     =~ s/[^\/]+$/$render/;
  return $self_uri;
}

# This is entry point for rendering a series of tracks given their labels
# input is (\@track_names_to_render)
#
# output is $results hashref:
#   $results->{$track_label}{gd} = $gd_object
#   $results->{$track_label{map} = $imagemap
#
# sub render_locally {
#   my $self    = shift;
#   my $tracks  = shift;

#   my $source = $self->source;

#   my $lang    = $self->page_renderer->language;

#   # sort tracks by the database they come from
#   my (%track2db,%db2db);

#   for my $track (@$tracks) { 
#     my $db = eval { $source->open_database($track)};
#     unless ($db) { warn "Couldn't open database for $_: $@"; next; }
#     $track2db{$db}{$track}++;
#     $db2db{$db}  =  $db;  # cache database object
#   }

#   my %merge;

#   for my $dbname (keys %track2db) {
#     my $db        = $db2db{$dbname};              # database object
#     my @labels     = keys %{$track2db{$dbname}};   # all tracks that use this database
#     my $results_for_this_db = $self->generate_panels(-db      => $db,
# 						     -labels   => \@labels,
# 						     -options  => $options);
#     %merge = (%merge,%$results_for_this_db);
#   }

#   my %results;
#   for my $label (keys %merge) {
#     my $panel    = $merge{$label} or next;
#     my $gd       = $panel->gd;
#     my $imagemap = $label eq '__scale__' ? $self->make_centering_map($panel) 
#     	: $self->make_map($panel,$label,$lang);
#     $results{$label}{gd} = $gd;
#     $results{$label}{map} = $imagemap;
#   }

#   return \%results;
# }

sub make_map {
  my $self = shift;
  my ($boxes,$panel,$map_name,$trackmap,$first_box_is_scale) = @_;
  my @map = ($map_name);

  my $source = $self->source;
  my $render = $self->page_renderer;

  my $flip = $panel->flip;
  my $tips = $source->global_setting('balloon tips');
  my $use_titles_for_balloons = $source->global_setting('titles are balloons');

  my $did_map;

  local $^W = 0; # avoid uninit variable warnings due to poor coderefs

  if ($first_box_is_scale) {
    push @map, $self->make_centering_map(shift @$boxes,$flip,0,$first_box_is_scale);
  }

  foreach (@$boxes){
    next unless $_->[0]->can('primary_tag');

    my $label  = $_->[5] ? $trackmap->{$_->[5]} : '';

    my $href   = $self->make_link($_->[0],$panel,$label,$_->[5]);
    my $title  = unescape($self->make_title($_->[0],$panel,$label,$_->[5]));
    my $target = $self->make_link_target($_->[0],$panel,$label,$_->[5]);

    my ($mouseover,$mousedown,$style);
    if ($tips) {
      #retrieve the content of the balloon from configuration files
      # if it looks like a URL, we treat it as a URL.
      my ($balloon_ht,$balloonhover)     =
	$self->balloon_tip_setting('balloon hover',$label,$_->[0],$panel,$_->[5]);
      my ($balloon_ct,$balloonclick)     =
	$self->balloon_tip_setting('balloon click',$label,$_->[0],$panel,$_->[5]);

      my $sticky             = $source->setting($label,'balloon sticky');
      my $height             = $source->setting($label,'balloon height') || 300;

      if ($use_titles_for_balloons) {
	$balloonhover ||= $title;
      }

      $balloon_ht ||= 'balloon';
      $balloon_ct ||= 'balloon';

      if ($balloonhover) {
        my $stick = defined $sticky ? $sticky : 0;
        $mouseover = $balloonhover =~ /^(https?|ftp):/
	    ? "$balloon_ht.showTooltip(event,'<iframe width='+$balloon_ct.maxWidth+' height=$height frameborder=0 " .
	      "src=$balloonhover></iframe>',$stick)"
	    : "$balloon_ht.showTooltip(event,'$balloonhover',$stick)";
	undef $title;
      }
      if ($balloonclick) {
	my $stick = defined $sticky ? $sticky : 1;
        $style = "cursor:pointer";
	$mousedown = $balloonclick =~ /^(http|ftp):/
	    ? "$balloon_ct.delayTime=0; $balloon_ct.showTooltip(event,'<iframe width='+$balloon_ct.maxWidth+' height=$height " .
	      "frameborder=0 src=$balloonclick></iframe>',$stick,$balloon_ct.maxWidth)"
	    : "$balloon_ct.delayTime=0; $balloon_ct.showTooltip(event,'$balloonclick',$stick)";
	undef $href;
      }
    }
    my %attributes = (
		      title       => $title,
		      href        => $href,
		      target      => $target,
		      onmouseover => $mouseover,
		      onmousedown => $mousedown,
		      style       => $style
		      );

    my $ftype = $_->[0]->primary_tag || 'feature';
    my $fname = $_->[0]->display_name if $_->[0]->can('display_name');
    $fname  ||= $_->[0]->name if $_->[0]->can('name');
    $fname  ||= 'unnamed';
    $ftype = "$ftype:$fname";
    my $line = join("\t",$ftype,@{$_}[1..4]);
    for my $att (keys %attributes) {
      next unless defined $attributes{$att};
      $line .= "\t$att\t$attributes{$att}";
    }
    push @map, $line;
  }

  return \@map;

}

# this creates image map for rulers and scales, where clicking on the scale
# should center the image on the scale.
sub make_centering_map {
  my $self   = shift;
  my ($ruler,$flip,$label,$scale_map_type)  = @_;
  my @map = $label ? ($label) : ();

  return if $ruler->[3]-$ruler->[1] == 0;

  my $length = $ruler->[0]->length;
  my $offset = $ruler->[0]->start;
  my $end    = $ruler->[0]->end;
  my $scale  = $length/($ruler->[3]-$ruler->[1]);
  my $pl     = $ruler->[-1]->panel->pad_left;

  my $ruler_intervals = RULER_INTERVALS;

  if ($scale_map_type eq 'interval_map' && $length/RULER_INTERVALS > $self->get_max_segment) {
    my $max = $self->get_max_segment/5;  # usually a safe guess
    $ruler_intervals = int($length/$max);
  }

  # divide into RULER_INTERVAL intervals
  my $portion = ($ruler->[3]-$ruler->[1])/$ruler_intervals;
  my $ref    = $ruler->[0]->seq_id;
  my $source = $self->source;

  for my $i (0..$ruler_intervals-1) {
    my $x1 = int($portion * $i+0.5);
    my $x2 = int($portion * ($i+1)+0.5);

    my ($start,$stop);
    if ($scale_map_type eq 'centering_map') {
      # put the middle of the sequence range into the middle of the picture
      my $middle = $flip ? $end - $scale * ($x1+$x2)/2 : $offset + $scale * ($x1+$x2)/2;
      $start  = int($middle - $length/2);
      $stop   = int($start  + $length - 1);
    }
    elsif ($scale_map_type eq 'interval_map') {
      # center on the interval
      $start = int($flip ? $end - $scale * $x1 : $offset + $scale * $x1);
      $stop  = int($start + $portion * $scale);
    }

    $x1 += $pl;
    $x2 += $pl;

    my $url = "?ref=$ref;start=$start;stop=$stop";
    $url .= ";flip=1" if $flip;
    push @map, join("\t",'ruler',$x2, $ruler->[2], $x2, $ruler->[4], 
		    href  => $url, title => 'recenter', alt   => 'recenter');
  }
  return $label ? \@map : @map;
}

# finally....
# this is the routine that actually does the work!!!!

sub generate_panels {
  my $self  = shift;
  my $args  = shift;

  my $labels         = $args->{labels} || [];
  my $feature_files  = $args->{feature_files};
  my $use_renderfarm = $args->{use_renderfarm};
  my $noscale        = $args->{noscale};
  my $do_map         = $args->{do_map};
  my $cache_extra    = $args->{cache_extra} || [];
  my $section        = $args->{section}     || 'detail';

  my $settings       = $self->settings;
  my $segment        = $self->segment;
  my $length         = $segment->length;

  my $render         = $self->page_renderer;
  my $lang           = $render->language;
  my $source         = $self->source;

  # FIXME: this has to be set somewhere
  my $hilite_callback= undef;

  my @panel_args     = $self->create_panel_args($section,$args);

  $segment->factory->debug(1) if DEBUG;

  #---------------------------------------------------------------------------------
  # Track and panel creation

  # we create two hashes:
  #        the %panels hash maps label names to panels
  #        the %tracks hash maps label names to tracks within the panels
  my %panels;           # map label names to Bio::Graphics::Panel objects
  my %tracks;           # map label names to Bio::Graphics::Track objects
  my %track_args;        # map label names to track-specificic arguments (for caching)
  my %seenit;           # used to avoid possible upstream error of putting track on list multiple times
  my %results;          # hash of {$label}{gd} and {$label}{map}
  my %cached;           # list of labels that have cached data on disk
  my %cache_key;         # list that maps labels to cache keys

  my $panel_key = '__scale__';

  my @cache_args          = ($section,$panel_key,@panel_args,@$cache_extra,$do_map);
  $cache_key{$panel_key}  = $self->create_cache_key(@cache_args);
  $cached{$panel_key}     = $self->panel_is_cached($cache_key{$panel_key});

  unless ($cached{$panel_key}) {
    $panels{$panel_key}      = Bio::Graphics::Panel->new(@panel_args);

    $panels{$panel_key}->add_track($segment      => 'arrow',
				   -double       => 1,
				   -tick         => 2,
				   -label        => $args->{label_scale} ? $segment->seq_id : 0,
				   -units        => $source->global_setting('units') || '',
				   -unit_divider => $source->global_setting('unit_divider') || 1,
				  ) unless $noscale;
  }

  $panel_key                  = '__pad__';
  @cache_args                 = ($section,$panel_key,@panel_args,@$cache_extra);
  $cache_key{$panel_key}      = $self->create_cache_key(@cache_args);

  unless ($cached{$panel_key} = $self->panel_is_cached($cache_key{$panel_key})) {
    $panels{$panel_key}       = Bio::Graphics::Panel->new(@panel_args);
  }

  my %feature_file_offsets;

  for my $label (@$labels) {
    next if $seenit{$label}++; # this shouldn't happen, but let's be paranoid

    # if "hide" is set to true, then skip panel
    next if $source->semantic_setting($label=>'hide',$length);

    $track_args{$label} ||= [$self->create_track_args($label,$args)];

    $panel_key = $label;

    # get config data from the feature files
    my @extra_args          = eval {
      $feature_files->{$label}->types,
	$feature_files->{$label}->mtime,
      };
    $cache_key{$label}      = $self->create_cache_key(@panel_args,
						      @{$track_args{$label}},
						      @extra_args,
						      @$cache_extra,
						      $settings->{features}{$label}{options},
						     );

    next if $cached{$label} = $self->panel_is_cached($cache_key{$label});

    my @keystyle = (-key_style=>'between') 
      if $label =~ /^\w+:/ && $label !~ /:(overview|region)/;  # a plugin

    $panels{$panel_key}         = Bio::Graphics::Panel->new(@panel_args,@keystyle);

    $tracks{$label} = $panels{$panel_key}->add_track(@{$track_args{$label}})
      unless $cached{$panel_key};
  }

  #---------------------------------------------------------------------------------
  # Add features to the database
  my @labels_to_generate = grep {!$cached{$_}} @$labels;
  my %filters = map { my %conf =  $source->style($_);
		      $conf{'-filter'} ? ($_ => $conf{'-filter'})
			               : ()
		      } @labels_to_generate;
  $self->add_features_to_track(-labels    => \@labels_to_generate,
			       -tracks    => \%tracks,
			       -filters   => \%filters,
			       -segment   => $segment,
			       -fsettings => $settings->{features},
			      ) if @labels_to_generate;

  # ------------------------------------------------------------------------------------------
  # Add feature files, including remote annotations
  my $featurefile_select = $args->{featurefile_select} || $self->feature_file_select($section);
  for my $label (keys %$feature_files) {
    next if $cached{$label};
    my $file = $feature_files->{$label} or next;
    ref $file or next;
    $panel_key = $label;
    next unless $panels{$panel_key};
    $self->add_feature_file(
			    file       => $file,
			    panel      => $panels{$panel_key},
			    position   => $feature_file_offsets{$label} || 0,
			    options    => $settings->{features}{$label}{options},
			    select     => $featurefile_select,
			   );
  }

  # map tracks (stringified track objects) to corresponding labels
  my %trackmap = reverse %tracks;

  # uncached panels need to be generated and cached
  $args->{scale_map_type} ||= 'centering_map' unless $noscale;
  (my $map_name = $section) =~ s/^\?//;

  for my $label (keys %panels) {
    my $gd = $panels{$label}->gd;
    my $map  = !$do_map              ? (undef,undef)
	     : $label eq '__pad__'   ? (undef,undef)
	     : $label eq '__scale__' ? $self->make_centering_map(shift @{$panels{$label}->boxes},
								 $args->{flip},
								 $label,
								 $args->{scale_map_type},
								)
	     : $self->make_map(scalar $panels{$label}->boxes,
			       $panels{$label},
			       $label,
			       \%trackmap,
			       0);
    my $key = $cache_key{$label};
    $self->set_cached_panel($key,$gd,$map);
    eval {$panels{$label}->finished};
  }

  # cached panels need to be retrieved
  for my $label (keys %cached) {
    @{$results{$label}}{qw(image map width height file gd boxes)} = $self->get_cached_panel($cache_key{$label});
  }

  return \%results;
}

sub add_features_to_track {
  my $self = shift;
  my %args = @_;

  my $labels          = $args{-labels}    or die "programming error";
  my $segment         = $args{-segment}   or die "programming error";
  my $tracks          = $args{-tracks}    or die "programming error";
  my $filters         = $args{-filters}   or die "programming error";
  my $fsettings       = $args{-fsettings} or die "programming error";

  my $max_labels      = $self->label_density;
  my $max_bump        = $self->bump_density;

  my $length  = $segment->length;
  my $source  = $self->source;

  # sort tracks by the database they come from
  my (%db2label,%db2db);
  for my $label (@$labels) {
    my $db = eval { $source->open_database($label)};
    unless ($db) { warn "Couldn't open database for $_: $@"; next; }
    $db2label{$db}{$label}++;
    $db2db{$db}  =  $db;  # cache database object
  }

  my %iterators;
  for my $db (keys %db2db) {
    my @feature_types = map { $source->label2type($_,$length) } @$labels;
    my $iterator      = $self->get_iterator($db2db{$db},$segment,\@feature_types);
    $iterators{$iterator} = $iterator;
  }

  my (%groups,%feature_count,%group_pattern,%group_field);

  # The effect of this loop is to fetch a feature from each iterator in turn
  # using a queueing scheme. This allows streaming iterators to parallelize a
  # bit. This may not be worth the effort.
  while (keys %iterators) {
    for my $iterator (values %iterators) {

      my $feature;

      unless ($feature = $iterator->next_seq) {
	delete $iterators{$iterator};
	next;
      }

      my @labels = $source->feature2label($feature,$length);

      for my $l (@labels) {

	my $track = $tracks->{$l}  or next;
	$filters->{$l}->($feature) or next if $filters->{$l};
	$feature_count{$l}++;
	
	# ------------------------------------------------------------------------------------------
	# GROUP CODE
	# Handle name-based groupings.
	unless (exists $group_pattern{$l}) {
	  $group_pattern{$l} =  $source->code_setting($l => 'group_pattern');
	  $group_pattern{$l} =~ s!^/(.+)/$!$1! 
	    if $group_pattern{$l}; # clean up regexp delimiters
	}

	# Handle generic grouping (needed for GFF3 database)
	$group_field{$l} = $source->code_setting($l => 'group_on') unless exists $group_field{$l};
	
	if (my $pattern = $group_pattern{$l}) {
	  my $name = $feature->name or next;
	  (my $base = $name) =~ s/$pattern//i;
	  $groups{$l}{$base} ||= Bio::Graphics::Feature->new(-type   => 'group');
	  $groups{$l}{$base}->add_segment($feature);
	  next;
	}
	
	if (my $field = $group_field{$l}) {
	  my $base = eval{$feature->$field};
	  if (defined $base) {
	    $groups{$l}{$base} ||= Bio::Graphics::Feature->new(-start  => $feature->start,
							       -end    => $feature->end,
							       -strand => $feature->strand,
							       -type   => $feature->primary_tag);
	    $groups{$l}{$base}->add_SeqFeature($feature);
	    next;
	  }
	}

	$track->add_feature($feature);
      }
    }
  }

  # ------------------------------------------------------------------------------------------
  # fixups

  # fix up %group features
  # the former creates composite features based on an arbitrary method call
  # the latter is traditional name-based grouping based on a common prefix/suffix

  for my $l (keys %groups) {
    my $track  = $tracks->{$l};
    my $g      = $groups{$l} or next;
    $track->add_feature($_) foreach values %$g;
    $feature_count{$l} += keys %$g;
  }

  # now reconfigure the tracks based on their counts
  for my $l (keys %$tracks) {
    next unless $feature_count{$l};

    $fsettings->{$l}{options} ||= 0;

    my $count    = $feature_count{$l};
    my $limit    = $fsettings->{$l}{limit};
    $count       = $limit if defined($limit) && $limit > 0 && $limit < $count;
    my $pack_options  = $fsettings->{$l}{options};

    my $do_bump  = $self->do_bump($l,
				  $pack_options,
				  $count,
				  $max_bump,
				  $length);

    my $do_label = $self->do_label($l,
				   $pack_options,
				   $count,
				   $max_labels,
				   $length);

    my $do_description = $self->do_description($l,
					       $pack_options,
					       $count,
					       $max_labels,
					       $length);

    $tracks->{$l}->configure(-bump        => $do_bump,
			     -label       => $do_label,
			     -description => $do_description,
			      );
    $tracks->{$l}->configure(-connector  => 'none') if !$do_bump;
    $tracks->{$l}->configure(-bump_limit => $limit)
      if $limit && $limit > 0;
  }
}

sub get_iterator {
  my $self = shift;
  my ($db,$segment,$feature_types) = @_;

  my $db_segment;
  if (eval{$segment->factory eq $db}) {
    my $db_segment   = $segment;
  } else {
    ($db_segment) = $db->segment($segment->seq_id,$segment->start,$segment->end);
  }

  unless ($db_segment) {
    warn "Couldn't get segment $segment from database $db";
    return;
  }

  return $db_segment->get_feature_stream(-type=>$feature_types);
}


=head2 add_feature_file

Internal use: render a feature file into a panel

=cut

sub add_feature_file {
  my $self = shift;
  my %args = @_;

  my $file    = $args{file}    or return;
  my $options = $args{options} or return;
  my $select  = $args{select}  or return;

  my $name = $file->name || '';
  $options->{$name}      ||= 0;

  eval {
    $file->render(
		  $args{panel},
		  $args{position},
		  $options,
		  $self->bump_density,
		  $self->label_density,
		  $select);
  };

  $self->error("error while rendering ",$args{file}->name,": $@") if $@;
}


=head2 create_panel_args()

  @args = $self->create_panel_args($section,$args);

Return arguments need to create a Bio::Graphics::Panel.
$section is one of 'detail','overview', or 'region'
$args is a hashref that contains the keys:

   keystyle
   title
   image_class
   postgrid
   background

=cut

sub create_panel_args {
  my $self               = shift;
  my ($section,$args) = @_;

  my $segment       = $self->segment;
  my ($seg_start,$seg_stop,$flip) = $self->segment_coordinates($segment,
							       $args->{flip});

  my $image_class = $args->{image_class} || 'GD';
  eval "use $image_class" unless "${image_class}::Image"->can('new');

  my $render   = $self->page_renderer;
  my $settings = $self->settings;

  my $keystyle = $self->drag_and_drop($args->{drag_n_drop})
                 ? 'none'
		 : $args->{keystyle} || $render->setting('keystyle') || DEFAULT_KEYSTYLE;

  my @pass_thru_args = map {/^-/ ? ($_=>$args->{$_}) : ()} keys %$args;
  my @argv = (
	      -grid         => 1,
	      -start        => $seg_start,
	      -end          => $seg_stop,
	      -stop         => $seg_stop,  #backward compatibility with old bioperl
	      -key_color    => $render->setting('key bgcolor')     || 'moccasin',
	      -bgcolor      => $render->setting('detail bgcolor')  || 'white',
	      -width        => $settings->{width},
	      -key_style    => $keystyle,
	      -empty_tracks => $render->setting('empty_tracks')    || DEFAULT_EMPTYTRACKS,
	      -pad_top      => $args->{title} ? $image_class->gdMediumBoldFont->height : 0,
	      -image_class  => $image_class,
	      -postgrid     => $args->{postgrid}   || '',
	      -background   => $args->{background} || '',
	      -truecolor    => $render->setting('truecolor') || 0,
	      @pass_thru_args,   # position is important here to allow user to override settings
	     );

  push @argv, -flip => 1 if $flip;
  my $p  = $self->image_padding;
  my $pl = $render->setting('pad_left');
  my $pr = $render->setting('pad_right');
  $pl    = $p unless defined $pl;
  $pr    = $p unless defined $pr;

  push @argv,(-pad_left =>$pl, -pad_right=>$pr) if $p;


  push @argv,(
	      -pad_top     => 18,
	      -extend_grid => 1)
    if $self->drag_and_drop;

  return @argv;
}

sub image_padding {
  my $self = shift;
  my $render = $self->page_renderer;
  return defined $render->setting('image_padding') ? $render->setting('image_padding')
                                                   : PAD_DETAIL_SIDES;
}

=head2 segment_coordinates()

   ($start,$stop,$flip) = $self->segment_coordinates($segment,$flip)

Method to correct for rare case in which start and stop are flipped.

=cut

sub segment_coordinates {
  my $self    = shift;
  my $segment = shift;
  my $flip    = shift;

  # Create the tracks that we will need
  my ($seg_start,$seg_stop ) = ($segment->start,$segment->end);
  if ($seg_stop < $seg_start) {
    ($seg_start,$seg_stop)     = ($seg_stop,$seg_start);
    $flip = 1;
  }
  return ($seg_start,$seg_stop,$flip);
}

=head2 create_track_args()

  @args = $self->create_track_args($label,$args);

Return arguments need to create a Bio::Graphics::Track.
$label is a config file stanza label for the track.

=cut

sub create_track_args {
  my $self = shift;
  my ($label,$args) = @_;

  my $segment         = $self->segment;
  my $lang            = $self->page_renderer->language;
  my $override        = $self->settings->{features}{$label}{override_settings} || {};   # user-set override settings for tracks
  my @override        = map {'-'.$_ => $override->{$_}} keys %$override;

  my $hilite_callback = $args->{hilite_callback};

  my $length = $segment->length;
  my $source = $self->source;

  my @default_args = (-glyph => 'generic');
  push @default_args,(-key   => $label)        unless $label =~ /^\w+:/;
  push @default_args,(-hilite => $hilite_callback) if $hilite_callback;

  my @args;
  if ($source->semantic_setting($label=>'global feature',$length)) {
    @args = ($segment,
	     @default_args,
	     $source->default_style,
	     $source->i18n_style($label,
			       $lang),
	     @override,
	    );
  } else {
    @args = (@default_args,
	     $source->default_style,
	     $source->i18n_style($label,
			       $lang,
			       $length),
	     @override,
	    );
  }
  return @args;
}

=head2 create_cache_key()

  $cache_key = $self->create_cache_key(@args)

Create a unique cache key for the given args.

=cut

sub create_cache_key {
  my $self = shift;
  my @args = map {$_ || ''} grep {!ref($_)} @_;  # the map gets rid of uninit variable warnings
  return md5_hex(@args);
}

sub get_cache_base {
  my $self            = shift;
  my ($key,$filename) = @_;
  my @comp        = $key =~ /(..)/g;
  my $rel_path    = join '/',$self->source,'panel_cache',@comp[0..2],$key;
  my ($uri,$path) = $self->source->tmpdir($rel_path);

  return wantarray ? ("$path/$filename","$uri/$filename") : "$path/$filename";
}

sub panel_is_cached {
  my $self  = shift;
  my $key   = shift;
  return if param('nocache');
  return unless (my $cache_time = $self->cache_time);
  my $size_file = $self->get_cache_base($key,'size');
  return unless -e $size_file;
  my $mtime    = (stat(_))[9];   # _ is not a bug, but an automatic filehandle
  my $hours_since_last_modified = (time()-$mtime)/(60*60);
  warn "cache_time is $cache_time, last modified = $hours_since_last_modified hours ago";
  return unless $hours_since_last_modified < $cache_time;
  warn "cache hit for $key";# if DEBUG;
  1;
}

sub cache_time {
  my $self = shift;
  my $ct   = $self->page_renderer->setting('cache time');
  return $ct if defined $ct;  # hours
  return 1;                   # cache for one hour by default
}

=head2 get_cached_panel()

  ($image_uri,$map,$width,$height) = $self->get_cached_panel($cache_key)

Return cached image url, imagemap data, width and height of image.

=cut

sub get_cached_panel {
  my $self = shift;
  my $key  = shift;

  my $map_file                = $self->get_cache_base($key,'map')   or return;
  my $size_file               = $self->get_cache_base($key,'size')  or return;
  my ($image_file,$image_uri) = $self->get_cache_base($key,'image') or return;

  # get map data
  my $map_data = [];
  if (-e $map_file) {
    my $f = IO::File->new($map_file) or return;
    while (my $line = $f->getline) {
      push @$map_data, $line;
    }
    $f->close;
  }

  # get size data
  my ($width,$height);
  if (-e $size_file) {
    my $f = IO::File->new($size_file) or return;
    chomp($width = $f->getline);
    chomp($height = $f->getline);
    $f->close;
  }

  my $base = -e "$image_file.png" ? '.png'
           : -e "$image_file.jpg" ? '.jpg'
	   : -e "$image_file.svg" ? '.svg'
           : '.gif';
  $image_uri  .= $base;
  $image_file .= $base;

  my $gd = GD::Image->new($image_file) unless $image_file =~ /svg$/;
  my $map_html  = $self->map_html(@$map_data);
  return ($image_uri,$map_html,$width,$height,$image_file,$gd,$map_data);
}



# Convert the cached image map data
# into HTML.
sub map_html {
  my $self = shift;
  my @data = @_;
  chomp @data;
  my $name = shift @data or return '';

  my $html  = qq(\n<map name="${name}_map" id="${name}_map">\n);
  for (@data) {
    my (undef,$x1,$y1,$x2,$y2,%atts) = split "\t";
    $x1 or next;
    my $coords = join(',',$x1,$y1,$x2,$y2);
    $html .= qq(<area shape="rect" coords="$coords" );
    for my $att (keys %atts) {
      $html .= qq($att="$atts{$att}" );
    }
    $html .= qq(/>\n);
  }
  $html .= qq(</map>\n);
  return $html;
}

sub set_cached_panel {
  my $self = shift;
  my ($key,$gd,$map_data) = @_;

  my $map_file                = $self->get_cache_base($key,'map')   or return;
  my $size_file               = $self->get_cache_base($key,'size')  or return;
  my ($image_file,$image_uri) = $self->get_cache_base($key,'image') or return;

  # write the map data 
  if ($map_data) {
    my $f = IO::File->new(">$map_file") or die "$map_file: $!";
    $f->print(join("\n", @$map_data),"\n");
    $f->close;
  }

  return unless $gd;

  # get the width and height and write the size data
  my ($width,$height) = $gd->getBounds;
  my $f = IO::File->new(">$size_file") or die "$size_file: $!";
  $f->print($width,"\n");
  $f->print($height,"\n");
  $f->close;

  my $image_data;

  if ($gd->can('svg')) {
    $image_file .= ".svg";
    $image_data = $gd->svg;
  }
  elsif ($gd->can('png')) {
    $image_file .= ".png";
    $image_data = $gd->png;
  }

  elsif ($gd->can('gif')) {
    $image_file .= ".gif";
    $image_data  = $gd->gif;
  }

  elsif ($gd->can('jpeg')) {
    $image_file .= ".jpg";
    $image_data  = $gd->jpeg;
  }

  $f = IO::File->new(">$image_file") or die "$image_file: $!";
  $f->print($image_data);
  $f->close;

  return ($image_uri,$map_data,$width,$height,$image_file);
}

# this returns a coderef that will indicate whether an added (external) feature is placed
# in the overview, region or detailed panel. If the section name begins with a "?", then
# if not otherwise stated, the feature will be placed in this section.
sub feature_file_select {
  my $self             = shift;
  my $required_section = shift;

  my $undef_defaults_to_true;
  if ($required_section =~ /^\?(.+)/) {
    $undef_defaults_to_true++;
    $required_section = $1;
  }

  return sub {
    my $file  = shift;
    my $type  = shift;
    my $section = $file->setting($type=>'section') || $file->setting(general=>'section');
    return $undef_defaults_to_true if !defined$section;
    return $section =~ /$required_section/;
  };
}

sub do_bump {
  my $self = shift;
  my ($track_name,$option,$count,$max,$length) = @_;

  my $source              = $self->source;
  my $maxb              = $source->code_setting($track_name => 'bump density');
  $maxb                 = $max unless defined $maxb;

  my $maxed_out = $count <= $maxb;
  my $conf_bump = $source->semantic_setting($track_name => 'bump',$length);
  $option ||= 0;
  return defined $conf_bump ? $conf_bump
      :  $option == 0 ? $maxed_out
      :  $option == 1 ? 0
      :  $option == 2 ? 1
      :  $option == 3 ? 1
      :  $option == 4 ? 2
      :  $option == 5 ? 2
      :  0;
}

sub do_label {
  my $self = shift;
  my ($track_name,$option,$count,$max_labels,$length) = @_;

  my $source              = $self->source;

  my $maxl              = $source->code_setting($track_name => 'label density');
  $maxl                 = $max_labels unless defined $maxl;
  my $maxed_out         = $count <= $maxl;

  my $conf_label        = $source->semantic_setting($track_name => 'label',$length);
  $conf_label           = 1 unless defined $conf_label;

  $option ||= 0;
  return  $option == 0 ? $maxed_out && $conf_label
        : $option == 3 ? $conf_label || 1
	: $option == 5 ? $conf_label || 1
        : 0;
}

sub do_description {
  my $self = shift;
  my ($track_name,$option,$count,$max_labels,$length) = @_;

  my $source              = $self->source;

  my $maxl              = $source->code_setting($track_name => 'label density');
  $maxl                 = $max_labels unless defined $maxl;
  my $maxed_out         = $count <= $maxl;

  my $conf_description  = $source->semantic_setting($track_name => 'description',$length);
  $conf_description     = 0 unless defined $conf_description;
  $option ||= 0;
  return  $option == 0 ? $maxed_out && $conf_description
        : $option == 3 ? $conf_description || 1
        : $option == 5 ? $conf_description || 1
        : 0;
}

# override make_link to allow for code references
sub make_link {
  my $self     = shift;
  my ($feature,$panel,$label,$track)  = @_;

  my $data_source = $self->source;
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
  my $source = $self->source;

  my ($title,$key) = ('','');

 TRY: {
    if ($label && $label->isa('Bio::Graphics::FeatureFile')) {
      $key = $label->name;
      $title = $label->make_title($feature) or last TRY;
      return $title;
    }

    else {
      $label     ||= $source->feature2label($feature) or last TRY;
      $key       ||= $source->setting($label,'key') || $label;
      $key         =~ s/s$//;
      $key         = $feature->segment->dsn if $feature->isa('Bio::Das::Feature');  # for DAS sources

      my $link     = $source->code_setting($label,'title')
	|| $source->code_setting('TRACK DEFAULTS'=>'title')
	  || $source->code_setting(general=>'title');
      if (defined $link && ref($link) eq 'CODE') {
	$title       = eval {$link->($feature,$panel,$track)};
	$self->_callback_complain($label=>'title') if $@;
	return $title if defined $title;
      }
      return $source->link_pattern($link,$feature) if $link && $link ne 'AUTO';
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
  my $source = $self->source;

  if ($feature->isa('Bio::Das::Feature')) { # new window
    my $dsn = $feature->segment->dsn;
    $dsn =~ s/^.+\///;
    return $dsn;
  }

  $label    ||= $source->feature2label($feature) or return;
  my $link_target = $source->code_setting($label,'link_target')
    || $source->code_setting('LINK DEFAULTS' => 'link_target')
    || $source->code_setting(general => 'link_target');
  $link_target = eval {$link_target->($feature,$panel,$track)} if ref($link_target) eq 'CODE';
  $source->_callback_complain($label=>'link_target') if $@;
  return $link_target;
}

sub balloon_tip_setting {
  my $self = shift;
  my ($option,$label,$feature,$panel,$track) = @_;
  $option ||= 'balloon tip';
  my $source = $self->source;
  my $value  = $source->code_setting($label=>$option);
  $value     = $source->code_setting('TRACK DEFAULTS' => $option) unless defined $value;
  $value     = $source->code_setting('general' => $option)        unless defined $value;

  return unless $value;
  my $val;
  my $balloon_type = 'balloon';

  if (ref($value) eq 'CODE') {
    $val = eval {$value->($feature,$panel,$track)};
    $source->_callback_complain($label=>$option) if $@;
  } else {
    $val = $source->link_pattern($value,$feature,$panel);
  }

  if ($val=~ /^\s*\[([\w\s]+)\]\s+(.+)/s) {
    $balloon_type = $1;
    $val          = $2;
  }
  # escape quotes
  $val =~ s/'/\\'/g;
  $val =~ s/"/&quot;/g;

  return ($balloon_type,$val);
}


1;

