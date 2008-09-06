package Bio::Graphics::Browser::Render::Server;

use strict;
use HTTP::Daemon;
use Storable qw(freeze thaw);
use CGI qw(header param escape unescape);
use IO::File;
use File::Basename 'basename';
use Bio::Graphics::Feature;
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::I18n;
use Bio::Graphics::Browser::DataSource;
use Bio::Graphics::Browser::RenderPanels;
use Bio::Graphics::Browser::RegionSearch; 
use POSIX 'WNOHANG','setsid','setuid';

use Carp 'croak';

use constant DEBUG => 0;

BEGIN {
    use Storable qw(freeze thaw retrieve);
    $Storable::Deparse = 1;
    $Storable::Eval    = 1;
}

sub new {
    my $class       = shift;
    my %args        = @_;

    $args{LocalAddr} ||= 'localhost';
    $args{Reuse}       = 1 unless exists $args{Reuse};
    $args{LocalPort} ||= 8123;

    my $d = HTTP::Daemon->new(%args)
	or croak "could not create daemon socket: @_";

    return bless {
	daemon => $d,
	args   => \%args,
	debug  => DEBUG,
    },ref $class || $class;
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
	    $c->close();
	} else {
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

    my $args = $r->method eq 'GET' ? $r->uri->query
              :$r->method eq 'POST'? $r->content
              : '';
    $CGI::Q  = CGI->new($args);

    $self->setup_environment(param('env'));
    my $operation = param('operation') || 'invalid';

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

    my $tracks	        = thaw param('tracks');
    my $settings	= thaw param('settings');
    my $datasource	= thaw param('datasource');
    my $language	= thaw param('language');

    my $db = $datasource->open_database();

    # extract segments
    my ($segment) = $db->segment(-name	=> $settings->{'ref'},
				 -start	=> $settings->{'start'},
				 -stop	=> $settings->{'stop'});
    $self->Fatal("Can't get segment for $settings->{ref}:$settings->{start}..$settings->{stop}")
	unless $segment;
	    
    # generate the panels
    $self->Debug("Calling RenderPanels->new()");
    my $renderer = Bio::Graphics::Browser::RenderPanels->new(-segment  => $segment,
							     -source   => $datasource,
							     -settings => $settings,
							     -language => $language);
    $self->Debug("Got renderer()");

    my $requests = $renderer->make_requests({labels => $tracks});

    $self->Debug("Calling run_local_requests()");

    $renderer->run_local_requests($requests);

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
			    imagedata => $imagedata};
    }
    my $content = freeze \%results;
    return $content;
}

sub search_features {
    my $self = shift;

    my $searchterm      = param('searchterm');
    my $tracks	        = thaw param('tracks');
    my $settings	= thaw param('settings');
    my $datasource	= thaw param('datasource');

    # initialize a region search object
    my $search = Bio::Graphics::Browser::RegionSearch->new(
	{source => $datasource,
	 state  => $settings}
	) or return;
    $search->init_databases($tracks);

    my $results = $search->search_features_locally($searchterm);
    return unless $results;
    my @features = map {
      Bio::Graphics::Feature->new(
	  -name   => $_->name,
	  -seq_id => $_->seq_id,
	  -start  => $_->start,
	  -end    => $_->end,
	  -strand => $_->strand,
	  -score  => eval{$_->score} || 0,
	  -desc   => eval{$_->desc}  || '',
	  );
    } @$results;
    return freeze(\@features);
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
    open STDERR,">&STDOUT" if $self->logfile;

    # write out PID file if requested
    if (my $l = $self->pidfile) {
	my $fh = IO::File->new($l,">") 
	    or $self->Fatal("Could not open pidfile $l: $!");
	$fh->print($$)
	    or $self->Fatal("Could not write to pidfile $l: $!");
	$fh->close();
    }

    $self->open_log;
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
