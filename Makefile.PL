#!/usr/bin/perl

use lib './install_util';
use ExtUtils::MakeMaker;
use GuessDirectories;
use FindBin '$Bin';
use Cwd;
require 5.005003;

my $VERSION = '1.59';
my $working_dir = cwd;

my @OPTIONS = qw(PREFIX CONF HTDOCS CGIBIN DO_XS);
my $OPTIONS = join ('|',@OPTIONS);
my %OPTIONS;

my @argv = @ARGV;
@ARGV = ();

foreach (@argv) {
  if (/^--?h/i) {
    die <<END;
To customize install locations, provide one or more of the options
PREFIX, CONF, HTDOCS, or CGIBIN, as in CONF=/usr/local/apache/conf.

For RedHat Linux, you will want to use:
    perl Makefile.PL CONF=/etc/httpd/conf \\
                     HTDOCS=/var/www/html \\
                     CGIBIN=/var/www/cgi-bin

For most versions of Apache built from source code, use:
    perl Makefile.PL PREFIX=/usr/local/apache

If you have a C compiler and wish to compile the XS extensions, set
DO_XS=1.  Currently all this does is to speed up the
multiple alignment plugin.
END
;
  }

  elsif (/($OPTIONS)=(.+)/og) {
    $OPTIONS{$1} = interpolate($2);
  }

  else {
    push @ARGV,$_;
  }
}

if (-e 'GGB.def' && !%OPTIONS) {
  print STDERR "\nShould I use your previous settings to set the file paths and options (y/n) [y]? ";
  chomp (my $line = <>);
  if (!$line || $line =~ /^[yY]/) {
    print STDERR "Using previous settings for file paths and options.\n";
    open F,'GGB.def' or die "GGB.def: $!";
    while (<F>) {
      chomp;
      next if /^\#/;
      next unless /^($OPTIONS)=(.+)/o;
      $OPTIONS{$1} = interpolate($2);
    }
    close F;
  }
}

if ($OPTIONS{PREFIX} && !(defined $OPTIONS{CONF})) {
  $OPTIONS{CONF} = "$OPTIONS{PREFIX}/conf";
}
if ($OPTIONS{PREFIX} && !(defined $OPTIONS{HTDOCS})) {
  $OPTIONS{HTDOCS} = "$OPTIONS{PREFIX}/htdocs";
}
if ($OPTIONS{PREFIX} && !(defined $OPTIONS{CGIBIN})) {
  $OPTIONS{CGIBIN} = "$OPTIONS{PREFIX}/cgi-bin";
}

# set hard-coded values
$OPTIONS{PREFIX} ||= '/usr/local/apache';
unless ($OPTIONS{CONF}) {
  $OPTIONS{CONF} = GuessDirectories->conf || "$OPTIONS{PREFIX}/conf";
}
unless ($OPTIONS{HTDOCS}) {
  $OPTIONS{HTDOCS} = GuessDirectories->htdocs || "$OPTIONS{PREFIX}/htdocs";
}
unless ($OPTIONS{CGIBIN}) {
  $OPTIONS{CGIBIN} = GuessDirectories->cgibin || "$OPTIONS{PREFIX}/cgi-bin";
}
unless (defined $OPTIONS{DO_XS}) {
  $OPTIONS{DO_XS}  = $^O =~ /^(MSWin|dos)/i ? '' : 1;
}

# workaround for known bug in FindBin library
$Bin = "." if -f './Makefile.PL' && -T './Makefile.PL';

open F,">$Bin/GGB.def" or die "Can't open $Bin/GGB.def for writing: $!";
print F "# This hints file contains configuration information used by the generic browser\n\n";
print F "# To reconfigure, run perl Makefile.PL `cat GGB.def`\n\n";
foreach (keys %OPTIONS) {
  print F "$_=$OPTIONS{$_}\n";
}
print F "VERSION=$VERSION\n";
close F;

print STDERR <<END;
----------------------------------------------
                File Paths

END
;
foreach (@OPTIONS) {
  printf STDERR "%7s %s\n",$_,$OPTIONS{$_};
}
print STDERR <<END;

(Run perl Makefile.PL -h for help on changing)
----------------------------------------------
END
;


# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	      'NAME'	     => 'Generic-Genome-Browser',
	      'VERSION'      => $VERSION,
	      'PREREQ_PM'    => {
				 Bio::Perl     => 1.02,
				 GD            => 2.07,
				 IO::String    => 0,
				 Text::Shellwords  => 1.0,
				}, # e.g., Module::Name => 1.1
	      PL_FILES       => {
                                 'install_util/htdocs_install.PLS' => 'install_util/htdocs_install.pl',
                                 'install_util/cgi_install.PLS' => 'install_util/cgi_install.pl',
                                 'install_util/conf_install.PLS' => 'install_util/conf_install.pl',
				 'bin/process_sgd.PLS' => 'bin/process_sgd.pl',
				 'bin/process_gadfly.PLS' => 'bin/process_gadfly.pl',
				 'bin/process_wormbase.PLS' => 'bin/process_wormbase.pl',
				 'bin/process_ncbi_human.PLS' => 'bin/process_ncbi_human.pl',
				 'bin/ucsc_genes2gff.PLS' => 'bin/ucsc_genes2gff.pl',
				 'bin/load_genbank.PLS' => 'bin/load_genbank.pl',
				 'bin/register_moby_services.PLS' => 'bin/register_moby_services.pl',
				 'install_util/gbrowse_ppm_install.PLS' => 'gbrowse_ppm_install.pl',
				 'cgi-bin/gbrowse.PLS'  => 'cgi-bin/gbrowse',
				 'cgi-bin/gbrowse_syn.PLS'  => 'cgi-bin/gbrowse_syn',
				 'cgi-bin/gbrowse_img.PLS'  => 'cgi-bin/gbrowse_img',
				 'cgi-bin/gbrowse_details.PLS'  => 'cgi-bin/gbrowse_details',
				 'cgi-bin/gbrowse_est.PLS'  => 'cgi-bin/gbrowse_est',
				 'cgi-bin/gbrowse_moby.PLS'  => 'cgi-bin/gbrowse_moby',
				 'cgi-bin/moby_server.PLS'  => 'cgi-bin/moby_server',
				 'conf/MobyServices/GbrowseServices.PMS'  => 'conf/MobyServices/GbrowseServices.pm',
				 },
	      EXE_FILES      => [
				 'bin/process_wormbase.pl',
				 'bin/process_sgd.pl',
				 'bin/process_gadfly.pl',
				 'bin/process_ncbi_human.pl',
                                 'bin/load_genbank.pl',
				],
	      'LIBS'	     => [''], # e.g., '-lm'
	      'DIR'          => $OPTIONS{DO_XS} ? ['libalign'] : [],
	      'DEFINE'	     => '',
	      'INC'	     => '', # e.g., '-I/usr/include/other'
              ($] ge '5.005') ? (
                  'AUTHOR'   => 'Lincoln Stein (lstein@cshl.org)',
                  'ABSTRACT' => 'A CGI-driven browser for genomic annotations.',
                                ) : (),
);

sub interpolate {
  my $path = shift;
  my ($to_expand,$homedir);
  return $path unless $path =~ m!^~([^/]*)!;
  eval {
    if ($to_expand = $1) {
      $homedir = (getpwnam($to_expand))[7];
    } else {
      $homedir = (getpwuid($<))[7];
    }
    return $path unless $homedir;

    $path =~ s!^~[^/]*!$homedir!;
  };
  return $path;
}

sub MY::clean {
  package MY;
  my $inherited = shift->SUPER::clean(@_);
  $inherited .= "\t-\$(PERL) install_util/make_clean_add.pl\n";
  $inherited;
}

sub MY::processPL {
  package MY;
  my $inherited = shift->SUPER::processPL(@_);
  $inherited =~ s/(cgi-bin\/gbrowse\w*)\s\:\:.+/$1 : FORCE/g;
  $inherited;
}

sub MY::install {
  package MY;
  my $inherited = shift->SUPER::install(@_);
  $inherited =~ s/doc_install/doc_install conf_install cgi_install htdocs_install/;
  $inherited;
}

sub MY::postamble {
  my $paths;
  for my $key (keys %OPTIONS) {
    $paths .= qq('$key=$OPTIONS{$key}' );
  }
qq{
conf_install ::
	\$(PERL) \"$working_dir/install_util/conf_install.pl\" $paths

htdocs_install ::
	\$(PERL) \"$working_dir/install_util/htdocs_install.pl\" $paths

cgi_install ::
	\$(PERL) \"$working_dir/install_util/cgi_install.pl\" $paths

};
}

