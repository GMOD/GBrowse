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

sub handle_legacy_calls {
    my $class  = shift;
    my ($q,$render) = @_;

    # redirect to galaxy form submission
    if ($q->param('galaxy')) {
	return (302,undef,$render->galaxy_link($render->state));
    }

    # redirect to the imagelink
    if (my $format = $q->param('make_image')) {
	return (302,undef,$render->image_link($render->state,$format));
    }

    if ($q->param('clear_dsn') || $q->param('reset_dsn')) {
	return (302,undef,"?action=reset_dsn");
    }

    return;
}

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

sub ACTION_share_track {
    my $self = shift;
    my $q    = shift;

    my $track_name = $q->param('track') or croak;
    my $html = $self->render->share_track($track_name);
    return ( 200, 'text/html', $html );
}

sub ACTION_retrieve_multiple {
    my $self = shift;
    my $q    = shift;

    my $render = $self->render;

    $render->init_plugins();
    $render->init_remote_sources();

    my %track_html;
    my @track_ids = $q->param('track_ids');

    foreach my $track_id (@track_ids) {
	my $track_key = $q->param( 'tk_' . $track_id ) or next;
	warn "retrieving $track_id=>$track_key" if DEBUG;
	
	$track_html{$track_id} = $render->render_deferred_track(
	    cache_key  => $track_key,
	    track_id   => $track_id,
            ) || '';
    }

    my $return_object = { track_html => \%track_html, };
    return ( 200, 'application/json', $return_object );
}

sub ACTION_add_tracks {
    my $self = shift;
    my $q    = shift;

    my $render = $self->render;
    

    my @track_names = $q->param('track_names');

    $render->init_database();
    $render->init_plugins();
    $render->init_remote_sources();

    my $track_data = $render->add_tracks(\@track_names);
    my $return_object = { track_data => $track_data, };

    return ( 200, 'application/json', $return_object );
}

sub ACTION_reconfigure_plugin {
    my $self   = shift;
    my $q      = shift;
    $self->render->init_plugins();
    return (204,'text/plain',undef);
}

sub ACTION_rerender_track {
    my $self  = shift;
    my $q     = shift;

    my $render   = $self->render;
    my $track_id = $q->param('track_id');

    $render->init_database();
    $render->init_plugins();
    $render->init_remote_sources();

    my ( $track_keys, $display_details, $details_msg )
	= $render->background_individual_track_render($track_id);

    my $return_object = {
	track_keys      => $track_keys,
	display_details => $display_details,
	details_msg     => $details_msg,
    };
    return (200,'application/json',$return_object);
}

sub ACTION_commit_file_edit {
    my $self = shift;
    my $q    = shift;

    my $data        = $q->param('a_data');
    my $edited_file = $q->param('edited_file');

    return ( 204, 'text/plain', undef ) unless ( $edited_file and $data );

    $self->render->init_remote_sources();
    my ($file_created,$tracks,$error) = $self->render->handle_edit( $edited_file, $self->state, $data );

    my $return_object = {
	file_created   => $file_created,
	tracks         => $tracks,
	error          => "$error"
    };

    return (200,'application/json',$return_object);
}

sub ACTION_add_url {
    my $self = shift;
    my $q    = shift;

    my $data   = $q->param('eurl');
    my $render = $self->render;

    $render->init_remote_sources;
    $render->remote_sources->add_source($data);
    $render->add_track_to_state($data);
    warn "adding $data to remote sources" if DEBUG;
    return (200,'application/json',{url_created=>1});
}

sub ACTION_delete_upload_file {
    my $self = shift;
    my $q    = shift;

    my $render = $self->render;
    my $file   = $q->param('file');
    warn "deleting file $file " if DEBUG;

    $render->init_remote_sources();
    $render->uploaded_sources->clear_file($file);
    $render->remote_sources->delete_source($file);
    $render->remove_track_from_state($file);

    return (204,'text/plain',undef);
}

sub ACTION_show_hide_section {
    my $self = shift;
    my $q    = shift;

    my @show = $q->param('show');
    my @hide = $q->param('hide');

    my $settings = $self->state;
    $settings->{section_visible}{$_} = 0 foreach @hide;
    $settings->{section_visible}{$_} = 1 foreach @show;

    return (204,'text/plain',undef);
}

sub ACTION_open_collapse_track {
    my $self = shift;
    my $q    = shift;

    my @open     = $q->param('open');
    my @collapse = $q->param('collapse');

    my $settings = $self->state;
    $settings->{track_collapsed}{$_} = 1 foreach @collapse;
    $settings->{track_collapsed}{$_} = 0 foreach @open;

    return (204,'text/plain',undef);
}

