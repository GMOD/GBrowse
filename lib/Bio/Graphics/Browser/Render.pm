package Bio::Graphics::Browser::Render;

use strict;	
use warnings;

use JSON;
use Digest::MD5 'md5_hex';
use CGI qw(:standard param request_method header url iframe img span div br center);
use Carp 'croak','cluck';
use File::Basename 'dirname';
use Text::Tabs;

use Bio::Graphics::Browser::I18n;
use Bio::Graphics::Browser::PluginSet;
use Bio::Graphics::Browser::UploadSet;
use Bio::Graphics::Browser::RemoteSet;
use Bio::Graphics::Browser::Shellwords;
use Bio::Graphics::Browser::Region;
use Bio::Graphics::Browser::RegionSearch;
use Bio::Graphics::Browser::RenderPanels;
use Bio::Graphics::Browser::GFFPrinter;
use Bio::Graphics::Browser::Util qw[get_section_from_label url_label];

use constant VERSION              => 2.0;
use constant DEBUG                => 0;
use constant OVERVIEW_SCALE_LABEL => 'Overview Scale';
use constant REGION_SCALE_LABEL   => 'Region Scale';
use constant DETAIL_SCALE_LABEL   => 'Detail Scale';
use constant EMPTY_IMAGE_HEIGHT   => 40;
use constant MAX_SEGMENT          => 1_000_000;
use constant TOO_MANY_SEGMENTS    => 5_000;
use constant OVERVIEW_RATIO       => 1.0;


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

  warn "RUN(): URI = ",url(-path=>1,-query=>1) if DEBUG;

  $self->set_source();

  return if $self->run_asynchronous_event;

  $self->init();
  $self->update_state();
  $self->render();
  $self->cleanup();
  select($old_fh);

  $self->session->flush;
}

sub set_source {
    my $self = shift;

    my $source = $self->session->source;

    if (CGI::unescape(CGI::path_info()) ne CGI::unescape("/$source/")) {
	my $args = CGI::query_string();
	my $url  = CGI::url(-absolute=>1,-path_info=>0);
	$url     =~ s!(gbrowse[^/]*)/.+$!$1!;  # fix CGI/Apache bug
	$url    .= "/$source/";
	# clear out some of the session variables that shouldn't transfer
	# delete $self->state->{name};
	# delete $self->state->{q};
	$url .= "?$args" if $args;
	print CGI::redirect($url);
	return 1;
    }
    return;
}

sub init {
    my $self = shift;
    $self->set_default_state();
    $self->init_database();
    $self->init_plugins();
    $self->init_remote_sources();
}

# this prints out the HTTP data from an asynchronous event
sub run_asynchronous_event {
    my $self = shift;
    my ($status,$mime_type,$data) = $self->asynchronous_event
	or return;

    if ($status == 204) { # no content
	print CGI::header( -status => '204 No Content' );
    }
    elsif ($status == 302) { # redirect
	warn CGI::redirect($data);
	print CGI::redirect($data);
    }
    elsif ($mime_type eq 'application/json') {
	print CGI::header(-status=>$status,
			  -type  => $mime_type),
	      JSON::to_json($data);
    }
    else {
	print CGI::header(-status => $status,
			  -type   => $mime_type),
	       $data;
    }
    return 1;  # no further processing needed
}

