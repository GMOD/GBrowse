package Bio::Graphics::Browser2::DataLoader::gff3;

# $Id$
use strict;
use base 'Bio::Graphics::Browser2::DataLoader::generic';

sub Loader {
    return 'Bio::DB::SeqFeature::Store::GFF3Loader';
}


1;
