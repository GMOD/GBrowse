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
use IO::Dir;
use File::Compare 'compare';
use File::Copy    'copy';
use GBrowseGuessDirectories;

use overload '""' => 'asString',
    fallback => 1;

use constant REGISTRATION_SERVER => 'http://modencode.oicr.on.ca/cgi-bin/gbrowse_registration';

my @OK_PROPS = (conf          => 'Directory for GBrowse\'s config and support files?',
		htdocs        => 'Directory for GBrowse\'s static images & HTML files?',
		tmp           => 'Directory for GBrowse\'s temporary data',
		persistent    => 'Directory for GBrowse\'s sessions, uploaded tracks and other persistent data',
		databases     => 'Directory for GBrowse\'s example databases',
		cgibin        => 'Directory for GBrowse\'s CGI script executables?',
		portdemo      => 'Internet port to run demo web site on (for demo)?',
		apachemodules => 'Apache loadable module directory (for demo)?',
		wwwuser       => 'User account under which Apache daemon runs?',
		installconf   => 'Automatically update Apache config files to run GBrowse?',
		installetc    => 'Automatically update system config files to run gbrowse-slave?',
    );
my %OK_PROPS = @OK_PROPS;

# TO FIX: this contains much of the same code as in the non-demo build
# and should be refactored.
sub ACTION_demo {
    my $self = shift;
    $self->depends_on('config_data');

    my $dir  = tempdir(
	'GBrowse_demo_XXXX',
	TMPDIR=>1,
	CLEANUP=>0,
	);
    my $port = $self->config_data('portdemo') 
	|| GBrowseGuessDirectories->portdemo();
    my $modules = $self->config_data('apachemodules')
	|| GBrowseGuessDirectories->apachemodules;
    my $db      = $self->config_data('databases')
	|| GBrowseGuessDirectories->databases;
    my $cgiurl  = $self->cgiurl;
    my $persistent = $self->config_data('persistent');

    mkdir "$dir/conf";
    mkdir "$dir/htdocs";
    mkdir "$dir/logs";
    mkdir "$dir/locks";
    mkdir "$dir/tmp";

    # make copies of htdocs and conf
    open my $saveout,">&STDOUT";
    open STDOUT,">/dev/null";

    my $f    = IO::File->new('MANIFEST');
    while (<$f>) {
	chomp;
	if (m!^(conf|htdocs)!) {
	    $self->copy_if_modified($_ => $dir);
	} elsif (m!cgi-bin!) {
	    $self->copy_if_modified(from => $_,to_dir => "$dir/cgi-bin/gb2",flatten=>1);
	} elsif (m!^sample_data!) {
	    chdir $self->base_dir();
	    my ($subdir) = m!^sample_data/([^/]+)/!;
	    $self->copy_if_modified(from    => $_,
				    to_dir  => "$dir/htdocs/databases/$subdir",
				    flatten => 1,
		);
	}
    }
    close $f;
    chdir $self->base_dir;
    open STDOUT,"<&",$saveout;

    # fix GBrowse.conf to point to correct directories
    for my $f ("$dir/conf/GBrowse.conf",
	       "$dir/conf/GBrowse.psgi",
	       "$dir/conf/yeast_simple.conf",
	       "$dir/conf/yeast_chr1+2.conf",
	       "$dir/conf/pop_demo.conf",
	       "$dir/conf/yeast_renderfarm.conf",
	       "$dir/htdocs/index.html") {
	my $in  = IO::File->new($f)         or die "$dir/conf/$f: $!";
	my $out = IO::File->new("$f.new",'>') or die $!;
	while (<$in>) {
	    
	    s!\$ROOT!$dir!g;
	    s!\$CONF!$dir/conf!g;
	    s!\$HTDOCS!$dir/htdocs!g;
	    s!\$DATABASES!$dir/htdocs/databases!g;
	    s!\$PERSISTENT!$dir/$persistent!g;
	    s!\$TMP!$dir/tmp!g;
	    s/\$CGIURL/$cgiurl/g;
	    s!\$VERSION!$self->dist_version!eg;
	    s/\$CAN_USER_ACCOUNTS_OPENID/$self->has_openid/eg;
	    s/\$CAN_USER_ACCOUNTS_REG/$self->has_smtp/eg;
	    s/\$CAN_USER_ACCOUNTS/$self->has_mysql_or_sqlite/eg;
	    s/\$USER_ACCOUNT_DB/$self->guess_user_account_db/eg;
	    s/\$SMTP_GATEWAY/$self->guess_smtp_gateway/eg;
	    s!^url_base\s*=.+!url_base               = /!g;
	    s!^user_accounts[^=]+=.*!user_accounts = 0!;
	    $out->print($_);
	}
	close $out;
	rename "$f.new",$f;
    }
    
    my $conf_data = $self->httpd_conf($dir,$port);
    my $conf = IO::File->new("$dir/conf/httpd.conf",'>')
	or die "$dir/conf/httpd.conf: $!";
    $conf->print($conf_data);
    $conf->close;

    $conf_data = $self->gbrowse_demo_conf($port,$dir);
    $conf = IO::File->new("$dir/conf/apache_gbrowse.conf",'>') 
	or die "$dir/conf/apache_gbrowse.conf: $!";
    $conf->print($conf_data);
    $conf->close;

    $conf_data = $self->mime_conf();
    my $mime = IO::File->new("$dir/conf/mime.types",'>') 
	or die "$dir/conf/mime.types: $!";
    $mime->print($conf_data);
    $mime->close;

    my $apache =  GBrowseGuessDirectories->apache
	or die "Could not find apache executable on this system. Can't run demo";

    system "$apache -k start -f $dir/conf/httpd.conf";
    sleep 3;
    if (-e "$dir/logs/apache2.pid") {
	print STDERR "Demo config and log files have been written to $dir\n";
	print STDERR "Demo is now running on http://localhost:$port\n";
	print STDERR "Run \"./Build demostop\" to stop it.\n";
	$self->config_data(demodir=>$dir);
    } else {
	print STDERR "Apache failed to start. Perhaps the demo is already running?\n";
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
    my $apache =  GBrowseGuessDirectories->apache
	or die "Could not find apache executable on this system. Can't stop demo";

    system "$apache -k stop -f $dir/conf/httpd.conf";
    rmtree([$dir,"$home/htdocs/tmp"]);
    $self->config_data('demodir'=>undef);
    print STDERR "Demo stopped.\n";
}

sub ACTION_clean {
    my $self = shift;
    $self->SUPER::ACTION_clean;
    unlink 'INSTALL.SKIP';
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
    $self->depends_on('register') unless $self->registration_done;
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
    warn "\n**Paths reconfigured. Running \"Build clean\".\n";
    $self->ACTION_clean;
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

    my $prefix = $self->install_base || $self->prefix || '';
    GBrowseGuessDirectories->prefix($prefix);

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
	my $conf_dir = $props->{$key} =~ /directory/i;

	$opts{$key} = prompt($props->{$key},
			     $opts{$key} ||
			     ($conf_dir 
			     ? File::Spec->canonpath(
				 File::Spec->catfile(GBrowseGuessDirectories->$key($opts{apache})))
			     : GBrowseGuessDirectories->$key($opts{apache})));
	if ($conf_dir) {
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

sub ACTION_register {
    my $self = shift;
    return unless -t STDIN;
    print STDERR "\n**Registration**\nGBrowse2 registration is optional, but will help us maintain funding for this project.\n";
    if (Module::Build->y_n("Do you wish to register your installation?",'y')) {
	print STDERR "All values are optional, but appreciated.\n";
	my $user  = prompt('Your name:');
	my $email = prompt('Your email address:');
	my $org   = prompt('Your organization:');
	my $organism = prompt('Organisms you will be using GBrowse for (one line):');
	my $site  = prompt('If GBrowse will be public, the URL of your web site:');
	my $result = eval {
	    eval "use HTTP::Request::Common";
	    eval "use LWP::UserAgent";
	    my $ua = LWP::UserAgent->new;
	    my $response = $ua->request(POST(REGISTRATION_SERVER,
					     [user=>$user,email=>$email,
					      org=>$org,organism=>$organism,
					      site=>$site]
					));
	    die $response->status_line unless $response->is_success;
	    my $content = $response->decoded_content;
	    $content eq 'ok';
	};
	if ($@) {
	    print STDERR "An error occurred during registration: $@\n";
	    print STDERR "If you are able to fix the error, you can register later ";
	    print STDERR "using \"./Build register\"\n";
	} else {
	    print STDERR $result ? "Thank you. Your registration was sent successfully.\n"
		                 : "An error occurred during registration. Thanks anyway.\n";
	}
    } else {
	print STDERR "If you wish to register at a later time please \"./Build register\"\n";
	print STDERR "Press any key to continue\n";
	my $h = <STDIN>;
    }
    $self->registration_done(1);
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
    my $dir       = $self->config_data('htdocs');
    my $conf      = $self->config_data('conf');
    my $cgibin    = $self->config_data('cgibin');
    my $tmp       = $self->config_data('tmp');
    my $databases = $self->config_data('databases');
    my $cgiroot = basename($cgibin);
    my $perl5lib= $self->added_to_INC;
    my $inc      = $perl5lib ? "SetEnv PERL5LIB \"$perl5lib\"" : '';
    my $fcgi_inc = $perl5lib ? "-initial-env PERL5LIB=$perl5lib"        : '';
    my $fcgid_inc= $perl5lib ? "FcgidInitialEnv PERL5LIB $perl5lib"        : '';
    my $modperl_switches = $perl5lib
	? "PerlSwitches ".join ' ',map{"-I$_"} split ':',$perl5lib
        : '';

    return <<END;
Alias        "/gbrowse2/i/" "$tmp/images/"
Alias        "/gbrowse2"    "$dir"
ScriptAlias  "/gb2"      "$cgibin"

<Directory "$dir">
  AllowOverride Options
  Options -Indexes -MultiViews +FollowSymLinks
  Order allow,deny
  Allow from all
</Directory>

<Directory "$dir/tutorial">
  Options +Indexes
</Directory>

<Directory "$tmp/images/">
  Order allow,deny
  Allow from all
</Directory>

<Directory "$databases">
  Order allow,deny
  Deny from all
</Directory>

<Directory "$cgibin">
  ${inc}
  Options ExecCGI
  SetEnv GBROWSE_CONF   "$conf"
</Directory>

<IfModule mod_fcgid.c>
  Alias /fgb2 "$cgibin"
  <Location /fgb2>
    SetHandler   fcgid-script
  </Location>
  FcgidInitialEnv GBROWSE_CONF $conf
  # these directives prevent idle/busy timeouts and may need to be
  # adjusted up or down
  FcgidMinProcessesPerClass 6
  FcgidIOTimeout   600
  FcgidBusyTimeout 600
  $fcgid_inc
</IfModule>

<IfModule mod_fastcgi.c>
  Alias /fgb2 "$cgibin"
  <Location /fgb2>
    SetHandler   fastcgi-script
  </Location>
  # Note: you may need to increase -idle-timeout if file uploads are timing out and returning server
  # errors.
  FastCgiConfig -idle-timeout 600 -maxClassProcesses 20 $fcgi_inc -initial-env GBROWSE_CONF=$conf 
</IfModule>

# Use of mod_perl is no longer supported. Use at your own risk.
<IfModule mod_perl.c>
   Alias /mgb2 "$cgibin"
   $modperl_switches
   <Location /mgb2>
     SetHandler perl-script
     PerlResponseHandler ModPerl::Registry
     PerlOptions +ParseHeaders
   </Location>
</IfModule>
END
}

sub ACTION_install {
    my $self = shift;
    my $prefix = $self->install_base || $self->prefix || '';
    GBrowseGuessDirectories->prefix($prefix);

    $self->depends_on('config_data');
    $self->install_path->{conf} 
        ||= $self->config_data('conf') || GBrowseGuessDirectories->conf;
    $self->install_path->{htdocs}
        ||= $self->config_data('htdocs')
	    || GBrowseGuessDirectories->htdocs;
    $self->install_path->{'cgi-bin'} 
        ||= $self->config_data('cgibin')
	    || GBrowseGuessDirectories->cgibin;
    $self->install_path->{'etc'} 
        ||= GBrowseGuessDirectories->etc;
    $self->install_path->{'databases'} 
        ||= $self->config_data('databases')
	    || GBrowseGuessDirectories->databases;
    $self->install_path->{'persistent'} 
        ||= $self->config_data('persistent')
	    || GBrowseGuessDirectories->persistent;
    
    $self->SUPER::ACTION_install();

    my $user = $self->config_data('wwwuser') || GBrowseGuessDirectories->wwwuser;

    # fix some directories so that www user can write into them
    my $tmp = $self->config_data('tmp') || GBrowseGuessDirectories->tmp;
    mkpath($tmp);
    my ($uid,$gid) = (getpwnam($user))[2,3];

    # taint check issues
    $uid =~ /^(\d+)$/;
    $uid = $1;
    $gid =~ /^(\d+)$/;
    $gid = $1;
    
    unless (chown $uid,$gid,$tmp) {
	$self->ownership_warning($tmp,$user);
    }

    my $htdocs_i = File::Spec->catfile($self->install_path->{htdocs},'i');
    my $images   = File::Spec->catfile($tmp,'images');
    my $htdocs = $self->install_path->{htdocs};
    chown $uid,-1,$htdocs;
    {
	local $> = $uid;
	symlink($images,$htdocs_i);  # so symlinkifowner match works!
    }
    chown $>,-1,$self->install_path->{htdocs};

    my $persistent = $self->install_path->{'persistent'};
    my $sessions   = File::Spec->catfile($persistent,'sessions');
    my $userdata   = File::Spec->catfile($persistent,'userdata');
    mkpath([$sessions,$userdata],0711);

    my $databases = $self->install_path->{'databases'};
    
    unless (chown $uid,$gid,glob(File::Spec->catfile($databases,'').'*')) {
	$self->ownership_warning($databases,$user);
    }

    chmod 0755,File::Spec->catfile($self->install_path->{'etc'},'init.d','gbrowse-slave');
    $self->fix_selinux;

    my $base = basename($self->install_path->{htdocs});

    # Configure the databases, if needed.
    print STDERR "Updating user account database...\n";
    my $metadb_script = File::Spec->catfile("bin", "gbrowse_metadb_config.pl");
    my $perl          = $self->perl;
    my @inc           = map{"-I$_"} split ':',$self->added_to_INC;
    system $perl,@inc,$metadb_script;
    system 'sudo','chown','-R',"$uid.$gid",$sessions,$userdata;

    if (Module::Build->y_n(
	    "It is recommended that you restart Apache. Shall I try this for you?",'y'
	)) {
	system "sudo /etc/init.d/apache2 restart";
    }
    
    print STDERR "\n***INSTALLATION COMPLETE***\n";
    print STDERR "Load http://localhost/$base for demo and documentation.\n";
    print STDERR "Visit the http://gmod.org for more information on setting up databases for users and custom tracks.\n";
}

sub ACTION_install_slave {
    my $self = shift;
    my $prefix = $self->install_base || $self->prefix ||'';
    GBrowseGuessDirectories->prefix($prefix);
    $self->install_path->{'etc'} ||= GBrowseGuessDirectories->etc;
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
    my $db     = $self->config_data('databases');
    system "/usr/bin/chcon -R -t httpd_sys_content_t $conf";
    system "/usr/bin/chcon -R -t httpd_sys_content_t $htdocs";
    system "/usr/bin/chcon -R -t httpd_sys_content_rw_t $tmp";
    system "/usr/bin/chcon -R -t httpd_sys_content_rw_t $db";
}

sub process_conf_files {
    my $self = shift;
    my $f    = IO::File->new('MANIFEST');

    my $prefix = $self->install_base || $self->prefix || '';
    GBrowseGuessDirectories->prefix($prefix);
    my $install_path = $self->config_data('conf') || GBrowseGuessDirectories->conf;
    my $skip;

    while (<$f>) {
	next unless m!^conf/!;
	chomp;
	my $base = $_;
	my $copied = $self->copy_if_modified($_=>'blib');
	$self->substitute_in_place("blib/$_")
	    if $copied
	    or !$self->up_to_date('_build/config_data',"blib/$_");
	
	if ($copied) {
	    $skip ||= IO::File->new('>>INSTALL.SKIP');
	    (my $new = $base) =~ s/^conf\///;
	    my $installed = File::Spec->catfile($install_path,$new);
	    if (-e $installed && $base =~ /\.conf$/ && (compare($base,$installed) != 0)) {
		warn "$installed is already installed. New version will be installed as $installed.new\n";
		rename ("blib/$base","blib/$base.new");
		print $skip '^',"blib/",quotemeta($base),'$',"\n";
	    }
	}
    }

    $skip->close if $skip;
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
	my $copied = $self->copy_if_modified($_=>'blib');
	my $path   = File::Spec->catfile('blib',$_);
	if ($copied) {
	    $self->fix_shebang_line($path);
	    chmod 0755,$path;
	}
    }
}

sub process_etc_files {
    my $self = shift;

    my $prefix = $self->install_base || $self->prefix || '';
    GBrowseGuessDirectories->prefix($prefix);
    my $install_path = GBrowseGuessDirectories->etc;

    my $skip;

    if ($self->config_data('installetc') =~ /^[yY]/) {
	my $f    = IO::File->new('MANIFEST');
	while (<$f>) {
	    next unless m!^etc/!;
	    chomp;

	    my $base = $_;

	    my $copied = $self->copy_if_modified($_=>'blib');
	    $self->substitute_in_place("blib/$_")
		if $copied
		or !$self->up_to_date('_build/config_data',"blib/$_");

	    if ($copied) {
		$skip ||= IO::File->new('>>INSTALL.SKIP');
		(my $new = $base) =~ s/^etc\///;
		my $installed = File::Spec->catfile($install_path,$new);
		if (-e $installed) {
		    warn "$installed is already installed. New version will be installed as $installed.new\n";
		    rename ("blib/$base","blib/$base.new");
		    print $skip '^',"blib/",quotemeta($base),'$',"\n";
		}
	    }
	}
    }

    $skip->close if $skip;

    # generate the apache config data
    my $includes = GBrowseGuessDirectories->apache_includes || '';

    # the following workaround checks for perl.conf (which must load before gbrowse.conf on modperl envs)
    # and renames the file so that it is loaded after perl.conf
    my $file     = -e "${includes}/perl.conf"   
	           ? 'z_gbrowse2.conf' 
                   : 'gbrowse2.conf';

    my $target   = "blib${includes}/$file";
    if ($includes && !$self->up_to_date('_build/config_data',$target)) {
	if ($self->config_data('installconf') =~ /^[yY]/ && !-e "${includes}/$file") {
	    warn "Creating include file for Apache config: $target\n";
	    my $dir = dirname($target);
	    mkpath([$dir]);
	    if (my $f = IO::File->new("blib${includes}/$file",'>')) {
		$f->print($self->apache_conf);
		$f->close;
	    }
	} else {
	    print STDERR 
	       -e "${includes}/$file"
		? "${includes}/$file is already installed. " 
		: "Automatic Apache config disabled. ";
	    print STDERR "Please run ./Build apache_conf to see this file's recommended contents.\n";
	}

    }
    if (!$self->config_data('installetc') =~ /^[yY]/) {
	warn "Not configuring your system to run gbrowse-slave automatically. Please reconfigure with this option enabled if you wish to do this.";
    }
}

sub process_database_files {
    my $self = shift;
    my $f    = IO::File->new('MANIFEST');
    while (<$f>) {
	next unless m!^sample_data/!;
	chomp;
        my $dest = $_;  $dest =~ s|^sample_data/||;
        $self->copy_if_modified(from => $_,
                                to   => "blib/databases/$dest",
                               );
    }
}

sub substitute_in_place {
    my $self = shift;
    my $path = shift;

    return if $path =~ /\.\w+$/ && $path !~ /\.(html|txt|conf|psgi)$/;

    my $in   = IO::File->new($path) or return;
    my $out  = IO::File->new("$path.$$",'>') or return;

    print STDERR "Performing variable substitutions in $path\n";

    my $htdocs     = $self->config_data('htdocs');
    my $conf       = $self->config_data('conf');
    my $cgibin     = $self->config_data('cgibin');
    my $persistent = $self->config_data('persistent');
    my $databases  = $self->config_data('databases');
    my $tmp        = $self->config_data('tmp');
    my $wwwuser    = $self->config_data('wwwuser');
    my $perl5lib   = $self->perl5lib || '';
    my $installscript =  $self->install_destination('script');
    my $etc         =  $self->install_path->{'etc'} ||= GBrowseGuessDirectories->etc;
    my $cgiurl        = $self->cgiurl;

    $persistent ||= $databases;

    while (<$in>) {
	s/\$INSTALLSCRIPT/$installscript/g;
	s/\$ETC/$etc/g;
	s/\$PERL5LIB/$perl5lib/g;
	s/\$HTDOCS/$htdocs/g;
	s/\$CONF/$conf/g;
	s/\$CGIBIN/$cgibin/g;
	s/\$CGIURL/$cgiurl/g;
	s/\$WWWUSER/$wwwuser/g;
	s/\$DATABASES/$databases/g;
	s/\$PERSISTENT/$persistent/g;
	s/\$VERSION/$self->dist_version/eg;
	s/\$CAN_USER_ACCOUNTS_OPENID/$self->has_openid/eg;
	s/\$CAN_USER_ACCOUNTS_REG/$self->has_smtp/eg;
	s/\$CAN_USER_ACCOUNTS/$self->has_mysql_or_sqlite/eg;
	s/\$USER_ACCOUNT_DB/$self->guess_user_account_db/eg;
	s/\$SMTP_GATEWAY/$self->guess_smtp_gateway/eg;
	s/\$TMP/$tmp/g;
	$out->print($_);
    }
    $in->close;
    $out->close;
    rename("$path.$$",$path);
}

sub generate_psgi_file {
    my $self = shift;
    my $path = shift;
    return if $path =~ /\.\w+$/ && $path !~ /\.(html|txt|conf)$/;
    my $in   = IO::File->new($path) or return;
    my $out  = IO::File->new("$path.$$",'>') or return;

    print STDERR "Performing variable substitutions in $path\n";

    my $htdocs     = $self->config_data('htdocs');
    my $conf       = $self->config_data('conf');
    my $cgibin     = $self->config_data('cgibin');
    my $persistent = $self->config_data('persistent');
    my $databases  = $self->config_data('databases');
    my $tmp        = $self->config_data('tmp');
    my $wwwuser    = $self->config_data('wwwuser');
    my $perl5lib   = $self->perl5lib || '';
    my $installscript =  $self->install_destination('script');
    my $etc         =  $self->install_path->{'etc'} ||= GBrowseGuessDirectories->etc;
    my $cgiurl        = $self->cgiurl;

    $persistent ||= $databases;

    while (<$in>) {
	s/\$INSTALLSCRIPT/$installscript/g;
	s/\$ETC/$etc/g;
	s/\$PERL5LIB/$perl5lib/g;
	s/\$HTDOCS/$htdocs/g;
	s/\$CONF/$conf/g;
	s/\$CGIBIN/$cgibin/g;
	s/\$CGIURL/$cgiurl/g;
	s/\$WWWUSER/$wwwuser/g;
	s/\$DATABASES/$databases/g;
	s/\$PERSISTENT/$persistent/g;
	s/\$VERSION/$self->dist_version/eg;
	s/\$CAN_USER_ACCOUNTS_OPENID/$self->has_openid/eg;
	s/\$CAN_USER_ACCOUNTS_REG/$self->has_smtp/eg;
	s/\$CAN_USER_ACCOUNTS/$self->has_mysql_or_sqlite/eg;
	s/\$USER_ACCOUNT_DB/$self->guess_user_account_db/eg;
	s/\$SMTP_GATEWAY/$self->guess_smtp_gateway/eg;
	s/\$TMP/$tmp/g;
	$out->print($_);
    }
    $in->close;
    $out->close;
    rename("$path.$$",$path);
}


sub has_mysql_or_sqlite {
    my $self = shift;
    return eval "require DBD::mysql; 1" || eval "require DBD::SQLite; 1" || 0;
}

sub has_smtp {
    my $self = shift;
    return eval "require Net::SMTP; 1" || 0;
}

sub has_openid {
    my $self = shift;
    return eval "require Net::OpenID::Consumer; require LWP::UserAgent; 1" || 0;
}

sub guess_user_account_db {
    my $self = shift;
    if (eval "require DBD::SQLite; 1") {
	my $databases = $self->config_data('databases');
	return "DBI:SQLite:$databases/users.sqlite";
    } elsif (eval "require DBD::mysql; 1") {
	return 'DBI:mysql:gbrowse_login;user=gbrowse;password=gbrowse';
    } else {
	return "no database defined # please correct this";
    }
}

sub guess_smtp_gateway {
    my $self = shift;
    return 'localhost  # this assumes that a correctly configured smtp server is running on current machine; change if necessary';
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
	|| GBrowseGuessDirectories->apachemodules;

    my $user    = $>;
    my ($group) = $) =~ /^(\d+)/;

    return <<END;
ServerName           "localhost"
ServerRoot           "$dir/conf"
LockFile             "$dir/locks/accept.lock"
PidFile              "$dir/logs/apache2.pid"
ErrorLog             "$dir/logs/error.log"
LogFormat            "%h %l %u %t \\"%r\\" %>s %b" common
CustomLog            "$dir/logs/access.log"      common
LogLevel             warn
User                 #$user
Group                #$group

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

sub gbrowse_demo_conf {
    my $self = shift;
    my ($port,$dir) = @_;
    my $blib = File::Spec->catfile($self->base_dir(),$self->blib);
    my $inc  = "$blib/lib:$blib/arch";
    my $more = $self->added_to_INC;
    $inc    .= ":$more" if $more;

    return <<END;
NameVirtualHost *:$port
<VirtualHost *:$port>
	ServerAdmin webmaster\@localhost
	Alias        "/i/"       "$dir/tmp/images/"
	ScriptAlias  "/cgi-bin/" "$dir/cgi-bin/"
	
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

	<Directory "$dir/cgi-bin/">
		SetEnv PERL5LIB $inc
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
    warn "NOTE: Run ./Build reconfig to change existing configuration.\n" if $done;
    return $done;
}

sub registration_done {
    my $self = shift;
    my $done = $self->config_data('registration_done');
    $self->config_data(registration_done=>shift) if @_;
    return $done;
}

sub added_to_INC {
    my $self       = shift;
    my @inc        = grep {!/install_util/} eval {$self->_added_to_INC};  # not in published API
    my $lib_base   = $self->install_destination('lib');
    my $arch_base  = $self->install_destination('arch');
    my %standard   = map {$_=>1} @INC;
    push @inc,$lib_base  unless $standard{$lib_base};
    push @inc,$arch_base unless $standard{$arch_base};
    return @inc ? join(':',@inc) : '';
}

sub perl5lib {
    my $self = shift;
    return $self->added_to_INC or undef;
}

sub scriptdir {
    my $self = shift;
    my $id   = $self->installdirs;
    my $scriptdir = $id eq 'core'   ? 'installscript'
                   :$id eq 'site'   ? 'installsitebin'
                   :$id eq 'vendor' ? 'installvendorbin'
		   :'installsitebin';
    return $Config::Config{$scriptdir};
}

sub ownership_warning {
    my $self = shift;
    my ($path,$owner) = @_;
    warn "*** WARNING: Using sudo to change ownership of $path to '$owner'. You may be prompted for your login password ***\n";
    system "sudo chown -R $owner $path";
}

sub cgiurl {
    my $self = shift;
    my $cgibin  = $self->config_data('cgibin');
    (my $cgiurl = $cgibin) =~ s!^.+/cgi-bin!/cgi-bin!;
    $cgiurl =~ s!^.+/CGI-Executables!/cgi-bin!; #Macs and their crazy paths
    return $cgiurl;
}

sub check_prereq {
    my $self   = shift;
    my $result = $self->SUPER::check_prereq(@_);
    unless ($result) {
	$self->log_warn(<<END);
  * Do not worry if some "recommended" prerequisites are missing. You can install *
  * them later if you need the features they provide. Do not proceed with the     *
  * install if any of "REQUIRED" prerequisites are missing.                       *
  *                                                                               *
  * The optional Safe::World module does not currently run on Perl 5.10 or        *
  * higher, and so cannot be installed.                                           *

END
    }
    return $result;
}

sub asString { return 'GBrowse installer' }

1;

__END__

=head1 ACTIONS

=over 4

=item config

Interactively configure the locations in which GBrowse's scripts,
configuration files, and static image/support files will be installed.

One or more of the config options can be set on the command 
line when first running perl Build.PL:

  perl Build.PL --conf=/etc/gbrowse2          \  # config files
                --htdocs=/var/www/gbrowse2    \  # static files
                --cgibin=/usr/lib/cgi-bin/gb2 \  # CGI executables
                --wwwuser=www-data            \  # apache user
                --tmp=/var/tmp/gbrowse2       \  # temporary data
                --portdemo=8000               \  # demo web site port
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
