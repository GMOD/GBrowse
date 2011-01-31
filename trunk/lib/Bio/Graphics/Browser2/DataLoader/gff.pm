package Bio::Graphics::Browser2::DataLoader::gff;

# $Id: gff3.pm 22257 2009-11-16 15:11:04Z lstein $
use strict;
use base 'Bio::Graphics::Browser2::DataLoader::generic';

sub Loader {
    return 'Bio::DB::SeqFeature::Store::GFF2Loader';
}


1;
