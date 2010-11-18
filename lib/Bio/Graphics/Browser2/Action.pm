package Bio::Graphics::Browser2::Action;

#$Id$
# dispatch

use strict;
use Carp 'croak';
use CGI();
use Bio::Graphics::Browser2::TrackDumper;
use File::Basename 'basename';
use JSON;
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
    my $self  = shift;
    my $q     = shift;
    my $render = $self->render;

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
    my $source   = $self->data_source;
    my $settings = $self->settings;

    my $action = $q->param('navigate') 
	or croak "for the navigate action, a CGI argument named \"navigate\" must be present";

    my $updated = $render->asynchronous_update_coordinates($action);
    $render->init_database() if $updated;

    my ( $track_keys, $display_details, $details_msg )
	= $render->background_track_render();

    my $overview_scale_return_object
	= $render->asynchronous_update_overview_scale_bar() if $source->show_section('overview');

    my $region_scale_return_object
	= $render->asynchronous_update_region_scale_bar()
            if ( $settings->{region_size} && $source->show_section('region'));

    my $detail_scale_return_object
	= $render->asynchronous_update_detail_scale_bar() if $source->show_section('detail');

    my $segment_info_object = $render->segment_info_object();
#    warn Data::Dumper::Dumper($segment_info_object);

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

sub ACTION_configure_track {
    my $self = shift;
    my $q    = shift;

    my $track_name = $q->param('track') or croak;
    my $revert     = $q->param('track_defaults');

    # this is fixing an upstream bug of some sort
    $track_name =~ s/:(overview|region|detail)$//
	if $track_name =~/^(plugin|file|http|ftp)/; 

    my $html = $self->render->track_config($track_name,$revert);
    return ( 200, 'text/html', $html );
}

sub ACTION_cite_track {
    my $self = shift;
    my $q    = shift;

    my $track_name = $q->param('track') or croak;

    my $html = $self->render->track_citation($track_name);
    return ( 200, 'text/html', $html );
}

sub ACTION_download_track_menu {
    my $self = shift;
    my $q    = shift;
    my $track_name = $q->param('track') or croak;
    my $html       = $self->render->download_track_menu($track_name);
    return ( 200, 'text/html', $html );
}

# return a listing of all discoverable tracks
sub ACTION_scan {
    my $self = shift;
    my $q    = shift;
    my $dumper = Bio::Graphics::Browser2::TrackDumper->new(
        -data_source => $self->data_source(),
    );
    return (200, 'text/plain', $dumper->get_scan);
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
    my $track_data = $render->add_tracks(\@track_names);
    my $return_object = { track_data => $track_data, };

    return ( 200, 'application/json', $return_object );
}

sub ACTION_set_track_visibility {
    my $self = shift;
    my $q    = shift;

    my $render     = $self->render;
    my $track_name = $q->param('track_name') or croak;
    my $visible    = $q->param('visible');
    
    warn "$track_name=>$visible" if DEBUG;

    if ($visible) {
	$render->init_plugins();
	$render->add_track_to_state($track_name);
    }
    else {
	$render->remove_track_from_state($track_name);
    }

    return (204,'text/plain',undef);
}

sub ACTION_reconfigure_plugin {
    my $self   = shift;
    my $q      = shift;
    my $plugin = $q->param('plugin');
    # currently we reinit all plugins, not just the one involved
    $self->render->init_plugins();
    return (204,'text/plain',undef);
}

