package GuessDirectories;

use IO::Socket::INET;
use File::Spec;

# this package never gets installed - it's just used by Makefile.PL
sub conf {
  shift;
  if ($^O =~ /mswin/i) {  # windows system
      return File::Spec->catfile('C:','Program Files','GBrowse2');
  } else {
      for (
	  '/etc',
	  '/usr/etc',
	  '/usr/local/etc',
	  ) {
	  return File::Spec->catfile($_,'GBrowse2') if -d $_;
      }
  }
  return File::Spec->catfile('/usr/local/etc','GBrowse2');   # fallback
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
	'/Library/Webserver/Documents',  # MacOSX
	) {
	return $_ if -d $_;
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
	return $_ if -d $_;
    }
    return '/usr/local/apache/cgi-bin'; #fallback
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

sub apachemodules {
    my $self = shift;
    my $root = $self->apache_root;
    foreach ('modules','libexec') {
	return File::Spec->catfile($root,$_)
	    if -d File::Spec->catfile($root,$_);
    }


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

1;
