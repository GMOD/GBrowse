package Bio::Graphics::GBrowseFeature;

# $Id: GBrowseFeature.pm,v 1.1 2008-10-11 00:02:43 lstein Exp $
# add gbrowse_dbid() method to Bio::Graphics::Feature;

use strict;
use warnings;
use base 'Bio::Graphics::Feature';

sub gbrowse_dbid {
    my $self = shift;
    my $d    = $self->{__gbrowse_dbid};
    $self->{__gbrowse_dbid} = shift if @_;
    $d;
}

1;

