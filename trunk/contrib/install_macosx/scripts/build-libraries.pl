#!/usr/bin/perl
# $Id: build-libraries.pl,v 1.3 2005-12-09 22:19:09 mwz444 Exp $

=pod

=head1 DESCRIPTION
 
  build-libraries.pl - build a variety of useful libraries

=head1 SYNPOSIS

 Usage build-libraries.pl [options...]

 Options:
    --self_contained full path. Build everything within this path.
    --package        Move build directories to the package dir
    --version        version of package for generating documentation

=head1 NOTES

This script simplifies the process of building a variety of libraries
required for the Generic Genome Browser and BioPerl. It can also be
used to construct a package of these libraries.

=head2 Creating a local installation
   
  build-libraries.pl

All libraries will be built in /usr/local. Perl modules will be
installed in /Library/Perl.

=head2 Building a self-contained package

  build-libraries.pl --self_contained /usr/local/libraries-october

Will cause all files to be built in a flat directory structure
suitable for generating a self-contained pacakge. After building, use
PackageMaker and point it to the directory provided in
--self_contained.  Alternatively, you can pass the --package option
(see below) to have these directories automatically moved into the
package path.

=head2 Building a package within standard local paths

  build-libraries.pl --package

You can also easily build a package using local paths. To simplify
this process, you should pass the --package (boolean) flag. This will
cause three things to happen.  First, all system directories that the
build process touches will be backed up (to $dir.bak). Empty
directories with the same name will be created.  Following the build,
these directories are then copied to predfined package directory.
Finally, the backup directories are restored to their original name.

=head1 AUTHOR

  Todd Harris (harris@cshl.org)
  Version: $Id: build-libraries.pl,v 1.3 2005-12-09 22:19:09 mwz444 Exp $
  Copyright @ 2003 Cold Spring Harbor Laboratory
  $Z<>Revision$

=cut

#'

use CPANPLUS::backend;
use CPANPLUS::Configure;
use Getopt::Long;
use Pod::Usage;
use lib '../';
use BuildConfig;
use strict;

my ($self_contained,$package,$version,$help);
GetOptions('self_contained=s'=> \$self_contained,
	   'version=s'       => \$version,
	   'package'         => \$package,
	   'help=s'          => \$help,
	  );

pod2usage(-verbose=>2) if ($help);

my $config = BuildConfig->new(-self_contained => $self_contained,
			      -version        => $version,
			      -components     => 'libraries',
			      -package        => $package,
			      -script_path    => 'libraries',
			     );

# Here is a list of straightforward Perl modules that require
# no additional modification outside of specifiying their path

my @EASY_INSTALLS = (qw/
		     HTML::Tagset
		     HTML::TokeParser
		     Bundle::LWP
		     IO::Scalar
		     IO::String
                     URI
		     File::Temp
		     Storable	
		     Text::Balanced
		     Parse::RecDescent
		     Text::Shellwords
		     Digest::MD5
		     DBI
		     Statistics::OLS
		     Log::Agent
		     SVG
		     CGI::Cache
		     /);

my @XML_MODULES = (qw/
		   XML::Parser
		   XML::Twig
		   XML::Writer
		   XML::DOM
		   XML::Parser::PerlSAX
		   XML::RegExp
	   /);


# Fetch out some global paths
my $bin     = $config->bin;
my $build   = $config->build;
my $include = $config->include;
my $lib     = $config->lib;
my $local   = $config->local_path;
my $man1    = $config->man1;
my $man3    = $config->man3;
my $man5    = $config->man5;
my $perllib = $config->perllib;

# Make sure the PERLLIB is in my @INC
# Can I do this script wide or does it need to be done for each system call...
$ENV{PERL5LIB} = $perllib;

# CPANPLUS OPTIONS
my $USE_FORCE = 1;
my $FLUSH     = 0;

