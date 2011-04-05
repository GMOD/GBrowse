package Bio::Graphics::Browser2::Session;

# $Id$

use strict;
use warnings;

use CGI::Session;
use CGI::Cookie;
use Fcntl 'LOCK_EX','LOCK_SH';
use File::Spec;
use File::Path 'mkpath';
use Digest::MD5 'md5_hex';
use Carp 'carp';
use constant LOCK_TIMEOUT => 10;
eval "require Time::HiRes;";


my $HAS_NFSLOCK;
my $HAS_MYSQL;

BEGIN {
    # Prevent CGI::Session from autoflushing. Only flush when we say to.
    undef *CGI::Session::DESTROY;
    $HAS_NFSLOCK = eval {require File::NFSLock;1           };
    $HAS_MYSQL   = eval {require DBI; require DBD::mysql; 1};
}

use constant DEBUG => 0;
use constant DEBUG_LOCK => DEBUG || 0;

sub new {
	my $class    = shift;
	my %args     = @_;
	my ($driver,$id,$session_args,$default_source,$lockdir,$locktype,$expire_time) 
	  = @args{'driver','id','args','source','lockdir','locktype','expires'};

	$CGI::Session::NAME = 'gbrowse_sess';     # custom cookie
	$CGI::Session::Driver::file::NoFlock = 1; # flocking unnecessary because we roll our own

	unless ($id) {
	    my $cookie = CGI::Cookie->fetch();
	    $id        = $cookie->{$CGI::Session::NAME}->value 
		if $cookie && $cookie->{$CGI::Session::NAME};
	}
	my $self            = bless {
	    lockdir  => $lockdir,
	    locktype => $locktype,
	},$class;

	$self->session_argv($driver,$id,$session_args);
	$self->{session} = $self->lock_ex($id);

	warn "CGI::Session->new($driver,$id,$session_args)=>",$self->{session}->id if DEBUG;

	# never expire private (authenticated) sessions
	$expire_time = 0 if $self->private;
	$self->{session}->expire($expire_time) 
		if defined $expire_time;

	warn "[$$] session fetch for ",$self->id if DEBUG;
	$self->source($default_source) unless defined $self->source;
	$self->{pid} = $$;
	$self;
}

sub load_session {
    my $self = shift;
    $self->session_argv(@_);
#     print Dumper("session = "(\%{$self->session_argv(@_)});
    return CGI::Session->new($self->session_argv);
}

sub session_argv {
    my $self = shift;
    if (@_) {
	$self->{session_argv} = \@_;
    } else {
	return unless $self->{session_argv};
	return @{$self->{session_argv}};
    }
}

sub locktime {
    my $self = shift;
    my $d = $self->{locktime};
    $self->{locktime} = shift if @_;
    return $d; 
}

sub locktype {
    my $self = shift;
    if ($self->{locktype} eq 'default') {
	return 'nfs' if $HAS_NFSLOCK;
	return 'flock';
    }
    return 'nfs'   if $self->{locktype} eq 'nfs'        && $HAS_NFSLOCK;
    return 'mysql' if $self->{locktype} =~ /^(dbi:mysql:|mysql):/    && $HAS_MYSQL;
    return 'flock' if $self->{locktype} eq 'flock';
}

