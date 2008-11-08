#!/usr/bin/perl

use strict;

my @bases = qw(g a t c);

my $length = shift || 50000;
my @nucleotides = map {$bases[rand @bases]} (1..$length);
my $nucleotides = join '',@nucleotides;
$nucleotides =~ s/(.{1,60})/$1\n/g;

print ">ctgA\n$nucleotides";

