package GuessDirectories;

# this package never gets installed - it's just used by Makefile.PL
sub conf {
  if ($^O =~ /mswin/i) {  # windows system
    for ('C:/Program Files/Apache Group/Apache2/conf',
	 'C:/Program Files/Apache Group/Apache/conf',
	 'C:/Apache/conf',
	 'C:/Apache2/conf') {
      return $_ if -d $_;
    }
  } else {
    for ('/usr/local/apache/conf',   # standard apache install
	 '/etc/httpd/conf',          # RedHat linux
	 '/etc/apache',              # Slackware linux
	 '/etc/httpd',               # MacOSX
	) {
      return $_ if -d $_;
    }
  }
  return;
}

sub htdocs {
  if ($^O =~ /mswin/i) {  # windows system
    for ('C:/Program Files/Apache Group/Apache2/htdocs',
	 'C:/Program Files/Apache Group/Apache/htdocs',
	 'C:/Apache/htdocs',
	 'C:/Apache2/htdocs') {
      return $_ if -d $_;
    }
  } else {
    for ('/usr/local/apache/htdocs',       # standard apache install
	 '/var/www/html',                  # RedHat linux
	 '/var/www/htdocs',                # Slackware linux
	 '/Library/Webserver/Documents',  # MacOSX
	) {
      return $_ if -d $_;
    }
  }
  return;
}

sub cgibin {
  if ($^O =~ /mswin/i) {  # windows system
    for ('C:/Program Files/Apache Group/Apache2/cgi-bin',
	 'C:/Program Files/Apache Group/Apache/cgi-bin',
	 'C:/Apache/cgi-bin',
	 'C:/Apache2/cgi-bin') {
      return $_ if -d $_;
    }
  } else {
    for ('/usr/local/apache/cgi-bin',      # standard apache install
	 '/var/www/cgi-bin',               # RedHat & Slackware linux
	 '/Library/Webserver/CGI-Executables',  # MacOSX
	) {
      return $_ if -d $_;
    }
  }
  return;
}

1;
