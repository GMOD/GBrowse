#!/usr/bin/perl

=head1 NAME

gbrowse_aws_balancer.pl  Load balance GBrowse using Amazon Web Service instances

=head1 SYNOPSIS

Launch the balancer in the foreground

 % gbrowse_aws_balancer.pl --conf         /etc/gbrowse2/aws_balancer.conf \
                           --access_key   XYZZY \
                           --secret_key   Plugh

Launch the balancer in the background as a daemon:

 % gbrowse_aws_balancer.pl --background \
                           --conf         /etc/gbrowse2/aws_balancer.conf \
                           --access_key   XYZZY \
                           --secret_key   Plugh \
                           --logfile      /var/log/gbrowse2/aws_balancer.log \
                           --pidfile      /var/run/aws_balancer.pid \
                           --user         nobody

Kill a running balancer daemon:

 % gbrowse_aws_balancer.pl --kill \
                           --conf         /etc/gbrowse2/aws_balancer.conf \
                           --access_key   XYZZY \
                           --secret_key   Plugh \
                           --logfile      /var/log/gbrowse2/aws_balancer.log \
                           --pidfile      /var/run/aws_balancer.pid \
                           --user         nobody

Use the init script:

 % sudo /etc/init.d/gbrowse-aws-balancer start
 % sudo /etc/init.d/gbrowse-aws-balancer restart
 % sudo /etc/init.d/gbrowse-aws-balancer stop
 % sudo /etc/init.d/gbrowse-aws-balancer status

=head1 DESCRIPTION

This script launches a process that monitors the load on the local
GBrowse instance. If the load exceeds certain predefined levels, then
it uses Amazon web services to launch one or more spot instances
running render slaves. The work of rendering tracks is then handed off
to these instances, reducing the load on the local instance.

Load balancing is most convenient to run in conjunction with a GBrowse
instance running within the Amazon Web Service EC2 cloud, but it can
also be used to supplement an instance running on local hardware. The
sections below describe the configuration needed for these two
scenarios.

Note that this script requires you to have an Amazon Web Services
account, and for the VM::EC2 Perl module to be installed on the
machine that is running this script.

=head1 COMMAND-LINE OPTIONS

Options can be abbreviated.  For example, you can use -a for
--access_key:

      --access_key   EC2 access key
      --secret_key   EC2 secret key
      --conf         Path to balancer configuration file
      --pidfile      Path to file that holds daemon process ID
      --logfile      Path to file that records log messages
      --user         User to run daemon under (script must be
                         started as root)
      --verbosity    Logging verbosity. 0=least, 3=most.
      --background   Go into the background and run as daemon.
      --kill         Kill a previously-launched daemon. Must provide
                         the same --pidfile argument as used when
                         the daemon was started.

=head1 PREREQUISITES

1. You must have the Perl modules VM::EC2 (v1.21 or later), and
Parse::Apache::ServerStatus installed on the machine you intend to run
the balancer on. The balancer must run on the same machine that
GBrowse is running on. To install these modules, run:

 perl -MCPAN -e 'install VM::EC2; install Parse::Apache::ServerStatus'

2. You must have an account on Amazon Web Services and must be
familiar with using the AWS Console to launch and terminate EC2
instances. If you run GBrowse on local hardware, then you will need to
provide the script with your access key and secret access key when
launching it. It may be safer to create and use an IAM user (Identity
and Access Management) who has more limited privileges. See
L<CONFIGURATION> below for some suggestions.

3. GBrowse must be running under Apache.

4. Apache must be configured to activate the mod_status module and to
allow password-less requests to this module from localhost
(http://httpd.apache.org/docs/2.2/mod/mod_status.html). This is the
recommended configuration:

 <Location /server-status>
    SetHandler server-status
    Order deny,allow
    Deny from all
    Allow from 127.0.0.1 ::1
 </Location>



=head1 ENVIRONMENT VARIABLES

The following environment variables are used if the corresponding
options are not present:

 EC2_ACCESS_KEY     your AWS EC2 access key
 EC2_SECRET_KEY     your AWS EC2 secret key

=head1 SEE ALSO

L<VM::EC2>, L<VM::EC2::Staging::Manager>

=head1 AUTHOR

Lincoln Stein, lincoln.stein@gmail.com

Copyright (c) 2012 Ontario Institute for Cancer Research
                                                                                
This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

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

$ConfFile  ||= File::Spec->catfile(GBrowse::ConfigData->config('conf'),'aws_balancer.conf');

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
    $balancer->stop_daemon();
} else {
    $balancer->run();
}

exit 0;

