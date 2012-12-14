#!/usr/bin/perl

use strict;
use Getopt::Long;
use GBrowse::ConfigData;
use File::Spec;
use Bio::Graphics::Browser2::Render::Slave::AWS_Balancer;

my $balancer;

$SIG{TERM} = sub {exit 0};
$SIG{INT}  = sub {exit 0};
END {  $balancer->cleanup() if $balancer }

my($Access_key,$Secret_key);
GetOptions(
	   'access_key=s'  => \$Access_key,
	   'secret_key=s'  => \$Secret_key,
    ) or exec 'perldoc',$0;

my $conf  = File::Spec->catfile(GBrowse::ConfigData->config('conf'),'aws_slave.conf');
$balancer = Bio::Graphics::Browser2::Render::Slave::AWS_Balancer->new($conf,$Access_key,$Secret_key);
$balancer->verbosity(5);
$balancer->run();

exit 0;

