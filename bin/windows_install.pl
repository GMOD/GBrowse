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

use constant BIOPERL_VERSION     => 'bioperl-1.5.2_102';
use constant BIOPERL_REQUIRES    => '1.005002';  # sorry for the redundancy
use constant GBROWSE_DEFAULT     => '1.66';
use constant SOURCEFORGE_MIRROR  => 'http://easynews.dl.sourceforge.net/sourceforge/gmod/';
use constant SOURCEFORGE_GBROWSE => 'http://sourceforge.net/project/showfiles.php?group_id=27707&package_id=34513';
use constant BIOPERL             => 'http://bioperl.org/DIST/'.BIOPERL_VERSION.'.tar.gz';
use constant NMAKE               => 'http://download.microsoft.com/download/vc15/patch/1.52/w95/en-us/nmake15.exe';

my %REPOSITORIES = ('BioPerl-Release-Candidates' => 'http://bioperl.org/DIST/RC',
		    'BioPerl-Regular-Releases'   => 'http://bioperl.org/DIST',
	            'Kobes'                      => 'http://theoryx5.uwinnipeg.ca/ppms',
                    'Bribes'                     => 'http://www.Bribes.org/perl/ppm');

my $binaries = $Config{'binexp'};
my $make     = $Config{'make'};

# this is so that ppm can be called in a pipe
$ENV{COLUMNS} = 80; # why do we have to do this?
$ENV{LINES}   = 24;

my $tmpdir = tempdir(CLEANUP=>1) or die "Could not create temporary directory: $!";
my $windows = $Config{osname} =~ /mswin/i;

if ($windows && !-e "$binaries/${make}.exe") {

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
  cp('NMAKE.ERR',"$binaries/${make}.ERR"); # or die "Couldn't install nmake.err: $!"; # not fatal
}

setup_ppm() if $windows;

unless ( eval "use GD 2.31; 1" ) {
   if ($windows) {
     print STDERR "Installing GD via ppm.\n";
     print STDERR "(This may take a while...\n";
     system("ppm install GD");
  }
  else {
     print STDERR "Installing GD via CPAN...\n";
     CPAN::Shell->install('GD') unless eval "use GD 2.31; 1";
  }
}

print STDERR "Installing other prerequisites via CPAN...\n";
CPAN::Shell->install('GD::SVG');
CPAN::Shell->install('IO::String');
CPAN::Shell->install('Text::Shellwords');
CPAN::Shell->install('CGI::Session');
CPAN::Shell->install('File::Temp');
CPAN::Shell->install('Class::Base');
CPAN::Shell->install('Digest::MD5');

my $version = BIOPERL_REQUIRES;
unless (eval "use Bio::Perl $version; 1") {
  print STDERR "Installing BioPerl...\n";
  if ($windows) {
    my $bioperl_index = find_bioperl_ppm();
    system("ppm install $bioperl_index");
  } else {
      CPAN::SHELL->install('Module::Build');
      do_install(BIOPERL,'bioperl.tgz',BIOPERL_VERSION,'Build');
  }
}
else {
  print STDERR "BioPerl is up to date.\n";
}

print STDERR "Installing Generic-Genome-Browser...\n";

my $latest_version = find_gbrowse_latest();
my $gbrowse        = SOURCEFORGE_MIRROR.$latest_version.'.tar.gz';
do_install($gbrowse,'gbrowse.tgz',$latest_version,'make');

exit 0;

END {
  open STDERR,">/dev/null"; # windows has an annoying message when cleaning up temp file
}

sub do_install {
  my ($download,$local_name,$distribution,$method) = @_;

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

  if ($method eq 'make') {
      system("perl Makefile.PL") == 0
            or die "Couldn't run perl Makefile.PL command\n";
      system("$make install")    == 0  ;#        or die "Couldn't install\n";
  }
  elsif ($method eq 'Build') {
      system("perl Build.PL")   == 0
            or die "Couldn't run perl Build.PL command\n";
      system("Build install") == 0;
  }
}

# make sure ppm repositories are correct!
sub setup_ppm {
  open S,"ppm repo list --csv|" or die "Couldn't open ppm for listing: $!";
  my %repository;
  while (<S>) {
     chomp;
     my($index,$package_count,$name) = split /,/;
     $repository{$name} = $index;
  }
  close S;
  print STDERR "Adding needed PPM repositories. This may take a while....\n";
  for my $name (keys %REPOSITORIES) {
     next if $repository{$name};
     system("ppm rep add $name $REPOSITORIES{$name}");
  }
}

sub find_bioperl_ppm {
  print STDERR "Finding most recent bioperl...";
  open S,"ppm search bioperl |" or die "Couldn't open ppm for listing: $!";
  local $/ = ''; # paragraph mode
  my ($blessed_one,$blessed_version);
  my $best = 0;
  while (<S>) {
    chomp;
    my ($number)     = /^(\d+): bioperl/m;
    my ($version)    = /^\s+Version: (.+)/m;
    my ($repository) = /^\s+Repo: (.+)/m;
    my $multiplier = 1000000;
    my $magnitude  = 0;
    # this dumb thing converts 1.5.1 into a real number
    foreach (split /[._]/,$version) {
      $magnitude += $_ * ($multiplier/=10);
    }
    ($blessed_one,$best,$blessed_version) = ($number,$magnitude,$version) if $best < $magnitude;
  }
  close S;
  print STDERR $blessed_version ? "found $blessed_version\n" : "not found\n";
  return $blessed_one;
}

sub find_gbrowse_latest {
  print STDERR "Looking up most recent version...";
  my $download_page = get(SOURCEFORGE_GBROWSE);
  my @versions      = sort {$b<=>$a} $download_page =~ /GBrowse-(\d+\.\d+)/g;
  my $version = $versions[0] || '1.67';
  print STDERR $version,"\n";
  return "Generic-Genome-Browser-$version";
}
