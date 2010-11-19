#!/usr/bin/perl

=head1 NAME

gbrowse_netinstall.pl

=head1 SYNOPSIS

  gbrowse_netinstall.pl -b|--build_param_str BUILD_STRING [options]

options: 

 -h|--help                Show this message 
 -d|--dev                 Use the developement version of both GBrowse 
                            and bioperl from CVS
 --bioperl_dev            Use the development version of BioPerl from SVN
 --gbrowse_dev            Use the development version of GBrowse from CVS
 --build_param_str=<args> Use this string to set Makefile.PL parameters
                            such as CONF or PREFIX for GBrowse 
                            installation
 --install_param_str=<args>
                           Use this string to predefine 'make install' 
                            parameters such as CONF or PREFIX for
                            GBrowse installation
 --wincvs                 WinCVS is present--allow cvs install on Windows 
 --gbrowse_path           Path to GBrowse tarball (will not download 
                            GBrowse); Assumes a resulting
                            'Generic-Genome-Browser' directory 
 --bioperl_path           Path to BioPerl tarball (will not download
                            BioPerl); Assumes a resulting'bioperl-live' 
                            directory
 --skip_start             Don't wait for 'Enter' at program start

=head1 DESCRIPTION

Net-based installer of GBrowse

Save this to disk as "gbrowse_netinstall.pl" and run:

   [sudo] perl gbrowse_netinstall.pl

=cut



# Universal Net-based installer
# Save this to disk as "gbrowse_netinstall.pl" and run:
#   perl gbrowse_netinstall.pl

use warnings;
use strict;
use CPAN;
use Config;
use Getopt::Long;
use Pod::Usage;
use File::Copy 'cp';
use File::Temp qw(tempdir);
use LWP::Simple;
use Cwd;

use constant NMAKE => 'http://download.microsoft.com/download/vc15/patch/1.52/w95/en-us/nmake15.exe';

my ( $show_help, $get_from_cvs, $build_param_string, $working_dir,
     $get_gbrowse_cvs, $get_bioperl_svn, $is_cygwin, $windows,
     $binaries, $make, $tmpdir, $wincvs, $gbrowse_path,$bioperl_path,
     $skip_start, $install_param_string, );

BEGIN {

  GetOptions(
        'h|help'              => \$show_help,             # Show help and exit
        'd|dev'               => \$get_from_cvs,          # Use the dev cvs
        'build_param_str=s'   => \$build_param_string,    # Build parameters
        'bioperl_dev'         => \$get_bioperl_svn,
        'gbrowse_dev'         => \$get_gbrowse_cvs,
        'wincvs'              => \$wincvs,
        'gbrowse_path=s'      => \$gbrowse_path,
        'bioperl_path=s'      => \$bioperl_path,
        'install_param_str=s' => \$install_param_string,
        'skip_start'          => \$skip_start,
        )
        or pod2usage(2);
  pod2usage(2) if $show_help;

  print STDERR "\nAbout to install GBrowse and all its prerequisites.\n";
  print STDERR "\nYou will be asked various questions during this process. You can almost always";
  print STDERR "\naccept the default answer (with a notable exception of libgd on MacOSX;\n";
  print STDERR "see the documentation on the GMOD website for more information.)\n";
  print STDERR "The whole process will take several minutes and will generate lots of messages.\n";
  print STDERR "\nNOTE: This installer will install bioperl-live, as the most recent GBrowse\n";
  print STDERR "requires the many changes that have gone into BioPerl since its last release\n\n";
  print STDERR "\nPress return when you are ready to start!\n";
  my $h = <> unless $skip_start;
  print STDERR "*** Installing Perl files needed for a net-based install ***\n";

  eval "CPAN::Config->load";
  eval "CPAN::Config->commit";

  $working_dir = getcwd;

  $tmpdir = tempdir(CLEANUP=>1) 
    or die "Could not create temporary directory: $!";

  $windows = $Config{osname} =~ /mswin/i;

  $binaries = $Config{'binexp'};
  $make     = $Config{'make'};

  if ($windows) {
    system("ppm install YAML");
  }
  else {
    CPAN::Shell->install('YAML');
  }
  CPAN::Shell->install('Archive::Zip');
  CPAN::Shell->install('HTML::Tagset');
  CPAN::Shell->install('LWP::Simple');
  eval "use Archive::Zip ':ERROR_CODES',':CONSTANTS'";

  if ($windows && !-e "$binaries/${make}.exe") {

    print STDERR "Installing make utility...\n";
    -w $binaries or die "$binaries directory is not writeable. Please re-login as Admin.\n";
    chdir $tmpdir;

    my $rc = mirror(NMAKE,"nmake.zip");
    die "Could not download nmake executable from Microsoft web site."
      unless $rc == RC_OK() or $rc == RC_NOT_MODIFIED();

    my $zip = Archive::Zip->new('nmake.zip') or die "Couldn't open nmake zip file for decompression: $!";
    $zip->extractTree == AZ_OK() or die "Couldn't unzip file: $!";
    -e 'NMAKE.EXE' or die "Couldn't extract nmake.exe";

    cp('NMAKE.EXE',"$binaries/${make}.EXE") or die "Couldn't install nmake.exe: $!";
    cp('NMAKE.ERR',"$binaries/${make}.ERR"); # or die "Couldn't install nmake.err: $!"; # not fatal
  }

  CPAN::Shell->install('Archive::Tar');
  #print STDERR $@;
  #print STDERR "at end of BEGIN{}\n";
  1;
};

