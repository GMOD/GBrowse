package Bio::Graphics::Browser2::RenderPanels;
use strict;
use warnings;

use GD 'gdTransparent','gdStyled';

use Bio::Graphics;
use Digest::MD5 'md5_hex';
use Carp 'croak','cluck';
use Bio::Graphics::Browser2::Render;
use Bio::Graphics::Browser2::CachedTrack;
use Bio::Graphics::Browser2::Util qw[shellwords url_label];
use Bio::Graphics::Browser2::Render::Slave::Status;
use IO::File;
use Time::HiRes 'sleep','time';
use Data::Dumper;
use POSIX 'WNOHANG','setsid';
use CGI qw(:standard param escape unescape);

use constant TRUE  => 1;
use constant DEBUG => 0;
use constant DEBUGGING_RECTANGLES => 0;  # outline the imagemap
use constant BENCHMARK => 0;

use constant DEFAULT_EMPTYTRACKS => 0;
use constant PAD_DETAIL_SIDES    => 10;
use constant RULER_INTERVALS     => 20;
use constant PAD_OVERVIEW_BOTTOM => 5;
use constant TRY_CACHING_CONFIG  => 1;
use constant MAX_PROCESSES       => 4;

# when we load, we set a global indicating the LWP::UserAgent is available
my $LPU_AVAILABLE;
my $STO_AVAILABLE;

sub new {
  my $class       = shift;
  my %options     = @_;
  my $segment       = $options{-segment};
  my $whole_segment = $options{-whole_segment};
  my $region_segment= $options{-region_segment};
  my $data_source   = $options{-source};
  my $page_settings = $options{-settings};
  my $language      = $options{-language};
  my $render        = $options{-render};

  my $self  = bless {},ref $class || $class;
  $self->segment($segment);
  $self->whole_segment($whole_segment);
  $self->region_segment($region_segment);
  $self->source($data_source);
  $self->settings($page_settings);
  $self->language($language);
  $self->render($render);

  return $self;
}

sub segment {
  my $self = shift;
  my $d = $self->{segment};
  $self->{segment} = shift if @_;
  return $d;
}

sub whole_segment {
  my $self = shift;
  my $d = $self->{whole_segment};
  $self->{whole_segment} = shift if @_;
  return $d;
}

sub region_segment {
  my $self = shift;
  my $d = $self->{region_segment};
  $self->{region_segment} = shift if @_;
  return $d;
}

sub source {
  my $self = shift;
  my $d = $self->{source};
  $self->{source} = shift if @_;
  return $d;
}

sub settings {
  my $self = shift;
  my $d = $self->{settings};
  $self->{settings} = shift if @_;
  return $d;
}

sub language {
  my $self = shift;
  my $d = $self->{language};
  $self->{language} = shift if @_;
  return $d;
}

sub render {
  my $self = shift;
  my $d = $self->{render};
  $self->{render} = shift if @_;
  return $d;
}

# NOTE: This is essentially the same as render_panels() in the 'stable' Browser.pm
# This renders the named tracks and returns the HTML needed to display them.
# Caching and distribution across multiple databases is implemented.
#
# input args:
#           {labels             => [array of track labels],
#            external_features  => [third party annotations (Bio::DasI objects)],
#            deferred           => generate in background
#           };
# output
# if deferred => false...
#      { label1 => html1, label2 => html2...} where HTML is the <div> for the named track
#
# if deferred => true
#      { label1 => CachedTrack1, label2 => CachedTrack2...}
#       where CachedTrack is a Bio::Graphics::Panel::CachedTrack object that will eventually
#       receive the data. Poll this object for its data.
#
sub request_panels {
  my $self    = shift;
  my $args    = shift;

  my $data_destinations = $self->make_requests($args);
  my $render            = $args->{render};

  # sort the requests out into local and remote ones
  my ($local_labels,
      $remote_labels) = $self->sort_local_remote($data_destinations);

  warn "[$$] request_panels(): section = $args->{section}; local labels = @$local_labels, remote labels = @$remote_labels" if DEBUG;

  # If we don't call clone_databases early, then we can have
  # a race condition where the parent hits the DB before the child
  # NOTE: commented out because clone logic has changed - may need to reenable this
  # for postgresql databases
  # Bio::Graphics::Browser2::DataBase->clone_databases();

  my $do_local  = @$local_labels;
  my $do_remote = @$remote_labels;

  # In the case of a deferred request we fork.
  # Parent returns the list of requests.
  # Child processes the requests in the background.
  # If both local and remote requests are needed, then we
  # fork a second time and process them in parallel.
  if ($args->{deferred}) {

      # precache local databases into cache
      my $length = $self->segment->length;
      my $source = $self->source;
      for my $l (@$local_labels) {
	  my $db = eval { $source->open_database($l,$length)};
      }

      my $child = $render->fork();

      if ($child) {
	  warn "[$$] Forked new rendering panel $child for $args->{section}" if DEBUG;
	  return $data_destinations;
      }

      open STDIN, "</dev/null" or die "Couldn't reopen stdin";
      open STDOUT,">/dev/null" or die "Couldn't reopen stdout";

      if ( $do_local && $do_remote ) {
          if ( $render->fork() ) {
              $self->run_local_requests( $data_destinations,
					 $args,
					 $local_labels );
          }
          else {
              $self->run_remote_requests( $data_destinations, 
					  $args,
					  $remote_labels );
          }
      }
      elsif ($do_local) {
	  warn "[$$] run_local_requests (@$local_labels)" if DEBUG;
          $self->run_local_requests( $data_destinations, $args,$local_labels );
      }
      elsif ($do_remote) {
          $self->run_remote_requests( $data_destinations, $args,$remote_labels );
      }

      warn "[$$] $args->{section} RENDERER EXITING" if DEBUG;
      CORE::exit 0;
  }

  else { # not deferred
      $self->run_local_requests($data_destinations,$args,$local_labels);  
      $self->run_remote_requests($data_destinations,$args,$remote_labels);
      return $data_destinations;
  }
}

sub render_panels {
    my $self = shift;
    my $args = shift;
    delete $args->{deferred}; # deferred execution incompatible with this call
    my $requests = $self->request_panels($args);
    return $self->render_tracks($requests,$args);
}


# this method returns a hashref in which the keys are track labels
# and the values are hashrefs with the keys 'gd' and 'map'. The former
# is a GD object, and the latter is the raw map data.
# Raw map data is tab-delimited in the format
# <feature name><x1><y1><x2><y2><key1><value1><key2><value2>...
# use map_html() to make HTML out of the thing
sub render_track_images {
    my $self         = shift;
    my $args         = shift;

    delete $args->{deferred}; # deferred execution incompatible with this call
    my $requests = $self->request_panels($args);

    my %results;
    my %still_pending = map {$_=>1} keys %$requests;
    my $k     = 1.25;
    my $delay = 0.1;
    while (%still_pending) {
	for my $label (keys %$requests) {
	    my $data = $requests->{$label};
	    $data->cache_time(0) if $data->cache_time < 0;
	    next if $data->status eq 'PENDING';
	    next if $data->status eq 'EMPTY';
	    if ($data->status eq 'AVAILABLE') {
		my ($gd,$map)  = eval{($data->gd,$data->map)};
		$results{$label}{gd}  = $gd;
		$results{$label}{map} = $map;
	    }
	    delete $still_pending{$label};
	}
	sleep $delay if %still_pending;
	$delay *= $k; # sleep a little longer each time using an exponential backoff
    }
    return \%results;
}


# return a hashref in which the keys are labels and the values are
# CachedTrack objects that are ready to accept data.
sub make_requests {
    my $self   = shift;
    my $args   = shift;
    my $source = $self->source;
    my $settings=$self->settings;

    my $feature_files  = $args->{external_features};
    my $labels         = $args->{labels};

    warn "[$$] MAKE_REQUESTS, labels = ",join ',',@$labels if DEBUG;

    my $base        = $self->get_cache_base();
    my @panel_args  = $self->create_panel_args($args);
    my @cache_extra = @{ $args->{cache_extra} || [] };
    my %d;

    warn "panel_args = @panel_args, cache_extra=@cache_extra" if DEBUG;

    foreach my $label ( @{ $labels || [] } ) {

        my @track_args = $self->create_track_args( $label, $args );

	my (@filter_args,@featurefile_args,@subtrack_args);

	my $format_option = $settings->{features}{$label}{options};

	my $filter     = $settings->{features}{$label}{filter};
	@filter_args   = %{$filter->{values}} if $filter->{values};
	@subtrack_args = @{$settings->{subtracks}{$label}} 
	                 if $settings->{subtracks}{$label};
	my $ff_error;

        # get config data from the feature files
	(my $track = $label) =~ s/:(overview|region|details?)$//;
	if ($feature_files && exists $feature_files->{$track}) {

	    # some broken logic here...
	    my $feature_file = $feature_files->{$track} || $feature_files->{$label};

	    unless (ref $feature_file) { # upload problem!
		my $cache_object = Bio::Graphics::Browser2::CachedTrack->new(
		    -cache_base => $base,
		    -panel_args => \@panel_args,
		    -track_args => \@track_args,
		    -extra_args => [ @cache_extra, 
				     @filter_args, 
				     @featurefile_args, 
				     @subtrack_args,
				     $format_option, 
				     $label ],
		    );
    
		my $msg = eval {$args->{remotes}->error($track)};
		$cache_object->flag_error($msg || "Could not fetch data for $track");
		$d{$track} = $cache_object;
		next;
	    }
	    
	    # broken logic here?
	    # next unless $label =~ /:$args->{section}$/;
	    @featurefile_args =  eval {
		$feature_file->isa('Bio::Das::Segment')||$feature_file->types, 
		$feature_file->mtime;
	    };
	}

	warn "[$$] creating CachedTrack for $label, nocache = $args->{nocache}" if DEBUG;
	my $cache_time =  $args->{nocache}    ? -1
	                : $settings->{cache}  ? $source->cache_time
                        : -1;

        my $cache_object = Bio::Graphics::Browser2::CachedTrack->new(
            -cache_base => $base,
            -panel_args => \@panel_args,
            -track_args => \@track_args,
            -extra_args => [ @cache_extra, 
			     @filter_args, 
			     @featurefile_args,  
			     @subtrack_args, 
			     $format_option, 
			     $label ],
	    -cache_time => $cache_time
        );

        $d{$label} = $cache_object;
    }

    return \%d;
}

