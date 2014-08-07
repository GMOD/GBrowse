#!/usr/bin/perl -w

eval 'exec /usr/bin/perl -w -S $0 ${1+"$@"}'
    if 0; # not running under some shell

# A script to prepare alignments for loading into a GBrowse_syn database from
# mercator-generated multiple sequence alignments


# $Id: mercatoraln_to_synhits.pl,v 1.1.2.3 2009-06-02 19:16:15 sheldon_mckay Exp $
use strict;
use Bio::AlignIO;
use List::Util qw/min max/;
use Getopt::Long;

# The name parsing is for mercator.

# The format used in this example is 'fasta' adjust if necessary
use constant OFFSET => 4;
my $aln_name   = 'output.mfa';
my $format     = 'fasta';
my $mapfile    = 'map';
my $genomefile = 'genomes';
my $debug = 0;
my $dir;
GetOptions(
	   'a|aln|i|input:s' => \$aln_name,
	   'v|verbose!' => \$debug,
	   'f|format:s' => \$format,
	   'd|dir:s'    => \$dir,
	   );

$dir = shift @ARGV unless $dir;

unless( -d "$dir" ) {
    die("need a dir provided\n");
}

open(my $genomesfh => "$dir/$genomefile") || die "could not open genomes $genomefile\n";
my @genomes;
while(<$genomesfh>) {
    @genomes = split;
    last;
}
close($genomesfh);
open(my $mapfh => "$dir/$mapfile" ) || die "could not open map $mapfile\n";

while(<$mapfh>) {
    my ($aln_id, @line) = split;
    my $i = 0;
    my $in = Bio::AlignIO->new(-format => $format,
			       -file   => File::Spec->catfile
			       ($dir,$aln_id, $aln_name));
    my $map = {};
    my %seq;
    my $len;

    if( my $aln = $in->next_aln ) {	
	$len = $aln->length;
	for my $seq ( $aln->each_seq ) {
	    $seq{$seq->id} = ['chrom','wholename','start','end','strand',
			      $seq->seq]; 
	}
    }
    for( my $i =0; $i < scalar @genomes; $i++ ) {
	my ($chrom1,$start1,$end1,
	    $strand1) = map { $line[($i * OFFSET) + $_] } 0..3;
	next if $chrom1 eq 'NA';
	($seq{$genomes[$i]}->[0],
	 $seq{$genomes[$i]}->[1],
	 $seq{$genomes[$i]}->[2],
	 $seq{$genomes[$i]}->[3],
	 $seq{$genomes[$i]}->[4]) = ($chrom1,
				     sprintf("%s-%s(%s)/%d-%d",
				     $genomes[$i],
					     $chrom1,$strand1,
					     $start1,$end1),
				     $start1,
				     $end1,
				     $strand1);
	
	for( my $j = 0; $j < scalar @genomes; $j++ ) {
	    next if $i == $j;
	    my ($chrom2,$start2,$end2,
		$strand2) = map { $line[($j * OFFSET) + $_] } 0..3;
	    
	    next if ( $chrom2 eq 'NA' );

	    ($seq{$genomes[$j]}->[0],
	     $seq{$genomes[$j]}->[1],
	     $seq{$genomes[$j]}->[2],
	     $seq{$genomes[$j]}->[3],
	     $seq{$genomes[$j]}->[4]) = ($chrom2,
					 sprintf("%s-%s(%s)/%d-%d",
						 $genomes[$j],
						 $chrom2,$strand2,
						 $start2,$end2),
					 $start2,
					 $end2,
					 $strand2);
	    $seq{$genomes[$j]}->[0] = $chrom2;
	}
    }
    my @species = keys %seq;
    map_coords($seq{$_},$map) for keys %seq;
    my $seq_idx = scalar @species;

    # make all pairwise hits and grid coordinates
    for my $p (map_pairwise(@species)) {
	my ($s1,$s2) = @$p;
	my $array1 = $seq{$s1};
	my $array2 = $seq{$s2};
	$array1->[6] = make_map($array1,$array2,$map);
	$array2->[6] = make_map($array2,$array1,$map);
	make_hit($s1 => $array1, $s2 => $array2);
    }
    
    # progress reporting
    print STDERR ( " Finished alignment $aln_id; length: $len; species: $seq_idx                   \r"); 
    last if $debug;
}


sub make_map {
  my ($s1,$s2,$map) = @_;
  $s1 && $s2 || return [];
  my $seq1 = $s1->[1];
  my $seq2 = $s2->[1];
  my $coord = nearest(100,$s1->[2]);
  $coord += 100 if $coord < $s1->[2];
  my @map;
  
  my $reverse = $s2->[4] ne $s1->[4];
  my $strand2 = $reverse ? 'minus' : 'plus';
  
  while(1) {
    last if $coord >= $s1->[3];
    my $cols = $map->{$seq1}{pmap}{plus}{$coord};
    my $start = min @$cols;
    my $end   = max @$cols;
    $start && $end || die $coord;
    my $coord2 = $start == $end ? int($map->{$seq2}{cmap}{$start}{$strand2}) : int(($map->{$seq2}{cmap}{$start}{$strand2} + $map->{$seq2}{cmap}{$end}{$strand2})/2);
    push @map, ($coord,$coord2);
    $coord += 100;
  }
  
  return \@map;
}


sub map_coords {
  my ($s,$map) = @_;
  my $forward_offset = $s->[2]-1;
  my $reverse_offset = $s->[3];
  my @chars = split '', $s->[5];
  my $cmap  = {};
  my $pmap = {};
  
  for my $col (1..@chars) {
    # forward strand map
    my $gap = $chars[$col-1] eq '-';
    $forward_offset++ unless $gap;
    $cmap->{$col}->{plus} = $forward_offset;
    push @{$pmap->{plus}->{$forward_offset}}, $col;
    # reverse strand map
    $reverse_offset-- unless $gap;
    $cmap->{$col}->{minus} = $reverse_offset;
    push @{$pmap->{minus}->{$reverse_offset}}, $col;
  }
  
  $map->{$s->[1]}{cmap} = $cmap;    
  $map->{$s->[1]}{pmap} = $pmap;
}


sub make_hit {
  my ($s1,$aln1,$s2,$aln2) = @_;
  die "wrong number of keys @$aln1" unless @$aln1 == 7;
  die "wrong number of keys @$aln2" unless @$aln2 == 7;
  my $map1 = $aln1->[6];
  my $map2 = $aln2->[6];

  # not using these yet
  my ($cigar1,$cigar2) = qw/. ./;
  print join("\t",$s1,@{$aln1}[0,2..4],$cigar1,$s2,@{$aln2}[0,2..4],$cigar2,@$map1,'|',@$map2), "\n";
}

sub map_pairwise {
  my @out;
  for my $i (0..$#_) {
    for my $j ($i+1..$#_) {
      push @out, [$_[$i], $_[$j]];
    }
  }
  return @out;
}

# stolen from Math::Round
sub nearest {
  my $targ = abs(shift);
  my $half = 0.50000000000008;
  my @res  = map {
    if ($_ >= 0) { $targ * int(($_ + $half * $targ) / $targ); }
    else { $targ * POSIX::ceil(($_ - $half * $targ) / $targ); }
  } @_;

  return (wantarray) ? @res : $res[0];
}