my $cpan_config = new CPANPLUS::Configure;
# Most mods will just ignore the EXPAT directives...
$cpan_config->set_conf('makemakerflags'  => { INSTALLMAN3DIR => $config->man3,
					      INSTALLMAN1DIR => $config->man1,
					      LIB            => $config->perllib,
					      EXPATLIBPATH   => $config->lib,
					      EXPATINCPATH   => $config->include,
					    },
		       'flush'           => $FLUSH,
		       'prereqs'         => 1,
		      );

# Ya only get one CPAN object? Huh? No destructor?
my $cpan = new CPANPLUS::Backend($cpan_config);

my @dirs = ($bin,$include,$lib,$local,$man1,$man3,$man5,$perllib);

$config->create_directories(\@dirs);
build_libraries();
$config->move_build_to_package() if ($package);

# Generate the ReadMes and scripts for the package
print_readme();
#print_welcome();

#################################################################
##                       END MAIN
#################################################################


sub build_libraries {
  cpan_installs(\@EASY_INSTALLS,'basic');
  build_zlib();
  build_libjpeg();
  build_libpng();
  ###  build_freetype();  # unnecessary
  ###  build_libiconv();  # unnecessary
  build_readline();   # The AceDB package builds this as well - oh well...
  build_libgd();
  build_GD();
  build_expat();
  build_aceperl();
  cpan_installs(\@XML_MODULES,'basic');  # XML modules

  # XML dependencies satisfied, let's install SOAP::Lite
  # Also installs: MIME::Lite, Mime::Parser, MIME::Tools, Mail::Tools, etc
  cpan_installs([qw/SOAP::Lite/],'basic');
  build_DBD();
  build_bioperl();
}

# Try flushing the cahce
sub cpan_installs {
  my ($modules,$type) = @_;
  foreach my $module (@$modules) {
    my $module_obj = $cpan->module_tree()->{$module};
    
    # force install, because the package list might just say it is
    # already there...
    my $result  = $module_obj->install(force=>1);
    my $path    = $module_obj->pathname();
    my $version = $module_obj->version();
    
    # Flush the perl5lib cache to ensure that newly installed modules
    # become part of our @INC.
    $cpan->flush('lib');
    $config->stuff_results($module,$result,$version,$path);
  }
}

########
# zlib #
########
sub build_zlib {
  my $version = $config->version('zlib');
  my $url     = $config->url('zlib');
  my $file    = "zlib-$version.tar.gz";
  my $command=<<END;
  set -x
   cd $build
   setenv PERL5LILB $perllib; export PERL5LIB
   printenv
   if [ -e "$file" ]; then
    echo "$file already fetched"
  else
     curl -O $url/$file
  fi
  gnutar xzf $file
  pushd zlib-$version/
  ./configure --prefix=$local
  make
  make install
  ranlib $lib/libz.a
  popd
END
  
  my $result = system($command);
  $config->stuff_results('zlib',$result,$version,$local);
}


###########
# libjpeg #
###########
sub build_libjpeg {
  my $version = $config->version('libjpeg');
  my $url     = $config->url('libjpeg');
  my $file    = "jpegsrc.v$version.tar.gz";
  my $command=<<END;
  set -x
  cd $build
  if [ -e "$file" ]
   then
     echo "$file already downloaded"
  else
     curl -O $url/$file
  fi
  gnutar xzf $file
  pushd jpeg-$version/
  ./configure --prefix=$local --mandir=$man1
  make
  make install 
  make install-lib
  ranlib $lib/libjpeg.a
  popd
END

  my $result = system($command);
  $config->stuff_results('libjpeg',$result,$version,$local);
}


