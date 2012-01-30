package GBrowseGuessDirectories;

use IO::Socket::INET;
use File::Spec;

my $PREFIX;

sub prefix {
    my $self = shift;
    my $d    = $PREFIX;
    $PREFIX  = shift if @_;
    return $d;
}

# this package never gets installed - it's just used by Makefile.PL
sub conf {
  my $self = shift;
  return File::Spec->catfile($PREFIX,'etc','gbrowse2') if $PREFIX;

  if ($^O =~ /mswin/i) {  # windows system
      return File::Spec->catfile('C:','Program Files','GBrowse2','conf');
  } else {
      for (
	  '/etc',
	  '/usr/etc',
	  '/usr/local/etc',
	  ) {
	  return File::Spec->catfile($_,'gbrowse2') if -d $_;
      }
  }
  return File::Spec->catfile($self->prefix || '/usr/local/etc','gbrowse2');   # fallback
}

sub etc {
    shift;
    return File::Spec->catfile($PREFIX,'etc') if $PREFIX;
    return '/etc';  # no exceptions
}

sub tmp {
    my $self = shift;
    return File::Spec->catfile($PREFIX,'tmp','gbrowse2') if $PREFIX;
    return '/srv/gbrowse2/tmp'   if $ENV{DEB_BUILD_ARCH}; # FHS system
    return '/var/tmp/gbrowse2'   if -e '/var/tmp' && -w '/var/tmp';
    return File::Spec->catfile(File::Spec->tmpdir,'gbrowse2');
}

sub persistent {
    my $self = shift;
    return '/srv/gbrowse2'   if $ENV{DEB_BUILD_ARCH}; # FHS system
    my $prefix = $self->prefix || '/var';
    return File::Spec->catfile($prefix,'lib','gbrowse2');
}

sub databases {
    my $self = shift;
    return File::Spec->catfile($self->persistent,'databases');
}

sub apache {
    my $self = shift;
    return -x '/usr/sbin/httpd'   ? '/usr/sbin/httpd'
	 : -x '/usr/sbin/apache2' ? '/usr/sbin/apache2'
	 : -x '/usr/sbin/apache'  ? '/usr/sbin/apache'
	 : undef;
}

sub apache_root {
  if ($^O =~ /mswin/i) {  # windows system
    for (
	'C:/Program Files/Apache Software Foundation/Apache2.5',
	'C:/Program Files/Apache Software Foundation/Apache2.4',
	'C:/Program Files/Apache Software Foundation/Apache2.3',
	'C:/Program Files/Apache Software Foundation/Apache2.2',
	'C:/Program Files/Apache Software Foundation/Apache2.1',
	'C:/Program Files/Apache Group/Apache2',
	'C:/Program Files/Apache Group/Apache',
	'C:/Apache/conf',
	'C:/Apache2/conf') {
	return $_ if -d $_;
    }
  } else {
      for (
	  '/usr/local/apache2',  # standard apache2 install
	  '/usr/local/apache',   # standard apache install
	  '/opt/apache2',
	  '/opt/apache',
	  ) {
	  return $_ if -d $_;
      }
  }
  return;
}

sub htdocs {
    my $self = shift;
    local $^W = 0;
    return File::Spec->catfile($PREFIX,'htdocs') if $PREFIX;

    return '/srv/gbrowse2/htdocs' if $ENV{DEB_BUILD_ARCH};
    my $root = $self->apache_root;
    foreach ('htdocs','html') {
	return File::Spec->catfile($root,$_) 
	    if -e File::Spec->catfile($root,$_);
    }

    for (
	'/var/www/html',                  # RedHat linux
	'/var/www/htdocs',                # Slackware linux
	'/var/www',                       # Ubuntu/debian
	'/var/www',                       # Ubuntu
	'/Library/Webserver/Documents',   # MacOSX
	) {
	return File::Spec->catfile($_,'gbrowse2') if -d $_;
    }
    return '/usr/local/apache/htdocs'; # fallback
}

sub cgibin {
    my $self = shift;
    my $root = $self->apache_root;
    foreach ('cgi-bin','cgi-perl','cgi') {
	return File::Spec->catfile($root,$_)
	    if -e File::Spec->catfile($root,$_);
    }
    for (
	'/var/www/cgi-bin',               # RedHat & Slackware linux
	'/usr/lib/cgi-bin',               # Ubuntu/debian
	'/Library/Webserver/CGI-Executables',  # MacOSX
	'/usr/lib/cgi-bin',               # Ubuntu
	) {
	return "$_/gb2" if -d $_;
    }
    return '/usr/local/apache/cgi-bin/gb2'; #fallback
}

# try a few ports until we find an open one
sub portdemo {
    my $self = shift;
    my @candidates = (80,8000,8080,8001,8008,8081,8888,8181);
    for my $port (@candidates) {
	my $h = IO::Socket::INET->new(LocalPort=>$port);
	return $port if $h;
    }
}

sub wwwuser {
    my $self = shift;
    for (qw(www-data www httpd apache apache2 System nobody )) {
	return $_ if getpwnam($_);
    }
    # fallback -- user current real user
    return (getpwuid($<))[0];
}

sub installconf {
    my $self = shift;
    return   'y';
}

sub installetc {
    my $self = shift;
    return   'y';
}

sub apachemodules {
    my $self = shift;
    my $root = $self->apache_root;
    foreach ('modules','libexec') {
	return File::Spec->catfile($root,$_)
	    if -d File::Spec->catfile($root,$_);
    }

    return '/etc/httpd/modules' if -d '/etc/httpd/modules';


    for my $first ('/usr/lib','/usr/share',
		   '/usr/local/lib','/usr/local/share') {
	for my $second ('apache','apache2') {
	    for my $third ('modules','libexec') {
		my $candidate = File::Spec->catfile($first,$second,$third);
		return $candidate if -d $candidate;
	    }
	}
    }
    return '/usr/lib/apache/modules'; #fallback
}

# most (all?) distributions have a way to add config file snippets
# to httpd.conf without modifying the main file
sub apache_includes {
    my $self = shift;
    return '/etc/apache2/other'  if -d '/etc/apache2/other'; # why cant macos do things like everybody else?
    return '/etc/apache2/conf.d' if -d '/etc/apache2/conf.d';
    return '/etc/apache/conf.d'  if -d '/etc/apache/conf.d';
    return '/etc/httpd/conf.d'   if -d '/etc/httpd/conf.d';
    return;
}

1;
