#!/usr/bin/perl

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

 --method=<method name>   Set the method for the GFF3 lines representing 
                           each quantitative data point in the track.
                           The default is "microarray_oligo."

 --source=<source>        Set the source field for the GFF3 file. The default is
                           none.

 --gff3                   Create a GFF3-format file (the default)

 --featurefile            Create a "featurefile" format file -- this is the
                           simplified format used for GBrowse uploads. This
                           option is incompatible with the --gff3 option.

 --sample                 If true, then very large files (>5 MB) will be sampled
                           to obtain minimum, maximum and standard deviation; otherwise
                           the entire file will be scanned to obtain these statistics. 
                           This will process the files faster but may miss outlier
                           values.

 --path=<path>            Specify the directory in which to place the binary wiggle
                           files. The default is the current temporary directory
                           (/tmp or whatever is appropriate for your operating system).

 --base=<path>            Same as "--path".


 --trackname              specify the trackname base for the wigfile creation

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

 wiggle2gff3.pl --meth=example --so=example --path=/var/gbrowse/db example.wig \
              > example.gff3

The output will look like this:

 ##gff-version 3

 chr19	example	example	59302001	59304700	.	.	.	Name=Bed Format;wigfile=/var/gbrowse/db/track001.chr19.1199828298.wig
 chr19	example	example	59304701	59308020	.	.	.	Name=variableStep;wigfile=/var/gbrowse/db/track002.chr19.1199828298.wig
 chr19	example	example	59307401	59310400	.	.	.	Name=fixedStep;wigfile=/var/gbrowse/db/track003.chr19.1199828298.wig

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
use File::Spec;
use File::Temp 'tempfile',':seekable';

my ($show_help, $method, $source, $use_gff3, $use_featurefile, 
    $base_directory, $trackname,$sample);

GetOptions(
	   'h|help'              => \$show_help,             # Show help and exit	
	   'method=s'            => \$method,
	   'source=s'            => \$source,
	   'gff3'                => \$use_gff3,
	   'sample'              => \$sample,
	   'featurefile'         => \$use_featurefile,
	   'base|path=s'         => \$base_directory,
	   't|trackname:s'       => \$trackname,
	  )
  or pod2usage(-verbose=>2);
pod2usage(-verbose=>2) if $show_help;

die "Only one of -gff3 or -featurefile options is allowed. Use -h for help"
  if $use_gff3 && $use_featurefile;

unless (defined $base_directory) {
  $base_directory = File::Spec->tmpdir();
  warn "Using $base_directory as base directory for binary files";
}

-d $base_directory && -w _
  or die "$base_directory is not a writeable directory. Use -h for more help";

my $loader = Bio::Graphics::Wiggle::Loader->new($base_directory)
  or die "could not create loader";
$loader->allow_sampling(1) if $sample && $loader->can('allow_sampling');  # newish feature

# specify the trackname base if provided
$loader->{trackname} = $trackname if defined $trackname;
my $type = $use_featurefile ? 'featurefile' : 'gff3';

while (my $file = shift) {

    my $fh;

    if ($file =~ /\.(gz|bz2)$/) {
	warn "creating tempfile";
	$fh = tempfile();
	my $unzipper = $file =~ /\.gz$/ ? 'gunzip -c' : 'bunzip2 -c';
	my $unzip    = IO::File->new("$unzipper $file|");
	my $data;
	while ($unzip->read($data,1024)) {
	    $fh->print($data);
	}
	$unzip->close;
	seek($fh,0,SEEK_SET);
    } else {
	$fh   = IO::File->new($file) or die "could not open $file: $!";
    }
    print STDERR "Processing $file...";
    $loader->load($fh);
    print STDERR "done.\n";
    print $loader->featurefile($type,$method,$source);
}

1;