# handle asynchronous events
#
# asynchronous requests:
#
# div_visible_<label>=bool              Turn on/off visibility of track with <label>
# track_collapse_<label>=bool           Collapse/uncollapse track with <label>
# label[]=<label1>,label[]=<label2>...  Change track order
# render=<label1>,render=<label2>...    Render the specified tracks
# navigate=
#
# returns ($http_status,$mime_type,$body_data)
sub asynchronous_event {
    my $self     = shift;
    my $settings = $self->state;
    my $events;

    warn "event(",(join ' ',param()),")" if DEBUG;

    if ( my $action = param('navigate') ) {

        $self->init_database();
        $self->asynchronous_update_coordinates($action);

        my ( $track_keys, $display_details, $details_msg )
            = $self->background_track_render();

        my $overview_scale_return_object
            = $self->asynchronous_update_overview_scale_bar();
        my $region_scale_return_object
            = $self->asynchronous_update_region_scale_bar()
            if ( $settings->{region_size} );
        my $detail_scale_return_object
            = $self->asynchronous_update_detail_scale_bar();
        my $segment_info_object = $self->segment_info_object();

	warn "navigate() returning track keys = ",join ' ',%$track_keys if DEBUG;

        my $return_object = {
            segment            => $settings->{name},
            segment_info       => $segment_info_object,
            track_keys         => $track_keys,
            display_details    => $display_details,
            details_msg        => $details_msg,
            overview_scale_bar => $overview_scale_return_object,
            region_scale_bar   => $region_scale_return_object,
            detail_scale_bar   => $detail_scale_return_object,
        };
	return (200,'application/json',$return_object);
    }

    if ( my $action = param('first_render') ) {

	return (204,'text/plain','no content') 
	    unless $self->state->{valid_region};

        $self->init_database();
        my ( $track_keys, $display_details, $details_msg )
            = $self->background_track_render();
        return unless ( $track_keys || $details_msg );

        my $segment_info_object = $self->segment_info_object();

        my $return_object = {
            segment         => $settings->{name},
            segment_info    => $segment_info_object,
            track_keys      => $track_keys,
            display_details => $display_details,
            details_msg     => $details_msg,
        };
        return ( 200, 'application/json', $return_object );
    }

    if ( param('update_sections') ) {
        my @section_names = param('section_names');

        my $section_html
            = $self->asynchronous_update_sections( \@section_names );
        my $return_object = { section_html => $section_html, };
        return ( 200, 'application/json', $return_object );
    }

    if ( my $track_name = param('configure_track') ) {
        my $html = $self->track_config($track_name);
        return ( 200, 'text/html', $html );
    }

    if ( my $track_name = param('reconfigure_track') ) {
        $self->reconfigure_track($track_name);
        return ( 200, 'application/json', {} );
    }

    if ( my $track_name = param('share_track') ) {
        my $html = $self->share_track($track_name);
        return ( 200, 'text/html', $html );
    }

    if ( my $element = param('update') ) {
        warn "UPDATE HAS BEEN DEPRICATED";
        my $html = $self->asynchronous_update_element($element);
	return (200,'text/html',$html);
    }

    if ( param('retrieve_multiple') ) {
        $self->init_database();
        $self->init_plugins();
        $self->init_remote_sources();

        my %track_html;
        my @track_names = param('track_names');

        foreach my $track_name (@track_names) {
            my $track_key = param( 'tk_' . $track_name ) or next;
            $track_html{$track_name} = $self->render_deferred_track(
                cache_key  => $track_key,
                track_name => $track_name,
            ) || '';
        }

        my $return_object = { track_html => \%track_html, };
        return ( 200, 'application/json', $return_object );
    }

    if ( my $action = param('add_tracks') ) {
        my @track_names = param('track_names');

        $self->init_database();
        $self->init_plugins();
        $self->init_remote_sources();
        my %track_data;

        foreach my $track_name ( @track_names ) {
            $self->add_track_to_state($track_name);
	    next  unless $self->segment;

            my ( $track_keys, $display_details, $details_msg )
                = $self->background_individual_track_render($track_name);

            my $track_key        = $track_keys->{$track_name};
            my $track_section    = get_section_from_label($track_name);
            my $image_width      = $self->get_image_width;
            my $image_element_id = $track_name . "_image";

            my $track_html;
            if ( $track_section eq 'detail' and not $display_details ) {
                my $image_width = $self->get_image_width;
                $track_html .= $self->render_grey_track(
                    track_name       => $track_name,
                    image_width      => $image_width,
                    image_height     => EMPTY_IMAGE_HEIGHT,
                    image_element_id => $track_name . "_image",
                );
            }
            else {
                $track_html = $self->render_deferred_track(
                    cache_key  => $track_key,
                    track_name => $track_name,
                ) || '';
            }
            $track_html = $self->wrap_track_in_track_div(
                track_name => $track_name,
                track_html => $track_html,
            );

            my $panel_id = 'detail_panels';
            if ( $track_name =~ /:overview$/ ) {
                $panel_id = 'overview_panels';
            }
            elsif ( $track_name =~ /:region$/ ) {
                $panel_id = 'region_panels';
            }

            $track_data{$track_name} = {
                track_key        => $track_key,
                track_name       => $track_name,
                track_html       => $track_html,
                track_section    => $track_section,
                image_element_id => $image_element_id,
                panel_id         => $panel_id,
                display_details  => $display_details,
                details_msg      => $details_msg,
            };
        }

        my $return_object = { track_data => \%track_data, };
        return ( 200, 'application/json', $return_object );
    }
    if ( param('set_track_visibility') ) {
        my $visible    = param('visible');
        my $track_name = param('track_name');

        if ($visible) {
            $self->add_track_to_state($track_name);
        }
        else {
            $self->remove_track_from_state($track_name);
        }

        return (204,'text/plain',undef);
    }

    if ( my $action = param('rerender_track') ) {
        my $track_name = param('track_name');

        $self->init_database();
        $self->init_plugins();
        $self->init_remote_sources();

        my ( $track_keys, $display_details, $details_msg )
            = $self->background_individual_track_render($track_name);

        my $return_object = {
            track_keys      => $track_keys,
            display_details => $display_details,
            details_msg     => $details_msg,
        };
        return (200,'application/json',$return_object);
    }

    if ( param('reconfigure_plugin') ) {

        # init_plugins will do the configure call needed
        $self->init_plugins();
	return (204,'text/plain',undef);
    }

    if ( param('commit_file_edit') ) {
        my $data        = param('a_data');
        my $edited_file = param('edited_file');

        return ( 204, 'text/plain', undef ) unless ( $edited_file and $data );
        $self->init_remote_sources();
        my $file_created = $self->handle_edit( $edited_file, $self->state, $data );

        my $return_object = {
            file_created   => $file_created,
        };

        return (200,'application/json',$return_object);
    }

    if ( param('delete_upload_file') ) {
        my $file = param('file');
        $self->init_remote_sources();
        $self->uploaded_sources->clear_file($file);
        $self->remote_sources->delete_source($file);
        $self->remove_track_from_state($file);

        return (204,'text/plain',undef);
    }

    # toggle the visibility of sections by looking for "div_visible_*"
    # parameters
    for my $p ( grep {/^div_visible_/} param() ) {
        my $visibility = param($p);
        $p =~ s/^div_visible_//;
        $settings->{section_visible}{$p} = $visibility;
        $events++;
    }

    # toggle the visibility of individual tracks
    for my $p ( grep {/^track_collapse_/} param() ) {
        my $collapsed = param($p);
        $p =~ s/^track_collapse_//;
	warn "\$settings->{track_collapsed}{$p} = $collapsed" if DEBUG;
        $settings->{track_collapsed}{$p} = $collapsed;
        $events++;
    }

    # Change the order of tracks if any "label[]" parameters are present
    if ( my @labels = param('label[]') ) {
        foreach (@labels) {s/%5F/_/g}
        my %seen;
        @{ $settings->{tracks} } = grep { length() > 0 && !$seen{$_}++ }
            ( @labels, @{ $settings->{tracks} } );
        $events++;
    }

    # Slightly different -- process a tracks request in the background.
    if ( my @labels = param('render') ) {    # deferred rendering requested
        $self->init_database();
        $self->init_plugins();
        $self->init_remote_sources();
        my $features = $self->region->features;
        my $seg      = $self->features2segments($features)->[0];    # likely wrong

        $self->set_segment($seg);

        my $deferred_data = $self->render_deferred( labels => \@labels );
	return (200,'application/json',$deferred_data);
    }

    # miscellaneous options
    if (param('set_display_option')) {
	$self->update_options();
	$events++;
    }

    # redirect to the bookmark
    if (param('bookmark')) {
	return (302,undef,$self->bookmark_link($self->state));
    }

    # redirect to the imagelink
    if (my $format = param('make_image')) {
	return (302,undef,$self->image_link($self->state,$format));
    }

    return unless $events;
    warn "processing asynchronous event(s)" if DEBUG;
    return (204,'text/plain',undef);
    $self->session->flush if $self->session;
    1;
}

sub background_track_render {
    my $self = shift;

    $self->session->unlock(); # don't hold session captive on renderers!
    
    $self->init_plugins();
    $self->init_remote_sources();

    $self->segment or return;
    my $cache_extra = $self->create_cache_extra();
    my $external    = $self->external_data,

    # Start rendering the detail, region and overview tracks
    my @cache_track_hash_list;
    my $display_details = 1;
    my $details_msg = '';
    if ( $self->segment->length <= $self->get_max_segment() ) {
        push @cache_track_hash_list,
            $self->render_deferred(
            labels          => [ $self->detail_tracks ],
            segment         => $self->segment,
            section         => 'detail',
            cache_extra     => $cache_extra,
            external_tracks => $external
            );
    }
    else{
        $display_details = 0;
        $details_msg = h1(
            $self->tr(
                'TOO_BIG',
                scalar $self->data_source()->unit_label($self->get_max_segment),
            )
        );
    }
    push @cache_track_hash_list,
        $self->render_deferred( labels          => [ $self->regionview_tracks ],
				segment         => $self->region_segment,
				section         => 'region', 
				cache_extra     => $cache_extra, 
				external_tracks => $external,
	    )
        if ( $self->state->{region_size} );
    push @cache_track_hash_list,
        $self->render_deferred( labels          => [ $self->overview_tracks ],
				segment         => $self->whole_segment,
				section         => 'overview', 
				cache_extra     => $cache_extra, 
				external_tracks => $external,
	    );

    my %track_keys;
    foreach my $cache_track_hash (@cache_track_hash_list) {
        foreach my $track_label ( keys %{ $cache_track_hash || {} } ) {
            $track_keys{ $track_label }
                = $cache_track_hash->{$track_label}->key();
        }
    }

    return (\%track_keys, $display_details, $details_msg);
}

sub create_cache_extra {
    my $self     = shift;
    my $settings = $self->state();
    my @cache_extra = (
            $settings->{show_tooltips},
            $settings->{start},
            $settings->{stop},
        );
    push @cache_extra,sort keys %{$settings->{h_feat}} if $settings->{h_feat};
    push @cache_extra,sort @{$settings->{h_region}}    if $settings->{h_region};
     push @cache_extra, map { $_->config_hash() } $self->plugins->plugins;
    return \@cache_extra;
}

