#!/usr/bin/perl -w

=head1 NAME

bam2bigwig_hybridplot.pl

=head1 SYNOPSIS

  bam2bigwig_hybridplot [options] bam genome > bigwig_load.gff3

Converts BAM file into bigwig with plus and minus strand separated and
a GFF file for loading suitable for hybrid_plot viewing in
Gbrowse. This is used for stranded seq information (smallRNA-Seq and
stranded RNA-Seq).

=head1 DESCRIPTION

Typical usage is as follows:

  % 

=head2 Options

The following options are accepted:

 --method=<method name>   Set the method for the GFF3 lines representing 
                           each quantitative data point in the track.
                           The default is "WIG."

 --source=<source>        Set the source field for the GFF3 file. The default is the 
                          basename of the bam file

 --gff3                   Create a GFF3-format file (the default)

 --path=<path>            Specify the directory in which to place the binary bigwig
                           files. The default is the current directory.

 --base=<path>            Same as "--path".

 --trackname=<name>       Specify the trackname base for the bigwigfile creation
 
 --wigToBigWig=<path>     Full path to the 'wigToBigWig' exe (Kent tools) if not in your path
 --genomeCoverageBed=<path> Full path to the 'genomeCoverageBed' exe (BEDtools) if not in your path

 --help                   This documentation.

This script will accept a variety of option styles, including
abbreviated options ("--meth=foo"), single character options ("-m
foo"), and other common variants.


=head1 SEE ALSO

L<wiggle2gff.pl>

=head1 AUTHOR

Jason Stajich <jason@bioperl.org>

This package is free software; you can redistribute it and/or modify
it under the terms of the GPL (either version 1, or at your option,
any later version) or the Artistic License 2.0.  Refer to LICENSE for
the full license text.  See DISCLAIMER.txt for disclaimers of
warranty.

=cut


use strict;

use Getopt::Long;
use File::Spec;

my ($path);

my $exe_genomeCoverage = 'genomeCoverageBed';
my $exe_wigtoBigwig       = 'wigToBigWig';

my $source;
my $method = 'WIG';
my $basename;
my ($genome,$bamfile,$trackname,$genomefa);
my $odir  = '.';
my $force = 0;
GetOptions('wigToBigWig:s' => \$exe_wigtoBigwig,
	   'genomeCoverageBed:s' => \$exe_genomeCoverage,
	   'p|path:s'       => \$path,
	   'm|method:s'     => \$method,
	   's|source:s'     => \$source,
	   'b|base:s'       => \$basename,
	   'g|genome:s'     => \$genome,
	   'f|fasta|genomefa:s' => \$genomefa,
	   'bam|bamfile:s'=> \$bamfile,
	   't|trackname:s'  => \$trackname,
	   'o|outdir:s'     => \$odir,
	   'force!'         => \$force,
	   );


$bamfile ||= shift @ARGV;

if( ! defined $genome ) {
    die("must provide the genome tab delimited format that genomeCoverageBed expects\n");
}

if( ! defined $bamfile) {
    die("must provide bamfile\n");
}

if( ! defined $basename ) {
    my (undef,$dir,$filename) = File::Spec->splitpath($bamfile);
    if( $filename =~ /(\S+)\.bam$/) {
	$basename = $1;
    } else {
	warn("unknown bamfile extension, expected .bam\n");
	$basename = $bamfile;
    }
}

$source ||= $basename;
$trackname ||= $basename;


# minus strand

if( $force || ! -f "$odir/$basename.minus.bedgraph" ) {
    `$exe_genomeCoverage ibam -split -bg -strand - -i $bamfile -g $genome > $odir/$basename.minus.bedgraph`;
}
if( $force || ! -f "$odir/$basename.plus.bedgraph") {
    `$exe_genomeCoverage ibam -split -bg -strand + -i $bamfile -g $genome > $odir/$basename.plus.bedgraph`;
}

my %chrom_cov;
for my $file ("$basename.minus.bedgraph","$basename.plus.bedgraph")  {
    open(my $fh => "$odir/$file") || die $!;
    while(<$fh>) {
	my ($chrom,$start,$end) = split;
	if( ! exists $chrom_cov{$chrom})  {
	    @{$chrom_cov{$chrom}} = ($start,$end);
	} else {
	    $chrom_cov{$chrom}->[0] = $start if($start < $chrom_cov{$chrom}->[0]);
	    $chrom_cov{$chrom}->[1] = $end if($end > $chrom_cov{$chrom}->[1] );
	}
    }
    close($fh);
}
warn("wigToBigWig $basename.minus.bedgraph $genome $path/$basename.minus.bw\n");

if( $force || ! -f "$path/$basename.minus.bw") {
    `wigToBigWig $basename.minus.bedgraph $genome $path/$basename.minus.bw`;
}
if( $force || ! -f "$path/$basename.plus.bw") {
    `wigToBigWig $basename.plus.bedgraph $genome $path/$basename.plus.bw`;
}



print "##gff-version 3\n","##date ".localtime()."\n";
for my $chrom ( sort keys %chrom_cov ) {
    print join("\t", $chrom, $source,$method, $chrom_cov{$chrom}->[0],$chrom_cov{$chrom}->[1],
	       '.','.','.', sprintf("Name=%s;peak_type=\"\",wigfileA=%s;wigfileB=%s;fasta=%s",
				    $basename,"$path/$basename.plus.bw","$path/$basename.minus.bw",
				    $genomefa)),"\n";
}