sub use_renderfarm {
  my $self   = shift;
  return $self->{use_renderfarm} if exists $self->{use_renderfarm};

  #comment out to force remote rendering (kludge)
  $self->source->global_setting('renderfarm') or return;	

  $LPU_AVAILABLE = eval { require LWP::UserAgent; }           unless defined $LPU_AVAILABLE;
  $STO_AVAILABLE = eval { require Storable; 1; }              unless defined $STO_AVAILABLE;
  $Storable::Deparse = 1;

  $self->{use_renderfarm} = $LPU_AVAILABLE && $STO_AVAILABLE;
  return $self->{use_renderfarm} if $self->{use_renderfarm};
  warn "The renderfarm setting requires the LWP::UserAgent and Storable modules,
but one or both are missing. Reverting to local rendering.\n";
  return;
}

sub drag_and_drop {
  my $self     = shift;
  my $override = shift;
  return if defined $override && !$override;
  my $source   = $self->source;
  return unless $source->global_setting('drag and drop'); # drag and drop turned off
  return if     $source->global_setting('postgrid');      # postgrid forces drag and drop off
  1;
}

# Returns the full HTML listing of all requested tracks.
sub render_tracks {
    my $self     = shift;
    my $requests = shift;
    my $args     = shift;
    my %result;

    for my $label ( keys %$requests ) {
        my $data   = $requests->{$label};
        my $gd     = eval{$data->gd} or next;
        my $map    = $data->map;
        my $titles = $data->titles;
        my $width  = $data->width;
        my $height = $data->height;
        my $url    = $self->source->generate_image($gd);

	# for debugging
        my $status = $data->status;

        $result{$label} = $self->wrap_rendered_track(
            label    => $label,
            area_map => $map,
            width    => $width,
            height   => $height,
            url      => $url,
	    titles   => $titles,
            status   => $status,
	    section  => $args->{section},
        );
    }
    
    return \%result;
 
}

