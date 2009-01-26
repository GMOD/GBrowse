package Bio::Graphics::Browser::Render::Slave;

use strict;
use HTTP::Daemon;
use Storable qw(nfreeze thaw);
use CGI qw(header param escape unescape);
use IO::File;
use IO::String;
use File::Spec;
use Text::ParseWords 'shellwords';
use File::Basename 'basename';
use Bio::Graphics::GBrowseFeature;
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::I18n;
use Bio::Graphics::Browser::DataSource;
use Bio::Graphics::Browser::RenderPanels;
use Bio::Graphics::Browser::Region;
use Bio::Graphics::Browser::RegionSearch; 
use Bio::Graphics::Browser::DataBase;
use POSIX 'WNOHANG','setsid','setuid';

use Carp 'croak';

use constant DEBUG => 0;

BEGIN {
    use Storable qw(nfreeze thaw retrieve);
    $Storable::Deparse = 1;
    $Storable::Eval    = 1;
}

sub new {
    my $class       = shift;
    my %args        = @_;

    $args{ReuseAddr}    = 1 unless exists $args{ReuseAddr};
    $args{LocalPort}  ||= 8101;
    $args{Listen}     ||= 20;

    delete $args{LocalPort} if $args{LocalPort} eq 'dynamic'; 

    my $d = HTTP::Daemon->new(%args)
	or croak "Could not create daemon socket: $@";

    $args{LocalPort} ||= $d->sockport;

    my $self = bless {
	daemon => $d,
	args   => \%args,
	debug  => DEBUG,
    },ref $class || $class;

    return $self;
}

sub d           { shift->{daemon}          }
sub listen_port { shift->{args}{LocalPort} }
sub pidfile     { shift->{args}{PidFile}   }
sub logfile     { shift->{args}{LogFile}   }
sub user        { shift->{args}{User}      }
sub pid         { shift->{pid}             }
sub kill        {
    my $self = shift;
    my $pid  = $self->pid;
    if (!$pid && (my $pidfile = $self->pidfile)) {
	my $fh = IO::File->open($pidfile);
	$pid   = $fh->getline;
	chomp($pid);
	$fh->close;
    }
    kill TERM=>$pid if defined $pid;
}
sub logfh       {
    my $self = shift;
    my $d    = $self->{logfh};
    $self->{logfh} = shift if @_;
    $d;
}

sub debug {
    my $self = shift;
    my $d    = $self->{debug};
    $self->{debug} = shift if @_;
    return $d;
}

sub preload_databases {
    my $self         = shift;
    my $d            = $self->{preload};
    $self->{preload} = shift if @_;
    $d;
}

sub do_preload {
    my $self = shift;
    my $conf_file = $self->{preload} or return;

    $self->Info("Preloading databases from $conf_file");

    my $conf      = Bio::Graphics::FeatureFile->new(-file=>$conf_file)
	or return;

    my @labels      = $conf->configured_types;

    for my $l (@labels) {
	my $adaptor = $conf->setting($l=>'db_adaptor');
	my $args    = $conf->setting($l=>'db_args');
	my @argv    = ref $args eq 'CODE'
	    ? $args->()
	    : shellwords($args||'');
	if (defined (my $a = $conf->setting($l => 'aggregators'))) {
	    my @aggregators = shellwords($a||'');
	    push @argv,(-aggregator => \@aggregators);
	}
	my $db = Bio::Graphics::Browser::DataBase->open_database($adaptor,@argv);
	if ($db) {
	    $self->Info("Preloaded $adaptor database $l");
	} else {
	    $self->Warn("Failed to preload database $l");
	}
    }
}

sub run {
    my $self     = shift;
    $self->{pid} = $self->become_daemon;
    return $self->{pid} if $self->{pid};

    my $quit     = 0;
    my $rotate   = 0;

    $SIG{TERM}   = sub { $quit     = 1 };
    $SIG{HUP}    = sub { $rotate   = 1 };

    my $d     = $self->d;
    $self->Info('GBrowse render slave starting on port ',$self->listen_port);
    $self->do_preload;

    # accept loop in child process
    while (!$quit) {

	if ($rotate) {
	    $self->Info("Reopening log file");
	    $self->open_log;
	    $rotate = 0;
	    next;
	}

	$self->Debug("Waiting for connection...");
	my $c     = $d->accept() or next; # accept() is interruptable...
	my $child = fork();
	$self->Fatal("Couldn't fork: $!") unless defined $child;
	if ($child) {
	    $self->Info("Forked child PID $child");
	    $c->close();
	} else {
	    Bio::Graphics::Browser::DataBase->clone_databases();
	    $self->process_connection($c);
	    $d->close();
	    $c->close();
	    exit 0;
	}
    }
    $self->Info('Normal termination');
    unlink $self->pidfile if $self->pidfile;
    CORE::exit 0;
}

