#!/usr/bin/perl

use lib './install_util';
use ExtUtils::MakeMaker;
use GuessDirectories;
use FindBin '$Bin';
use Config;
use Cwd;
require 5.005003;

my $VERSION = '1.64';
my $working_dir = cwd;

my @OPTIONS = qw(
                 APACHE
                 CONF HTDOCS CGIBIN
                 LIB
                 DO_XS NONROOT
                 PREFIX PREFIXSTRIP
                 INSTALLMAN1DIR INSTALLMAN3DIR
                );
my $OPTIONS = join ('|',@OPTIONS);
my %OPTIONS;

my @argv = @ARGV;
@ARGV = ();

#
# SET DEFAULT OPTIONS
#
$OPTIONS{INSTALLMAN1DIR} = $Config{installman1dir};
$OPTIONS{INSTALLMAN3DIR} = $Config{installman3dir};
$OPTIONS{INSTALLSCRIPT}  = $Config{installscript};
$OPTIONS{CONF}           = GuessDirectories->conf()   || "$Config{prefix}/etc/httpd/conf";
$OPTIONS{HTDOCS}         = GuessDirectories->htdocs() || "$Config{prefix}/var/www/html";
$OPTIONS{CGIBIN}         = GuessDirectories->cgibin() || "$Config{prefix}/var/www/cgi-bin";
$OPTIONS{DO_XS}          = $^O =~ /^(MSWin|dos)/i ? '' : 1;