sub background_individual_track_render {
    my $self = shift;
    my $label = shift;

    my $display_details = 1;
    my $details_msg = '';
    
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
	and $self->segment
        and $self->segment->length > $self->get_max_segment() )
    {
        $display_details = 0;
        $details_msg     = h1(
            $self->tr(
                'TOO_BIG',
                scalar $self->data_source()->unit_label(MAX_SEGMENT),
            )
        );
        my %track_keys = ( $label => 0 );
        return ( \%track_keys, $display_details, $details_msg );
    }

    my $cache_extra = $self->create_cache_extra();

    # Start rendering the detail and overview tracks
    my $cache_track_hash = $self->render_deferred( 
	labels       => [ $label, ],
	segment     => $segment, 
        section     => $section, 
	cache_extra => $cache_extra, 
	external_tracks => $self->external_data,
	);

    my %track_keys;
    foreach my $cache_track_hash ( $cache_track_hash, ) {
        foreach my $track_label ( keys %{ $cache_track_hash || {} } ) {
            $track_keys{ $track_label }
                = $cache_track_hash->{$track_label}->key();
        }
    }

    return (\%track_keys, $display_details, $details_msg);
}

sub render {
  my $self           = shift;

  # NOTE: these handle_* methods will return true
  # if they want us to exit before printing the header
  $self->handle_gff_dump()  && return;
  $self->handle_plugins()   && return;
  $self->handle_downloads() && return;

  $self->render_header();
  $self->render_body();
}

sub render_header {
  my $self    = shift;
  my $cookie = $self->create_cookie();
  print CGI::header(
    -cookie  => $cookie,
    -charset => $self->tr('CHARSET')
  );
}

sub create_cookie {
  my $self    = shift;
  my $session = $self->session;
  my $cookie = CGI::Cookie->new(
    -name    => $CGI::Session::NAME,
    -value   => $session->id,
    -path    => url(-absolute => 1),
    -expires => $self->globals->remember_settings_time
  );
  return $cookie;
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

  my $title    = $self->generate_title($features);

  print $self->render_top($title);
  print $self->render_title($title);
  print $self->render_instructions;

  if ($region->feature_count > 1) {
      print $self->render_navbar();
      print $self->render_multiple_choices($features,$self->state->{name});
      print $self->render_config();
  }

  elsif (my $seg = $region->seg) {
      print $self->render_navbar($seg);
      print $self->render_panels($seg,{overview=>1,regionview=>1,detailview=>1});
      print $self->render_config($seg);
  }
  else {
      print $self->render_navbar();
      print $self->render_config();
  }

  print $self->render_bottom($features);
}


sub generate_title {
    my $self     = shift;
    my $features = shift;

    my $dsn         = $self->data_source;
    my $description = $dsn->description;

    return $description unless $features;
    return @$features == 1 
             ? "$description: ".$features->[0]->seq_id
                               .":"
                               .$features->[0]->start
                               .'..'
                               .$features->[0]->end
             : "$description: ".$self->tr('HIT_COUNT',scalar @$features);
}

# never called, method in HTML.pm with same name is run instead
sub render_top    {
  my $self     = shift;
  my $title    = shift;
  croak "render_top() should not be called in parent class";
}

# never called, method in HTML.pm with same name is run instead
sub render_title   {
  my $self     = shift;
  my $title    = shift;
  croak "render_title() should not be called in parent class";
}

#never called, method in HTML.pm with same name is run instead
sub render_navbar {
  my $self = shift;
  my $seg  = shift;
  croak "render_navbar() should not be called in parent class";
}

# Provide segment info for rubberbanding
sub segment_info_object {
    my $self          = shift;
    my $settings      = $self->state;
    my $segment       = $self->segment;
    my $whole_segment = $self->whole_segment;

    my $renderer = $self->get_panel_renderer($segment);

    my $pad = $self->data_source->global_setting('pad_left')
        || $renderer->image_padding
        || 0;
    my $max = $self->get_max_segment;
    my $width = ( $settings->{width} * OVERVIEW_RATIO );

    my %segment_info_object = (
        image_padding        => $pad,
        max_segment          => $max,
        overview_start       => $whole_segment->start,
        overview_stop        => $whole_segment->end,
        overview_pixel_ratio => $whole_segment->length / $width,
        detail_start         => $segment->start,
        detail_stop          => $segment->end,
        'ref'                => $segment->seq_id,
        details_pixel_ratio  => $segment->length / $settings->{width},
        detail_width         => $settings->{width} + 2 * $pad,
        overview_width       => $width + 2 * $pad,
    );

    if ( $settings->{region_size} ) {
        my ( $rstart, $rend )
            = $self->get_regionview_start_stop( $settings, $segment->start, $segment->end,
            $whole_segment->start, $whole_segment->end );
        my $rlen  = abs( $rend - $rstart );
        my $ratio = $rlen / $width;
        $segment_info_object{'region_start'}       = $rstart;
        $segment_info_object{'region_stop'}        = $rend;
        $segment_info_object{'region_pixel_ratio'} = $rlen / $width;
    }
    return \%segment_info_object;
}

sub render_panels {
    my $self    = shift;
    my $seg     = shift;
    my $section = shift;

    my $html = '';

    my $cache_extra = $self->create_cache_extra();

    # Kick off track rendering
    if ($section->{'overview'} ) {
        my $scale_bar_html = $self->scale_bar( $seg, 'overview', );
        my $panels_html   .= $self->get_blank_panels( [$self->overview_tracks,] );
        my $drag_script    = $self->drag_script( 'overview_panels', 'track' );
        $html .= div(
            $self->toggle(
                'Overview',
                div({ -id => 'overview_panels', -class => 'track' },
                    $scale_bar_html, $panels_html,
                )
            )
        ) . $drag_script;
    }

    if ( $section->{'regionview'} and $self->state->{region_size} ) {

        my $scale_bar_html = $self->scale_bar( $seg, 'region' );
        my $panels_html   .= $self->get_blank_panels( [$self->regionview_tracks,] );
        my $drag_script    = $self->drag_script( 'region_panels', 'track' );

        $html .= div(
            $self->toggle(
                'Region',
                div({ -id => 'region_panels', -class => 'track' },
                    $scale_bar_html, $panels_html,
                )
            )
        ) . $drag_script;
    }

    if ( $section->{'detailview'} ) {
        my $scale_bar_html = $self->scale_bar( $seg, 'detail' );
        my $panels_html   .= $self->get_blank_panels( [$self->detail_tracks,] );
        my $drag_script    = $self->drag_script( 'detail_panels', 'track' );
        my $details_msg    = div({ -id => 'details_msg', },'');
        $html .= div(
            $self->toggle(
                'Details',
                div({ -id => 'detail_panels', -class => 'track' },
                    $details_msg,$scale_bar_html, $panels_html,
                )
            )
        ) . $drag_script;
    }

    return $html;
}

sub scale_bar {
    my $self         = shift;
    my $seg          = shift;
    my $this_section = shift || 'detail';

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
            state   => $self->state
        );
    }
    my $html = $renderer->wrap_rendered_track(
        label      => $label,
        area_map   => [],
        width      => $width,
        height     => $height,
        url        => $url,
        status     => '',
    );
    $html = $self->wrap_track_in_track_div(
        track_name => $label,
        track_html => $html,
        track_type => 'scale_bar',
    );
    return $html
}

