package BuildConfig;

=pod

=head2 BuildConfig.pm - subroutines for building packages on Mac OS X

=cut

# Simplify the construction of packages on Mac OS X

use strict 'vars';
use vars (qw/@ISA @EXPORT_OK @EXPORT/);

require Exporter;

@ISA       = qw//;
@EXPORT    = qw//;
@EXPORT_OK = qw//;

=pod

=head2 Global Variables

=over4

=item %VERSIONS

This global hash contains the versions of all libraries and modules
built by the scripts. These are hard-coded only when necessary.

=item %URLS

This global hash contains the URLs for all libraries and modules built
by the scripts.

=item %UIDS and %GIDS

User and group IDs. Used to create pre- and post-install scripts for
packages.

=back

=cut

my %VERSIONS = (
		ace        => '1.86',
		acedb      => '4_9t',
		bioperl    => '1.2.3',
		dbd        => '2.9002',
		expat      => '1.95.6',
		libfreetype=> '2.0.9',
		gbrowse    => '1.54',
		gd         => '2.06',		
		libiconv   => '1.8',
		libjpeg    => '6b',
		libpng     => '1.2.5',
		libgd      => '2.0.15',
		mysql      => '4.0.14',
		readline   => '4.3',
		zlib       => '1.1.4',
	       );

my %URLS = (
	    ace         => 'http://stein.cshl.org/AcePerl',
	    acedb       => 'http://www.acedb.org/Software/Downloads/SUPPORTED',
	    bioperl     => 'http://www.bioperl.org/DIST',
	    dbd         => 'http://cpan.org/modules/by-module/DBD',
	    expat       => 'http://easynews.dl.sourceforge.net/sourceforge/expat',
	    gbrowse     => 'http://umn.dl.sourceforge.net/sourceforge/gmod',
	    gd          => 'http://stein.cshl.org/WWW/software/GD',
	    libfreetype => 'http://umn.dl.sourceforge.net/sourceforge/freetype',
	    libiconv    => 'http://mirrors.usc.edu/pub/gnu/libiconv',
	    libjpeg     => 'ftp://ftp.uu.net/graphics/jpeg',
	    libpng      => 'http://download.sourceforge.net/libpng',
	    libgd       => 'http://www.boutell.com/gd/http',
	    mysql       => 'ftp://ftp.orst.edu/pub/mysql/Downloads/MySQL-4.0',
	    readline    => 'ftp://ftp.cwru.edu/pub/bash',
	    zlib        => 'http://www.libpng.org/pub/png/src',
	   );


# USERS AND GROUPS
my %UIDS = (
	    mysql   => '11742',
	    gbrowse => '420',
	    acedb   => '419'
	   );

my %GIDS = (
	    mysql   => '11742',
	    gbrowse => '420',
	    acedb   => '419'
	   );


=pod

=head2 Subroutines

=over 4

=item BuildConfig->new()

=back

=cut

sub new {
  my ($class,%params) = @_;
  my $this   = {};
  
  my $base = `pwd`;
  chomp $base;

  $this->{'self_contained'} = $params{'-self_contained'};
  $this->{'version'}        = $params{'-version'};
  $this->{'create_package'} = $params{'-package'};
  $this->{'components'}     = $params{'-components'};
  $this->{'script_path'}    = $params{'-script_path'};

  # INSTALLATION PATHS
  if ($this->{self_contained}) {
    $this->{root}    = $this->{self_contained};
    $this->{perllib} = $this->{root} . '/Perl';
    $this->{conf}    = $this->{root} . '/gbrowse';  # GBrowse specific files
    $this->{htdocs}  = $this->{root} . '/gbrowse/htdocs';
    $this->{cgibin}  = $this->{root} . '/gbrowse/cgi-bin';
  } else {
    $this->{root}    = '/usr/local';
    $this->{perllib} = '/Library/Perl/5.8.1';
    $this->{conf}    = '/Library/WebServer/conf'; # GBrowse specific files
    $this->{htdocs}  = '/Library/WebServer/Documents';
    $this->{cgibin}  = '/Library/WebServer/CGI-Executables';
  }

  $this->{build}      = $base . '/' . $params{'-script_path'} . '/build';
  $this->{package}    = $base . '/' . $params{'-script_path'} . '/files';
  $this->{local}      = $this->{root};
  $this->{include}    = $this->{root} . '/include';
  $this->{bin}        = $this->{root} . '/bin';
  $this->{lib}        = $this->{root} . '/lib';
  $this->{man5_share} = $this->{root} . '/share/man/man5';
  $this->{man3_share} = $this->{root} . '/share/man/man3';
  $this->{man1_share} = $this->{root} . '/share/man/man1';
  $this->{man1}       = $this->{root} . '/man/man1';
  $this->{man3}       = $this->{root} . '/man/man3';
  $this->{man5}       = $this->{root} . '/man/man5';
  $this->{mysqlroot}  = $this->{root} . '/mysql';

  # These are paths for the MySQL package
  $this->{mysqlinc}   = $this->{root} . '/mysql/include';
  $this->{mysqlbin}   = $this->{root} . '/mysql/bin';
  $this->{mysqllib}   = $this->{root} . '/mysql/lib';

  # These are the appropriate paths for the mysql source build
  #  $this->{mysqlinc}   = $this->{root} . '/mysql/include/mysql';
  #  $this->{mysqlbin}   = $this->{root} . '/mysql/bin';
  #  $this->{mysqllib}   = $this->{root} . '/mysql/lib/mysql';

  $this->{gbrowse}    = $this->{root} . '/gbrowse/sample_data';
  $this->{acedb}      = $this->{root} . '/acedb';
  $this->{acedbbin}   = $this->{root} . '/acedb/bin';

  bless $this,$class;
  return $this;
}



