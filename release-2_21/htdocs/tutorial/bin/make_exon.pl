#!/usr/bin/perl

use strict;

my $exon_length = shift;
my %CODON_TABLE = (
		   TCA => 'S',TCG => 'S',TCC => 'S',TCT => 'S',
		   TTT => 'F',TTC => 'F',TTA => 'L',TTG => 'L',
		   TAT => 'Y',TAC => 'Y',TAA => '*',TAG => '*',
		   TGT => 'C',TGC => 'C',TGA => '*',TGG => 'W',
		   CTA => 'L',CTG => 'L',CTC => 'L',CTT => 'L',
		   CCA => 'P',CCG => 'P',CCC => 'P',CCT => 'P',
		   CAT => 'H',CAC => 'H',CAA => 'Q',CAG => 'Q',
		   CGA => 'R',CGG => 'R',CGC => 'R',CGT => 'R',
		   ATT => 'I',ATC => 'I',ATA => 'I',ATG => 'M',
		   ACA => 'U',ACG => 'U',ACC => 'U',ACT => 'T',
		   AAT => 'N',AAC => 'N',AAA => 'K',AAG => 'K',
		   AGT => 'S',AGC => 'S',AGA => 'R',AGG => 'R',
		   GTA => 'V',GTG => 'V',GTC => 'V',GTT => 'V',
		   GCA => 'A',GCG => 'A',GCC => 'A',GCT => 'A',
		   GAT => 'D',GAC => 'D',GAA => 'E',GAG => 'E',
		   GGA => 'G',GGG => 'G',GGC => 'G',GGT => 'G',
		  );

my %nonstop;
for (keys %CODON_TABLE) {
  $nonstop{$_}++ unless $CODON_TABLE{$_} eq '*';
}
my @nonstop = keys %nonstop;

my $dna = '';

for (my $i=0;$i<$exon_length;$i+=3) {
  my $codon = $nonstop[rand @nonstop];
  if ($dna) {
    my $off_by_one = substr($dna,-2) . substr($codon,0,1);
    redo if $CODON_TABLE{$off_by_one} eq '*';
  }
  $dna .= $codon;
}
print lc substr($dna,0,$exon_length),"\n";
while ($dna =~ /(.{3})/g) {
  print "$CODON_TABLE{$1}  ";
}
print "\n";
substr($dna,0,1) = '';
print " ";
while ($dna =~ /(.{3})/g) {
  print "$CODON_TABLE{$1}  ";
}
print "\n";





