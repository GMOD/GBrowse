#!/usr/bin/perl -w
use strict;
use File::Copy;
use Bio::Root::IO;

my $cgi_target = $ARGV[0];

print "Installing gbrowse CGI scripts...\n";

if (! (-e $cgi_target) ) {
    mkdir($cgi_target,0777) or die "unable to create $cgi_target directory\n";
}

chdir 'cgi-bin';
foreach (glob('*')) {
  next if /README/;
  next if /CVS/;
  next if /^[.\#]/;
  next if /~$/;
  my $installfile = Bio::Root::IO->catfile($cgi_target, $_);
  warn "copying $_ to $installfile";
  copy($_, $installfile ) or die "unable to copy to $installfile\n";
  my $mode = 0755;
  chmod $mode, $installfile
    or die "unable to make $installfile world executable\n";
}