sub version {
  my ($self,$pkg) = @_;
  return ($VERSIONS{$pkg});
}

sub url {
  my ($self,$pkg) = @_;
  return ($URLS{$pkg});
}

sub uid {
  my ($self,$pkg) = @_;
  return ($UIDS{$pkg});
}

sub gid {
  my ($self,$pkg) = @_;
  return ($GIDS{$pkg});
}


# shortcuts for returning paths
sub root         { return shift->{root}; }
sub local_path   { return shift->{local}; }
sub perllib      { return shift->{perllib}; }
sub conf         { return shift->{conf}; }
sub htdocs       { return shift->{htdocs}; }
sub cgibin       { return shift->{cgibin}; }
sub build        { return shift->{build}; }
sub package_path { return shift->{package}; }
sub include      { return shift->{include}; }
sub bin          { return shift->{bin}; }
sub lib          { return shift->{lib}; }
sub man5_share   { return shift->{man5_share}; }
sub man3_share   { return shift->{man3_share}; }
sub man1_share   { return shift->{man1_share}; }
sub man1         { return shift->{man1}; }
sub man3         { return shift->{man3}; }
sub man5         { return shift->{man5}; }
sub mysqlroot    { return shift->{mysqlroot}; }
sub mysqlinc     { return shift->{mysqlinc}; }
sub mysqlbin     { return shift->{mysqlbin}; }
sub mysqllib     { return shift->{mysqllib}; }
sub gbrowse      { return shift->{gbrowse}; }
sub acedb        { return shift->{acedb}; }
sub acedb_bin    { return shift->{acedbbin}; }


# some installs require skeletal directories be present first
# Each package will pass in a list of directories that it will
# touch...  If building a package, create the identical paths within
# the package directory, too

sub create_directories {
  my ($self,$dirs) = @_;
  my $build = $self->build;
  my $pkg   = $self->package_path;
  #  mkdir($build);
  #  mkdir($pkg);
  
  my @package_dirs = ($build,$pkg);
  if ($self->{create_package}) {

    # THIS DOES NOT WORK AS EXPECTED...(I can't do the top level
    # directories because then it's contents cannot be found)
    # $self->create_backup($dirs);
    
    # create this identical path but within the package dir
    # by prepending the package path to each
    foreach (@$dirs) {
      push (@package_dirs,$pkg . $_);

      # Save these dirs for later so that I can move their contents
      # into the package
      @{$self->{dirs}} = @$dirs;
    }
  }
  
  push (@$dirs,@package_dirs);
  foreach (@$dirs) {
    my $command=<<END;
    set -x
      if [ -d "$_" ]; then
	echo 'directory $_ already exists'
      else
         mkdir -p $_
      fi
END
    
    my $result = system($command);
    _error($result);
  }
  return ($dirs);
}


# If this installation is destined for a package (instead of just a
# local install), backup all the directories that I am going to touch
# first.
sub create_backup {
  my ($self,$dirs) = @_;
  my $command=<<END;
  mv /usr/local /usr/local.bak
  mv /Library/Perl /Library/Perl.bak
  mv /Library/Webserver /Library/Webserver.bak
END
;

  system($command);
}



# restore the backed up /usr/local
sub restore_backup {
  my $self = shift;
  my $command=<<END;
  sudo rm -rf /usr/local
  sudo mv /usr/local.bak /usr/local
  sudo rm -rf /Library/Perl
  sudo mv /Library/Perl.bak /Library/Perl
  sudo rm -rf /Library/Perl
  sudo mv /Library/Webserver.bak /Library/Webserver
END

  my $result = system($command);
}


sub remove_build {
  my $self = shift;
  my $build   = $self->build;
  print "Removing the build directory...\n";
  my $result = system("rm -rf $build");
}


sub move_build_to_package {
  my $self = shift;
  my $dirs = $self->dirs;
  my $pkg = $self->package_path;

  foreach my $dir (@$dirs) {
    my $command=<<END;
    set -x

    # Move the contents of the install into the package
    mv $dir/* $pkg$dir/.
END
      my $result = system($command);
      error($result);
  }
}

sub _error {
  my $result = shift;
  warn "Non-zero result: $!\n" if ($result != 0);
}

sub stuff_results {
  my ($self,$lib,$result,$version,$path) = @_;
  _error($result);
  $self->{results}->{$lib} = { result  => $result,
			       path    => $path,
			       version => $version
			     };
}

sub print_results {
  my $self = shift;
  foreach my $lib (keys %{$self->{results}}) {
    my $result = ($self->{results}->{$lib}->{result} == 0) ? 'ok' : 'failed';
    print join("\t",$lib,$self->{results}->{$lib}->{version},$self->{results}->{$lib}->{path},$result),"\n";
  }
}

sub fetch_results {
  my $self = shift;
  return ($self->{results});
}

sub fetch_date {
  my $date = `date '+%Y %h %d (%a) at %H:%M'`;
  return $date;
}

sub dirs {
  my $self = shift;
  return (\@{$self->{dirs}});
}


1;
