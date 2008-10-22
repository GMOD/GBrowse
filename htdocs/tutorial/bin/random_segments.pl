#!/usr/bin/perl

use strict;
use constant FLEN => 10000;
use constant SLEN => 50000;
use constant FNUM => 15;

my $fclass  = shift || "Match";
my $fprefix = shift || 'seg';

# open STDOUT,"|sort -k4,4n" or die;

for (1..FNUM) {
  my $start  = int(rand(SLEN));
  my $end    = $start + int(rand(FLEN));
  $end       = SLEN if $end > SLEN;
  my $strand = rand(1) > 0.5 ? '+' : '-';
  my $name   = sprintf("$fprefix%02d",$_);

  my @rows = <<END;
ctgA	example	match	$start	$end	.	$strand	.	$fclass $name
END
;

  my ($seg_start,$seg_end,$last_start,$last_end);
  $seg_start = $start;
  do {
    $seg_end = $seg_start + int(rand(500));
    $seg_end = $end if $seg_end > $end;
  push @rows,<<END;
ctgA	example	similarity	$seg_start	$seg_end	.	$strand	.	$fclass $name
END
;
    $last_end   = $seg_end;
    $last_start = $seg_start;
    $seg_start = $seg_end + int(rand(500));
  } until ($seg_start > $end);

  if ($last_end < $end) {
    $rows[-1] = <<END;
ctgA	example	similarity	$last_start	$end	.	$strand	.	$fclass $name
END
;
  }

  print @rows;

}

close STDOUT;