#print STDERR "here i am\n";
#print STDERR $@;

use Archive::Tar;
use CPAN '!get';

$is_cygwin = 1 if ( $^O eq 'cygwin' );

if ($get_from_cvs) {
    $get_bioperl_svn = $get_gbrowse_cvs = 1;
}

if ($windows and !$wincvs and $get_gbrowse_cvs ) {
    die "\n\nThe development/cvs tags are not supported on Windows when\n"
        ."WinCVS is not installed; exiting...\n";
}

$build_param_string ||="";
$install_param_string ||="";

use constant BIOPERL_VERSION      => 'bioperl-1.5.2_103';
use constant BIOPERL_REQUIRES     => '1.005003';  # sorry for the redundancy
use constant BIOPERL_LIVE_URL     => 'http://bioperl.org/DIST/nightly_builds/';
use constant GBROWSE_DEFAULT      => '2.00';
use constant SOURCEFORGE_MIRROR1  => 'http://superb-west.dl.sourceforge.net/sourceforge/gmod/';
use constant SOURCEFORGE_MIRROR2  => 'http://easynews.dl.sourceforge.net/sourceforge/gmod/';
use constant SOURCEFORGE_GBROWSE  => 'http://sourceforge.net/project/showfiles.php?group_id=27707&package_id=34513';
use constant BIOPERL              => 'http://bioperl.org/DIST/'.BIOPERL_VERSION.'.tar.gz';

my %REPOSITORIES = ('BioPerl-Release-Candidates' => 'http://bioperl.org/DIST/RC',
		    'BioPerl-Regular-Releases'   => 'http://bioperl.org/DIST',
	            'Kobes'                      => 'http://theoryx5.uwinnipeg.ca/ppms',
                    'Bribes'                     => 'http://www.Bribes.org/perl/ppm');


# this is so that ppm can be called in a pipe
$ENV{COLUMNS} = 80; # why do we have to do this?
$ENV{LINES}   = 24;

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

print STDERR "\n*** Installing prerequisites for BioPerl ***\n";

if ($windows and !eval "use DB_File; 1") {
  print STDERR "Installing DB_File for BioPerl.\n";
  system("ppm install DB_File");
}
system("ppm install SVG") if $windows;
CPAN::Shell->install('GD::SVG');
CPAN::Shell->install('IO::String');
CPAN::Shell->install('Text::Shellwords');
CPAN::Shell->install('CGI::Session');
CPAN::Shell->install('File::Temp');
CPAN::Shell->install('Class::Base');
CPAN::Shell->install('Digest::MD5');
CPAN::Shell->install('Statistics::Descriptive');
CPAN::Shell->install('JSON');
CPAN::Shell->install('JSON::Any');

# recent versions of Module::Build fail to install without force!
CPAN::Shell->force(install=>'Module::Build') unless eval "require Module::Build; 1";

my $version = BIOPERL_REQUIRES;
if (!(eval "use Bio::Perl $version; 1") or $get_bioperl_svn or $bioperl_path) {
  print STDERR "\n*** Installing BioPerl ***\n";
  if ($windows and !$get_bioperl_svn and !$bioperl_path) {
    my $bioperl_index = find_bioperl_ppm();
    system("ppm install --force $bioperl_index");
  } else {
      do_install(BIOPERL,
		 'bioperl.tgz',
		 BIOPERL_VERSION,
		 'Build',
		 $get_bioperl_svn ? 'svn' : '',
		 '',
		 $bioperl_path);
  }
}
else {
  print STDERR "BioPerl is up to date.\n";
}

print STDERR "\n *** Installing Generic-Genome-Browser ***\n";

my $latest_version = find_gbrowse_latest();
my $gbrowse        = SOURCEFORGE_MIRROR1.$latest_version.'.tar.gz';
eval {do_install($gbrowse,
		 'gbrowse.tgz',
		 $latest_version,
		 'Build',
		 $get_gbrowse_cvs ? 'cvs' : '',
		 $build_param_string,
		 $gbrowse_path,
		 $install_param_string)};
if ($@ =~ /Could not download/) {
  print STDERR "Could not download: server down? Trying a different server...\n";
  $gbrowse        = SOURCEFORGE_MIRROR2.$latest_version.'.tar.gz';
  do_install($gbrowse,'gbrowse.tgz',$latest_version,'make',$get_gbrowse_cvs,$build_param_string,$install_param_string);
}

exit 0;

