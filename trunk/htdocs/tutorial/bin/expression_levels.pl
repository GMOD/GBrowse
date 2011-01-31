#!/usr/bin/perl

# simulated affy chip
use strict;

# one affy series laid down every 100 bp
use constant SAMPLE_INTERVAL => 100;
use constant GENE_SIZE       => 5000;
use constant GENE_DENSITY    => 5;     # 1 gene every 5 GENE_SIZE intervals
use constant GENOME_SIZE     => 50000;

my $gene_interval = 1;
while ($gene_interval < GENOME_SIZE) {
  my $in_gene = rand(GENE_DENSITY) < 1;
  my $base_intensity = $in_gene ? 800 : 200 ;
  my $gene_size_variance = int(GENE_SIZE/2 - rand(GENE_SIZE/2));
  my $gene_size += $gene_size_variance;
  my $last_end;
  for (my $i = 0; $i < $gene_size; $i += 100) {
    my $score = int $base_intensity + (100-rand(200));
    my $start = $gene_interval + $i;
    my $end   = $start + 99;
    print join ("\t",qw(ctgA affy tlevel),$start,$end,$score,qw(. .),"Affy Expt1"),"\n";
    $last_end = $end;
  }
  # round to nearest 100
  $gene_interval = $last_end+1;
}
