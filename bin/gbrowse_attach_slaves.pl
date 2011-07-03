#!/usr/bin/perl
use strict;

use Term::ReadLine;

use constant RENDERFARM_CONF         => '/srv/gbrowse/etc/renderfarm.conf';
use constant IMAGE_MAP               => '/srv/gbrowse/etc/ami_map.txt';
use constant SLAVE_SECURITY_GROUP    => 'GBrowseSlave';
use constant MASTER_SECURITY_GROUP   => 'GBrowseMaster';
use constant PORT_RANGE              => '8101-8103';

# This is called on the master to launch instances.
# It discovers which species are mounted
# on the current instance, snapshots them, and
# attaches them to the slave(s).
# EC2_ACCESS_KEY and EC2_SECRET_KEY must be defined

$ENV{PYTHONPATH}='/usr/local/lib/python2.6/dist-packages';

if ($ARGV[0] =~ /^--?h/) {
    die <<END;
Usage: gbrowse_attach_slaves.pl [number of slaves]

For use with the Amazon GBrowse image.
Launch indicated number of gbrowse slaves and attach the current set of
mounted data directories to them. Relaunch server in render slave mode.
END
}

my $TERM;
check_eucarc();

my $SLAVE_COUNT = shift || 1;

my @mounts       = get_species_mounts();
my $snapshot_map = get_snapshot_map(\@mounts);
my $ami_map      = get_ami_map();

# set up the block devices that need to be attached
my @devices = map {"/dev/sd$_"} ('h'..'z');
my $i = 0;
my @block_args    = ('-b','/dev/sdg=:0:true',map {
    my $device    = $devices[$i++];
    my $species   = $_->[1];
    my $snapshot  = $snapshot_map->{$species};
    $snapshot ? ('-b',"${device}=${snapshot}:0:true") : ();  # all these volumes are terminate-on-delete
} @mounts);

my $ami      = $ami_map->{GBROWSE_SLAVE} or die "Couldn't look up current AMI for the slave";
my $key      = get_keypair();
my $security = get_security_group();

my @command = ('euca-run-instances','-k',$key,'-g',$security,@block_args,'-t','t1.micro','-n',$SLAVE_COUNT,$ami);

# now get the IP addresses of these instances
my @instances;
open OUTPUT,'-|' or exec @command;
while (<OUTPUT>) {
    chomp;
    next unless /^INSTANCE\s+(\S+)/;
    push @instances,$1;
}
close OUTPUT;

my %ips;
while (keys %ips < $SLAVE_COUNT) {
    print STDERR "waiting for instance to start....\n";
    sleep 5;
    chomp (my $output = `euca-describe-instances @instances`);
    for my $line (split "\n",$output) {
	next unless $line =~ /^INSTANCE/;
	my @fields = split "\t",$line;
	$ips{$fields[4]}++ if $fields[4];
    }
}

open F,'>',RENDERFARM_CONF or die "Can't write ",RENDERFARM_CONF,": $!";
print F "renderfarm = 1\n";
print F "remote renderer =\n";
my ($low,$hi) = split /-/,PORT_RANGE;
foreach my $ip ('localhost',keys %ips) {
    my $slaves = join ' ',map {"http://${ip}:$_"} ($low..$hi);
    print F " $slaves\n";
}
close F;

system "sudo /etc/init.d/apache2 restart";
exit 0;

sub get_snapshot_map {
    my $mounts = shift;
    my (%vol2snap,%mount2vol,%map);

    print STDERR "Identifying slave AMI...\n";

    chomp (my $instance = `curl -s http://169.254.169.254/latest/meta-data/instance-id`);
    chomp (my $volumes  = `euca-describe-volumes`);

    # get volume and snapshot id for each mounted volume
    for my $line (split "\n",$volumes) {
	if ($line =~ /^VOLUME/) {
	    my ($vol,$snap) = (split /\t/,$line)[1,3];
	    $vol2snap{$vol} = $snap;
	} elsif ($line =~ /^ATTACHMENT/) {
	    next unless $line =~ /\s$instance\s/;
	    my ($vol,$mount) = (split /\t/,$line)[1,3];
	    $mount2vol{$mount} = $vol;
	}
    }

    for my $m (@$mounts) {
	my ($device,$species) = @$m;
	$device =~ s/\d+$//;
	my $vol  = $mount2vol{$device} or next;
	my $snap = $vol2snap{$vol};
	$snap  ||= make_snap($vol);
	$map{$species} = $snap;
    }

    return \%map;
}