# Returns the HMTL to show a track with controls, title, arrows, etc.
sub wrap_rendered_track {
    my $self   = shift;
    my %args   = @_;
    my $label  = $args{'label'};
    my $map    = $args{'area_map'};
    my $width  = $args{'width'};
    my $height = $args{'height'};
    my $url    = $args{'url'};
    my $titles = $args{'titles'};
  
    # track_type Used in register_track() javascript method
    my $track_type = $args{'track_type'} || 'standard';
    my $status = $args{'status'};    # for debugging

    my $buttons  = $self->source->globals->button_url;
    my $plus     = "$buttons/plus.png";
    my $minus    = "$buttons/minus.png";
    my $kill     = "$buttons/ex.png";
    my $share    = "$buttons/share.png";
    my $help     = "$buttons/query.png";
    my $download = "$buttons/download.png";
    my $configure= "$buttons/tools.png";
    my $menu 	 = "$buttons/menu.png";
    my $favicon  = "$buttons/fmini.png";
    my $favicon_2= "$buttons/fmini_2.png";
    my $add_or_remove = $self->language->translate('ADDED_TO') || 'Add track to favorites';
    
    my $settings = $self->settings;
    my $source   = $self->source;

    my $collapsed = $settings->{track_collapsed}{$label};
    my $img_style = $collapsed ? "display:none" : "display:inline";

    # commented out alt because it interferes with balloon tooltips is IE
    my $map_id = "${label}_map";

    # Work around bug in google chrome which is manifested by the <area> link information
    # on all EVEN reloads of the element by ajax calls. Weird.
    my $agent  = CGI->user_agent || '';
    $map_id   .= "_".int(rand(1000)) ;

    my $img = img(
        {   -src    => $url,
            -usemap => "#${map_id}",
            -width  => $width,
            -id     => "${label}_image",
            -height => $height,
            -border => 0,
            -name   => $label,
            -style  => $img_style
	    
        }
    );

    my $icon = $collapsed ? $plus : $minus;
    my $show_or_hide = $self->language->translate('SHOW_OR_HIDE_TRACK')
        || "Show or Hide";
    my $kill_this_track = $self->language->translate('KILL_THIS_TRACK')
	|| "Turn off this track.";
    my $share_this_track = $self->language->translate('SHARE_THIS_TRACK')
        || "Share this track";

    my $download_this_track = '';
    $download_this_track .= $self->language->translate('DOWNLOAD_THIS_TRACK')
        || "<b>Download this track</b>";

    my $configure_this_track = '';
    $configure_this_track .= $self->language->translate('CONFIGURE_THIS_TRACK')
        || "Configure this track";

    my $about_this_track = '';
    $about_this_track .= $self->language->translate('ABOUT_THIS_TRACK',$label)
        || "<b>About this track</b>";

    my $escaped_label = CGI::escape($label);

    # The inline config will go into a box 500px wide by 500px tall
    # scrollbars will appear if there is overflow. The box should shrink
    # to fit if the contents are smaller than 500 x 500
    my $config_click;
    if ( $label =~ /^plugin:/ ) {
        my $config_url = "url:?plugin=$escaped_label;plugin_do=Configure";
        $config_click
            = "GBox.showTooltip(event,'$config_url',true)";
    }

    elsif ( $label =~ /^file:/ ) {
	my $escaped_file = CGI::escape($label);
	$config_click    = qq[Controller.edit_upload('$escaped_file')];
    }

    else {
        my $config_url = "url:?action=configure_track;track=$escaped_label";
        $config_click
            = "GBox.showTooltip(event,'$config_url',true)";
    }

    my $help_url       = "url:?action=cite_track;track=$escaped_label";
    my $help_click     = "GBox.showTooltip(event,'$help_url',1)"; 

    

    my $download_click = "GBox.showTooltip(event,'url:?action=download_track_menu;track=$escaped_label;view_start='+TrackPan.get_start()+';view_stop='+TrackPan.get_stop(),true)" unless $label =~ /^(http|ftp)/;

    my $title;
    if ($label =~ /^file:/) {
	$title = $label;
    }
    elsif ($label =~ /^(http|ftp):/) {
	$title = url_label($label);

    }
    elsif ($label =~ /^plugin/) {
	$title = $self->render->plugin_name($label);
    }
    else {
	(my $l = $label) =~ s/:\w+$//;
	$title = $source->setting( $label => 'key') || $l;
    }
    $title =~ s/:(overview|region|detail)$//;
   
    my $balloon_style = $source->global_setting('balloon style') || 'GBubble'; 
    my $favorite      = $settings->{favorites}{$label};
    my $starIcon      = $favorite ? $favicon_2 : $favicon;
    my $starclass     = $favorite ? "toolbarStar favorite" : "toolbarStar";
    (my $l = $label) =~ s/:detail$//;
    my $fav_click      =  "toggle_titlebar_stars('$l')";

    my @images = (
        $fav_click ? img({   	-src         => $starIcon,
				-id          =>"barstar_${l}",
				-class       => $starclass,
				-style       => 'cursor:pointer',
				-onmousedown => $fav_click,
				$self->if_not_ipad(-onMouseOver => "$balloon_style.showTooltip(event,'$add_or_remove')"),
			    })
	              : '',
	img({   -src         => $icon, 
                -id          => "${label}_icon",
                -onClick     =>  "collapse('$label')",
                -style       => 'cursor:pointer',
		$self->if_not_ipad(-onMouseOver => "$balloon_style.showTooltip(event,'$show_or_hide')"),
            }
        ),

	img({   -src         => $kill,
                -id          => "${label}_kill",
		-onClick     => "ShowHideTrack('$l',false)",
                -style       => 'cursor:pointer',
                $self->if_not_ipad(-onMouseOver => "$balloon_style.showTooltip(event,'$kill_this_track')"),
            }
        ),
        img({   -src   => $share,
                -style => 'cursor:pointer',
		-onMousedown => "Controller.get_sharing(event,'url:?action=share_track;track=$escaped_label',true)",
                $self->if_not_ipad(-onMouseOver =>
                    "$balloon_style.showTooltip(event,'$share_this_track')"),
            }
        ),

        $download_click ? img({   -src         => $download,
				  -style       => 'cursor:pointer',
				  -onmousedown => $download_click,
				  $self->if_not_ipad(-onMouseOver =>
						     "$balloon_style.showTooltip(event,'$download_this_track')"),
			      })
	                 : '',

        $config_click ? img({   -src         => $configure,
				-style       => 'cursor:pointer',
				-onmousedown => $config_click,
				$self->if_not_ipad(-onMouseOver => "$balloon_style.showTooltip(event,'$configure_this_track')"),
			    })
	              : '',

        img({   -src         => $help,
                 -style       => 'cursor:pointer',
                 -onmousedown => $help_click,
                 -onMouseOver =>
             "$balloon_style.showTooltip(event,'$about_this_track')",
             }
        )
	); 

    my $ipad_collapse = $collapsed ? 'Expand':'Collapse';
    my $cancel_ipad = 'Turn off';
    my $share_ipad = 'Share'; 
    my $configure_ipad = 'Configure';
    my $download_ipad = 'Download';
    my $about_ipad = 'About track';

    my $bookmark = 'Favorite'; 
    my $menuicon = img ({-src => $menu, 
			 -style => 'padding-right:15px;',},),
   
    my $popmenu = div({-id =>"popmenu_${title}", -style => 'display:none'},
		      div({-class => 'ipadtitle', -id => "${label}_title",}, $title ),
		      div({-class => 'ipadcollapsed', 
			   -id    => "${label}_icon", 
			   -onClick =>  "collapse('$label')",
			  },
			  div({-class => 'linkbg', 
			       -onClick => "swap(this,'Collapse','Expand')", 
			       -id => "${label}_expandcollapse", },$ipad_collapse)),
		      div({-class => 'ipadcollapsed',
			   -id => "${label}_kill",
			   -onClick     => "ShowHideTrack('$label',false)",
			  }, div({-class => 'linkbg',},
				 $cancel_ipad)),
		      div({-class => 'ipadcollapsed',  
			   -onMousedown => "Controller.get_sharing(event,'url:?action=share_track;track=$escaped_label',true)",}, 
			  div({-class => 'linkbg',},$share_ipad)),
		      div({-class => 'ipadcollapsed',  -
			       onmousedown => $config_click,}, div({-class => 'linkbg',},$configure_ipad)),
		      div({-class => 'ipadcollapsed',  
			   -onmousedown => $fav_click,}, 
			  div({-class => 'linkbg', -onClick => "swap(this,'Favorite','Unfavorite')"},$bookmark)),
		      div({-class => 'ipadcollapsed',  
			   -onmousedown => $download_click,}, 
			  div({-class => 'linkbg',},$download_ipad)),
		      div({-class => 'ipadcollapsed', 
			   -style => 'width:200px',  
			   -onmousedown => $help_click,}, 
			  div({-class => 'linkbg', -style => 'position:relative; left:30px;',},$about_ipad)),
 		  );
    
    # modify the title if it is a track with subtracks
    $self->select_features_menu($label,\$title);
    
    my $titlebar = 
	span(
		{   -class => $collapsed ? 'titlebar_inactive' : 'titlebar',
		    -id => "${label}_title",
				},

 	    $self->if_not_ipad(@images,),
	    $self->if_ipad(span({-class => 'menuclick',  -onClick=> "GBox.showTooltip(event,'load:popmenu_${title}')"}, $menuicon,),),	
	    span({-class => 'drag_region',},$title),

	);

    my $show_titlebar
        = ( ( $source->setting( $label => 'key' ) || '' ) ne 'none' );
    my $is_scalebar = $label =~ /scale/i;
    my $is_detail   = $label !~ /overview|region/i;
    $show_titlebar &&= !$is_scalebar;

    my $map_html = $self->map_html($map,$map_id);

    # the padding is a little bit of empty track that is displayed only
    # when the track is collapsed. Otherwise the track labels get moved
    # to the center of the page!
    my $pad     = $self->render_image_pad(
	$args{section}||Bio::Graphics::Browser2::DataSource->get_section_from_label($label),
	);
    my $pad_url = $self->source->generate_image($pad);
    my $pad_img = img(
        {   -src    => $pad_url,
            -width  => $pad->width,
            -border => 0,
            -id     => "${label}_pad",
            -style  => $collapsed ? "display:inline" : "display:none",
        }
    );

    my $overlay_div = '';

    # Add arrows for panning to details scalebar panel
    if ($is_scalebar && $is_detail) {
	my $style    = 'opacity:0.35;position:absolute;border:none;cursor:pointer';
        my $pan_left   =  img({
	    -style   => $style . ';left:5px',
	    -class   => 'panleft',
	    -src     => "$buttons/panleft.png",
	    -onClick => "Controller.scroll('left',0.5)"
	});

	my $pan_right  = img({ 
	    -style   => $style . ';right:5px',
	    -class   => 'panright',
	    -src     => "$buttons/panright.png",
	    -onClick => "Controller.scroll('right',0.5)",
	});
	
	my $scale_div = div( { -id => "detail_scale_scale", 
			       -style => "position:absolute; top:12px", }, "" );

        $overlay_div = div( { -id => "${label}_overlay_div", 
			      -style => "position:absolute; top:0px; width:100%; left:0px", }, $pan_left . $pan_right . $scale_div);
    }

    my $inner_div = div( { -id => "${label}_inner_div" }, $img . $pad_img ); #Should probably improve this


    my $subtrack_labels = join '',map {
	my ($label,$left,$top,undef,undef,$color) = @$_;
	$left -= $source->global_setting('pad_left') + PAD_DETAIL_SIDES;
	$left = 3 if $left < 3;
	my ($r,$g,$b,$a) = $color =~ /rgba\((\d+),(\d+),(\d+),([\d.]+)/;
	$a = 0.60 if $a > 0.75;
	my $fgcolor = $a <= 0.5 ? 'black' : ($r+$g+$b)/3 > 128 ? 'black' : 'white';
	div({-class=>'subtrack',-style=>"top:${top}px;left:${left}px;color:$fgcolor;background-color:rgba($r,$g,$b,$a)"},$label);
    } @$titles;

    my $html = div({-class=>'centered_block',
		 -style=>"position:relative;overflow:hidden"
		},
         ($show_titlebar ? $titlebar : '' ) . $popmenu .  $subtrack_labels . $inner_div . $overlay_div ) . ( $map_html || '' );
    return $html;
}

sub if_not_ipad {
    my $self = shift;
    my @args = @_;
    my $agent = CGI->user_agent || '';
    my $probably_ipad = $agent =~ /Mobile.+Safari/i;
    return if $probably_ipad;
    return @args;
}

sub if_ipad {
    my $self = shift;
    my @args = @_;
    my $agent = CGI->user_agent || '';
    my $probably_ipad = $agent =~ /Mobile.+Safari/i;
    return  if !$probably_ipad;
    return @args;
}
# This routine is called to hand off the rendering to a remote renderer. 
# The remote processor does not have to have a copy of the config file installed;
# the entire DataSource object is sent to it in serialized form via
# POST. It returns a serialized hash consisting of the GD object and the imagemap.
#
# INPUT $renderers_hashref
#    $renderers_hashref->{$remote_url}{$track}
#
# RETURN NOTHING (data will be stored in track cache for later retrieval)
#
# POST outgoing arguments:
#    datasource => serialized Bio::Graphics::Browser2::DataSource
#    settings   => serialized state hash (from the session)
#    tracks     => serialized list of track names to render
#
# POST result: serialized      { label1 => {image,map,width,height,file,gd,boxes}... }
#
# reminder: segment can be found in the settings as $settings->{ref,start,stop,flip}
sub run_remote_requests {
  my $self      = shift;
  my ($requests,$args,$labels) = @_;

  warn "[$$] run_remote_requests on @$labels" if DEBUG;
  my $render = $args->{render};

  my @labels_to_generate = @$labels;
  return unless @labels_to_generate;

  eval { use HTTP::Request::Common; } unless HTTP::Request::Common->can('POST');

  my $source     = $self->source;
  my $settings   = $self->settings;
  my $lang       = $self->language;
  my %env        = map {$_=>$ENV{$_}}    grep /^(GBROWSE|HTTP)/,keys %ENV;
  my %args       = map {$_=>$args->{$_}} grep /^-/,keys %$args;									#/

  $args{$_}  = $args->{$_} foreach ('section','image_class','cache_extra');

  # serialize the data source and settings
  my $s_set	= Storable::nfreeze($settings);
  my $s_lang	= Storable::nfreeze($lang);
  my $s_env	= Storable::nfreeze(\%env);
  my $s_args    = Storable::nfreeze(\%args);
  my $s_mtime   = 0;

  my $frozen_source = Storable::nfreeze($source);
  my $s_dsn;

  if (TRY_CACHING_CONFIG) {
      $s_dsn   = undef;
      $s_mtime = $source->mtime;
  } else {
      $s_dsn = Storage::nfreeze($source);
  }

  # sort requests by their renderers
  my $slave_status = Bio::Graphics::Browser2::Render::Slave::Status->new(
      $source->globals->slave_status_path
      );

  my %renderers;
  for my $label (@labels_to_generate) {
      my $url     = $source->remote_renderer or next;
      my @urls    = shellwords($url);
      $url        = $slave_status->select(@urls);
      warn "label => $url (selected)" if DEBUG;
      unless ($url) {
	  # the status monitor indicates that there are no "up" servers for this
	  # track, so flag an error immediately and don't attempt to retrieve.
	  # after a suitable time interval has passed, we will try this server again
	  $requests->{$label}->flag_error('no slave servers are marked up');
      } else {
	  $renderers{$url}{$label}++;
      }
  }

  my $ua = LWP::UserAgent->new;
  my $timeout = $source->global_setting('slave_timeout') 
      || $source->global_setting('global_timeout') 
      || 30;
  $ua->timeout($timeout);

  for my $url (keys %renderers) {

      my $child   = $render->fork();
      next if $child;

      my $total_time = time();

      # THIS PART IS IN THE CHILD
      my @labels   = keys %{$renderers{$url}};
      my $s_track  = Storable::nfreeze(\@labels);

      foreach (@labels) {
	  $requests->{$_}->lock();   # flag that request is in process
      }
  
    FETCH: {
	my $request = POST ($url,
			    Content_Type => 'multipart/form-data',
			    Content => [
				operation  => 'render_tracks',
				panel_args => $s_args,
				tracks     => $s_track,
				settings   => $s_set,
				datasource => $s_dsn||'',
				data_name  => $source->name,
				data_mtime => $s_mtime,
				language   => $s_lang,
				env        => $s_env,
			    ]);

	my $time = time();
	my $response = $ua->request($request);
	my $elapsed = time() - $time;

	warn "$url=>@labels: ",$response->status_line," ($elapsed s)" if DEBUG;

	if ($response->is_success) {
	    my $contents = Storable::thaw($response->content);
	    for my $label (keys %$contents) {
		my $map = $contents->{$label}{map}        
		  or die "Expected a map from remote server, but got nothing!";
		my $titles = $contents->{$label}{titles}        
		  or die "Expected titles from remote server, but got nothing!";
		my $gd2 = $contents->{$label}{imagedata}  
		  or die "Expected imagedata from remote server, but got nothing!";
		$requests->{$label}->put_data($gd2,$map,$titles);
	    }
	    $slave_status->mark_up($url);
	}
	elsif ($response->status_line =~ /REQUEST DATASOURCE/) {
	    $s_dsn	= Storable::nfreeze($source);
	    $s_mtime    = 0;
	    redo FETCH;
	}
	else {
	    my $uri = $request->uri;
	    my $response_line = $response->status_line;
	    $slave_status->mark_down($url);
	  
	    # try to recover from a transient slave failure; this only works
	    # right if all of the tracks there are multiple equivalent slaves for the tracks
	    my %urls    = map {$_=>1} 
  	                    map {
				shellwords($source->remote_renderer)
			    } @labels;
	    my $alternate_url = $slave_status->select(keys %urls);
	    if ($alternate_url) {
		warn "retrying fetch of @labels with $alternate_url";
		$url = $alternate_url;
		redo FETCH;
	    }

	    $response_line =~ s/^\d+//;  # get rid of status code
	    $requests->{$_}->flag_error($response_line) foreach keys %{$renderers{$uri}};
	}
      }

      my  $elapsed = time() - $total_time;
      warn "[$$] total_time = $elapsed s" if DEBUG;

      CORE::exit(0);  # from CHILD
  }
}

# Sort requests into those to be performed locally
# and remotely. Returns two arrayrefs (\@local_labels,\@remote_labels)
# Our algorithm is very simple. It is a remote request if the "remote renderer"
# option is set, local otherwise. This means that a "remote renderer" of "localhost"
# will be treated as a remote renderer request.
sub sort_local_remote {
    my $self     = shift;
    my $requests = shift;

    warn "requests = ",join ' ',keys %$requests if DEBUG;

    my @uncached;
    if ($self->settings->{cache}){
        @uncached = grep {$requests->{$_}->needs_refresh} keys %$requests;
    }
    else{
        @uncached = keys %$requests;
    }

    my $source         = $self->source;
    my $use_renderfarm = $self->use_renderfarm;

    unless ($use_renderfarm) {
	return (\@uncached,[]);
    }

    my $url;
    my %is_remote = map { $_ => ( 
			      !/plugin:/ &&
			      !/file:/   &&
			      !/^(ftp|http|das):/ &&
			      !$source->is_usertrack($_) &&
			      !$source->is_remotetrack($_) &&
			      (($url = $source->remote_renderer||0) &&
			      ($url ne 'none') &&
			      ($url ne 'local')))
                        } @uncached;

    my @remote    = grep {$is_remote{$_} } @uncached;
    my @local     = grep {!$is_remote{$_}} @uncached;

    return (\@local,\@remote);
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

# Handle the rendering of all three types of scale bars
sub render_scale_bar {
    my $self    = shift;
    my %args    = @_;
    my $segment = $args{'segment'};
    my $state   = $args{'state'};
    my $section = $args{'section'} || 'detail';
    my $gd;

    # Temporary kludge until I can figure out a more
    # sane way of rendering overview with SVG...
    my $image_class = 'GD';
    eval "use $image_class";

    my $source = $self->source;

    my ( $wide_segment, $bgcolor, $pad_bottom, %add_track_extra_args, );

    if ( $section eq 'overview' ) {
        $wide_segment = $args{'whole_segment'} or return ( '', 0, 0 );
        %add_track_extra_args = (
            -bgcolor => $source->global_setting('overview bgcolor')
                || 'wheat',
            -pad_bottom => 0,
            -label      => $wide_segment->seq_id,
            -label_font => $image_class->gdMediumBoldFont,
        );
    }
    elsif ( $section eq 'region' ) {
        $wide_segment = $args{'region_segment'} or return ( '', 0, 0 );
        %add_track_extra_args = (
            -bgcolor => $source->global_setting('region bgcolor') || 'wheat',
            -pad_bottom => 0,
        );
    }
    else {
        $wide_segment         = $segment;
        %add_track_extra_args = (
            -bgcolor    => $source->global_setting('detail bgcolor') || 'wheat',
            -pad_top    => 18,
            -pad_bottom => 0,
            -label_font => $image_class->gdMediumBoldFont,
	    -label      => eval{$segment->seq_id.
				    ': '
				    .$self->source->unit_label($segment->length)
	    }||'', # intermittent bug here with undefined $segment
        );
    }

    my $flip = ( $section eq 'detail' and $state->{'flip'} ) ? 1 : 0;

    $add_track_extra_args{'-postgrid'} = $args{'postgrid'} if $args{'postgrid'};

    my @panel_args = $self->create_panel_args(
        {   section        => $section, 
            segment        => $wide_segment,
            flip           => $flip,
            %add_track_extra_args
        }
    );


    my $panel = Bio::Graphics::Panel->new( @panel_args, );

    my $width = ($section eq 'detail')? $self->render->get_detail_image_width($state) : $self->render->get_image_width($state);

    # no cached data, so do it ourselves
    unless ($gd) {
        my $units = $source->global_setting('units') || '';
        my $no_tick_units = $source->global_setting('no tick units');


        $panel->add_track(
             $wide_segment,
            -glyph          => 'arrow',
            -double         => 1,
            -tick           => 2,
            -units_in_label => $no_tick_units,
            -units          => $units,
            -unit_divider   => $source->unit_divider,
            %add_track_extra_args,
        );

	if (my $feats = $args{'tracks'}) {

	    my @feature_types = $feats->types;

	    for my $type (@feature_types) {
	    my $features = $feats->features($type);
	    my %options  = $feats->style($type);
	    $panel->add_track($features,%options);  
	    }

	}

        # add uploaded files that have the "(over|region)view" option set

        $gd = $panel->gd;
    }

    my ( $y1, $y2 ) = ( 0, ( $gd->getBounds )[1] );

    eval { $panel->finished }; # should quash memory leaks when used in conjunction with bioperl 1.4

    my $url    = $self->source->generate_image($gd);
    my $height = $y2 - $y1; # + 1;

    return ( $url, $height, $width, );
}

sub render_image_pad {
    my $self    = shift;
    my ($section,$segment) = @_;

    $segment ||= $section  eq 'overview'  ? $self->whole_segment
                 :$section eq 'region'    ? $self->region_segment
                 :$self->segment;

    my @panel_args  = $self->create_panel_args({
	section => $section,
	segment => $segment,
	}
	);
    my @track_args  = ();
    my @extra_args  = ($self->settings->{start},
		       $self->settings->{stop});
    my $cache = Bio::Graphics::Browser2::CachedTrack->new(
	-cache_base => $self->get_cache_base,
	-panel_args => \@panel_args,
	-track_args => \@track_args,
	-extra_args => \@extra_args,
        );
    unless ($cache->status eq 'AVAILABLE') {
	my $panel = Bio::Graphics::Panel->new(@panel_args);
	$cache->lock;
	my $gd = $panel->gd;
	$cache->put_data($gd,'',[]);
    }

    my $gd = $cache->gd;
    return $gd;
}

sub bump_density {
  my $self     = shift;
  my $conf = $self->source;
  my $bd = $conf->global_setting('bump density')
      || $conf->setting('TRACK DEFAULTS' =>'bump density')
      || 50;
  return int($bd * $self->details_mult);
}

sub label_density {
  my $self = shift;
  my $conf = $self->source;
  my $ld = $conf->global_setting('label density')
      || $conf->setting('TRACK DEFAULTS' =>'label density')
      || 10;
  return int($ld * $self->details_mult);
}

sub calculate_scale_size {
    my $self      = shift;
    my ($length,$width) = @_;

    # how long is 1/5 of the width?
    my $scale        = $length/$width;
    my $guesstimate  = $scale * ($width/5);

    # turn into multiples of 10
    my $exp  = 10 ** int log10($guesstimate);
    my $base = ($guesstimate/$exp);
    if    ($base < 1) { $base = 1 }
    elsif ($base < 2) { $base = 2 }
    elsif ($base < 5) { $base = 5 }
    else              { $base = 10};
    $guesstimate = $base * $exp;
    my $label    = $self->source->unit_label($guesstimate);

    return ($guesstimate, $label);
}

sub log10 { return eval {log(shift)/log(10)} || 0 }

# Deprecated. This method was used to add the scale to the detail scale track. This is now done in javascript.
sub make_scale_feature {
    my $self      = shift;
    my ($segment,$width) = @_;
    return unless $segment;

    my $length   = $segment->length;

    my ($guesstimate, $label) = $self->calculate_scale_size($length, $width);

    my $scale = $segment->length/$width;

    $label       .= ' '; # more attractive
    my $size     = $guesstimate/$scale;
    my $left     = ($width-$size)/2;
    my $start    = int (($segment->start + $segment->end)/2 - $guesstimate/2);
    my $end      = $start + $guesstimate - 1;

    return Bio::Graphics::Feature->new(-display_name => $label,
				       -start        => $start,
				       -end          => $end,
				       -seq_id       => $segment->seq_id);
}

sub make_map {
  my $self = shift;
  my ($boxes,$panel,$label,$trackmap,$first_box_is_scale) = @_;
  my @map = ($label);

  my $source = $self->source;

  my $length   = $self->segment->length;
  my $settings = $self->settings;
  my $flip     = $panel->flip;
  my ($track_dbid) = $source->db_settings($label,$length);

  local $^W = 0; # avoid uninit variable warnings due to poor coderefs

  push @map, $self->make_centering_map(shift @$boxes,$flip,0,$first_box_is_scale)
      if $first_box_is_scale;

  my $inline = $source->use_inline_imagemap($label,$length);
  my $inline_options = {};

  if ($inline) {
      $inline_options = {tips                    => $source->global_setting('balloon tips') && $settings->{'show_tooltips'} || 0,
			 summary                 => $source->show_summary($label,$length,$self->settings) || 0,
			 use_titles_for_balloons => $source->global_setting('titles are balloons') || 0,
			 balloon_style           => $source->global_setting('balloon style') || 'GBubble',
			 balloon_sticky          => $source->semantic_fallback_setting($label,'balloon sticky',$length) || 0,
			 balloon_height          => $source->semantic_fallback_setting($label,'balloon height',$length) || 300,
      }
  }

  foreach my $box (@$boxes){
      my $feature = $box->[0];
      next unless $feature->can('primary_tag');

      my $attributes = $inline ? $self->make_imagemap_element_inline($feature,$panel,$label,$box->[5],$inline_options)
	                       : $self->make_imagemap_element_callback($feature,$track_dbid);
      $attributes or next;
      my $fname = eval {$feature->display_name} || eval{$box->[0]->name} || 'unnamed';
      my $ftype = $feature->primary_tag || 'feature';
      $ftype   =  "$ftype:$fname";
      my $line = join("\t",$ftype,@{$box}[1..4]);
      for my $att (keys %$attributes) {
	  next unless defined $attributes->{$att} && length $attributes->{$att};
	  $line .= "\t$att\t$attributes->{$att}";
      }
      push @map, $line;
  }
  return \@map;
}

sub make_imagemap_element_callback {
    my $self = shift;
    my ($feature,$dbid) = @_;
    my $id       = eval {CGI::escape($feature->primary_id || $feature->name)};
    $id        ||= '*summary*' if eval {$feature->has_tag('coverage')};
    return unless $id;
    return {
        dbid        => $dbid,
        fid         => $id,
	href        => 'javascript:void(0)',
	};
}

sub make_imagemap_element_inline {
    my $self    = shift;
    my ($feature,$panel,$label,$track,$options) = @_;

    my $tips                    = $options->{tips};
    my $use_titles_for_balloons = $options->{use_titles_for_balloons};
    my $balloon_style           = $options->{balloon_style};
    my $sticky                  = $options->{balloon_sticky};
    my $height                  = $options->{balloon_height};
    my $summary                 = $options->{summary};

    if ($summary) {
	return {onmouseover => $self->render->feature_summary_message('mouseover',$label),
		onmouseeown => $self->render->feature_summary_message('mousedown',$label),
		href        => 'javascript:void(0)',
		inline      => 1
	}
    }
    my $source = $self->source;
    my $href   = $self->make_link($feature,$panel,$label,$track);
    my $title  = unescape($self->make_title($feature,$panel,$label,$track));
    my $target = $self->make_link_target($feature,$panel,$label,$track);

    my ($mouseover,$mousedown,$style);

    if ($tips) {
      #retrieve the content of the balloon from configuration files
      # if it looks like a URL, we treat it as a URL.
      my ($balloon_ht,$balloonhover)     =
        $self->balloon_tip_setting('balloon hover',$label,$feature,$panel,$track,'inline');
      my ($balloon_ct,$balloonclick)     =
        $self->balloon_tip_setting('balloon click',$label,$feature,$panel,$track,'inline');

      $balloonhover ||= $title if $use_titles_for_balloons;
      $balloon_ht ||= $balloon_style;
      $balloon_ct ||= $balloon_ht;

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
            ? "$balloon_ct.showTooltip(event,'<iframe width='+$balloon_ct.maxWidth+' height=$height " .
              "frameborder=0 src=$balloonclick></iframe>',$stick,$balloon_ct.maxWidth)"
            : "$balloon_ct.showTooltip(event,'$balloonclick',$stick)";
        undef $href;
        undef $target;
      }
    }

    # workarounds to accomodate observation that some browsers don't respect cursor:pointer styles in
    # <area> tags unless there is an href defined
    $href    ||=     'javascript:void(0)';

    my %attributes = (
                      title       => $title,
                      href        => $href,
                      target      => $target,
                      onmouseover => $mouseover,
                      onmousedown => $mousedown,
                      style       => $style,
	              inline      => 1,
                      );

    return \%attributes;
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

# this is the routine that actually does the work!!!!
# input
#    arg1: request hashref 
#                 {label => Bio::Graphics::Browser2::CachedTrack}
#    arg2: arguments hashref
#                  {
#                    external_features => [list of external features, plugins]
#                    noscale           => (get rid of this?)
#                    do_map            => (get rid of this?)
#                    cache_extra       => (get rid of this?)
#                    section           => (get rid of this?)
#                   }
#    arg3: labels arrayref (optional - uses keys %$request otherwise)
#
# output
#    { label1 => $track_cache_object,
#      label2 => $track_cache_object....
#    }

sub run_local_requests {
    my $self     = shift;
    my $requests = shift;  # a hash of labels => Bio::Graphics::Browser2::CachedTrack objects
    my $args     = shift;
    my $labels   = shift;

    my $time     = time();

    warn "[$$] run_local_requests on @$labels" if DEBUG;

    $labels    ||= [keys %$requests];

    my $noscale        = $args->{noscale};
    my $do_map         = $args->{do_map};
    my $cache_extra    = $args->{cache_extra} || [];
    my $section        = $args->{section}     || 'detail';
    my $nocache        = $args->{nocache};
    my $render         = $args->{render};

    my $settings       = $self->settings;
    my $segment        = $self->segment;
    my $length         = $segment->length;

    my $source         = $self->source;
    my $lang           = $self->language;

    my $base           = $self->get_cache_base;

    my $feature_files  = $args->{external_features};

    # FIXME: this has to be set somewhere
    my $hilite_callback= undef;

    $segment->factory->debug(1) if DEBUG;

    #---------------------------------------------------------------------------------
    # Track and panel creation
    
    my %seenit;           # avoid error of putting track on list multiple times
    my %results;          # hash of {$label}{gd} and {$label}{map}
    my %feature_file_offsets;

    my @labels_to_generate = @$labels;
    my @ordinary_tracks    = grep {!$feature_files->{$_}} @labels_to_generate;
    my @feature_tracks     = grep {$feature_files->{$_} } @labels_to_generate;

    # create all the feature filters for each track
    my $filters = $self->generate_filters($settings,$source,\@labels_to_generate);

    my (%children,%reaped);

    local $SIG{CHLD} = sub {
    	while ((my $pid = waitpid(-1, WNOHANG)) > 0) {
    	    print STDERR "[$$] reaped render child $pid" if DEBUG;
    	    $reaped{$pid}++;
    	    delete $children{$pid} if $children{$pid};
    	}
    };
    local $SIG{TERM}    = sub { warn "[$$] GBrowse render process terminated"; exit 0; };

    my $max_processes = $self->source->global_setting('max_render_processes')
	|| MAX_PROCESSES;

    for my $label (@labels_to_generate) {

        # this shouldn't happen, but let's be paranoid
        next if $seenit{$label}++;

	# don't let there be more than this many processes 
	# running simultaneously
	while ((my $c = keys %children) >= $max_processes) {
	    warn "[$$] too many processes ($c), sleeping" if DEBUG;
	    sleep 1;
	}

	$render ||= 'Bio::Graphics::Browser2::Render';
	my $child = $render->fork();
	croak "Can't fork: $!" unless defined $child;
	if ($child) {
	    warn "[$$] Launched rendering process $child for $label" if DEBUG;
	    $children{$child}++ unless $reaped{$child}; # in case child was reaped before it was sown
	    next;
	}

	(my $base = $label) =~ s/:(overview|region|details?)$//;
	warn "label=$label, base=$base, file=$feature_files->{$base}" if DEBUG;

	my $multiple_tracks = $base =~ /^(http|ftp|file|das|plugin):/ 
	    || $source->code_setting($base=>'remote feature');

        my @keystyle = ( -key_style    => 'between',
	    )
            if $multiple_tracks;

	my $key = $source->setting( $base => 'key' ) || '' ;
	my @nopad = ();
        my $panel_args = $requests->{$label}->panel_args;
	
        my $panel
            = Bio::Graphics::Panel->new( @$panel_args, @keystyle, @nopad );

        my %trackmap;

	my $timeout         = $source->global_setting('global_timeout');
	
	my $oldaction;
	my $time = time();
	eval {
	    local $SIG{ALRM}    = sub { warn "alarm clock"; die "timeout" };
	    alarm($timeout);

	    $requests->{$label}->lock();
	    my ($gd,$map,$titles);

	    if (my $hide = $source->semantic_setting($label=>'hide',$self->segment_length)) {
		$gd     = $self->render_hidden_track($hide,$args);
		$map    = [];
		$titles = [];
	    }

	    else {

		if ( exists $feature_files->{$base} ) {
		    my $file = $feature_files->{$base};

		    # Add feature files, including remote annotations
		    my $featurefile_select = $args->{featurefile_select}
		    || $self->feature_file_select($section);
			
 		    if ( ref $file and $panel ) {
			$self->add_feature_file(
			    file     => $file,
			    panel    => $panel,
			    position => $feature_file_offsets{$label} || 0,
			    options  => {},
			    select   => $featurefile_select,
				);
			%trackmap = map { $_ => $file } @{ $panel->{tracks} || [] };
		    }
		}
		else {
		    my $track_args = $requests->{$label}->track_args;
		    my $track      = $panel->add_track(@$track_args);

		    warn "track_setup($label): ",time()-$time," seconds " if BENCHMARK;

		    # == populate the tracks with feature data ==
		    $self->add_features_to_track(
			-labels    => [ $label, ],
			-tracks    => { $label => $track },
			-filters   => $filters,
			-segment   => $segment,
			-fsettings => $settings->{features},
			);

		    warn "add_features($label): ",time()-$time," seconds " if BENCHMARK;

		    %trackmap = ($track=>$label);
		}

		# == generate the images and maps in background==
		$gd     = $panel->gd;
		warn "render gd($label): ",time()-$time," seconds " if BENCHMARK;

		$titles    = $panel->key_boxes;
		foreach (@$titles) {
		    my $index = $_->[5]->bgcolor;  # record track config bgcolor
		    my ($r,$g,$b) = $gd->rgb($index);
		    my $alpha     = 1;
		    if ($_->[5]->can('default_opacity')) {
			$alpha     = $_->[5]->default_opacity;
		    }
		    $_->[5]       =  "rgba($r,$g,$b,$alpha)";
		}  # don't want to store all track config data to cache!

		$self->debugging_rectangles($gd,scalar $panel->boxes)
		    if DEBUGGING_RECTANGLES;
		warn "render titles($label): ",time()-$time," seconds " if BENCHMARK;

		my $boxes = $panel->boxes;
		warn "boxes($label): ",time()-$time," seconds " if BENCHMARK;

		$map = $self->make_map( $boxes,
					$panel, $label,
					\%trackmap, 0 );
		warn "make_map($label): ",time()-$time," seconds " if BENCHMARK;
	    }

	    $requests->{$label}->put_data($gd, $map, $titles );
	};
	alarm(0);

	my $elapsed = time()-$time;
	warn "render($label): $elapsed seconds ", ($@ ? "(error)" : "(ok)") if BENCHMARK;
	
	if ($@) {
	    warn "RenderPanels error: $@";
	    if ($@ =~ /timeout/) {
		$requests->{$label}->flag_error('Timeout; Try turning off tracks or looking at a smaller region.');
	    } else {
		$requests->{$label}->flag_error($@);
	    }
	}
	CORE::exit 0; # in child;
    }
    warn "[$$] waiting for children" if DEBUG;
    if ($ENV{MOD_PERL}) {
	$SIG{CHLD}->(); # hacky workaround
    } else {
	sleep while %children;
    }
    warn "done waiting" if DEBUG;

    my $elapsed = time() - $time;
    warn "[$$] run_local_requests (@$labels): $elapsed seconds" if DEBUG;

    # make sure requests are populated
    # the "1" argument turns off expiration checking
    $requests->{$_}->get_data(1) foreach keys %$requests;  
}

sub render_hidden_track {
    my $self    = shift;
    my ($message,$args) = @_;
    $message    = 'Track not shown at this magnification' if $message eq '1';
    my $gd     = $self->render_image_pad($args->{section});
    my $font   = GD->gdMediumBoldFont;
    my $len    = $font->width * length($message);
    my ($wid)  = $gd->getBounds;
    my $black  = $gd->colorClosest(0,0,0);
    $gd->string(GD->gdMediumBoldFont,($wid-$len)/2,0,$message,$black);
    return $gd;
}

sub select_features_menu {
    my $self     = shift;
    my $label    = shift;
    my $titleref = shift;
    my $stt      = $self->subtrack_manager($label) or return;
    my ($selected,$total) = $stt->counts;
    my $escaped_label = CGI::escape($label);
    my $subtrack_over  = "GBubble.showTooltip(event,'url:?action=show_subtracks;track=$escaped_label',false)";
    my $subtrack_click = "GBox.showTooltip(event,'url:?action=select_subtracks;track=$escaped_label',true)";

    # modify the title to show that some subtracks are hidden
    $$titleref .= " ".span({-class       =>'clickable',
			   -onMouseOver  => "GBubble.showTooltip(event,'" . $self->language->translate('CLICK_MODIFY_SUBTRACK_SEL') . "')",
			   -onClick      => $subtrack_click
			  },
			  $self->language->translate('SHOWING_SUBTRACKS',$selected,$total));						#;
    
}

sub generate_filters {
    my $self     = shift;
    my ($settings,$source,$label_list) = @_;
    my %filters;
    for my $l (@$label_list) {
	my %conf =  $source->style($l);

	if (my $filter = $conf{'-filter'}) {
	    $filters{$l} = $filter;
	}

	else {
	    $filters{$l} = $self->subtrack_select_filter($settings,$l);
	}
    }
    return \%filters;
}

sub subtrack_select_filter {
    my $self     = shift;
    my ($settings,$label) = @_;

    # new method via SubtrackTable:
    my $stt = $self->subtrack_manager($label) or return;
    return $stt->filter_feature_sub;
}


# this routine is too long and needs to be modularized
sub add_features_to_track {
  my $self = shift;
  my %args = @_;

  my $labels          = $args{-labels}    or die "programming error";
  my $segment         = $args{-segment}   or die "programming error";
  my $tracks          = $args{-tracks}    or die "programming error";
  my $filters         = $args{-filters}   or die "programming error";
  my $fsettings       = $args{-fsettings} or die "programming error";

  warn "[$$] add_features_to_track @{$args{-labels}}" if DEBUG;

  my $max_labels      = $self->label_density;
  my $max_bump        = $self->bump_density;

  my $length  = $segment->length;
  my $source  = $self->source;

  # sort tracks by the database they come from
  my (%db2label,%db2db);
  for my $label (@$labels) {
    my $db = eval { $source->open_database($label,$length)};
    unless ($db) { warn "Couldn't open database for $label: $@"; next; }
    $db2label{$db}{$label}++;
    $db2db{$db}  =  $db;  # cache database object
  }

  my (%iterators,%iterator2dbid,%is_summary,%type2label);
  for my $db (keys %db2db) {
      my @labels           = keys %{$db2label{$db}};

      my (@full_types,@summary_types);
      for my $l (@labels) {
	  my @types = $source->label2type($l,$length) or next;
	  if ($source->show_summary($l,$length,$self->settings)) {
	      $is_summary{$l}++;
	      push @summary_types,@types;
	  } else {
	      push @full_types,@types;
	  }
	  $type2label{$_}{$l}++ foreach @types;
      }
      $self->{_type2label}=\%type2label;
      
      warn "[$$] RenderPanels->get_iterator(@full_types)"  if DEBUG;
      warn "[$$] RenderPanels->get_summary_iterator(@summary_types)" if DEBUG;
      if (@summary_types && 
	  (my $iterator = $self->get_summary_iterator($db2db{$db},$segment,\@summary_types))) {
	  $iterators{$iterator}     = $iterator;
	  $iterator2dbid{$iterator} = $source->db2id($db);
      }

      if (@full_types && (my $iterator = $self->get_iterator($db2db{$db},$segment,\@full_types))) {
	  $iterators{$iterator}     = $iterator;
	  $iterator2dbid{$iterator} = $source->db2id($db);
      }
  }

  my (%groups,%feature_count,%group_pattern,%group_field);

  # The effect of this loop is to fetch a feature from each iterator in turn
  # using a queueing scheme. This allows streaming iterators to parallelize a
  # bit. This may not be worth the effort.
  my (%feature2dbid,%classes,%limit_hit,%has_subtracks);

  while (keys %iterators) {
    for my $iterator (values %iterators) {

      my $feature;

      unless ($feature = $iterator->next_seq) {
	delete $iterators{$iterator};
	next;
      }

      $source->add_dbid_to_feature($feature,$iterator2dbid{$iterator});
      my @labels = $self->feature2label($feature);

      warn "[$$] $iterator->next_seq() returns $feature, will assign to @labels" if DEBUG;

      for my $l (@labels) {

          $l =~ s/:\d+//;  # get rid of semantic zooming tag

	  my $track = $tracks->{$l}  or next;

	  my $stt        = $self->subtrack_manager($l);
	  my $is_summary = $is_summary{$l};

	  $filters->{$l}->($feature) or next if $filters->{$l} && !$is_summary;
	  $feature_count{$l}++;

	  # -----------------------------------------------------------------------------
	  # GROUP CODE
	  # Handle name-based groupings.
	  unless (exists $group_pattern{$l}) {
	      $group_pattern{$l} =  $source->semantic_setting($l => 'group_pattern',$length);
	      $group_pattern{$l} =~ s!^/(.+)/$!$1! 
		  if $group_pattern{$l}; # clean up regexp delimiters
	  }
	  
	  # Handle generic grouping (needed for GFF3 database)
 	  $group_field{$l} = $source->semantic_setting($l => 'group_on',$length) 
	      unless exists $group_field{$l};
	  
	  if (my $pattern = $group_pattern{$l}) {
	      my $name = $feature->name or next;
	      (my $base = $name) =~ s/$pattern//i;
	      $groups{$l}{$base}  ||= Bio::Graphics::Feature->new(-type   => 'group',
								  -name   => $feature->display_name,
								  -strand => $feature->strand,
		  );
	      $groups{$l}{$base}->add_segment($feature);
	      next;
	  }
	
	  if (my $field = $group_field{$l}) {
	      my $base = eval{$feature->$field};
	      if (defined $base) {
		  $groups{$l}{$base} ||= Bio::Graphics::Feature->new(-name   => $feature->display_name,
								     -start  => $feature->start,
								     -end    => $feature->end,
								     -strand => $feature->strand,
								     -type   => $feature->primary_tag);
		  $groups{$l}{$base}->add_SeqFeature($feature);
		  next;
	      }
	  }

	  if (!$is_summary && $stt && (defined (my $id = $stt->feature_to_id_sub->($feature)))) {
	      $groups{$l}{$id} ||= Bio::Graphics::Feature->new(-type       => 'group',
							       -primary_id => $id,
							       -name       => $stt->id2label($id),
							       -start      => $segment->start,
							       -end        => $segment->end,
							       -seq_id     => $segment->seq_id,
		  );
	      $has_subtracks{$l}++;
	      $groups{$l}{$id}->add_segment($feature);
	      next;
	  }

	  $track->add_feature($feature);
      }
    }
  }
  warn "[$$] RenderPanels finished iteration fetch" if DEBUG;

  # ------------------------------------------------------------------------------------------
  # fixups

  # fix up %group features
  # the former creates composite features based on an arbitrary method call
  # the latter is traditional name-based grouping based on a common prefix/suffix

  for my $l (keys %groups) {
    my $track  = $tracks->{$l};
    my $g      = $groups{$l} or next;

    # add empty subtracks if needed
    if ($has_subtracks{$l} && !$source->semantic_setting($l => 'hide empty subtracks',$length)) {
	my $stt   = $self->subtrack_manager($l);
	my @ids   = $stt->selected_ids;
	$g->{$_} ||= Bio::Graphics::Feature->new(-type   => 'group',
						 -primary_id     => $_,
						 -name   => $stt->id2label($_),
						 -start  => $segment->start,
						 -end    => $segment->end,
						 -seq_id => $segment->seq_id) 
	    foreach @ids
    }

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
    $tracks->{$l}->configure(-label         => 0     ) if !$do_bump;
    $tracks->{$l}->configure(-bump_limit    => $limit)
      if $limit && $limit > 0;

    # essentially make label invisible if we are going to get the label position
    $tracks->{$l}->configure(-fontcolor   => 'white:0.0') 
	if $tracks->{$l}->parts->[0]->record_label_positions;

    if (eval{$tracks->{$l}->features_clipped}) { # may not be present in older Bio::Graphics
	my $max       = $tracks->{$l}->feature_limit;
	my $count     = $tracks->{$l}->feature_count;
	my $message   = $count == $self->source->globals->max_features ? 'FEATURES_CLIPPED_MAX' : 'FEATURES_CLIPPED';
	$tracks->{$l}->panel->key_style('between');
	$tracks->{$l}->configure(-key => $self->language->translate($message,$max,$count));
    }
  }

}

sub get_iterator {
  my $self = shift;
  my ($db,$segment,$feature_types) = @_;

  # The Bio::DB::SeqFeature::Store database supports correct
  # semantics for directly retrieving features that overlap
  # a range. All the others require you to get a segment first
  # and then to query the segment! This is a problem, because it
  # means that the reference sequence (e.g. the chromosome) is
  # repeated in each database, even if it isn't the primary one :-(
  my $max = $self->source->globals->max_features;
  if ($db->can('get_seq_stream')) {
      my @args = (-type   => $feature_types,
		  -seq_id => $segment->seq_id,
		  -start  => $segment->start,
		  -end    => $segment->end);
      push @args,(-max_features => $max) if $max > 0;  # some adaptors allow this
      return $db->get_seq_stream(@args);
  }

  my $db_segment;
  if (eval{$segment->factory||'' eq $db}) {
      $db_segment   = $segment;
  } else {
      ($db_segment) = $db->segment($segment->seq_id,$segment->start,$segment->end);
  }

  unless ($db_segment) {
    warn "Couldn't get segment $segment from database $db; id=",
       $self->source->db2id($db);
    return;
  }

  return $db_segment->get_seq_stream(-type=>$feature_types);
}

sub get_summary_iterator {
  my $self = shift;
  my ($db,$segment,$feature_types) = @_;

  my @args = (-type   => $feature_types,
	      -seq_id => $segment->seq_id,
	      -start  => $segment->start,
	      -end    => $segment->end,
	      -bins   => $self->get_detail_width_no_pad,
	      -iterator=>1,
      );
  return $db->feature_summary(@args);
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
	          $options->{$name},
		  $self->bump_density,
		  $self->label_density,
		  $select,
	          $self->segment,
	);
  };

  warn "error while rendering ",$args{file}->name,": $@" if $@;
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
  my $args               = shift;

  my $segment        = $args->{segment}        || $self->segment;
  my ($seg_start,$seg_stop,$flip) = $self->segment_coordinates($segment,
							       $args->{flip});

  my $image_class = $args->{image_class} || 'GD';
  eval "use $image_class" unless "${image_class}::Image"->can('new');

  my $settings = $self->settings;
  my $source   = $self->source;

  my $section  = $args->{section} || 'detail';

  my $postgrid = '';
  my $detail_start = $settings->{start};
  my $detail_stop  = $settings->{stop};
  my $h_region_str     = '';

  if (1 && ($section eq 'overview' or $section eq 'region')){
    $postgrid  = hilite_regions_closure(
	            [$detail_start,
		     $detail_stop,
		     $self->loaded_segment_fill(),
		     $self->loaded_segment_outline()
		    ]);
  }
  elsif ($section eq 'detail'){
    $postgrid = make_postgrid_callback($settings);
    $h_region_str = join(':', @{$settings->{h_region}||[]}); 
  }

  my $keystyle = 'none';

  my @pass_thru_args = map {/^-/ ? ($_=>$args->{$_}) : ()} keys %$args;
  my @argv = (
	      -grid         => $section eq 'detail' ? $settings->{'grid'} : 0,
              -seqid        => $segment->seq_id,
	      -start        => $seg_start,
	      -end          => $seg_stop,
	      -stop         => $seg_stop,  #backward compatibility with old bioperl
	      -key_color    => $source->global_setting('key bgcolor')      || 'moccasin',
	      -bgcolor      => $source->global_setting("$section bgcolor") || 'wheat',
              -width        => $section eq 'detail'? $self->get_detail_width_no_pad : $settings->{width},
	      -key_style    => $keystyle,
              -suppress_key => 1,
	      -empty_tracks => $source->global_setting('empty_tracks')    || DEFAULT_EMPTYTRACKS,
	      -pad_top      => $image_class->gdMediumBoldFont->height+2,
              -pad_bottom   => 3,
	      -image_class  => $image_class,
	      -postgrid     => $postgrid,
	      -background   => $args->{background} || '',
	      -truecolor    => $source->global_setting('truecolor') || 0,
	      -map_fonts_to_truetype    => $source->global_setting('truetype') || 0,
	      -extend_grid  => 1,
              -gridcolor    => $source->global_setting('grid color') || 'lightcyan',
              -gridmajorcolor    => $source->global_setting('grid major color') || 'cyan',
	      @pass_thru_args,   # position is important here to allow user to override settings
	     );

  push @argv, -flip => 1 if $flip;
  my $p  = $self->image_padding;
  my $pl = $source->global_setting('pad_left');
  my $pr = $source->global_setting('pad_right');
  $pl    = $p unless defined $pl;
  $pr    = $p unless defined $pr;

  push @argv,(-pad_left =>$pl, -pad_right=>$pr) if $p;

  return @argv;
}

