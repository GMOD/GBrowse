package Bio::Graphics::Browser2::Render::Slave::AWS_Balancer;

# This module is used to manage GBrowse slaves in an on-demand Amazon EC2
# environment.

use strict;
use Parse::Apache::ServerStatus;
use VM::EC2;
use VM::EC2::Instance::Metadata;
use Parse::Apache::ServerStatus;
use Carp 'croak';

sub new {
    my $class = shift;
    my ($conf_file,$access_key,$secret_key) = @_;
    #setup defaults
    $ENV{EC2_ACCESS_KEY} = $access_key if defined $access_key;
    $ENV{EC2_SECRET_KEY} = $secret_key if defined $secret_key;
    return bless {
	conf_file => $conf_file,
    },ref $class || $class;
}

sub conf_file {shift->{conf_file}}

sub load_table {
    return shift->{'LOAD TABLE'};
}

sub option {
    my $self = shift;
    my ($stanza,$option) = @_;
    return $self->{uc $stanza}{$option};
}

# given load, returns two element list of min_instances, max_instances
sub slaves_wanted {
    my $self = shift;
    my $load = shift;

    my $lt   = $self->load_table or croak 'no load table!';
    my ($min,$max) = (0,0);
    for my $l (sort {$a<=>$b} keys %$lt) {
	($min,$max) = @{$lt->{$l}} if $load >= $l;
    }
    return ($min,$max);
}

sub slave_instance_type { shift->option('SLAVE','instance_type') || 'm1.large' }
sub slave_spot_bid      { shift->option('SLAVE','spot_bid')      || 0.08       }
sub slave_ports         { my $p = shift->option('SLAVE','ports');
			  my @p = split /\s+/,$p;
			  return @p ? @p : (8101); }
sub aws_region          {
    my $self = shift;
    if ($self->running_as_an_instance) {
	my $zone =  $self->{instance_metadata}{availabilityZone}
	$zone    =~ s/[a-z]$//;  #  zone=>region
	return $zone;
    } else {
	return $self->option('SLAVE','region');
    }
}

sub aws_zone {
    my $self = shift;
    if ($self->running_as_an_instance) {
	return $self->{instance_metadata}{availabilityZone};
    } else {
	$self->option('SLAVE','availability_zone');
    }
}

sub aws_image_id {
    my $self = shift;
    if ($self->running_as_an_instance) {
	return $self->{instance_metadata}{imageId};
    } else {
	$self->option('SLAVE','image_id');
    }
}

sub aws_subnet {
    my $self = shift;
    if ($self->running_as_an_instance) {
	return eval {(values %{$meta->interfaces})[0]{subnetId}};
    } else {
	$self->option('SLAVE','subnet');
    }
}

sub aws_security_group {
    my $self = shift;
    my $sg   = $self->option('SLAVE','security_group');
    unless ($sg) {
	my $ec2 = $self->ec2;
	$sg = $ec2->create_security_group(-name  =>  "GBROWSE_SLAVE_$$",
					  -description => 'Temporary security group for slave communications');
	$self->{create_security_group} = $sg;
	$sg->authorize_incoming(-protocol  => 'tcp',
				-port      => $_,
				-source_ip => $self->master_ip) foreach $self->aws_ports;
	$sg->update;
    }
    return $sg;
}

sub initialize {
    my $self = shift;
    $self->_parse_conf_file;
    $self->_parse_instance_metadata;
}

sub _parse_conf_file {
    my $self = shift;
    return if exists $self->{'LOAD TABLE'};
    open my $f,$self->conf_file or croak "Could not open ",$self->conf_file,": $!";
    $self->{pushback} = [];
    while (defined(my $line = $self->_getline($f))) {
	$self->_parse_stanza($1,$f) if $line =~ /^\[([^]]+)\]/;
    }
    close $f;
    croak "invalid config file; must contain [LOAD TABLE] and [SLAVE] stanzas"
	unless exists $self->{'LOAD TABLE'} and exists $self->{'SLAVE'};
}

sub _parse_stanza {
    my $self = shift;
    my ($stanza,$fh) = @_;
    if (uc $stanza eq 'LOAD TABLE') {
	$self->_parse_load_table($fh);
    } else {
	$self->_parse_regular_stanza($stanza,$fh);
    }
}

sub _parse_load_table {
    my $self = shift;
    my $fh   = shift;
    while (my $line = $self->_get_stanza_line($fh)) {
	my @tokens = split /\s+/,$line;
	@tokens    == 3 or croak "invalid load table line: $line";
	my ($load,$min,$max) = @tokens;
	$self->{'LOAD TABLE'}{$load} = [$min,$max];
    } 
}

sub _parse_regular_stanza {
    my $self = shift;
    my ($stanza,$fh) = @_;
    while (my $line = $self->_get_stanza_line($fh)) {
	my ($option,$value) = $line =~ /^(\S+)\s*=\s*(.+)/ or next;
	$self->{options}{uc $stanza}{$option} = $value;
    }
}

sub _get_stanza_line {
    my $self = shift;
    my $fh   = shift;
    my $line = $self->_getline($fh);
    if ($line =~ /^\[/) {
	push @{$self->{pushback}},$line;
	return;
    }
    return $line;
}

sub _getline {
    my $self = shift;
    my $fh   = shift;

    if (@{$self->{pushback}}) {
	return pop @{$self->{pushback}};
    }

    while (1) {
	my $line = <$fh> or return;
	chomp $line;
	$line =~ /^\s*#/ and next;
	$line =~ s/\s+#.*$//;
	$line =~ /\S/    or  next;
	return $line;
    }
}

sub DESTROY {
    my $self = shift;
    if (my $sg = $self->{create_security_group}) {
	$self->ec2->delete_security_group($sg);
    }
}

1;

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2012 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

