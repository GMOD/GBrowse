# This is -*-Perl-*- code
## Bioperl Test Harness Script for Modules
##
# $Id: GraphicsBrowserConfigIO.t,v 1.1.2.1 2003-05-23 16:38:06 pedlefsen Exp $

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use vars qw( $NUMTESTS $DEBUG $VERBOSE );

#use lib '..','.','./blib/lib';
use lib '..','.','./lib';

BEGIN { 
  # to handle systems with no installed Test module
  # we include the t dir (where a copy of Test.pm is located)
  # as a fallback
  eval { require Test; };
  if( $@ ) {
    use lib 't';
  }
  use Test;

  $NUMTESTS = 35;
  plan tests => $NUMTESTS;
}

## End of black magic.
##
## Insert additional test code below but remember to change
## the NUMTESTS variable in the BEGIN block to reflect the
## total number of tests that will be run. 

use Bio::Graphics::Browser::ConfigIO;
use Bio::Graphics::Browser::Config;

my $config_string = <<"EOF";
# file begins
[general]
pixels = 1024
bases = 1-20000
reference = Contig41
height = 12

[Cosmid]
glyph = segments
fgcolor = blue
key = C. elegans conserved regions

[EST]
glyph = segments
bgcolor= yellow
connector = dashed
height = 5

[FGENESH]
glyph = transcript2
bgcolor = green
description = 1

Cosmid	B0511	516-619
Cosmid	B0511	3185-3294
Cosmid	B0511	10946-11208
Cosmid	B0511	13126-13511
Cosmid	B0511	11394-11539
EST	yk260e10.5	15569-15724
EST	yk672a12.5	537-618,3187-3294
EST	yk595e6.5	552-618
EST	yk595e6.5	3187-3294
EST	yk846e07.3	11015-11208
EST	yk53c10
	yk53c10.3	15000-15500,15700-15800
	yk53c10.5	18892-19154
EST	yk53c10.5	16032-16105
SwissProt	PECANEX	13153-13656	Swedish fish
FGENESH	'Predicted gene 1'	1-205,518-616,661-735,3187-3365,3436-3846	Pfam domain
FGENESH	'Predicted gene 2'	5513-6497,7968-8136,8278-8383,8651-8839,9462-9515,10032-10705,10949-11340,11387-11524,11765-12067,12876-13577,13882-14121,14169-14535,15006-15209,15259-15462,15513-15753,15853-16219	Mysterious
FGENESH	'Predicted gene 3'	16626-17396,17451-17597
FGENESH	'Predicted gene 4'	18459-18722,18882-19176,19221-19513,19572-19835	Transmembrane protein
# file ends
EOF

my $configio =
  Bio::Graphics::Browser::ConfigIO->new( -text => $config_string );

ok( $configio );
ok( $configio->text(), $config_string );

## By default things should be marked unsafe.
ok( !$configio->safe() );

my $config = $configio->read_config();
ok( $config );

my @sections = $config->get_sections();
ok( scalar( @sections ), 3 );

ok( scalar( $config->get_tags( 'EST' ) ), 4 );

ok( $config->get( 'bases' ), '1-20000' );
ok( $config->get( 'FGENESH', 'glyph' ), 'transcript2' );
ok( $config->get( 'Cosmid', 'key' ), 'C. elegans conserved regions' );

my $collection = $config->get_collection();
ok( $collection->feature_count(), 12 );

my ( $feature ) = $collection->features( '-name' => 'B0511' );
ok( $feature->start(), 516 );
ok( $feature->end(), 13511 );

# The subfeatures should now have relative coords.
my ( $subfeature ) = $feature->features( '-range' => new Bio::RelRange( '-start'=>1, '-end'=>104 ) );
ok( $subfeature );
ok( $subfeature->abs_start(), 516 );
ok( $subfeature->abs_end(), 619 );
ok( $subfeature->start(), 1 );
ok( $subfeature->end(), 104 );
( $subfeature ) = $feature->features( '-range' => new Bio::RelRange( '-start'=>12611, '-end'=>12996 ) );
ok( $subfeature );
ok( $subfeature->abs_start(), 13126 );
ok( $subfeature->abs_end(), 13511 );
ok( $subfeature->start(), 12611 );
ok( $subfeature->end(), 12996 );

# Test the strange new grouping technique
( $feature ) = $collection->features( '-name' => 'yk53c10' );
ok( $feature );
ok( $feature->start(), 15000 );
ok( $feature->end(), 19154 );

( $subfeature ) = $feature->features( '-name' => 'yk53c10.3' );
ok( $subfeature );
ok( $subfeature->abs_start(), 15000 );
ok( $subfeature->abs_end(), 15800 );
ok( $subfeature->start(), 1 );
ok( $subfeature->end(), 801 );

my ( $sub_subfeature ) =
  $subfeature->features( '-range' => new Bio::RelRange( '-start'=>701, '-end'=>801 ) );
ok( $sub_subfeature );
ok( $sub_subfeature->abs_start(), 15700 );
ok( $sub_subfeature->abs_end(), 15800 );
ok( $sub_subfeature->start(), 701 );
ok( $sub_subfeature->end(), 801 );

