#-*-Perl-*-
## Bioperl Test Harness Script for Modules

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use ExtUtils::MakeMaker;
use Bio::Root::IO;
use constant TEST_COUNT => 3;

BEGIN {
  # to handle systems with no installed Test module
  # we include the t dir (where a copy of Test.pm is located)
  # as a fallback
  eval { require Test; };
  if( $@ ) {
    use lib '../t';
  }
  use Test;
  plan test => TEST_COUNT;
}
use lib './blib/lib','./blib/arch';
use Bio::Graphics::Browser::CAlign;

my ($score,$align) = Bio::Graphics::Browser::CAlign->_do_alignment('gattttttc','gattttccc');
ok($align);
ok($score,6);
ok($align->[0],0);
ok($align->[6],undef);
ok($align->[8],8);

