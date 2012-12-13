#!/usr/bin/perl

use strict;
use Getopt::Long;
use Bio::Graphics::Browser2::Render::Slave::AWS_Balancer;

my $balancer;

$SIG{TERM} = sub {exit 0};
$SIG{INT}  = sub {exit 0};
END {  undef $balancer }


my($Access_key,$Secret_key);
GetOptions(
	   'access_key=s'  => \$Access_key,
	   'secret_key=s'  => \$Secret_key,
    ) or exec 'perldoc',$0;

#setup defaults
$ENV{EC2_ACCESS_KEY} = $Access_key if defined $Access_key;
$ENV{EC2_SECRET_KEY} = $Secret_key if defined $Secret_key;

$balancer = Bio::Graphics::Browser2::Render::Slave::AWS_Balancer;
$balancer->run();

exit 0;