sub process_connection {
    my $self = shift;
    my $c    = shift;
    $self->Debug("Connect from ",$c->peerhost);

    while (my $r = $c->get_request) {
	$self->process_request($r,$c);
    }

    $self->Debug("Finished connection from ",$c->peerhost);
}


sub process_request {
    my $self = shift;
    my ($r,$c) = @_;

    if ($r->method eq 'GET') {
	$CGI::Q = CGI->new($r->uri->query);
    } elsif ($r->method eq 'POST') {
        # This is all to trick CGI.pm into thinking that it is getting the
	# request from the usual CGI environment.
	tie *STDIN,IO::String->new($r->content); 
	$ENV{REQUEST_METHOD} = 'POST';
	$ENV{CONTENT_LENGTH} = $r->content_length;
	$ENV{CONTENT_TYPE}   = $r->content_type;
	$CGI::Q = CGI->new();
    }

    $self->Debug("process_request(): read ",$r->content_length," bytes");

    $self->Debug("process_request(): setting environment");

    $self->setup_environment(param('env'));
    my $operation = param('operation') || 'invalid';

    $self->Debug("process_request(): operation = $operation");

    my $content   = $operation eq 'render_tracks'   ? $self->render_tracks
                  : $operation eq 'search_features' ? $self->search_features
                                                    : 'Invalid request';

    my ($status_code,$status_text,$content_type) =
	$content !~ /invalid/i
	? (200 => 'Ok',          'application/gbrowse-encoded-genome')
	: (400 => 'Bad request', 'text/plain');

    my $response = HTTP::Response->new($status_code => $status_text,
			      ['Content-type'   => $content_type,
			       'Content-length' => length $content],
			       $content
			      );

    $c->send_response($response);
    $self->Info("host=",$c->peerhost,"; operation=$operation; response=$status_code; bytes=",length $content);
}

sub render_tracks {
    my $self = shift;

    $self->Debug("render_tracks(): thawing parameters");

    my $tracks	        = thaw param('tracks');
    my $settings	= thaw param('settings');
    my $datasource	= thaw param('datasource');
    my $language	= thaw param('language');
    my $panel_args      = thaw param('panel_args');

    $self->Debug("render_tracks(): Opening database...");

    # Find the segment - it may be hiding in any of the databases.
    my (%seenit,$segment,$db);
    for my $track ('general',@$tracks) {
	$db = $datasource->open_database($track) or next;
	next if $seenit{$db}++;
	($segment) = $db->segment(-name	=> $settings->{'ref'},
				  -start=> $settings->{'start'},
				  -stop	=> $settings->{'stop'});
	last if $segment;
    }

    $self->Fatal("Can't get segment for $settings->{ref}:$settings->{start}..$settings->{stop} (1)")
	unless $segment;

    $self->Debug("render_tracks(): Got database handle $db");
    $self->Debug("rendering tracks @$tracks");


    # BUG: duplicated code from Render.pm -- move into a common place
    $panel_args->{section} ||= '';  # prevent uninit variable warnings
    if ($panel_args->{section} eq 'overview') {
	$segment = Bio::Graphics::Browser::Region->whole_segment($segment,$settings);
    } elsif ($panel_args->{section} eq 'region') {
	$segment  = Bio::Graphics::Browser::Region->region_segment($segment,$settings);
    }

    $self->Fatal("Can't get segment for $settings->{ref}:$settings->{start}..$settings->{stop} (2)")
	unless $segment;
	    
    # generate the panels
    $self->Debug("Calling RenderPanels->new()");
    my $renderer = Bio::Graphics::Browser::RenderPanels->new(-segment  => $segment,
							     -source   => $datasource,
							     -settings => $settings,
							     -language => $language);
    $self->Debug("Got renderer()");

    #FIX: this is a cut and paste, and isn't fully general!
    # hiliting should be handled in RenderPanels, not in Render
    if ($settings->{h_feat}) {
	$panel_args->{hilite_callback} =  sub {
	        my $feature = shift;
		# if we get here, we select the search term for highlighting
		return unless $feature->display_name;
		return $settings->{h_feat}{$feature->display_name};
	    };
    }

    my $requests = $renderer->make_requests({labels => $tracks,%$panel_args});

    $self->Debug("Calling run_local_requests(tracks=@$tracks)");

    $renderer->run_local_requests($requests,$panel_args);

    $self->Debug("Finished run_local_requests()");

    # we return the URL to the PNG, the image map, the width and height of the image,
    # keyed to the requested label(s)
    my %results;
    for my $label (keys %$requests) {
	
	my $response  = $requests->{$label};
	my $map       = $response->map;
	my $width     = $response->width;
	my $height    = $response->height;
	my $imagedata = $response->gd;

	$results{$label} = {map       => $map,
			    width     => $width,
			    height    => $height,
			    imagedata => eval{$imagedata->gd2}};
    }
    my $content = nfreeze \%results;
    return $content;
}

