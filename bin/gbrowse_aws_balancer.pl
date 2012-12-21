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

Synchronize the master with the slave image:

 % sudo gbrowse_sync_aws_slave.pl -c /etc/gbrowse2/aws_balancer.conf
 syncing data....done
 data stored in snapshot(s) snap-12345
 updated conf file, previous version in /etc/gbrowse2/aws_balancer.conf.bak

=head1 DESCRIPTION

This script launches a process that monitors the load on the local
GBrowse instance. If the load exceeds certain predefined levels, then
it uses Amazon web services to launch one or more GBrowse slave
instances.  The work of rendering tracks is then handed off to these
instances, reducing the load on the local instance. Slave instances
are implemented using Amazon's spot instance mechanism, which allows
you to run EC2 instances at a fraction of the price of a standard
on-demand instance.

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

4. Apache must be configured to enable the mod_status module and to
allow password-less requests to this module from localhost
(http://httpd.apache.org/docs/2.2/mod/mod_status.html). This is the
recommended configuration:

 <Location /server-status>
    SetHandler server-status
    Order deny,allow
    Deny from all
    Allow from 127.0.0.1 ::1
 </Location>

5. If you are running GBrowse on local hardware, the local hardware
must be connected to the Internet or have a Virtual Private Cloud
(VPC) connection to Amazon.

=head1 THE CONFIGURATION FILE

The balancer requires a configuration file, ordinarily named
aws_balancer.conf and located in the GBrowse configuration directory
(e.g. /etc/gbrowse2). The configuration file has three sections:

=head2 [LOAD TABLE]

This section describes the number of slave instances to launch for
different load levels. It consists of a three-column space-delimited
table with the following columns:

 <requests/sec>    <min instances>    <max instances>

For example, the first few rows of the default table reads:

 0.1     0   1
 0.5     0   2
 1.0     1   3
 2.0     2   4

This is read as meaning that when the number of requests per second on
the GBrowse server is greater than 0.1 but less than 0.5, run at least
0 slave servers but no more than 1 slave server. When the number of
requests is between 0.5 and 1.0, run between 0 and 2 slave
instances. When the rate is between 1.0 and 2.0, run at least 1 slave
instance, but no more than 3. Load levels below the lowest value on
the table (0.1 in this case) will run no slave servers, while levels
above the highest value on the table (2.0) will launch the minimum and
maximum number of slaves for that load value (between 2 and 4 in this
case).

The reason for having a range of instance counts for each load range
is to avoid unecessarily launching and killing slaves repeatedly when
the load fluctuates around the boundary. You may wish to tune the
values in this table to maximize the performance of your GBrowse
installation.

Note that the server load includes both GBrowse requests and all other
requests on the web server. If this is a problem, you may wish to run
GBrowse on a separate Apache port or virtual host.

=head2 [MASTER]

The options in this sections configure the master GBrowse
instance. Three options are recognized:

=over 4

=item external_ip (optional)

This controls the externally-visible IP address of the GBrowse master,
which is needed by the firewall rule for master/slave
communications. This option can usually be left blank: when the master
is running on EC2, then the IP address is known; when the master is
running on a local machine, the externally-visible IP address is
looked up using a web service. It is only in the rare case that this
lookup is incorrect that you will need to configure this option
yourself.

The external IP that the balancer script finds can be seen in a log
message when verbosity is 2 or higher.

=item poll_interval (required)

This is the interval, in minutes, that the balancer script will
periodically check the Apache load and adjust the number of slave
instances. The suggested value is 0.5 (30s intervals).

=item server_status_url (required)

This is the URL to call to fetch the server load from Apache's
server_status module.

=back
 
=head2 [SLAVE]

The options in this section apply to the render slaves launched by the
balancer.

=over 4

=item instance_type (required)

This is the EC2 instance type. Faster instances give better
performance. High-IO instances give the best performance, but cost
more.

=item spot_bid (required)

This is the maximum, in US dollars, that you are willing to pay per
hour to run a slave spot instance. Typically you will pay less than
the bid price. If the spot price increases beyond the maximum bid,
then the spot instances will be terminated and the balancer will wait
until the spot price decreases below the maximum bid before launching
additional slaves.

=item ports (required)

This is a space-delimited list of TCP port numbers on which the render
slaves should listen for incoming render requests from the
master. Generally it is only necessary to listen on a single port;
multiple ports were supported for performance reasons in earlier
single-threaded versions of the slave.

=item region (required for local masters)

The Amazon region in which to launch slaves. When the master is
running in EC2, this is automatically chosen to be the same as the
master's region and can be left blank.

=item image_id (required for local masters)

This is the ID of the AMI that will be used to launch slaves. The
correct value will be filled in when you run the
gbrowse_sync_aws_slave.pl. You can leave this value blank if the
GBrowse master is being run within an EC2 instance, in which case the
slave will be launched using the same AMI that was used to launch the
master.

=item data_snapshots (required for local masters)

Before launching the slave, attach EBS volumes created from one or
more volume snapshots listed in this option. Multiple snapshots can be
attached by providing a space-delimited list:

 data_snapshots = snap-12345 snap-abcdef

The gbrowse_sync_aws_slave.pl script will automatically maintain this
option for you.

=item availability_zone (optional)

This option will force the slave into the named availability zone. If
not specified, an availability zone in the current region will be
chosen at random.

=item subnet (optional)

If you are in a VPC environment, then this option will force the slave
into the named subnet. Ordinarily the balancer script will launch
slaves into non-VPC instances if the master is running on local
hardware or a non-VPC EC2 instance. The balancer will launch slaves
into the same VPC subnet as the master if the master is running on a
VPC instance.

=item security_group (optional)

This specifies the security group to assign the slaves to. If not
specified, a properly-configured security group will be created as
needed and destroyed when the balancer script exits. If you choose to
manage the security group manually, be sure to configure the firewall
ingress rule to allow access to the slave port(s) (see the "ports"
option) from the master's group or IP address.

=back

=head1 CONFIGURING AWS CREDENTIALS

To work, the balancer script must be able to make spot instance
requests and to monitor and terminate instances. To perform these
operations the script must have access to the appropriate AWS
credentials (access key and secret key). You may provide these
credentials in any one of three ways:

=over 4

=item 1. Your personal EC2 credentials

You may provide the balancer script with --access_key and --secret_key
command line arguments using your personal EC2 credentials. This is
the simplest method, but has the risk that if the credentials are
intercepted by a malicious third party, he or she gains access to all
your EC2 resources.

=item 2. The credentials of a restricted IAM account

You may use the Amazon AWS console to create an IAM (Identity Access
and Management) user with restricted permissions, and provide that
user's credentials to script with the --access_key and --secret_key
arguments. The following IAM permission policy is the minimum needed
for the balancer script to work properly:

 {
  "Statement": [
    {
      "Sid": "BalancerPolicy",
      "Action": [
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSpotInstanceRequests",
        "ec2:RequestSpotInstances",
        "ec2:TerminateInstances"
      ],
      "Effect": "Allow",
      "Resource": [
        "*"
      ]
    }
  ]
 }

=item 3. Create an IAM role

This method works only for 

=back

=head1 ENVIRONMENT VARIABLES

The following environment variables are used if the corresponding
options are not present:

 EC2_ACCESS_KEY     AWS EC2 access key
 EC2_SECRET_KEY     AWS EC2 secret key

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