##########
# libpng #
##########
sub build_libpng {
  my $version = $config->version('libpng');
  my $url     = $config->url('libpng');
  my $file    = "libpng-$version.tar.gz";
  my $command=<<END;
  set -x
  cd $build
  if [ -e "$file" ]
  then
    echo "$file already fetched"
  else
    curl -O $url/$file
  fi
  gnutar -xzf $file
  pushd libpng-$version/
  # Replace the prefix directive in the makefile...
  cp scripts/makefile.darwin makefile
  perl -p -i -e "s|prefix=\/usr\/local|prefix=$local|g" makefile
  make ZLIBINC="$include" ZLIBLIB="$lib"
  make install
  ranlib $lib/libpng.a
  popd
END

  my $result = system($command);
  $config->stuff_results('libpng',$result,$version,$lib);
}



######
# freetype (version 1)
######
sub build_freetype {
  my $version = $config->version('libfreetype');
  my $url     = $config->url('libfreetype');
  my $file    = "freetype-$version.tar.gz";
  my $command=<<END;
  set -x
  cd $build
  if [ -e "$file" ]
  then
    echo "$file already fetched"
  else
    curl -O $url/$file
  fi
  gnutar -zxf $file
  pushd freetype-$version/
   cp /usr/share/libtool/config.guess .
   cp /usr/share/libtool/config.sub .
  ./configure --prefix=/usr/local
  make
  make install
  popd
END

  my $result = system($command);
  $config->stuff_results('libfreetype',$result,$version,$local);
}

######
# libiconv  (This shouldn't be necessary...)
######
sub build_libiconv {
  my $version = $config->version('libiconv');
  my $url     = $config->url('libiconv');
  my $file    = "libiconv-$version.tar.gz";
  my $command=<<END;
  set -x
  cd $build
  if [ -e "$file" ]
  then
    echo "$file already fetched"
  else
    curl -O $url/$file
  fi
  gnutar -zxf $file
  pushd libiconv-$version/
  ./configure --prefix=$local
  make
  make install
  ranlib $lib/libiconv.la
  popd
END

#   cp /usr/share/libtool/config.guess .
#   cp /usr/share/libtool/config.sub .


  my $result = system($command);
  $config->stuff_results('libiconv',$result,$version,$local);
}


# READLINE NEEDS TO BE MODIFIED PRIOR TO BUILD!
# Please see the build notes for AceDB for important information
sub build_readline {
  my $version = $config->version('readline');
  my $url     = $config->url('readline');
  my $file    = "readline-$version.tgz";
  my $command=<<END;
  cd $build/
  cp ../src/readline-4.3-modified.tgz readline-4.3.tgz
  if [ -e "$file" ]
  then
     echo "$file already fetched"
  else
    curl -O $url/$file
  fi
  gnutar xzf $file
  pushd readline-$version/
  ./configure --prefix=$local
  make
  sudo make install
  popd
END
;
   system($command);
}

######
# gd
######
sub build_libgd {
  my $version = $config->version('libgd');
  my $url     = $config->url('libgd');
  my $file    = "gd-$version.tar.gz";
  my $command=<<END;
  set -x
  cd $build
  if [ -e "$file" ]
  then
    echo "$file already fetched"
  else
    curl -O $url/$file
  fi
  gnutar -zxf $file
  pushd gd-$version/
  ./configure CPPFLAGS=-I/usr/X11R6/include/freetype2 --prefix=$local --mandir=$man1 --bindir=$bin --with-freetype=/usr/X11R6/lib --includedir=$include
  make
  make install
  popd
END

#   cp /usr/share/libtool/config.guess .
#   cp /usr/share/libtool/config.sub .

#  ranlib $LIB/libgd.a
  my $result = system($command);
  $config->stuff_results('libgd',$result,$version,$local);
}

#########
# GD.pm #
#########
sub build_GD {
  my $version = $config->version('gd');
  my $url     = $config->url('gd');
  my $file    = "GD.pm.tar.gz";
  my $command=<<END;
  set -x
  cd $build
  if [ -e "$file" ]
  then
    echo "$file already fetched"
  else
    curl -O $url/$file
  fi
  gnutar xzf $file
  pushd GD-*/
  perl Makefile.PL LIB=$perllib
  make
  make test
  make install
  popd
END

  my $result = system($command);
  $config->stuff_results('GD',$result,$version,$perllib);
}


