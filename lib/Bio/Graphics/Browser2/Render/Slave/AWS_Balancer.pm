package Bio::Graphics::Browser2::Render::Slave::AWS_Balancer;

# This module is used to manage GBrowse slaves in an on-demand Amazon EC2
# environment.

use strict;
use Parse::Apache::ServerStatus;
use VM::EC2;
use VM::EC2::Instance::Metadata;
use Parse::Apache::ServerStatus;


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



=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2012 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

