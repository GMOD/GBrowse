package Bio::Graphics::Browser2::Render::Slave;

use strict;
use HTTP::Daemon;
use Storable qw(nfreeze thaw lock_store lock_retrieve);
use CGI qw(header param escape unescape);
use IO::File;
use IO::String;
use File::Spec;
use Text::ParseWords 'shellwords';
use File::Basename 'basename';
use File::Path 'mkpath';
use Bio::Graphics::GBrowseFeature;
use Bio::Graphics::Browser2;
use Bio::Graphics::Browser2::I18n;
use Bio::Graphics::Browser2::DataSource;
use Bio::Graphics::Browser2::RenderPanels;
use Bio::Graphics::Browser2::Region;
use Bio::Graphics::Browser2::RegionSearch; 
use Bio::Graphics::Browser2::DataBase;
use Time::HiRes 'time';
use POSIX 'WNOHANG','setsid','setuid';
use Fcntl ':flock';

use Carp 'croak';

use constant DEBUG => 0;
my %CHILDREN;

our ($bench_message,$bench_time);

BEGIN {
    use Storable qw(nfreeze thaw retrieve);
    $Storable::Deparse = 1;
    $Storable::Eval    = 1;
}

sub new {
    my $class       = shift;
    my %args        = @_;

    $args{ReuseAddr}          = 1 unless exists $args{ReuseAddr};
    $args{LocalPort}        ||= 8101;
    $args{Listen}           ||= 20;
    $args{PreForkCopies}    ||= 5;

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

sub d           { 
    my $self = shift;
    my $d    = $self->{daemon};
    $self->{daemon} = shift if @_;
    $d;
}
sub listen_port { shift->{args}{LocalPort} }
sub pidfile     { shift->{args}{PidFile}   }
sub logfile     { shift->{args}{LogFile}   }
sub user        { shift->{args}{User}      }
sub prefork_copies { shift->{args}{PreForkCopies}      }
sub pid         { shift->{pid}             }
sub config_cache{ shift->{args}{CCacheDir} || File::Spec->catfile(File::Spec->tmpdir,'gbslave_ccache')}
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
    if (@_) {
	my $conf_file    = shift;
	$self->{preload} = Bio::Graphics::FeatureFile->new(-file=>$conf_file);
	$self->{preload}->name($conf_file);
    }
    $d;
}

sub do_preload {
    my $self = shift;
    my $conf = $self->preload_databases or return;

    $self->Info("Preloading databases from ",$conf->name);

    my @labels      = $conf->configured_types;

    for my $l (@labels) {
	my $adaptor = $conf->setting($l=>'db_adaptor') or next;
	my $args    = $conf->setting($l=>'db_args')    or next;
	(my $label = $l) =~ s/:database//;  # aesthetic

	my @argv    = ref $args eq 'CODE'
	    ? $args->()
	    : shellwords($args||'');
	if (defined (my $a = $conf->setting($l => 'aggregators'))) {
	    my @aggregators = shellwords($a||'');
	    push @argv,(-aggregator => \@aggregators);
	}
	my $db = Bio::Graphics::Browser2::DataBase->open_database($adaptor,@argv);
	if ($db) {
	    $self->Info("Preloaded $adaptor database $label");
	} else {
	    $self->Warn("Failed to preload database $label");
	}
    }
}

sub run {
    my $self     = shift;
    $self->{pid} = $self->become_daemon;
    return $self->{pid} if $self->{pid};

    my $quit     = 0;
    my $rotate   = 0;

    $SIG{TERM}   = sub { $self->Info('TERM received'); $quit     = 1 };
    $SIG{HUP}    = sub { $self->Info('HUP received');  $rotate   = 1 };

    my $d = $self->d;
    $self->Info('GBrowse render slave starting on port ',$self->listen_port);
    $self->do_preload;

    %CHILDREN = map {$_=>1} $self->prefork($self->prefork_copies);

    # parent sleeps until children need to be "taken care" of
    if (!%CHILDREN) {
	$self->request_loop;
	CORE::exit 0;
    }

    if (%CHILDREN) { 
#	$d->close;
      SLEEP:
	while (1) {
	    sleep;
	    if ($quit) {
		CORE::kill TERM=>keys %CHILDREN;
		last SLEEP;
	    }

	    if ($rotate) {
		$self->Info("Reopening log file");
		$self->open_log;
		$rotate = 0;
		next SLEEP;
	    }

	    $self->Info('children remaining = ', join ' ',keys %CHILDREN);
	    if (keys %CHILDREN < $self->prefork_copies) {
		my @new_children = $self->prefork($self->prefork_copies - keys %CHILDREN);
		unless (@new_children) {
		    $self->request_loop;
		    CORE::exit 0;
		}
		%CHILDREN = (%CHILDREN,map {$_=>1} @new_children);
		next SLEEP;
	    }

	}
	unlink $self->pidfile if $self->pidfile;
	$self->Info('Normal termination');
    }

    CORE::exit 0;
}

