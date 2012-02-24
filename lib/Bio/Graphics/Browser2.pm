package Bio::Graphics::Browser2;
# $Id$
# Globals and utilities for GBrowse and friends

our $VERSION = '2.48';

use strict;
use warnings;
use base 'Bio::Graphics::Browser2::AuthorizedFeatureFile';

use File::Spec;
use File::Path 'mkpath';
use File::Basename 'dirname','basename';
use Text::ParseWords 'shellwords';
use File::Path 'mkpath';
use Bio::Graphics::Browser2::DataSource;
use Bio::Graphics::Browser2::Session;
use GBrowse::ConfigData;
use Carp qw(croak carp confess cluck);

use constant DEFAULT_MASTER => 'GBrowse.conf';

my (%CONFIG_CACHE,$HAS_DBFILE,$HAS_STORABLE);

# Open a globals object with a config file in the standard location.
sub open_globals {
    my $self = shift;
    my $conf_dir  = $self->config_base;
    my $conf_file = $ENV{GBROWSE_MASTER} || DEFAULT_MASTER;
    my $path      = File::Spec->catfile($conf_dir,$conf_file);
    die "No GBrowse configuration file at $path!" unless -r $path;
    return $self->new($path);
}

sub new {
  my $class            = shift;
  my $config_file_path = shift;

  # Cache the config info so we don't need to reparse in a persistent (e.g. modperl) environment
  my $mtime            = (stat($config_file_path))[9] || 0;
  if (exists $CONFIG_CACHE{$config_file_path}
      && $CONFIG_CACHE{$config_file_path}{mtime} >= $mtime) {
    return $CONFIG_CACHE{$config_file_path}{object};
  }

  my $self = $class->SUPER::new(-file=>$config_file_path,
                                -safe=>1);

  # a little trick here -- force the setting of "config_base" from the config file
  # base if not explicitly overridden
  unless ($self->setting('general' => 'config_base')) {
    my $dir = dirname($config_file_path);
    $self->setting('general' => 'config_base',$dir);
  }

  $CONFIG_CACHE{$config_file_path}{object} = $self;
  $CONFIG_CACHE{$config_file_path}{mtime}  = $mtime;
  return $self;
}

## methods for dealing with paths
sub resolve_path {
  my $self = shift;
  my $path      = shift;
  my $path_type = shift; # one of "config" "htdocs" or "url"
  return unless $path;
  return $path if $path =~ m!^/!;           # absolute path
  return $path if $path =~ m!\|\s*$!;       # a pipe
  return $path if $path =~ m!^(http|ftp):!; # an URL
  my $method = ${path_type}."_base";
  $self->can($method) or confess "path_type must be one of 'config','htdocs', or 'url'";
  my $base   = $self->$method or return $path;
  return File::Spec->catfile($base,$path);
}

sub config_path {
  my $self    = shift;
  my $option  = shift;
  $self->resolve_path($self->setting(general => $option),'config');
}

sub htdocs_path {
  my $self    = shift;
  my $option  = shift;
  $self->resolve_path($self->setting(general => $option),'htdocs') 
      || "$ENV{DOCUMENT_ROOT}/gbrowse2";
}

sub url_path {
  my $self    = shift;
  my $option  = shift;
  $self->resolve_path( scalar($self->setting(general => $option)),'url');
}

sub config_base {$ENV{GBROWSE_CONF} 
		    || eval {shift->setting(general=>'config_base')}
			|| GBrowse::ConfigData->config('conf')
		              || '/etc/GBrowse2' }
sub htdocs_base {$ENV{GBROWSE_HTDOCS}
		 || eval{shift->setting(general=>'htdocs_base')}
                    || GBrowse::ConfigData->config('htdocs')
		        || '/var/www/gbrowse2'     }
sub url_base    {eval{shift->setting(general=>'url_base')}   
                     || basename(GBrowse::ConfigData->config('htdocs'))
		        || '/gbrowse2'             }

sub tmp_base    {eval{shift->setting(general=>'tmp_base')}
                     || GBrowse::ConfigData->config('tmp')
			|| '/tmp' }
sub persistent_base    {
    my $self = shift;
    my $base = $self->setting(general=>'persistent_base');
    return $base || $self->tmp_base;  # for compatibility with pre 2.27 installs
}
sub db_base        { 
    my $self = shift;
    my $base = $self->setting(general=>'db_base');
    return $base || File::Spec->catfile(shift->persistent_base,'databases');
}
sub userdata_base  { 
    my $self = shift;
    my $base = $self->setting(general=>'userdata_base');
    return $base ||  File::Spec->catfile($self->persistent_base,'userdata');
}