sub MY::ppd {
  package MY;
  my $repository = 'http://www.gmod.org/ggb/ppm';
  my $arch       = 'MSWin32-x86-multi-thread';
  my $inherited = shift->SUPER::ppd(@_);

  my $implementation;
  my $newimp;
  my $oldMM =0;

#VERY irritating--different versions of ExtUtils::MakeMaker has
#different ways of generating the ppd file.
  if ($inherited =~ /qq\{(<S.*R>\\n)\}.*qq\{(\\t<I.*\/>\\n)\}.*qq\{(\\t\\t<O.*G>\\n)\}/sg){
    $oldMM=1;
    my $xml = $1.$2.$3;
    #warn "$xml\n";
    $inherited =~ s/qq\{.*>>/qq{$xml}" >/s;
  } elsif ($inherited =~ /NOECHO/) {
    my @la = split /\n/, $inherited;
    my $grab = 0;
    for (@la) {
      $grab++ if (m!<IMPLEMENTATION>!); 
      if ($grab and $_ =~ /\'(.*)\'/) {
        $implementation .= "$1\n";
      }
      $grab = 0 if (m!</IMPLEMENTATION>!);
    } 
  }

  if ($oldMM and $inherited =~ /(\s*\<IMPLEMENTATION\>.*\<\/IMPLEMENTATION\>)/m) {
    $implementation = $newimp = $1;
    $newimp      =~ s/ARCHITECTURE NAME=\\"\S+\\"/ARCHITECTURE NAME=\\"$arch\\"/;
    $newimp      =~ s/\$\(OSNAME\)/MSWin32/;
    my $impl58   = $newimp;
    $impl58      =~ s/\Q$arch\E/$arch\-5\.8/;
    $newimp      .= "\\n\\t\\t$impl58";
    $inherited   =~ s/\Q$implementation\E/$newimp/;
  } elsif (!$oldMM and $implementation) {
    $newimp      = $implementation;
    $newimp      =~ s/ARCHITECTURE NAME="\S+"/ARCHITECTURE NAME="$arch"/;
    $newimp      =~ s/\$\(OSNAME\)/MSWin32/;
    my $impl58   = $newimp;
    $impl58      =~ s/\Q$arch\E/$arch\-5\.8/;
    $newimp      .= $impl58;
    my @la       = split /\n/, $newimp;
    for my $line (@la) {
      $line = qq{\t\$(NOECHO) \$(ECHO) '$line' >> \$(DISTNAME).ppd}; 
    }

    my @inherit_array = split /\n/, $inherited;
    my @newinherit;
    $inherited = '';
    for (@inherit_array) {
      if (/<IMPLEMENTATION>/) {
        push @newinherit, @la;
        last;
      } else {
        push @newinherit, $_; 
      }
    }
    push @newinherit, qq{\t\$(NOECHO) \$(ECHO) '</SOFTPKG>' >> \$(DISTNAME).ppd\n};
    $inherited = join "\n", @newinherit;
  }

  $inherited .= <<END;

	\@echo "creating Generic-Genome-Browser.ppd"
	\@echo "creating gbrowse_ppm_support_files-$VERSION.tar.gz"
	\@\$(TAR) zcf gbrowse_ppm_support_files-$VERSION.tar.gz --exclude CVS --exclude '*~' --exclude '*.PLS' --exclude '.*' --exclude README --exclude '#*' DISCLAIMER INSTALL docs htdocs conf cgi-bin install_util sample_data contrib
	\@echo "creating gbrowse_ppm-$VERSION.tar.gz"
	\@\$(TAR) zcf gbrowse_ppm-$VERSION.tar.gz --exclude man1 blib
	\@perl -pi -e 's!HREF=""!HREF="$repository/gbrowse_ppm-$VERSION.tar.gz"!' Generic-Genome-Browser.ppd
	\@perl -pi -e 's!(\\s*</IMPLEMENTATION>)!\\t\\t<INSTALL HREF="$repository/gbrowse_ppm_install.pl" EXEC="PPM_PERL" />\\n\\1!' Generic-Genome-Browser.ppd
	\@perl -pi -e 's!Bio-Perl!bioperl!' Generic-Genome-Browser.ppd
END
;
}


