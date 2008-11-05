package GBrowseInstall;

use base 'Module::Build';
use strict;
use warnings;
use ExtUtils::CBuilder;
use ExtUtils::MakeMaker 'prompt';
use Cwd;
use File::Basename 'dirname','basename';
use File::Path 'rmtree';
use File::Temp 'tempdir';
use File::Spec;
use IO::File;
use GuessDirectories;

my %OK_PROPS = (conf          => 'Directory for GBrowse\'s config and support files?',
		htdocs        => 'Directory for GBrowse\'s static images & HTML files?',
		cgibin        => 'Apache CGI scripts directory?',
		portdemo      => 'Internet port to run demo web site on (for demo)?',
		apachemodules => 'Apache loadable module directory (for demo)?',
		wwwuser       => 'User account under which Apache daemon runs?');

sub ACTION_demo {
    my $self = shift;
    $self->depends_on('config_data');

    my $home = File::Spec->catfile($self->base_dir(),'blib');
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
    rmtree(["$home/htdocs/tmp"]);

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

    my $apache =  -x '/usr/sbin/httpd'   ? '/usr/sbin/httpd'
	        : -x '/usr/sbin/apache2' ? '/usr/sbin/apache2'
                : -x '/usr/sbin/apache'  ? '/usr/sbin/apache'
                : 'not found';
    if ($apache eq 'not found') {
	die "Could not find apache executable on this system. Can't run demo";
    }
    system "$apache -k start -f $dir/conf/httpd.conf";
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
    my $home = $self->base_dir();
    unless ($dir && -e $dir) {
	print STDERR "Demo doesn't seem to be running.\n";
	return;
    }
    system "apache2 -k stop -f $dir/conf/httpd.conf";
    rmtree([$dir,"$home/htdocs/tmp"]);
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
    unless (Module::Build->y_n("Reuse previous configuration as defaults?",'y')) {
	for (keys %{$self->private_props}) {
	    $self->config_data($_=>undef);
	}
    }
    $self->depends_on('config_data');
}

sub ACTION_test {
    my $self = shift;
    $self->depends_on('config_data');
    $self->SUPER::ACTION_test;
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
	if ($props->{$key} =~ /directory/i) {
	    my $dir_to_check = $key eq 'conf' || $key eq 'htdocs'
		? dirname($opts{$key}) 
		: $opts{$key};
	    unless (-d $dir_to_check) {
		next if Module::Build->y_n("The directory $dir_to_check does not exist. Use anyway?",'n');
		redo;
	    }
	}
    }

    for my $key (keys %opts) {
	$self->config_data($key=>$opts{$key});
    }

    $self->config_done(1);

    print STDERR "\n**Interactive configuration done. Run './Build reconfig' to reconfigure**\n";
}

sub ACTION_config_data {
    my $self = shift;
    $self->depends_on('config');
    $self->SUPER::ACTION_config_data;
}

sub ACTION_apache_conf {
    my $self = shift;
    $self->depends_on('config');
    my $dir    = $self->config_data('htdocs');
    my $conf   = $self->config_data('conf');
    my $cgibin = $self->config_data('cgibin');
    my $cgiroot= basename($cgibin);
    my $docs   = basename($dir);
    my $inc    = $self->added_to_INC;
    $inc      .= "\n  " if $inc;

    print <<END;

INSTRUCTIONS: Cut this where indicated and paste it into your Apache
configuration file. You may wish to save it separately and include it
using the Apache "Include /path/to/file" directive. Then restart
Apache and point your browser to http://your.site/$docs/ to start
browsing the sample genomes.

===>>> cut here <<<===
Alias "/$docs/" "$dir/"

<Location "/$docs/">
  Options -Indexes -MultiViews -FollowSymLinks +SymLinksIfOwnerMatch
</Location>

<Directory "$cgibin/gb2">
  ${inc}SetEnv GBROWSE_MASTER GBrowse.conf
  SetEnv GBROWSE_CONF   "$conf"
  SetEnv GBROWSE_DOCS   "$dir"
  SetEnv GBROWSE_ROOT   "/$docs"
</Directory>
===>>> cut here <<<===
END
}

sub ACTION_install {
    my $self = shift;
    $self->depends_on('config_data');
    $self->install_path->{conf} 
        ||= $self->config_data('conf')
	    || GuessDirectories->conf;
    $self->install_path->{htdocs}
        ||= File::Spec->catfile($self->config_data('htdocs'))
	    || GuessDirectories->htdocs;
    $self->install_path->{'cgi-bin'} 
        ||= $self->config_data('cgibin')
	    || GuessDirectories->cgibin;
    $self->SUPER::ACTION_install();

    my $user = $self->config_data('wwwuser') || GuessDirectories->wwwuser;

    # fix some directories so that www user can write into them
    mkdir File::Spec->catfile($self->install_path->{htdocs},'tmp');
    my ($uid,$gid) = (getpwnam($user))[2,3];
    chown $uid,$gid,File::Spec->catfile($self->install_path->{htdocs},     'tmp');
    chown $uid,$gid,glob(File::Spec->catfile($self->install_path->{htdocs},'databases','').'*');
    $self->fix_selinux;

    print STDERR "\n***INSTALLATION COMPLETE***\n";
    print STDERR "Now run ./Build apache_conf to generate the needed configuration lines for Apache.\n";
}

