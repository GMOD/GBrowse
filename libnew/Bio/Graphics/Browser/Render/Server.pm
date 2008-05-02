package Bio::Graphics::Browser::Render::Server;

use strict;
use HTTP::Daemon;
use Storable qw(freeze thaw);
use CGI qw(header param escape unescape);
use IO::File;
use File::Basename 'basename';
use Storable qw(freeze thaw retrieve);
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::I18n;
use Bio::Graphics::Browser::DataSource;
use Bio::Graphics::Browser::RenderPanels;
use POSIX 'WNOHANG';

use Carp 'croak';

use constant DEBUG => 0;

sub new {
    my $class       = shift;
    my %socket_args = @_;

    $socket_args{LocalAddr} ||= 'localhost';
    $socket_args{Reuse}       = 1 unless exists $socket_args{Reuse};
    $socket_args{LocalPort} ||= 8123;

    my $d = HTTP::Daemon->new(%socket_args) or croak "could not create daemon socket: @_";
    return bless {
	daemon => $d,
	args   => \%socket_args,
	debug  => DEBUG,
    },ref $class || $class;
}

sub d           { shift->{daemon}          }
sub listen_port { shift->{args}{LocalPort} }
sub pid         { shift->{pid}             }
sub kill        { kill TERM=>(shift->pid)  }

sub debug {
    my $self = shift;
    my $d    = $self->{debug};
    $self->{debug} = shift if @_;
    return $d;
}

sub run {
    my $self = shift;

    my $child = fork();
    croak "Couldn't fork: $!" unless defined $child;
    return $self->{pid} = $child if $child;  # return child in parent process

    # install signal handler in the master server
    $SIG{CHLD} = sub {
	while ((my $c = waitpid(-1,WNOHANG))>0) { }
    };

#    chdir '/';  # this is breaking relative paths in the regression test config files
    close STDIN;
    close STDOUT;
    close STDERR unless $self->debug;

    # accept loop in child process
    my $d = $self->d;
    while (1) {
	print STDERR "$$: waiting for connection(",$self->listen_port,")\n" if $self->debug>1;
	my $c = $d->accept() or next; # accept() is interruptable...
	$child = fork();
	croak "Couldn't fork: $!" unless defined $child;
	if ($child) {
	    $c->close();
	} else {
	    $d->close();
	    $self->process_connection($c);
	    $c->close();
	    exit 0;
	}
	print STDERR "$$: waiting for connection (",$self->listen_port,")\n" if $self->debug>1;
    }
    print STDERR "$$: exiting (",$self->listen_port,")\n" if $self->debug>1;
    exit 0;
}

sub process_connection {
    my $self = shift;
    my $c    = shift;
    print STDERR "$$: process_connection(START) (",$self->listen_port,")\n" if $self->debug>1;

    while (my $r = $c->get_request) {
	$self->process_request($r,$c);
    }

    print STDERR "$$: process_connection(END) (",$self->listen_port,")\n" if $self->debug>1;
}


sub process_request {
    my $self = shift;
    my ($r,$c) = @_;
    print STDERR "$$: process_request(START)(",$self->listen_port,")\n" if $self->debug>1;

    my $args = $r->method eq 'GET' ? $r->uri->query
              :$r->method eq 'POST'? $r->content
              : '';
    $CGI::Q  = new CGI($args);
    
    my $tracks	        = thaw param('tracks');
    my $settings	= thaw param('settings');
    my $datasource	= thaw param('datasource');
    my $language	= thaw param('language');

    my $db = $datasource->open_database();

    # extract segments
    my ($segment) = $db->segment(-name	=> $settings->{'ref'},
				 -start	=> $settings->{'start'},
				 -stop	=> $settings->{'stop'});
    die "can't get segment!" unless $segment;
	    
    # generate the panels
    print STDERR "$$: calling RenderPanels->new()\n" if $self->debug;
    my $renderer = Bio::Graphics::Browser::RenderPanels->new(-segment  => $segment,
							     -source   => $datasource,
							     -settings => $settings,
							     -language => $language);
    print STDERR "$$: got renderer()\n";

    my $requests = $renderer->make_requests({labels => $tracks});

    print STDERR "$$: calling run_local_requests()\n" if $self->debug;

    $renderer->run_local_requests($requests);

    print STDERR "$$: finished run_local_requests()\n" if $self->debug;

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
    my $length  = length $content;
    
    my $response = HTTP::Response->new(200 => 'Ok',
				       ['Content-type'   => 'application/gbrowse-encoded-genome',
					'Content-length' => $length],
				       $content);
    $c->send_response($response);

    print STDERR "$$: process_request(END)(",$self->listen_port,")\n" if $self->debug>1;
}


1;