sub ACTION_change_track_order {
    my $self = shift;
    my $q    = shift;

    warn "change_track_order()";

    my $settings = $self->state;
    my @labels   = $q->param('label[]') or return;
    foreach (@labels) {
	s/%5F/_/g;
	s/:(overview|region|detail)$// if m/^(plugin|file|http|ftp):/;
    }
    my %seen;
    @{ $settings->{tracks} } = grep { length() > 0 && !$seen{$_}++ }
    ( @labels, @{ $settings->{tracks} } );

    return (204,'text/plain',undef);    
}

sub ACTION_set_display_option {
    my $self = shift;

    # this is a little bogus because update_options() is going to
    # read from the CGI parameter list directly.
    $self->render->update_options;  
    return (204,'text/plain',undef);        
}

sub ACTION_bookmark {
    my $self = shift;
    return (302,undef,$self->render->bookmark_link($self->state));
}

sub ACTION_autocomplete {
    my $self   = shift;
    my $q      = shift;
    my $render = $self->render;

    my $match  = $q->param('prefix') or croak;

    my $search = $render->get_search_object;
    my $matches= $search->features_by_prefix($match,100);
    my $autocomplete = $render->format_autocomplete($matches,$match);
    return (200,'text/html',$autocomplete);
}

sub ACTION_reset_dsn {
    my $self = shift;
    warn "here I am";
    $self->data_source->clear_cached_config();
    return (204,'text/plain',undef);
}

sub ACTION_authorize_login {
    my $self = shift;
    my $q    = shift;
    my $username = $q->param('username') or croak;
    my $session  = $q->param('session')  or croak;
    my $openid   = $q->param('openid')   or croak;

    my ($id,$nonce) = $self->render->authorize_user($username,$session,$openid);
    return (200,'application/json',{id=>$id,authority=>$nonce});
}

# DEBUGGING METHOD
sub ACTION_new_test_track {
    my $self = shift;
    my $q    = shift;

    my $render   = $self->render;
    my $userdata = Bio::Graphics::Browser2::UploadSet->new($render->data_source,
							   $render->state,
							   $render->language);
    warn "Adding test track for ",$render->state->{uploadid}," path = ",($userdata->name_file('test'))[1];
    return (204,'text/plain',undef);
}

sub ACTION_upload_file {
    my $self = shift;
    my $q    = shift;

    my $fh = $q->param('file') or return(204,'text/plain',undef);

    my $render   = $self->render;
    my $state    = $self->state;
    my $session  = $render->session;

    my $userdata = Bio::Graphics::Browser2::UserTracks->new($render->data_source,
							    $render->state,
							    $render->language);
    warn "created userdata $userdata";

    my $name = File::Basename::basename($fh );
    $state->{current_upload} = $name;
    $session->flush();
    $session->unlock();

    my ($result,$msg) = $userdata->upload_track($name,$fh);

    return $msg ? (200,
		   'text/html',
		   "<pre style='background-color:pink'>$msg</pre>".
		   a({
		       -href    =>'javascript:void(0)',
		       -onClick =>"\$('upload_status').innerHTML=''"
		     },
		     '[Remove]'
		   )
	)
	: (200,'text/plain','');
}

sub ACTION_delete_upload {
    my $self  = shift;
    my $q     = shift;

    my $track  = $q->param('track') or croak;
    my $render = $self->render;

    my $userdata = Bio::Graphics::Browser2::UserTracks->new($render->data_source,
							    $render->state,
							    $render->language);
    $userdata->delete_track($track);
    return (204,'text/plain',undef);
}

sub ACTION_upload_status {
    my $self = shift;
    my $q    = shift;

    my $status    = 'status unknown';
    my $file_name = 'Unknown';

    my $state      = $self->state;
    my $render     = $self->render;

    if ($file_name = $state->{current_upload}) {
	my $userdata = Bio::Graphics::Browser2::UserTracks->new($render->data_source,
								$render->state,
								$render->language);
	$status      = $userdata->status($file_name);
	return (200,'text/html',"<b>$file_name:</b> <i>$status</i>");
    } else {
	return (204,'text/plain',undef);
    }
}


1;

__END__

# some dead code follows here

# This looks like an older version of the retrieve_multiple request

# Slightly different -- process a tracks request in the background.
#     if ( my @labels = param('render') ) {    # deferred rendering requested
#         $self->init_database();
#         $self->init_plugins();
#         $self->init_remote_sources();
#         my $features = $self->region->features;
#         my $seg      = $self->features2segments($features)->[0];    # likely wrong

#         $self->set_segment($seg);

#         my $deferred_data = $self->render_deferred( labels => \@labels );
# 	return (200,'application/json',$deferred_data);
#     }