# these are url-relative options
sub button_url  { shift->url_path('buttons')            }
sub balloon_url { shift->url_path('balloons')           }
sub openid_url  { shift->url_path('openid')             }
sub js_url      { shift->url_path('js')                 }
sub help_url    { shift->url_path('gbrowse_help')       }
sub stylesheet_url   { shift->url_path('stylesheet')    }
sub auth_plugin { shift->setting(general=>'authentication plugin') }

# this returns the base URL and path info for use in constructing
# links. For example, if gbrowse is running at http://foo.bar/cgi-bin/gb2/gbrowse/yeast,
# it will return the list ('http://foo.bar/cgi-bin/gb2','yeast')
sub gbrowse_base {
    my $self   = shift;
    my $url    = CGI::url();
    my $source = $self->get_source_from_cgi;
    $source    = CGI::escape($source);
    $url =~   s!/[^/]*$!!;
    return ($url,$source);
}

# this returns the URL of the "master" gbrowse instance
sub gbrowse_url {
    my $self            = shift;
    my $fallback_source = shift;
    my ($base,$source) = $self->gbrowse_base;
    $source          ||= $fallback_source if $fallback_source;
    return "$base/gbrowse/$source";
}

sub make_path {
    my $self = shift;
    my $path = shift;
    return unless $path =~ /^(.+)$/;
    $path = $1;
    mkpath($path,0,0777) unless -d $path;    
}

sub tmpdir {
    my $self       = shift;
    my @components = @_;
    my $path = File::Spec->catfile($self->tmp_base,@components);
    $self->make_path($path) unless -d $path;
    return $path;
}

sub user_dir {
    my $self       = shift;
    my @components = @_;
    my $base       = $self->userdata_base;
    return File::Spec->catfile($base,@components);
}

sub admin_dir {
    my $self = shift;
    my @components = @_;
    my $path = $self->admin_dbs();
    return File::Spec->catfile($path,@components);
}

sub tmpimage_dir {
    my $self  = shift;
    return $self->tmpdir('images',@_);
}

sub image_url {
    my $self = shift;
    my $path = File::Spec->catfile($self->url_base,'i');
    return $path;
}

sub cache_dir {
    my $self  = shift;
    my $path  = File::Spec->catfile($self->tmp_base,'cache',@_);
    $self->make_path($path) unless -d $path;
    return $path;
}

sub session_locks {
    my $self = shift;
    my $path  = File::Spec->catfile($self->tmp_base,'locks',@_);
    $self->make_path($path) unless -d $path;
    return $path;
}

# return one of
# 'flock'  -- standard flock locking
# 'nfs'    -- use File::NFSLock
# 'mysql'  -- use mysql advisory locks
sub session_locktype {
    my $self = shift;
    return $self->setting(general=>'session lock type') || 'default';
}

sub session_dir {
    my $self = shift;
    my $path  = File::Spec->catfile($self->persistent_base,'sessions',@_);
    $self->make_path($path) unless -d $path;
    return $path;
}

sub slave_dir {
    my $self = shift;
    my $path = $self->setting(general=>'tmp_slave') || '/tmp/gbrowse_slave';
    $self->make_path($path) unless -d $path;
    return $path;
}

sub slave_status_path {
    my $self = shift;
    my $path = File::Spec->catfile($self->tmp_base,'slave_status');
    return $path;
}

# these are relative to the config base
sub plugin_path    { shift->config_path('plugin_path')     }
sub language_path  { shift->config_path('language_path')   }
sub templates_path { shift->config_path('templates_path')  }
sub moby_path      { shift->config_path('moby_path')       }

sub global_timeout         { shift->setting(general=>'global_timeout')      ||  60   }
sub remember_settings_time { shift->setting(general=>'expire session')      || '1M'  }
sub cache_time             { shift->setting(general=>'expire cache')        || '2h'  }
sub upload_time            { shift->setting(general=>'expire uploads')      || '6w'  }
sub datasources_expire     { shift->setting(general=>'expire data sources') || '10m' }
sub url_fetch_timeout      { shift->setting(general=>'url_fetch_timeout')            }
sub url_fetch_max_size     { shift->setting(general=>'url_fetch_max_size')           }

