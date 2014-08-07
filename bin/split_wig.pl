#!/usr/bin/perl -w
use strict;
use warnings;
use File::Temp qw/tempdir/;
use Getopt::Long;

##
##  Splits a wig file (variable or fixed step format) in different wig files with a maximum of 900 scaffolds/each
##  and runs the wiggel2gff.pl script to upload these files to GBrowse2.
##  Usage:  split_wig.pl -w FILE.wig -p DATABASE_PATH
##  The whole path is needed, since the gff files will point to their respective wib files.
##  After running this script, you can run it again for a different wig file, and all gff files will be pooled
##  together in the same folder. To upload the data to GBrowse2, the MySQL Backend is recommended:
##  bp_seqfeature_load.pl -f -a DBI::mysql -d DATABASE gff3_files/*.gff3
##  The data track should be configured in your DATABASE.conf file, setting the 'feature' field with the name of
##  your original wig file (without extension).
##
##  Juan J. Tena, CABD 2013
##  jjtenagu@upo.es
##

my ($wig,$path)=('','');
GetOptions
(
    "w=s" => \$wig,
    "p=s" => \$path,
);


if (!$wig || !$path) {die "Usage: split_wig.pl -w FILE.wig -p DATABASE_PATH\n";}

mkdir "$path/wib_files";
mkdir "$path/gff3_files";

my $count=0;
my $chr_old='';
my $dir=tempdir(CLEANUP => 1);
my $out=File::Temp->new(DIR => $dir, UNLINK => 0, SUFFIX => '.dat');
my $header=`head -n 1 $wig`;
open IN, $wig or die "Cannot open $wig: $!\n";
while (<IN>) {
    my $line=$_;
    chomp $line;
    if ($line=~/chrom/) {
        if ($count>=900) {
            $out=File::Temp->new(DIR => $dir, UNLINK => 0, SUFFIX => '.dat');
            print $out $header;
            $count=0;
        }
        my @fields=split /\s/,$line;
        my $chr=$fields[1];
        $chr=~s/chrom=//;
        if ($chr ne $chr_old) {
            $count++;            
        }
        $chr_old=$chr;
    }
    print $out "$line\n";
}
close IN;

my @files=<$dir/*.dat>;
my @filepath=split /\//,$wig;
my @filename=split /\./,$filepath[-1];
my $suf=1;
foreach (@files) {
    my $tmpout=File::Temp->new();
    my $outfile="$path/gff3_files/$filename[0]_$suf.gff3";
    system("wiggle2gff3.pl --path=$path/wib_files $_ > $tmpout");
    system ("sed 's/microarray_oligo/$filename[0]/' $tmpout > $outfile");
    $suf++;
}

exit;
