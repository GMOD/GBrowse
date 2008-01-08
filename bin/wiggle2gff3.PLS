#!/usr/bin/perl -w

=head1 NAME

wiggle2gff3.pl

=head1 SYNOPSIS

  wiggle2gff3.pl [options] WIG_FILE > load_data.gff3

Converts UCSC WIG format files into gff3 files suitable for loading
into GBrowse databases. This is used for high-density quantitative
data such as CNV, SNP and expression arrays.

=head1 DESCRIPTION

Use this converter when you have dense quantitative data to display
using the xyplot, density, or heatmap glyphs, and too many data items
(thousands) to load into GBrowse. It creates one or more space-
efficient binary files containing the quantitative data, as well as a
small GFF3 file that can be loaded into Chado or other GBrowse
databases.

Typical usage is as follows:

  % wiggle2gff3.pl --method=microarray_oligo my_data.wig > my_data.gff3

=head2 Options

The following options are accepted:

 --method=<method name>   Set the Sequence Ontology method for the GFF3 lines
                           representing the quantitative features in this file. 
                           The default is "microarray_oligo."

 --source=<source>        Set the source field for the GFF3 file. The default is
                           none.

 --gff3                   Create a GFF3-format file (the default)

 --featurefile            Create a "featurefile" format file -- this is the
                           simplified format used for GBrowse uploads. This
                           option is incompatible with the --gff3 option.

 --base=<path>            Specify the directory in which to place the binary wiggle
                           files. The default is the current temporary directory
                           (/tmp or whatever is appropriate for your operating system).

 --help                   This documentation.

This script will accept a variety of option styles, including
abbreviated options ("--meth=foo"), single character options ("-m
foo"), and other common variants.

=head2 Binary wiggle files

The binary "wiggle" files created by this utility are readable using
the L<Bio::Graphics::Wiggle> module. The quantitative data is scaled
to the range of 1-255 (losing lots of precision, but still more than
enough for data visualization), and stored in a packed format in which
each file corresponds to the length of a single chromosome or contig.

Once created, the binary files should not be moved or renamed, unless
you are careful to make corresponding changes to the pathnames given
by the "wigfile" attribute in the GFF3 file feature lines. You should
also be careful about using the cp command to copy the binary files;
they are formatted with "holes" in such a way that missing data does
not take up any space on disk. If you cp them, the holes will fill up
with zeroes and the space savings will be lost. Better to use the
"tar" command with its --sparse option to move the files from one
place to another.

=head2 Example WIG File

This example is from
L<http://genome.ucsc.edu/goldenPath/help/wiggle.html>:


 # filename: example.wig
 #
 #       300 base wide bar graph, autoScale is on by default == graphing
 #       limits will dynamically change to always show full range of data
 #       in viewing window, priority = 20 positions this as the second graph
 #       Note, zero-relative, half-open coordinate system in use for bed format
 track type=wiggle_0 name="Bed Format" description="BED format" \
     visibility=full color=200,100,0 altColor=0,100,200 priority=20
 chr19 59302000 59302300 -1.0
 chr19 59302300 59302600 -0.75
 chr19 59302600 59302900 -0.50
 chr19 59302900 59303200 -0.25
 chr19 59303200 59303500 0.0
 chr19 59303500 59303800 0.25
 chr19 59303800 59304100 0.50
 chr19 59304100 59304400 0.75
 chr19 59304400 59304700 1.00
 #       150 base wide bar graph at arbitrarily spaced positions,
 #       threshold line drawn at y=11.76
 #       autoScale off viewing range set to [0:25]
 #       priority = 10 positions this as the first graph
 #       Note, one-relative coordinate system in use for this format
 track type=wiggle_0 name="variableStep" description="variableStep format" \
     visibility=full autoScale=off viewLimits=0.0:25.0 color=255,200,0 \
     yLineMark=11.76 yLineOnOff=on priority=10
 variableStep chrom=chr19 span=150
 59304701 10.0
 59304901 12.5
 59305401 15.0
 59305601 17.5
 59305901 20.0
 59306081 17.5
 59306301 15.0
 59306691 12.5
 59307871 10.0
 #       200 base wide points graph at every 300 bases, 50 pixel high graph
 #       autoScale off and viewing range set to [0:1000]
 #       priority = 30 positions this as the third graph
 #       Note, one-relative coordinate system in use for this format
 track type=wiggle_0 name="fixedStep" description="fixed step" visibility=full \
     autoScale=off viewLimits=0:1000 color=0,200,100 maxHeightPixels=100:50:20 \
     graphType=points priority=30
 fixedStep chrom=chr19 start=59307401 step=300 span=200
 1000
  900
  800
  700
  600
  500
  400
  300
  200
  100

You can convert this into a loadable GFF3 file with the following
command:

 wiggle2gff3 --meth=example --so=example --base=/var/gbrowse/db example.wig \
              > example.gff3

The output will look like this:

[ TO COME ]

=head1 SEE ALSO

L<Bio::DB::GFF>, L<bp_bulk_load_gff.pl>, L<bp_fast_load_gff.pl>,
L<bp_load_gff.pl>, L<bp_seqfeature_load.pl>

=head1 AUTHOR

Lincoln Stein <lstein@cshl.org>.

Copyright (c) 2008 Cold Spring Harbor Laboratory

This package is free software; you can redistribute it and/or modify
it under the terms of the GPL (either version 1, or at your option,
any later version) or the Artistic License 2.0.  Refer to LICENSE for
the full license text.  See DISCLAIMER.txt for disclaimers of
warranty.

=cut


use strict;

use Bio::Graphics::Wiggle::Loader;
use Getopt::Long;
use Pod::Usage;

my ( $show_help, $method, $source, $use_gff3, $use_featurefile, $base_directory);

GetOptions(
	   'h|help'              => \$show_help,             # Show help and exit	
	   'method=s'            => \$method,
	   'source=s'            => \$source,
	   'gff3'                => \$use_gff3,
	   'featurefile'         => \$use_featurefile,
	   'base'                => \$base_directory
	  )
  or pod2usage(2);
pod2usage(2) if $show_help;