sub application_name       { shift->setting(general=>'application_name')      || 'GBrowse'                    }
sub application_name_long  { shift->setting(general=>'application_name_long') || 'The Generic Genome Browser' }
sub email_address          { shift->setting(general=>'email_address')         || 'noreply@gbrowse.com'        }
sub smtp                   { my $smtp = shift->setting(general=>'smtp_gateway'); return  if $smtp eq 'none'; return $smtp  }
sub smtp_enabled           { return defined shift->smtp;                                                      }
sub user_account_db        { shift->setting(general=>'user_account_db')                                       } # Used by uploads & user databases, they set their own defaults.
sub user_accounts	   { my $self = shift;
			     return $self->setting(general=>'user_accounts') ||
				    $self->setting(general=>'user_accounts')  || 
				    0; }
sub user_accounts_allow_registration
                           { 
			       my $val = shift->setting(general=>'user_accounts_registration');
			       return 1 unless defined $val;
			       return $val;
			   }
sub user_accounts_allow_openid
                           { 
			       my $val = shift->setting(general=>'user_accounts_openid');
			       return 1 unless defined $val;
			       return $val;
			   }
sub public_files           { shift->setting(general=>'public_files')          || 10                           }
sub admin_account          { shift->setting(general=>'admin_account')                                         }
sub admin_dbs              { shift->setting(general=>'admin_dbs')                                             }
sub openid_secret {
    return GBrowse::ConfigData->config('OpenIDConsumerSecret')
}

# uploads
sub upload_db_adaptor {
    my $self = shift;
    my $adaptor = $self->setting(general=>'upload_db_adaptor') || $self->setting(general=>'userdb_adaptor');
    warn "The upload_db_adaptor in your Gbrowse.conf file isn't in the DBI::<module> format: remember, it's not a connection string." if $adaptor =~ /^DBI/ && $adaptor !~ /(^DBI::+)/i;
    return $adaptor;
}
sub upload_db_host {
    my $self = shift;
    return $self->setting(general=>'upload_db_host') || $self->setting(general=>'userdb_host') || 'localhost'
}
sub upload_db_user {
    my $self = shift;
    return $self->setting(general=>'upload_db_user') || $self->setting(general=>'userdb_user') || '';
}
sub upload_db_pass {
    my $self = shift;
    return $self->setting(general=>'upload_db_pass') || $self->setting(general=>'userdb_pass') || '';
}

sub session_driver {
    my $self = shift;
    my $driver = $self->setting(general=>'session driver');
    return $driver if $driver;

    $HAS_DBFILE = eval "require DB_File; 1" || 0
	unless defined $HAS_DBFILE;
    $HAS_STORABLE = eval "require Storable; 1" || 0
	unless defined $HAS_STORABLE;

    my $sdriver    = $HAS_DBFILE ? 'db_file' : 'file';
    my $serializer = $HAS_STORABLE ? 'storable' : 'default';

    return "driver:$sdriver;serializer:$serializer";
}

sub session_args    {
  my $self = shift;
  my %args = shellwords($self->setting(general=>'session args')||'');
  return \%args if %args;
  return {Directory=>$self->session_dir};
}

## methods for dealing with data sources
sub data_sources {
  return sort grep {!/^\s*=~/ && !/:plugin$/} shift->SUPER::configured_types();
}

sub data_source_description {
  my $self = shift;
  my $dsn  = shift;
  return $self->setting($dsn=>'description');
}

sub data_source_restrict {
  my $self = shift;
  my $dsn  = shift;
  return $self->setting($dsn=>'restrict');
}

sub data_source_show {
    my $self = shift;
    my $dsn      = shift;
    my ($username,$authenticator) = @_;
    return if $self->setting($dsn=>'hide');

    # because globals are cached between use, we do not want usernames
    # to be defined outside the scope of this call
    local $self->{'.authenticated_username'} = $username      if defined $username;
    local $self->{'.authenticator'}          = $authenticator if defined $authenticator;
    return $self->authorized($dsn);
}