sub image_padding {
  my $self   = shift;
  my $source = $self->source;
  return defined $source->global_setting('image_padding') 
      ? $source->global_setting('image_padding')
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

  return unless $segment;

  # Create the tracks that we will need
  my ($seg_start,$seg_stop ) = ($segment->start,$segment->end);
  if ($seg_stop < $seg_start) {
    ($seg_start,$seg_stop)     = ($seg_stop,$seg_start);
    $flip = 1;
  }
  return ($seg_start,$seg_stop,$flip);
}

# this returns semantically-correct override configuration
# as a hash ref
sub override_settings {
    my $self  = shift;
    my $label = shift;
    my $source            = $self->source;
    my $state             = $self->settings;
    my $length            = eval {$self->segment->length} || 0;
    my $is_summary        = $source->show_summary($label,$length,$state);
    my $semantic_override = Bio::Graphics::Browser2::Render->find_override_region(
	$state->{features}{$label}{semantic_override},
	$length);
    return $is_summary           ? $state->{features}{$label}{summary_override}
                                 : $semantic_override ? $state->{features}{$label}{semantic_override}{$semantic_override}
                                 : {};
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
  my $length          = $segment->length;
  my $source          = $self->source;
  my $lang            = $self->language;

  my $is_summary      = $source->show_summary($label,$length,$self->settings);
  my $overlaps        =    ($self->settings->{features}{$label}{options}||0) == 4
                        || ($source->semantic_setting($label => 'bump',$length)||'') eq 'overlap';

  my $override        = $self->override_settings($label);
  my @override        = map {'-'.$_ => $override->{$_}} keys %$override;

  push @override,(-feature_limit => $override->{limit}) if $override->{limit};
  push @override,(-opacity => 1.0) unless $overlaps;

  my @summary_args = ();
  if ($is_summary) {
      @summary_args = $source->Bio::Graphics::FeatureFile::setting("$label:summary") 
	  ? $source->i18n_style("$label:summary",$lang)
	  : (-glyph     => 'wiggle_density',
	     -height    => 15,
	     -min_score => 0,
	     -autoscale => 'local',
	  );
  }
  my $hilite_callback = $args->{hilite_callback};

  my @default_args = (-glyph => 'generic');
  push @default_args,(-key   => $label)        unless $label =~ /^\w+:/;
  push @default_args,(-hilite => $hilite_callback) if $hilite_callback;

  if (my $stt = $self->subtrack_manager($label)) {
      push @default_args,(-connector   => '');
      my $left_label = 
	  $source->semantic_setting($label=>'label_position',$length)||'' eq 'left';

      $left_label++ 
	  if $source->semantic_setting($label=>'label_transcripts',$length);

      my $group_label = $source->semantic_setting($label=>'glyph',$length) !~ /xyplot|wiggle|density|whisker/;

      push @default_args,(
	  -group_label          => $group_label||0,
	  -group_label_position => $left_label ? 'top' : 'left',
	  -group_subtracks      => !$overlaps,
      );
      push @default_args,$stt->track_args;
  }

  my @args;
  if ($source->semantic_setting($label=>'global feature',$length)) {
      eval { # honor the database indicated in the track config
	  my $db    = $self->source->open_database($label,$length);
	  my $class = eval {$segment->seq_id->class} || eval{$db->refclass};
	  ($segment)= $db->segment(-name  => $segment->seq_id,
				   -start => $segment->start,
				   -end   => $segment->end,
				   -class => $class);
      };
      warn $@ if $@;
      @args = ($segment,
	       @default_args,
	       $source->default_style,
	       $source->i18n_style($label,$lang),
	       @summary_args,
	       @override,
	  );
  } else {
    @args = (@default_args,
	     $source->default_style,
	     $source->i18n_style($label,$lang,$length),
	     @summary_args,
	     @override,
	    );
  }

  if (my $stt = $self->subtrack_manager($label)) {
      my $sub = $stt->sort_feature_sub;
      push @args,(-sort_order => $sub);
#      push @args,(-color_series => 1) if $overlaps;
  }

  return @args;
}

