package Bio::Graphics::Browser2::Action;

#$Id$
# dispatch

use strict;
use Carp 'croak';
use CGI();
use constant DEBUG => 0;

sub new {
    my $class  = shift;
    my $render = shift;
    return bless \$render,ref $class || $class;
}

sub render {
    my $self = shift;
    return $$self;
}

# convenience functions
sub settings    {shift->render->state}
sub state       {shift->render->state}
sub data_source {shift->render->data_source}
sub session     {shift->render->session}
sub segment     {shift->render->segment}

# each ACTION_* method corresponds to a "action=*" parameter on the CGI stack
sub ACTION_navigate {
    my $self   = shift;
    my $q      = shift;

    my $render   = $self->render;
    my $settings = $self->settings;

    my $action = $q->param('navigate') 
	or croak "for the navigate action, a CGI argument named \"navigate\" must be present";

    my $updated = $render->asynchronous_update_coordinates($action);
    $render->init_database() if $updated;

    my ( $track_keys, $display_details, $details_msg )
	= $render->background_track_render();

    my $overview_scale_return_object
	= $render->asynchronous_update_overview_scale_bar();

    my $region_scale_return_object
	= $render->asynchronous_update_region_scale_bar()
            if ( $settings->{region_size} );

    my $detail_scale_return_object
	= $render->asynchronous_update_detail_scale_bar();

    my $segment_info_object = $render->segment_info_object();

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

sub ACTION_update_sections {
    my $self    = shift;
    my $q       = shift;

    my $render  = $self->render;
    my @section_names = $q->param('section_names');

    my $section_html
	= $render->asynchronous_update_sections( \@section_names );

    my $return_object = { section_html => $section_html, };
    return ( 200, 'application/json', $return_object );
}

sub ACTION_upload_table {
    my $self   = shift;
    my $render = $self->render_table;
    $render->init_remote_sources();
    my $html   = $render->render_external_table();
    return ( 200, 'text/html', $html );
}


sub ACTION_configure_track {
    my $self = shift;
    my $q    = shift;

    my $track_name = $q->param('track') or croak;
    my $html = $self->render->track_config($track_name);
    return ( 200, 'text/html', $html );
}


sub ACTION_select_subtracks {
    my $self = shift;
    my $q    = shift;

    my $track_name = $q->param('track') or croak;
    my $html = $self->render->select_subtracks($track_name);
    return ( 200, 'text/html', $html );
}


sub ACTION_filter_subtrack {
    my $self = shift;
    my $q    = shift;

    my $track_name = $q->param('track') or croak;
    my $html = $self->render->filter_subtrack($track_name);
    return ( 200, 'application/json', {} );
}


sub ACTION_reconfigure_track {
    my $self = shift;
    my $q    = shift;

    my $track_name     = $q->param('track') or croak;
    my $semantic_label = $q->param('semantic_label');
    $self->render->reconfigure_track($track_name,$semantic_label);
    return ( 200, 'application/json', {} );
}

1;