#########
# expat #
#########
sub build_expat {
  my $version = $config->version('expat');
  my $url     = $config->url('expat');
  my $file    = "expat-$version.tar.gz";
  my $command=<<END;
  set -x
  cd $build
  if [ -e "$file" ]
  then
    echo "$file already fetched"
  else
    curl -O $url/$file
  fi
  gnutar -xzf $file
  pushd expat-$version/
  ./configure --prefix=$local --mandir=$man1 --bindir=$bin
  make
  make install
  ranlib $lib/libexpat.a
  popd
END

  my $result = system($command);
  $config->stuff_results('expat',$result,$version,$local);
}


##############
# bioperl.pm - Installing manually so I can fetch the Bio::DB::GFF scripts
##############
sub bioperl {
  my $version = $config->version('bioperl');
  my $url     = $config->url('bioperl');
  my $file    = "bioperl-$version.tar.gz";
  my $command=<<END;
  set -x
  cd $build
  if [ -e "$file" ]
   then
     echo "$file already fetched"
  else
    curl -O $url/$file
  fi
  gnutar xzf $file
  pushd bioperl-$version/
  perl Makefile.PL LIB=$perllib INST_MAN3DIR=$man3 INST_MAN1DIR=$man1
  make install
  cp scripts/Bio-DB-GFF/*.pl $bin/.
  popd
END

  my $result = system($command);
  $config->stuff_results('bioperl',$result,$version,$perllib);
}


#########
# Ace.pm
#########
sub build_aceperl {
  my $version = $config->version('ace');
  my $url     = $config->url('ace');
  my $file    = "AcePerl.tar.gz";
  my $command=<<END;
  set -x
  cd $build
  if [ -e "$file" ]
  then
    echo "$file already fetched"
  else
    curl -O $url/$file
  fi
  gnutar xzf $file
END
;

  my $result = system($command);
  print_darwin_def();

my $command=<<END;
  cd $build
  pushd AcePerl-*/
#  set ACEDB_MACHINE DARWIN_4
#  export ACEDB_MACHINE
  perl Makefile.PL INSTALLSITELIB=$perllib INSTALLBIN=$bin INSTALLSCRIPT=$bin
  make
  make install
  popd
END

  my $result = system($command);
  $config->stuff_results('ace',$result,$version,$perllib);
}


#########
# DBD.pm
#########
sub build_DBD {
  my $version = $config->version('dbd');
  my $url     = $config->url('dbd');
  my $file    = "DBD-mysql-$version.tar.gz";
  my $mysqlinc   = $config->mysqlinc;
  my $mysqllib   = $config->mysqllib;
  my $command=<<END;
  set -x
  cd $build
  if [ -e "$file" ]
  then
    echo "$file already fetched"
  else
    curl -O $url/$file
  fi
  gnutar xzf $file
  pushd DBD-mysql-$version/
  set PATH /usr/local/mysql/bin ; export PATH
  printenv
  perl Makefile.PL --cflags=-I'$mysqlinc' --libs=-L"$mysqllib -lmysqlclient -lz -lm" LIB=$perllib --nocatchstderr INST_MAN3DIR=$man3 INST_MAN1DIR=$man1
  make
  sudo make install
  popd
END

  my $result = system($command);
  $config->stuff_results('DBD',$result,$version,$mysqllib);
}



sub build_bioperl {
  my $version = $config->version('bioperl');
  my $url     = $config->url('bioperl');
  my $file    = "bioperl-$version.tar.gz";
  my $command=<<END;
  set -x
  cd $build
  if [ -e "$file" ]
  then
    echo "$file already fetched"
  else
    curl -O $url/$file
  fi
  gnutar xzf $file
  pushd bioperl-$version/
  perl Makefile.PL PREFIX=$local INSTALLSITELIB=$perllib
  make
  # make test
  make install
  popd
END

  my $result = system($command);
  $config->stuff_results('bioperl',$result,$version,$local);
}




