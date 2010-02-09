package Bio::Graphics::Browser2;
# $Id$
# Globals and utilities for GBrowse and friends

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
use Carp 'croak','carp';

use constant DEFAULT_MASTER => 'GBrowse.conf';

my (%CONFIG_CACHE,$HAS_DBFILE,$HAS_STORABLE);
our $VERSION = '2.02';

sub open_globals {
    my $self = shift;
    my $conf_dir  = $self->config_base;
    my $conf_file = $ENV{GBROWSE_MASTER} || DEFAULT_MASTER;
    my $path      = File::Spec->catfile($conf_dir,$conf_file);
    return $self->new($path);
}

sub new {
  my $class            = shift;
  my $config_file_path = shift;

  # this code caches the config info so that we don't need to 
  # reparse in persistent (e.g. modperl) environment
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
  my $path = shift;
  my $path_type = shift; # one of "config" "htdocs" or "url"
  return unless $path;
  return $path if $path =~ m!^/!;           # absolute path
  return $path if $path =~ m!\|\s*$!;       # a pipe
  return $path if $path =~ m!^(http|ftp):!; # an URL
  my $method = ${path_type}."_base";
  $self->can($method) or croak "path_type must be one of 'config','htdocs', or 'url'";
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
  $self->resolve_path($self->setting(general => $option),'url');
}

sub config_base {$ENV{GBROWSE_CONF} 
		    || eval {shift->setting(general=>'config_base')}
			|| GBrowse::ConfigData->config('conf')
		              || '/etc/GBrowse2' }
sub htdocs_base {eval{shift->setting(general=>'htdocs_base')}
                    || GBrowse::ConfigData->config('htdocs')
		        || '/var/www/gbrowse2'     }
sub url_base    {eval{shift->setting(general=>'url_base')}   
                     || basename(GBrowse::ConfigData->config('htdocs'))
		        || '/gbrowse2'             }

sub tmp_base    {eval{shift->setting(general=>'tmp_base')}
                     || GBrowse::ConfigData->config('tmp')
			|| '/tmp' }
sub db_base     {eval{shift->setting(general=>'db_base')}
                    || GBrowse::ConfigData->config('databases')
			|| '//var/www/gbrowse2/databases' }

# these are url-relative options
sub button_url  { shift->url_path('buttons')            }
sub balloon_url { shift->url_path('balloons')           }
sub openid_url  { shift->url_path('openid')             }
sub js_url      { shift->url_path('js')                 }
sub help_url    { shift->url_path('gbrowse_help')       }
sub stylesheet_url   { shift->url_path('stylesheet')    }

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
    return $self->tmpdir('userdata',@components);
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
    my $path  = File::Spec->catfile($self->tmp_base,'sessions',@_);
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
sub smtp                   { shift->setting(general=>'smtp_gateway')          || 'smtp.res.oicr.on.ca'        }
sub user_account_db        { shift->setting(general=>'user_account_db')       
				   || 'DBI:mysql:gbrowse_login;user=gbrowse;password=gbrowse'  }
sub admin_account          { shift->setting(general=>'admin_account') }
sub admin_dbs              { shift->setting(general=>'admin_dbs')     }

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
  return sort shift->SUPER::configured_types();
}

sub data_source_description {
  my $self = shift;
  my $dsn  = shift;
  return $self->setting($dsn=>'description');
}

sub data_source_show {
    my $self = shift;
    my $dsn  = shift;
    return if $self->setting($dsn=>'hide');
    return $self->authorized($dsn);
}

sub data_source_path {
  my $self = shift;
  my $dsn  = shift;
  $self->resolve_path($self->setting($dsn=>'path'),'config');
}

sub create_data_source {
  my $self = shift;
  my $dsn  = shift;
  my $path = $self->data_source_path($dsn) or return;
  my $source = Bio::Graphics::Browser2::DataSource->new($path,
							$dsn,
							$self->data_source_description($dsn),
							$self) or return;
  if (my $adbs = $self->admin_dbs) {
      my $path  = File::Spec->catfile($adbs,$dsn);
      my $expr = "$path/*/*.conf";
      $source->add_conf_files($expr);
  }
  return $source;
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
    carp "Invalid source $new_source";
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
  my $id    = shift;

  $id ||= undef;
  my @args       = (driver   => $self->session_driver,
                    args     => $self->session_args,
                    source   => $self->default_source,
                    lockdir  => $self->session_locks,
                    locktype => $self->session_locktype,
                    expires  => $self->remember_settings_time);
  return Bio::Graphics::Browser2::Session->new(@args,id => $id);
}

sub authorized_session {
  my $self                     = shift;
  my ($id,$authority) = @_;

  $id       ||= undef;
  my $session = $self->session($id);
  return $session unless $session->private;

  if ($session->match_nonce($authority,CGI::remote_addr())) {
      return $session;
  } else {
      warn "UNAUTHORIZED ATTEMPT";
      return $self->session('xyzzy');
  }
}

1;