sub render_config {
  my $self = shift;
  my $seg = shift;
  return $self->render_toggle_track_table(). 
      $self->render_global_config().
      $self->render_toggle_external_table;
}

#never called, method in HTML.pm with same name is run instead
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

sub render_external_table {
  my $self = shift;
  croak "render_external_table() should not be called in parent class";
}

sub render_bottom {
  my $self = shift;
  my $features = shift;
  croak "render_bottom() should not be called in parent class";
}

sub init_database {
  my $self = shift;

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
    elsif ($self->state->{ref}) { # a known region
	$region->set_features_by_region(@{$self->state}{'ref','start','stop'});
    }
    else { # a feature search
	warn "FEATURE SEARCH" if DEBUG;
	my $search = Bio::Graphics::Browser::RegionSearch->new(
	    { source => $self->data_source,
	      state  => $self->state,
	    });
	$search->init_databases(
	    param('dbid') ? [param('dbid')]
	                  :()
	    );
	my $features = $search->search_features();
	$region->features($features);
    }

    $self->plugins->set_segments($region->segments) if $self->plugins;

    $self->state->{valid_region} = $region->feature_count > 0;
    return $self->{region} = $region;
}

sub segment {
    my $self   = shift;
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
    $action = $self->tr(param('plugin_do')) || $self->tr('Go');
  }
  $action ||= param('plugin_action');
  return $action;
}

sub current_plugin {
  my $self = shift;
  my $plugin_base = param('plugin') or return;
  $self->plugins->plugin($plugin_base);
}

sub plugin_find {
  my $self = shift;
  my ($plugin,$search_string) = @_;

  my $settings = $self->state;
  my $plugin_name = $plugin->name;
  my ($results,$keyword) = $plugin->can('auto_find') && defined $search_string
                             ? $plugin->auto_find($search_string)
                             : $plugin->find();

  # nothing returned, so plug the keyword into the search box to save user's search
  unless ($results && @$results) {
      $settings->{name} = $keyword ? $keyword : $self->tr('Plugin_search_2',$plugin_name);
      return;
  }

  # Write informative information into the search box - not sure if this is the right thing to do.
  $settings->{name} = defined($search_string) ? $self->tr('Plugin_search_1',$search_string,$plugin_name)
                                              : $self->tr('Plugin_search_2',$plugin_name);
  $self->write_auto($results);
  return $results;
}

# Handle plug-ins that aren't taken care of asynchronously
sub handle_gff_dump {
    my $self = shift;

    return unless ( param('gbgff') );

    my $dumper = Bio::Graphics::Browser::GFFPrinter->new(
        -data_source => $self->data_source(),
        -source_name => param('src') || param('source') || path_info(),
        -segment    => param('q')          || param('segment'),
        -seqid      => param('ref')        || param('seqid'),
        -start      => param('start')      || 1,
        -end        => param('stop')       || param('end'),
        -stylesheet => param('stylesheet') || param('s'),
        -id         => param('id'),
        '-dump'     => param('d')          || '',
        -db         => $self->db(),
        -labels => [ param('type'), param('t') ],
    );
    $dumper->get_segment();

    print header( $dumper->get_mime_type );
    $dumper->print_gff3();

    return 1;
}

