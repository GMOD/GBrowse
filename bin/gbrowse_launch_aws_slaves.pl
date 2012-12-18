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

my($ConfFile,$AccessKey,$SecretKey,$PidFile,$LogFile,$Daemon,$User,$Verbosity,$Kill);
GetOptions(
	   'access_key=s'  => \$AccessKey,
	   'secret_key=s'  => \$SecretKey,
	   'conf=s'        => \$ConfFile,
	   'pidfile=s'     => \$PidFile,
	   'logfile=s'     => \$LogFile,
           'user=s'        => \$User,
           'verbosity=i'   => \$Verbosity,
	   'kill'          => \$Kill,
	   'daemon'        => \$Daemon,

    ) or exec 'perldoc',$0;

$ConfFile  ||= File::Spec->catfile(GBrowse::ConfigData->config('conf'),'aws_slave.conf');

$balancer = Bio::Graphics::Browser2::Render::Slave::AWS_Balancer->new(
    -conf       => $ConfFile,
    -access_key => $AccessKey||'',
    -secret_key => $SecretKey||'',
    -logfile    => $LogFile||'',
    -pidfile    => $PidFile||'',
    -user       => $User||'',
    -daemon     => $Daemon||0,
    );

$Verbosity = 3 unless defined $Verbosity;
$balancer->verbosity($Verbosity);
if ($Kill) {
    $balancer->stop_daemon;
} else {
    $balancer->run();
}

exit 0;

