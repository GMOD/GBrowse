#!/usr/bin/perl -w
use strict;
use File::Copy;
use Bio::Root::IO;

my $cgi_target = $ARGV[0];

# now using Bio::Root::IO
#my $delim = '/';
#if ($Config{'osname'} =~ /win/i && $Config{'osname'} !~ /darwin/i ) {
#    $cgi_target =~ s!\/!\\!g;
#    $delim = '\\';
#}

print "Installing gbrowse CGI script...\n";

if (! (-e $cgi_target) ) {
    mkdir($cgi_target,0777) or die "unable to create $cgi_target directory\n";
}

foreach (qw(gbrowse gbrowse_img gbrowse_details)) {
  my $installfile = Bio::Root::IO->catfile($cgi_target, $_);
  copy($_, $installfile ) or die "unable to copy to $installfile\n";
  my $mode = 0755;
  chmod $mode, $installfile
    or die "unable to make $installfile world executable\n";
}
