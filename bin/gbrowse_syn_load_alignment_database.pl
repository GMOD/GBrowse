#!/usr/bin/perl -w 

use strict;

=head1 NAME

load_alignment_database.pl - a script to load the database for gbrowse_syn.

=head1 DESCRIPTION

The expected file format is tab-delimited (shown below):

  species1  ref1  start1 end1 strand1  cigar_string1 \
  species2  ref2  start2 end2 strand2  cigar_string2 \
  coords1... | coords2...

the coords (coordinate) format:

  pos1_species1 pos1_species2 ... posn_species1 posn_species2 | \
  pos1_species2 pos1_species1 ... posn_species2 posn_species1

where pos is the matching sequence coordinate (ungapped) in each
species.

=cut

use strict;

use Getopt::Long;
use Pod::Usage;

use constant VERBOSE  => 0;

use Bio::DB::Synteny::Store;
use Bio::DB::Synteny::Store::Loader::Tabular;

my ( $format, $user, $pass, $dsn, $verbose, $nomap, $create, $adaptor );

GetOptions(
	   'f|format=s'    => \$format,
           'a|adaptor=s'   => \$adaptor,
           'u|user=s'      => \$user,
	   'p|pass=s'      => \$pass,
	   'd|dsn=s'       => \$dsn,
	   'v|verbose'     => \$verbose,
	   'M|nomap'       => \$nomap,
	   'c|create'      => \$create
	   );

my $usage = "Usage: load_alignment_database.pl -u username -p password -d database [-m map_resolution, -v, -n, -c] file1, file2 ... filen\n\n";

$dsn     || pod2usage();
$verbose ||= VERBOSE;

my $syn_store = Bio::DB::Synteny::Store->new(
    -adaptor => $adaptor || 'DBI::mysql',
    -dsn     => $dsn,
    -user    => $user,
    -pass    => $pass,
    -create  => $create,
    -verbose => $verbose,
   );

my $loader = Bio::DB::Synteny::Store::Loader::Tabular->new(
    -store   => $syn_store,
    -nomap   => $nomap,
    -verbose => $verbose,
    );

$loader->load( @ARGV );
