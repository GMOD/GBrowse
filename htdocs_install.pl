#!/usr/bin/perl
use strict;
use warnings;
use File::Copy;

my $ht_target = $ARGV[0]; #target directory

print "Installing stylesheet and images...\n";

if (! (-e $ht_target) ) {
    mkdir $ht_target or die "unable to make $ht_target directory\n";
}

opendir HTDOCS, "./htdocs" or die "unable to opendir ./htdocs\n";
while (my $file = readdir(HTDOCS) ) {
    if (-f "./htdocs/$file") {
        copy("./htdocs/$file", "$ht_target/$file") or die "unable to copy to $ht_target/$file\n";
    }
}
closedir HTDOCS; 

if (! (-e "$ht_target/images/buttons") ) {
    print "Making $ht_target/images/buttons...\n";
    mkdir "$ht_target/images/buttons" or die "unable to make $ht_target/images/buttons directory\n";
}

opendir BUTTONS, "./htdocs/images/buttons" or die "unable to open ./htdocs/images/buttons\n";
while (my $file = readdir(BUTTONS) ) {
    if (-f "./htdocs/images/buttons/$file") {
        copy("./htdocs/images/buttons/$file", "$ht_target/images/buttons/$file") or die "unable to copy to $ht_target/images/buttons/$file\n"; 
    }
}
closedir BUTTONS;

if (! (-e "$ht_target/images/help") ) {
    print "Making $ht_target/images/help...\n";
    mkdir "$ht_target/images/help" or die "unable to make $ht_target/images/help directory\n";
}

opendir HELP, "./htdocs/images/help" or die "unable to open ./htdocs/images/help\n";
while (my $file = readdir(HELP) ) {
    if (-f "./htdocs/images/help/$file") {
        copy("./htdocs/images/help/$file", "$ht_target/images/help/$file") or die "unable to copy to $ht_target/images/help/$file\n";
    }
}
closedir HELP;

if (! (-e "$ht_target/tmp") ) {
    print "Making $ht_target/tmp...\n";
    mkdir "$ht_target/tmp" or die "unable to make $ht_target/tmp directory\n";
    my $mode = 0777;
    chmod $mode, "$ht_target/tmp" or die "unable to make $ht_target/tmp world writable\n";
}

