#!/usr/bin/perl

# This script should do a Windows install from the command line.

use warnings;
use strict;
use Config;
use File::Temp qw(tempdir);
use LWP::Simple;
use Archive::Zip ':ERROR_CODES';
use Archive::Tar;
use File::Copy 'cp';
use CPAN '!get';

use constant GBROWSE=>'http://gmod.cshl.edu/Generic-Genome-Browser-1.66.tar.gz';
use constant BIOPERL=>'http://gmod.cshl.edu/bioperl-1.52.tar.gz';
#use constant BIOPERL=>'http://bioperl.org/DIST/current_core_unstable.tar.gz';
use constant NMAKE  =>'http://download.microsoft.com/download/vc15/patch/1.52/w95/en-us/nmake15.exe';

my $binaries = $Config{'binexp'};
my $make     = $Config{'make'};

my $tmpdir = tempdir(CLEANUP=>1) or die "Could not create temporary directory: $!";


if ($Config{osname} =~ /mswin/i && !-e "$binaries/${make}.exe") {

  print STDERR "Installing make utility...\n";

  -w $binaries or die "$binaries directory is not writeable. Please re-login as Admin.\n";

  chdir $tmpdir;

  my $rc = mirror(NMAKE,"nmake.zip");
  die "Could not download nmake executable from Microsoft web site." 
    unless $rc == RC_OK or $rc == RC_NOT_MODIFIED;

  my $zip = Archive::Zip->new('nmake.zip') or die "Couldn't open nmake zip file for decompression: $!";
  $zip->extractTree == AZ_OK or die "Couldn't unzip file: $!";
  -e 'NMAKE.EXE' or die "Couldn't extract nmake.exe";

  cp('NMAKE.EXE',"$binaries/${make}.EXE") or die "Couldn't install nmake.exe: $!";
  #cp('NMAKE.ERR',"$binaries/${make}.EXE") or die "Couldn't install nmake.err: $!";
}

if ($Config{osname} =~ /mswin/i) {
  print STDERR "Installing GD via ppm and the Theory repository at UWinnipeg;\n";
  print STDERR "(This may take a while...\n";
  system("ppm rep delete Theory");
  system("ppm rep add Theory http://theoryx5.uwinnipeg.ca/ppms/");
  system("ppm install GD");
}
else {
  print STDERR "Installing GD via CPAN...\n";
  CPAN::Shell->install('GD') unless eval "use GD 2.31; 1";
}
print STDERR "Installing other prerequisites via CPAN...\n";
CPAN::Shell->install('GD::SVG');
CPAN::Shell->install('IO::String');
CPAN::Shell->install('Text::Shellwords');
CPAN::Shell->install('CGI::Session');
CPAN::Shell->install('File::Temp');
CPAN::Shell->install('Class::Base');
CPAN::Shell->install('Digest::MD5');

unless (eval "use Bio::Perl 1.52; 1") {
  print STDERR "Installing BioPerl...\n";
  do_install(BIOPERL,'bioperl-1.52.tar.gz','bioperl-live');
}

print STDERR "Installing Generic-Genome-Browser...\n";
do_install(GBROWSE,'gbrowse.tgz','Generic-Genome-Browser-1.66');

exit 0;

sub do_install {
  my ($download,$local_name,$distribution) = @_;

  chdir $tmpdir;

  print STDERR "Downloading $download...\n";
  my $rc = mirror($download,$local_name);
  die "Could not download $distribution distribution from $download."
    unless $rc == RC_OK or $rc == RC_NOT_MODIFIED;

  print STDERR "Unpacking $local_name...\n";
  my $z = Archive::Tar->new($local_name,1)
            or die "Couldn't open $distribution archive: $@";
  $z->extract()
            or die "Couldn't extract $distribution archive: $@";
  chdir $distribution
            or die "Couldn't enter $distribution directory: $@";
  system("perl Makefile.PL") == 0
            or die "Couldn't run perl Makefile.PL command\n";
  system("$make install")    == 0  ;#        or die "Couldn't install\n";
}
