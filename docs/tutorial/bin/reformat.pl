#!/usr/bin/perl

use Bio::SeqIO;
my $in = Bio::SeqIO->newFh(-file=>shift,-format=>'fasta');
my $out = Bio::SeqIO->newFh(-format=>'fasta');
print $out $_ while <$in>;
