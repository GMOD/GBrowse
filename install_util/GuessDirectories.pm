package GuessDirectories;

# this package never gets installed - it's just used by Makefile.PL
sub conf {
  shift;
  my $root = shift;
  return "$root/conf" if -d "$root/conf";
  if ($^O =~ /mswin/i) {  # windows system
    for ('C:/Program Files/Apache Software Foundation/Apache2.3/conf',
	 'C:/Program Files/Apache Software Foundation/Apache2.2/conf',
	 'C:/Program Files/Apache Software Foundation/Apache2.1/conf',
	 'C:/Program Files/Apache Group/Apache2/conf',
	 'C:/Program Files/Apache Group/Apache/conf',
	 'C:/Apache/conf',
	 'C:/Apache2/conf') {
      return $_ if -d $_;
    }
  } else {
    for (
	 '/usr/local/apache/conf',   # standard apache install	 
	 '/usr/local/apache2/conf',  # standard apache2 install
	 '/etc/httpd/conf',          # RedHat linux
	 '/etc/apache',              # Slackware linux
	 '/etc/apache2',             # Ubuntu and Cygwin
	 '/etc/httpd',               # MacOSX
	 '/etc/apache2',             # Ubuntu/debian
	 '/etc/apache-perl',         # Ubuntu/debian
	) {
      return $_ if -d $_;
    }
  }
  return '/usr/local/apache/conf';   # fallback
}

sub root {
  if ($^O =~ /mswin/i) {  # windows system
    for (
	 'C:/Program Files/Apache Software Foundation/Apache2.5',
	 'C:/Program Files/Apache Software Foundation/Apache2.4',
	 'C:/Program Files/Apache Software Foundation/Apache2.3',
	 'C:/Program Files/Apache Software Foundation/Apache2.2',
	 'C:/Program Files/Apache Software Foundation/Apache2.1',
	 'C:/Program Files/Apache Group/Apache2/conf',
	 'C:/Program Files/Apache Group/Apache/conf',
	 'C:/Apache/conf',
	 'C:/Apache2/conf') {
      return $_ if -d $_;
    }
  } else {
    for (
	 '/usr/local/apache2',  # standard apache2 install
	 '/usr/local/apache',   # standard apache install
	 '/usr/apache2',
	 '/usr/apache',
	) {
      return $_ if -d $_;
    }
  }
  return;
}

sub htdocs {
  shift;
  my $root = shift;
  return "$root/htdocs" if -d "$root/htdocs";
  return "$root/html"   if -d "$root/html";
  if ($^O =~ /mswin/i) {  # windows system
    for ('C:/Program Files/Apache Software Foundation/Apache2.3/htdocs',
	 'C:/Program Files/Apache Software Foundation/Apache2.2/htdocs',
	 'C:/Program Files/Apache Software Foundation/Apache2.1/htdocs',
	 'C:/Program Files/Apache Group/Apache2/htdocs',
	 'C:/Program Files/Apache Group/Apache/htdocs',
	 'C:/Apache/htdocs',
	 'C:/Apache2/htdocs') {
      return $_ if -d $_;
    }
  } else {
    for ('/srv/www/htdocs',                # Cygwin
         '/usr/local/apache/htdocs',       # standard apache install
	 '/usr/local/apache2/htdocs',      # standard apache2 install
	 '/var/www/html',                  # RedHat linux
	 '/var/www/htdocs',                # Slackware linux
	 '/var/www',                       # Ubuntu/debian
	 '/var/www',                       # Ubuntu
	 '/Library/Webserver/Documents',   # MacOSX
	) {
      return $_ if -d $_;
    }
  }
  return '/usr/local/apache/htdocs'; # fallback
}

sub cgibin {
  shift;
  my $root = shift;
  return "$root/cgi-bin"  if -d "$root/cgi-bin";
  return "$root/cgi-perl" if -d "$root/cgi-perl";
  return "$root/cgi"      if -d "$root/cgi";

  if ($^O =~ /mswin/i) {  # windows system
    for (
	 'C:/Program Files/Apache Software Foundation/Apache2.3/cgi-bin',
	 'C:/Program Files/Apache Software Foundation/Apache2.2/cgi-bin',
	 'C:/Program Files/Apache Software Foundation/Apache2.1/cgi-bin',
	 'C:/Program Files/Apache Group/Apache2/cgi-bin',
	 'C:/Program Files/Apache Group/Apache/cgi-bin',
	 'C:/Apache/cgi-bin',
	 'C:/Apache2/cgi-bin') {
      return $_ if -d $_;
    }
  } else {
    for ('/srv/www/cgi-bin',               # Cygwin
         '/usr/local/apache/cgi-bin',      # standard apache install
	 '/usr/local/apache2/cgi-bin',     # standard apache2 install
	 '/var/www/cgi-bin',               # RedHat & Slackware linux
	 '/usr/lib/cgi-bin',               # Ubuntu/debian
	 '/Library/Webserver/CGI-Executables',  # MacOSX
	 '/usr/lib/cgi-bin',               # Ubuntu
	) {
      return $_ if -d $_;
    }
  }
  return '/usr/local/apache/cgi-bin'; #fallback
}

1;
