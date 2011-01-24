#!/usr/bin/perl

# convert UCSC gene files into GFF3 data

use strict;
use File::Basename 'basename';
use Getopt::Long;

my $executable = basename($0);

my ($SRC,$ORIGIN);
GetOptions('src:s'    => \$SRC,
	   'origin:i' => \$ORIGIN,
	   ) or die <<USAGE;
Usage: $0 [options] ucsc_file1 ucsc_file2...

Convert UCSC Genome Browser BED-format gene files into GFF3 version files.
Only the gene IDs and their locations come through.  You have to get
the comments and aliases some other way.

Options:

    -src    <string>   Choose a source for the gene, default "UCSC"
    -origin <integer>  Choose a relative position to number from, default is "1"

The resulting file is in GFF3 format and should be loaded into a
Bio::DB::GFF database using the following command:

 bp_bulk_load_gff.pl -c -d db1 --maxfeature 1000000000 --gff3_munge file.gff

USAGE

$SRC    ||= 'UCSC';
$ORIGIN ||= 1;

print "##gff-version 3\n";

# automatically uncompress varous compression formats
foreach (@ARGV) {
  $_ = "gunzip     -c $_ |" if /\.gz$/;
  $_ = "uncompress -c $_ |" if /\.Z$/;
  $_ = "bunzip2    -c $_ |" if /\.bz2$/;
}

while (<>) {
  chomp;
  next if /^\#/;;
  next if /random/;  ## added line

  my ($chrom,$txStart,$txEnd,$id,$score,$strand,$cdsStart,$cdsEnd,
      $itemRGB,$exonCount,$exonSizes,$exonStarts) = split /\t/;
  my ($utr5_start,$utr5_end,$utr3_start,$utr3_end);

  # adjust for Jim's 0-based coordinates
  $txStart++;
  $cdsStart++;

  $txStart  -= $ORIGIN;
  $txEnd    -= $ORIGIN;
  $cdsStart -= $ORIGIN;
  $cdsEnd   -= $ORIGIN;

  # print the transcript
  print join("\t",$chrom,$SRC,'mRNA',$txStart,$txEnd,'.',$strand,'.',"ID=$id;Name=$id"),"\n";

  # now handle the CDS entries -- the tricky part is the need to keep
  # track of phase
  my $phase = 0;
  my @exon_starts = map {$_-$ORIGIN+$txStart} split ',',$exonStarts;
  my @exon_sizes  = map {$_-$ORIGIN} split ',',$exonSizes;
  my @exon_ends   = map {$exon_starts[$_]+$exon_sizes[$_]+1} (0..@exon_sizes);

  if ($strand eq '+') {
    for (my $i=0;$i<@exon_starts;$i++) {  # for each exon start
      my $exon_start = $exon_starts[$i] + 1;
      my $exon_end   = $exon_ends[$i];
      my (@utr_start,@utr_end,$cds_start,$cds_end);

      if ($exon_start < $cdsStart) { # in a 5' UTR
	push (@utr_start, $exon_start);
      } elsif ($exon_start > $cdsEnd) { 
	push (@utr_start, $exon_start);
      } else {
	$cds_start = $exon_start;
      }

      if ($exon_end < $cdsStart) {
	push (@utr_end, $exon_end);
      } elsif ($exon_end > $cdsEnd) {
	push (@utr_end, $exon_end);
      } else {
	$cds_end = $exon_end;
      }

      if ($utr_start[0] && !$utr_end[0]) { # half in half out on 5' end
	$utr_end[0]= $cdsStart - 1;
	$cds_start = $cdsStart;
	$cds_end   = $exon_end;
      }

      if ($utr_end[0] && !$utr_start[0]) { # half in half out on 3' end
	$utr_start[0]= $cdsEnd + 1;
	$cds_end     = $cdsEnd;
	$cds_start   = $exon_start;
      }

      # If the CDS is within the exon
      if (defined $utr_start[0] == defined $utr_end[0] && 
	  $utr_start[0] < $cdsStart && $utr_end[0] > $cdsEnd) {
	$utr_end[0]= $cdsStart - 1;
	$cds_start = $cdsStart;
	$cds_end   = $cdsEnd;
	
	push (@utr_start, $cdsEnd + 1);
	push (@utr_end, $exon_end);
      }


      die "programmer error, not an even number of utr_starts and
utr_ends"
	unless $#utr_start == $#utr_end;
      die "programmer error, cds_start and no cds_end" 
	unless defined $cds_start == defined $cds_end;

      for (my $i=0;$i<@utr_start;$i++) {  # for each utr start
	if (defined $utr_start[$i] && $utr_start[$i] <= $utr_end[$i] &&
$utr_start[$i] < $cdsStart) {
	  print join
("\t",$chrom,$SRC,"five_prime_UTR",$utr_start[$i],$utr_end[$i],'.',$strand,'.',"Parent=$id"),"\n"	
	} # end of if	    
      } # end of foreach

      if (defined $cds_start && $cds_start <= $cds_end) {
	print join
("\t",$chrom,$SRC,'CDS',$cds_start,$cds_end,'.',$strand,$phase,"Parent=$id"),"\n";
	$phase = (($cds_end-$cds_start+1-$phase)) % 3;
      }

      for (my $i=0;$i<@utr_start;$i++) {  # for each utr start
	if (defined $utr_start[$i] && $utr_start[$i] <= $utr_end[$i] &&
$utr_start[$i] > $cdsEnd) {
	  print join ("\t",$chrom,$SRC,"three_prime_UTR",,$utr_start[$i],
$utr_end[$i],'.',$strand,'.',"Parent=$id"),"\n"	
	}
      }
    } # end of for each exon
  } # matches if strand = +


  if ($strand eq '-') {
    my @lines;
    for (my $i=@exon_starts-1; $i>=0; $i--) { # count backwards
      my $exon_start = $exon_starts[$i] + 1;
      my $exon_end   = $exon_ends[$i];
      my (@utr_start,@utr_end,$cds_start,$cds_end);

      if ($exon_end > $cdsEnd) { # in a 5' UTR
	push (@utr_end,  $exon_end);
      } elsif ($exon_end < $cdsStart) {
	push (@utr_end,  $exon_end);
      } else {
	$cds_end = $exon_end;
      }

      if ($exon_start > $cdsEnd) {
	push (@utr_start, $exon_start);
      } elsif ($exon_start < $cdsStart) {
	push (@utr_start, $exon_start);
      } else {
	$cds_start = $exon_start;
      }

      if ($utr_start[0] && !$utr_end[0]) { # half in half out on 3' end
	$utr_end[0]   = $cdsStart - 1;
	$cds_start = $cdsStart;
	$cds_end   = $exon_end;
      }

      if ($utr_end[0] && !$utr_start[0]) { # half in half out on 5' end
	$utr_start[0] = $cdsEnd + 1;
	$cds_end   = $cdsEnd;
	$cds_start = $exon_start;
      }

      # If the CDS is within the exon  
      if (defined $utr_start[0] == defined $utr_end[0] && 
	  $utr_start[0] < $cdsStart && $utr_end[0] > $cdsEnd) {
	$utr_end[0]= $cdsStart - 1;
	$cds_start = $cdsStart;
	$cds_end   = $cdsEnd;
	
	push (@utr_start, $cdsEnd + 1);
	push (@utr_end, $exon_end);
      }

      die "programmer error, not an even number of utr_starts and
utr_ends"
	unless $#utr_start == $#utr_end;

      die "programmer error, cds_start and no cds_end" unless defined
$cds_start == defined $cds_end;

      for (my $i=0;$i<@utr_start;$i++) {  # for each utr start
	if (defined $utr_start[$i] && $utr_start[$i] <= $utr_end[$i] &&
$utr_start[$i] > $cdsEnd) {
	  unshift @lines,join
("\t",$chrom,$SRC,"five_prime_UTR",,$utr_start[$i],$utr_end[$i],'.',$strand,'.',"Parent=$id"),"\n"	
	}
      } # end of for

      if (defined $cds_start && $cds_start <= $cds_end) {
	unshift @lines,join
("\t",$chrom,$SRC,'CDS',$cds_start,$cds_end,'.',$strand,$phase,"Parent=$id"),"\n";
	$phase = (($cds_end-$cds_start+1-$phase)) % 3;
      }

      for (my $i=0;$i<@utr_start;$i++) {  # for each utr start
	if (defined $utr_start[$i] && $utr_start[$i] <= $utr_end[$i] &&
$utr_end[$i] < $cdsStart) {
	  unshift @lines,join
("\t",$chrom,$SRC,"three_prime_UTR",$utr_start[$i],$utr_end[$i],'.',$strand,'.',"Parent=$id"),"\n"	
	}
      } # end for
    }
    print @lines;
  }
} # end while <>

