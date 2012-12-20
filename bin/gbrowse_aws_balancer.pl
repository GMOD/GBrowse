#!/usr/bin/perl

use strict;
use Getopt::Long;
use GBrowse::ConfigData;
use File::Spec;
use Bio::Graphics::Browser2::Render::Slave::AWS_Balancer;

my $balancer;

# this obscures the AWS secrets from ps; it is not 100% effective
($0 = "$0 @ARGV") =~ s/(\s--?[as]\S*?)(=|\s+)\S+/$1$2xxxxxxxxxx/g;

$SIG{TERM} = sub {exit 0};
$SIG{INT}  = sub {exit 0};

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
	   'background'    => \$Daemon,

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