foreach (@argv) {
  if (/^--?h/i) {
    die <<END;

LOW-LEVEL OPTIONS:

  INSTALLMAN1DIR  Install manpages here, default: $OPTIONS{INSTALLMAN1DIR}
  INSTALLMAN3DIR  Install manpages here, default: $OPTIONS{INSTALLMAN3DIR}
  INSTALLSCRIPT   Install Non-CGI scripts here.  default: $OPTIONS{INSTALLSCRIPT}
  CONF            Install CGI configuration files here.  default: $OPTIONS{CONF}
  HTDOCS          Install Documents to be served over HTTP here.  default: $OPTIONS{HTDOCS}
  CGIBIN          Install CGI scripts here.  default: $OPTIONS{CGIBIN}
  PREFIXSTRIP     Remove leading string from the value of PREFIX for PL_FILES and EXE_FILES

HIGH-LEVEL OPTIONS:

  APACHE          Prefix CONF, HTDOCS, and CGIBIN with this string
  PREFIX          Prefix CONF, HTDOCS, CGIBIN, INSTALLMAN1DIR, INSTALLMAN3DIR, and
                  INSTALLSCRIPT with this string.  Occurs after APACHE prefixing
  NONROOT         Set to 1 to suppress manpage installation.

To customize install locations, provide one or more of the options
APACHE, CONF, HTDOCS, or CGIBIN, as in CONF=/usr/local/apache/conf.

EXAMPLES:

Install to /tmp/gbrowse:
  /usr/bin/perl Makefile.PL \\
    PREFIX=/tmp/gbrowse \\
    INSTALLMAN1DIR=/usr/share/man/man1 \\
    INSTALLMAN3DIR=/usr/share/man/man3 \\
    LIB=`/usr/bin/perl -MConfig -e 'print $Config{sitelib}'`

Install to /usr/src/redhat/gbrowse, but keep PREFIX out of generated scripts:
  /usr/bin/perl Makefile.PL \\
    PREFIX=/tmp/gbrowse \\
    INSTALLMAN1DIR=/usr/share/man/man1 \\
    INSTALLMAN3DIR=/usr/share/man/man3 \\
    LIB=`/usr/bin/perl -MConfig -e 'print $Config{sitelib}'` \\
    PREFIXSTRIP=1

Install to default locations on a RPM-based RedHat/Fedora system:
    /usr/bin/perl Makefile.PL

Install to default locations for Apache built from source:
  /usr/bin/perl Makefile.PL \\
    APACHE=/usr/local/apache

Install under ~/gbrowse without requiring root privileges:
  /usr/bin/perl Makefile.PL \\
    APACHE=~/gbrowse \\
    LIB=~/gbrowse/lib \\
    INSTALLSCRIPT=~/gbrowse/bin \\
    NONROOT=1

will perform a non-privileged installation that places all gbrowse
components (including perl libraries) in the path ~/gbrowse.

In the above example, before running 'make install', create the
directories ~/gbrowse/html, ~gbrowse/cgi-bin and ~/gbrowse/conf

To make the CGI scipts aware of the custom library location, you can
either ask someone with root privileges to edit the apache
configuration file or define the environmental variable $PERL5LIB for
the owner of the httpd processes serving gbrowse.  Failing that, you
will want to add the line

  use lib "$ENV{HOME}/gbrowse/lib";

to each of the CGI scripts.

If you have a C compiler and wish to compile the XS extensions, set
DO_XS=1.  Currently all this does is to speed up the multiple
alignment plugin.
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

if (defined $OPTIONS{APACHE}) {
  $OPTIONS{CONF}   = $OPTIONS{APACHE} . $OPTIONS{CONF};
  $OPTIONS{HTDOCS} = $OPTIONS{APACHE} . $OPTIONS{HTDOCS};
  $OPTIONS{CGIBIN} = $OPTIONS{APACHE} . $OPTIONS{CGIBIN};
}
if (defined($OPTIONS{PREFIX})) {
  foreach my $k (keys %OPTIONS) {
    next if $k =~ /^PREFIX/; #skip PREFIX and PREFIXSTRIP
    next if $k eq 'DO_XS';
    next if $k eq 'NONROOT';
    $OPTIONS{$k} = $OPTIONS{PREFIX} . $OPTIONS{$k};
  }
}

# look for non-root installation
if (defined $OPTIONS{NONROOT}) {
  $OPTIONS{INSTALLMAN1DIR} = 'none';
  $OPTIONS{INSTALLMAN3DIR} = 'none';
}

push @ARGV, "LIB=$OPTIONS{LIB}" if $OPTIONS{LIB};

#different perl versions use INSTALLSITE vs INSTALL
push @ARGV, "INSTALLMAN1DIR=$OPTIONS{INSTALLMAN1DIR}" if $OPTIONS{INSTALLMAN1DIR};
push @ARGV, "INSTALLMAN3DIR=$OPTIONS{INSTALLMAN3DIR}" if $OPTIONS{INSTALLMAN3DIR};
push @ARGV, "INSTALLSITEMAN1DIR=$OPTIONS{INSTALLMAN1DIR}" if $OPTIONS{INSTALLMAN1DIR};
push @ARGV, "INSTALLSITEMAN3DIR=$OPTIONS{INSTALLMAN3DIR}" if $OPTIONS{INSTALLMAN3DIR};

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
  printf STDERR "%15s %s\n",$_,$OPTIONS{$_};
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
				 Bio::Perl         => 1.5,
				 GD                => 2.07,
				 IO::String        => 0,
				 Text::Shellwords  => 1.0,
				 Template          => 2.0,
				 Log::Log4perl     => 0, 
				}, # e.g., Module::Name => 1.1
	      PL_FILES       => {
                             'install_util/htdocs_install.PLS' => 'install_util/htdocs_install.pl',
                             'install_util/cgi_install.PLS' => 'install_util/cgi_install.pl',
                             'install_util/conf_install.PLS' => 'install_util/conf_install.pl',
                             'bin/make_das_conf.PLS' => 'bin/make_das_conf.pl',
                             'bin/process_sgd.PLS' => 'bin/process_sgd.pl',
                             'bin/process_gadfly.PLS' => 'bin/process_gadfly.pl',
                             'bin/process_wormbase.PLS' => 'bin/process_wormbase.pl',
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
                             'cgi-bin/das.PLS'          => 'cgi-bin/das',
                             'conf/MobyServices/GbrowseServices.PMS'  => 'conf/MobyServices/GbrowseServices.pm',
				 },
	      EXE_FILES      => [
                             'bin/register_moby_services.pl',
                             'bin/make_das_conf.pl',
                             'bin/process_wormbase.pl',
                             'bin/process_sgd.pl',
                             'bin/process_gadfly.pl',
                             'bin/load_genbank.pl',
                            ],
	      'LIBS'	     => [''], # e.g., '-lm'
	      'LIB'          => $OPTIONS{LIB}, # custom location for perl modules
	      'DIR'          => $OPTIONS{DO_XS} ? ['libalign'] : [],
	      'DEFINE'	     => '',
	      'INC'	     => '', # e.g., '-I/usr/include/other'
              ($] ge '5.005') ? (
                  'AUTHOR'   => 'Lincoln Stein (lstein@cshl.org)',
                  'ABSTRACT' => 'A CGI-driven browser for genomic annotations.',
                                ) : (),
              'INSTALLSITEMAN1DIR' => $OPTIONS{INSTALLSITEMAN1DIR}, # don't install man pages for
              'INSTALLSITEMAN3DIR' => $OPTIONS{INSTALLSITEMAN3DIR}, # non-root user
              'INSTALLSCRIPT'      => $OPTIONS{INSTALLSCRIPT}
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

sub MY::dist_dir {
  package MY;
  my $inherited = shift->SUPER::dist_dir(@_);
  $inherited =~ s!^(\s+.+)!\tpod2text docs/pod/INSTALL.pod > INSTALL\n$1!m;
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
  my $prefix = $OPTIONS{PREFIX} || '';
  for my $key (keys %OPTIONS) {
    $paths .= qq('$key=$OPTIONS{$key}' ) if defined $OPTIONS{$key};
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
	\@\$(TAR) zcf gbrowse_ppm-$VERSION.tar.gz --exclude man1 --exclude man3 blib
	\@perl -pi -e 's!HREF=""!HREF="$repository/gbrowse_ppm-$VERSION.tar.gz"!' Generic-Genome-Browser.ppd
	\@perl -pi -e 's!(\\s*</IMPLEMENTATION>)!\\t\\t<INSTALL HREF="$repository/gbrowse_ppm_install.pl" EXEC="PPM_PERL" />\\n\\1!' Generic-Genome-Browser.ppd
	\@perl -pi -e 's!Bio-Perl!bioperl!' Generic-Genome-Browser.ppd
END
;
}


