#!/usr/bin/perl -w

# A script to prepare alignments for loading into a GBrowse_syn database and 
# map actual sequence coordinates to keep track on insertions/deletions
# $Id: aln2hit.pl,v 1.1.2.3 2009-07-19 09:11:34 sheldon_mckay Exp $
use strict;
use lib "$ENV{HOME}/lib";;
use Bio::AlignIO;
use List::Util 'sum';
use Getopt::Long;
use Data::Dumper;
use File::Temp 'tempfile';
use IO::File;

# The sequence naming convention used here is as follows:
# species-seqname(strand)/start-end
# The species, strand and coordinates of each sequence in the alignment
# must be provided for the database to be loaded properly.

# Sorry for the ad-hoc overloading of the sequence name -- Have
# to get the strand and coordinate info for this to work

# The format used in this example is 'clustalw'
# adjust as required
use constant FORMAT => 'clustalw';
use constant DEBUG  => 0;

use vars qw/$format $infile $outfile/;

GetOptions(
	   'format=s'    => \$format,
	   'infile=s'    => \$infile
	   );

$infile or die "Usage: aln2hit.pl -i infile [-f format]\n\n";

my $verbose = DEBUG;
$format ||= FORMAT;


my $alignIO = Bio::AlignIO->new( -file   => $infile, 
				 -format => $format);

while (my $aln = $alignIO->next_aln) {
  next if $aln->num_sequences < 2;
  my %seq;
  my $map = {};
  for my $seq ($aln->each_seq) {
    my $seqid = $seq->display_name;
    check_name_format($seqid);
    my ($species,$ref,$strand) = $seqid =~ /(\S+)-(\S+)\(([+-])\)/;
    next if $seq->seq =~ /^-+$/;
    $seq{$species} = [$ref, $seq->display_name, $seq->start, $seq->end, $strand, $seq->seq, $seq]; 
  }
  
  map_coords($seq{$_},$map) for keys %seq;
  
  # make all pairwise hits and grid coordinates
  my @species = keys %seq;

  for my $p (map_pairwise(@species)) {
    my ($s1,$s2) = @$p;
    my $array1 = $seq{$s1};
    my $array2 = $seq{$s2};
    $array1->[6] = make_map($array1,$array2,$map);
    $array2->[6] = make_map($array2,$array1,$map);
    make_hit($s1 => $array1, $s2 => $array2);
  }
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
    my $col = $map->{$seq1}{pmap}{plus}{$coord};
    my $coord2  = $map->{$seq2}{cmap}{$col}{$strand2};
    push @map, ($coord,$coord2) if $coord2;
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
  
  # position maps to middle of gap if gaps are present
  for my $coord (keys %{$pmap->{minus}}) {
      my $ary = $pmap->{minus}->{$coord};
      if (@$ary == 1) {
	  $ary = @$ary[0];
      }
      else {
	  # round down mean
	  $ary = int((sum(@$ary)/@$ary));
      }
      $pmap->{minus}->{$coord} = $ary;
  }
  for my $coord (keys %{$pmap->{plus}}) {
      my $ary = $pmap->{plus}->{$coord};
      if (@$ary == 1) {
          $ary = @$ary[0];
      }
      else {
          # round up mean
          $ary = int((sum(@$ary)/@$ary)+0.5);
      }
      $pmap->{plus}->{$coord} = $ary;
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

sub check_name_format {
  my $name = shift;
  my $nogood = <<'  END';
I\'m sorry, this will not work unless you use the name format described below for each
sequence in the alignment.  WE need the species, sequence name, strand, start and end for
each sequence in the alignment.

  species-sequence(strand)/start-end
  
  where species   = name of species, genome, strain, etc (string with no '-' characters)
        sequence  = name of reference sequence (string with no '/' characters)
        (strand)  = orientation of the alignment (relative to the reference sequence; + or -)
        start     = start coordinate of the alignment relative to the reference sequence (integer)
        end       = end coordinate of the alignment relative to the reference sequence   (integer)

  Examples:
    c_elegans-I(+)/1..2300
    myco_bovis-chr1(-)/15000..25000
  END
  ;

  die unless $name =~ /^[^-]+-[^\(]+\([+-]\)\/\-?\d+\-\-?\d+$/; 
}