sub lock {
    my $self    = shift;
    my $type    = shift;
    my $id      = shift;
    
    # no id, so we have to create a session and get an id
    # otherwise we lock before we make the session
    unless ($id) {
	$self->{session} ||= $self->load_session();
	$id = $self->id;
    }

    return if $self->lockobj; # don't double lock
    my $locktype = $self->locktype;
    my $start_time = $self->time();

    warn "[$$] waiting on $type session lock...\n" if DEBUG_LOCK;

    eval {
	local $SIG{ALRM} = sub {die "timeout\n"};
	# timeout lock to avoid some process from keeping process open
	# you may see some lock timeouts if a process is taking too long
	# to release its session.
	alarm(LOCK_TIMEOUT); 

	if ($locktype eq 'flock') {
	    $self->lock_flock($type,$id);
	}
	elsif ($locktype eq 'nfs') {
	    $self->lock_nfs($type,$id);
	}
	elsif ($locktype eq 'mysql') {
	    $self->lock_mysql($type,$id);
	}
	else {
	    die "unknown lock type $locktype";
	}
	alarm(0);
    };
    my $elapsed = sprintf("%5.3fs",$self->time()-$start_time);
    if ($@) {
	die $@ unless $@ eq "timeout\n";
	warn ("[$$] session lock timed out on request after $elapsed\n",
	      CGI::request_method(),': ',
	      CGI::url(-path=>1),' ',
	      CGI::query_string());
    } else {
	warn "[$$] ...$type lock obtained after $elapsed" if DEBUG;
    }
    $self->locktime($self->time());
    return $self->{session} ||= $self->load_session();
}

sub lock_flock {
    my $self = shift;
    my ($type,$id) = @_;

    my $mode  = $type eq 'exclusive' ? LOCK_EX : LOCK_SH;

    my ($lockdir,$lockfile) = $self->lockfile($id);

    mkpath($lockdir) unless -e $lockdir;
    my $lockpath = File::Spec->catfile($lockdir,$lockfile);
    my $o_mode   = $mode eq 'exclusive' ? '>'
	          :-e $lockpath ? "<" 
		  : ">";

    open my $fh,$o_mode,$lockpath 
	or die "Couldn't open lockfile $lockpath: $!";
    flock ($fh,$mode);
    $self->lockobj($fh);
}

sub lock_nfs {
    my $self = shift;
    my ($type,$id) = @_;
    my ($lockdir,$lockfile) = $self->lockfile($id);
    mkpath($lockdir) unless -e $lockdir;
    my $lockpath = File::Spec->catfile($lockdir,$lockfile);
    my $lock     = File::NFSLock->new(
	{file               => $lockpath,
	 lock_type          => $type eq 'exclusive' ? LOCK_EX : LOCK_SH,
	 blocking_timeout   => LOCK_TIMEOUT,  # 2 sec
	 stale_lock_timeout => 60, # 1 min
	});
    warn  "[$$] ...timeout waiting for lock after ",sprintf("%5.3fs",LOCK_TIMEOUT)
	unless $lock;
    $self->lockobj($lock);
}

sub lock_mysql {
    my $self = shift;
    my ($type,$id) = @_;
    my $lock_name  = $self->mysql_lock_name($id);
    (my $dsn       = $self->{locktype}) =~ s/^mysql://;
    my $dbh        = $self->{mysql} ||= DBI->connect($dsn)
                     or die "Session has no dbh handle!";
    my $result     = $dbh->selectrow_arrayref("SELECT GET_LOCK('$lock_name',10)");
    warn "Could not get my lock on $id" unless $result->[0];
    $self->lockobj($dbh);
}

sub lock_sh {
    shift->lock('shared',@_);
}
sub lock_ex {
    shift->lock('exclusive',@_);
}

sub unlock {
    my $self     = shift;
    my $lock = $self->lockobj or return;
    warn "[$$] session unlock" if DEBUG_LOCK;
    if ($lock->isa('DBI::db')) {
	my $lock_name = $self->mysql_lock_name($self->id);
	$lock->do("SELECT RELEASE_LOCK('$lock_name')");
    } else {
	$self->lockobj(undef);
	unlink File::Spec->catfile($self->lockfile($self->id))
	    if $self->locktype eq 'flock';
    }
    $self->lockobj(undef);
    warn "[$$] lock released after ",sprintf("%2.1f",$self->time() - $self->locktime)," s" if DEBUG;
}

sub lockfile {
    my $self   = shift;
    my $id     = shift;
    my ($a) = $id =~ /^(.{2})/;
    return (File::Spec->catfile($self->{lockdir},$a),
	    $id);
}

sub mysql_lock_name {
    my $self = shift;
    my $id   = shift;
    return "gbrowse_session_lock.$id";
}

sub delete {
    my $self = shift;
    $self->{session}->delete if $self->{session};
    $self->unlock;
}

