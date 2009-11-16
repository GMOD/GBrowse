package Bio::Graphics::Browser2::DataLoader::featurefile;

# $Id$
use strict;
use base 'Bio::Graphics::Browser2::DataLoader::generic';

sub Loader {
    return 'Bio::DB::SeqFeature::Store::FeatureFileLoader';
}

sub do_fast {0}


1;
