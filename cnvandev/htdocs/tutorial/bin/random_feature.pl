#!/usr/bin/perl

use strict;
use constant FLEN => 4000;
use constant SLEN => 50000;
use constant FNUM => 15;

my $ftype   = shift or "feature";
my $fclass  = shift or "Feature";
my $fprefix = shift or "f";


open STDOUT,"|sort -k4,4n" or die;

for (1..FNUM) {
  my $start  = int(rand(SLEN));
  my $end    = $start + int(rand(FLEN));
  $end       = SLEN if $end > SLEN;
  my $strand = rand(1) > 0.5 ? '+' : '-';
  my $name   = sprintf("$fprefix%02d",$_);
  print <<END;
ctgA	example	$ftype	$start	$end	.	$strand	.	$fclass $name
END
}

close STDOUT;
