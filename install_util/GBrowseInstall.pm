package GBrowseInstall;

use base 'Module::Build';
use strict;
use warnings;
use ExtUtils::CBuilder;
use ExtUtils::MakeMaker 'prompt';
use Cwd;
use File::Path 'rmtree';
use File::Temp;
use IO::File;
use GuessDirectories;

my %OK_PROPS = (apache   => 'Apache root directory (\'\' for none)? ',
		conf     => 'Apache config directory? ',
		htdocs   => 'Apache documents directory? ',
		cgibin   => 'Apache CGI scripts directory? ',
		portdemo => 'Internet port to run demo on (demo only)? ',
		apachemodules => 'Apache loadable module directory (demo only)? ');

sub private_props {
    return \%OK_PROPS;
}

sub valid_property {
    my $self  = shift;
    my $prop  = shift;
    return $OK_PROPS{$prop} || $self->SUPER::valid_property($prop);
}

sub ACTION_demo {
    my $self = shift;
    my $cwd  = cwd();
    my $dir  = File::Temp->newdir(
	'GBrowse_demo_XXXX',
	TMPDIR=>1,
	CLEANUP=>0,
	);
    my $port = $self->config_data('portdemo') 
	|| GuessDirectories->portdemo();
    my $modules = $self->config_data('apachemodules')
	|| GuessDirectories->apachemodules;

    mkdir "$dir/conf";
    mkdir "$dir/logs";
    mkdir "$dir/locks";
    my $conf = IO::File->new("$dir/conf/httpd.conf",'>');
    $conf->print(<<END);
ServerName           "localhost"
ServerRoot           "$dir/conf"
LockFile             "$dir/locks/accept.lock"
PidFile              "$dir/logs/apache2.pid"
ErrorLog             "$dir/logs/error.log"
LogFormat            "%h %l %u %t \\"%r\\" %>s %b" common
CustomLog            "$dir/logs/access.log"      common
LogLevel             warn

Timeout              300
KeepAlive            On
MaxKeepAliveRequests 100
KeepAliveTimeout     15
DefaultType text/plain
HostnameLookups Off

<IfModule so_module>
 LoadModule cgi_module        $modules/mod_cgi.so
 LoadModule authz_host_module $modules/mod_authz_host.so
 LoadModule env_module        $modules/mod_env.so
 LoadModule alias_module      $modules/mod_alias.so
 LoadModule dir_module        $modules/mod_dir.so
 LoadModule mime_module       $modules/mod_mime.so
</IfModule>

TypesConfig "$dir/conf/mime.types"

Listen $port
NameVirtualHost *:$port
<VirtualHost *:$port>
	ServerAdmin webmaster\@localhost
	
	DocumentRoot $cwd/htdocs/
	<Directory />
		Options FollowSymLinks
		AllowOverride None
	</Directory>
	<Directory $cwd/htdocs/>
		Options Indexes FollowSymLinks MultiViews
		AllowOverride None
		Order allow,deny
		allow from all
	</Directory>

	ScriptAlias /cgi-bin/ $cwd/cgi-bin/
	<Directory "$cwd/cgi-bin/">
		SetEnv PERL5LIB $cwd/lib
		SetEnv GBROWSE_MASTER GBrowse.conf
                SetEnv GBROWSE_CONF   $cwd/conf
                SetEnv GBROWSE_DOCS   $cwd/htdocs
                SetEnv GBROWSE_ROOT   /
		AllowOverride None
		Options +ExecCGI -MultiViews +SymLinksIfOwnerMatch
		Order allow,deny
		Allow from all
	</Directory>
</VirtualHost>
END
;
    $conf->close;
    my $mime = IO::File->new("$dir/conf/mime.types",'>') or die $!;
    $mime->print(<<END);
image/gif					gif
image/jpeg					jpeg jpg jpe
image/png					png
image/svg+xml					svg svgz
text/css					css
text/html					html htm shtml
END
;
    system "apache2 -k start -f $dir/conf/httpd.conf";
    if (-e "$dir/logs/apache2.pid") {
	print STDERR "Demo is now running on http://localhost:$port\n";
	print STDERR "Run \"./Build stop_demo\" to stop it.\n";
	$self->config_data(demodir=>$dir);
    } else {
	print STDERR "Apache failed to start. The error log shows:\n";
	my $f = IO::File->new("$dir/logs/error.log");
	print while <$f>;
    }
}

sub ACTION_stop_demo {
    my $self = shift;
    my $dir  = $self->config_data('demodir') or return;
    system "apache2 -k stop -f $dir/conf/httpd.conf";
    rmtree([$dir]);
    $self->config_data('demodir'=>undef);
}

sub ACTION_realclean {
    my $self = shift;
    $self->SUPER::ACTION_realclean;
    foreach ('CAlign.xs','CAlign.pm') {
	unlink "./lib/Bio/Graphics/Browser/$_";
    }
}

sub ACTION_build {
    my $self = shift;
    $self->SUPER::ACTION_build;
    mkdir './htdocs/tmp';
    chmod 0777,'./htdocs/tmp';
}

sub ACTION_config {
    my $self  = shift;
    local $^W = 0;

    $self->depends_on('build');

    my $props = $self->private_props;
    my %opts  = map {
	$_=>$self->config_data($_)
      } keys %$props;

    $opts{apache} = prompt($props->{apache},
				  GuessDirectories->root);
    
    for my $key (sort keys %opts) {
	next if $key eq 'apache';
	# next if $self->config_data($key);
	$opts{$key} = prompt($props->{$key},
				    $opts{$key} ||
					      GuessDirectories->$key($opts{apache}))
    }

    for my $key (keys %opts) {
	$self->config_data($key=>$opts{$key});
    }
}

1;
