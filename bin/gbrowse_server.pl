#!/usr/bin/perl

use strict;
use Getopt::Long;
use FindBin '$Bin';
use lib "$Bin/../libnew";

use Bio::Graphics::Browser::Render::Server;

my ($port,$debug,$logfile);

my $usage = <<USAGE;
Usage: $0 [options]

Options:

    --port    -p  <port>  Network port number to listen to.
    --verbose -v  <level> Verbosity level (0-3)
    --log     -l  <path>  Log file (not implemented)

Bare-naked Gbrowse render server.
Launch with the port number to listen on.

No other configuration information is necessary. The
needed configuration will be transmitted from the master
server at run time.
USAGE
    ;

GetOptions('port=i'     => \$port,
	   'verbose=i'  => \$debug,
	   'logfile'    => \$logfile) or die $usage;

my $port   = $port
    or die $usage;
my $server = Bio::Graphics::Browser::Render::Server->new(LocalPort=>$port)
    or die "Could not create server.\n";

$server->debug($debug);
$server->run();
exit 0;
