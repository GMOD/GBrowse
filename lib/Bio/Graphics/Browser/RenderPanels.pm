package Bio::Graphics::Browser::RenderPanels;

use strict;
use warnings;

use Bio::Graphics;
use Digest::MD5 'md5_hex';
use Carp 'croak','cluck';
use Bio::Graphics::Browser::Render;
use Bio::Graphics::Browser::CachedTrack;
use Bio::Graphics::Browser::Util qw[citation shellwords url_label];
use Bio::Graphics::Browser::Render::Slave::Status;
use IO::File;
use Time::HiRes 'sleep';
use POSIX 'WNOHANG','setsid';

use CGI qw(:standard param escape unescape);

use constant TRUE  => 1;
use constant DEBUG => 0;

use constant DEFAULT_EMPTYTRACKS => 0;
use constant PAD_DETAIL_SIDES    => 10;
use constant RULER_INTERVALS     => 20;
use constant PAD_OVERVIEW_BOTTOM => 5;

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

  my $self  = bless {},ref $class || $class;
  $self->segment($segment);
  $self->whole_segment($whole_segment);
  $self->region_segment($region_segment);
  $self->source($data_source);
  $self->settings($page_settings);
  $self->language($language);

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

  # sort the requests out into local and remote ones
  my ($local_labels,
      $remote_labels) = $self->sort_local_remote($data_destinations);

  warn "[$$] request_panels(): section = $args->{section}; local labels = @$local_labels, remote labels = @$remote_labels" if DEBUG;

  # If we don't call clone_databases early, then we can have
  # a race condition where the parent hits the DB before the child
  # NOTE: commented out because clone logic has changed - may need to reenable this
  # for postgresql databases
  # Bio::Graphics::Browser::DataBase->clone_databases();

  my $do_local  = @$local_labels;
  my $do_remote = @$remote_labels;

  # In the case of a deferred request we fork.
  # Parent returns the list of requests.
  # Child processes the requests in the background.
  # If both local and remote requests are needed, then we
  # fork a second time and process them in parallel.
  if ($args->{deferred}) {
      $SIG{CHLD} = 'IGNORE';

      my $child = Bio::Graphics::Browser::Render->fork();

      if ($child) {
	  return $data_destinations;
      }

      open STDIN, "</dev/null" or die "Couldn't reopen stdin";
      open STDOUT,">/dev/null" or die "Couldn't reopen stdout";
      POSIX::setsid()          or die "Couldn't start new session";

      if ( $do_local && $do_remote ) {
          if ( Bio::Graphics::Browser::Render->fork() ) {
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
          $self->run_local_requests( $data_destinations, $args,
              $local_labels );
      }
      elsif ($do_remote) {
          $self->run_remote_requests( $data_destinations, $args,
              $remote_labels );
      }
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

sub render_track_images {
    my $self = shift;
    my $args = shift;
    delete $args->{deferred}; # deferred execution incompatible with this call
    my $requests = $self->request_panels($args);

    my %results;
    my %still_pending = map {$_=>1} keys %$requests;
    my $k     = 1.25;
    my $delay = 0.1;
    while (%still_pending) {
	for my $label (keys %$requests) {
	    my $data = $requests->{$label};
	    next if $data->status eq 'PENDING';
	    next if $data->status eq 'EMPTY';
	    if ($data->status eq 'AVAILABLE') {
		my $gd = eval{$data->gd};
		$results{$label} = $gd;
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
    foreach my $label ( @{ $labels || [] } ) {
        my @track_args = $self->create_track_args( $label, $args );
	my (@filter_args,@featurefile_args);

	my $filter     = $settings->{features}{$label}{filter};
	@filter_args   = %{$filter->{values}} if $filter->{values};
	my $ff_error;

        # get config data from the feature files
	(my $track = $label) =~ s/:(overview|region|details?)$//;
	if ($feature_files && exists $feature_files->{$track}) {

	    my $feature_file = $feature_files->{$track};

	    unless (ref $feature_file) { # upload problem!
		my $cache_object = Bio::Graphics::Browser::CachedTrack->new(
		    -cache_base => $base,
		    -panel_args => \@panel_args,
		    -track_args => \@track_args,
		    -extra_args => [ @cache_extra, @filter_args, @featurefile_args, $label ],
		    );
		$cache_object->flag_error("Could not fetch data for $track");
		$d{$track} = $cache_object;
		next;
	    }

	    next unless $label =~ /:$args->{section}$/;
	    @featurefile_args =  eval {
		$feature_file->isa('Bio::Das::Segment')||$feature_file->types, 
		$feature_file->mtime;
	    };
	}

	warn "[$$] creating CachedTrack for $label" if DEBUG;
        my $cache_object = Bio::Graphics::Browser::CachedTrack->new(
            -cache_base => $base,
            -panel_args => \@panel_args,
            -track_args => \@track_args,
            -extra_args => [ @cache_extra, @filter_args, @featurefile_args, $label ],
	    -cache_time => $settings->{cache} 
			    ? $source->cache_time 
			    : 0
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

sub render_tracks {
    my $self     = shift;
    my $requests = shift;
    my $args     = shift;

    my %result;

    for my $label ( keys %$requests ) {
        my $data   = $requests->{$label};
        my $gd     = eval{$data->gd} or next;
        my $map    = $data->map;
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
            status   => $status,
	    section  => $args->{section},
        );
    }
    
    return \%result;
}

sub wrap_rendered_track {

    my $self   = shift;
    my %args   = @_;
    my $label  = $args{'label'};
    my $map    = $args{'area_map'};
    my $width  = $args{'width'};
    my $height = $args{'height'};
    my $url    = $args{'url'};

    # track_type Used in register_track() javascript method
    my $track_type = $args{'track_type'} || 'standard';
    my $status = $args{'status'};    # for debugging

    my $buttons = $self->source->globals->button_url;
    my $plus    = "$buttons/plus.png";
    my $minus   = "$buttons/minus.png";
    my $kill    = "$buttons/ex.png";
    my $share   = "$buttons/share.png";
    my $help    = "$buttons/query.png";

    my $settings = $self->settings;
    my $source   = $self->source;

    my $collapsed = $settings->{track_collapsed}{$label};
    my $img_style = $collapsed ? "display:none" : "display:inline";

    # commented out alt because it interferes with balloon tooltips is IE
    my $map_id = "${label}_map";

    # Work around bug in google chrome which is manifested by the <area> link information
    # on all EVEN reloads of the element by ajax calls. Weird.
    my $agent  = CGI->user_agent || '';
    $map_id   .= "_".int(rand(1000)) if $agent =~ /chrome/i;  

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
    my $show_or_hide = $self->language->tr('SHOW_OR_HIDE_TRACK')
        || "Show or Hide";
    my $kill_this_track = $self->language->tr('KILL_THIS_TRACK')
	|| "Turn off this track.";
    my $share_this_track = $self->language->tr('SHARE_THIS_TRACK')
        || "Share This Track";
    my $citation = $self->plain_citation( $label, 512 );

    #$citation            =~ s/"/&quot;/g;
    #$citation            =~ s/'/&#39;/g;

    my $configure_this_track = $citation || '';
    $configure_this_track .= '<br>' if $citation;
    $configure_this_track .= $self->language->tr('CONFIGURE_THIS_TRACK')
        || "Configure this Track";

    my $escaped_label = CGI::escape($label);

    # The inline config will go into a box 500px wide by 500px tall
    # scrollbars will appear if there is overflow. The box should shrink
    # to fit if the contents are smaller than 500 x 500
    my $config_click;
    if ( $label =~ /^plugin:/ ) {
        my $help_url = "url:?plugin=$escaped_label;plugin_do=Configure";
        $config_click
            = "GBox.showTooltip(event,'$help_url',1,500,500)";
    }

    elsif ( $label =~ /^file:/ ) {
	my $escaped_file = CGI::escape($label);
	$config_click    = qq[Controller.edit_upload('$escaped_file')];
    }

    else {
        my $help_url = "url:?configure_track=$escaped_label";
        $config_click
            = "GBox.showTooltip(event,'$help_url',1,500,500)";
    }

    my $title;
    if ($label =~ /^file:/) {
	$title = $label;
    }
    elsif ($label =~ /^(http|ftp):/) {
	$title = url_label($label);
    }
    else {
      $title = $source->setting($label=>'key') || $label;
    }
    $title =~ s/:(overview|region|detail)$//;

    my $balloon_style = $source->global_setting('balloon style') || 'GBubble'; 
    my @images = (
	img({   -src         => $icon,
                -id          => "${label}_icon",
                -onClick     => "collapse('$label')",
                -style       => 'cursor:pointer',
                -onMouseOver => "$balloon_style.showTooltip(event,'$show_or_hide')",
            }
        ),
	img({   -src         => $kill,
                -id          => "${label}_kill",
		-onClick     => "ShowHideTrack('$label',false)",
                -style       => 'cursor:pointer',
                -onMouseOver => "$balloon_style.showTooltip(event,'$kill_this_track')",
            }
        ),
        img({   -src   => $share,
                -style => 'cursor:pointer',
                -onMouseOver =>
                    "$balloon_style.showTooltip(event,'$share_this_track')",
		    -onMousedown =>
                    "GBox.showTooltip(event,'url:?share_track=$escaped_label',1,500,500)",
            }
        ),

        img({   -src         => $help,
                -style       => 'cursor:pointer',
                -onmousedown => $config_click,
                -onMouseOver =>
	    "$balloon_style.showTooltip(event,'$configure_this_track')",
		    
            }
        )
	);

    # modify the title if it is a track with subtracks
    $self->select_features_menu($label,\$title);

    my $titlebar = span(
        {   -class => $collapsed ? 'titlebar_inactive' : 'titlebar',
            -id => "${label}_title"
        },
	@images,
	$title
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
	$args{section}||Bio::Graphics::Browser::Render->get_section_from_label($label),
	);
    my $pad_url = $self->source->generate_image($pad);
    my $pad_img = img(
        {   -src    => $pad_url,
            -width  => $pad->width,
            -height => $pad->height,
            -border => 0,
            -id     => "${label}_pad",
            -style  => $collapsed ? "display:inline" : "display:none",
        }
    );


    # Add arrows for pannning to details scalebar panel
    if ($is_scalebar && $is_detail) {
	my $style    = 'opacity:0.35;position:absolute;border:none;cursor:pointer';
	$style      .= ';filter:alpha(opacity=70);moz-opacity:0.35';
        my $pan_left   =  img({
	    -style   => $style . ';left:10px',
	    -class   => 'panleft',
	    -src     => "$buttons/panleft.png",
	    -onClick => "Controller.scroll('left',0.5)"
			      },
	    );
	my $pan_left2  =  img({
            -style   => $style . ';left:-3px',
            -class   => 'panleft',
            -src     => "$buttons/panleft2.png",
            -onClick => "Controller.scroll('left',1)",
                              },
            );
	my $pan_right  = img({ -style   => $style . ';right:10px',
			       -class   => 'panright',
			       -src     => "$buttons/panright.png",
			       -onClick => "Controller.scroll('right',0.5)",
			     }
	    );
        my $pan_right2  = img({ -style   => $style . ';right:-3px',
                               -class   => 'panright',
                               -src     => "$buttons/panright2.png",
                               -onClick => "Controller.scroll('right',1)",
                             }
            );

	$img = $pan_left2 . $pan_left . $img . $pan_right . $pan_right2;
    }
    return div({-class=>'centered_block',
		-style=>"width:${width}px;position:relative"},
	       ( $show_titlebar ? $titlebar : '' ) . $img . $pad_img )
        . ( $map_html || '' );

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
#    datasource => serialized Bio::Graphics::Browser::DataSource
#    settings   => serialized state hash (from the session)
#    tracks     => serialized list of track names to render
#
# POST result: serialized      { label1 => {image,map,width,height,file,gd,boxes}... }
#
# reminder: segment can be found in the settings as $settings->{ref,start,stop,flip}
sub run_remote_requests {
  my $self      = shift;
  my ($requests,$args,$labels) = @_;

  my @labels_to_generate = @$labels;
  foreach (@labels_to_generate) {
      $requests->{$_}->lock();   # flag that request is in process
  }
  
  return unless @labels_to_generate;

  eval { use HTTP::Request::Common; } unless HTTP::Request::Common->can('POST');

  my $source     = $self->source;
  my $settings   = $self->settings;
  my $lang       = $self->language;
  my %env        = map {$_=>$ENV{$_}}    grep /^(GBROWSE|HTTP)/,keys %ENV;
  my %args       = map {$_=>$args->{$_}} grep /^-/,keys %$args;

  $args{$_}  = $args->{$_} foreach ('section','image_class','cache_extra');

  # serialize the data source and settings
  my $s_dsn	= Storable::nfreeze($source);
  my $s_set	= Storable::nfreeze($settings);
  my $s_lang	= Storable::nfreeze($lang);
  my $s_env	= Storable::nfreeze(\%env);
  my $s_args    = Storable::nfreeze(\%args);

  # sort requests by their renderers
  my $slave_status = Bio::Graphics::Browser::Render::Slave::Status->new(
      $source->globals->slave_status_path
      );

  my %renderers;
  for my $label (@labels_to_generate) {
      my $url     = $source->fallback_setting($label => 'remote renderer') or next;
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

      my $child   = Bio::Graphics::Browser::Render->fork();
      next if $child;

      # THIS PART IS IN THE CHILD
      my @labels   = keys %{$renderers{$url}};
      my $s_track  = Storable::nfreeze(\@labels);

    FETCH: {
	my $request = POST ($url,
			    Content_Type => 'multipart/form-data',
			    Content => [
				operation  => 'render_tracks',
				panel_args => $s_args,
				tracks     => $s_track,
				settings   => $s_set,
				datasource => $s_dsn,
				language   => $s_lang,
				env        => $s_env,
			    ]);

	my $response = $ua->request($request);

	warn "$url=>@labels: ",$response->status_line if DEBUG;

	if ($response->is_success) {
	    my $contents = Storable::thaw($response->content);
	    for my $label (keys %$contents) {
		my $map = $contents->{$label}{map}        
		or die "Expected a map from remote server, but got nothing!";
		my $gd2 = $contents->{$label}{imagedata}  
		or die "Expected imagedata from remote server, but got nothing!";
		$requests->{$label}->put_data($gd2,$map);
	    }
	    $slave_status->mark_up($url);
	}
	else {
	    my $uri = $request->uri;
	    my $response_line = $response->status_line;
	    $slave_status->mark_down($url);
	  
	    # try to recover from a transient slave failure; this only works
	    # right if all of the tracks there are multiple equivalent slaves for the tracks
	    my %urls    = map {$_=>1} 
  	                    map {
				shellwords($source->fallback_setting($_ => 'remote renderer'))
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
			      (($url = $source->fallback_setting($_=>'remote renderer') ||0)
			       && ($url ne 'none')
			       && ($url ne 'local')))
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
            -bgcolor => $source->global_setting('detail bgcolor') || 'wheat',
            -pad_bottom => 0,
        );
    }

    my $flip = ( $section eq 'detail' and $state->{'flip'} ) ? 1 : 0;

    my @panel_args = $self->create_panel_args(
        {   section        => $section, 
            segment        => $wide_segment,
            flip           => $flip,
            %add_track_extra_args
        }
    );


    my $panel = Bio::Graphics::Panel->new( @panel_args, );

    # I don't understand why I need to add the pad to the width, since the
    # other panels don't do it but in order for the scale bar to be the same
    # size as the other panels, I need to do it.
    my $image_pad = $self->image_padding;
    my $padl      = $source->global_setting('pad_left');
    my $padr      = $source->global_setting('pad_right');
    $padl = $image_pad unless defined $padl;
    $padr = $image_pad unless defined $padr;
    my $width = $state->{'width'} * $self->overview_ratio() + $padl + $padr;

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
            -unit_divider   => $source->global_setting('unit_divider') || 1,
            %add_track_extra_args,
        );

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
    my $cache = Bio::Graphics::Browser::CachedTrack->new(
	-cache_base => $self->get_cache_base,
	-panel_args => \@panel_args,
	-track_args => \@track_args,
	-extra_args => \@extra_args,
        );
    unless ($cache->status eq 'AVAILABLE') {
	my $panel = Bio::Graphics::Panel->new(@panel_args);
	$cache->lock;
	my $gd = $panel->gd;
	$cache->put_data($gd,'');
    }

    return $cache->gd;
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

sub make_map {
  my $self = shift;
  my ($boxes,$panel,$map_name,$trackmap,$first_box_is_scale) = @_;
  my @map = ($map_name);

  my $source = $self->source;

  my $flip = $panel->flip;
  my $tips = $source->global_setting('balloon tips') && $self->settings->{show_tooltips};
  my $use_titles_for_balloons = $source->global_setting('titles are balloons');

  my $did_map;

  local $^W = 0; # avoid uninit variable warnings due to poor coderefs

  if ($first_box_is_scale) {
    push @map, $self->make_centering_map(shift @$boxes,$flip,0,$first_box_is_scale);
  }

  foreach my $box (@$boxes){
    next unless $box->[0]->can('primary_tag');

    my $label  = $box->[5] ? $trackmap->{$box->[5]} : '';

    my $href   = $self->make_link($box->[0],$panel,$label,$box->[5]);
    my $title  = unescape($self->make_title($box->[0],$panel,$label,$box->[5]));
    my $target = $self->make_link_target($box->[0],$panel,$label,$box->[5]);

    my ($mouseover,$mousedown,$style);
    if ($tips) {

      #retrieve the content of the balloon from configuration files
      # if it looks like a URL, we treat it as a URL.
      my ($balloon_ht,$balloonhover)     =
	$self->balloon_tip_setting('balloon hover',$label,$box->[0],$panel,$box->[5]);
      my ($balloon_ct,$balloonclick)     =
	$self->balloon_tip_setting('balloon click',$label,$box->[0],$panel,$box->[5]);

      my $sticky             = $source->setting($label,'balloon sticky');
      my $height             = $source->setting($label,'balloon height') || 300;

      if ($use_titles_for_balloons) {
	$balloonhover ||= $title;
      }

      $balloon_ht ||= $source->global_setting('balloon style') || 'GBubble';
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
	undef $target;
	# workarounds to accomodate observation that some browsers don't respect cursor:pointer styles in
	# <area> tags unless there is an href defined
	my $agent =  CGI->user_agent || '';
	$href     =  $agent =~ /msie/i    ? undef
                     : $agent =~ /firefox/i ? undef
                     : 'javascript:void(0)';
      }
    }
    my %attributes = (
		      title       => $title,
		      href        => $href,
		      target      => $target,
		      onmouseover => $mouseover,
		      onmousedown => $mousedown,
		      style       => $style,
		      );

    my $ftype = $box->[0]->primary_tag || 'feature';
    my $fname = $box->[0]->display_name if $box->[0]->can('display_name');
    $fname  ||= $box->[0]->name if $box->[0]->can('name');
    $fname  ||= 'unnamed';
    $ftype = "$ftype:$fname";
    my $line = join("\t",$ftype,@{$box}[1..4]);
    for my $att (keys %attributes) {
      next unless defined $attributes{$att} && length $attributes{$att};
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

# this is the routine that actually does the work!!!!
# input
#    arg1: request hashref 
#                 {label => Bio::Graphics::Browser::CachedTrack}
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
    my $requests = shift;  # a hash of labels => Bio::Graphics::Browser::CachedTrack objects
    my $args     = shift;
    my $labels   = shift;

    warn "[$$] run_local_requests" if DEBUG;

    $labels    ||= [keys %$requests];

    my $noscale        = $args->{noscale};
    my $do_map         = $args->{do_map};
    my $cache_extra    = $args->{cache_extra} || [];
    my $section        = $args->{section}     || 'detail';

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

    foreach (@labels_to_generate) {
	$requests->{$_}->lock();   # flag that request is in process
    }

    my @ordinary_tracks    = grep {!$feature_files->{$_}} @labels_to_generate;
    my @feature_tracks     = grep {$feature_files->{$_} } @labels_to_generate;

    # create all the feature filters for each track
    my $filters = $self->generate_filters($settings,$source,\@labels_to_generate);

    # == create whichever panels are not already cached ==
    for my $label (@labels_to_generate) {

        # this shouldn't happen, but let's be paranoid
        next if $seenit{$label}++;

	(my $base = $label) =~ s/:(overview|region|details?)$//;
	warn "label=$label, base=$base, file=$feature_files->{$base}" if DEBUG;

	my $multiple_tracks = $base =~ /^(http|ftp|file|das|plugin):/ 
	    || $source->code_setting($base=>'remote feature');

        my @keystyle = ( -key_style => 'between' )
            if $multiple_tracks;

	my $key = $source->setting( $base => 'key' ) || '' ;
	my @nopad = (($key eq '') || ($key eq 'none')) 
	    && !$multiple_tracks
             ? (-pad_top => 0)
             : ();
        my $panel_args = $requests->{$label}->panel_args;

        my $panel
            = Bio::Graphics::Panel->new( @$panel_args, @keystyle, @nopad );

        my %trackmap;

        if ( my $file = ($feature_files->{$base}) ) {

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
	    # == populate the tracks with feature data ==
	    $self->add_features_to_track(
		-labels    => [ $label, ],
		-tracks    => { $label => $track },
		-filters   => $filters,
		-segment   => $segment,
		-fsettings => $settings->{features},
		);
	    %trackmap = ($track=>$label);
        }

        # == generate the maps ==
        my $gd  = eval {$panel->gd};
	unless ($gd) {
	    warn "Fatal error while making track for $label: $@";
	    $requests->{$label}->flag_error($@);
	    next;
	}
        my $map = $self->make_map( scalar $panel->boxes,
            $panel, $label,
            \%trackmap, 0 );
        $requests->{$label}->put_data($gd, $map );
    }
}

# this method is a little unconventional; it modifies the title in-place
sub select_features_menu {
    my $self     = shift;
    my $label    = shift;
    my $titleref = shift;

    my $source = $self->source;
    my $settings=$self->settings;

    my ($method,@values) = shellwords $source->setting($label=>'select');
    return unless @values;

    my $buttons = $self->source->globals->button_url;
    my $escaped_label = CGI::escape($label);

    my $filter = $settings->{features}{$label}{filter};

    $filter->{values} ||= {map {$_=>1} @values};
    $filter->{method} ||= $method;


    my @showing = grep {
 	$filter->{values}{$_}
    } @values;

    my @hidden = grep {
	!$filter->{values}{$_}
    } @values;

    my $showing = @showing;
    my $total   = @showing+@hidden;

    my $select_features = $self->language->tr('SUBTRACKS_SHOWN');
    $select_features   .= ul({-style=>'list-style: none;margin:0,0,0,0'},
			      map {$filter->{values}{$_} ? li($_)
				                         : li({-style=>'color: gray'},$_)
			      } @values);
				 

    $select_features   .= $self->language->tr('SELECT_SUBTRACKS');

    my $balloon_style = $source->global_setting('balloon style') || 'GBubble'; 

    my $select_features_click
	= "GBox.showTooltip(event,'url:?select_subtracks=$escaped_label',1,500,500)";
    my $select_features_over = "$balloon_style.showTooltip(event,'$select_features')";

    # modify the title to show that some subtracks are hidden
    $$titleref .= " ".a({-href       => 'javascript:void(0)',
			 -onClick    => $select_features_click,
			 -onMouseOver=> $select_features_over
			},
			$self->language->tr('SHOWING_SUBTRACKS',$showing,$total)
    );
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

    my $filter   = $settings->{features}{$label}{filter} or return;
    my $method   = $filter->{method};
    return unless $method;

    my $code;
    my @values = grep {$filter->{values}{$_}} keys %{$filter->{values}};
    if (@values) {
	my $regex  = join '|',@values;
	$code .= "return 1 if \$f->$method =~ /($regex)/i;\n";
    } else {
	$code .= "return;\n";
    }
    return unless $code;
    my $sub = <<END;
sub {
    my \$f = shift;
    $code;
    return;
}
END

    my $cref = eval $sub;
    warn "failed compiling $sub: ",$@ if $@;
    return $cref;
}

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
    my $db = eval { $source->open_database($label)};
    unless ($db) { warn "Couldn't open database for $_: $@"; next; }
    $db2label{$db}{$label}++;
    $db2db{$db}  =  $db;  # cache database object
  }

  my (%iterators,%iterator2dbid);
  for my $db (keys %db2db) {
      my @types_in_this_db = map { $source->label2type($_,$length) } keys %{$db2label{$db}};
      next unless @types_in_this_db;
      my $iterator  = $self->get_iterator($db2db{$db},$segment,\@types_in_this_db)
	  or next;
      $iterators{$iterator}     = $iterator;
      $iterator2dbid{$iterator} = $source->db2id($db);
  }

  my (%groups,%feature_count,%group_pattern,%group_field);

  # The effect of this loop is to fetch a feature from each iterator in turn
  # using a queueing scheme. This allows streaming iterators to parallelize a
  # bit. This may not be worth the effort.
  my (%feature2dbid,%classes,%max_features,%limit_hit);

  while (keys %iterators) {
    for my $iterator (values %iterators) {

      my $feature;

      unless ($feature = $iterator->next_seq) {
	delete $iterators{$iterator};
	next;
      }

      $source->add_dbid_to_feature($feature,$iterator2dbid{$iterator});

      my @labels = $source->feature2label($feature,$length);

      for my $l (@labels) {

          $l =~ s/:\d+//;  # get rid of semantic zooming tag

	  my $track = $tracks->{$l}  or next;


	  $max_features{$l} = $source->fallback_setting($l => 'feature limit') || 0
	      unless exists $max_features{$l};

	  $filters->{$l}->($feature) or next if $filters->{$l};
	  $feature_count{$l}++;
	
	  if ($max_features{$l}
	      && $feature_count{$l} 
	      && $feature_count{$l} >= $max_features{$l}) {
	      $limit_hit{$l}++;
	      next;
	  }

	  # -----------------------------------------------------------------------------
	  # GROUP CODE
	  # Handle name-based groupings.
	  unless (exists $group_pattern{$l}) {
	      $group_pattern{$l} =  $source->code_setting($l => 'group_pattern');
	      $group_pattern{$l} =~ s!^/(.+)/$!$1! 
		  if $group_pattern{$l}; # clean up regexp delimiters
	  }
	  
	  # Handle generic grouping (needed for GFF3 database)
	  $group_field{$l} = $source->code_setting($l => 'group_on') 
	      unless exists $group_field{$l};
	  
	  if (my $pattern = $group_pattern{$l}) {
	      my $name = $feature->name or next;
	      (my $base = $name) =~ s/$pattern//i;
	      $groups{$l}{$base} 
	      ||= Bio::Graphics::Feature->new(-type   => 'group',
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

    if ($limit_hit{$l}) {
	$tracks->{$l}->panel->key_style('between');
	$tracks->{$l}->configure(-key => "Showing $max_features{$l} of $feature_count{$l} features");
    }
  }
}

sub load_external_sources {
    croak "do not call load_external_sources";
    my ( $self, %args ) = @_;

    my $segment       = $args{'segment'}       or return;
    my $whole_segment = $args{'whole_segment'} or return;
    my $settings      = $args{'settings'};
    my $plugin_set    = $args{'plugin_set'};
    my $uploaded_sources = $args{'uploaded_sources'};
    my $remote_sources   = $args{'remote_sources'};

    # $f will hold a feature file hash in which keys are human-readable names
    # of feature files and values are FeatureFile objects.

    my $feature_file = {};
    if ($segment) {
        my $rel2abs = $self->coordinate_mapper( $segment, $whole_segment, 1 );
        my $rel2abs_slow
            = $self->coordinate_mapper( $segment, $whole_segment, 0 );
        for my $featureset ( $plugin_set, $uploaded_sources, $remote_sources)
        {
	    next unless $featureset;
            $featureset->annotate(
                $segment,      $feature_file, $rel2abs,
                $rel2abs_slow, $self->setting('max segment') || 1_000_000
		);
        }
    }
    return $feature_file;
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
  if ($db->can('get_seq_stream')) {
      my @args = (-type   => $feature_types,
		  -seq_id => $segment->seq_id,
		  -start  => $segment->start,
		  -end    => $segment->end);
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

  warn "render $file" if DEBUG;
  
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
  if ($section eq 'overview' or $section eq 'region'){
    $postgrid  = hilite_regions_closure(
	            [$detail_start,
		     $detail_stop,
		     $self->hilite_fill(),
		     $self->hilite_outline()
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
	      -start        => $seg_start,
	      -end          => $seg_stop,
	      -stop         => $seg_stop,  #backward compatibility with old bioperl
	      -key_color    => $source->global_setting('key bgcolor')      || 'moccasin',
	      -bgcolor      => $source->global_setting("$section bgcolor") || 'wheat',
	      -width        => $settings->{width},
	      -key_style    => $keystyle,
	      -empty_tracks => $source->global_setting('empty_tracks')    || DEFAULT_EMPTYTRACKS,
	      -pad_top      => $image_class->gdMediumBoldFont->height+2,
              -pad_bottom   => 3,
	      -image_class  => $image_class,
	      -postgrid     => $postgrid,
	      -background   => $args->{background} || '',
	      -truecolor    => $source->global_setting('truecolor') || 0,
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

=head2 create_track_args()

  @args = $self->create_track_args($label,$args);

Return arguments need to create a Bio::Graphics::Track.
$label is a config file stanza label for the track.

=cut

sub create_track_args {
  my $self = shift;
  my ($label,$args) = @_;

  my $segment         = $self->segment;
  my $lang            = $self->language;
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
      eval { # honor the database indicated in the track config
	  my $db    = $self->source->open_database($label);
	  my $class = eval {$segment->seq_id->class} || eval{$db->refclass};
	  $segment  = $db->segment(-name  => $segment->seq_id,
				   -start => $segment->start,
				   -end   => $segment->end,
				   -class => $class);
      };
      warn $@ if $@;
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
    my $self = shift;
    my $path = $self->source->globals->cache_dir($self->source->name);
    return $path;
}

# Convert the cached image map data
# into HTML.
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
  return $label->make_link($feature)
      if $label
      && $label =~ /^[a-zA-Z_]/
      && $label->isa('Bio::Graphics::FeatureFile');

  $panel ||= 'Bio::Graphics::Panel';
  $label ||= $data_source->feature2label($feature);
  $label ||= 'general';

  # most specific -- a configuration line
  my $link     = $data_source->code_setting($label,'link');

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
    my $dbid  = eval {CGI::escape($feature->gbrowse_dbid)};
    my $id    = eval {CGI::escape($feature->primary_id)};
    warn $@ if $@;
    $url      =~ s!/gbrowse.*!!;
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

  my ($title,$key) = ('','');

 TRY: {
    if ($label && eval { $label->isa('Bio::Graphics::FeatureFile') }) {
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
    || $source->code_setting('TRACK DEFAULTS' => 'link_target')
    || $source->globals->code_setting(general => 'link_target')
    || '_blank';
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
  $val =~ s/"/&quot;/g;

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

sub plain_citation {
    my ( $self, $label, $truncate ) = @_;
    my $text = citation( $self->source(), $label, $self->language ) || '';
    $text =~ s/\<a/<span/gi;
    $text =~ s/\<\/a/\<\/span/gi;
    if ($truncate) {
        $text =~ s/^(.{$truncate}).+/$1\.\.\./;
    }
    CGI::escape($text);
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
                $gd->line( $left + $start, 0, $left + $start, $bottom, $c );
                $gd->line( $left + $end,   0, $left + $end,   $bottom, $c );
            }
        }

    };
}

sub hilite_fill {
    my $self = shift;
    return $self->source->global_setting('hilite fill') || 'yellow';
}

sub hilite_outline {
    my $self = shift;
    return $self->source->global_setting('hilite outline') || 'yellow';
}

1;