sub ACTION_rerender_track {
    my $self  = shift;
    my $q     = shift;

    my $render   = $self->render;
    my $track_id = $q->param('track_id');
    my $nocache  = $q->param('nocache');

    $render->init_database();
    $render->init_plugins();
    $render->init_remote_sources if $track_id =~ /http|ftp|das/;

    my ( $track_keys, $display_details, $details_msg )
	= $render->background_individual_track_render($track_id,$nocache);

    my $return_object = {
	track_keys      => $track_keys,
	display_details => $display_details,
	details_msg     => $details_msg,
    };
    return (200,'application/json',$return_object);
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

    warn "change_track_order()" if DEBUG;

    my $settings = $self->state;
    my @labels   = $q->param('label[]') or return;
    foreach (@labels) {
	s/%5F/_/g;
	s/:(overview|region|detail)$// if m/^(plugin|file|http|ftp)/;
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

    if ($match =~ /^\w+:\d+/) { # region search, give up
	return(200,'text/html',$render->format_autocomplete([],''));
    }

    my $search = $render->get_search_object;
    my $matches= $search->features_by_prefix($match,100);
    my $autocomplete = $render->format_autocomplete($matches,$match);
    return (200,'text/html',$autocomplete);
}

sub ACTION_reset_dsn {
    my $self = shift;
    $self->data_source->clear_cached_config();
    return (204,'text/plain',undef);
}

sub ACTION_authorize_login {
    my $self = shift;
    my $q    = shift;
    my $username = $q->param('username') or croak "no username provided";
    my $session  = $q->param('session')  or croak "no session ID provided";
    my $openid   = $q->param('openid');   # or croak;
    my $remember = $q->param('remember'); # or croak;

    my ($id,$nonce) = $self->render->authorize_user($username,$session,$remember,$openid);
    return (200,'application/json',{id=>$id,authority=>$nonce});
}

sub ACTION_register_upload {
    my $self = shift;
    my $q    = shift;
    my $id   = $q->param('upload_id');
    my $name = $q->param('upload_name');

    if ($id && $name) {
	$self->state->{uploads}{$id} = [$name,0];
    }

    return (204,'text/plain',undef);
}

sub ACTION_upload_file {
    my $self = shift;
    my $q    = shift;

    my $fh   = $q->param('file');
    my $data = $q->param('data');
    my $url  = $q->param('mirror_url');
    my $workaround = $q->param('workaround');

    ($fh || $data || $url) or 
	return(200,'text/html',JSON::to_json({success=>0,
					      error_msg=>'empty file'}
	       ));

    my $upload_id = $q->param('upload_id');

    my $render   = $self->render;
    my $state    = $self->state;
    my $session  = $render->session;

    my $usertracks = $render->user_tracks;
    my $name       = $fh  ? basename($fh) 
	            :$url ? $url
                          : $q->param('name');
    $name  ||= 'Uploaded file';

    my $content_type = $fh ? $q->uploadInfo($fh)->{'Content-Type'} : 'text/plain';

    my $track_name = $usertracks->trackname_from_url($name);

    $state->{uploads}{$upload_id} = [$track_name,$$];
    $session->flush();
    $session->unlock();
    
    my ($result,$msg,$tracks,$pid) = $url  ? $usertracks->mirror_url($track_name,  $url, 1)
                                    :$data ? $usertracks->upload_data($track_name, $data,$content_type, 1)
                                           : $usertracks->upload_file($track_name, $fh,  $content_type, 1);

    $session->lock('exclusive');
    delete $state->{uploads}{$upload_id};
    $session->flush();
    $session->unlock();

    # simplify the message if it is coming from BioPerl
    $msg = $1 if $msg =~ /MSG:\s+(.+?)\nSTACK/s;
    $msg =~ s/\n.+\Z//s;
    $msg =~ s/[\n"]/ /g;

    my $return_object        = { success   => $result||0,
				 error_msg => CGI::escapeHTML($msg),
				 tracks    => $tracks,
				 uploadName=> $name,
                               };
    return (200,'text/html',JSON::to_json($return_object)) if $workaround;
    return (200,'application/json',$return_object);
}

sub ACTION_import_track {
    my $self = shift;
    my $q    = shift;

    my $url = $q->param('url') or 
	return(200,'text/html',JSON::to_json({success=>0,
					      error_msg=>'no URL provided'}
	       ));

    my $upload_id  = $q->param('upload_id');
    my $workaround = $q->param('workaround');

    my $render   = $self->render;
    my $state    = $self->state;
    my $session  = $render->session;

    my $usertracks = $render->user_tracks;
    (my $track_name = $url) =~ tr!a-zA-Z0-9_%^@.!_!cs;
    $state->{uploads}{$upload_id} = [$track_name,$$];
    $session->flush();
    $session->unlock();
    
    my ($result,$msg,$tracks) = $usertracks->import_url($url);
    $session->lock('exclusive');
    delete $state->{uploads}{$upload_id};
    $session->flush();
    $session->unlock();

    my $return_object        = { success   => $result||0,
				 error_msg => CGI::escapeHTML($msg),
				 tracks    => $tracks ,
				 uploadName=> $url,
                               };
    return (200,'text/html',JSON::to_json($return_object)) if $workaround;
    return (200,'application/json',$return_object);
}

sub ACTION_delete_upload {
    my $self  = shift;
    my $q     = shift;

    my $file   = $q->param('file') or croak;
    my $render = $self->render;

    my $usertracks = $render->user_tracks;
    my @tracks     = $usertracks->labels($file);
    
    foreach (@tracks) {
	my (undef,@db_args) = $self->data_source->db_settings($_);
	Bio::Graphics::Browser2::DataBase->delete_database(@db_args);
	$render->remove_track_from_state($_);
    }
    $usertracks->delete_file($file);

    return (200,'application/json',{tracks=>\@tracks});
}

sub ACTION_upload_status {
    my $self = shift;
    my $q    = shift;

    my $upload_id = $q->param('upload_id');

    my $status    = 'status unknown';
    my $file_name = 'Unknown';

    my $state      = $self->state;
    my $render     = $self->render;

    if ($file_name = $state->{uploads}{$upload_id}[0]) {
	my $usertracks = $render->user_tracks;
	$status      = $usertracks->status($file_name);
	return (200,'text/html',"<b>$file_name:</b> <i>$status</i>");
    } else {
	return (500,'text/html',"not found");
    }
}

sub ACTION_cancel_upload {
    my $self = shift;
    my $q    = shift;
    my $upload_id = $q->param('upload_id');

    my $state      = $self->state;
    my $render     = $self->render;

    if ($state->{uploads}{$upload_id} && (my ($file_name,$pid) = @{$state->{uploads}{$upload_id}})) {
	my $usertracks = $render->user_tracks;
	kill TERM=>$pid;
	$usertracks->delete_file($file_name);
	delete $state->{uploads}{$upload_id};
	return (200,'text/html',"<div class='error'><b>$file_name:</b> <i>Cancelling</i></div>");
    } else {
	return (200,'text/html','<div class="error"><i>Not found</i></div>');
    }
    
}

sub ACTION_set_upload_description {
    my $self = shift;
    my $q    = shift;

    my $state       = $self->state;
    my $render      = $self->render;
    my $upload_name = $q->param('upload_name') or croak;
    my $upload_desc = $q->param('description') or croak;

    my $usertracks = $render->user_tracks;
    $usertracks->description($upload_name,$upload_desc);
    return (204,'text/plain',undef);
}

sub ACTION_modifyUserData {
    my $self = shift;
    my $q    = shift;
    my $ftype     = $q->param('sourceFile');
    my $track     = $q->param('track');
    my $text      = $q->param('data');
    my $upload_id = $q->param('upload_id');

    my $userdata = $self->render->user_tracks;
    my $state    = $self->state;

    $state->{uploads}{$upload_id} = [$ftype,$$];

    if ($ftype eq 'conf') {
	$userdata->merge_conf($track,$text);
    } else {
	$userdata->upload_data($track,$text,'text/plain',1); # overwrite
    }
    delete $state->{uploads}{$upload_id};
    my @tracks     = $userdata->labels($track);
    $self->render->track_config($_,'revert') foreach @tracks;
    return (200,'application/json',{tracks=>\@tracks});
}

sub ACTION_show_subtracks {
    my $self = shift;
    my $q    = shift;
    my $track_name = $q->param('track') or croak 'provide "track" argument';
    my $stt = $self->render->create_subtrack_manager($track_name)
	or return (204,'text/plain','');
    return ( 200, 'text/html', $stt->preview_table($self->render) );
}

sub ACTION_select_subtracks {
    my $self = shift;
    my $q    = shift;
    my $label= $q->param('track') or return (200,'text/plain','Programming error');
    my $html = $self->render->subtrack_table($label);
    return (200,'text/html',$html);
}

sub ACTION_set_subtracks {
    my $self = shift;
    my $q    = shift;
    my $label= $q->param('label');
    my $subtracks = JSON::from_json($q->param('subtracks'));
    my $settings  = $self->state;
    $self->state->{subtracks}{$label} = $subtracks;
    return (204,'text/plain',undef);
}

sub ACTION_chrom_sizes {
    my $self = shift;
    my $q    = shift;
    my $loader = Bio::Graphics::Browser2::DataLoader->new(undef,undef,undef,
							  $self->data_source,
							  undef);
    my $sizes  = $loader->chrom_sizes;
    unless ($sizes) {
	return (200,
		'text/plain',
		"The chromosome sizes cannot be determined from this data source. Please contact the site administrator for help");
    }
    my $data;
    open my $f,'<',$sizes or return (200,
				     'text/plain',
				     "An error occurred when opening chromosome sizes file: $!");
    $data.= $_ while <$f>;
    close $f;
    my $build = $self->data_source->build_id || 'build_unknown';
    my $name  = $self->data_source->species  || $self->data_source->name;
    $name     =~ s/\s/_/g;
    return (200,'text/plain',$data,
	    -content_disposition => "attachment; filename=${name}_${build}_chrom.sizes",
	);
}

sub ACTION_about_gbrowse {
    my $self = shift;
    my $q    = shift;

    my $html = $q->div(
	$q->img({-src=>'http://phenomics.cs.ucla.edu/GObase/images/gmod.gif',
		 -align=>'right',
		 -width=>'100',
		}),
	$q->p(
	    $q->b(
		"This is the Generic Genome Browser version $Bio::Graphics::Browser2::VERSION"
	    )
	    ),
	$q->p(
	    'It is part of the',$q->a({-href=>'http://www.gmod.org'},'Generic Model Organism (GMOD)'),
	    'suite of genome analysis software tools.'),
	$q->p(
	    'The software is copyright 2002-2010 Cold Spring Harbor Laboratory,',
	    'Ontario Institute for Cancer Research,',
	    'and the University of California, Berkeley.')
	);
    return (200,'text/html',$html)
}

sub ACTION_about_dsn {
    my $self = shift;
    my $q    = shift;

    my $source = $self->data_source;
    my $html;

    if (my $metadata = $source->metadata) {
	my $taxid    = $metadata->{taxid} || $metadata->{species};
	$taxid    =~ tr/ /+/;

	my $coordinates = $metadata->{coordinates};
	my $build       = $metadata->{authority} . '_' . $metadata->{coordinates_version};
	my $build_link  = $coordinates  ? $q->a({-href=>$coordinates},$build)
	                 :$build ne '_' ? $q->b($build)
			 :'';

	$html     = $q->h1($self->render->tr('ABOUT_NAME',$source->description));
	$html    .= $q->p({-style=>'margin-left:1em'},$metadata->{description});
	my @lines;
	push @lines,(
	    $q->dt($q->b('Species:')),
	    $q->dd($q->a({-href=>"http://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?name=$taxid"},
			 $q->i($metadata->{species})))
	) if $metadata->{species};

	push @lines,(
	    $q->dt($q->b('Build:')),
	    $q->dd($build_link)
	) if $build_link;

	$html    .= $q->h1('Species and Build Information').
	    $q->div({-style=>'margin-left:1em'},$q->dl(@lines)) if @lines;

	my $attribution = '';

	if (my $maintainer = $metadata->{maintainer}) {
            $maintainer    =~ s!<(.+)>!&lt;<a href="mailto:$1">$1</a>&gt;!;
	    $attribution         .= $q->div({-style=>'margin-left:1em'},"Maintained by $maintainer");
	}
        if (my $created    = $metadata->{created}) {
	    $attribution         .= $q->div({-style=>'margin-left:1em'},"Created $created");
        }
	
        if (my $modified   = $metadata->{modified}) {
	    $attribution         .= $q->div({-style=>'margin-left:1em'},"Modified $modified");
        }
	$html .= "<hr>$attribution" if $attribution;
	
    } else {
	$html = $q->i('No further information on',$q->b($source->name),'is available.');
    }
    return (200,'text/html',$html)
}

sub ACTION_about_me {
    my $self = shift;
    my $q    = shift;
    my $state = $self->state;

    my $html = $q->div(
	$q->h2('Session IDs'),
	$q->p('If you wish to use a script to upload or download browser data from this session',
	      'you will need the user and/or upload IDs for the currently active session.'),
	$q->p("Your   userID is",$q->b($state->{userid})),
	$q->p("Your uploadID is",$q->b($state->{uploadid})));
    return (200,'text/html',$html);
}

sub ACTION_list {
    my $self = shift;
    my $q    = shift;
    my $globals = $self->render->globals;
    my @sources = grep {$globals->data_source_show($_)} $globals->data_sources;
    my $text = '# '.join ("\t",
			  'Name',
			  'Description',
			  'Species',
			  'TaxID',
			  'CoordinateType',
			  'BuildAuthority',
			  'BuildVersion',
			  'BuildURL')."\n";
    for my $src (@sources) {
	my $dsn = $globals->create_data_source($src) or next;
	my $description = $globals->data_source_description($src);
	my $meta        = $dsn->metadata || {};
	$text .= join ("\t",
		       $src,
		       $description,
		       $meta->{species},
		       $meta->{taxid},
		       $meta->{source},
		       $meta->{authority},
		       $meta->{coordinates_version},
		       $meta->{coordinates})."\n";
    }
    return (200,'text/plain',$text);
}

1;

__END__

