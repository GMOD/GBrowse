#-*-Perl-*-
## Bioperl Test Harness Script for Modules

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use ExtUtils::MakeMaker;
use Bio::Root::IO;
use constant TEST_COUNT => 6;

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
use Bio::DB::SeqFeature::Store;


my $db = eval { Bio::DB::SeqFeature::Store->new(
            -adaptor=>'memory',
            -dsn=>'htdocs/databases/yeast_chr1+2/yeast_chr1+2.gff3',
            ) } ;

ok($db);

unless ($db) {
  warn "This test script will only work after you have created and loaded the test \"yeast\" database;\n";
  warn "Please see the INSTALL file for details.\n";
  die '';
}

my @h = $db->features(-type => 'LTR_retrotransposon');
ok(@h > 0);

my $s = $db->segment('YARCTy1-1');
ok(defined $s);
ok($s->start,160239);
ok($s->end,166163);

my @i = $s->features;
ok(@i>0);

