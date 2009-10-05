package Bio::Graphics::Browser2::DataLoader::featurefile;

# $Id: featurefile.pm,v 1.3 2009/08/31 19:46:38 lstein Exp $
use strict;
use base 'Bio::Graphics::Browser2::DataLoader::generic';

sub Loader {
    return 'Bio::DB::SeqFeature::Store::FeatureFileLoader';
}


1;