####################################
## GENERATE PACKAGE DOCUMENTATION ##
####################################
sub print_readme {
  my $text=<<END;
This package installs a variety of libraries for Mac OS X.
In particular it includes all necessary prerequisites for a
either the Generic Genome Browser or BioPerl.

PREREQUISITES: Installation of these libraries assumes that you
already have a working copy of mysql installed at
/usr/local/mysql. These libraries have been designed around the MySQL
package installer.

For advanced users:

To minimize the potential for file conflicts, this installer places
most of its files under /usr/local and perl modules in /Libary/Perl.
If you have pre-existing installations of any of these files, they
may be overwritten (depending on their preexisting file permissions).

In general, this should not be a problem unless you have linked
against these libraries.

What is installed:
    libraries    :  /usr/local/lib
    includes     :  /usr/local/include
    man files    :  /usr/local/share/man
    binaries     :  /usr/local/bin
    perl modules :  /Library/Perl

Installed Perl modules:
END
;

  open README,">libraries/resources/ReadMe.txt";

  print README $text;
  my $results = $config->fetch_results();
  
  my $c;
  printf README ("%4s %-20s %6s %-40s %6s\n",
		 '','Library','Version','Path','Status');
  foreach my $lib (sort keys %{$results}) {
    my $result = ($results->{$lib}->{result} == 0) ? 'ok' : 'failed';
    my $no = ++$c . '. ';
    printf README ("%-4s %-20s %6s %-40s %6s\n",
		   $no,$lib,$results->{$lib}->{version},$results->{$lib}->{path},$result);
  }
}




sub print_darwin_def {
  system("rm -rf $build/AcePerl-*/acelib/wmake/DARWIN_4_DEF");
  
my $def=<<END;
#################################################################
############### acedb: R.Durbin and J.Thierry-Mieg ##############
############### ported to Linux by Ken Letovski    ##############
############### wmake/LINUX_DEF    Feb-2-1993      ##############
#################################################################

#################################################################
########## Machine dependant compiler modification ##############
###########    for generic intel-based LINUX   ##################
#################################################################
########### This file is included by wmake/truemake #############
######  Edit this file to adapt the ACeDB to a new machine ######
#####   following the explanations given in wmake/truemake  #####
#################################################################

NAME = DARWIN

# Compiler used to build 3rd party libraries
LIBCC = cc

# Link to the packaged versions of the libraries
#COMPILER = cc -g -fwritable-strings -Wall -O2 -DACEDB4 `../w3rdparty/include-config -I/usr/local/include -I/usr/X11R6/include`

COMPILER = cc -g -fwritable-strings -Wall -O2 -DACEDB4 `../w3rdparty/include-config -I$include -I/usr/X11R6/include`

LINKER = cc -g

# The arg to libs-config is used if our private copy not installed.
#LIBS = `../w3rdparty/libs-config` -lm -lreadline
LIBS = `../w3rdparty/libs-config` -lreadline

### Linux uses flex to emulate the standard 'lex' program
LEX_LIBS = -ll
### flex -l emulates AT&T lex as accurately as possible
LEX = flex
LEX_OPTIONS = -l

### linux may use bison with flag -y if yacc doesn't exist
YACC = yacc
YACC_OPTIONS =

RPCGEN_FLAGS = -b -I -K -1

RANLIB_NEEDED = true

#################################################################
#################################################################
END
;

  # HARDCODED VERSION!  Can't use wildcards in paths like this...
  open OUT,">$build/AcePerl-1.87/acelib/wmake/DARWIN_DEF";
  print OUT $def;
  close OUT;
}