sub prefork {
    my $self   = shift;
    my $copies = shift;
    my @children;

    for (1..$copies) {
	my $child = fork();
	$DB::inhibit_exit = 0;
	die "fork() error: $!" unless defined $child;
	if ($child) {
	    $self->Info("preforked pid $child");
	    push @children,$child;
	} else {
	    return;
	}
    }
    return @children;

}

sub request_loop {
    my $self = shift;
    my $d    = $self->d;
    $self->preload_databases;

    my $quit = 0;
    $SIG{TERM}   = sub { $quit     = 1 };
    while (!$quit) {
	my $c  = $d->accept() or next; # accept() is interruptable...
	$self->process_connection($c);
    }
}

sub process_connection {
    my $self = shift;
    my $c    = shift;
    $self->Debug("Connect from ",$c->peerhost);

    while (my $r = $c->get_request) {
	my $time = time();
	$self->process_request($r,$c);
	my $elapsed = time() - $time;
	$self->Debug("Process_request time: $elapsed s");
    }

    $self->Debug("Finished connection from ",$c->peerhost);
    $c->close;
}


sub process_request {
    my $self = shift;
    my ($r,$c) = @_;

    $self->Bench('reading request');

    CGI::initialize_globals();
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
    $self->Bench('setting environment');
    $self->setup_environment(param('env'));
    my $operation = param('operation') || 'invalid';

    $self->Debug("process_request(): operation = $operation");

    # make sure databases are already open in parent process
    $self->Bench('thawing parameters');
    my $tracks   = thaw param('tracks')     if param('tracks');
    my $settings = thaw param('settings')   if param('settings');
    my $dsn      = param('datasource');
    my $d_name   = param('data_name');
    my $d_mtime  = param('data_mtime');
    my $source   = $self->get_datasource($dsn,$d_name,$d_mtime);
    unless ($source) {
	$self->Info('sending REQUEST DATASOURCE response');
	$c->send_response(HTTP::Response->new(403=>"REQUEST DATASOURCE: $d_name"));
	return;
    }
    $source or return (403,"REQUEST DATASOURCE: $d_name");

    $self->Bench('loading databases');
    $self->load_databases($tracks,$source) if $tracks;
    
    # forking version
    if ($self->prefork_copies <= 1) {
	$self->Bench('forking child');
	my $child = fork();
	$DB::inhibit_exit = 0;
	$self->Fatal("Couldn't fork: $!") unless defined $child;
	if ($child) {
	    $self->Info("Forked child PID $child");
	    return;
	} else {
	    $self->d->close();
	    $self->Bench('cloning databases');
	    Bio::Graphics::Browser2::DataBase->clone_databases();
	    $self->Bench("operation $operation");
	    $self->run_operation($c,$operation,$tracks,$source,$settings);
	    $self->Bench("cleaning up");
	    exit 0;
	}
    }
    # preforked version
    else {
	$self->Bench("operation $operation");
	$self->run_operation($c,$operation,$tracks,$source,$settings);
	$self->Bench("cleaning up");
    }
}

sub run_operation {
    my $self      = shift;
    my ($c,$operation,$tracks,$source,$settings) =  @_;

    my $content   = $operation eq 'render_tracks'   ? $self->render_tracks($tracks,  $source, $settings)
                  : $operation eq 'search_features' ? $self->search_features($tracks,$source, $settings)
                                                    : 'invalid request';

    my ($status_code,$status_text,$content_type) = 
	$content =~ /invalid/i ? (400 => 'Bad request', 'text/plain')
	                       : (200 => 'Ok',          'application/gbrowse-encoded-genome');

    $self->Bench('creating response');

    my $response = HTTP::Response->new($status_code => $status_text,
			      ['Content-type'   => $content_type,
			       'Content-length' => length $content],
			       $content
			      );

    $self->Bench('sending response');
    $c->send_response($response);
    $self->Info("host=",$c->peerhost,"; operation=$operation; response=$status_code; bytes=",length $content);
}

sub load_databases {
    my $self   = shift;
    my ($tracks,$source,$settings) = @_;
    for my $t (@$tracks) {
	# this caches databases in memory
	my $length = defined $settings->{start} ? $settings->{start}-$settings->{stop}+1 : 0;
	my $db = $source->open_database($t,$length);
    }
}

sub Bench {
    my $self = shift;
    my $msg = shift;

    if ($bench_time && $bench_message) {
	my $elapsed = time()-$bench_time;
	$self->Debug("BENCH: $bench_message: $elapsed s");
    }

    $bench_message = $msg;
    $bench_time    = time();
}

