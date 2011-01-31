#!/usr/bin/perl
# $Id: build-gbrowse.pl,v 1.1 2003-11-19 01:49:18 tharris Exp $

=pod

=head1 DESCRIPTION
 
  build-gbrowse.pl - build GBrowse and its dependencies

=head1 SYNPOSIS

 Usage build-gbrowse.pl [options...]

 Options:
    --self_contained full path. Build everything within this path.
    --package        Move build directories to the package dir
    --version        version of package for generating documentation

=head1 NOTES

  This script simplifies the process of building the Gbrowse core of
  the Generic Genome Browser. It can also be used to create a package
  installer of GBrowse.

=head2 Creating a local installation
   
  build-gbrowse.pl

  All files will be built in standard system paths:

  Perl modules         /Library/Perl
  binaries             /usr/local/bin
  configuration files  /Library/WebServer/conf
  htdocs               /Library/WebServer/Documents
  cgi-bin              /Library/WebServer/CGI-Executables

=head2 Building a self-contained package

  build-gbrowse.pl --self_contained /usr/local/gbrowse-november2003

  Issuing this command will cause all files to be built in a flat
  directory structure suitable for generating a self-contained
  pacakge. After building, use PackageMaker and point it to the
  directory provided in --self_contained.  Alternatively, you can pass
  the --package option (see below) to have these directories
  automatically moved into the package path.

=head2 Building a package within standard local paths

  build-gbrowse.pl --package

  You can also easily build a package using local paths. To simplify
  this process, you should pass the --package (boolean) flag. This
  will cause three things to happen.  First, all system directories
  that the build process touches will be backed up (to
  $dir.bak). Empty directories with the same name will be created.
  Following the build, these directories are then copied to predfined
  package directory.  Finally, the backup directories are restored to
  their original name.

=head1 AUTHOR

  Todd Harris (harris@cshl.org)
  Version: $Id: build-gbrowse.pl,v 1.1 2003-11-19 01:49:18 tharris Exp $
  Copyright @ 2003 Cold Spring Harbor Laboratory

=cut

#'

use Getopt::Long;
use Pod::Usage;
use lib '../';
use BuildConfig;
use strict;

$ENV{PERL5LIB} = '/Library/Perl.bak/5.8.1';

my ($self_contained,$package,$version,$help);
GetOptions('self_contained=s'=> \$self_contained,
	   'version=s'      => \$version,
	   'package'        => \$package,
	   'help=s'         => \$help,
	  );

pod2usage(-verbose=>2) if ($help);

my $config = BuildConfig->new(-self_contained => $self_contained,
			      -version        => $version,
			      -components     => 'gbrowse',
			      -package        => $package,
			      -script_path    => 'gbrowse',
			     );

my $build   = $config->build;
my $cgibin  = $config->cgibin;
my $conf    = $config->conf;
my $htdocs  = $config->htdocs;
my $perllib = $config->perllib;
my $bin     = $config->bin;

my @dirs = ($cgibin,$conf,$htdocs,$perllib,$bin);

$config->create_directories(\@dirs);
build_gbrowse();

print_results();

# Generate the ReadMes and scripts for the package
generate_readmes();
generate_scripts();

#################################################################
##                       END MAIN
#################################################################
sub build_gbrowse {
  my $version = $config->version('gbrowse');
  my $url     = $config->url('gbrowse');
  my $file    = "Generic-Genome-Browser-$version.tar.gz";
  my $command=<<END;
  set -x
  cd $build
  if [ -e "$file" ]
  then
    echo "$file already downloaded"
   else 
     curl -O $url/$file
  fi
  gnutar zxf $file
  pushd Generic-Genome-Browser-$version/
  perl Makefile.PL CONF=$conf CGIBIN=$cgibin HTDOCS=$htdocs INSTALLSITELIB=$perllib
  make
  sudo make install

  # Copy the test database files into the package so
  # that I can build a sample database after the install...
  # I don't think I am actually doing this...
  # sudo cp -r sample_data \$gbrowse/.

  # Copy the various bin scripts as well into the site-specific bin directory
  sudo cp bin/* $bin/.
  popd
END

  # Strip some of the build paths..
  # Should no longer be necessary
  # echo perl -p -i -e 's|\/Users\/todd\/projects\/macosx\/gbrowse\/gbrowse\/files||g' $CGIBIN/gbrowse
  # perl -p -i -e 's|\/Users\/todd\/projects\/macosx\/gbrowse\/gbrowse\/files||g' $CGIBIN/gbrowse
  my $result = system($command);
  $config->stuff_results('GBrowse',$result,$version,$conf);
}

####################################
## GENERATE PACKAGE DOCUMENTATION ##
####################################
sub print_gbrowse_readme {
  my $text=<<END;
This package installs the primary components of the Generic Genome
Browser.

This installer is designed to be used in conjunction with the supplied
"libraries" and "mysql", packages. You may, if you choose,
use your own installations of MySQL and the associated libraries.
However, module dependecies and version conflicts may prevent GBrowse
from working appropriately.
END
;
  print README $text;
}


###############################################
# PRE- AND POST- INSTALL SCRIPTS FOR PACKAGES #
###############################################
sub gbrowse_preinstall {
  my $UID = $config->uid('gbrowse');
  my $GID = $config->gid('gbrowse');
  my $text=<<END;
#!/bin/sh
# Create the gbrowse user and group

niutil -create / /users/gbrowse
niutil -createprop / /users/gbrowse uid $UID
niutil -createprop / /users/gbrowse gid $GID
niutil -createprop / /users/gbrowse name gbrowse
niutil -createprop / /users/gbrowse passwd *
niutil -createprop / /users/gbrowse realname gbrowse
niutil -createprop / /users/gbrowse _writers_passwd root
niutil -createprop / /users/gbrowse change 0
niutil -createprop / /users/gbrowse home /dev/null
niutil -createprop / /users/gbrowse shell /dev/null

niutil -create / /groups/gbrowse
niutil -createprop / /groups/gbrowse gid $GID
niutil -createprop / /groups/gbrowse passwd *
END
;

}
