#!/usr/bin/perl

=head1 NAME

gbrowse_netinstall.pl

=head1 SYNOPSIS

  gbrowse_netinstall.pl -b|--build_param_str BUILD_STRING [options]

  options:
  -h|--help            : Show this message
  -d|--dev             : Use the developement version of both GBrowse and
                         bioperl from CVS
  --bioperl_dev        : Use the development version of BioPerl from CVS
  --gbrowse_dev        : Use the development version of GBrowse from CVS
  -b|--build_param_str : Use this string to predefine Makefile.PL parameters
                         such as CONF or PREFIX for GBrowse installation

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
use Config;
use Getopt::Long;
use Pod::Usage;

my ( $show_help, $get_from_cvs, $build_param_string, 
     $get_gbrowse_cvs, $get_bioperl_cvs );

BEGIN {

  GetOptions(
        'h|help'              => \$show_help,             # Show help and exit
        'd|dev'               => \$get_from_cvs,          # Use the dev cvs
        'b|build_param_str=s' => \$build_param_string,    # Build parameters
        'bioperl_dev'         => \$get_bioperl_cvs,
        'gbrowse_dev'         => \$get_gbrowse_cvs,
        )
        or pod2usage(2);
  pod2usage(2) if $show_help;


  print STDERR "\nAbout to install GBrowse and all its prerequisites.\n";
  print STDERR "\nYou will be asked various questions during this process. You can almost always";
  print STDERR "\naccept the default answer (with a notable exception of libgd on MacOSX;\n";
  print STDERR "see the documetation on the GMOD website for more information.)\n";
  print STDERR "The whole process will take several minutes and will generate lots of messages.\n";
  print STDERR "\nPress return when you are ready to start!\n";
  my $h = <>;
  print STDERR "*** Installing Perl files needed for a net-based install ***\n";
  eval {
    use CPAN qw{install};
    eval "use CPAN::Config;"; 
    if ($@) {
        CPAN::Shell->Config();
    }

    CPAN::Shell->install('Archive::Zip');
    CPAN::Shell->install('HTML::Tagset');
    CPAN::Shell->install('LWP::Simple');
    CPAN::Shell->install('Archive::Tar');
    CPAN::HandleConfig->commit;
  }
}

use File::Temp qw(tempdir);
use LWP::Simple;
use Archive::Zip ':ERROR_CODES';
use Archive::Tar;
use File::Copy 'cp';
use CPAN '!get';

if ($get_from_cvs) {
    $get_bioperl_cvs = $get_gbrowse_cvs = 1;
}
$build_param_string ||="";

use constant BIOPERL_VERSION      => 'bioperl-1.5.2_102';
use constant BIOPERL_REQUIRES     => '1.005002';  # sorry for the redundancy
use constant GBROWSE_DEFAULT      => '1.68';
use constant SOURCEFORGE_MIRROR1  => 'http://superb-west.dl.sourceforge.net/sourceforge/gmod/';
use constant SOURCEFORGE_MIRROR2  => 'http://easynews.dl.sourceforge.net/sourceforge/gmod/';
use constant SOURCEFORGE_GBROWSE  => 'http://sourceforge.net/project/showfiles.php?group_id=27707&package_id=34513';
use constant BIOPERL              => 'http://bioperl.org/DIST/'.BIOPERL_VERSION.'.tar.gz';
use constant NMAKE                => 'http://download.microsoft.com/download/vc15/patch/1.52/w95/en-us/nmake15.exe';

my %REPOSITORIES = ('BioPerl-Release-Candidates' => 'http://bioperl.org/DIST/RC',
		    'BioPerl-Regular-Releases'   => 'http://bioperl.org/DIST',
	            'Kobes'                      => 'http://theoryx5.uwinnipeg.ca/ppms',
                    'Bribes'                     => 'http://www.Bribes.org/perl/ppm');

my $binaries = $Config{'binexp'};
my $make     = $Config{'make'};

# this is so that ppm can be called in a pipe
$ENV{COLUMNS} = 80; # why do we have to do this?
$ENV{LINES}   = 24;

my $tmpdir = tempdir(CLEANUP=>1) 
    or die "Could not create temporary directory: $!";
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

print STDERR "\n*** Installing prerequisites for BioPerl ***\n";
CPAN::Shell->install('GD::SVG');
CPAN::Shell->install('IO::String');
CPAN::Shell->install('Text::Shellwords');
CPAN::Shell->install('CGI::Session');
CPAN::Shell->install('File::Temp');
CPAN::Shell->install('Class::Base');
CPAN::Shell->install('Digest::MD5');