sub data_source_path {
  my $self = shift;
  my $dsn  = shift;
  my ($regex_key) = grep { $dsn =~ /^$_$/ } map { $_ =~ s/^=~//; $_ } grep { $_ =~ /^=~/ } keys(%{$self->{config}});
  if ($regex_key) {
      my $path = $self->resolve_path($self->setting("=~".$regex_key=>'path'),'config');
      my @matches = ($dsn =~ /$regex_key/);
      for (my $i = 1; $i <= scalar(@matches); $i++) {
	  $path =~ s/\$$i/$matches[$i-1]/;
      }
      return $self->resolve_path($path, 'config');
  }
  my $path = $self->setting($dsn=>'path') or return;
  $self->resolve_path($path,'config');
}

sub authorized {
    my $self = shift;
    my $sourcename = shift;
    my ($username,$authenticator)   = @_;
    local $self->{'.authenticated_username'} = $username      if defined $username;
    local $self->{'.authenticator'}          = $authenticator if defined $authenticator;
    return $self->SUPER::authorized($sourcename);
}

sub create_data_source {
  my $self = shift;
  my $dsn  = shift;
  my $path = $self->data_source_path($dsn) or return;
  my ($regex_key) = grep { $dsn =~ /^$_$/ } map { $_ =~ s/^=~//; $_ } grep { $_ =~ /^=~/ } keys(%{$self->{config}});
  my $name = $dsn;
  if ($regex_key) { $dsn = "=~".$regex_key; }
  my $source = Bio::Graphics::Browser2::DataSource->new($path,
							$name,
							$self->data_source_description($dsn),
							$self) or return;
  if (my $adbs = $self->admin_dbs) {
      my $path  = File::Spec->catfile($adbs,$dsn);
      my $expr = "$path/*/*.conf";
      $source->add_conf_files($expr);
  }
  return $source;
}

sub max_features {
    my $self = shift;
    my $max = $self->setting(general => 'maximum features');
    return 5000 unless defined $max;
    return $max;
}

sub default_source {
  my $self    = shift;
  my $source  = $self->setting(general => 'default source');
  return $source if $self->valid_source($source);
  return ($self->data_sources)[0];
}

sub valid_source {
  my $self            = shift;
  my $proposed_source = shift;

  if (!exists($self->{config}{$proposed_source})) {
    my ($regex_key) = grep { $proposed_source =~ /^$_$/ } map { $_ =~ s/^=~//; $_ } grep { $_ =~ /^=~/ } keys(%{$self->{config}});
    return unless $regex_key;
    my $path =  $self->data_source_path("=~" . $regex_key) or return;
    return -e $path || $path =~ /\|\s*$/;
  }

  return unless exists $self->{config}{$proposed_source};
  my $path =  $self->data_source_path($proposed_source) or return;
  return -e $path || $path =~ /\|\s*$/;
}

sub get_source_from_cgi {
    my $self = shift;

    my $source = CGI::param('source') || CGI::param('src') || CGI::path_info();
    $source    =~ s!\#$!!;  # get rid of trailing # left by IE
    $source    =~ s!^/+!!;  # get rid of leading & trailing / from path_info()
    $source    =~ s!/+$!!;
    
    $source;
}

sub update_data_source {
  my $self    = shift;
  my $session    = shift;
  my $new_source = shift;
  my $old_source = $session->source || $self->default_source;

  $new_source ||= $self->get_source_from_cgi();

  my $source;
  if ($self->valid_source($new_source)) {
    $session->source($new_source);
    $source = $new_source;
  } else {
    my $fallback_source = $self->valid_source($old_source) 
	? $old_source
	: $self->default_source;
    $session->source($fallback_source);
    $source = $fallback_source;
  }
  return $source;
}

sub time2sec {
    my $self = shift;
    my $time  = shift;
    $time =~ s/\s*#.*$//; # strip comments

    my(%mult) = ('s'=>1,
                 'm'=>60,
                 'h'=>60*60,
                 'd'=>60*60*24,
                 'w'=>60*60*24*7,
                 'M'=>60*60*24*30,
                 'y'=>60*60*24*365);
    my $offset = $time;
    if (!$time || (lc($time) eq 'now')) {
	$offset = 0;
    } elsif ($time=~/^([+-]?(?:\d+|\d*\.\d*))([smhdwMy])/) {
	$offset = ($mult{$2} || 1)*$1;
    }
    return $offset;
}

## methods for dealing with the session
sub session {
  my $self  = shift;
  my ($id,$mode) = @_;

  $id ||= undef;
  my @args       = (driver   => $self->session_driver,
                    args     => $self->session_args,
                    source   => $self->default_source,
                    lockdir  => $self->session_locks,
                    locktype => $self->session_locktype,
		    mode     => $mode || 'exclusive',
                    expires  => $self->remember_settings_time);
  return Bio::Graphics::Browser2::Session->new(@args,id => $id);
}

sub authorized_session {
  my $self                     = shift;
  my ($id,$authority,$shared_ok) = @_;

  $id       ||= undef;
  my $session = $self->session($id,$shared_ok ? 'shared' : 'exclusive');

  return $session unless $session->private;

  if ($session->match_nonce($authority,CGI::remote_addr())) {
      return $session;
  } else {
      cluck "UNAUTHORIZED ATTEMPT";
      return $self->session('xyzzy');
  }
}

1;