# Handle plug-ins that aren't taken care of asynchronously
sub handle_plugins {
    my $self = shift;

    my $plugin_base = param('plugin');
    return unless ($plugin_base);

    $self->init_plugins();

    my $plugin;
    if ($plugin_base   =~ /^plugin:(.+)/) {
	my $name       = $1;
	($plugin) = grep {$_->name eq $name } $self->plugins->plugins;
    } else {
	$plugin      = $self->plugins->plugin($plugin_base);
    }
    warn "an operation was requested on plugin $plugin_base, but this plugin has not been configured"
	unless $plugin;
    return unless $plugin;

    my $plugin_type = $plugin->type();

    my $plugin_action = param('plugin_action') || '';

    # for activating the plugin by URL
    if ( param('plugin_do') ) {
        $plugin_action = $self->tr( param('plugin_do') ) || $self->tr('Go');
    }

    my $state  = $self->state();
    my $cookie = $self->create_cookie();

    ### CONFIGURE  ###############################################
    if ($plugin_action eq $self->tr('Configure')) {
	$self->plugin_configuration_form($plugin);
	exit 0;
    }
    

    ### FIND #####################################################
    if ( $plugin_action eq $self->tr('Find') ) {

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
        and $plugin_action eq $self->tr('Go')
        and (  $segment
            or param('plugin_config')
            or $plugin->verb eq ( $self->tr('Import') || 'Import' ) )
        )
    {
        $self->do_plugin_header( $plugin, $cookie );
        $self->do_plugin_dump( $plugin, $segment, $state )
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

    #if ($segment && $state && $segment->length <= $MAX_SEGMENT) {
    #   my $feature_files = load_external_sources($segment,$state);
    #   @additional_feature_sets = values %{$feature_files};
    #}
    $plugin->dump( $segment, @additional_feature_sets );
    return 1;
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

sub cleanup {
  my $self = shift;
  my $state = $self->state;
  $state->{name} = "$state->{ref}:$state->{start}..$state->{stop}"
      if $state->{ref};  # to remember us by :-)
}

sub fatal_error {
  my $self = shift;
  my @msg  = @_;
  croak 'Please call fatal_error() for a subclass of Bio::Graphics::Browser::Render';
}

sub zoomBar {
    my $self = shift;
    croak 'Please define zoomBar() in a subclass of Bio::Graphics::Browser::Render';
}

sub write_auto {
    my $self             = shift;
    my $features         = shift;
    my $styles           = shift;
    my $setting          = $self->state();
    my $uploaded_sources = $self->uploaded_sources();
    return unless @$features;

    my $basename = "Custom_Track";
    $uploaded_sources->clear_file("file:${basename}")
        ;    # in case it's already there
    my $file = $uploaded_sources->new_file($basename);

    my %seenit;

    warn "opening $file...\n" if DEBUG;
    my $out = $uploaded_sources->open_file( $file, ">>" ) or return;
    warn "writing $file...\n" if DEBUG;

    $styles ||= [];
    for my $style (@$styles) {
        my ( $type, @options ) = shellwords($style);
        print $out "[$type]\n";
        print $out join "\n", @options;
        print $out "\n";
    }

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
        print $out "\nreference=$reference\n";
        print $out join( "\t", qq("$type"), qq("$name"), $position ), "\n";
    }
    close $out;
}

sub handle_downloads {
  my $self = shift;
  my ($file,$action)        = $self->get_file_action;

  return unless (my $to_download = (param($self->tr('Download_file'))
				    ||
				    (
				     $action 
				     && param($action) eq $self->tr('Download_file')
				    ) 
				    && $file));
  
  # This gets called if the user wants to download his annotation data
  my $download = CGI::unescape($to_download);
  (my $fname = $to_download) =~ s/^file://;
  print CGI::header(-attachment   => $fname,
		    -charset      => $self->tr('CHARSET'),
		    -type         => 'application/octet-stream');
  my $line_end = $self->line_end();
  if (my $fh   = $self->uploaded_sources->open_file($to_download)) {
    while (<$fh>) {
      chomp;
      print $_,$line_end;
    }
  }
  return 1;  # this will cause an exit from the script

  # return 1 to exit
  return;
}

sub line_end {
    my $self  = shift;
   my $agent  = CGI->user_agent();
   return "\r"   if $agent =~ /Mac/;
   return "\r\n" if $agent =~ /Win/;
   return "\n";
}


sub get_file_action {
    my $self = shift;

    my ($file_action)         = grep {/^modify\./} param();
    (my $file = $file_action) =~ s/^modify\.// if $file_action;
    $file = CGI::unescape($file);
    
    return ($file,$file_action);
}

sub handle_external_data {
  my $self = shift;

  my ($file,$action)   = $self->get_file_action;
  my $state            = $self->state;

  my $uploads = $self->uploaded_sources;
  my $remotes = $self->remote_sources;

  if ((param('Upload')||param('upload')) && (my $f = param('upload_annotations'))) {
      $file = $uploads->upload_file($f);
      $self->add_track_to_state($file);
  }

  elsif (my @data = (param('auto'),param('add'),param('a'))) {
    my @styles    = (param('style'),param('s'));
    $self->handle_quickie($state,\@data,\@styles);
  }

  elsif ( param('eurl') ) {
      my @urls = param('eurl');
      $self->add_track_to_state($_) foreach @urls;
  }
  
  # return 1 to exit
  return;
}

sub handle_edit {
    my $self             = shift;
    my $file             = shift;
    my $setting          = shift;
    my $data             = shift;

    my $uploaded_sources = $self->uploaded_sources();
    my @lines            = unexpand( split '\r?\n|\r\n?', $data );
    $data = join "\n", @lines;
    $data .= "\n";

    my $file_created = 0;
    if (not $uploaded_sources->url2path($file)){
        $file_created = 1;
    }

    $uploaded_sources->new_file($file);    # register it
    $self->add_track_to_state($file);
    my $fh = $uploaded_sources->open_file( $file, '>' ) or return;
    print $fh $data;
    close $fh;
    return $file_created;
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
    write_auto( \@features, $styles );
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

    $type = 'Your Features' unless defined $type;
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
  my $self = shift;
  $self->update_state_from_cgi;

  my $state         = $self->state;

  if ($self->segment) {

      # A reset won't have a segment, so we need to test for that before we use
      # one in whole_segment().
      my $whole_segment = $self->whole_segment;
      $state->{seg_min} = $whole_segment->start;
      $state->{seg_max} = $whole_segment->stop;

      # Open Automatically the tracks with features in them
      $self->auto_open();
  }

  $self->session->unlock;
}

sub default_state {
  my $self  = shift;
  my $state = $self->state;
  my $data_source = $self->data_source;
  %$state = ();
  @$state{'name','ref','start','stop','flip','version'} = ('','','','','',100);
  $state->{width}        = $self->setting('default width');
  $state->{source}       = $data_source->name;
  $state->{cache}        = defined $data_source->cache_time    ? $data_source->cache_time : 1;
  $state->{region_size}  = $self->setting('region segment');
  $state->{'max segment'}  = $self->setting('max segment');
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
  $self->session->unlock();
}

sub default_tracks {
  my $self  = shift;
  my $state  = $self->state;
  my @labels = $self->data_source->labels;

  $state->{tracks}   = \@labels;
  warn "order = @labels" if DEBUG;

  $state->{features}{$_} = {visible=>0,options=>0,limit=>0}
      foreach @labels;
  $state->{features}{$_}{visible} = 1
      foreach $self->data_source->default_labels;
}

# Open Automatically the tracks with features in them
sub auto_open {
    my $self     = shift;
    my $features = $self->region()->features() || return;
    my $state    = $self->state;

    for my $feature (@$features) {
        my @desired_labels = $self->data_source()->feature2label($feature)  or next;
	warn "desired labels = @desired_labels" if DEBUG;
	for my $desired_label (@desired_labels) {
	    warn "auto_open(): add_track_to_state($desired_label)" if DEBUG;
	    $self->add_track_to_state($desired_label);
	    $state->{h_feat} = {};
	    $state->{h_feat}{ $feature->display_name } = 'yellow'
		unless param('h_feat') && param('h_feat') eq '_clear_';
	}
    }
}


sub add_track_to_state {
  my $self  = shift;
  my $label = shift;

  return unless length $label; # refuse to add empty tracks!

  my $state  = $self->state;
  my %current = map {$_=> 1} @{$state->{tracks}};
  push @{$state->{tracks}},$label unless $current{$label};

  warn "ADD TRACK TO STATE WAS: ",
    join ' ',grep {$state->{features}{$_}{visible}} sort keys %{$state->{features}},"\n" if DEBUG;

  if($state->{features}{$label}){
    $state->{features}{$label}{visible}=1;
  }
  else{
    $state->{features}{$label} = {visible=>1,options=>0,limit=>0};
  }

  warn "ADD TRACK TO STATE NOW: ",
    join ' ',grep {$state->{features}{$_}{visible}} sort keys %{$state->{features}},"\n" if DEBUG;
}

sub remove_track_from_state {
  my $self  = shift;
  my $label = shift;
  my $state  = $self->state;

#  $state->{features}{$label} = {visible=>0,options=>0,limit=>0};
  delete $state->{features}{$label};
  $self->session->flush;
}

sub track_visible {
    my $self  = shift;
    my $label = shift;
    return $self->state->{features}{$label}{visible};
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
  $self->update_section_visibility($state);
  $self->update_external_sources();

#  $self->handle_remotes();
  $self->handle_external_data();

}

# Handle returns from the track configuration form
sub reconfigure_track {
    my $self  = shift;
    my $label = shift;
    my $state = $self->state();
    $state->{features}{$label}{visible} = param('show_track') ? 1 : 0;
    $state->{features}{$label}{options} = param('format_option');
    $state->{features}{$label}{limit}   = param('limit');
    my $dynamic = $self->tr('DYNAMIC_VALUE');
    for my $s ( 'bgcolor', 'fgcolor', 'height', 'glyph', 'linewidth' ) {
        my $value = param($s);
        delete $state->{features}{$label}{override_settings}{$s}, next
            if $value eq $dynamic;
        $state->{features}{$label}{override_settings}{$s} = $value;
    }
}

sub track_config {
  my $self     = shift;
  my $track_name    = shift;
  croak "track_config() should not be called in parent class";
}

sub share_track {
  my $self     = shift;
  my $track_name    = shift;
  croak "share_track() should not be called in parent class";
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

# this chunk of code is dead?
# just looking to see if the settings form was submitted
#   if (param('width')) { 
#     $state->{grid}  = param('grid');
#     $state->{show_tooltips} = param('show_tooltips');
#     unless (
# 	defined $data_source->cache_time()
#         && $data_source->cache_time() == 0 )
#     {
#         $state->{cache} = param('cache');
#         $state->{cache} = !param('nocache') if defined param('nocache');
#     }
#   }

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

  $self->set_tracks($self->split_labels(param('label'))) if param('label');
  $self->set_tracks($self->split_labels(param('t')))     if param('t');

  if (my @selected = split_labels(param('enable'))) {
    $state->{features}{$_}{visible} = 1 foreach @selected;
  }

  if (my @selected = split_labels(param('disable'))) {
    $state->{features}{$_}{visible} = 0 foreach @selected;
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
      warn "param(q) = ",param('q');
      @{$state}{'ref','start','stop'} 
          = Bio::Graphics::Browser::Region->parse_feature_name(param('q'));
      $position_updated++;
  }

  # quench uninit variable warning
  my $current_span = length($state->{stop}||'') ? ($state->{stop} - $state->{start} + 1) 
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
      undef $state->{ref};  # no longer valid
      $state->{name} = param('name');
      $state->{dbid} = param('dbid') if param('dbid'); # get rid of this
  }
}