sub flush {
  my $self = shift;
  return unless $$ == $self->{pid};
  carp "[$$] session flush" if DEBUG;
  $self->{session}->flush if $self->{session};
  $self->unlock;
  warn "[$$] SESSION FLUSH ERROR: ",$self->{session}->errstr 
      if $self->{session}->errstr;
}

sub time {
    return defined &Time::HiRes::time ? Time::HiRes::time() : time();
}

sub modified {
  my $self = shift;
  $self->{session}->_set_status(CGI::Session::STATUS_MODIFIED());
}

sub lockobj {
    my $self = shift;
    my $d    = $self->{lockobj};
    $self->{lockobj} = shift if @_;
    return $d;
}

sub id {
    shift->{session}->id;
}

sub session { shift->{session} }

sub page_settings {
  my $self        = shift;
  my $hash        = $self->config_hash;
  $hash->{page_settings}         ||= {};
  $hash->{page_settings}{userid} ||= $self->id;     # store the id in our state
  return $hash->{page_settings};
}

sub plugin_settings {
  my $self = shift;
  my $plugin_base = shift;
  my $hash = $self->config_hash;
  return $hash->{plugins}{$plugin_base} ||= {};
}

sub source {
  my $self = shift;
  my $source = $self->{session}->param('.source');
  $self->{session}->param('.source' => shift()) if @_;
  return $source;
}

sub uploadsid {
  my $self = shift;
  $self->{session}->param('.uploadsid' => shift() ) if @_;
  my $id = $self->{session}->param('.uploadsid');
  unless ($id) {
      # uploadsid used to be stored in the settings, which was wrong
      $id = $self->page_settings->{uploadid} ||
	  Bio::Graphics::Browser2::Util->generate_id;
      $self->{session}->param('.uploadsid' => $id);
  }
  return $id;
}

sub private {
    my $self = shift;
    my $private = $self->{session}->param('.private');
    $self->{session}->param('.private' => shift()) if @_;
    return $private;
}

sub remember_auth {
    my $self = shift;
    my $ra = $self->{session}->param('.remember_auth');
    $self->{session}->param('.remember_auth' => shift()) if @_;
    return $ra;
}

sub username {
    my $self = shift;
    my $user = $self->{session}->param('.username');
    $self->{session}->param('.username' => shift()) if @_;
    return $user;
}

sub using_openid {
    my $self = shift;
    my $using = $self->{session}->param('.using_openid');
    $self->{session}->param('.using_openid' => shift()) if @_;
    return $using;
}

sub set_nonce {
    my $self = shift;
    my ($nonce,$salt,$remember) = @_;
    warn "id=",$self->id," writing nonce = ",md5_hex($nonce,$salt) if DEBUG;
    $self->{session}->param('.nonce' => md5_hex($nonce,$salt));

    # handle session expiration
    if ($remember) {
        $self->{session}->expire('.nonce' => '30d'); # remembers authorization for 30 days
	$self->remember_auth(1);
    } else {
        $self->{session}->expire('.nonce' => '1d');  # force reauthorization every day
	$self->remember_auth(0);
    }
    $self->private(1);
}

sub match_nonce {
    my $self  = shift;
    my ($new_nonce,$salt) = @_;
    $self->private || return;
    my $nonce = $self->{session}->param('.nonce');
    warn "id=",$self->id," matching $nonce against ",$new_nonce,"|",$salt if DEBUG;
    warn "$nonce eq ",md5_hex($new_nonce, $salt)                          if DEBUG;
    return $nonce eq md5_hex($new_nonce, $salt);
}

sub config_hash {
  my $self = shift;
  my $source  = $self->source;
  my $session = $self->{session};

  $session->param($source=>{}) unless $session->param($source);
  return $session->param($source);
}

# problem with explicit DESTROY is that it gets called in all child
# processes. Better to have the unlock happen when filehandle is truly
# destroyed.
#sub DESTROY {
#    my $self = shift;
#    $self->flush;
#    $self->unlock;
#}

1;