sub vis_length {
    my $self = shift;
    my $segment = $self->segment;
    my $length  = $segment->length;
    return $length/$self->details_mult;
}

sub subtrack_manager {
    my $self = shift;
    my $label = shift;
    return $self->{_stt}{$label} if exists $self->{_stt}{$label};
    return $self->{_stt}{$label} = undef
	if $self->source->show_summary($label,$self->vis_length,$self->settings);
    return $self->{_stt}{$label} = Bio::Graphics::Browser2::Render->create_subtrack_manager($label,
											    $self->source,
											    $self->settings);
}

sub debugging_rectangles {
  my $self = shift;
  my ($image,$boxes) = @_;
  my $red = $image->colorClosest(255,0,0);
  foreach (@$boxes) {
    my @rect = @{$_}[1,2,3,4];
    $image->rectangle(@{$_}[1,2,3,4],$red);
  }
}

sub get_cache_base {
    my $self = shift;
    my $path = $self->source->globals->cache_dir($self->source->name);
    return $path;
}

# Returns the HTML image map from the cached image map data.
sub map_html {
  my $self = shift;
  my $map  = shift;
  my $id   = shift;

  my @data = @$map;

  my $name = shift @data or return '';
  $id    ||= "${name}_map";

  my $html  = qq(\n<map name="$id" id="$id">\n);
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

# this returns a coderef that will indicate whether an added (external) feature is placed
# in the overview, region or detailed panel. It is necessary to avoid one section's features
# from being placed in another section's track.
sub feature_file_select {
  my $self             = shift;
  my $required_section = shift;

  my $undef_defaults_to_true;
  if ($required_section =~ /detail/) {
    $undef_defaults_to_true++;
  }

  return sub {
      my $file    = shift;
      my $type    = shift;

      my $section = $file->setting($type=>'section')
	            || $file->setting(general=>'section');
      my ($modifier) = $type =~ /:(overview|region}detail)$/;
      $section     ||= $modifier;

      return $undef_defaults_to_true
	  if !defined $section;

      return $section  =~ /$required_section/;
  };
}

