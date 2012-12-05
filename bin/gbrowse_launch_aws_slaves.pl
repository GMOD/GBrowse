#!/usr/bin/perl

# Script to launch additional render slaves when running under Amazon AWS
# Will monitor the load level and launch a graded series of spot instances
# to deal with it.
#
# All values are hard-coded as constants during this testing phase
#
# Need following security groups:
# GBrowseMaster
#   allow inbound on 22 from all
#   allow inbound on 80 from all
#
# GBrowseSlave
#   allow inbound on 8101-8105 from GBrowseMaster group
#   (nothing else)
#
# Master server must be configured to allow http://localhost/server-status requests
# from localhost. The "Satisfy any" step ensures that no password will
# be required on this URL.
#
#<Location /server-status>
#    SetHandler server-status
#    Order deny,allow
#    Deny from all
#    Allow from 127.0.0.1
#    Satisfy any
#</Location>
# ExtendedStatus On
#


use strict;
use Getopt::Long;
use Parse::Apache::ServerStatus;
use FindBin '$Bin';
use VM::EC2;
use VM::EC2::Instance::Metadata;
use Parse::Apache::ServerStatus;

$SIG{TERM} = sub {exit 0};
$SIG{INT}  = sub {exit 0};
END {  terminate_instances()  }

# load averages:
# each item represents requests per second, lower and upper bounds
use constant LOAD_TABLE => [
    #load  min  max
    [ 0.01,  0,   1 ],
    [ 0.5,   0,   2 ],
    [ 1.0,   1,   4 ],
    [ 5.0,   3,   6 ],
    [ 10.0,  6,   8 ]
    ];

use constant IMAGE_TYPE       => 'm1.large';
use constant POLL_INTERVAL    => 0.5;  # minutes
use constant SPOT_PRICE       => 0.08;  # dollars/hour
use constant SECURITY_GROUP   => 'GBrowseSlave';
use constant CONFIGURE_SLAVES => "$Bin/gbrowse_configure_slaves.pl";
use constant SERVER_STATUS    => 'http://localhost/server-status';

my($Access_key,$Secret_key);
GetOptions(
	   'access_key=s'  => \$Access_key,
	   'secret_key=s'  => \$Secret_key,
    ) or exec 'perldoc',$0;

#setup defaults
$ENV{EC2_ACCESS_KEY} = $Access_key if defined $Access_key;
$ENV{EC2_SECRET_KEY} = $Secret_key if defined $Secret_key;

my $meta       = VM::EC2::Instance::Metadata->new();
my $imageId    = $meta->imageId;
my $instanceId = $meta->instanceId;
my $zone       = $meta->availabilityZone;
my $subnet     = eval {(values %{$meta->interfaces})[0]{subnetId}};
my $vpcId      = eval {(values %{$meta->interfaces})[0]{vpcId}};
my @groups     = $meta->securityGroups;

die "This instance needs to belong to the GBrowseMaster security group in order for this script to run correctly"
    unless "@groups" =~ /GBrowseMaster/;

warn "slave imageId=$imageId, zone=$zone, subnet=$subnet, vpcId=$vpcId\n";

(my $region = $zone)       =~ s/[a-z]$//;  #  zone=>region
my $ec2     = VM::EC2->new(-region=>$region);

my (@slave_security_groups) = $ec2->describe_security_groups({'group-name' => SECURITY_GROUP});
my $slave_security_group;
if ($vpcId) {
    ($slave_security_group)  = grep {$vpcId eq $_->vpcId} @slave_security_groups; 
} else {
    $slave_security_group = $slave_security_groups[0];
}

$slave_security_group or die "Could not find a security group named ",SECURITY_GROUP," in current region or VPC";

my $pr      = Parse::Apache::ServerStatus->new(url=>SERVER_STATUS);

while (1) { # main loop
    my $load = get_load();
    warn "current load = $load\n";
    my @instances = adjust_spot_requests($load);
    adjust_configuration(@instances);
    sleep (POLL_INTERVAL * 60);
}

terminate_instances();

exit 0;

