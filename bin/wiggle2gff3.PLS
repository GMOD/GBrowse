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

The binary files are readable using the L<Bio::Graphics::Wiggle>
module. The quantitative data is scaled to the range of 1-255 (losing
lots of precision, but still more than enough for data visualization),
and stored in a packed format in which each file corresponds to the
length of a single chromosome or contig.

Once created, the binary files should not be moved or renamed, unless
you are careful to make corresponding changes to the pathnames given
by the "wigfile" attribute in the GFF3 file feature lines.

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
podwusage(2) if $show_help;
