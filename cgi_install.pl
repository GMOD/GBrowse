#!/usr/bin/perl
use strict;
use warnings;
use File::Copy;

my $cgi_target = $ARGV[0];

my $delim = '/';
my $platform = 'linux';
if ($Config{'osname'} =~ /win/i) {
    $cgi_target =~ s!\/!\\!g;
    $delim = '\\';
    $platform = 'windows';
}

print "Installing gbrowse CGI script...\n";

if (! (-e $cgi_target) ) {
    mkdir $cgi_target or die "unable to create $cgi_target directory\n";
}

copy("gbrowse",    $cgi_target.$delim.'gbrowse') or die "unable to copy to $cgi_target/gbrowse\n";
my $mode = 0755;
chmod $mode, $cgi_target.$delim.'gbrowse' or die "unable to make $cgi_target/gbrowse world executable\n";

copy("gbrowse_img", $cgi_target.$delim.'gbrowse_img') or die "unable to copy to $cgi_target/gbrowse_img\n";
chmod $mode, "$cgi_target/gbrowse_img" or die "unable to make $cgi_target/gbrowse_img world executable\n";