sub asynchronous_update_overview_scale_bar {
    my $self    = shift;
    my $seg = $self->segment;

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

sub asynchronous_update_region_scale_bar {
    my $self    = shift;
    my $seg = $self->segment;

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

    return {
        url      => $url,
        height   => $height,
        width    => $width,
        image_id => $image_id,
    };
}

sub asynchronous_update_sections {
    my $self          = shift;
    my $section_names = shift;
    $self->init_database();

    my $source        = $self->data_source;
    my $return_object = {};

    my %handle_section_name = map { $_ => 1 } @{ $section_names || [] };

    # Init Plugins if need be
    if (   $handle_section_name{'plugin_configure_div'}
        || $handle_section_name{'tracks_panel'} )
    {
        $self->init_plugins();
    }

    # Init remote sources if need be
    if (   $handle_section_name{'external_utility_div'}
        || $handle_section_name{'tracks_panel'}
        || $handle_section_name{'upload_tracks_panel'} )
    {
        $self->init_remote_sources();
    }

    # Page Title
    if ( $handle_section_name{'page_title'} ) {
        my $segment     = $self->segment;
        my $dsn         = $self->data_source;
        my $description = $dsn->description;
        $return_object->{'page_title'} = $description . '<br>'
            . $self->tr(
            'SHOWING_FROM_TO',
            scalar $source->unit_label( $segment->length ),
            $segment->seq_id,
            $source->commas( $segment->start ),
            $source->commas( $segment->end )
            );
    }

    # Span that shows the range
    if ( $handle_section_name{'span'} ) {
        my $container
	    = $self->slidertable($self->segment);
        $return_object->{'span'} = $container;
    }

    # Unused Search Field
    if ( $handle_section_name{'search_form_objects'} ) {
        $return_object->{'search_form_objects'} = $self->render_search_form_objects();
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
                    = "$plugin_base is not a recognized plugin\n";
            }
        }
        else {
            $return_object->{'plugin_configure_div'}
                = "No plugin was specified.\n";
        }
    }

    # External File Stuff
    # Params are used to determine which type of activity the user wants
    if ( $handle_section_name{'external_utility_div'} ) {
        if ( my $file_name = param('edit_file') ) {
            $file_name = CGI::unescape($file_name);
            $return_object->{'external_utility_div'}
                = $self->edit_uploaded_file($file_name);
        }
        elsif ( param('new_edit_file') ) {
            my $file_name = $self->uploaded_sources->new_file_name();
            $return_object->{'external_utility_div'}
                = $self->edit_uploaded_file($file_name);
        }
        else {
            $return_object->{'external_utility_div'}
                = "No recognized action for external_utility_div.";
        }
    }

    # Track Checkboxes
    if ( $handle_section_name{'tracks_panel'} ) {
        $return_object->{'tracks_panel'} = $self->render_track_table();
    }

    # External Data Form
    if ( $handle_section_name{'upload_tracks_panel'} ) {
        $return_object->{'upload_tracks_panel'}
            = $self->render_external_table();
    }

    # Handle Remaining and Undefined Sections
    foreach my $section_name ( keys %handle_section_name ) {
        next if ( defined $return_object->{$section_name} );
        $return_object->{$section_name} = 'Unknown element: ' . $section_name;
    }
    return $return_object;
}

# asynchronous_update_element has been DEPRICATED
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
        return $description . '<br>'
            . $self->tr(
            'SHOWING_FROM_TO',
            scalar $source->unit_label( $segment->length ),
            $segment->seq_id,
            $source->commas( $segment->start ),
            $source->commas( $segment->end )
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
        $self->init_remote_sources();
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
        $self->init_remote_sources();
        return $self->render_track_table();
    }
    # External Data Form
    elsif ( $element eq 'upload_tracks_panel' ) {
        $self->init_remote_sources();
        return $self->render_external_table();
    }

    return 'Unknown element: ' . $element;
}

sub asynchronous_update_coordinates {
    my $self   = shift;
    my $action = shift;

    my $state  = $self->state;

    my $whole_segment_start = $state->{seg_min};
    my $whole_segment_stop = $state->{seg_max};

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
        if ( $1 eq 'true' ) {
            $state->{'flip'} = 1;
        }
        else {
            $state->{'flip'} = 0;
        }
    }

    if ($position_updated) { # clip and update param
	if (defined $whole_segment_start && $state->{start} < $whole_segment_start) {
	    my $delta = $whole_segment_start - $state->{start};
	    $state->{start} += $delta;
	    $state->{stop}  += $delta;
	}

	if (defined $whole_segment_stop && $state->{stop}  > $whole_segment_stop) {
	    my $delta = $state->{stop} - $whole_segment_stop;
	    $state->{start} -= $delta;
	    $state->{stop}  -= $delta;
	}

	# update our "name" state and the CGI parameter
	$state->{name} = "$state->{ref}:$state->{start}..$state->{stop}";
    }

    $self->session->unlock();

    $position_updated;
}

sub zoom_to_span {
  my $self = shift;
  my ($state,$new_span) = @_;

  my ($span) = $new_span =~ /([\d+.-]+)/;

  my $current_span = $state->{stop} - $state->{start} + 1;
  my $center	    = int(($current_span / 2)) + $state->{start};
  my $range	    = int(($span)/2);
  $state->{start}   = $center - $range;
  $state->{stop }   = $state->{start} + $span - 1;
}