sub make_snap {
    die "make_snap() unimplemented";
}

sub get_species_mounts {
    print STDERR "Determining which volumes to mount...\n";
    my @mounts;
    open F,'/proc/mounts' or die "Can't open /proc/mounts: $!";
    while (<F>) {
	chomp;
	my ($dev,$mount_point,@etc) = split /\s+/;
	next unless $mount_point =~ m!/srv/gbrowse/species/([^/]+)!;
	push @mounts,[$dev,$1];
    }
    close F;
    return @mounts;
}

sub get_ami_map {
    my %map;
    open F,IMAGE_MAP or die "Can't open ",IMAGE_MAP,": $!";
    while (<F>) {
	chomp;
	next if /^#/;
	my ($role,$ami) = split /\s+/;
	$map{$role} = $ami;
    }
    close F;
    return \%map;
}

sub get_keypair {
    my $out = `curl -s http://169.254.169.254/latest/meta-data/public-keys/`;
    my ($keyname) = $out =~ /0=(.+)/;
    return $keyname;
}

sub get_security_group {
    print STDERR <<END;
Creating appropriate security group...
If you see duplication warnings, it is because there are already (possibly inactive)
slave instances defined for this master. This will not adversely affect the new slaves,
but you may wish to terminate the old ones to recover storage space.
END

    my $ssg        = SLAVE_SECURITY_GROUP;
    my $range      = PORT_RANGE;
    chomp (my $ip = `curl -s http://169.254.169.254/latest/meta-data/local-ipv4/`);
    chomp (my $instance = `curl -s http://169.254.169.254/latest/meta-data/instance-id`);
    $ssg   .= "-$instance";
    chomp (my $result   = `euca-delete-group $ssg`);
    chomp ($result = `euca-add-group -d'security group for gbrowse render slaves allows ssh and ports $range' $ssg`);
    warn   $result unless $result =~ /^GROUP/;
    chomp ($result = `euca-authorize -P tcp -p 22 -s $ip/32 $ssg`);	
    warn   $result unless $result =~ /PERMISSION/;
    chomp ($result = `euca-authorize -P tcp -p $range -s $ip/32 $ssg`);
    warn   $result unless $result =~ /PERMISSION/;
    return $ssg;
}

sub check_eucarc {
    if (-r "$ENV{HOME}/.eucarc") {
	open my $f,"$ENV{HOME}/.eucarc" or die "~/.eucarc: $!";
	while (<$f>) {
	    chomp;
	    my ($key,$value) = /^(EC2\w+)\s*=\s*(.+)/ or next;
	    $ENV{$key}=$value;
	}
    }

    $ENV{EC2_URL}        ||= get_ec2_url();
    $ENV{EC2_ACCESS_KEY} ||= get_access_key();
    $ENV{EC2_SECRET_KEY} ||= get_secret_key();
}

sub get_ec2_url {
    chomp (my $zone = `curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`);
    chop $zone;  # remove trailing 'a','b'...
    return "http://ec2.$zone.amazonaws.com";
}

sub get_access_key {
    print STDERR "\n";
    print STDERR "I need your EC2 access key id. You can find this under \"Security Credentials\" on your Amazon account page.\n";
    print STDERR "To avoid this prompt in the future, create a ~/.eucarc file containing the line EC2_ACCESS_KEY=<access key>\n";
    return prompt ('EC2_ACCESS_KEY:');
}

sub get_secret_key {
    print STDERR "\n";
    print STDERR "I need your EC2 secret key. You can find this under \"Security Credentials\" on your Amazon account page.\n";
    print STDERR "To avoid this prompt in the future, create a ~/.eucarc file containing the line EC2_SECRET_KEY=<access key>\n";
    return prompt ('EC2_SECRET_KEY:');
}

sub prompt {
    my $prompt = shift;
    $TERM ||= Term::ReadLine->new('gbrowse_attach_slaves.pl');
    return $TERM->readline($prompt);
}
