#-*-Perl-*-
## Bioperl Test Harness Script for Modules

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use ExtUtils::MakeMaker;
use Bio::Root::IO;
use constant TEST_COUNT => 7;

BEGIN {
  # to handle systems with no installed Test module
  # we include the t dir (where a copy of Test.pm is located)
  # as a fallback
  eval { require Test; };
  if( $@ ) {
    use lib 't';
  }
  use Test;
  plan test => TEST_COUNT;
}
use DBI;
use Bio::DB::GFF;

my $db = eval { Bio::DB::GFF->new(-dsn=>'yeast',-user=>'nobody') } ;

ok($db);

unless ($db) {
  warn "This test script will only work after you have created and loaded the test \"yeast\" database;\n";
  warn "Please see the INSTALL file for details.\n";
  die '';
}

my @h = $db->features('Transposon:sgd');
ok(@h > 0);

my $s = $db->segment(Transposon=>'YARCTy1-1');
ok(defined $s);
ok($s->start,1);
$s->absolute(1);
ok($s->low,160234);
ok($s->high,166158);

my @i = $s->features;
ok(@i>0);

