# This is -*-Perl-*- code
## Bioperl Test Harness Script for Modules
##
# $Id: GraphicsBrowser.t,v 1.1.2.3 2003-07-02 22:33:43 pedlefsen Exp $

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use vars qw( $CONF_DIR $NUMTESTS $DEBUG $VERBOSE );

$DEBUG    = 1;
$VERBOSE  = 1;

## All files ending in .conf in the directory $CONF_DIR will be made
## available to the Browser being tested, but only the first
## (alphabetically) will be used.
#$CONF_DIR = 'conf';
## TODO: REMOVE
$CONF_DIR = 't/gbrowse.conf';

#use lib '..','.','./blib/lib';
## TODO: REMOVE
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

  $NUMTESTS = 3;
  plan tests => $NUMTESTS;
}

## End of black magic.
##
## Insert additional test code below but remember to change
## the NUMTESTS variable in the BEGIN block to reflect the
## total number of tests that will be run. 


use Bio::Graphics::Browser qw( &configureBrowsers &retrieveBrowser );
use CGI;

my %defaults =
(
 # if you change the zoom/nav icons, you must change this as well.
 'mag_icon_height'      => 20,
 'mag_icon_width'       => 8,

 # hard-coded values for segment sizes
 # many of these can be overridden by configuration file entries
 'max_segment'          => 1_000_000,
 'min_seg_size'         => 50,
 'tiny_seg_size'        => 2,
 'expand_seg_size'      => 5000,
 'too_many_segments'    => 5_000,
 'too_many_features'    => 100,
 'too_many_refs'        => 100,
 'default_segment'      => 100_000,

 'overview_ratio'       => 0.9,
 'annotation_edit_rows' => 25,
 'annotation_edit_cols' => 100,
 'url_fetch_timeout'    => 5,  # five seconds max!
 'url_fetch_max_size'   => 1_000_000,  # don't accept any files larger than 1 Meg
 'keyword search max'   => 1_000,     # max number of results from keyword search
 'zoom_levels'          => q(100 500 1000 5000 10000 25000 100000 200000 400000),
 'fine_zoom'            => '10%',
 'help'                 => '/gbrowse', # gbrowse help dir
 #'plugins'              => 'FastaDumper RestrictionAnnotator SequenceDumper',

 'width'                => 800,
 'default_db_adaptor'   => 'Bio::DB::GFF',
 'keystyle'             => 'bottom',
 'empty_tracks'         => 'key',
 'ruler_intervals'      => 20,  # fineness of the centering map on the ruler
 'too_many_segments'    => 5_000,
 'max_segment'          => 1_000_000,
 'default_ranges'       => q(100 500 1000 5000 10000 25000 100000 200000 400000),
 'min_overview_pad'     => 25,
 'pad_overview_bottom'  => 3,
 'browser_ttl'          => '+3d' # Browsers are recycled after 3 days of disuse

);

## CONFIGURATION & INITIALIZATION ################################
# preliminaries -- read and/or refresh the configuration directory

# Load the configuration files
ok( configureBrowsers( $CONF_DIR ) );

my $browser =
  Bio::Graphics::Browser->new(
    %defaults
  );
ok( $browser );

my $session_id = $browser->unique_id();
ok( $session_id );

#$browser->gbrowse( \*STDOUT, 'sample', undef, { 'name' => 'B0511' } );
#$browser->gbrowse( \*STDOUT, 'sample', undef, { 'name' => 'Contig41' } );
#$browser->gbrowse( \*STDOUT, 'sample', undef, { 'name' => 'II' } );
#$browser->gbrowse( \*STDOUT, 'blast', undef, { 'name' => 'test_first_protein_in_IPI' } );
#$browser->gbrowse( \*STDOUT, 'rakari', undef, { 'name' => 'Genome' } );
$browser->gbrowse( \*STDOUT, 'jdrf', undef, { 'name' => 'chr1:228150000,228650000' } );
