package GBrowseInstall;

use base 'Module::Build';
use strict;
use warnings;
use ExtUtils::CBuilder;
use ExtUtils::MakeMaker 'prompt';
use Cwd;
use File::Basename 'dirname','basename';
use File::Path 'rmtree','mkpath';
use File::Temp 'tempdir';
use File::Spec;
use IO::File;
use GuessDirectories;

my @OK_PROPS = (conf          => 'Directory for GBrowse\'s config and support files?',
		htdocs        => 'Directory for GBrowse\'s static images & HTML files?',
		tmp           => 'Directory for GBrowse\'s temporary data',
		databases     => 'Directory for GBrowse\'s example databases',
		cgibin        => 'Apache CGI scripts directory?',
		portdemo      => 'Internet port to run demo web site on (for demo)?',
		apachemodules => 'Apache loadable module directory (for demo)?',
		wwwuser       => 'User account under which Apache daemon runs?');
my %OK_PROPS = @OK_PROPS;

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
    $self->depends_on('config');
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

sub ACTION_distclean {
    my $self = shift;
    $self->SUPER::ACTION_distclean;
    rmtree(['debian/libgbrowse-perl']);
}

sub ACTION_config {
    my $self  = shift;
    local $^W = 0;

    # $self->depends_on('build');
    return if $self->config_done;

    print STDERR "\n**Beginning interactive configuration**\n";

    my $props = $self->private_props;
    my %opts  = map {
	$_=>$self->config_data($_)
      } keys %$props;

    my @keys = @OK_PROPS;
    while (@keys) {
	my $key = shift @keys;
	my $val = shift @keys; # not used

	# next if $self->config_data($key);
	$opts{$key} = prompt($props->{$key},
			     $opts{$key} ||
			     GuessDirectories->$key($opts{apache}));
	if ($props->{$key} =~ /directory/i) {
	    my ($volume,$dir) = File::Spec->splitdir($opts{$key});
	    my $top_level     = File::Spec->catfile($volume,$dir);
	    unless (-d $top_level) {
		next if Module::Build->y_n("The directory $top_level does not exist. Use anyway?",'n');
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

    my $docs   = basename($self->config_data('htdocs'));
    print STDERR <<END;

INSTRUCTIONS: Paste the following into your Apache configuration
file. You may wish to save it separately and include it using the
Apache "Include /path/to/file" directive. Then restart Apache and
point your browser to http://your.site/$docs/ to start browsing the
sample genomes.

>>>>>> cut here <<<<<
END
;
    print $self->apache_conf;
}

sub apache_conf {
    my $self = shift;
    my $dir    = $self->config_data('htdocs');
    my $conf   = $self->config_data('conf');
    my $cgibin = $self->config_data('cgibin');
    my $tmp    = $self->config_data('tmp');
    my $cgiroot= basename($cgibin);
    my $docs   = basename($dir);
    my $inc    = $self->added_to_INC;
    $inc      .= "\n  " if $inc;

    return <<END;
Alias        "/$docs/i/" "$tmp/images/"
Alias        "/$docs"    "$dir"
ScriptAlias  "/gb2"      "$cgibin/gb2"

<Directory "$dir">
  Options -Indexes -MultiViews +FollowSymLinks
</Directory>

<Directory "$cgibin/gb2">
  ${inc}SetEnv GBROWSE_CONF   "$conf"
</Directory>
END
}

sub ACTION_install {
    my $self = shift;
    $self->depends_on('config_data');
    $self->install_path->{conf} 
        ||= $self->config_data('conf')
	    || GuessDirectories->conf;
    $self->install_path->{htdocs}
        ||= $self->config_data('htdocs')
	    || GuessDirectories->htdocs;
    $self->install_path->{'cgi-bin'} 
        ||= $self->config_data('cgibin')
	    || GuessDirectories->cgibin;
    $self->install_path->{'etc'} 
        ||= File::Spec->catfile($self->prefix||'',GuessDirectories->etc);
    $self->install_path->{'database'} 
        ||= $self->config_data('database')
	    || GuessDirectories->databases;
    
    # there's got to be a better way to avoid overwriting the config file
    my $old_conf = File::Spec->catfile($self->install_path->{conf},'GBrowse.conf');
    my $rename_conf;
    if (-e $old_conf) {
	warn "Detected existing GBrowse config file in ",
	      $self->install_path->{conf},'. ',
	      "New version will be installed as GBrowse.conf.new.\n";
	$rename_conf = rename $old_conf,"$old_conf.orig";
    }

    $self->SUPER::ACTION_install();

    if ($rename_conf) {
	rename $old_conf,"$old_conf.new";
	rename "$old_conf.orig",$old_conf;
    }

    my $user = $self->config_data('wwwuser') || GuessDirectories->wwwuser;

    # fix some directories so that www user can write into them
    my $tmp = $self->config_data('tmp') || GuessDirectories->tmp;
    mkdir $tmp;
    my ($uid,$gid) = (getpwnam($user))[2,3];

    # taint check issues
    $uid =~ /^(\d+)$/;
    $uid = $1;
    $gid =~ /^(\d+)$/;
    $gid = $1;
    
    chown $uid,$gid,$tmp;

    my $htdocs_i = File::Spec->catfile($self->install_path->{htdocs},'i');
    my $images   = File::Spec->catfile($tmp,'images');
    chown $uid,-1,$self->install_path->{htdocs};
    {
	local $> = $uid;
	symlink($images,$htdocs_i);  # so symlinkifowner match works!
    }
    chown $>,-1,$self->install_path->{htdocs};

    my $databases = $self->install_path->{'database'};
    chown $uid,$gid,glob(File::Spec->catfile($databases,'').'*');

    chmod 0755,File::Spec->catfile($self->install_path->{'etc'},'init.d','gbrowse-slave');
    $self->fix_selinux;

    my $base = basename($self->install_path->{htdocs});

    print STDERR "\n***INSTALLATION COMPLETE***\n";
    print STDERR "Load http://localhost/$base for demo and documentation\n";
}

sub ACTION_install_slave {
    my $self = shift;
    $self->SUPER::ACTION_install();
}

sub ACTION_debian {
    my $self = shift;
    system "debuild";
}

sub fix_selinux {
    my $self = shift;
    return unless -e '/proc/filesystems';
    my $f    = IO::File->new('/proc/filesystems') or return;
    return unless grep /selinux/i,<$f>;

    print STDERR "\n*** SELinux detected -- fixing permissions ***\n";

    my $htdocs = $self->config_data('htdocs');
    my $conf   = $self->config_data('conf');
    my $tmp    = $self->config_data('tmp');
    my $db     = $self->config_data('database');
    system "/usr/bin/chcon -R -t httpd_sys_content_t $conf";
    system "/usr/bin/chcon -R -t httpd_sys_content_t $htdocs";
    system "/usr/bin/chcon -R -t httpd_sys_content_rw_t $tmp";
    system "/usr/bin/chcon -R -t httpd_sys_content_rw_t $db";
}

sub process_conf_files {
    my $self = shift;
    my $f    = IO::File->new('MANIFEST');
    while (<$f>) {
	next unless m!^conf/!;
	chomp;
	my $copied = $self->copy_if_modified($_=>'blib');
	$self->substitute_in_place("blib/$_")
	    if $copied
	    or !$self->up_to_date('_build/config_data',"blib/$_");
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

sub process_etc_files {
    my $self = shift;
    my $f    = IO::File->new('MANIFEST');
    while (<$f>) {
	next unless m!^etc/!;
	chomp;
	my $copied = $self->copy_if_modified($_=>'blib');
	$self->substitute_in_place("blib/$_")
	    if $copied
	    or !$self->up_to_date('_build/config_data',"blib/$_");
    }
    # generate the apache config data
    my $includes = GuessDirectories->apache_includes || '';
    my $target   = "blib${includes}/gbrowse2.conf";
    if ($includes && !$self->up_to_date('_build/config_data',$target)) {
	warn "Creating include file for Apache config: $target\n";
	my $dir = dirname($target);
	mkpath([$dir]);
	if (my $f = IO::File->new("blib${includes}/gbrowse2.conf",'>')) {
	    $f->print($self->apache_conf);
	    $f->close;
	}

    }
}

sub process_database_files {
    my $self = shift;
    my $f    = IO::File->new('MANIFEST');
    while (<$f>) {
	next unless m!^sample_data/!;
	chomp;
	my ($subdir) = m!^sample_data/([^/]+)/!;
	$self->copy_if_modified(from    => $_,
				to_dir  => "blib/database/$subdir",
				flatten => 1,
	    );
    }
}

sub substitute_in_place {
    my $self = shift;
    my $path = shift;
    return if $path =~ /\.\w+$/ && $path !~ /\.(html|txt|conf)$/;
    my $in   = IO::File->new($path) or return;
    my $out  = IO::File->new("$path.$$",'>') or return;

    print STDERR "Performing variable substitutions in $path\n";

    my $htdocs     = $self->config_data('htdocs');
    my $conf       = $self->config_data('conf');
    my $cgibin     = $self->config_data('cgibin');
    my $databases  = $self->config_data('databases');
    my $tmp        = $self->config_data('tmp');
    my $wwwuser  = $self->config_data('wwwuser');
    my $perl5lib = $self->perl5lib || '';
    my $installscript = $self->scriptdir;

    while (<$in>) {
	s/\$INSTALLSCRIPT/$installscript/g;
	s/\$PERL5LIB/$perl5lib/g;
	s/\$HTDOCS/$htdocs/g;
	s/\$CONF/$conf/g;
	s/\$CGIBIN/$cgibin/g;
	s/\$WWWUSER/$wwwuser/g;
	s/\$DATABASES/$databases/g;
	s/\$TMP/$tmp/g;
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
    warn "NOTE: Run ./Build reconfig to change existing configuration.\n" if $done;
    return $done;
}

sub added_to_INC {
    my $self = shift;
    my @inc    = grep {!/install_util/} eval {$self->_added_to_INC};  # not in published API
    return @inc ? 'SetEnv PERL5LIB '.
	          join(':',@inc)
		: '';
}

sub perl5lib {
    my $self = shift;
    my @inc    = grep {!/install_util/} eval {$self->_added_to_INC};  # not in published API
    return unless @inc;
    return join(':',@inc);
}

sub scriptdir {
    my $self = shift;
    my $id   = $self->installdirs;
    my $scriptdir = $id eq 'site'   ? 'installsitescript'
                   :$id eq 'vendor' ? 'installvendorscript'
                   : 'installscript';
    return $Config::Config{$scriptdir};
}

# sub biographics_needs_patch  {
#     my $self = shift;
#     eval "require Bio::Graphics::Panel; 1"   or return 1;
#     my $version = eval {Bio::Graphics::Panel->api_version} || 0;
#     return $version < 1.8;
# }

# sub biodbseqfeature_needs_patch  {
#     my $self = shift;
#     eval "require Bio::DB::SeqFeature::Store; 1"   or return 1;
#     my $version = eval {Bio::DB::SeqFeature::Store->api_version} || 0;
#     return $version < 1.2;
# }


# sub patch_biographics {
#     my $self   = shift;
#     $self->config(patch_biographics=>1);
# }

# sub patch_biodbseqfeature {
#     my $self = shift;
#     $self->config(patch_biodbseqfeature=>1);
# }

# sub find_pm_files {
#     my $self = shift;
#     my %results  = %{$self->_find_file_by_type('pm','lib')};

#     my @extra_libs;
#     push @extra_libs,'extras/biographics'     
# 	if $self->biographics_needs_patch || $ENV{GBROWSE_DEBIAN_BUILD};
#     push @extra_libs,'extras/biodbseqfeature' 
# 	if $self->biodbseqfeature_needs_patch || $ENV{GBROWSE_DEBIAN_BUILD};

#     for my $l (@extra_libs) {
# 	my $r = $self->_find_file_by_type('pm',$l);
# 	for my $k (keys %$r) {
# 	    $r->{$k} =~ s!$l/!lib/!;
# 	}
# 	%results = (%results,%$r);
#     }
#     return \%results;
# }

1;

__END__

=head1 ACTIONS

=over 4

=item config

Interactively configure the locations in which GBrowse's scripts,
configuration files, and static image/support files will be installed.

One or more of the config options can be set on the command 
line when first running perl Build.PL:

  perl Build.PL --conf=/etc/growse2 \         # config files
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

=item debian

Build Debian source & binary packages.

=back
