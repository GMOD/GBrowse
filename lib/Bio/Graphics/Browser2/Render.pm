package Bio::Graphics::Browser2::Render;

use strict;	
use warnings;

use JSON;
use Digest::MD5 'md5_hex';
use CGI qw(:standard param request_method header url iframe img span div br center url_param);
use Carp qw(croak cluck);
use File::Basename 'dirname','basename';
use Text::Tabs;
use Data::Dumper;
use English;

use Bio::Graphics::Browser2::I18n;
use Bio::Graphics::Browser2::PluginSet;
use Bio::Graphics::Browser2::Shellwords;
use Bio::Graphics::Browser2::Action;
use Bio::Graphics::Browser2::Region;
use Bio::Graphics::Browser2::RegionSearch;
use Bio::Graphics::Browser2::RenderPanels;
use Bio::Graphics::Browser2::RemoteSet;
use Bio::Graphics::Browser2::SubtrackTable;
use Bio::Graphics::Browser2::TrackDumper;
use Bio::Graphics::Browser2::Util qw[modperl_request url_label];
use Bio::Graphics::Browser2::UserTracks;
use Bio::Graphics::Browser2::UserDB;
use Bio::Graphics::Browser2::Session;
use Bio::Graphics::Browser2::Render::SnapshotManager;
use POSIX ":sys_wait_h";

use constant VERSION              => 2.0;
use constant DEBUG                => 0;
use constant TRACE_RUN            => 0;
use constant TRACE                => 0; # shows top level events
use constant OVERVIEW_SCALE_LABEL => 'Overview Scale';
use constant REGION_SCALE_LABEL   => 'Region Scale';
use constant DETAIL_SCALE_LABEL   => 'Detail Scale';
use constant EMPTY_IMAGE_HEIGHT   => 12;
use constant MAX_SEGMENT          => 1_000_000;
use constant TOO_MANY_SEGMENTS    => 5_000;
use constant OVERVIEW_RATIO       => 1.0;
use constant GROUP_SEPARATOR      => "\x1d";
use constant LABEL_SEPARATOR      => "\x1e";

my %PLUGINS;       # cache initialized plugins
my $FCGI_REQUEST;  # stash fastCGI request handle
my $STATE;         # stash state for use by callbacks


# new() can be called with two arguments: ($data_source,$session)
# or with one argument: ($globals)
# in the latter case, it will invoke this code:
#   $session = $globals->authorized_session()
#   $globals->update_data_source($session)
#   $source = $globals->create_data_source($session->source)