sub do_bump {
  my $self = shift;
  my ($track_name,$option,$count,$max,$length) = @_;

  my $source            = $self->source;
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
      :  $option == 4 ? 'overlap'
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

  my $glyph             = $source->semantic_setting($track_name => 'glyph',$length) || 'generic';
  my $overlap_label     = $glyph =~ /xyplot|vista|wiggle|density/;

  $option ||= 0;
  return  $option == 0 ? $maxed_out && $conf_label
        : $option == 3 ? $conf_label || 1
	: $option == 4 ? ($overlap_label ? $conf_label : 0)
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

sub feature2label {
    my $self = shift;
    my $feature = shift;
    my $type2label = $self->{_type2label} or die "no type2label map defined";
    my $type = eval {$feature->type} || eval{$feature->source_tag} || eval{$feature->primary_tag} or return;
    (my $basetype = $type) =~ s/:.+$//;
    my $labels = $type2label->{$type}||$type2label->{$basetype} or return;
    my @labels = keys %$labels;
    return @labels;
}

# override make_link to allow for code references
sub make_link {
  my $self     = shift;
  my ($feature,$panel,$label,$track)  = @_;
  my $label_fix = $label;

  if (ref $label && $label->{name}){ 
    $label_fix = $label->{name};
    if ($label_fix =~/^(plugin)\:/){$label_fix = join(":",($',$1));}
  }

  my $data_source = $self->source;
  my $ds_name     = $data_source->name;

  my $link     = $data_source->code_setting($label_fix,'link');

  if (! defined $link) {
  if ($feature->can('url')) {
    my $link = $feature->url;
    return $link if defined $link;
  }
  return $label->make_link($feature)
      if $label
      && $label =~ /^[a-zA-Z_]/
      && $label->isa('Bio::Graphics::FeatureFile');
  }

  $panel ||= 'Bio::Graphics::Panel';
  $label ||= eval {$self->feature2label($feature)};
  $label ||= 'general';

  # most specific -- a configuration line

  # less specific - a smart feature
  $link        = $feature->make_link if $feature->can('make_link') && !defined $link;

  # general defaults
  $link        = $data_source->code_setting('TRACK DEFAULTS'=>'link') unless defined $link;
  $link        = $data_source->code_setting(general=>'link')          unless defined $link;
  $link        = $data_source->globals->setting(general=>'link')      unless defined $link;

  return unless $link;

  if (ref($link) eq 'CODE') {
    my $val = eval {$link->($feature,$panel,$track)};
    $data_source->_callback_complain($label=>'link') if $@;
    return $val;
  }
  elsif (!$link || $link eq 'AUTO') {
    my $n     = $feature->display_name || '';
    my $c     = $feature->seq_id       || '';
    my $name  = CGI::escape("$n");  # workaround CGI.pm bug
    my $class = eval {CGI::escape($feature->class)}||'';
    my $ref   = CGI::escape("$c");  # workaround again
    my $start = CGI::escape($feature->start);
    my $end   = CGI::escape($feature->end);
    my $src   = CGI::escape(eval{$feature->source} || '');
    my $url   = CGI->request_uri || '../..';
    my $id    = eval {CGI::escape($feature->primary_id)};
    my $dbid  = eval {$feature->gbrowse_dbid} || ($data_source->db_settings($label))[0];
    $dbid     = CGI::escape($dbid);
    $url      =~ s/\?.+//;
    $url      =~ s! /gbrowse[^/]* / [^/]+ /? [^/]*  $!!x;
    $url      .= "/gbrowse_details/$ds_name?ref=$ref;start=$start;end=$end";
    $url      .= ";name=$name"     if defined $name;
    $url      .= ";class=$class"   if defined $class;
    $url      .= ";feature_id=$id" if defined $id;
    $url      .= ";db_id=$dbid"    if defined $dbid;
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

  my $length = eval {$self->segment->length} || 0;

  my ($title,$key) = ('','');

 TRY: {
    if ($label && eval { $label->isa('Bio::Graphics::FeatureFile') }) {
      $key = $label->name;
      $title = $label->make_title($feature) or last TRY;
      return $title;
    }

    else {
      $label     ||= eval {$self->feature2label($feature)} or last TRY;
      $key       ||= $source->setting($label,'key') || $label;
      $key         =~ s/s$//;
      $key         = "source = ".$feature->segment->dsn if $feature->isa('Bio::Das::Feature');  # for DAS sources

      my $length   = $self->segment_length($label);

      my $link     = $source->semantic_fallback_setting($label,'title',$length);
      if (defined $link && ref($link) eq 'CODE') {
	$title       = eval {$link->($feature,$panel,$track)};
	$source->_callback_complain($label=>'title') if $@;
	return $title if defined $title;
      }
      return $source->link_pattern($link,$feature) if defined $link && $link ne 'AUTO';
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
      my $name         = $feature->can('info') 
	                 ? $feature->info
			 : $feature->display_name;
      my $result;
      $result .= "$key "  if defined $key;
      $result .= "$name " if defined $name;
      $result .= '['.$feature->seq_id.":" if defined $feature->seq_id;
      $result .= $feature->start      if defined $feature->start;
      $result .= '..' . $feature->end if defined $feature->end;
      $result .= ']' if defined $feature->seq_id;
      $result;
    }
  };
  warn $@ if $@;

  return $title;
}

sub segment_length {
    my $self    = shift;
    my $label   = shift;
    my $section = $label 
	           ? Bio::Graphics::Browser2::DataSource->get_section_from_label($label) 
		   : 'detail';
    return eval {$section eq 'detail'   ? $self->segment->length
	        :$section eq 'region'   ? $self->region_segment->length
		:$section eq 'overview' ? $self->whole_segment->length
		: 0} || 0;
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

  $label    ||= eval{$self->feature2label($feature)} or return;
  my $link_target = $source->code_setting($label,'link_target')
    || $source->code_setting('TRACK DEFAULTS' => 'link_target')
    || $source->globals->code_setting(general => 'link_target')
    || '_blank';
  $link_target = eval {$link_target->($feature,$panel,$track)} if ref($link_target) eq 'CODE';
  $source->_callback_complain($label=>'link_target') if $@;
  return $link_target;
}

sub balloon_tip_setting {
  my $self = shift;
  my ($option,$label,$feature,$panel,$track,$inline) = @_;
  my $length = $self->segment_length($label);
  $option ||= 'balloon tip';
  my $source = $self->source;
  my $value  = $source->semantic_setting($label=>$option,$length||0);
  $value     = $source->code_setting('TRACK DEFAULTS' => $option) unless defined $value;
  $value     = $source->code_setting('general' => $option)        unless defined $value;

  return unless $value;
  my $val;
  my $balloon_type = $source->global_setting('balloon style') || 'GBubble';

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
  if ($inline) {
      $val =~ s/"/&quot;/g;
  } else {
      $val =~ s/"/\\"/g;
  }

  return ($balloon_type,$val);
}

# this generates the callback for highlighting a region
sub make_postgrid_callback {
    my $settings = shift;
    return unless ref $settings->{h_region};

    my @h_regions = map {
        my ( $h_ref, $h_start, $h_end, $h_color )
            = /^(.+):(\d+)\.\.(\d+)(?:@(\S+))?/;
        defined($h_ref)
            && $h_ref eq $settings->{ref}
            ? [ $h_start, $h_end, $h_color || 'lightgrey' ]
            : ()
    } @{ $settings->{h_region} };

    return unless @h_regions;
    return hilite_regions_closure(@h_regions);
}

# this subroutine generates a Bio::Graphics::Panel callback closure 
# suitable for hilighting a region of a panel.
# The args are a list of [start,end,bgcolor,fgcolor]
sub hilite_regions_closure {
    my @h_regions = @_;

    return sub {
        my $gd     = shift;
        my $panel  = shift;
        my $left   = $panel->pad_left;
        my $top    = $panel->top;
        my $bottom = $panel->bottom+$panel->pad_bottom;
        for my $r (@h_regions) {
            my ( $h_start, $h_end, $bgcolor, $fgcolor ) = @$r;
            my ( $start, $end ) = $panel->location2pixel( $h_start, $h_end );
            if ( $end - $start <= 1 ) {
                $end++;
                $start--;
            }    # so that we always see something
                 # assuming top is 0 so as to ignore top padding
            $gd->filledRectangle(
                $left + $start,
                0, $left + $end,
                $bottom, $panel->translate_color($bgcolor)
            ) if $bgcolor && $bgcolor ne 'none';

            # outline can only be the left and right sides
            # -- otherwise it looks funny.
            if ( $fgcolor && $fgcolor ne 'none' ) {
                my $c = $panel->translate_color($fgcolor);
                $gd->setStyle($c,$c,gdTransparent,gdTransparent);#,gdTransparent,gdTransparent,gdTransparent);
                $gd->line( $left + $start, 0, $left + $start, $bottom, gdStyled );
                $gd->line( $left + $end,   0, $left + $end,   $bottom, gdStyled );
            }
        }

    };
}

sub loaded_segment_fill {
    my $self = shift;
    return $self->source->global_setting('loaded segment fill') || 'none';
}

sub loaded_segment_outline {
    my $self = shift;
    return $self->source->global_setting('loaded segment outline') || 'gray';
}

sub details_mult { 
    my $self = shift;
    my $render = $self->render;
    return $render->details_mult if $render;

    # workaround for Slave processes, which have no render object
    return $self->source->details_multiplier($self->settings);
}

sub get_detail_width_no_pad {
    my $self = shift;
    my $settings = $self->settings;
    return int($settings->{width} * $self->details_mult);
}

1;