sub search_features {
    my $self = shift;

    my $searchargs      = thaw param('searchargs');
    my $tracks	        = thaw param('tracks');
    my $settings	= thaw param('settings');
    my $datasource	= thaw param('datasource');

    # initialize a region search object
    my $search = Bio::Graphics::Browser::RegionSearch->new(
	{source => $datasource,
	 state  => $settings}
	) or return;
    $search->init_databases($tracks,'local_search');

    warn "SERVER, dbid = ",$settings->{dbid} if DEBUG;

    my $results = $search->search_features_locally($searchargs);
    return unless $results;
    my @features = map { $self->clone_feature($_) } grep {defined $_} @$results;
    return nfreeze(\@features);
}

sub clone_feature {
    my $self  = shift;
    my $f     = shift;
    my $level = shift || 0;
    my %attributes = map {$_=>[$f->get_tag_values($_)]} eval {$f->get_all_tags};
    my $clone = Bio::Graphics::GBrowseFeature->new(
					    -name   => $f->name,
					    -primary_tag => $f->primary_tag,
					    -source_tag  => eval {$f->source_tag} || 'region',
					    -seq_id => $f->seq_id,
					    -start  => $f->start,
					    -end    => $f->end,
					    -strand => $f->strand,
					    -score  => eval{$f->score} || 0,
					    -desc   => eval{$f->desc}  || '',
					    -primary_id => eval{$f->primary_id} || undef,
					    -attributes => \%attributes,
					    );
    for my $s (map {$self->clone_feature($_,$level+1)} $f->get_SeqFeatures()) {
	$clone->add_SeqFeature($s) ;
    }
    $clone->gbrowse_dbid($f->gbrowse_dbid) 
	if $level == 0 && $f->can('gbrowse_dbid');
    return $clone;
}

sub setup_environment {
    my $self    = shift;
    my $env_str = shift or return;

    my $env     = thaw($env_str);
    for my $key (keys %$env) {
	next unless $key =~ /^GBROWSE/;
	$ENV{$key}       = $env->{$key};
    }
}

sub become_daemon {
    my $self = shift;

    my $child = fork();
    croak "Couldn't fork: $!" unless defined $child;
    return $child if $child;  # return child PID in parent process

    # install signal handler in the master server
    $SIG{CHLD} = sub {
	while ((my $c = waitpid(-1,WNOHANG))>0) { }
    };
    umask(0);
    $ENV{PATH} = '/bin:/sbin:/usr/bin:/usr/sbin';

    setsid();   # become process leader
    chdir '/';  # don't hold open working directories
    open STDIN, "</dev/null";
    open STDOUT,">/dev/null";

    # write out PID file if requested
    if (my $l = $self->pidfile) {
	my $fh = IO::File->new($l,">") 
	    or $self->Fatal("Could not open pidfile $l: $!");
	$fh->print($$)
	    or $self->Fatal("Could not write to pidfile $l: $!");
	$fh->close();
    }

    $self->open_log;

    open STDERR,">&",$self->logfh if $self->logfh;
    $self->set_user;
    return;
}

# open log file if requested
sub open_log {
    my $self = shift;
    my $l = $self->logfile or return;
    my $fh = IO::File->new($l,">>")  # append
	or $self->Fatal("Could not open logfile $l: $!");
    $fh->autoflush(1);
    $self->logfh($fh);
}

# change user if requested
sub set_user {
    my $self = shift;
    my $u = $self->user or return;
    my $uid = getpwnam($u);
    defined $uid or $self->Fatal("Cannot change uid to $u: unknown user");
    setuid($uid) or $self->Fatal("Cannot change uid to $u: $!");
}

sub Debug {
    my $self = shift;
    my @msg  = @_;
    return unless $self->debug > 2;
    $self->_log('debug',@msg);
}

sub Info {
    my $self = shift;
    my @msg  = @_;
    return unless $self->debug > 1;
    $self->_log('info',@msg);
}

sub Warn {
    my $self = shift;
    my @msg  = @_;
    return unless $self->debug > 0;
    $self->_log('warn',@msg);
}

sub Fatal {
    my $self = shift;
    my @msg  = @_;
    $self->_log('fatal',@msg);
    croak @msg;
}

sub _log {
    my $self         = shift;
    my ($level,@msg) = @_;
    my $time         = localtime();
    my $fh           = $self->logfh || \*STDERR;
    $fh->printf("%25s %-8s %-12s","[$time]","[$level]","[pid=$$]");
    $fh->print(@msg,"\n");
}

1;