sub new {
  my $class = shift;

  my ($data_source, $session, $requested_id, $authority);

  if (@_ == 2) {
    ($data_source, $session) = @_;
  } elsif (@_ == 1) {
    my $globals = shift;
    $requested_id = param('id')        || CGI::cookie('gbrowse_sess');
    $authority    = param('authority') || CGI::cookie('authority');
    my $shared_ok = Bio::Graphics::Browser2::Action->shared_lock_ok(param('action'));
    $session      = $globals->authorized_session($requested_id, 
						 $authority,
						 $shared_ok);
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
  $self->set_signal_handlers();
  $self;
}

sub set_signal_handlers {
    my $self = shift;
    $SIG{CHLD} = sub {
	my $kid; 
	do { $kid = waitpid(-1, WNOHANG) } while $kid > 0;
    };
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
    warn "d= $d" if DEBUG;
    warn "self->session= $self->{session}" if DEBUG;
    $d;
}

sub state {
  my $self = shift;
  my $d = $self->{state};
  $STATE = $self->{state}= shift if @_;
  $d;
}

# this is a STATIC method that can be used by callbacks as
# Bio::Graphics::Browser2::Render->request->{name}
sub request {
    return $STATE;
}

sub error_message {
    my $self = shift;
    my $d = $self->{error_message};
    $self->{error_message} = shift if @_;
    $d;
}

sub is_admin {
    my $self = shift;
    my $login = $self->session->username      or return;
    my $admin = $self->globals->admin_account or return;
    return $login eq $admin;
}

sub userdb {
    my $self = shift;
    return $self->{userdb} if exists $self->{userdb};
    unless ($self->globals->user_accounts) {
	$self->{userdb} = undef;
	return;
    }
    my $userdb = $self->{userdb} ||= Bio::Graphics::Browser2::UserDB->new($self->globals);
    return $userdb;
}

# User Tracks - Returns a list of a user's tracks.
sub user_tracks {
    my $self  = shift;

    # note: Bio::Graphics::Browser2::AdminTracks is a subclass of UserTracks
    # that is defined within the UserTracks.pm file.
    my $class = $self->is_admin ? 'Bio::Graphics::Browser2::AdminTracks'
                                : 'Bio::Graphics::Browser2::UserTracks';
    
    $self->{usertracks} ||= $class->new($self->data_source,$self->session);
    return $self->{usertracks};
}

sub get_usertrack_labels {
    my $self = shift;
    return $self->{'.user_labels'} if exists $self->{'.user_labels'};
    my $userdata = $self->user_tracks;
    my @files    = $userdata->tracks;  # misnomer -- should be "uploads" or "files"
    for my $f (@files) {
	my @labels = $userdata->labels($f);
	$self->{'.user_labels'}{$_}=$f foreach @labels;
    }
    return $self->{'.user_labels'} ||= {};
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

sub plugin_name {
    my $self = shift;
    my $label = shift;
    my ($id) = $label =~ /^plugin:(\w+)/;
    return $self->plugins->plugin($id)->name;
}

sub debug {
    my $self = shift;
    return $self->{debug} if exists $self->{debug};
    return $self->{debug} = DEBUG || $self->data_source->global_setting('debug');
}

sub DESTROY {
    my $self = shift;
    warn "[$$] $self: destroy she said" if DEBUG;
}

sub destroy {
    my $self = shift;
    # because the login manager maintains a copy of the render object,
    # we need to explicitly destroy it to avoid memory leaks.
    if (my $lm = $self->{login_manager}) {
	$lm->destroy;
	delete $self->{login_manager};
    }
    $self->session->unlock if $self->session;
#    $self->session->flush if $self->session;
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

  my $debug = $self->debug || TRACE;

  warn "[$$] RUN(): ",
       request_method(),': ',
       url(-path=>1),' ',
       query_string() if $debug || TRACE_RUN;
  warn "[$$] session id = ",$self->session->id if $debug;

  $self->set_source() && return;

  my $session = $self->session;
  my $source  = $self->data_source;
  if ($session->private) {
      $source->set_username($session->username);
  } else {
      $source->set_username(undef);
  }

  if ($source->must_authenticate) {
      if ($session->private && 
	  $self->user_authorized_for_source($session->username))
      {
	  # login session - make sure that the data source has the information needed
	  # to restrict tracks according to policy
      } else {
	  # authentication required, but not a login session, so initiate authentication request
	  $self->force_authentication;
	  $session->flush;
	  return;
      }
  }

  warn "[$$] add_user_tracks()" if $debug;
  $self->add_user_tracks($self->data_source);

  warn "[$$] testing for asynchronous event()" if $debug;
  if ($self->run_asynchronous_event) {
      warn "[$$] asynchronous exit" if $debug;
      $self->session->unlock;
      return ;
  }
  
  if (my $file = param('share_link')) {
      $self->share_link($file);
  }

  warn "[$$] init()"         if $debug;
  $self->init();

  warn "[$$] update_state()" if $debug;
  $self->update_state();
  
  # EXPERIMENTAL CODE -- GET RID OF THE URL PARAMETERS
  if ($ENV{QUERY_STRING} && $ENV{QUERY_STRING} =~ /reset/) {
      print CGI::redirect(CGI::url(-absolute=>1,-path_info=>1));
  } else {
      warn "[$$] render()" if $debug;
      $self->render();
  }

  warn "[$$] cleanup" if $debug;
  $self->cleanup();
  select($old_fh);

  warn "[$$] session flush" if $debug;
  $self->session->flush;
  
  delete $self->{usertracks};
  warn "[$$] synchronous exit" if $debug;
}

sub user_authorized_for_source {
    my $self = shift;
    my $username = shift;
    my $source   = $self->data_source;
    my $globals  = $source->globals;
    my $session  = $self->session;
    my $plugins = $self->init_plugins();
    $source->set_username($username);
    return $globals->authorized($source->name,$username,$plugins->auth_plugin)
	&& $source->authorized('general');
}

sub set_source {
    my $self = shift;

    my $source = $self->session->source;

    if (CGI::unescape(CGI::path_info()) ne CGI::unescape("/$source/")) {
	my $args = CGI::query_string();
	my $url  = CGI::url(-absolute=>1,-path_info=>0);
	$url     =~ s!(gbrowse[^/]*)(?\!.*gbrowse)/.+$!$1!;  # fix CGI/Apache bug
	$url    .= "/$source/";
	$url .= "?$args" if $args && $args !~ /^source=/;
	print CGI::redirect($url);
	return 1;
    }
    return;
}

sub init {
    my $self = shift;
    warn "init()" if DEBUG;
    warn "init_database()" if DEBUG;
    $self->init_database();
    warn "init_plugins()" if DEBUG;
    $self->init_plugins();
    warn "init_remote_sources()" if DEBUG;
    $self->init_remote_sources();
    warn "set_default_state()" if DEBUG;
    $self->set_default_state();
    warn "init done" if DEBUG;
}

# this prints out the HTTP data from an asynchronous event
sub run_asynchronous_event {
    my $self = shift;
    my ($status, $mime_type, $data, %headers) = $self->asynchronous_event or return;

    warn "[$$] asynchronous event returning status=$status, mime-type=$mime_type" if TRACE_RUN;

    # add the cookies!
    $headers{-cookie} = [$self->state_cookie,$self->auth_cookie];

    if ($status == 204) { # no content
		print CGI::header( -status => '204 No Content', %headers );
    } elsif ($status == 302) { # redirect
	print CGI::redirect($data);
    } elsif ($mime_type eq 'application/json') {
		print CGI::header(
			-status			=> $status,
			-cache_control	=> 'no-cache',
			-charset		=> $self->translate('CHARSET'),
			-type			=> $mime_type,
			%headers),
			JSON::to_json($data);
    } else {
		print CGI::header(
			-status        => $status,
			-cache_control => 'no-cache',
			-charset       => $self->translate('CHARSET'),
			-type          => $mime_type,
			%headers),
			$data;
    }
    return 1;  # no further processing needed
}

# handle asynchronous events
#
# Asynchronous requests. See Bio::Graphics::Browser2::Action for dispatch
# table. Each request returns a three element list of format:
#    ($http_status,$mime_type,$body_data)
sub asynchronous_event {
    my $self     = shift;
    my $settings = $self->state;
    my $events;

    warn "[$$] asynchronous event(",query_string(),")" if TRACE_RUN;

    # TO ADD AN ASYNCHRONOUS REQUEST...
    # 1. Give the request a unique name, such as "foo"
    # 2. Arrange for the client to POST or GET the document URL with a CGI
    #    argument list that includes "action=foo".
    # 3. Modify Bio::Graphics::Browser2::Action to include a method named
    #    ACTION_foo that processes the request. The method will receive 
    #    the CGI object as its argument, and is expected to return
    #    a three-item list consisting of the HTTP status code, the MIME type,
    #    and the message contents in the appropriate format for the MIME type.
    #    Within the method call $self->render()
    #    to get this Bio::Graphics::Browser2::Render object.

    # legacy URLs
    my $dispatch = Bio::Graphics::Browser2::Action->new($self);
    if (my @result = $dispatch->handle_legacy_calls($CGI::Q,$self)) {
		return @result;
    }

    if ( my $track_name = param('display_citation') ) {
         my $html = $self->display_citation($track_name);
         return ( 200, 'text/html', $html );
    }

    elsif (my $action = param('action')) {
		my $method   = "ACTION_${action}";
		unless ($dispatch->can($method)) {
			return (401,'text/plain',"invalid action: '$action'");
		}
		return $dispatch->$method($CGI::Q);
    }

    else {
		return;
    }
}

sub authorize_user {
    my $self = shift;
    my ($username,$id,$remember,$using_openid) = @_;
    my ($session,$error);

    my $userdb     = $self->userdb;
    return unless $userdb->username_from_sessionid($id) eq $username;
    
    warn "Checking current session" if DEBUG;
    my $current = $self->session->id;
    if ($current eq $id) {
        warn "Using current session" if DEBUG;
        $session = $self->session;
    } elsif ($self->session->private) { # trying to login without logging out?
	$session = $self->globals->session($id);  # create/retrieve session
    } else {
        warn "Retrieving old session" if DEBUG;
	$session = $self->globals->session($id);  # create/retrieve session
    }
    unless ($session->id eq $id) {
	warn "fixing probable expired session";
      FIX: {
	  my $username   = $userdb->username_from_sessionid($id) or last FIX;
	  my $userid     = $userdb->get_user_id($username)       or last FIX;
	  my $uploadsid  = $userdb->get_uploads_id($userid)      or last FIX;
	  $session->uploadsid($uploadsid);
	  $userdb->set_session_and_uploadsid($userid,$session->id,$uploadsid);
	  $id = $session->id;
	}
    }

    my $nonce = Bio::Graphics::Browser2::Util->generate_id;
    my $ip    = CGI::remote_addr();

    $session->set_nonce($nonce,$ip,$remember);
    $session->username($username);
    $session->using_openid($using_openid);

    warn "id=$id, username =",$session->username if DEBUG;

    $session->flush();
    return ($session->id,$nonce);
}

sub background_track_render {
    my $self = shift;

    $self->session->unlock(); # don't hold session captive on renderers!
    
    $self->init_plugins();
    $self->init_remote_sources();

    $self->segment or return;
    my $cache_extra = $self->create_cache_extra;
    my $external    = $self->external_data;

    my $display_details   = 1;
    my $details_msg       = '';
    my %requests;

    if ( $self->get_panel_renderer($self->segment)->vis_length <= $self->get_max_segment ) {
        $requests{'detail'} =
            $self->render_deferred(
            labels          => [ $self->expand_track_names($self->detail_tracks) ],
            segment         => $self->segment,
            section         => 'detail',
            cache_extra     => $cache_extra,
            external_tracks => $external
            );
    } else {
        $display_details = 0;
        $details_msg = h1(
	    br(),
            $self->translate(
                'TOO_BIG',
                scalar $self->data_source()->unit_label($self->get_max_segment),
            )
        );
    }

    $requests{'region'} =
        $self->render_deferred( labels          => [ $self->expand_track_names($self->regionview_tracks) ],
				segment         => $self->region_segment,
				section         => 'region', 
				cache_extra     => $cache_extra, 
				external_tracks => $external,
	    )
        if ( $self->state->{region_size} && $self->data_source->show_section('region') );

    $requests{'overview'} =
        $self->render_deferred( labels          => [ $self->expand_track_names($self->overview_tracks) ],
				segment         => $self->whole_segment,
				section         => 'overview', 
				cache_extra     => $cache_extra, 
				external_tracks => $external,
	    )
        if ( $self->data_source->show_section('overview') );

    my (%track_keys,%seenit);
    for my $section (keys %requests) {
	my $cache_track_hash = $requests{$section};
        foreach my $track_label ( keys %{ $cache_track_hash || {} } ) {
	    my $track_id = $self->trackname_to_id($track_label,$section);
            $track_keys{ $track_id }
	      = $cache_track_hash->{$track_label}->key();
        }
    }

    warn "background_track_render() return track keys ",join ' ',%track_keys if DEBUG;

    return (\%track_keys, $display_details, $details_msg);
}

sub share_link {
    my $self = shift;
    my $file = shift;
    my $usertracks = $self->user_tracks;
    $usertracks->share_link($file);
    $self->add_user_tracks;
    my @tracks = $usertracks->labels($file);
    $self->add_track_to_state($_) foreach @tracks;
    return \@tracks;
}

sub add_tracks {
    my $self        = shift;
    my $track_names = shift;

    warn "[$$] add_tracks(@$track_names)" if DEBUG; 

    my %track_data;
    my $segment = $self->segment;
    
    my $remote;
    foreach (@$track_names) {
	$self->add_track_to_state($_);
	$remote++ if /http|ftp|das/;
	$remote++ if $self->data_source->setting($_=>'remote feature');
    }

    $self->init_remote_sources if $remote;
	
    if ($segment) {
	foreach my $track_name ( @$track_names ) {

	    my @track_ids = $self->expand_track_names($track_name);
	    
	    for my $track_id (@track_ids) {
	    
		warn "rendering track $track_id" if DEBUG;

		my ( $track_keys, $display_details, $details_msg )
		    = $self->background_individual_track_render($track_id);
	    
		my $track_key        = $track_keys->{$track_id};
		my $track_section    = $self->data_source->get_section_from_label($track_id);
		my $image_width      = $self->get_image_width($self->state);
		my $image_element_id = $track_name . "_image";
		
		my $track_html;
		if ( $track_section eq 'detail' and not $display_details ) {
		    my $image_width = $self->get_image_width($self->state);
		    $track_html .= $self->render_grey_track(
			track_id         => $track_name,
			image_width      => $image_width,
			image_height     => EMPTY_IMAGE_HEIGHT,
			image_element_id => $track_name . "_image",
			);
		}
		else {
		    $track_html = $self->render_deferred_track(
			cache_key  => $track_key,
			track_id   => $track_id,
			) || '';
		}
		$track_html = $self->wrap_track_in_track_div(
		    track_id   => $track_id,
		    track_name => $track_name,
		    track_html => $track_html,
		    );
	    
		my $panel_id = 'detail_panels';
		if ( $track_id =~ /:overview$/ ) {
		    $panel_id = 'overview_panels';
		}
		elsif ( $track_id =~ /:region$/ ) {
		    $panel_id = 'region_panels';
		}
		warn "add_track() returning track_id=$track_id, key=$track_key, name=$track_name, panel_id=$panel_id" if DEBUG;
		
		$track_data{$track_id} = {
		    track_key        => $track_key,
		    track_id         => $track_id,
		    track_name       => $track_name,
		    track_html       => $track_html,
		    track_section    => $track_section,
		    image_element_id => $image_element_id,
		    panel_id         => $panel_id,
		    display_details  => $display_details,
		    details_msg      => $details_msg,
		};
	    }
	}
    }	
    return \%track_data;
}

sub create_cache_extra {
    my $self     = shift;
    my $settings = $self->state();
    my @cache_extra = (
            $settings->{show_tooltips},
	    $settings->{ref},
            $settings->{start},
            $settings->{stop},
        );

    push @cache_extra,sort map {"$_\@$settings->{h_feat}{$_}"}
                               keys %{$settings->{h_feat}} 
                      if $settings->{h_feat};

    push @cache_extra,sort @{$settings->{h_region}}
                      if $settings->{h_region};

    push @cache_extra, map { $_->config_hash() } $self->plugins->plugins;

    return \@cache_extra;
}

sub background_individual_track_render {
    my $self    = shift;
    my $label   = shift;
    my $nocache = shift;

    my $display_details = 1;
    my $details_msg = '';

    my $external    = $self->external_data;
    my $source      = $self->data_source;
    
    my $section;
    my $segment;
    if ($label =~ /:overview$/){
        $section = 'overview';
        $segment = $self->whole_segment();
    }
    elsif ($label =~ /:region$/){
        $section = 'region';
        $segment = $self->region_segment();
    }
    else{
        $section = 'detail';
        $segment = $self->segment();
    }

    if ($section eq 'detail'
        && $self->segment
        && $self->get_panel_renderer($self->segment)->vis_length > $self->get_max_segment() )
    {
        $display_details = 0;
        $details_msg     = h1(
            $self->translate(
                'TOO_BIG',
                scalar $source->unit_label(MAX_SEGMENT),
            )
        );
        my %track_keys = ( $label => 0 );
        return ( \%track_keys, $display_details, $details_msg );
    }
    
    my $cache_extra = $self->create_cache_extra();

    # Start rendering the detail and overview tracks
    my $cache_track_hash = $self->render_deferred( 
	labels          => [ $label, ],
	segment         => $segment, 
        section         => $section, 
	cache_extra     => $cache_extra, 
	external_tracks => $external,
	nocache         => $nocache,
	);

    my %track_keys;
    foreach my $cache_track_hash ( $cache_track_hash, ) {
        foreach my $track_label ( keys %{ $cache_track_hash || {} } ) {
	    my $unique_label = 
		$source->is_remotetrack($track_label) ? $track_label
		: $external->{$track_label}           ? "$track_label:$section"
		: $track_label;
            $track_keys{ $unique_label }
                = $cache_track_hash->{$track_label}->key();
        }
    }

    return (\%track_keys, $display_details, $details_msg);
}

sub render {
  my $self           = shift;

  warn "[$$] render()" if DEBUG;

  # NOTE: these handle_* methods will return true
  # if they want us to exit before printing the header
  $self->handle_track_dump()         && return;
  $self->handle_gff_dump()           && return;
  $self->handle_plugins()            && return;
  $self->handle_download_userdata()  && return;

  $self->render_header();
  $self->render_body();
}

sub render_header {
  my $self    = shift;
  my $cookie1 = $self->state_cookie();
  my $cookie2 = $self->auth_cookie();
  my $header = CGI::header(
      -cache_control =>'no-cache',
      -cookie  => [$cookie1,$cookie2],
      -charset => $self->translate('CHARSET'),
  );
  print $header;
}

sub state_cookie {
  my $self    = shift;
  my $session = $self->session;
  my $id      = shift || $session->id;
  my $path    = url(-absolute => 1);
  $path       =~ s!gbrowse/?$!!;
  my $globals = $self->globals;
  my $cookie = CGI::Cookie->new(
      -name    => $CGI::Session::NAME,
      -value   => $id,
      -path    => $path,
      -expires => '+'.$globals->time2sec($globals->remember_settings_time).'s',
      );
  return $cookie;
}

sub auth_cookie {
    my $self = shift;
    my $path = url(-absolute => 1);
    $path    =~ s!gbrowse/?$!!;
    my $auth     = (shift || param('authority')) or return;
    my $globals  = $self->globals;
    my $remember = $self->session->remember_auth;
    my @args = (-name => 'authority',
		-value=> $auth,
		-path => $path);
    if ($remember) {
	push @args,(-expires => '+'.$globals->time2sec($globals->remember_settings_time).'s');
    }
    return CGI::Cookie->new(@args);
}

# for backward compatibility
sub create_cookie { 
    my $self = shift;
    return [
	$self->state_cookie,
	$self->auth_cookie
	];
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

  warn "render_body()" if DEBUG;

  my $region   = $self->region;
  my $features = $region->features;
  my $settings = $self->state;
  my $source   = $self->data_source;

  my $title    = $self->generate_title($features);

  my $output;
  my @post_load = $self->get_post_load_functions;
  $output .= $self->render_html_start($title,@post_load);
  $output .= $self->render_user_header;
  $output .= $self->render_busy_signal;
  $output .= $self->render_actionmenu;
  $output .= $self->render_top($title,$features);

  my $main_page   .= $self->render_navbar($region->seg);

  if ($region->feature_count > 1) {
      $main_page .= $self->render_multiple_choices($features,$self->state->{name});
      $main_page .= $self->render_select_track_link;
  }

  elsif (my $seg = $region->seg) {
      $main_page .= $self->render_panels($seg,{overview   => $source->show_section('overview'),
					       regionview => $source->show_section('region'),
					       detailview => $source->show_section('detail')});
      $main_page .= $self->render_galaxy_form($seg);
  }

  elsif ($region->feature_count > 0) { # feature but no segment? Admin error
      my $message = $self->translate('CHROM_NOT_FOUND');
      my $details = $self->translate('CHROM_NOT_FOUND_DETAILS',  $features->[0]->display_name, $features->[0]->seq_id);
      $main_page .= script({-type=>'text/javascript'},"Controller.show_error('$message','$details')")
  }
  
  my $tracks        = $self->render_tracks_section;
  my $snapshots     = $self->snapshot_manager->render_snapshots_section;
  my $community     = $self->user_tracks->database? $self->render_community_tracks_section : "";
  my $custom        = $self->render_custom_tracks_section;
  my $global_config = $self->render_global_config;

  $output .= $self->render_tabbed_pages($main_page,$tracks,$snapshots,$community,$custom,$global_config);
  $output .= $self->login_manager->render_confirm;
  $output .= $self->render_bottom($features);

  print $output;
}

sub render_tracks_section {
    my $self = shift;
    return $self->render_toggle_track_table;
}

sub generate_title {
    my $self     = shift;
    my $features = shift;

    my $dsn         = $self->data_source;
    my $state       = $self->state;
    my $description = $dsn->description;
    my $divider     = $self->data_source->unit_divider;

    return $description unless $features;
    return !$features || !$state->{name}     ? $description
         : @$features == 0                   ? $self->translate('NOT_FOUND',$state->{name})
	 : @$features == 1 ? "$description: ".
				   $self->translate('SHOWING_FROM_TO',
					     scalar $dsn->unit_label($state->{view_stop} - $state->{view_start}),
					     $state->{ref},
					     $dsn->commas($state->{view_start}),
					     $dsn->commas($state->{view_stop}))
	 : $description;
}

# Provide segment info for rubberbanding and panning
sub segment_info_object {
    my $self          = shift;
    my $state         = $self->state;
    my $segment       = $self->segment;
    my $whole_segment = $self->whole_segment;

    my $renderer = $self->get_panel_renderer($segment);

    my $pad = $self->data_source->global_setting('pad_left')
        || $renderer->image_padding
        || 0;
    my $max = $self->get_max_segment;
    my $width = ( $state->{width} * OVERVIEW_RATIO );
    my $image_width  = $self->get_image_width($state);
    my $detail_width = $self->get_detail_image_width($state);

    my %segment_info_object = (
        image_padding        => $pad,
        max_segment          => $max,
        overview_start       => $whole_segment->start,
        overview_stop        => $whole_segment->end,
        overview_pixel_ratio => $whole_segment->length / $width,
        detail_start         => $segment->start,
        detail_stop          => $segment->end,
        'ref'                => $segment->seq_id,
        details_pixel_ratio  => $segment->length / ($state->{width} * $self->details_mult()),
        detail_width         => $detail_width,
        overview_width       => $image_width,
        width_no_pad         => $state->{width},
        details_mult         => $self->details_mult(),
        hilite_fill          => $self->data_source->global_setting('hilite fill')    || 'red',  # Not sure if there's a
        hilite_outline       => $self->data_source->global_setting('hilite outline') || 'gray', # better place for this
        flip                 => $state->{flip},
        initial_view_start   => $state->{view_start},
        initial_view_stop    => $state->{view_stop},
        length_label         => scalar $self->data_source->unit_label($state->{view_stop} - $state->{view_start}),
        description          => $self->data_source->description,
    );
    if ( $state->{region_size} ) {
        my ( $rstart, $rend ) = $self->regionview_bounds;
        my $rlen  = abs( $rend - $rstart );
        my $ratio = $rlen / $width;
        $segment_info_object{'region_start'}       = $rstart;
        $segment_info_object{'region_stop'}        = $rend;
        $segment_info_object{'region_pixel_ratio'} = $rlen / $width;
        $segment_info_object{'region_width'}       = $image_width;
    }
    return \%segment_info_object;
}

# Returns the HTML for the blank panel for a section (which will later be filled)
sub render_panels {
    my $self    = shift;
    my $seg     = shift;
    my $section = shift;

    warn "render_panels()" if DEBUG;

    my $html = '';

    my $cache_extra = $self->create_cache_extra();

    # Kick off track rendering
    if ($section->{'overview'} ) {
        my $scale_bar_html = $self->scale_bar( $seg, 'overview', );
        my $panels_html    = $self->get_blank_panels( [$self->overview_tracks],
						      'overview' );
	my $drag_script    = $self->drag_script( 'overview_panels', 'track' );
	$html .= div(
	    $self->toggle({tight=>1},
			  'Overview',
			  div({ -id => 'overview_panels', -class => 'track', -style=>'margin-bottom:3px; overflow: hidden; margin-left:auto; margin-right:auto; position:relative; width:'.$self->get_image_width($self->state).'px' },
			      $scale_bar_html, $panels_html,
			  ))
	    ) . $drag_script;
    }
    
    if ( $section->{'regionview'} and $self->state->{region_size} ) {

        my $scale_bar_html = $self->scale_bar( $seg, 'region' );
        my $panels_html    = $self->get_blank_panels( [$self->regionview_tracks],
						      'region');
        my $drag_script    = $self->drag_script( 'region_panels', 'track' );

        $html .= div(
            $self->toggle({tight=>1},
			  'Region',
			  div({ -id => 'region_panels', -class => 'track', 
				-style=>'margin-bottom:3px; overflow: hidden; margin-left:auto; margin-right:auto; position:relative; width:'.$self->get_image_width($self->state).'px'  },
			      $scale_bar_html, $panels_html,
			  )
            )
	    ) . $drag_script;
    }

    if ( $section->{'detailview'} ) {
        my $scale_bar_html = $self->scale_bar( $seg, 'detail' );
        my $ruler_html     = $self->render_ruler_div;
        my $panels_html    = $self->get_blank_panels( [$self->detail_tracks],
						      'detail');
        my $drag_script    = $self->drag_script( 'detail_panels', 'track' );
        my $details_msg    = span({ -id => 'details_msg', },'');
	my $clear_hilites  = $self->clear_highlights;
        $html .= div(
            $self->toggle({tight=>1},
			  'Details',
			  div({ -id => 'detail_panels', -class => 'track', -style=>'margin-left:auto; margin-right:auto; position:relative; width:'.$self->get_image_width($self->state).'px' },
			      $details_msg,
			      $ruler_html,
			      $scale_bar_html, 
			      $panels_html,
			  ),
			  div({-style=>'text-align:center'},
			      $self->render_select_track_link,
			      $clear_hilites,
			  ),
			  div($self->html_frag('html4',$self->state))
            )
	    ) . $drag_script;
    }
    return div({-id=>'panels'},$html);
}

sub get_post_load_functions {
    my $self = shift;
    my @fun;
    if (my $url = param('eurl')) {
	    my $trackname = $self->user_tracks->escape_url($url);
	    push @fun,'Controller.select_tab("custom_tracks_page")';
	    push @fun,"loadURL('$trackname','$url',true)";
    }
    return @fun;
}

sub scale_bar {
    my $self         = shift;
    my $seg          = shift;
    my $this_section = shift || 'detail';
    my $extra_args   = shift; 

    my $label = '';
    my ( $url, $height, $width );
    my $renderer = $self->get_panel_renderer($seg);
    if ( $this_section eq 'overview' ) {
        $label = OVERVIEW_SCALE_LABEL;
        ( $url, $height, $width ) = $renderer->render_scale_bar(
            section       => 'overview',
            whole_segment => $self->whole_segment,
            segment       => $seg,
            state         => $self->state
        );
    }
    elsif ( $this_section eq 'region' ) {
        $label = REGION_SCALE_LABEL;
        ( $url, $height, $width ) = $renderer->render_scale_bar(
            section        => 'region',
            region_segment => $self->region_segment,
            segment        => $seg,
            state          => $self->state
        );
    }
    elsif ( $this_section eq 'detail' ) {
        $label = DETAIL_SCALE_LABEL;
        ( $url, $height, $width ) = $renderer->render_scale_bar(
            section => 'detail',
            segment => $seg,
            state   => $self->state,
	    @$extra_args 
        );
    }
    my $html = $renderer->wrap_rendered_track(
        label      => $label,
        area_map   => [],
        width      => $width,
        height     => $height,
        url        => $url,
        status     => '',
	section    => $this_section,
    );
    $html = $self->wrap_track_in_track_div(
	track_name  => $label,
        track_id    => $label,
        track_html => $html,
        track_type => 'scale_bar',
    );
    return $html
}

sub init_database {
  my $self = shift;
  return $self->db() if $self->db();  # already done

  my $dsn = $self->data_source;
  my $db  = $dsn->open_database();

  # I don't know what this is for, 
  # but it was there in gbrowse and looks like an important hack.
  eval {$db->biosql->version($self->state->{version})};

  $self->db($db);
  $db;
}

sub region {
    my $self     = shift;

    return $self->{region} if $self->{region};

    my $source = $self->data_source;
    my $db     = $source->open_database();
    my $dbid   = $source->db2id($db);

    my $region   = Bio::Graphics::Browser2::Region->new(
 	{ source     => $self->data_source,
 	  state      => $self->state,
 	  db         => $db,
	  searchopts => $source->search_options($dbid),
	}
 	) or die;

    # run any "find" plugins
    my $plugin_action  = $self->plugin_action || '';
    my $current_plugin = $self->current_plugin;
    if ($current_plugin 
	&& $plugin_action eq $self->translate('Find')
	|| lc $plugin_action eq 'find') {
	$region->features($self->plugin_find($current_plugin,$self->state->{name}));
    }
    elsif ($self->state->{ref}) { # a known region
	$region->set_features_by_region(@{$self->state}{'ref','start','stop'});
    }
    elsif (my $features = $self->plugin_auto_find($self->state->{name})) {  # plugins with the auto_find() method defined
	$region->features($features);
    }
    else { # a feature search
	my $search   = $self->get_search_object();
	my $features = $search->search_features();
	if ($@) {
	    (my $msg = $@) =~ s/\sat.+line \d+//;
	    $self->error_message($msg);
	    $self->state->{name} = ''; # to avoid the error again
	}
	$region->features($features);
    }

    $self->plugins->set_segments($region->segments) if $self->plugins;
    $self->state->{valid_region} = $region->feature_count > 0;
    return $self->{region}       = $region;
}

sub thin_segment {
    my $self  = shift;
    my $state = $self->state;
    if (defined $state->{ref}) {
	return Bio::Graphics::Feature->new(-seq_id => $state->{ref},
					   -start  => $state->{start},
					   -end    => $state->{stop});
    } else {
	return $self->segment;
    }
}

sub thin_whole_segment {
    my $self  = shift;

    my $state = $self->state;
    if (defined $state->{ref} && defined $state->{seg_min}) {
	return Bio::Graphics::Feature->new(-seq_id => $state->{ref},
					   -start  => $state->{seg_min},
					   -end    => $state->{seg_max});
    } else {
	return $self->whole_segment;
    }
}

sub thin_region_segment {
    my $self  = shift;
    my $state = $self->state;
    my $thin_segment       = $self->thin_segment;
    my $thin_whole_segment = $self->thin_whole_segment;

    return Bio::Graphics::Browser2::Region->region_segment(
	$thin_segment,
	$state,
	$thin_whole_segment);
}

sub segment {
    my $self   = shift;
    my $state  = $self->state;
    my $region = $self->region or return;
    return $region->seg;
}

sub whole_segment {
  my $self    = shift;

  return $self->{whole_segment} 
  if exists $self->{whole_segment};

  my $segment  = $self->segment;
  my $settings = $self->state;
  return $self->{whole_segment} = 
      $self->region->whole_segment($segment,$settings);
}

sub region_segment {
    my $self          = shift;
    return $self->{region_segment} 
       if exists $self->{region_segment};

    my $segment       = $self->segment;
    my $settings      = $self->state;
    return $self->{region_segment} = 
	$self->region->region_segment($segment,$settings,$self->whole_segment);
}

sub get_search_object {
    my $self = shift;
    return $self->{searchobj} if defined $self->{searchobj};
    my $search = Bio::Graphics::Browser2::RegionSearch->new(
	{ source => $self->data_source,
	  state  => $self->state,
	});
    $search->init_databases(
	param('dbid') ? [param('dbid')]
	:()
	);
    return $self->{searchobj} = $search;
}

# ========================= plugins =======================
sub init_plugins {
  my $self        = shift;
  my $source      = $self->data_source->name;
  return $PLUGINS{$source} if $PLUGINS{$source} && $self->{'.plugins_inited'}++;

  my @plugin_path = shellwords($self->data_source->globals->plugin_path);

  my $plugins = $PLUGINS{$source} ||= Bio::Graphics::Browser2::PluginSet->new($self->data_source,@plugin_path);
  $self->fatal_error("Could not initialize plugins") unless $plugins;
  $plugins->configure($self);
  $self->plugins($plugins);
  $self->load_plugin_annotators();
  $plugins;
}

# for activating plugins
sub plugin_action {
  my $self = shift;
  my $action;

  # the logic of this is obscure to me, but seems to have to do with activating plugins
  # via the URL versus via fill-out forms, which may go through a translation.
  if (param('plugin_do')) {
    $action = $self->translate(param('plugin_do')) || $self->translate('Go');
  }

  $action   ||=  param('plugin_action');
  $action   ||= 'find' if param('plugin_find');

  return $action;
}

sub current_plugin {
  my $self = shift;
  my $plugin_base = param('plugin') || param('plugin_find') or return;
  $self->plugins->plugin($plugin_base);
}

sub plugin_auto_find {
    my $self = shift;
    my $search_string = shift;
    return if Bio::Graphics::Browser2::Region->is_chromosome_region($search_string);
    my (@results,$found_one);
    my $plugins = $self->plugins or return;

    for my $plugin ($plugins->plugins) {  # not a typo
	next unless $plugin->type eq 'finder' && $plugin->can('auto_find');
	my $f = $plugin->auto_find($search_string);
	next unless $f;
	$found_one++;
	push @results,@$f;
    }
    return $found_one ? \@results : undef;
}

sub plugin_find {
  my $self = shift;
  my ($plugin,$search_string) = @_;

  my $settings    = $self->state;
  my $plugin_name = $plugin->name;
  my ($results,$keyword) = $plugin->can('auto_find') && defined $search_string
                             ? $plugin->auto_find($search_string)
                             : $plugin->find();

  # nothing returned, so plug the keyword into the search box to save user's search
  unless ($results && @$results) {
      $settings->{name} = $keyword ? $keyword : $self->translate('Plugin_search_2',$plugin_name);
      return;
  }

  # Write informative information into the search box - not sure if this is the right thing to do.
  $settings->{name} = defined($search_string) ? $self->translate('Plugin_search_1',$search_string,$plugin_name)
                                              : $self->translate('Plugin_search_2',$plugin_name);
  # do we really want to do this?!!
  $self->write_auto($results);
  return $results;
}

# Handle plug-ins that aren't taken care of asynchronously
# http://localhost/cgi-bin/gb2/gbrowse/yeast/?fetch=gff3           gff3 dump as text/plain
# http://localhost/cgi-bin/gb2/gbrowse/yeast/?fetch=save+gff3      gff3 dump as attachment
# http://localhost/cgi-bin/gb2/gbrowse/yeast/?fetch=save+gff3      gff3 dump as attachment
# http://localhost/cgi-bin/gb2/gbrowse/yeast/?fetch=gff3+trackdef  gff3 plus trackdefs
# add q=chr:start..end to filter by region (otherwise uses current session)
# add t=track1+track2+track3... to select tracks

sub handle_gff_dump {
    my $self = shift;

    my $gff_action;
    
    # new API
    if (my $action = param ('f') || param('fetch')) {
	$gff_action = $action;
    } elsif ($action = param('gbgff')||param('download_track')) {
	$gff_action  = 'scan'           if $action eq 'scan';
	$gff_action  = 'datafile'       if $action eq '1';
	$gff_action  = 'save datafile'  if $action =~ /save/i;
	$gff_action  = 'save fasta'     if $action =~ /fasta/i;
	$gff_action .= " trackdef"      if param('s') or param('stylesheet');
    }
    return unless $gff_action;

    my %actions = map {$_=>1} split /\s+/,$gff_action;

    my $segment    = param('q') || param('segment') || undef;

    my @labels     = $self->split_labels_correctly(param('l'));
    @labels        = $self->split_labels((param('type'),param('t'))) unless @labels;
    @labels        = $self->visible_tracks                           unless @labels;

    $self->state->{preferred_dump_format} = param('format') if param('format');

    my $dumper = Bio::Graphics::Browser2::TrackDumper->new(
        -data_source => $self->data_source(),
        -stylesheet  => $actions{trackdef}   ||  'no',
        '-dump'      => param('d')           || undef,
        -labels      => \@labels,
	-segment     => $segment             || undef,
        -mimetype    => param('m')           || undef,
	-format      => param('format')      || undef,
    ) or return 1;

    # so that another user's tracks are added if requested
    $self->add_user_tracks($self->data_source,param('uuid')) if param('uuid');

    my @l   = @labels;
    foreach (@l) {s/[^a-zA-Z0-9_]/_/g};

    my $title      = @l ? join('+',@l) : '';
    $title        .= $title ? "_$segment" : $segment if $segment;
    $title       ||= $self->data_source->name;

    if ($actions{scan}) {
	print header('text/plain');
	$dumper->print_scan();
    }
    else {
	$dumper->state($self->state);
	my $mime = $dumper->get_file_mime_type;
	my $ext  = $dumper->get_file_extension;

	if ($actions{save} && ($actions{datafile}||$actions{gff3})) {
	    print header( -type                => $mime,
			  -content_disposition => "attachment; filename=$title.$ext");
	    $dumper->print_datafile() ;
	}
	elsif ($actions{fasta}) {
	    my $build = $self->data_source->build_id;
	    $title   .= "_$build" if $build;
	    print header( -type                => $mime =~ /x-/ ? 'application/x-fasta' : $mime,
			  -content_disposition => "attachment; filename=$title.fa");
	    $dumper->print_fasta();
	}
	elsif ($actions{datafile}) {
	    print header( -type                => $mime);
	    $dumper->print_datafile();
	} elsif ($actions{trackdef}) {
	    print header( -type                => 'text/plain');
	    $dumper->print_stylesheet();
	} else {
	    print header( -type                => $mime,
			  -content_disposition => "attachment; filename=$title.$ext");
	    $dumper->print_datafile() ;
	}
    }

    return 1;
}

sub track_filter_plugin {
    my $self = shift;
    my $plugins  = $self->plugins;
    my ($filter) = grep {$_->type eq 'trackfilter'} $plugins->plugins;
    return $filter;
}

# track dumper
sub handle_track_dump {
    my $self   = shift;
    my $source = $self->data_source;

    param('show_tracks') or return;
    print header('text/plain');
    
    my (%ts,%ds,@labels_to_dump);
    if (my @labels = $source->track_source_to_label(shellwords param('ts'))) {
	%ts     = map {$_=>1} @labels;
    }
    if (my @labels = $source->data_source_to_label(shellwords param('ds'))) {
	%ds     = map {$_=>1} @labels;
    }
    if (param('ts') && param('ds')) { # intersect
	@labels_to_dump = grep {$ts{$_}} keys %ds;
    } elsif (param('ts') or param('ds')) { #union
	@labels_to_dump = (keys %ts,keys %ds);
    } else {
	@labels_to_dump = $source->labels;
    }

    print '#',join("\t",qw(TrackLabel DataSource TrackSource Description)),"\n";
    for my $l (@labels_to_dump) {
	next if $l =~ /_scale/;
	next if $l =~ /(plugin|file):/;
	print join("\t",
		   $l,
		   $source->setting($l=>'data source'),
		   $source->setting($l=>'track source'),
		   $source->setting($l=>'key')),"\n";
    }
    return 1;
}

# Handle plug-ins that aren't taken care of asynchronously
sub handle_plugins {
    my $self = shift;

    my $plugin_base = param('plugin');
    return unless ($plugin_base);

    $self->init_plugins();
    my ($id) = $plugin_base =~ /^plugin:(\w+)/;
    $id    ||= $plugin_base;
    my $plugin      = $self->plugins->plugin($id);
    warn "an operation was requested on plugin $id, but this plugin has not been configured"
	unless $plugin;
    return unless $plugin;

    my $plugin_type = $plugin->type();

    my $plugin_action = param('plugin_action') || '';

    # for activating the plugin by URL
    if ( param('plugin_do') ) {
        $plugin_action = $self->translate( param('plugin_do') ) || $self->translate('Go');
    }
	
    my $state  = $self->state();
    my $cookie = $self->create_cookie();

    ### CONFIGURE  ###############################################
    if ($plugin_action eq $self->translate('Configure')) {
	$self->plugin_configuration_form($plugin);
	return 1;
    }
    

    ### FIND #####################################################
    if ( $plugin_action eq $self->translate('Find') ) {

        #$self->do_plugin_find( $state, $plugin_base, $features )
        #    or ( $plugin_action = 'Configure' );    #reconfigure
        return;
    }

    ### DUMP #####################################################
    # Check to see whether one of the plugin dumpers was invoked.  We have to
    # do this first before printing the header because the plugins are
    # responsible for generating the header.  NOTE THE return 1 HERE IF THE
    # DUMP IS SUCCESSFUL!

    my $segment = $self->segment();
    if (    $plugin_type   eq 'dumper'
        and $plugin_action eq $self->translate('Go')
        and (  $segment
            or param('plugin_config')
            or $plugin->verb eq ( $self->translate('Import') || 'Import' ) )
        )
    {
        $segment->{start} = param('view_start') || $segment->{start}; # We only care about the segment the user is actually
        $segment->{stop}  = param('view_stop')  || $segment->{stop};  # viewing, not the whole segment that he/she has loaded
        $segment->{end}   = param('view_stop')  || $segment->{end};   #

	my $search      = $self->get_search_object();
	my $metasegment = $search->segment($segment);
        $self->do_plugin_header( $plugin, $cookie );
        $self->do_plugin_dump( $plugin, $metasegment, $state )
            && return 1;
    }

    return;
}

sub do_plugin_header {
    my $self   = shift;
    my $plugin = shift;
    my $cookie = shift;

    # Defined in HTML.pm
}

sub do_plugin_dump {
    my $self    = shift;
    my $plugin  = shift;
    my $segment = shift;
    my $state   = shift;
    my @additional_feature_sets;

    $plugin->dump( $segment, @additional_feature_sets );
    return 1;
}

#======================== remote sources ====================
sub init_remote_sources {
  my $self = shift;
  warn "init_remote_sources()" if DEBUG;
  my $remote_sources   = Bio::Graphics::Browser2::RemoteSet->new($self->data_source,
								 $self->state,
								 $self->language,
								 $self->session->uploadsid,
      );
  $remote_sources->add_files_from_state;
  $self->remote_sources($remote_sources);
  return $remote_sources;
}

# this generates the form that is sent to Galaxy
# defined in HTML.pm
sub render_galaxy_form {
    my $self = shift;
    my $seg  = shift;
    $self->wrap_in_div('galaxy_form',
		     $self->galaxy_form($seg));
}

# to be inherited
sub galaxy_form { }

sub delete_uploads {
    my $self = shift;
    my $userdata = $self->user_tracks;
    my @files  = $userdata->tracks;
    for my $file (@files) {
	my @tracks = $userdata->labels($file);
	$userdata->delete_file($file);
	$self->remove_track_from_state($_) foreach @tracks;
    }
    $self->data_source->clear_usertracks();
}

sub cleanup {
  my $self = shift;
  warn "cleanup()" if DEBUG;
  $self->plugins->destroy;
  my $state = $self->state;
  $state->{name} = $self->region_string if $state->{ref};  # to remember us by :-)
}

sub add_remote_tracks {
    my $self        = shift;
    my $urls        = shift;

    my $user_tracks = $self->user_tracks;

    warn "ADD_REMOTE_TRACKS(@$urls)" if DEBUG;

    my @tracks;

    for my $url (@$urls) {
	my $name = $user_tracks->create_track_folder($url);
	my ($result,$msg,$tracks) 
	    = $user_tracks->mirror_url($name,$url,1,$self);
	warn "[$$] $url: result=$result, msg=$msg, tracks=@$tracks" if DEBUG;
	push @tracks,@$tracks;
    }

    push @tracks,$self->add_user_tracks($self->data_source);
    warn "[$$] adding tracks @tracks" if DEBUG;
    $self->add_track_to_state($_) foreach @tracks;
    $self->init_remote_sources();
}

sub write_auto {
    my $self             = shift;
    my $features         = shift;
    my $styles           = shift;
    my $setting          = $self->state();
    return unless @$features;

    my $user_tracks = $self->user_tracks;

    # ideally we should fork here and pass our child's STDOUT
    # to $user_tracks->upload_file(), but I'm scared...
    # So we create the file in core.
    my $feature_file = '';

    $styles ||= [];
    for my $style (@$styles) {
        my ( $type, @options ) = shellwords($style);
        $feature_file .= "[$type]\n";
        $feature_file .= join "\n", @options;
        $feature_file .= "\n";
    }

    my %seenit;
    for my $f (@$features) {
        my $reference = $f->can('seq_id') ? $f->seq_id : $f->seq_id;
        my $type      = $f->primary_tag;
        my $name      = $f->seqname;
        my $position
            = $f->sub_SeqFeature
            ? join( ',',
            map { $_->start . '..' . $_->end } $f->sub_SeqFeature )
            : $f->start . '..' . $f->end;
        $name .= "($seenit{$name})" if $seenit{$name}++;
        $feature_file .= "\nreference=$reference\n";
        $feature_file .= join( "\t", qq("$type"), qq("$name"), $position ). "\n";
    }

    my ($result,$msg,$tracks) 
	= $user_tracks->upload_data('My Track',$feature_file,'text/plain','overwrite');
    warn $msg unless $result;

    $self->add_user_tracks($self->data_source);
    $self->add_track_to_state($_) foreach @$tracks;
}

sub handle_download_userdata {
    my $self = shift;
    my $ftype   = param('userdata_download')    or return;
    my $file   = param('track')                or return;

    my $userdata = $self->user_tracks;
    my $download = $ftype eq 'conf' ? $userdata->track_conf($file)
	                        : $userdata->data_path($file, $ftype);

    my $fname = basename($download);
    my $is_text = -T $download;

    print CGI::header(-attachment   => $fname,
		      -charset      => $self->translate('CHARSET'), # 'US-ASCII' ?
		      -type         => $is_text ? 'text/plain' : 'application/octet-stream');

    my $f = $ftype eq 'conf' ? $userdata->conf_fh($file)
	                     : IO::File->new($download);
    $f or croak "$download: $!";

    if ($is_text) {
	# try to make the file match the native line endings
	# not necessary?
	my $eol = $self->guess_eol();
	while (<$f>) {
	    # print;
	    s/[\r\n]+$//;
	    print $_,$eol;
	}
    } else {
	my $buffer;
	while (read($f,$buffer,1024)) {
	    print $buffer;
	}
    }
    close $f;
    return 1;
}

sub guess_eol {
    my $self = shift;
    my $agent = CGI->user_agent;
    return "\012"     if $agent =~ /linux/i;
    return "\015"     if $agent =~ /macintosh/i;
    return "\015\012" if $agent =~ /windows/i;
    return "\n"; # default
}

sub handle_quickie {
    my $self   = shift;
    my $data   = shift;
    my $styles = shift;
    return unless $data;

    # format of quickie data is
    # reference+type+name+start..end,start..end,start..end
    my @features;
    foreach my $d (@$data) {
        my ( $reference, $type, $name, @segments )
            = $self->parse_feature_str($d);
        push @features,
            Bio::Graphics::Feature->new(
            -ref  => $reference || '',
            -type => $type      || '',
            -name => $name      || '',
            -segments => \@segments,
            );
    }
    $self->write_auto( \@features, $styles );
}

sub parse_feature_str {
    my $self = shift;
    my $f    = shift;
    my ( $reference, $type, $name, @position );
    my @args = shellwords( $f || '' );
    if ( @args > 3 ) {
        ( $reference, $type, $name, @position ) = @args;
    }
    elsif ( @args > 2 ) {
        ( $reference, $name, @position ) = @args;
    }
    elsif ( @args > 1 ) {
        ( $reference, @position ) = @args;
    }
    elsif ( $f =~ /^(.+):(\d+.+)$/ ) {
        ( $reference, @position ) = ( $1, $2 );
    }
    elsif ( $f =~ /^(.+)/ ) {
        $reference = $1;
        @position  = '1..1';
    }
    return unless $reference;

    $type = 'region' unless defined $type;
    $name = "Feature " . ++$self->{added_features} unless defined $name;

    my @segments
        = map { [/(-?\d+)(?:-|\.\.)(-?\d+)/] } map { split ',' } @position;
    ( $reference, $type, $name, @segments );
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
# AUTHENTICATION
#
##################################################################3
sub force_authentication {
    my $self = shift;

    # asynchronous event -- only allow the ones needed for authentication
    if (Bio::Graphics::Browser2::Action->is_authentication_event) {
	$self->run_asynchronous_event;
	$self->session->unlock;
	return;
    }

    if (param('action')) {
	print CGI::header(-status => '403 Forbidden');
	return;
    }

    # render main page
    $self->init();
    $self->render_header();

    my $confirm        = param('confirm') || param('openid_confirm');

    my $action;
    if ($self->data_source->auth_plugin) {
	$action = "GBox.showTooltip(event,'url:?action=plugin_login',true)";
    } else {
 	$action = $self->login_manager->login_script();
    }
    $action .= ";login_blackout(true,'')";

    my $output = $self->render_html_start('GBrowse Login Required',
					  $self->get_post_load_functions,
					  ($confirm ? '' : $action));
    $output .= div({-id=>'source_form'},$self->source_form());
    if ($confirm) {
	$output .= $self->login_manager->render_confirm;
    } else {
	$output .= $self->render_login_required($action);
    }
    $output .= "<hr>";
    $output .= $self->render_bottom();
    print $output;
}

##################################################################3
#
# STATE CODE HERE
#
##################################################################3

sub set_default_state {
  my $self = shift;
  my $state = $self->state;
  $self->default_state if !$state->{tracks} # always set in one form or another
                           or param('reset');
}

sub update_state {
  my $self   = shift;
  warn "[$$] update_state()" if DEBUG;
  return if param('gbgff');          # don't let gbgff requests update our coordinates!!!
#  return if url() =~ /gbrowse_img/;  # don't let gbrowse_img requests update our coordinates either!!
  $self->_update_state;
}

sub _update_state {
    my $self = shift;

    my $state  = $self->state;

    $self->update_state_from_cgi;
    warn "[$$] CGI updated" if DEBUG;
    if (my $seg = $self->segment) {
	# A reset won't have a segment, so we need to test for that before we use
	# one in whole_segment().
	my $whole_segment = $self->whole_segment;
	$state->{seg_min} = $whole_segment->start;
	$state->{seg_max} = $whole_segment->end;
	
	$state->{ref}          ||= $seg->seq_id;
	$state->{view_start}   ||= $seg->start; # The user has selected the area that they want to see. Therefore, this
	$state->{view_stop}    ||= $seg->end;   # will be the view_start and view_stop, rather than just start and stop.
	                                        # asynchronous_update_coordinates will multiply this by the correct factor
	                                        # to find the size of the segment to load

	$state->{start}   ||= $seg->start;      # Set regular start and stop as well, just to be safe
	$state->{stop}    ||= $seg->end;        # 
	
	# Automatically open the tracks with found features in them
	$self->auto_open();
    }
    $self->cleanup_dangling_uploads($state);
    warn "[$$] update_state() done" if DEBUG;
}

sub default_state {
  my $self  = shift;
  my $state = $self->state;
  my $data_source = $self->data_source;
  %$state = ();
  @$state{'name','ref','start','stop','flip','version'} = ('','','','','',100);
  $state->{width}        = $self->setting('default width');
  $state->{source}       = $data_source->name;
  $state->{cache}        = $data_source->cache_time>0;
  $state->{region_size}  = $self->setting('region segment');
  $state->{'max segment'}= $self->setting('max segment');
  $state->{v}            = VERSION;
  $state->{stp}          = 1;
  $state->{ins}          = 1;
  $state->{head}         = 1;
  $state->{show_tooltips}= 1;
  $state->{ks}           = 'between';
  $state->{grid}         = 1;
  $state->{sk}           = $self->setting("default varying") ? "unsorted" : "sorted";

  # if no name is specified but there is a "initial landmark" defined in the
  # config file, then we default to that.
  $state->{name} ||= $self->setting('initial landmark') 
    if defined $self->setting('initial landmark');

  $self->default_tracks();
  $self->default_category_open();
  $self->session->unlock();
}

sub default_category_open {
    my $self = shift;
    my $state = $self->state;

    my $categories = $self->data_source->category_open;
    for my $c (keys %$categories) {
	$state->{section_visible}{$c} = $categories->{$c};
    }
}

sub default_tracks {
  my $self  = shift;
  my $state  = $self->state;
#  my @labels = $self->data_source->labels;
  my @labels = $self->potential_tracks;

  $state->{tracks}   = \@labels;

  $state->{features}{$_} = {visible=>0,options=>0,limit=>0}
      foreach @labels;
  $state->{features}{$_}{visible} = 1
      foreach $self->data_source->default_labels;

  # set collapse state here
  my $source = $self->data_source;
  for my $label (@labels) {
      my $visibility = $source->setting($label => 'visible');
      next unless defined $visibility;
      $visibility = lc $visibility;
      $state->{features}{$label}{visible} = 1 if $visibility eq 'show'
	                                      or $visibility eq 'collapse';
      $state->{features}{$label}{visible} = 0 if $visibility eq 'hide';
      $state->{track_collapsed}{$label}   = 1 if $visibility eq 'collapse';
  }
}

# Open Automatically the tracks with features in them
sub auto_open {
    my $self     = shift;
    my $features = $self->region()->features() || return;
    @$features  <= 1 or return;  # don't autoopen multiple hits!!
    my $state    = $self->state;

    for my $feature (@$features) {
	# the next step optimizes away the case in which the feature type
	# is a chromosome region
	next if $feature->type eq 'region' || $feature->type eq 'segment';

        my @desired_labels = $self->data_source()->feature2label($feature);
	@desired_labels || next ;
	warn "desired labels = @desired_labels" if DEBUG;
	for my $desired_label (@desired_labels) {
	    warn "auto_open(): add_track_to_state($desired_label)" if DEBUG;
	    $self->add_track_to_state($desired_label);
	    $state->{h_feat} = {};
	    $state->{h_feat}{ lc $feature->display_name } = 'yellow'
		unless param('h_feat') && param('h_feat') eq '_clear_';
	}
    }
}

# remove upload markers that are no longer relevant
sub cleanup_dangling_uploads {
    my $self  = shift;
    my $state = shift;
	
    my %name_to_id;
    for my $id (keys %{$state->{uploads}}) {
		unless ($state->{uploads}{$id}[0]) {
			delete $state->{uploads}{$id};
			next;
		}
		$name_to_id{$state->{uploads}{$id}[0]}{$id}++;
    }

    my $usertracks = $self->user_tracks;
    my %tracks = map {$_=>1} $usertracks->tracks();

    for my $k (keys %name_to_id) {
		unless (exists $tracks{$k}) {
			delete $state->{uploads}{$_} foreach keys %{$name_to_id{$k}};
		}
    }

}

sub add_track_to_state {
  my $self  = shift;
  my $label = shift;
  my $state = $self->state;

  warn '[',Bio::Graphics::Browser2::Session->time,'] ',"[$$] add_track_to_state($label)" if DEBUG;

  return unless length $label; # refuse to add empty tracks!

  # don't add invalid track
  my %potential_tracks = map {$_=>1} $self->potential_tracks;
  warn "invalid track $label" if DEBUG && !$potential_tracks{$label};
  return unless $potential_tracks{$label};

#  my %current = map {$_=> 1} @{$state->{tracks}};
#  unshift @{$state->{tracks}},$label unless $current{$label}; # on top (better)

  # experimental -- force track to go to top
  @{$state->{tracks}} = grep {$_ ne $label} @{$state->{tracks}};
  unshift @{$state->{tracks}},$label;

  warn "[$$]ADD TRACK TO STATE WAS: ",
    join ' ',grep {$state->{features}{$_}{visible}} sort keys %{$state->{features}},"\n" if DEBUG;

  if ($state->{features}{$label}) {
    $state->{features}{$label}{visible}=1;
  }
  else{
    $state->{features}{$label}{visible} = {visible=>1,options=>0,limit=>0};
  }

  warn "[$$] ADD TRACK TO STATE NOW: ",
    join ' ',grep {$state->{features}{$_}{visible}} sort keys %{$state->{features}},"\n" if DEBUG;
}

sub remove_track_from_state {
  my $self  = shift;
  my $label = shift;
  warn '[',Bio::Graphics::Browser2::Session->time,'] ',"[$$] remove_track_from_state($label)" if DEBUG;
  delete $self->state->{features}{$label};
}

sub track_visible {
    my $self  = shift;
    my $label = shift;
    return $self->state->{features}{$label}{visible};
}

sub update_state_from_cgi {
  my $self  = shift;
  my $state = $self->state;
  warn "state = $state" if DEBUG;
  $self->update_options($state);
  $self->update_coordinates($state);
  $self->update_region($state);

  if (param('revert')) {
      $self->default_tracks($state);
  }
  else {
      $self->remove_invalid_tracks($state);
      $self->update_tracks($state);
  }

  $self->update_section_visibility($state);
  $self->update_galaxy_url($state);
}

sub create_subtrack_manager {
    my $self          = shift;
    my $label         = shift;
    my $source        = shift || $self->data_source;
    my $state         = shift || $self->state;
    
    my ($dimensions,$rows,$aliases) 
	= Bio::Graphics::Browser2::SubtrackTable->infer_settings_from_source($source,$label)
	or return;

    my $key            = $source->setting($label => 'key');
    my $selected       = $state->{subtracks}{$label};
    my $comment        = $source->setting($label => 'brief comment');

    my $stt            = Bio::Graphics::Browser2::SubtrackTable->new(-columns=>$dimensions,
								     -rows   =>$rows,
								     -label  => $label,
								     -key    => $key||$label,
								     -aliases => $aliases,
								     -comment => $comment);
    $stt->set_selected($selected) if $selected;
    return $stt;
}

# Handle returns from the track configuration form
sub reconfigure_track {
    my $self  = shift;
    my $label = shift;

    my $state  = $self->state();
    my $source = $self->data_source;

    $state->{features}{$label}{visible}          = param('show_track') ? 1 : 0;
    $state->{features}{$label}{options}          = param('format_option');
    my $dynamic = $self->translate('DYNAMIC_VALUE');
    my $mode    = param('mode');
    my $mult    = $self->details_mult;

    my $length            = param('segment_length') * $mult       || 0;
    my $semantic_low      = param('apply_semantic_low') * $mult   || 0;
    my $semantic_hi       = param('apply_semantic_hi')  * $mult   || 0;
    my $delete_semantic   = param('delete_semantic');
    my $summary           = param('summary_mode');

    $state->{features}{$label}{summary_mode_len} = $summary if defined $summary;

    ($semantic_low,$semantic_hi) = ($semantic_hi,$semantic_low) if $semantic_low > $semantic_hi;
    $self->clip_override_ranges($state->{features}{$label}{semantic_override},
				$semantic_low,
				$semantic_hi);

    my $o = $mode eq 'summary' ? $state->{features}{$label}{summary_override}                                = {}
                               : $state->{features}{$label}{semantic_override}{"$semantic_low:$semantic_hi"} = {};

    my $glyph = param('conf_glyph') || '';
    for my $s ( grep {/^conf_/} param()) {
        my @values = param($s);
	my $value  = $values[-1]; # last one wins
	$s =~ s/^conf_//;
	next unless defined $value;

	if ($s =~ /(\w+)_subtype/) {
	    next unless $1 eq $glyph;
	    $s = 'glyph_subtype';
	}
	elsif ($s =~ /(\w+)_graphtype/) {
	    next unless $1 eq $glyph;
	    $s = 'graph_type';
	} elsif ($s =~ /(\w+)_autoscale/) {
	    my $g = $1;
	    next if $g eq 'wiggle' && $glyph !~ /wiggle|vista/;
	    next if $g eq 'xyplot' && $glyph !~ /xyplot|density/;
	    $s = 'autoscale';
	}

	# semantic setting for this configured length
	my $configured_value = $source->semantic_fallback_setting($label=>$s,$semantic_low+1);

	if ($value eq $dynamic) {
	    delete $o->{$s};
	} elsif ($s eq 'bicolor_pivot' && $value eq 'value') {
	    my $bp = param('bicolor_pivot_value');
	    $o->{$s} =    $bp if !defined $configured_value or $bp != $configured_value;
	} else {
	    $o->{$s} = $value if !defined $configured_value or $value ne $configured_value;
	    if ($glyph eq 'wiggle_whiskers') {# workarounds for whisker options
		$o->{"${s}_neg"}  = $value if $s =~ /^(mean_color|stdev_color)/; 
		$o->{min_color}   = $value if $s eq 'max_color';
	    }
	}
    }
    if (defined $o->{autoscale} && $o->{autoscale}=~/local|global|chromosome/) { 
	undef $o->{min_score}; 
	undef $o->{max_score} 
    }
}

#        low                    hi
#          <--------------------->  current
#  <-----------> A
#                            <-------------> B
#   <--------------------------------------------->  C
#                <--------->  D
#
sub clip_override_ranges {
    my $self = shift;
    my ($semconf,$low,$hi) = @_;

    # legacy representation of bounds
    for my $k (keys %$semconf) {
	unless ($k =~ /:/) {
	    $semconf->{"$k:999999999"} = $semconf->{$k};
	    delete $semconf->{$k};
	}
    }

    my @ranges = map {
	my ($l,$h) = split ':';
	$l ||= 0;
	$h ||= 1_000_000_000;
	[$l,$h];
    } keys %$semconf;
    @ranges = sort {$a->[0]<=>$b->[0]} @ranges;
    for my $r (@ranges) {
	my $key  = "$r->[0]:$r->[1]";
	my $conf = $semconf->{$key};
	delete $semconf->{$key};
	my $overlap;

	if ($r->[0] <= $low && $r->[1] >= $hi) {   # case C
	    $semconf->{$r->[0]  . ':' . ($low-1)} = $conf unless $r->[0] >= $low-1;
	    $semconf->{($hi+1)  . ':' . $r->[1] } = $conf unless $hi+1   >= $r->[1];
	    $overlap++;
	}

	if ($r->[0] > $low && $r->[1] < $hi) {   # case D
	    $overlap++;
	    # delete
	}
	
	if ($r->[1] >= $low && $r->[0] <= $low) { # case A
	    $r->[1] =  $low-1;
	    $semconf->{"$r->[0]:$r->[1]"} = $conf
		unless $r->[0] >= $r->[1];
	    $overlap++;
	} 

	if ($r->[1] >= $hi && $r->[0] <= $hi) {   # case B
	    $r->[0] =  $hi+1;
	    $semconf->{"$r->[0]:$r->[1]"} = $conf
		unless $r->[0] >= $r->[1];
	    $overlap++;
	}

	unless ($overlap) {
	    $semconf->{$key} = $conf;
	}
    }
}

sub find_override_bounds {
    my $self = shift;
    my ($semconf,$length) = @_;
    my @ranges = sort {$a->[0]<=>$b->[0]} 
    map { my @a = split ':';
	  \@a
    } keys %$semconf;
    my ($low,$hi) = (0,999999999);
    for my $r (@ranges) {
	next unless @$r == 2;
	if ($length >= $r->[0] && $length <= $r->[1]) {
	    return @$r;
	}
	$low = $r->[1]+1 if $r->[1] < $length;
	$hi  = $r->[0]-1 if $r->[0] > $length;
    }
    return ($low,$hi);
}

sub find_override_region {
    my $self = shift;
    my ($semconf,$length) = @_;
    my @ranges = keys %$semconf;
    for my $r (@ranges) {
	my ($low,$hi) = split ':',$r;
	return $r if $length >= $low && (!defined $hi || $length <= $hi);
    }
    return;
}

sub update_options {
  my $self  = shift;
  my $state = shift || $self->state;
  my $data_source = shift || $self->data_source;

  #  return unless param('width'); # not submitted
  $state->{width} ||= $self->setting('default width');  # working around a bug during development

  $state->{grid} = 1 unless exists $state->{grid};  # to upgrade from older settings
  $state->{flip} = 0;  # obnoxious for this to persist

  $state->{version} ||= param('version') || '';
  do {$state->{$_} = param($_) if defined param($_) } 
    foreach qw(name source plugin stp ins head ks sk version 
               grid flip width region_size show_tooltips cache
               );

  if (my @features = shellwords(param('h_feat'))) {
      $state->{h_feat} = {};
      for my $hilight (@features) {
	  last if $hilight eq '_clear_';
	  my ($featname,$color) = split '@',$hilight;
	  $state->{h_feat}{lc $featname} = $color || 'yellow';
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
  my $self  = shift;
  my $state = shift;

  if (my @add = param('add')) {
      my @style = param('style');
      $self->handle_quickie(\@add,\@style);
  }

  # selected tracks can be set by the 'l', 'label' or 't' parameter
  # the preferred parameter is 'l', because it implements correct
  # semantics for the label separator
  if (my @l = param('l')) {
      $self->set_tracks($self->split_labels_correctly(@l));
  }
  elsif (@l = param('label')) {
      $self->set_tracks($self->split_labels(@l));
  } #... the 't' parameter
  elsif (my @t = param('t')) {
      $self->set_tracks($self->split_labels(@t));
  } #... the 'ds' (data source) or the 'ts' (track source) parameter
  elsif ((my @ds = shellwords param('ds')) || (my @ts = shellwords param('ts'))) {
      my @main_l = @ds ? $self->data_source->data_source_to_label(@ds) : $self->data_source->track_source_to_label(@ts);
      if (!@ds && @ts) {
       my %ds = ();
       foreach my $label (@main_l) {
	   my @tracks = grep {!/^#/} shellwords $self->setting($label=>'track source');
	   my @datasr = grep {!/^#/} shellwords $self->setting($label=>'data source');

	   for (my $i = 0; $i <@tracks; $i++) {
	       map{$ds{$datasr[$i]}++ if $_ == $tracks[$i] && $datasr[$i]} (@ts);
	   }
       }
       @ds = keys %ds;
      }

      foreach my $label (@main_l) {
	  my @subs = grep {!/^#/} shellwords $self->setting($label=>'select');
	  shift @subs;
	  
	  my @matched;
	  foreach my $s (@subs) {
	      map {push(@matched,$`) if ($s=~/\D(\d+)\;*$/i && $1 == $_)} @ds;
	      map {s/\s*//} @matched;													#**
	  }
	  $label.="/".join("+",@matched) if @matched;
      }
      
      $self->set_tracks(@main_l);
  }
  
  if (my @selected = $self->split_labels_correctly(param('enable'))) {
      $self->add_track_to_state($_) foreach @selected;
  }
  
  if (my @selected = $self->split_labels_correctly(param('disable'))) {
      $self->remove_track_from_state($_) foreach @selected;
  }
  
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

  if (param('ref')) {
    $state->{ref}   = param('ref');
    $state->{view_start} = param('start') if defined param('start') && param('start') =~ /^[\d-]+/;
    $state->{view_stop}  = param('stop')  if defined param('stop')  && param('stop')  =~ /^[\d-]+/;
    $state->{view_stop}  = param('end')   if defined param('end')   && param('end')   =~ /^[\d-]+/;
    $position_updated++;
  }

  # quench uninit variable warning
  my $current_span = length($state->{view_stop}||'') ? ($state->{view_stop} - $state->{view_start} + 1) 
                                                : 0;
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
      if (defined $state->{seg_min} && $state->{view_start} < $state->{seg_min}) {
	  my $delta = $state->{seg_min} - $state->{view_start};
	  $state->{view_start} += $delta;
	  $state->{view_stop}  += $delta;
      }

      if (defined $state->{seg_max} && $state->{view_stop}  > $state->{seg_max}) {
	  my $delta = $state->{view_stop} - $state->{seg_max};
	  $state->{view_start} -= $delta;
	  $state->{view_stop}  -= $delta;
      }

      # Take details multiplier into account
      $self->update_state_from_details_mult;

      # update our "name" state and the CGI parameter
      $state->{name} = $self->region_string;
      param(name => $state->{name});

      warn "name = $state->{name}" if DEBUG;
  }

  elsif (param('name') || param('q')) {
      $state->{backup_region} = 
	  [$state->{ref},$state->{start},$state->{stop},$state->{view_start},$state->{view_stop}] if $state->{ref};
      undef $state->{ref};  # no longer valid
      undef $state->{start};
      undef $state->{stop};
      undef $state->{view_start};
      undef $state->{view_stop};
      $state->{name}       = $state->{search_str} = param('name') || param('q');
      $state->{dbid}       = param('dbid'); # get rid of this
  }
}

sub asynchronous_update_overview_scale_bar {
    my $self = shift;
    my $seg  = $self->segment;

    my $renderer = $self->get_panel_renderer($seg);
    my ( $url, $height, $width ) = $renderer->render_scale_bar(
        section       => 'overview',
        whole_segment => $self->whole_segment,
        segment       => $seg,
        state         => $self->state
    );

    my $image_id = OVERVIEW_SCALE_LABEL."_image";

    return {
        url      => $url,
        height   => $height,
        width    => $width,
        image_id => $image_id,
    };
}

sub debug_visible {
    my $self  = shift;
    my $state = shift;
    warn "[$$] ",join ' ',map {
	$_ . '=>' . $state->{features}{$_}{visible}
    }
    @{$state->{tracks}};
}

sub asynchronous_update_region_scale_bar {
    my $self = shift;
    my $seg  = $self->segment;

    my $renderer = $self->get_panel_renderer($seg);
    my ( $url, $height, $width ) = $renderer->render_scale_bar(
        section       => 'region',
        region_segment => $self->region_segment,
        segment       => $seg,
        state         => $self->state
    );

    my $image_id = REGION_SCALE_LABEL."_image";

    return {
        url      => $url,
        height   => $height,
        width    => $width,
        image_id => $image_id,
    };
}

sub asynchronous_update_detail_scale_bar {
    my $self = shift;
    my $seg  = $self->segment;

    my $renderer = $self->get_panel_renderer($seg);
    my ( $url, $height, $width ) = $renderer->render_scale_bar(
        section => 'detail',
        segment => $seg,
        state   => $self->state
    );

    my $image_id = DETAIL_SCALE_LABEL . "_image";

    my ($scale_size, $scale_label) = $renderer->calculate_scale_size($seg->length/$self->details_mult, $width/$self->details_mult);

    return {
        url         => $url,
        height      => $height,
        width       => $width,
        view_width  => $self->get_image_width($self->state),
        image_id    => $image_id,
        scale_size  => $scale_size,
        scale_label => $scale_label,
    };
}

sub asynchronous_update_sections {
    my $self          = shift;
    my $section_names = shift;

    # avoid unecessary database inits
    #    $self->init_database();

    my $source        = $self->data_source;
    my $return_object = {};

    my %handle_section_name = map { $_ => 1 } @{ $section_names || [] };

    # Init Plugins if need be
    if (   $handle_section_name{'plugin_configure_div'}
        || $handle_section_name{'tracks_panel'}
	|| $handle_section_name{'plugin_form'})
    {
        $self->init_plugins();
    }

    # Page Title
    if ( $handle_section_name{'page_title'} ) {
	my $segment     = $self->thin_segment;  # avoids a db open
        my $dsn         = $self->data_source;
        my $description = $dsn->description;
        $return_object->{'page_title'} = $self->generate_title([$segment]);
    }

    # Span that shows the range
    if ( $handle_section_name{'span'} ) {
        my $container
	    = $self->slidertable();
        $return_object->{'span'} = $container;
    }

    # Unused Search Field
    if ( $handle_section_name{'search_form_objects'} ) {
        $return_object->{'search_form_objects'} 
	    = $self->render_search_form_objects();
    }

    if ($handle_section_name{'login_menu'}) {
	$return_object->{login_menu} = $self->login_manager->render_login();
    }

    # Plugin Configuration Form
    # A params is used to determine the plugin
    if ( $handle_section_name{'plugin_configure_div'} ) {
        my $plugin_base = param('plugin_base');
        if ($plugin_base) {
            my $plugin = $self->plugins->plugin($plugin_base);
            if ($plugin) {
                $return_object->{'plugin_configure_div'}
                    = $self->wrap_plugin_configuration( $plugin_base,
                    $plugin );
            }
            else {
                $return_object->{'plugin_configure_div'}
                    = $self->translate('NOT_RECOGNIZED_PLUGIN',$plugin_base)||'' . "\n";
            }
        }
        else {
            $return_object->{'plugin_configure_div'}
                = $self->translate('NO_PLUGIN_SPECIFIED')||'' . "\n";
        }
    }

    # Galaxy form
    if ( $handle_section_name{'galaxy_form'} ) {
	$return_object->{'galaxy_form'} = $self->galaxy_form($self->thin_segment);
    }

    # Plugin form
    if ( $handle_section_name{'plugin_form'} ) {
	$return_object->{'plugin_form'} = $self->plugin_form();
    }

    # Track Checkboxes
    if ( $handle_section_name{'tracks_panel'} ) {
        $return_object->{'tracks_panel'} = $self->render_track_table();
    }

    # New Custom Tracks Section
    if ( $handle_section_name{'custom_tracks'}) {
	$return_object->{'custom_tracks'} = $self->render_custom_track_listing();
    }
    
    # Community Tracks Section
    if ( $handle_section_name{'community_tracks'}) {
	$return_object->{'community_tracks'} = $self->render_community_track_listing(@_); #Passing on any search terms.
    }

    # Saved Snapshot Section
    if ( $handle_section_name{'snapshots_page'}) {
	$return_object->{'snapshots_page'} = $self->snapshot_manager->render_snapshots_listing($self);
    }

    # Handle Remaining and Undefined Sections
    foreach my $section_name ( keys %handle_section_name ) {
        next if ( defined $return_object->{$section_name} );
        $return_object->{$section_name} = 'Unknown element: ' . $section_name;
    }
    return $return_object;
}

# asynchronous_update_element has been DEPRECATED
# in favor of asynchronous_update_sections
sub asynchronous_update_element {
    my $self    = shift;
    my $element = shift;
    $self->init_database();
    my $source = $self->data_source;

    if ( $element eq 'page_title' ) {
        my $segment     = $self->segment;
        my $dsn         = $self->data_source;
        my $description = $dsn->description;
	my $divider     = $dsn->unit_divider;
        return $description . '<br>'
            . $self->translate(
            'SHOWING_FROM_TO',
            scalar $source->unit_label( $segment->length ),
            $segment->seq_id,
            $source->commas( $segment->start/$divider ),
            $source->commas( $segment->end/$divider )
            );
    }
    elsif ( $element eq 'span' ) {  # this is the popup menu that shows ranges
        my $container
            = $self->zoomBar( $self->segment, $self->whole_segment );
        $container =~ s/<\/?select.+//g;
        return $container;
    }
    elsif ( $element eq 'landmark_search_field' ) {
        return $self->state->{name};
    }
    elsif ( $element eq 'overview_panels' ) {
        return "<b>some day this will be the overview showing "
            . $self->state->{name} . "</b>";
    }
    elsif ( $element eq 'detail_panels' ) {
        $self->init_plugins();
	$self->init_remote_sources();
        return join ' ',
            $self->render_detailview_panels( $self->region->seg );
    }
    elsif ( $element eq 'plugin_configure_div' ) {
        $self->init_plugins();
        my $plugin_base = param('plugin_base');
        my $plugin      = $self->plugins->plugin($plugin_base)
            or return "$plugin_base is not a recognized plugin\n";

        return $self->wrap_plugin_configuration($plugin_base,$plugin);
    }
    elsif ( $element eq 'external_utility_div' ) {
        if ( my $file_name = param('edit_file') ) {
            $file_name = CGI::unescape($file_name);
            return $self->edit_uploaded_file($file_name);
        }
        elsif ( param('new_edit_file') ) {
            my $file_name = $self->uploaded_sources->new_file_name();
            return $self->edit_uploaded_file($file_name);
        }
    }

    # Track Checkboxes
    elsif ( $element eq 'tracks_panel' ) {
        $self->init_plugins();
        return $self->render_track_table();
    }
    # External Data Form
    elsif ( $element eq 'upload_tracks_panel' ) {
        return $self->render_external_table();
    }

    return 'Unknown element: ' . $element;
}

sub asynchronous_update_coordinates {
    my $self   = shift;
    my $action = shift;

    my $state  = $self->state;

    my $whole_segment_start = $state->{seg_min};
    my $whole_segment_stop  = $state->{seg_max};

    my $position_updated;
    if ($action =~ /left|right/) {
	$self->scroll($state,$action);
	$position_updated++;
    }
    if ($action =~ /zoom/) {
	$self->zoom($state,$action);
	$position_updated++;
    }
    if ($action =~ /set span/) {
	$self->zoom_to_span($state,$action);
	$position_updated++;
    }
    if ($action =~ /set segment/) {
	$self->move_segment($state,$action);
	$position_updated++;
    }
    if ($action =~ /reload segment/) {
	$position_updated++;
    }
    if ( $action =~ /flip (\S+)/ ) {
	if ( $action =~ /name/) {
	    $self->move_to_name($state, $action);
	    $position_updated++;
	}
	if ( $1 eq 'true' ) {
	    $state->{'flip'} = 1;
	}
	else {
	    $state->{'flip'} = 0;
	}
    }

    if ($position_updated) { # clip and update param
	if (defined $whole_segment_start && $state->{view_start} < $whole_segment_start) {
	    my $delta = $whole_segment_start - $state->{view_start};
	    $state->{view_start} += $delta;
	    $state->{view_stop}  += $delta;
	}

	if (defined $whole_segment_stop && $state->{view_stop}  > $whole_segment_stop) {
	    my $delta = $state->{view_stop} - $whole_segment_stop;
	    $state->{view_start} -= $delta;
	    $state->{view_stop}  -= $delta;

            if ($state->{view_start} < 0) {
                # Segment requested is larger than the whole segment
                $state->{view_start} = $whole_segment_start;
	        $state->{view_stop}  = $whole_segment_stop;
            }
	}

        # Take details multiplier into account
        $self->update_state_from_details_mult;

	unless (defined $state->{ref}) {
	    warn "Reverting coordinates to last known good region (user probably hit 'back' button).";
	    if ($state->{backup_region}) { # last known working region
		@{$state}{'ref','start','stop','view_start','view_stop'} = @{$state->{backup_region}};
	    } else {
		$state->{name} = param('name') || param('q') || url_param('name') || url_param('q'); # get the region somehow!!
		if (my $seg = $self->segment) {
		    $state->{ref}   = $seg->seq_id;
		    $state->{start} = $seg->start;
		    $state->{stop}  = $seg->stop;
		}
	    }
	}

	# update our "name" state and the CGI parameter
	$state->{name} = $self->region_string;
    }
    $position_updated;
}

sub update_state_from_details_mult {
    my $self = shift;
    my $state = $self->state;

    my $view_start = $state->{view_start} || 0;
    my $view_stop  = $state->{view_stop}  || 0;

    my $details_mult = $self->details_mult;

    my $length         = $view_stop - $view_start;
    my $length_to_load = int($length * $details_mult);

    my $start_to_load  = int($view_start - $length * ($details_mult - 1) / 2);

    if (defined $state->{seg_min} && $start_to_load < $state->{seg_min}) {
        $start_to_load = $state->{seg_min};
    }

    my $stop_to_load   = $start_to_load + $length_to_load;

    if (defined $state->{seg_max} && $stop_to_load > $state->{seg_max}) {
        my $delta = $stop_to_load - $state->{seg_max};
        $start_to_load -= $delta;
        $stop_to_load  -= $delta;
    }

    $state->{start} = $start_to_load;
    $state->{stop}  = $stop_to_load;
}

sub region_string {
    my $self    = shift;
    my $state   = $self->state;
    my $source  = $self->data_source;
    my $divider = $source->unit_divider || 1;
    $state->{view_start}  ||= 0;
    $state->{view_stop}   ||= 0;
    return "$state->{ref}:".
	$source->commas($state->{view_start}/$divider).
	'..'.
	$source->commas($state->{view_stop}/$divider);
}

sub zoom_to_span {
  my $self = shift;
  my ($state,$new_span) = @_;

  my ($span) = $new_span =~ /([\d+.-]+)/;

sub move_to_name {
  my $self = shift;
  my ( $state, $new_name ) = @_;

  if ( $new_name =~ /:(.*):([\d+.-]+)\.\.([\d+.-]+)/ ) {
    my $new_chr   = $1;
    my $new_start = $2;
    my $new_stop  = $3;

    $state->{ref} = $new_chr;
    $state->{view_start} = $new_start;
    $state->{view_stop}  = $new_stop;
    $self->background_track_render();
  }
}

  my $current_span = $state->{view_stop} - $state->{view_start} + 1;
  my $center	    = int(($current_span / 2)) + $state->{view_start};
  my $range	    = int(($span)/2);
  $state->{view_start}   = $center - $range;
  $state->{view_stop }   = $state->{view_start} + $span - 1;
}

sub move_segment {
  my $self = shift;
  my ( $state, $new_segment ) = @_;

  if ( $new_segment =~ /:([\d+.-]+)\.\.([\d+.-]+)/ ) {
    my $new_start = $1;
    my $new_stop  = $2;

    $state->{view_start} = $new_start;
    $state->{view_stop}  = $new_stop;
  }
}

sub scroll {
  my $self = shift;
  my $state       = shift;
  my $scroll_data = shift;

  my $flip        = $state->{flip} ? -1 : 1;

  $scroll_data    =~ s/\.[xy]$//; # get rid of imagemap button cruft
  my $scroll_distance = $self->unit_to_value($scroll_data);

  $state->{view_start} += $flip * $scroll_distance;
  $state->{view_stop}  += $flip * $scroll_distance;
}

sub zoom {
  my $self = shift;
  my $state     = shift;
  my $zoom_data = shift;

  $zoom_data    =~ s/\.[xy]$//; # get rid of imagemap button cruft
  my $zoom_distance = $self->unit_to_value($zoom_data);
  my $span          = $state->{view_stop} - $state->{view_start} + 1;
  my $center	    = int($span / 2) + $state->{view_start};
  my $range	    = int($span * (1-$zoom_distance)/2);
  $range            = 1 if $range < 1;

  my $newstart      = $center - $range;
  my $newstop       = $center + $range - 1;
  
  if ($newstart==$state->{view_start} && $newstop==$state->{view_stop}) {
      if ($zoom_distance < 0) {$newstart--;$newstop++};
      if ($zoom_distance > 0) {$newstart++;$newstop--};
  }
  if ($newstop-$newstart <=2) {$newstop++}  # don't go down to 2 bp level!

  $state->{view_start}   = $newstart;
  $state->{view_stop}    = $newstop;
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

  if ($self->setting('region segment')) {
    $state->{region_size} = param('region_size') 
	if defined param('region_size');
    $state->{region_size} = $self->setting('region segment') 
	unless defined $state->{region_size};
  }
  else {
    delete $state->{region_size};
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

sub update_galaxy_url {
    my $self  = shift;
    my $state = shift;
    if (my $url = param('GALAXY_URL')) {
	warn "[$$] setting galaxy" if DEBUG;
	$state->{GALAXY_URL} = $url;
    } elsif (param('clear_galaxy')) {
	warn "clearing galaxy" if DEBUG;
	delete $state->{GALAXY_URL};
    }
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

  my $lang             = Bio::Graphics::Browser2::I18n->new($data_source->globals->language_path);
  my $default_language = $data_source->setting('language') || 'POSIX';

  my $accept           = CGI::http('Accept-language') || '';
  my @languages        = $accept =~ /([a-z]{2}-?[a-z]*)/ig;
  push @languages,$default_language if $default_language;

  return unless @languages;
  $lang->language(@languages);
  $self->language($lang);
  Bio::Graphics::Browser2::Util->set_language($lang);
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

  # make URL labels a bit nicer
  if ($label =~ /^ftp|^http/) {
    $key = $source->setting($label => 'key') || url_label($label);
  }
  elsif ($label =~ /^plugin/) {
      ($key = $label) =~ s/^plugin://;
  }

  my $presets = $self->get_external_presets || {};
  for my $l ($self->language->language) {
    $key     ||= $source->setting($label=>"key:$l");
  }
  $key     ||= $source->setting($label => 'key');
  $key     ||= $key if defined $key;
  $key     ||= $label;
  $key;
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

sub get_max_segment {
  my $self = shift;
  my $divisor   = $self->setting('unit_divider') || 1;
  my $max_seg   = $self->setting('max segment');
  if (!$max_seg) {
    return MAX_SEGMENT;
  } elsif ($divisor == 1 ) {
    return $max_seg
  } else {
    return $max_seg * $divisor;
  }
}


#############################################################################
#
# HANDLING SEGMENTS
#
#############################################################################
sub regionview_bounds {
  my $self  = shift;
  my $segment = $self->thin_region_segment;
  return ($segment->start,$segment->end);
}

# this version handles labels with embedded hyphens correctly
sub split_labels_correctly {
  my $self = shift;
  return map {split LABEL_SEPARATOR,$_} @_;
}

# this version does not handle labels with embedded "+" or "-"
# unless the hyphen is escaped with %01d
sub split_labels {
  my $self = shift;
  my @results;

  for (@_) {

      # pass URLs through unmodified
      if (/^(http|ftp|das)/) {
	  push @results,$_;
	  next;
      }
      push @results, split /[+-]/;
  }

  my $group_separator = GROUP_SEPARATOR;
  foreach (@results) {
      s/$group_separator/-/g;  # unescape hyphens
      s/$;/-/g;                # unescape hyphens -backward compatibility
  }

  @results;
}

# remove any tracks that the client still thinks are valid
# but which have been removed from the config file
sub remove_invalid_tracks {
    my $self = shift;
    my $state = shift;

    my %potential = map {$_=>1} $self->potential_tracks;
    my @defunct   = grep {!$potential{$_}} keys %{$state->{features}};
    delete $state->{features}{$_} foreach @defunct;
    $state->{tracks} = [grep {$potential{$_}} @{$state->{tracks}}];
}

sub set_tracks {
    my $self   = shift;
    my @labels = @_;
    my $state  = $self->state;

    my %potential = map {$_=>1} $self->potential_tracks;

    my @main;
    for my $label (@labels) {
	my ($main,$subtracks) = split '/',$label;
	$subtracks ||= '';
	my @subtracks         = shellwords($subtracks);
	foreach (@subtracks) {s/#.+$//}  # get rid of comments
	push @main,$main;
	$state->{subtracks}{$main} = \@subtracks if @subtracks;
    }

    my %seenit;

    $state->{tracks} = [grep {$potential{$_} && !$seenit{$_}++} @main];
    $self->load_plugin_annotators(\@main);
    $state->{features}{$_}{visible} = 0 foreach $self->data_source->labels;
    $state->{features}{$_}{visible} = 1 foreach @main;
}

sub load_plugin_annotators {
  my ($self,$visible_labels) = @_;

  my %label_visible = map { $_ => 1 } @{ $visible_labels || [] };
  my $state = $self->state;
  my $source = $self->data_source;
  my %default_plugin = map {$_=>1} map {s/^plugin:// && $_}
    grep {/^plugin:/} $source->default_labels;

  my %listed           = $state->{tracks} ? map {$_=>1} @{$state->{tracks}} : (); # are we already on the list?
  my %listed_in_source = map {$_=>1} $source->configured_types;                   # are we already on the list?

  for my $plugin ($self->plugins->plugins) {
    next unless $plugin->type eq 'annotator';
    my $name = $plugin->id;  # use the ID "RestrictionAnnotator" rather than the name "Restriction Annotator"
    $name = "plugin:$name";
    $source->add_type($name,{}) unless $listed_in_source{$name}++;
    $state->{features}{$name} ||= {visible=>$label_visible{$name}||0,options=>0,limit=>0};
  }
}

sub detail_tracks {
  my $self     = shift;
  my $external = $self->external_data;
  my %files_in_details = map {$_=>1} $self->featurefiles_in_section('detail','expand');
  my @tracks           = grep {$files_in_details{$_}
			       || !/:(overview|region)$/} $self->visible_tracks;
  return @tracks;
}

sub overview_tracks {
  my $self = shift;
  my @tracks = grep {/:overview$/} $self->visible_tracks;
  my @files_in_overview  = $self->featurefiles_in_section('overview');
  my %seen;
  return grep {!$seen{$_}++} (@tracks,@files_in_overview);
}

sub regionview_tracks {
  my $self = shift;
  my @tracks = grep {/:region$/}   $self->visible_tracks;
  my @files_in_region  = $self->featurefiles_in_section('region');
  my %seen;
  return grep {!$seen{$_}++}  (@tracks,@files_in_region);
  
}

# all tracks currently in our state; this MAY go out of date if the
# configuration file changes.
sub all_tracks {
    my $self   = shift;
    my $state  = $self->state;
    my $source = $self->data_source;
    return grep {$source->authorized($_)} @{$state->{tracks}};
}

# all potential tracks; this is guaranteed to be up to date with the
# configuration file.
sub potential_tracks {
    my $self   = shift;
    my $source  = $self->data_source;
    my %seenit;
    return grep {!$seenit{$_}++
	      && !/^_/} ($source->detail_tracks,
			 $source->overview_tracks,
			 $source->plugin_tracks,
			 $source->regionview_tracks,
                        );
}

sub visible_tracks {
    my $self  = shift;
    my $state = $self->state;
    my @tracks = grep {$state->{features}{$_}{visible} 
		 && !/^_/
           } $self->all_tracks;
    return @tracks;
}

sub featurefiles_in_section {
    my $self             = shift;
    my $desired_section  = shift;
    my $expand           = shift;

    my $external = $self->external_data;
    my $state    = $self->state;
    my %found;

    for my $label (keys %$external) {
	$state->{features}{$label}{visible}   or next;
	my $file     = $external->{$label}    or next;
	my %sections = map {$_=>1} $self->featurefile_sections($label);
	$label .= ":".lc $desired_section if $expand;
	$found{$label}++ if $sections{lc $desired_section};
    }
    return keys %found;
}

sub featurefile_sections {
    my $self  = shift;
    my $label = shift;
    my $ff    = $self->external_data->{$label} or return;
    return $self->_featurefile_sections($ff);
}

sub _featurefile_sections {
    my $self = shift;
    my $ff   = shift;
    return 'detail' if $ff->isa('Bio::Das::Segment');

    my %sections;

    # we prefer to read the labels from the feature file,
    # but some of the featurefile types don't support this.
    my @labels     = eval {$ff->labels};
    for my $label (@labels) {
	my $section = $1 if $label =~ /:(overview|region|details?)$/i;
	$section  ||= $ff->setting($label => 'section');
	$section  ||= 'detail';
	$section    =~ s/details/detail/; # foo!
	$sections{lc $_}++ for $section   =~ /(\w+)/g;
    }

    # probe for unconfigured types, which will go into detail section by default
    my @unconfigured  = eval {grep{!$ff->type2label($_)} $ff->types};
    $sections{detail}++ if @unconfigured;

    # last chance!
    $sections{detail}++ unless %sections;
    return keys %sections;
}

# given a set of track names append the section names
# to those that correspond to file uploads
sub expand_track_names {
    my $self     = shift;
    my @tracks   = @_;

    my $external = $self->external_data;
    my $source   = $self->data_source;
    my @results;

    for my $t (@tracks) {
	if ($source->code_setting($t=>'remote feature')) {
	    push @results,$t;
	}
	elsif ($external->{$t}) {
	    my @sections = $self->featurefile_sections($t);
	    @sections    = ('detail') unless @sections;
	    push @results,"$t:$_" foreach @sections;
	}
	else {
	    push @results,$t;
	}
    }

    return @results;
 }

# This turns track names into IDs for use at the client side.
# This is necessary because tracks from external files/URLs
# may generate more than one track
sub trackname_to_id {
    my $self = shift;
    my ($name,$section) = @_;
    $self->data_source->is_remotetrack($name) ? $name
   :$self->external_data->{$name}             ? "$name:$section"
   : $name;
}

################## get renderer for this segment #########
sub get_panel_renderer {
  my $self   = shift;
  my $seg    = shift || $self->segment;
  my $whole  = shift || $self->whole_segment;
  my $region = shift || $self->region_segment;

  return Bio::Graphics::Browser2::RenderPanels->new(-segment        => $seg,
						   -whole_segment  => $whole,
						   -region_segment => $region,
						   -source         => $self->data_source,
						   -settings       => $self->state,
						   -language       => $self->language,
						   -render         => $self,
						  );}

################## image rendering code #############

# render_detailview is now obsolete, but we retain it
# because it is handy for regression testing.
sub render_detailview {
    my $self = shift;
    my $seg  = shift or return;
    my @panels = $self->render_detailview_panels($seg);
    my $drag_script = $self->drag_script('detail_panels','track');
    local $^W = 0; # quash uninit variable warning
    return div($self->toggle('Details',
			     div({-id=>'detail_panels',-class=>'track'},
				 @panels
			     )
	       )
	).$drag_script;
}

sub render_detailview_panels {
    my $self = shift;
    my $seg  = shift;

    my @labels   = $self->detail_tracks;
    my $renderer = $self->get_panel_renderer($seg);
    my $panels   = $renderer->render_panels(
	{
	    labels            => \@labels,
	    external_features => $self->external_data,
	    section           => 'detail',
	}
	);
    
    return map {$panels->{$_}} @labels;
}

sub get_blank_panels {
    my $self        = shift;
    my $track_names = shift;
    my $section     = shift;

    my $settings = $self->state;

    my $html  = '';
    my $image_width = $self->get_image_width($settings);
    foreach my $track_name ( @{ $track_names || [] } ) {

	my $divname = $self->trackname_to_id($track_name,$section);

	warn "$track_name => $divname" if DEBUG;

        my $track_html = $self->render_grey_track(
            track_id         => $track_name,
            image_width      => $image_width,
            image_height     => EMPTY_IMAGE_HEIGHT,
            image_element_id => $track_name . "_image",
        );
        $track_html = $self->wrap_track_in_track_div(
	    track_name => $track_name,
            track_id   => $divname,
            track_html => $track_html,
        );
        $html .= $track_html;
    }
    return $html;

}

sub get_image_width {
    my $self = shift;
    my $state = shift;
    my $image_width = $state->{'width'} + $self->get_total_pad_width;
    return int($image_width);
}

sub get_detail_image_width {
    my $self = shift;
    my $state = shift;
    my $image_width = $state->{'width'} * $self->details_mult + $self->get_total_pad_width;
    return int($image_width);
}

sub get_total_pad_width {
    my $self = shift;
    my $source = $self->data_source;
    my $renderer  = $self->get_panel_renderer($self->thin_segment,
					      $self->thin_whole_segment,
					      $self->thin_region_segment,
					      );
    my $padl      = $source->global_setting('pad_left');
    my $padr      = $source->global_setting('pad_right');
    my $image_pad = $renderer->image_padding;
    $padl = $image_pad unless defined $padl;
    $padr = $image_pad unless defined $padr;
    return $padl + $padr;
}

sub set_details_multiplier {
    my $self = shift;
    my $mult = shift || 1;
    $self->{'.details_mult'} = $mult;
}

sub details_mult {
    my $self = shift;
    $self->{'.details_mult'} ||= $self->_details_mult;
    return $self->{'.details_mult'};
}

sub _details_mult {
    my $self = shift;
    my $state = $self->state;
    return $self->data_source->details_multiplier($state);
}

sub render_deferred {
    my $self        = shift;

    my %args = @_;

    my $labels      = $args{labels}          || [ $self->detail_tracks ];
    my $seg         = $args{segment}         || $self->thin_segment;
    my $section     = $args{section}         || 'detail';
    my $cache_extra = $args{cache_extra}     || $self->create_cache_extra();
    my $external    = $args{external_tracks} || $self->external_data;
    my $nocache     = $args{nocache};
    
    warn '(render_deferred(',join(',',@$labels),') for section ',$section,' nocache=',$nocache if DEBUG;

    my $renderer   = $self->get_panel_renderer($seg,
					       $self->thin_whole_segment,
					       $self->thin_region_segment
	);

    my $h_callback = $self->make_hilite_callback();
    my $requests = $renderer->request_panels(
        {   labels           => $labels,
            section          => $section,
            deferred         => 1,
            whole_segment    => $self->thin_whole_segment(),
	    external_features=> $external,
            hilite_callback  => $h_callback || undef,
            cache_extra      => $cache_extra,
	    nocache          => $nocache || 0,
	    remotes          => $self->remote_sources,
	    render           => $self,
            flip => ( $section eq 'detail' ) ? $self->state()->{'flip'} : 0,
        }
    );

    return $requests;
}

sub render_grey_track {
    my $self             = shift;
    my %args             = @_;
    my $image_width      = $args{'image_width'};
    my $image_height     = $args{'image_height'};
    my $image_element_id = $args{'image_element_id'};
    my $track_id         = $args{'track_id'};

    my $renderer = $self->get_panel_renderer($self->thin_segment,
					      $self->thin_whole_segment,
					      $self->thin_region_segment,
					     );
    my $url      = $renderer->source->globals->button_url() . "/grey.png";

    my $html = $renderer->wrap_rendered_track(
        label    => $track_id,
        area_map => [],
        width    => $image_width,
        height   => $image_height,
        url      => $url,
	section  => 'detail',
        status   => '',
    );

    return $html;
}

sub render_error_track {
    my $self = shift;
    my %args             = @_;
    my $image_width      = $args{'image_width'};
    my $image_height     = $args{'image_height'} * 3;
    my $image_element_id = $args{'image_element_id'};
    my $track_id         = $args{'track_id'};
    my $error_message    = $args{'error_message'};

    my $gd               = GD::Image->new($image_width,$image_height);
    my $black            = $gd->colorAllocate(0,0,0);
    my $white            = $gd->colorAllocate(255,255,255);
    my $pink             = $gd->colorAllocate(255,181,197);
    $gd->filledRectangle(0,0,$image_width,$image_height,$pink);
    my $font             = GD->gdMediumBoldFont;
    my ($swidth,$sheight) = ($font->width * length($error_message),$font->height);
    my $xoff              = ($image_width - $swidth)/2;
    my $yoff              = ($image_height - $sheight - 3);
    $gd->string($font,$xoff,$yoff,$error_message,$black);
    my ($url,$path) = $self->data_source->generate_image($gd);

    return $self->get_panel_renderer->wrap_rendered_track(
        label    => $track_id,
        area_map => [],
        width    => $image_width,
        height   => $image_height,
        url      => $url,
	section  => 'detail',
        status   => '',
    );
}

sub render_deferred_track {
    my $self             = shift;
    my %args             = @_;
    my $cache_key        = $args{'cache_key'};
    my $track_id         = $args{'track_id'};

    my $renderer = $self->get_panel_renderer($self->thin_segment,
					     $self->thin_whole_segment,
					     $self->thin_region_segment
	);

    my $base  = $renderer->get_cache_base();
    my $cache = Bio::Graphics::Browser2::CachedTrack->new(
        -cache_base => $base,
        -key        => $cache_key,
	-cache_time => ($self->state->{cache} 
	                 ? $self->data_source->cache_time 
	                 : 0),
    );
    my $status_html = "<!-- " . $cache->status . " -->";

    warn "render_deferred_track(): $track_id: status = $status_html" if DEBUG;

    my $result_html = '';
    if ( $cache->status eq 'AVAILABLE' ) {
        my $result   = $renderer->render_tracks( { $track_id => $cache } );
        $result_html = $result->{$track_id};
    }
    elsif ($cache->status eq 'ERROR') {
	warn "[$$] rendering error track: ",$cache->errstr; # if DEBUG;
        my $image_width = $track_id =~ /overview|region/ ? $self->get_image_width($self->state)
	                                                 : $self->get_detail_image_width($self->state);
        $result_html   .= $self->render_error_track(
						  track_id       => $track_id,
						  image_width      => $image_width,
						  image_height     => EMPTY_IMAGE_HEIGHT,
						  image_element_id => $track_id . "_image",
						  error_message    => 'Track rendering error: '.$cache->errstr)
     } else {
        my $image_width = $self->get_detail_image_width($self->state);
        $result_html .= $self->render_grey_track(
						 track_id         => $track_id,
						 image_width      => $image_width,
						 image_height     => EMPTY_IMAGE_HEIGHT,
						 image_element_id => $track_id . "_image",
						 );
    }
    $result_html .= '';   # to prevent uninit warning
    warn "[$$] $track_id=>",$cache->status if DEBUG;
    return $status_html . $result_html;
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

sub make_hilite_callback {
  my $self = shift;
  my $state = $self->state();
  my @hiliters = grep {$_->type eq 'highlighter'} $self->plugins()->plugins;
  return unless @hiliters or ($state->{h_feat} && %{$state->{h_feat}});
  return sub {
    my $feature = shift;
    my $color;

    # run through the set of hilite plugins and give each one
    # a chance to choose the highlighting for its feature
    foreach (@hiliters) {
      $color ||= $_->highlight($feature);
    }
    return $color if $color;
   
    # if we get here, we select the search term for highlighting
    my %names = map 
                 {lc $_=> 1}
                  $feature->display_name,
                  eval{$feature->get_tag_values('Alias')};
    return unless %names;
    $color ||= $state->{h_feat}{$_} foreach keys %names;
    return $color;
  }
}

sub categorize_track {
  my $self  = shift;
  my $label = shift;

  my $user_labels = $self->get_usertrack_labels;

  return $self->translate('OVERVIEW') if $label =~ /:overview$/;
  return $self->translate('REGION')   if $label =~ /:region$/;
  return $self->translate('EXTERNAL') if $label =~ /^(http|ftp|file):/;
  return $self->translate('ANALYSIS') if $label =~ /^plugin:/;

  if ($user_labels->{$label}) {
      my $cat = $self->user_tracks->is_mine($user_labels->{$label}) 
	  ? $self->translate('UPLOADED_TRACKS_CATEGORY')
	  : $self->translate('SHARED_WITH_ME_CATEGORY');
      return "$cat:".$self->user_tracks->title($user_labels->{$label});
  }

  my $category;
  for my $l ($self->language->language) {
    $category      ||= $self->setting($label=>"category:$l");
  }
  $category        ||= $self->setting($label => 'category');
  $category        ||= '';  # prevent uninit variable warnings
  $category         =~ s/^["']//;  # get rid of leading quotes
  $category         =~ s/["']$//;  # get rid of trailing quotes
  return $category ||= $self->translate('GENERAL');
}

sub is_safari {
  return (CGI::user_agent||'') =~ /safari/i;
}

sub external_data {
    my $self    = shift;
    my $segment = $self->segment or return { };
    my $state   = $self->state;

    return $self->{feature_files} if exists $self->{feature_files};

    # $f will hold a feature file hash in which keys are human-readable names of
    # feature files and values are FeatureFile objects.
    my $f           = {};
    my $max_segment  = $self->get_max_segment;
    my $search       = $self->get_search_object;
    my $meta_segment = $search->segment($segment);
    my $too_big      =  $segment && ($self->get_panel_renderer($segment)->vis_length > $max_segment);
    if (!$too_big && $segment) {
	my $search       = $self->get_search_object;
	my $rel2abs      = $search->coordinate_mapper($segment,1);
	my $rel2abs_slow = $search->coordinate_mapper($segment,0);
	my $plugins      = $self->plugins;
	eval {
	    $_->annotate($meta_segment,$f,
			 $rel2abs,$rel2abs_slow,$max_segment,
			 $self->whole_segment,$self->region_segment);
	} foreach ($self->plugins,$self->remote_sources);
    }
    return $self->{feature_files} = $f;
}
#
# Supplement data source with user uploads
sub add_user_tracks {
    my $self        = shift;
    my ($data_source,$uuid) = @_;
    $data_source ||= $self->data_source;
    my $files   = $self->user_tracks;
    my $userdb  = $self->userdb;
    my $session = $self->session;

    return if $self->is_admin;  # admin user's tracks are already in main config file.
    $self->session->uploadsid;

    my $userdata    = $self->user_tracks;
    my @user_tracks = $userdata->tracks;

    for my $track (@user_tracks) {
	my $config_path = $userdata->track_conf($track);
	eval {$data_source->parse_user_file($config_path)};
    }

    return @user_tracks;
}

# Delete the segments so that they can be recreated with new parameters
sub delete_stored_segments {
    my $self = shift;

    delete $self->{region};
    delete $self->{region_segment};
    delete $self->{whole_segment};
}

###################### link generation ##############
sub annotation_help {
  return shift->globals->url_base."/annotation_help.html";
}

sub general_help {
  return shift->globals->url_base."/general_help.html";
}

sub join_selected_tracks {
    my $self = shift;
    my $state = $self->state;

    my @selected = $self->visible_tracks;
    for (@selected) { # escape hyphens
		if ((my $filter = $state->{features}{$_}{filter}{values})) {
			my @subtracks = grep {$filter->{$_}} keys %{$filter};
			$_ .= "/@subtracks";
		}
    }
    return $self->join_tracks(\@selected);
}

sub join_tracks {
    my $self = shift;
    my $tracks = shift;
    return join LABEL_SEPARATOR,@$tracks;
}

sub bookmark_link {
  my $self     = shift;
  my $settings = shift;

  my $q = new CGI('');
  my @keys = qw(start stop ref width version flip grid);
  foreach (@keys) {
    $q->param(-name=>$_,   -value=>$settings->{$_});
  }
  $q->param(-name=>'id',   -value=>$settings->{userid});  # slight inconsistency here
  $q->param(-name=>'l',    -value=>$self->join_selected_tracks);

  $q->param(-name=>'h_region',-value=>$settings->{h_region}) if $settings->{h_region};
  my @h_feat= map {"$_\@$settings->{h_feat}{$_}"} keys %{$settings->{h_feat}};
  $q->param(-name=>'h_feat',  -value=>\@h_feat) if @h_feat;
  return "?".$q->query_string();
}

sub gff_dump_link {
  my $self     = shift;
  my $fasta    = shift;

  my $state     = $self->state;
  my $upload_id = $self->session->uploadsid;
  my $segment   = $self->thin_segment or return '';

  my $q = new CGI('');
  if ($fasta) {
      $q->param(-name=>'gbgff',   -value=>'Fasta');
      $q->param(-name=>'m',       -value=>'application/x-fasta');
  } else {
       $q->param(-name=>'gbgff',   -value=>'Save');
       $q->param(-name=>'m',       -value=>'application/x-gff3');
  }

  # This will now be detemined and added on the client side
  #$q->param('q'=>$segment->seq_id.':'.$segment->start.'..'.$segment->end);

  # we probably need this ?
  $q->param(-name=>'id',      -value=>$upload_id);

  # handle external urls
  return "?".$q->query_string();
}

sub dna_dump_link {
  my $self     = shift;
  my $link     = $self->gff_dump_link('fastaonly');
  return $link;
}

sub galaxy_link {
    my $self = shift;
    my $settings   = shift || $self->state;

    my $galaxy_url = $settings->{GALAXY_URL} 
                     || $self->data_source->global_setting('galaxy outgoing');

    warn "[$$] galaxy_link = $galaxy_url" if DEBUG;
    return '' unless $galaxy_url;
    my $clear_it  = $self->galaxy_clear;
    my $submit_it = q(document.galaxyform.submit());							#}) - Syntax highlight fixing.
    return "$clear_it;$submit_it";
}

sub galaxy_clear {
    return q(new Ajax.Request(document.URL,{method:'post',postBody:'clear_galaxy=1'}));
}


sub image_link {
    my $self = shift;
    my $settings = shift;
    my $format   = shift;

    $format      = 'GD' unless $format && $format=~ /^(GD|GD::SVG|PDF)$/;

    my $source   = $self->data_source->name;
    my $id       = $self->session->id;
    my $flip     = $settings->{flip} || param('flip') || 0;
    my $keystyle = $settings->{ks};
    my $grid     = $settings->{grid} || 0;
    my ($base,$s) = $self->globals->gbrowse_base;
    my $url      = "$base/gbrowse_img/$s";
    my $tracks   = $settings->{tracks};
    my $width    = param('view_width') || $settings->{width};
    my $start    = param('view_start') || $settings->{view_start};
    my $stop     = param('view_stop')  || $settings->{view_stop};
    $stop++;
    my $name     = "$settings->{ref}:$start..$stop";
    my $selected = $self->join_selected_tracks;
    my $options  = join '+',map { join '+', CGI::escape($_),$settings->{features}{$_}{options}
                             } map {/\s/?"$_":$_}
    grep {
		$settings->{features}{$_}{options}
    } @$tracks;
    $id        ||= ''; # to prevent uninit variable warnings
    my $img_url  = "$url/?name=$name;l=$selected;width=$width;id=$id";
    $img_url    .= ";flip=$flip"         if $flip;
    $img_url    .= ";options=$options"   if $options;
    $img_url    .= ";format=$format"     if $format;
    $img_url    .= ";keystyle=$keystyle" if $keystyle;
    $img_url    .= ";grid=$grid";
    $self->add_hilites($settings,\$img_url);

    return $img_url
}

sub add_hilites {
    my $self     = shift;

    my $settings = shift;
    my $img_url  = shift;

  # add feature hilighting
    if ($settings->{h_feat} && ref $settings->{h_feat} eq 'HASH') {
		for my $h (keys %{$settings->{h_feat}}) {
			$$img_url .= ";h_feat=$h\@$settings->{h_feat}{$h}";
		}
    }
  # add region hilighting
    if ($settings->{h_region} && ref $settings->{h_region} eq 'ARRAY') {
		for my $h (@{$settings->{h_region}}) {
			$$img_url .= ";h_region=$h";
		}
    }
}

sub svg_link {
    my $self = shift;
    my $settings = shift;
    return "?help=svg_image;flip=".($settings->{flip}||0);
}

sub fcgi_request {
    my $self = shift;
    return $FCGI_REQUEST if defined $FCGI_REQUEST;

    unless (eval 'require FCGI;1') {
	return $FCGI_REQUEST = 0;
    }

    my $request  = FCGI::Request(\*STDIN,\*STDOUT,\*STDERR,\%ENV,0,FCGI::FAIL_ACCEPT_ON_INTR());
    return $FCGI_REQUEST = ($request && $request->IsFastCGI ? $request : 0);
}

sub fork {
    my $self = shift;
    
    $self->prepare_modperl_for_fork();
    $self->prepare_fcgi_for_fork('starting');

    my $child = CORE::fork();
    print STDERR "forked $child" if DEBUG;
    die "Couldn't fork: $!" unless defined $child;

    if ($child) { # parent process
	$self->session->was_forked('parent') if ref $self;
	$self->prepare_fcgi_for_fork('parent');
    }

    else {
	$self->session->was_forked('child')  if ref $self;
	Bio::Graphics::Browser2::DataBase->clone_databases();
	Bio::Graphics::Browser2::Render->prepare_fcgi_for_fork('child');
	if (ref $self) {
	    $self->userdb->clone_database()      if $self->userdb;
	    $self->user_tracks->clone_database() if $self->user_tracks;
	}
    }

    return $child;
}


sub prepare_modperl_for_fork {
    my $self = shift;
    my $r    = modperl_request() or return;
    if ($ENV{MOD_PERL_API_VERSION} < 2) {
	eval {
	    require Apache::SubProcess;
	    $r->cleanup_for_exec() 
	}
    };
}

sub prepare_fcgi_for_fork {
    my $self  = shift;
    my $state = shift;
    my $req   = $self->fcgi_request() or return;
    if ($state eq 'starting') {
	$req->Detach();
    } elsif ($state eq 'parent') {
	$req->Attach();
    } elsif ($state eq 'child') {
	$req->LastCall();
	$FCGI_REQUEST = 0;
	undef *FCGI::DESTROY;
    }
}

# try to generate a chrom sizes file
sub chrom_sizes {
    my $self   = shift;
    my $source = $self->data_source;
    my $mtime  = $source->mtime;
    my $name   = $source->name;
    my $sizes  = File::Spec->catfile($self->globals->tmpdir('chrom_sizes'),"$name.sizes");
    if (-e $sizes && (stat(_))[9] >= $mtime) {
	return $sizes;
    }
    $self->generate_chrom_sizes($sizes) or return;
    return $sizes;
}

sub generate_chrom_sizes {
    my $self  = shift;
    my $sizes = shift;

    my $source = $self->data_source;

    open my $s,'>',$sizes or die "Can't open $sizes for writing: $!";

    # First, try to query the default database for the
    # seq_ids it knows about.
    my $db     = $source->open_database or return;

    # Bio::DB::SeqFeature has a seq_ids method.
    if (my @seqids = eval {$db->seq_ids}) {
	for (@seqids) {
	    my $segment = $db->segment($_) or die "Can't find chromosome $_ in default database";
	    print $s "$_\t",$segment->length,"\n";
	}
	close $s;
	return 1;
    }

    # Bio::DasI objects have an entry_points method
    if (my @segs = eval {$db->entry_points}) {
	for (@segs) {
	    print $s $_,"\t",$_->length,"\n";
	}
	close $s;
	return 1;
    }

    # Otherwise we search for databases with associated fasta files
    # or indexed fasta (fai) files.
    my ($fasta,$fastai);
    my @dbs    = $source->databases;
    for my $db (@dbs) {
	my ($dbid,$adaptor,%args) = $source->db2args($db);
	my $fasta = $args{-fasta} or next;
	if (-e "$fasta.fai") {
	    $fastai ||= "$fasta.fai";
	} elsif (-e $fasta && -w dirname($fasta)) {
	    $fasta  ||= $fasta;
	}
    }

    return unless $fasta or $fastai;

    if (!$fastai && eval "require Bio::DB::Sam;1") {
	Bio::DB::Sam::Fai->load($fasta);
	$fastai = "$fasta.fai";
    }

    if ($fastai) { # fai file -- copy to sizes
	open my $f,$fastai or die "Can't open $fasta: $!";
	while (<$f>) {
	    my ($seqid,$length) = split /\s+/;
	    print $s "$seqid\t$length\n";
	}
	close $f;
    }

    elsif (eval "require Bio::DB::Fasta; 1") {
	my $fa = Bio::DB::Fasta->new($fasta);
	my @ids = $fa->ids;
	for my $i (@ids) {
	    print $s $i,"\t",$fa->length($i),"\n";
	}
	undef $fa;
    }

    close $s;
    return 1;
}

# Change IDs (Old Uploads ID, New Uploads ID, Old UserID, New User ID) - Sometimes the user's session (as stored by the ID) is unretrievable - this changes the session to a new one so that a user's login is still valid.
sub change_ids {
    my $self = shift;
    my $old_uploadsid = shift;
    my $new_uploadsid = shift;
    my $old_userid = shift;
    my $new_userid = shift;
    my $usertracks = $self->user_tracks;
    $usertracks->change_ids($old_uploadsid, $new_uploadsid, $old_userid, $new_userid);
    my $userdb = $self->{userdb};
    $userdb->change_ids($old_uploadsid, $new_uploadsid, $old_userid, $new_userid);
}

# The following functions are implemented in HTML.pm (or any other Render subclass), are never called, and are here for debugging.
sub format_autocomplete {
    croak "implement in subclass";
}

sub render_actionmenu {
    my $self = shift;
    croak "implement in subclass";
}

sub render_tabbed_pages {
    my $self = shift;
    my ($main,$upload_share,$config) = @_;
    croak "implement in subclass";
}

sub render_select_track_link {
    croak "implement in subclass";
}

sub render_upload_share_section {
    croak "implement in subclass";
}

sub render_top    {
  my $self     = shift;
  my $title    = shift;
  croak "render_top() should not be called in parent class";
}

sub render_title   {
  my $self     = shift;
  my $title    = shift;
  croak "render_title() should not be called in parent class";
}

sub render_navbar {
  my $self = shift;
  my $seg  = shift;
  croak "render_navbar() should not be called in parent class";
}

sub clear_highlights { croak 'implement in subclass' }

sub render_toggle_track_table {
  my $self = shift;
  croak "render_toggle_track_table() should not be called in parent class";
}

sub render_track_table {
  my $self = shift;
  croak "render_track_table() should not be called in parent class";
}

sub render_instructions {
  my $self  = shift;
  my $title = shift;
  croak "render_instructions() should not be called in parent class";
}
sub render_multiple_choices {
  my $self = shift;
  croak "render_multiple_choices() should not be called in parent class";
}

sub render_global_config {
  my $self = shift;
  croak "render_global_config() should not be called in parent class";
}

sub render_toggle_external_table {
  my $self = shift;
  croak "render_toggle_external_table() should not be called in parent class";
}

sub render_toggle_userdata_table {
  my $self = shift;
  croak "render_toggle_userdata_table() should not be called in parent class";
}

sub render_bottom {
  my $self = shift;
  my $features = shift;
  croak "render_bottom() should not be called in parent class";
}

sub html_frag {
  my $self = shift;
  croak "html_frag() should not be called in parent class";
}

sub fatal_error {
  my $self = shift;
  my @msg  = @_;
  croak 'Please call fatal_error() for a subclass of Bio::Graphics::Browser2::Render';
}

sub zoomBar {
    my $self = shift;
    croak 'Please define zoomBar() in a subclass of Bio::Graphics::Browser2::Render';
}

sub track_config {
  my $self     = shift;
  my $track_name    = shift;
  croak "track_config() should not be called in parent class";
}

sub select_subtracks {
  my $self       = shift;
  my $track_name = shift;
  croak "select_subtracks() should not be called in parent class";
}

sub share_track {
  my $self     = shift;
  my $track_name    = shift;
  croak "share_track() should not be called in parent class";
}

sub render_ruler_div {
  my $self = shift;
  croak "render_ruler_div() should not be called in parent class";
}

########## note: "sub tr()" makes emacs' syntax coloring croak, so place this function at end
sub translate {
	my $self = shift;
	my $lang = $self->language or return @_;
	$lang->translate(@_);
}

sub login_manager {
    my $self = shift;
    return $self->{login_manager} if exists $self->{login_manager};
    eval "require Bio::Graphics::Browser2::Render::Login" unless
	Bio::Graphics::Browser2::Render::Login->can('new');
    return $self->{login_manager} = Bio::Graphics::Browser2::Render::Login->new($self);
}

sub snapshot_manager {
    my $self = shift;
    return $self->{snapshot_manager} ||= Bio::Graphics::Browser2::Render::SnapshotManager->new($self);
}

sub feature_summary_message {
    my $self = shift;
    my ($event_type,$label) = @_;
    my $sticky = $event_type eq 'mousedown' || 0;
    my $message= $self->data_source->setting($label=>'key'). ' '.lc($self->tr('FEATURE_SUMMARY'));
    return "GBubble.showTooltip(event,'$message',$sticky)";
}

sub feature_interaction {
    my $self = shift;
    my ($event_type,$label,$feature) = @_;
    my $source    = $self->data_source;
    my $settings  = $self->state;
    my $tips      = $source->global_setting('balloon tips') && $settings->{'show_tooltips'};
    my $renderer  = $self->get_panel_renderer($self->segment);

    if ($tips) {
	my $sticky  = $source->setting($label,'balloon sticky');
	my $height  = $source->setting($label,'balloon height') || 300;

	my $stick   = defined $sticky ? $sticky : $event_type eq 'mousedown';
	$stick     ||= 0;
	my ($balloon_style,$balloon_action) 
	    = $renderer->balloon_tip_setting($event_type eq 'mousedown' ? 'balloon click' : 'balloon hover',$label,$feature,undef,undef);
	$balloon_action ||= $renderer->make_title($feature,undef,$label,undef) 
	    if $source->global_setting('titles are balloons') && $event_type eq 'mouseover';
	$balloon_style  ||= 'GBubble';
	if ($balloon_action) {
	    my $action = $balloon_action =~ /^(http|ftp):/
		? "$balloon_style.showTooltip(event,'<iframe width='+$balloon_style.maxWidth+' height=$height " .
		"frameborder=0 src=$balloon_action></iframe>',$stick,$balloon_style.maxWidth)"
		: "$balloon_style.showTooltip(event,'$balloon_action',$stick)";
	    return ('text/plain',$action)
	}
    }

    my $link   = $renderer->make_link($feature,undef,$label,undef);
    my $target = $renderer->make_link_target($feature,undef,$label,undef);
    return ('text/plain',$target ? "window.open('$link','$target')" : "document.location='$link'") if $link;
    return;
}
sub tr {
	my $self = shift;
	my $lang = $self->language or return @_;
	$lang->translate(@_);
}

1;

