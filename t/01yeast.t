#-*-Perl-*-
## Bioperl Test Harness Script for Modules

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use ExtUtils::MakeMaker;
use Bio::Root::IO;
use FindBin '$Bin';
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
use Bio::DB::SeqFeature::Store;

my $db = eval { Bio::DB::SeqFeature::Store->new(-adaptor=>'memory',
						-dsn    =>"$Bin/../sample_data/yeast_chr1+2") } ;

ok($db);

my @h = $db->features('LTR_retrotransposon:SGD');
ok(@h > 0);

my ($s) = $db->get_features_by_name('YARCTy1-1');
ok(defined $s);
ok($s->start,160239);
ok($s->end,166163);

my $seg = $db->segment('YARCTy1-1');
ok($seg);

my @i = $seg->features;
ok(@i>0);

END {
    unlink "$Bin/../htdocs/databases/yeast_chr1+2/directory.index";
}
