#!/usr/bin/perl -w
use strict;
use File::Copy;
use Config;

my $ht_target = $ARGV[0]; #target directory

my $delim = '/';
if ($Config{'osname'} =~ /win/i && $Config{'osname'} !~ /darwin/i ) {
    $ht_target =~ s!\/!\\!g;
    $delim = '\\';
}



print "Installing stylesheet and images...\n";

if (! (-e $ht_target) ) {
    mkdir($ht_target,0777) or die "unable to make $ht_target directory\n";
}

opendir HTDOCS, "htdocs" or die "unable to opendir htdocs\n";
while (my $file = readdir(HTDOCS) ) {
    if (-f "htdocs/$file") {
        copy("htdocs" . $delim . $file, $ht_target . $delim . $file) or die "unable to copy to $ht_target/$file\n";
    }
}
closedir HTDOCS; 

my $imagedir  = $ht_target . $delim . "images" ;
my $buttondir = $ht_target . $delim . "images" . $delim . "buttons";
if (! (-e $imagedir) ) {
    mkdir($imagedir,0777) or die "unable to make $imagedir\n";
}
if (! (-e $buttondir) ) {
    print "Making $buttondir...\n";
    mkdir($buttondir,0777) or die "unable to make $buttondir\n";
}

opendir BUTTONS, "htdocs/images/buttons" or die "unable to open ./htdocs/images/buttons\n";
while (my $file = readdir(BUTTONS) ) {
    if (-f "./htdocs/images/buttons/$file") {
        copy("htdocs".$delim."images".$delim."buttons".$delim.$file, $buttondir.$delim.$file) 
            or die "unable to copy to $ht_target/images/buttons/$file\n"; 
    }
}
closedir BUTTONS;

my $helpdir = $ht_target . $delim . "images" . $delim . "help";
if (! (-e $helpdir) ) {
    print "Making $helpdir...\n";
    mkdir($helpdir,0777) or die "unable to make $helpdir\n";
}

opendir HELP, "htdocs/images/help" or die "unable to open htdocs/images/help\n";
while (my $file = readdir(HELP) ) {
    if (-f "./htdocs/images/help/$file") {
        copy("htdocs".$delim."images".$delim."help".$delim.$file, $helpdir.$delim.$file) 
            or die "unable to copy to $ht_target/images/help/$file\n";
    }
}
closedir HELP;

my $tmpdir = $ht_target . $delim . "tmp";
if (! (-e $tmpdir) ) {
    print "Making $tmpdir...\n";
    mkdir($tmpdir,0777) or die "unable to make $tmpdir\n";
    my $mode = 0777;
    chmod $mode, $tmpdir or die "unable to make $tmpdir world writable\n";
}