sub ACTION_install_slave {
    my $self = shift;
    $self->SUPER::ACTION_install();
}

sub fix_selinux {
    my $self = shift;
    return unless -e '/proc/filesystems';
    my $f    = IO::File->new('/proc/filesystems') or return;
    next unless grep /selinux/i,<$f>;

    print STDERR "\n*** SELinux detected -- fixing permissions ***\n";

    my $htdocs = $self->config_data('htdocs');
    my $conf   = $self->config_data('conf');
    system "/usr/bin/chcon -R -t httpd_sys_content_t $conf";
    system "/usr/bin/chcon -R -t httpd_sys_content_t $htdocs";
    system "/usr/bin/chcon -R -t httpd_sys_content_rw_t $htdocs/tmp";
}

sub process_conf_files {
    my $self = shift;
    my $f    = IO::File->new('MANIFEST');
    while (<$f>) {
	next unless m!^conf/!;
	chomp;
	$self->copy_if_modified($_=>'blib');
    }
}

sub process_htdocs_files {
    my $self = shift;
    my $f    = IO::File->new('MANIFEST');
    while (<$f>) {
	next unless m!^htdocs/!;
	chomp;
	my $copied = $self->copy_if_modified($_=>'blib');
	$self->substitute_in_place("blib/$_")
	    if $copied
	    or !$self->up_to_date('_build/config_data',"blib/$_");
    }
}

sub process_cgibin_files {
    my $self = shift;
    my $f    = IO::File->new('MANIFEST');
    while (<$f>) {
	next unless m!^cgi-bin/!;
	chomp;
	$self->copy_if_modified($_=>'blib');
    }
}

sub substitute_in_place {
    my $self = shift;
    my $path = shift;
    return unless $path =~ /\.(html|txt)$/;
    my $in   = IO::File->new($path) or return;
    my $out  = IO::File->new("$path.$$",'>') or return;

    print STDERR "Performing variable substitutions in $path\n";

    my $htdocs = $self->config_data('htdocs');
    my $conf   = $self->config_data('conf');
    my $cgibin = $self->config_data('cgibin');

    while (<$in>) {
	s/\$HTDOCS/$htdocs/g;
	s/\$CONF/$conf/g;
	s/\$CGIBIN/$cgibin/g;
	$out->print($_);
    }
    $in->close;
    $out->close;
    rename("$path.$$",$path);
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

 <IfModule !log_config_module>
   LoadModule log_config_module $modules/mod_log_config.so
 </IfModule>

 <IfModule !cgi_module>
  LoadModule cgi_module         $modules/mod_cgi.so
 </IfModule>

 <IfModule !authz_host_module>
   LoadModule authz_host_module $modules/mod_authz_host.so
 </IfModule>

 <IfModule !env_module>
   LoadModule env_module        $modules/mod_env.so
 </IfModule>

 <IfModule !alias_module>
  LoadModule alias_module      $modules/mod_alias.so
 </IfModule>

 <IfModule !dir_module>
   LoadModule dir_module        $modules/mod_dir.so
 </IfModule>

 <IfModule !mime_module>
   LoadModule mime_module       $modules/mod_mime.so
 </IfModule>

</IfModule>

TypesConfig "$dir/conf/mime.types"

Listen $port
Include "$dir/conf/apache_gbrowse.conf"
END
}

sub gbrowse_conf {
    my $self = shift;
    my ($port,$dir) = @_;
    my $inc         = $self->added_to_INC;
    $inc           .= "\n" if $inc;

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
		${inc}AllowOverride None
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

sub added_to_INC {
    my $self = shift;
    my @inc    = grep {!/install_util/} eval {$self->_added_to_INC};  # not in published API
    return @inc ? 'SetEnv PERL5LIB '.
	          join(':',@inc)
		: '';
}

1;

__END__

=head1 ACTIONS

=over 4

=item config

Interactively configure the locations in which GBrowse's scripts,
configuration files, and static image/support files will be installed.

One or more of the config options can be set on the command 
line when first running perl Build.PL:

  perl Build.PL --conf=/etc/GBrowse2 \         # config files
                --htdocs=/var/www/gbrowse2 \   # static files
                --cgibin=/usr/lib/cgi-bin \    # CGI directory
                --wwwuser=www-data \           # apache user
                --portdemo=8000 \              # demo web site port
                --apachemodules=/usr/lib/apache2/modules  # apache loadable modules

=item reconfig

Interactively edit configuration locations. See "./Build help config".

=item demo

Try to start an apache/gbrowse instance running in demo mode on the
port specified during "./Build config". This allows you to try GBrowse
without installing it.

=item stopdemo

Stop the demo instance.

=item apache_conf

Generate a fragment of the Apache configuration file needed to run
GBrowse.

=back
