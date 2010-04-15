#!/usr/bin/perl -w

# A script to prepare alignments for loading into a GBrowse_syn database from
# mercator-generated multiple sequence alignments


# $Id: mercatoraln_to_synhits.pl,v 1.1.2.3 2009-06-02 19:16:15 sheldon_mckay Exp $
use strict;
use Bio::AlignIO;
use List::Util qw/min max sum/;
use Getopt::Long;

# coordinate mapping resolution is 100bp
# by default.  This keeps track of indels
use constant MAPRES   => 100;

# The name parsing is for mercator.

# The format used in this example is 'fasta' adjust if necessary
use constant OFFSET => 4;
my $aln_name   = 'output.mfa';
my $format     = 'fasta';
my $mapfile    = 'map';
my $genomefile = 'genomes';
my $debug = 0;
my $dir;
my $mapres;
my %map;

GetOptions(
	   'a|aln|i|input:s' => \$aln_name,
	   'v|verbose!' => \$debug,
	   'f|format:s' => \$format,
	   'd|dir:s'    => \$dir,
           'm|map:i'    => \$mapres
	   );

$mapres ||= MAPRES;

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
			      $seq->seq, $seq]; 
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

        my $seq1 = $seq{$genomes[$i]}->[6];
	$seq1->strand($strand1 eq '+' ? +1 : -1);
	$seq1->start($start1);
	$seq1->end($end1 - 1);
	
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
	    my $seq2 = $seq{$genomes[$j]}->[6];
	    $seq2->strand($strand2 eq '+' ? +1 : -1);
	    $seq2->start($start2);
	    $seq2->end($end2 - 1);
	  }
      }

    my @species = keys %seq;
    #map_coords($seq{$_},$map) for keys %seq;
    my $seq_idx = scalar @species;

    # make all pairwise hits and grid coordinates
    for my $p (map_pairwise(@species)) {
	my ($s1,$s2) = @$p;
	my $array1 = $seq{$s1};
	my $array2 = $seq{$s2};
	my $seq1   = $array1->[6];
	my $seq2   = $array2->[6];
	$array1->[7] = make_map($seq1,$seq2,$map);
	$array2->[7] = make_map($seq2,$seq1,$map);
	make_hit($s1 => $array1, $s2 => $array2);
    }
    
    # progress reporting
    warn( " Finished alignment $aln_id; length: $len; species: $seq_idx                   \n"); 
   last if $debug;
}


sub make_hit {
  my ($s1,$aln1,$s2,$aln2) = @_;
  die "wrong number of keys @$aln1" unless @$aln1 == 8;
  die "wrong number of keys @$aln2" unless @$aln2 == 8;
  my $map1 = $aln1->[7];
  my $map2 = $aln2->[7];

  # not using these yet
  my ($cigar1,$cigar2) = qw/. ./;
  print join("\t",$s1,@{$aln1}[0,2..4],$cigar1,$s2,@{$aln2}[0,2..4],$cigar2,@$map1,'|',@$map2), "\n";
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

# Make coordinate maps at the specified resolution
sub make_map {
  my ($s1,$s2,$map) = @_;
  $s1 && $s2 || return {};
  unless (UNIVERSAL::can($s1,'isa')) {
    #warn "WTF? $s1 $s2\n" and next;
    warn Dumper $s1, $s2;
  }
  
  column_to_residue_number($s1,$s2);
  my $coord = nearest($mapres,$s1->start);
  $coord += $mapres if $coord < $s1->start;
  my @map;
  
  my $reverse = $s1->strand ne $s2->strand;
 
  # have to get the column number from residue position, then
  # the matching residue num from the column number 
  while ($coord < $s1->end) {
    my $col     = column_from_residue_number($s1,$coord);
    my $coord2  = residue_from_column_number($s2,$col) if $col;
    push @map, ($coord,$coord2) if $coord2;
    $coord += $mapres;
  }
  return \@map;
}

sub column_to_residue_number {
  for my $seq (@_) {
    my $str = $seq->seq;
    my $id  = $seq->id;
    next if $map{$id};
    my $rev = $seq->strand < 0;
    my $res = $rev ? $seq->end - 1 : $seq->start + 1;
    my @cols = split '', $str;
    
    my $pos;
    my $col;
    for my $chr (@cols) {
      unless ($chr eq '-') {
	$rev ? $res-- : $res++;
      }

      $col++;
      $map{$id}{col}{$col} = $res;
      $map{$id}{res}{$res} ||= $col;
    }
  }
}

sub column_from_residue_number {
  my ($seq, $res) = @_;
  my $id = $seq->id;
  return $map{$id}{res}{$res};  
}

sub residue_from_column_number {
  my ($seq, $col) = @_;
  my $id = $seq->id;
  print"WTF? $seq $id $col\n" unless $id &&$col;
  return $map{$id}{col}{$col};
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