sub get_datasource {
    my $self = shift;
    my ($dsn,$name,$mtime)  = @_;

    $self->Bench('getting datasource');
    mkpath $self->config_cache unless -e $self->config_cache;

    if (Storable::read_magic($dsn)) { # this is a storable image
	my $source = Storable::thaw($dsn);
	$name   = $source->name;
	$mtime  = $source->mtime;
	my $cachefile = File::Spec->catfile($self->config_cache,$name);
	$self->Debug("Using transmitted version of $name");
	lock_store($source,$cachefile);
	return $source;
    } elsif ($name) {
	my $cachefile = File::Spec->catfile($self->config_cache,$name);
	if (-e $cachefile && $mtime <= (stat(_))[9]) {
	    $self->Debug("Using cached version of $name config data");
	    my $source = lock_retrieve($cachefile);
	    return $source;
	} else {
	    $self->Debug("Cache for $name missing or out of date; requesting frozen dsn");
	    return;
	}
    } else {
	$self->Debug("Datasource name missing; requesting frozen dsn");
	return;
    }
}

sub render_tracks {
    my $self = shift;
    my ($tracks,$datasource,$settings) = @_;

    my $language	= thaw param('language');
    my $panel_args      = thaw param('panel_args');

    $self->do_init($datasource);
    $self->adjust_conf($datasource);

    $self->Debug("render_tracks(): Opening database...");

    # Find the segment - it may be hiding in any of the databases.
    $self->Bench('searching for segment');
    my (%seenit,$segment,$db);
    if ($panel_args->{section} and $panel_args->{section} eq 'detail') { # short cut
	$segment = Bio::Graphics::Feature->new(-seq_id=>$settings->{'ref'},
					       -start => $settings->{'start'},
					       -end   =>$settings->{'stop'});
    } else {
	for my $track ('general',@$tracks) {
	    $db = $datasource->open_database($track) or next;
	    next if $seenit{$db}++;
	    ($segment) = $db->segment(-name	=> $settings->{'ref'},
				      -start    => $settings->{'start'},
				      -stop	=> $settings->{'stop'});
	    last if $segment;
	}
    }

    $self->Fatal("Can't get segment for $settings->{ref}:$settings->{start}..$settings->{stop} (1)")
	unless $segment;

    $self->Debug("render_tracks(): Got database handle $db") if $db;

    # BUG: duplicated code from Render.pm -- move into a common place
    $panel_args->{section} ||= '';  # prevent uninit variable warnings
    if ($panel_args->{section} eq 'overview') {
	$segment = Bio::Graphics::Browser2::Region->whole_segment($segment,$settings);
    } elsif ($panel_args->{section} eq 'region') {
	$segment  = Bio::Graphics::Browser2::Region->region_segment($segment,$settings);
    }

    $self->Fatal("Can't get segment for $settings->{ref}:$settings->{start}..$settings->{stop} (2)")
	unless $segment;
	    
    # generate the panels
    $self->Bench('creating renderpanel');
    $self->Debug("calling RenderPanels->new()");
    my $renderer = Bio::Graphics::Browser2::RenderPanels->new(-segment  => $segment,
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
		return $settings->{h_feat}{lc $feature->display_name};
	    };
    }

    $self->Bench('calling make_requests');
    my $requests = $renderer->make_requests({labels => $tracks,%$panel_args});

    $self->Debug("Calling run_local_requests(tracks=@$tracks)");
    $self->Bench('calling run_local_requests');
    $renderer->run_local_requests($requests,$panel_args);

    $self->Debug("Finished run_local_requests()");

    # we return the URL to the PNG, the image map, the width and height of the image,
    # keyed to the requested label(s)
    my %results;
    for my $label (keys %$requests) {
	
	my $response  = $requests->{$label};
	my $map       = $response->map;
	my $titles    = $response->titles;
	my $width     = $response->width;
	my $height    = $response->height;
	my $imagedata = $response->gd;

	$results{$label} = {map       => $map,
			    titles    => $titles,
			    width     => $width,
			    height    => $height,
			    imagedata => eval{$imagedata->gd2}};
    }
    my $content = nfreeze \%results;
    return $content;
}

sub search_features {
    my $self = shift;
    my ($tracks,$datasource,$settings) = @_;

    my $searchargs      = thaw param('searchargs');

    # initialize a region search object
    my $search = Bio::Graphics::Browser2::RegionSearch->new(
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
	next unless $key =~ /^(GBROWSE|HTTP)/;
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
	while ((my $c = waitpid(-1,WNOHANG))>0) { 
	    $self->Info("Child pid $c terminated");
	    delete $CHILDREN{$c};
	}
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

# adjust the passed config file by overriding any options specified in the
# preload config file
sub adjust_conf {
    my $self       = shift;
    my $datasource = shift;

    my $preload    = $self->preload_databases     or return;
    my @settings   = $preload->setting('general') or return;
    my $globals    = $datasource->globals;
    $self->Debug('Overriding passed settings with slave-specific settings from preload file');
    for my $s (@settings) {
	my $value = $preload->setting(general=>$s);
	$globals->setting(general=>$s,$value);
    }
}

sub do_init {
    my $self = shift;
    my $datasource = shift;
    $self->Debug('do_init()');
    $datasource->initialize_code();
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