my $version = BIOPERL_REQUIRES;
if (!(eval "use Bio::Perl $version; 1") or $get_bioperl_cvs) {
  print STDERR "\n*** Installing BioPerl ***\n";
  if ($windows) {
    my $bioperl_index = find_bioperl_ppm();
    system("ppm install $bioperl_index");
  } else {
      CPAN::Shell->install('Module::Build');
      do_install(BIOPERL,'bioperl.tgz',BIOPERL_VERSION,'Build',$get_bioperl_cvs);
  }
}
else {
  print STDERR "BioPerl is up to date.\n";
}

print STDERR "\n *** Installing Generic-Genome-Browser ***\n";

my $latest_version = find_gbrowse_latest();
my $gbrowse        = SOURCEFORGE_MIRROR1.$latest_version.'.tar.gz';
eval {do_install($gbrowse,'gbrowse.tgz',$latest_version,'make',$get_gbrowse_cvs,$build_param_string)};
if ($@ =~ /Could not download/) {
  print STDERR "Could not download: server down? Trying a different server...\n";
  $gbrowse        = SOURCEFORGE_MIRROR2.$latest_version.'.tar.gz';
  do_install($gbrowse,'gbrowse.tgz',$latest_version,'make',$get_gbrowse_cvs,$build_param_string);
}

exit 0;

END {
  open STDERR,">/dev/null"; # windows has an annoying message when cleaning up temp file
}

sub do_install {
  my ($download,$local_name,$distribution,$method,
                     $from_cvs,$build_param_string) = @_;

  chdir $tmpdir;

  do_get_distro($download,$local_name,$distribution,$from_cvs);

  if ($method eq 'make') {
      system("perl Makefile.PL") == 0
            or die "Couldn't run perl Makefile.PL command\n";
      system("$make install UNINST=1 $build_param_string")    == 0 ;
  }
  elsif ($method eq 'Build') {
      system("perl ./Build.PL")   == 0
            or die "Couldn't run perl Build.PL command\n";
      system("./Build install --uninst 1") == 0;
  }
}

sub do_get_distro {
    my ($download,$local_name,$distribution,$from_cvs) = @_;

    if ($from_cvs) {
        my $distribution_dir;
        if ($local_name =~ /gbrowse/) {
            $distribution_dir = 'Generic-Genome-Browser';
            print STDERR "\n\nPlease press return when prompted for a password.\n";
            unless (
            system(
                'cvs -d:pserver:anonymous@gmod.cvs.sourceforge.net:/cvsroot/gmod login'
                    . ' && '
                    . 'cvs -z3 -d:pserver:anonymous@gmod.cvs.sourceforge.net:/cvsroot/gmod co -P -r stable Generic-Genome-Browser'
            ) == 0
            )
            {
                print STDERR "Failed to check out the GBrowse from CVS: $!\n";
                return undef;
            }

        }
        else { #bioperl
            $distribution_dir = 'bioperl-live';
            print STDERR "\n\nPlease enter 'cvs' when prompted for a password.\n";
            unless (
            system(
                'cvs -d :pserver:cvs@code.open-bio.org:/home/repository/bioperl login'
                    . ' && '
                    . 'cvs -z3 -d:pserver:cvs@code.open-bio.org:/home/repository/bioperl checkout bioperl-live'
            ) == 0
            )
            {
                print STDERR "Failed to check out the GBrowse from CVS: $!\n";
                return undef;
            }
        }
        chdir $distribution_dir
            or die "Couldn't enter $distribution_dir directory: $@";
    }
    else {
        print STDERR "Downloading $download...\n";
        my $rc = mirror($download,$local_name);
        die "Could not download $distribution distribution from $download."
            unless $rc == RC_OK or $rc == RC_NOT_MODIFIED;

        print STDERR "Unpacking $local_name...\n";
        my $z = Archive::Tar->new($local_name,1)
            or die "Couldn't open $distribution archive: $@";
        $z->extract()
            or die "Couldn't extract $distribution archive: $@";
        $distribution =~ s/--/-/;
        chdir $distribution
            or die "Couldn't enter $distribution directory: $@";
    }
    return 1;
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
  my @files         = $download_page =~ /(Generic-Genome-Browser--?\d+\.\d+)/g;
  my %versions      = map {/(\d+\.\d+)/ => $_} @files;
  my @versions      = sort {$b<=>$a} keys %versions;
  my $version = $versions[0] || '1.67';
  print STDERR $version,"\n";
  return $versions{$version};
}