END {
  open STDERR,">/dev/null"; # windows has an annoying message when cleaning up temp file
}

sub do_install {
  my ($download,$local_name,$distribution,$method,
         $from_cvs,$build_param_string,$file_path,$install_param_string) = @_;

  chdir $tmpdir;

  do_get_distro($download,$local_name,$distribution,$from_cvs,$file_path);

  my $build_str = $windows ? "Build" : "./Build";

  if ($method eq 'make') {
      system("perl Makefile.PL $build_param_string") == 0
            or die "Couldn't run perl Makefile.PL command\n";
      system("$make install UNINST=1 $install_param_string")    == 0 ;
  }
  elsif ($method eq 'Build') {
      system("perl $build_str.PL --yes=1")   == 0
            or die "Couldn't run perl Build.PL command\n";
      system("$build_str install --uninst 1") == 0;
  }
}

sub do_get_distro {
    my ($download,$local_name,$distribution,$distribution_method,$file_path) = @_;

    if ($file_path) {
        chdir $working_dir;
        if (-e $file_path) { #must be an absolute path
            cp($file_path, "$tmpdir/$local_name");
        }
        elsif (-e "$working_dir/$file_path") { #assume it's a rel path from the original directory
            cp("$working_dir/$file_path", "$tmpdir/$local_name");
        }
        else {
            print "Couldn't find $file_path; nothing to do so quitting...\n";
            exit(-1);
        }
        $distribution = ($local_name =~ /gbrowse/)
                      ? "Generic-Genome-Browser" : "bioperl-live"; 
        chdir $tmpdir;
        extract_tarball($local_name,$distribution);
    }
    elsif ($distribution_method) {
        my $distribution_dir;
        if ($local_name =~ /gbrowse/) {
            $distribution_dir = 'Generic-Genome-Browser';
            print STDERR "\n\nPlease press return when prompted for a password.\n";
            unless (
              (system(
    "$distribution_method -d:pserver:anonymous\@gmod.cvs.sourceforge.net:/cvsroot/gmod login")==0
                or $is_cygwin)
              &&
              (system(
    "$distribution_method -z3 -d:pserver:anonymous\@gmod.cvs.sourceforge.net:/cvsroot/gmod co -kb -P Generic-Genome-Browser") == 0
                or $is_cygwin)
            )
            {
                print STDERR "Failed to check out the GBrowse from CVS: $!\n";
                return undef;
            }

        }
        else { #bioperl
            print STDERR "Downloading bioperl-live...\n";
            $distribution_dir = 'bioperl-live';

            my $filename = 'bioperl-live.tar.gz'; # =determine_filename();
            my $url = BIOPERL_LIVE_URL."/$filename";
            my $rc = mirror($url, $filename); 
            unless ($rc == RC_OK or $rc == RC_NOT_MODIFIED){
                print STDERR "Failed to get nightly bioperl-live file: $rc\n";
                return undef;
            }
            extract_tarball($filename,$distribution_dir);
            return 1;
        }
        chdir $distribution_dir
            or die "Couldn't enter $distribution_dir directory: $@";
    }
    else {
        print STDERR "Downloading $download...\n";
        my $rc = mirror($download,$local_name);
        die "Could not download $distribution distribution from $download."
            unless $rc == RC_OK or $rc == RC_NOT_MODIFIED;

        extract_tarball($local_name,$distribution);
    }
    return 1;
}

#this is probably not going to be needed again, as the nightly
#bioperl build names have been simplified
sub determine_filename {
  my $listing = "dirlisting.html";
  my $rc = mirror(BIOPERL_LIVE_URL, $listing);
  die "Could not get directory listing of bioperl nightly build url: $rc\n"
      unless ($rc == RC_OK or $rc == RC_NOT_MODIFIED);

  my $filename; 
  open LIST, $listing or die "unable to open $listing: $!\n";
  while (<LIST>) {
    if (/href="(bioperl-live.*?\.tar\.gz)"/) {
      $filename = $1;
      last;
    }
  }
  close LIST;
  unlink $listing; 
  return $filename;
}

sub extract_tarball {
  my ($local_name,$distribution) = @_;

  print STDERR "Unpacking $local_name...\n";
  my $z = Archive::Tar->new($local_name,1)
        or die "Couldn't open $distribution archive: $@";
  $z->extract()
        or die "Couldn't extract $distribution archive: $@";
  $distribution =~ s/--/-/;
  chdir $distribution
        or die "Couldn't enter $distribution directory: $@";
  return;
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
    my $multiplier = 10000000;
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
#  print STDERR "Looking up most recent version...";
  my $download_page = get(SOURCEFORGE_GBROWSE);
  my @files         = $download_page =~ /(Generic-Genome-Browser--?\d+\.\d+)/g;
  my %versions      = map {/(\d+\.\d+)/ => $_} @files;
  my @versions      = sort {$b<=>$a} keys %versions;
  my $version = $versions[0] || GBROWSE_DEFAULT ;
#  print STDERR $version,"\n";
  return $versions{$version};
}
