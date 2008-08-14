#-*-Perl-*-
## Bioperl Test Harness Script for Modules

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use ExtUtils::MakeMaker;
use Bio::Root::IO;
use File::Temp; 
use FindBin '$Bin';
use lib "$Bin/../lib";

use constant TEST_COUNT => 26;

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
use Bio::Graphics::Wiggle;

my $tmpfile = File::Temp->new;

my $wig = eval { 
   Bio::Graphics::Wiggle->new($tmpfile,
			      1,
			      {seqid => 'chr1',
			       start => 500,
			       min   => 1,
			       max   => 255,
			      }
       )};
ok($wig);

ok($wig->start,500);
ok($wig->end,undef);

$wig->set_value(500=>1);
ok($wig->end,500);

$wig->set_value(501=>2);
ok($wig->end,501);

$wig->set_value(502=>3);
ok($wig->end,502);

$wig->set_value(503=>4);
ok($wig->end,503);

my @values = map {int $_ } @{$wig->values(500=>503)};
ok("@values","1 2 3 4");
ok($wig->end,503);

$wig->set_values(5001,[1..100]);
@values    = map {int $_} @{$wig->values(5010,5015)};
ok("@values","10 11 12 13 14 15");

undef $wig;

$wig = eval { 
    Bio::Graphics::Wiggle->new($tmpfile,1);
};
ok($wig->start,500);
ok($wig->end,5100);
ok($wig->step,1);
ok($wig->version,0);
@values = map {int $_ } @{$wig->values(500=>503)};
ok("@values","1 2 3 4");

@values    = map {int $_} @{$wig->values(5010,5015)};
ok("@values","10 11 12 13 14 15");

# now load the whole thing up
$wig->set_values(500,[1..100]);
$wig->set_values(600,[1..100]);
$wig->set_values(700,[1..100]);
$wig->set_values(900,[100..200]);
my $r = $wig->values(500=>600);
ok(scalar @$r,101);
ok(int $r->[99],100);

# test the wif import/export functionality
my $tmpfile2 = File::Temp->new;
my $wig2     = Bio::Graphics::Wiggle->new($tmpfile2,1);

# export positions 600=>700 and 900=>1000 (values are 1..100 and 100..200)
my $export1 = $wig->export_to_wif(600=>700);
ok(length $export1,365);
my $export2 = $wig->export_to_wif(900=>1000);
ok(length $export2,365);

$wig2->import_from_wif($export1);
$wig2->import_from_wif($export2);
ok($wig2->value(500),undef);
ok(int $wig2->value(600),1);
ok(int $wig2->value(601),2);
ok($wig2->value(800),undef);
ok(int $wig2->value(900),100);
ok(int $wig2->value(902),102);

