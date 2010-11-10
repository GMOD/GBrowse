use strict;
use warnings;

use Test::More;
use Test::WWW::Mechanize;

my $base_url = $ENV{GBROWSE_TEST_URL}
    or plan skip_all => 'set the GBROWSE_URL environment variable to the URL of a gbrowse_syn instance to run this test';
$base_url =~ s!/+$!!;

my $gbsyn_url = "$base_url/gbrowse_syn";

my $mech = Test::WWW::Mechanize->new;

$mech->get_ok( $gbsyn_url, 'got the bare gbrowse_syn page' );

done_testing;