sub get_load {
    if (-e '/tmp/gbrowse_load') {
	open my $fh,'/tmp/gbrowse_load';
	chomp (my $load = <$fh>);
	return $load;
    }
    my $stats = $pr->get or die $pr->errstr;
    return $stats->{rs};
}

sub adjust_spot_requests {
    my $load = shift;

    # first find out how many spot instances we want to have
    my ($min_instances,$max_instances) = (0,0);
    my $lt = LOAD_TABLE;
    for my $i (@$lt) {
	my ($load_limit,$min,$max) = @$i;
	if ($load > $load_limit) {
	    $min_instances = $min;
	    $max_instances = $max;
	}
    }

    warn "load=$load: min=$min_instances, max=$max_instances\n";

    # count the realized and pending 
    my @spot_requests = $ec2->describe_spot_instance_requests({'tag:Requestor' => 'gbrowse_launch_aws_slaves'});
    my @potential_instances;
    for my $sr (@spot_requests) {
	my $state    = $sr->state;
	my $instance = $sr->instance;
	if ($state eq 'open' or ($instance && $instance->instanceState =~ /running|pending/)) {
	    $instance->add_tag(Name => 'GBrowse Slave')      if $instance;
	    $instance->add_tag(GBrowseMaster => $instanceId) if $instance;  # we'll use this to terminate all slaves sometime later
	    push @potential_instances,$instance || $sr;
	}
    }

    warn "current active and pending spot instances = ",scalar @potential_instances;
    
    # what to do if there are too many spot requests for the current load
    # either cancel spot requests or shut instances down
    while (@potential_instances > $max_instances) {
	my $i = shift @potential_instances;
	if ($i->isa('VM::EC2::Instance')) {
	    warn "terminating $i";
	    $i->terminate();
	} else {
	    warn "cancelling spot request $i";
	    $ec2->cancel_spot_instance_requests($i);
	}
    }

    # what to do if there are too few
    if (@potential_instances < $min_instances) {
	warn "launching a new spot request";
	my @requests = $ec2->request_spot_instances(
	    -image_id             => $imageId,
	    -instance_type        => IMAGE_TYPE,
	    -instance_count       => 1,
	    -security_group_id    => $slave_security_group,
	    -spot_price           => SPOT_PRICE,
	    $subnet? (-subnet_id  => $subnet) : (),
	    -user_data         => "#!/bin/sh\nexec /opt/gbrowse/etc/init.d/gbrowse-slave start",
	    );
	@requests or warn $ec2->error_str;
	$_->add_tag(Requestor=>'gbrowse_launch_aws_slaves') foreach @requests;
	push @potential_instances,@requests;
    }
    return @potential_instances;
}

sub adjust_configuration {
    # this is a heterogeneous list of running instances and spot instance requests
    my @potential_instances = @_;
    warn "adjust_configuration(@potential_instances)";

    my @instances = grep {$_->isa('VM::EC2::Instance')} @potential_instances;
    if (@instances) {
	my @addresses = grep {$_} map  {$_->privateDnsName||$_->privateIpAddress}    @instances;
	return unless @addresses;
	warn "Adding slaves at address @addresses";
	my @a         = map {("http://$_:8101",
			      "http://$_:8102",
			      "http://$_:8103")} @addresses;
	my @args      = map  {('--set'=> "$_") } @a;
	system 'sudo',CONFIGURE_SLAVES,@args;
    } else {
	system 'sudo',CONFIGURE_SLAVES,'--set','';
    }
}

sub terminate_instances {
    $ec2 or return;
    warn "terminating all slave instances";
    my @spot_requests = $ec2->describe_spot_instance_requests({'tag:Requestor' => 'gbrowse_launch_aws_slaves'});
    my @instances     = $ec2->describe_instances({'tag:GBrowseMaster'=>$instanceId});
    my %to_terminate = map {$_=>1} @instances;
    foreach (@spot_requests) {
	$to_terminate{$_->instance}++;
	$ec2->cancel_spot_instance_requests($_);
    }
    my @i = grep {/^i-/} keys %to_terminate;
    warn "instances to terminate = @i";
    $ec2->terminate_instances(@i);
    system 'sudo',CONFIGURE_SLAVES,'--set','';
}

END { terminate_instances() }
