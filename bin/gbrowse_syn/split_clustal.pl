#!/usr/bin/perl -w
# split a clustal file with multiple alignments into 
# multiple files with one alignment each.

# Usage: 
#  gzip -c clustal_file.gz |./split_clustal.pl [destination_dir]
#  cat clustal_file.gz |./split_clustal.pl [destination_dir] 
use strict;

my $dir = shift || '.';
-d $dir or mkdir($dir);
chdir($dir);

# change input record seperator from the default newline;
my $header = 'CLUSTAL W(1.81) multiple sequence alignment';
$/ = $header;

my $idx = 0;
while (<>) {
    next unless /[+-]/;
    my @lines = split "\n", $_;
    chomp @lines;
    pop @lines;
    my $name = ++$idx.".aln";
    open OUT, ">$name";
    my $out = join("\n",$header,@lines)."\n";
    print OUT $out; 
    print STDERR "Finished alignment ".++$idx."\r";
}
