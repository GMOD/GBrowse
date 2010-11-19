#-*-Perl-*-
## Bioperl Test Harness Script for Modules

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use ExtUtils::MakeMaker;
use Bio::Root::IO;
use FindBin '$Bin';
use constant TEST_COUNT => 6;

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
use lib "$Bin/../blib/lib","$Bin/../blib/arch";
use Bio::Graphics::Browser2::Realign;

my $aligner = Bio::Graphics::Browser2::Realign->new('gattttgttccc','gattttacccc');
ok($aligner);
my $score   = $aligner->score;
my $align   = $aligner->alignment; 
ok($align);
ok($score,6);
ok($align->[0],0);
ok($align->[7],undef);
ok($align->[9],7);

