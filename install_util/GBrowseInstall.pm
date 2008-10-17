package GBrowseInstall;

use base 'Module::Build';
use strict;
use warnings;
use ExtUtils::CBuilder;
use ExtUtils::MakeMaker 'prompt';
use Cwd;
use File::Path 'rmtree';
use File::Temp 'tempdir';
use File::Spec;
use IO::File;
use GuessDirectories;

my %OK_PROPS = (conf          => 'Directory for GBrowse\'s config and support files?',
		htdocs        => 'Apache documents directory?',
		cgibin        => 'Apache CGI scripts directory?',
		portdemo      => 'Internet port to run demo web site on (for demo)?',
		apachemodules => 'Apache loadable module directory (for demo)?');

sub ACTION_demo {
    my $self = shift;
    $self->depends_on('config');

    my $home = $self->base_dir();
    my $dir  = tempdir(
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

    my $conf_data = $self->httpd_conf($dir,$port);
    my $conf = IO::File->new("$dir/conf/httpd.conf",'>')
	or die "$dir/conf/httpd.conf: $!";
    $conf->print($conf_data);
    $conf->close;

    $conf_data = $self->gbrowse_conf($port,$home);
    $conf = IO::File->new("$dir/conf/apache_gbrowse.conf",'>') 
	or die "$dir/conf/apache_gbrowse.conf: $!";
    $conf->print($conf_data);
    $conf->close;

    $conf_data = $self->mime_conf();
    my $mime = IO::File->new("$dir/conf/mime.types",'>') 
	or die "$dir/conf/mime.types: $!";
    $mime->print($conf_data);
    $mime->close;

    system "apache2 -k start -f $dir/conf/httpd.conf";
    if (-e "$dir/logs/apache2.pid") {
	print STDERR "Demo is now running on http://localhost:$port\n";
	print STDERR "Run \"./Build demostop\" to stop it.\n";
	$self->config_data(demodir=>$dir);
    } else {
	print STDERR "Apache failed to start.\n";
	if (-e "$dir/logs/error.log") {
	    print STDERR "==Apache Error Log==\n";
	    my $f = IO::File->new("$dir/logs/error.log");
	    print STDERR while <$f>;
	}
	rmtree([$dir]);
    }
}

sub ACTION_demostop {
    my $self = shift;
    my $dir  = $self->config_data('demodir');
    unless ($dir && -e $dir) {
	print STDERR "Demo doesn't seem to be running.\n";
	return;
    }
    system "apache2 -k stop -f $dir/conf/httpd.conf";
    rmtree([$dir]);
    $self->config_data('demodir'=>undef);
    print STDERR "Demo stopped.\n";
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

sub ACTION_reconfig {
    my $self = shift;
    $self->config_done(0);
    $self->depends_on('config');
}

sub ACTION_config {
    my $self  = shift;
    local $^W = 0;

    $self->depends_on('build');
    return if $self->config_done;

    print STDERR "\n**Beginning interactive configuration**\n";

    my $props = $self->private_props;
    my %opts  = map {
	$_=>$self->config_data($_)
      } keys %$props;

    for my $key (sort keys %opts) {
	# next if $self->config_data($key);
	$opts{$key} = prompt($props->{$key},
			     $opts{$key} ||
			     GuessDirectories->$key($opts{apache}));
	if ($props->{$key} =~ /directory/i
	    && !-d $opts{$key}) {
	    redo unless Module::Build->y_n("The directory $opts{$key} does not exist. Use anyway?",'n');
	}
    }

    for my $key (keys %opts) {
	$self->config_data($key=>$opts{$key});
    }

    $self->config_done(1);
}

sub ACTION_make_apache_conf {
    my $self = shift;
    $self->depends_on('config');
    my $data = $self->gbrowse_conf($self->config_data(''));
}

sub process_conf_files {
    my $self = shift;
    my $f    = IO::File->new('MANIFEST');
    while (<$f>) {
	next unless m!^conf/!;
	chomp;
	$self->copy_if_modified($_=>'blib/conf');
    }
}

sub process_htdocs_files {
    my $self = shift;
    my $f    = IO::File->new('MANIFEST');
    while (<$f>) {
	next unless m!^htdocs/!;
	chomp;
	$self->copy_if_modified($_=>'blib/htdocs');
    }
}

sub private_props {
    return \%OK_PROPS;
}

sub valid_property {
    my $self  = shift;
    my $prop  = shift;
    return $OK_PROPS{$prop} || $self->SUPER::valid_property($prop);
}

sub httpd_conf {
    my $self = shift;
    my ($dir,$port) = @_;

    my $modules = $self->config_data('apachemodules')
	|| GuessDirectories->apachemodules;

    return <<END;
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
Include "$dir/conf/apache_gbrowse.conf"
END
}

sub gbrowse_conf {
    my $self = shift;
    my ($port,$dir) = @_;

    return <<END;
NameVirtualHost *:$port
<VirtualHost *:$port>
	ServerAdmin webmaster\@localhost
	
	DocumentRoot $dir/htdocs/
	<Directory />
		Options FollowSymLinks
		AllowOverride None
	</Directory>
	<Directory $dir/htdocs/>
		Options Indexes FollowSymLinks MultiViews
		AllowOverride None
		Order allow,deny
		allow from all
	</Directory>

	ScriptAlias /cgi-bin/ $dir/cgi-bin/
	<Directory "$dir/cgi-bin/">
		SetEnv PERL5LIB $dir/blib/lib:$dir/blib/arch:$dir/lib
		SetEnv GBROWSE_MASTER GBrowse.conf
                SetEnv GBROWSE_CONF   $dir/conf
                SetEnv GBROWSE_DOCS   $dir/htdocs
                SetEnv GBROWSE_ROOT   /
		AllowOverride None
		Options +ExecCGI -MultiViews +SymLinksIfOwnerMatch
		Order allow,deny
		Allow from all
	</Directory>
</VirtualHost>
END
}

sub mime_conf {
    my $self = shift;
    return <<END;
image/gif					gif
image/jpeg					jpeg jpg jpe
image/png					png
image/svg+xml					svg svgz
text/css					css
text/html					html htm shtml
END
}

sub config_done {
    my $self = shift;
    my $done = $self->config_data('config_done');
    $self->config_data(config_done=>shift) if @_;
    return $done;
}

1;