__END__

=head1 NAME

ucsc_genes2gff.pl - Convert UCSC Genome Browser-format gene files into GFF
files suitable for loading into gbrowse

=head1 SYNOPSIS

  % uscsc_genes2gff.pl [options] ucsc_file1 ucsc_file2...

Options:

    -src    <string>   Choose a source for the gene, default "UCSC"
    -origin <integer>  Choose a relative position to number from, default
is "1"

=head1 DESCRIPTION

This script massages the gene files available from the "tables" link
of the UCSC genome browser (genome.ucsc.edu) into a form suitable for
loading of gbrowse.  Warning: it only works with the gene tables.
Other tables, such as EST alignments, contours and repeats, have their
own formats which will require other scripts to parse.

To use this script, get one or more UCSC tables, either from the
"Tables" link on the browser, or from the UCSC Genome Browser FTP
site.  Give the table file as the argument to this script.  You may
want to provide an alternative "source" field.  Otherwise this script
defaults to "UCSC".

  % pucsc_genes2gff.pl -src RefSeq refseq_data.ucsc > refseq.gff

The resulting GFF file can then be loaded into a Bio::DB::GFF database
using the following command:

  % bulk_load_gff.pl -d <databasename> refseq.gff

=head1 SEE ALSO

L<Bio::DB::GFF>, L<bulk_load_gff.pl>, L<load_gff.pl>

=head1 AUTHOR

Lincoln Stein <lstein@cshl.org>.

Copyright (c) 2003 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut

