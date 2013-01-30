#!/usr/bin/perl 

=head1 NAME

gbrowse_grow_cloud-vol.pl     Grow the GBrowse volume by the requested amount

=head1 SYNOPSYS

Grow /opt/gbrowse by another 100 gigabytes

  % gbrowse_grow_cloud_vol.pl 100

=head1 DESCRIPTION

This script grows /opt/gbrowse by the requested number of
gigabytes. The single argument must be a number between 1 and 1000,
which indicates the number of GB to grow the volume by (not the new
size of the volume).

It works by creating a new EBS volume and adding it to the logical
volume manager (LVM2) for this machine. The filesystem is then
extended to the desired size.

=head1 COMMAND-LINE OPTIONS

Options can be abbreviated.  For example, you can use -a for
--access_key:

      --access_key   EC2 access key
      --secret_key   EC2 secret key

=head1 ENVIRONMENT VARIABLES

The following environment variables are used if the corresponding
options are not present:

 EC2_ACCESS_KEY     your access key
 EC2_SECRET_KEY     your secret key

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
use lib '../lib';

use VM::EC2;
use File::Basename 'basename';
use Getopt::Long;

my($Access_key,$Secret_key,$Endpoint);
my $Program_name = basename($0);

GetOptions(
	   'access_key=s'  => \$Access_key,
	   'secret_key=s'  => \$Secret_key,
    ) or exec 'perldoc',$0;

my $extra_size = shift or die "Please provide size to grow /opt/gbrowse by. Use --help for details.";

#setup defaults
$ENV{EC2_ACCESS_KEY} = $Access_key if defined $Access_key;
$ENV{EC2_SECRET_KEY} = $Secret_key if defined $Secret_key;

my $meta     = VM::EC2->instance_metadata;
my $zone     = $meta->availabilityZone;
(my $region  = $zone) =~ s/[a-z]$//;  # hack
my $instance = $meta->instanceId;
my ($ebs_device,$local_device)   = unused_block_device() or die "Couldn't find a suitable device to attach to";

my $ec2 = VM::EC2->new(-region=>$region)                 or die VM::EC2->error_str;

print STDERR "Creating $extra_size EBS volume.\n";
my $vol = $ec2->create_volume(-availability_zone => $zone,
			      -size              => $extra_size) or die "Couldn't create EBS volume: ",$ec2->error_str;
$vol->add_tag(Name=>"GBrowse lvm disk $local_device");

print STDERR "Attaching volume.\n";
my $a = $vol->attach($instance=>$ebs_device)                     or die "Couldn't attach EBS volume to $ebs_device: ",$ec2->error_str;
$ec2->wait_for_attachments($a);
$a->deleteOnTermination(1);
-e $local_device                                                 or die "EBS volume did not appear at $local_device as expected";

print STDERR "Creating lvm physical device.\n";
system("sudo pvcreate $local_device")         == 0               or die "pvcreate failed";

print STDERR "Extending 'volumes' volume group.\n";
system("sudo vgextend volumes $local_device") == 0               or die "vgextend failed";

my $result = `sudo vgdisplay -c volumes`                         or die "vgdisplay filed";
my @result = split /:/,$result;
my $free   = $result[15]                                         or die "volume group has no free extents";

print STDERR "Extending 'gbrowse' logical volume.\n";
system("sudo lvextend -l +$free /dev/volumes/gbrowse") == 0       or die "lvextend failed";

print STDERR "Extending /opt/gbrowse filesystem.\n";
system("sudo resize2fs /dev/volumes/gbrowse")         == 0               or die "resize2fs failed";

print STDERR "Volume resized successfully\n";

exit 0;

sub unused_block_device {
    my $major_start = shift || 'g';

    my @devices = `ls -1 /dev/sd?* /dev/xvd?* 2>/dev/null`;
    chomp(@devices);
    return unless @devices;
    my %used = map {$_ => 1} @devices;
    
    my $base =   $used{'/dev/sda1'}   ? "/dev/sd"
	: $used{'/dev/xvda1'}  ? "/dev/xvd"
	: '';
    die "Device list contains neither /dev/sda1 nor /dev/xvda1; don't know how blocks are named on this system"
        unless $base;

    my $ebs = '/dev/sd';
    for my $major ($major_start..'p') {
        for my $minor (1..15) {
            my $local_device = "${base}${major}${minor}";
            next if $used{$local_device}++;
            my $ebs_device = "/dev/sd${major}${minor}";
            return ($ebs_device,$local_device);
        }
    }
    return;
}
