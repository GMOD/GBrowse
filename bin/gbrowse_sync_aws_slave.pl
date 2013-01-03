#!/usr/bin/perl

=head1 NAME

gbrowse_sync_aws_slave.pl  Synchronize local file system to GBrowse slave volume.

=head1 SYNOPSIS

 % sudo gbrowse_sync_aws_script.pl --conf     /etc/gbrowse2/aws_balancer.conf \
                                   --mysql    /var/lib/mysql \
                                   --postgres /var/lib/postgresql

 syncing data....done
 data stored in snapshot(s) snap-12345
 updated conf file, previous version in /etc/gbrowse2/aws_balancer.conf.bak

=head1 ENVIRONMENT VARIABLES

The following environment variables are used if the corresponding
command line options are not present:

 EC2_ACCESS_KEY AWS EC2 access key EC2_SECRET_KEY AWS EC2 secret key

=head1 SEE ALSO

L<VM::EC2>, L<VM::EC2::Staging::Manager>

=head1 AUTHOR

Lincoln Stein, lincoln.stein@gmail.com

Copyright (c) 2013 Ontario Institute for Cancer Research
                                                                                
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

use constant GB => 1_073_741_824;

my $balancer;

# this obscures the AWS secrets from ps; it is not 100% effective
($0 = "$0 @ARGV") =~ s/(\s--?[as]\S*?)(=|\s+)\S+/$1$2xxxxxxxxxx/g;

$SIG{TERM} = sub {exit 0};
$SIG{INT}  = sub {exit 0};

my($ConfFile,$AccessKey,$SecretKey,$MySqlPath,$PostGresPath,$Verbosity);
GetOptions(
	   'access_key=s'  => \$AccessKey,
	   'secret_key=s'  => \$SecretKey,
	   'conf=s'        => \$ConfFile,
	   'mysql=s'       => \$MySqlPath,
	   'postgres=s'    => \$PostGresPath,
           'verbosity=i'   => \$Verbosity,
    ) or exec 'perldoc',$0;

$ConfFile  ||= File::Spec->catfile(GBrowse::ConfigData->config('conf'),'aws_balancer.conf');
$balancer = Bio::Graphics::Browser2::Render::Slave::AWS_Balancer->new(
    -conf       => $ConfFile,
    -access_key => $AccessKey||'',
    -secret_key => $SecretKey||'',
    );

$Verbosity = 3 unless defined $Verbosity;
$balancer->verbosity($Verbosity);

# run the remote staging server
my $slave = $balancer->launch_staging_slave();

# figure out total size needed on destination volume
my $DataBasePath = GBrowse::ConfigData->config('databases');

my $gig_needed = tally_sizes($DataBasePath,$MySqlPath,$PostGresPath);  # keep an extra 10 G free
my $gig_have   = $slave->volume_size;
if ($gig_needed < $gig_have) {
    $gig_needed = $gig_have + 10;  # grow by 10 G increments
    $slave->grow_volume($gig_needed);
}
$slave->put("$DataBasePath/",'/opt/gbrowse2/databases');
$slave->put("$MySqlPath/",'/opt/gbrowse2/databases')    if $MySqlPath;
$slave->put("$PostGresPath",'/opt/gbrowse2/databases')  if $PostGresPath;
my @snapshots = $slave->snapshot_gbrowse_volumes;
$slave->write_new_snapshot_conf(@snapshots);
$slave->terminate;

exit 0;

sub tally_sizes {
    my @dirs  = @_;
    my $out   = `sudo du -sc @dirs`;
    my $bytes = $out=~/^(\d+)\s+total/;
    return int(0.5+$bytes/GB);
}

__END__