sub move_segment {
  my $self = shift;
  my ( $state, $new_segment ) = @_;

  if ( $new_segment =~ /:([\d+.-]+)\.\.([\d+.-]+)/ ) {
    my $new_start = $1;
    my $new_stop  = $2;

    $state->{start} = $new_start;
    $state->{stop}  = $new_stop;
  }
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

# the following code is dead?
#   if (my @features = shellwords(param('h_feat'))) {
#     $state->{h_feat} = {};
#     for my $hilight (@features) {
#       last if $hilight eq '_clear_';
#       my ($featname,$color) = split '@',$hilight;
#       $state->{h_feat}{$featname} = $color || 'yellow';
#     }
#   }

#   if (my @regions = shellwords(param('h_region'))) {
#     $state->{h_region} = [];
#     foreach (@regions) {
#       last if $_ eq '_clear_';
#       $_ = "$state->{ref}:$_" unless /^[^:]+:-?\d/; # add reference if not there
#       push @{$state->{h_region}},$_;
#     }
#   }

  if ($self->setting('region segment')) {
    $state->{region_size} = param('region_size') if defined param('region_size');
    $state->{region_size} = $self->setting('region segment') unless defined $state->{region_size};
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

  # make URL labels a bit nicer
  if ($label =~ /^ftp|^http/) {
    $key = url_label($label);
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
  map {/^(http|ftp|das)/ ? $_ : split /[ +-]/} @_;
}

sub set_tracks {
    my $self   = shift;
    my @labels = @_;
    my $state  = $self->state;

    $state->{tracks} = \@labels;
    $self->load_plugin_annotators(\@labels);
    $state->{features}{$_}{visible} = 0 foreach $self->data_source->labels;
    $state->{features}{$_}{visible} = 1 foreach @labels;
}

sub load_plugin_annotators {
  my ($self,$visible_labels) = @_;

  my %label_visible = map { $_ => 1 } @{ $visible_labels || [] };
  my $state = $self->state;
  my $source = $self->data_source;
  my %default_plugin = map {$_=>1} map {s/^plugin:// && $_}
    grep {/^plugin:/} $source->default_labels;

  my %listed = map {$_=>1} @{$state->{tracks}}; # are we already on the list?
  my %listed_in_source = map {$_=>1} $source->configured_types; # are we already on the list?

  for my $plugin ($self->plugins->plugins) {
    next unless $plugin->type eq 'annotator';
    my $name = $plugin->name;
    $name = "plugin:$name";
    $source->add_type($name,{}) unless $listed_in_source{$name}++;
    $state->{features}{$name} ||= {visible=>$label_visible{$name}||0,options=>0,limit=>0};
    #push @{$state->{tracks}},$name unless $listed{$name}++;
  }

}

sub detail_tracks {
  my $self   = shift;
  my $state  = $self->state;
  my @tracks = grep {$state->{features}{$_}{visible} && !/:(overview|region)$/ && !/^_/}
               @{$state->{tracks}};
}
sub overview_tracks {
  my $self = shift;
  my $state = $self->state;
  return grep {$state->{features}{$_}{visible} && /:overview$/ && !/^_/ }
    @{$state->{tracks}};
}

sub regionview_tracks {
  my $self = shift;
  my $state = $self->state;
  return grep {$state->{features}{$_}{visible} && /:region$/ && !/^_/ }
    @{$state->{tracks}};
}

sub visible_tracks {
    my $self = shift;
    return ($self->detail_tracks,
	    $self->regionview_tracks,
	    $self->overview_tracks);
}

################## get renderer for this segment #########
sub get_panel_renderer {
  my $self = shift;
  my $seg  = shift || $self->segment;
  return Bio::Graphics::Browser::RenderPanels->new(-segment  => $seg,
						   -source   => $self->data_source,
						   -settings => $self->state,
						   -language => $self->language,
						  );}

################## image rendering code #############

# render_detailview is now obsolete
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
    my $self = shift;
    my $track_names = shift;

    my $html  = '';

    my $image_width = $self->get_image_width;
    foreach my $track_name ( @{ $track_names || [] } ) {

        my $track_html = $self->render_grey_track(
            track_name       => $track_name,
            image_width      => $image_width,
            image_height     => EMPTY_IMAGE_HEIGHT,
            image_element_id => $track_name . "_image",
        );
        $track_html = $self->wrap_track_in_track_div(
            track_name => $track_name,
            track_html => $track_html,
        );
        $html .= $track_html;
    }
    return $html;

}

sub get_image_width {
    my $self = shift;
    my $state = $self->state;
    my $source = $self->data_source;
    my $renderer  = $self->get_panel_renderer();
    my $padl      = $source->global_setting('pad_left');
    my $padr      = $source->global_setting('pad_right');
    my $image_pad = $renderer->image_padding;
    $padl = $image_pad unless defined $padl;
    $padr = $image_pad unless defined $padr;

    my $image_width = $state->{'width'} + $padl + $padr;
    return $image_width;
}

sub render_regionview {
  my $self = shift;
  my $seg = shift;
  return '';
}

sub render_deferred {
    my $self        = shift;

    my %args = @_;

    my $labels      = $args{labels}          || [ $self->detail_tracks ];
    my $seg         = $args{segment}         || $self->segment;
    my $section     = $args{section}         || 'detail';
    my $cache_extra = $args{cache_extra}     || $self->create_cache_extra();
    my $external    = $args{external_tracks} || $self->external_data;

    warn 'render_deferred(',join(',',@$labels),')' if DEBUG;

    my $renderer = $self->get_panel_renderer($seg);

    my $h_callback = $self->make_hilite_callback();

    my $requests = $renderer->request_panels(
        {   labels           => $labels,
            section          => $section,
            deferred         => 1,
            whole_segment    => $self->whole_segment(),
	    external_features=> $external,
            hilite_callback  => $h_callback || undef,
            cache_extra      => $cache_extra,
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
    my $track_name       = $args{'track_name'};

    my $renderer = $self->get_panel_renderer();
    my $url      = $renderer->source->globals->button_url() . "/grey.png";

    my $html = $renderer->wrap_rendered_track(
        label    => $track_name,
        area_map => [],
        width    => $image_width,
        height   => $image_height,
        url      => $url,
        status   => '',
    );

    return $html;
}

sub render_error_track {
    my $self = shift;
    my %args             = @_;
    my $image_width      = $args{'image_width'};
    my $image_height     = $args{'image_height'};
    my $image_element_id = $args{'image_element_id'};
    my $track_name       = $args{'track_name'};
    my $error_message    = $args{'error_message'};

    my $gd               = GD::Image->new($image_width,$image_height);
    my $black            = $gd->colorAllocate(0,0,0);
    my $white            = $gd->colorAllocate(255,255,255);
    my $pink             = $gd->colorAllocate(255,181,197);
    $gd->filledRectangle(0,0,$image_width,$image_height,$pink);
    my ($swidth,$sheight) = (GD->gdGiantFont->width * length($error_message),GD->gdGiantFont->height);
    my $xoff              = ($image_width - $swidth)/2;
    my $yoff              = ($image_height - $sheight)/2;
    $gd->string(GD->gdGiantFont,$xoff,$yoff,$error_message,$black);
    my ($url,$path) = $self->data_source->generate_image($gd);

    return $self->get_panel_renderer->wrap_rendered_track(
        label    => $track_name,
        area_map => [],
        width    => $image_width,
        height   => $image_height,
        url      => $url,
        status   => '',
    );
}

sub render_deferred_track {
    my $self             = shift;
    my %args             = @_;
    my $cache_key        = $args{'cache_key'};
    my $track_name       = $args{'track_name'};

    my $renderer = $self->get_panel_renderer;

    my $base  = $renderer->get_cache_base();
    my $cache = Bio::Graphics::Browser::CachedTrack->new(
        -cache_base => $base,
        -key        => $cache_key,
    );
    $cache->cache_time( $self->data_source->cache_time * 60 );
    my $status_html = "<!-- " . $cache->status . " -->";

    warn "render_deferred_track(): $track_name: status = $status_html" if DEBUG;

    my $result_html = '';
    if ( $cache->status eq 'AVAILABLE' ) {
        my $result = $renderer->render_tracks( { $track_name => $cache } );
        $result_html = $result->{$track_name};
    }
    elsif ($cache->status eq 'ERROR') {
        my $image_width = $self->get_image_width;
        $result_html .= $self->render_error_track(
						  track_name       => $track_name,
						  image_width      => $image_width,
						  image_height     => EMPTY_IMAGE_HEIGHT,
						  image_element_id => $track_name . "_image",
						  error_message    => 'An error occurred while processing this track')
    } else {
        my $image_width = $self->get_image_width;
        $result_html .= $self->render_grey_track(
						 track_name       => $track_name,
						 image_width      => $image_width,
						 image_height     => EMPTY_IMAGE_HEIGHT,
						 image_element_id => $track_name . "_image",
						 );
    }
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

=head2 get_regionview_start_stop

 usage

Description

=cut

sub get_regionview_start_stop {
  my $self = shift;
  my ($settings,$detail_start, $detail_end, $whole_start, $whole_end) = @_;
  my $regionview_length = $settings->{region_size};
  if ($detail_end - $detail_start + 1 > $regionview_length) { # region can't be smaller than detail
    $regionview_length = $detail_end - $detail_start + 1;
  }
  my $midpoint = ($detail_end + $detail_start) / 2;
  my $regionview_start = int($midpoint - $regionview_length/2 + 1);
  my $regionview_end = int($midpoint + $regionview_length/2);
  if ($regionview_start < $whole_start) {
    $regionview_start = 1;
    $regionview_end   = $regionview_length;
  }
  if ($regionview_end > $whole_end) {
    $regionview_start = $whole_end - $regionview_length + 1;
    $regionview_end   = $whole_end;
  }
  return ($regionview_start, $regionview_end);
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
    return unless $feature->display_name;
    return $state->{h_feat}{$feature->display_name};
  }
}

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

sub external_data {
    my $self    = shift;
    my $segment = $self->segment or return { };
    my $state   = $self->state;

    return $self->{feature_files} if exists $self->{feature_files};

    # $f will hold a feature file hash in which keys are human-readable names of
    # feature files and values are FeatureFile objects.
    my $f           = {};
    my $max_segment = $self->get_max_segment;
    if ($segment) {
	my $rel2abs      = $self->coordinate_mapper($segment,1);
	my $rel2abs_slow = $self->coordinate_mapper($segment,0);
	for my $featureset ($self->plugins,$self->uploaded_sources,$self->remote_sources) {
	    next unless $featureset;
	    $featureset->annotate($segment,$f,$rel2abs,$rel2abs_slow,$max_segment);
	}
    }
    
    return $self->{feature_files} = $f;
}

sub coordinate_mapper {
    my $self            = shift;
    my $current_segment = shift;
    my $optimize        = shift;

    my $db = $current_segment->factory;

    my ( $ref, $start, $stop ) = (
        $current_segment->seq_id, $current_segment->start,
        $current_segment->end
    );
    my %segments;

    my $closure = sub {
        my ( $refname, @ranges ) = @_;

        unless ( exists $segments{$refname} ) {
            $segments{$refname} = $self->whole_segment();
        }

        my $mapper  = $segments{$refname} || return;
        my $absref  = $mapper->abs_ref;
        my $cur_ref = eval { $current_segment->abs_ref }
            || eval { $current_segment->ref }; # account for api changes in Bio::SeqI
        return unless $absref eq $cur_ref;

        my @abs_segs;
        if ( $absref eq $refname ) {           # doesn't need remapping
            @abs_segs = @ranges;
        }
        else {
            @abs_segs
                = map { [ $mapper->rel2abs( $_->[0], $_->[1] ) ] } @ranges;
        }

        # this inhibits mapping outside the displayed region
        if ($optimize) {
            my $in_window;
            foreach (@abs_segs) {
                next unless defined $_->[0] && defined $_->[1];
                $in_window ||= $_->[0] <= $stop && $_->[1] >= $start;
            }
            return $in_window ? ( $absref, @abs_segs ) : ();
        }
        else {
            return ( $absref, @abs_segs );
        }
    };
    return $closure;
}


# Delete the segments so that they can be recreated with new parameters
sub delete_stored_segments {
    my $self = shift;

    delete $self->{region};
    delete $self->{region_segment};
    delete $self->{whole_segment};
}

# I know there must be a more elegant way to insert commas into a long number...
sub commas {
    my $self = shift;
    my $i    = shift;
    return $i if $i=~ /\D/;

    $i = reverse $i;
    $i =~ s/(\d{3})/$1,/g;
    chop $i if $i=~/,$/;

    $i = reverse $i;
    return $i;
}

###################### link generation ##############
sub annotation_help {
  return shift->globals->url_base."/annotation_help.html";
}

sub general_help {
  return shift->globals->url_base."/general_help.html";
}

sub bookmark_link {
  my $self     = shift;
  my $settings = shift;

  my $q = new CGI('');
  my @keys = qw(start stop ref width version flip);
  foreach (@keys) {
    $q->param(-name=>$_,-value=>$settings->{$_});
  }

  # handle selected features slightly differently
  my @selected = grep {$settings->{features}{$_}{visible} && !/^(file|ftp|http):/} @{$settings->{tracks}};
  $q->param(-name=>'label',-value=>join('-',@selected));

  # handle external urls
  my @url = grep {/^(ftp|http):/} @{$settings->{tracks}};
  $q->param(-name=>'eurl',-value=>\@url);
  $q->param(-name=>'h_region',-value=>$settings->{h_region}) if $settings->{h_region};
  my @h_feat= map {"$_\@$settings->{h_feat}{$_}"} keys %{$settings->{h_feat}};
  $q->param(-name=>'h_feat',-value=>\@h_feat) if @h_feat;
  $q->param(-name=>'id',-value=>$settings->{id});
  $q->param(-name=>'grid',-value=>$settings->{grid});

  return "?".$q->query_string();
}

# for the subset of plugins that are named in the 'quicklink plugins' option, create
# quick links for them.
sub plugin_links {
  my $self    = shift;
  my $plugins = shift;

  my $quicklink_setting = $self->setting('quicklink plugins') or return '';
  my @plugins           = shellwords($quicklink_setting)      or return '';
  my @result;
  for my $p (@plugins) {
    my $plugin = $plugins->plugin($p) or next;
    my $name   = $plugin->name;
    my $action = "?plugin=$p;plugin_do=".$self->tr('Go');
    push @result,a({-href=>$action},"[$name]");
  }
  return join ' ',@result;
}

sub image_link {
    my $self = shift;
    my $settings = shift;
    my $format   = shift;

    $format      = 'GD' unless $format eq 'GD' || $format eq 'GD::SVG';

    my $source   = $self->data_source->name;
    my $id       = $settings->{id};
    my $flip     = $settings->{flip} || param('flip') || 0;
    my $keystyle = $settings->{ks};
    my $grid     = $settings->{grid} || 0;
    my $url      = url();
    $url         = dirname($url) . "/gbrowse_img/".CGI::escape($source);
    my $tracks   = $settings->{tracks};
    my $width    = $settings->{width};
    my $name     = "$settings->{ref}:$settings->{start}..$settings->{stop}";
    my $type     = join '+',map{CGI::escape($_)} map {/\s/?qq("$_"):$_} $self->visible_tracks;
    my $options  = join '+',map { join '+', CGI::escape($_),$settings->{features}{$_}{options}
                             } map {/\s/?"$_":$_}
    grep {
	$settings->{features}{$_}{options}
    } @$tracks;
    my $img_url  = "$url/?name=$name;label=$type;width=$width;id=$id";
    $img_url    .= ";flip=$flip"         if $flip;
    $img_url    .= ";options=$options"   if $options;
    $img_url    .= ";format=$format"     if $format;
    $img_url    .= ";keystyle=$keystyle" if $keystyle;
    $img_url    .= ";grid=$grid";
    $self->add_hilites($settings,\$img_url);
    warn "img url = $img_url";
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

########## note: "sub tr()" makes emacs' syntax coloring croak, so place this function at end
sub tr {
  my $self = shift;
  my $lang = $self->language or return @_;
  $lang->tr(@_);
}

sub DESTROY {
   my $self = shift;
   if ($self->session) { $self->session->flush; }
}
1;

