package Bio::Graphics::Browser::Session;

# $Id: Session.pm,v 1.12 2009-03-10 13:57:24 lstein Exp $

use strict;
use warnings;

use CGI::Session;
use Fcntl 'LOCK_EX';
use File::Spec;
use File::Path 'mkpath';

use constant DEBUG => 0;

sub new {
  my $class    = shift;
  my %args     = @_;
  my ($driver,$id,$session_args,$default_source,$lockdir) 
      = @args{'driver','id','args','source','lockdir'};

  $CGI::Session::NAME = 'gbrowse_sess';
  $id               ||= CGI->cookie($CGI::Session::NAME);
  my $self            = bless {lockdir=>$lockdir},$class;

  $self->lock($id) if $id;
  $self->{session}    = CGI::Session->new($driver,$id,$session_args);
  $self->lock($self->{session}->id) unless $id;  # if we have a newly-created ID, then lock now
  warn "[$$] session fetch for ",$self->id if DEBUG;
  $self->source($default_source) unless defined $self->source;
  $self->{pid} = $$;
  $self;
}

sub lock {
    my $self     = shift;
    my $id       = shift;
    my ($lockdir,$lockfile)
	= $self->lockfile($id);
    mkpath($lockdir) unless -e $lockdir;
    my $lockpath = File::Spec->catfile($lockdir,$lockfile);
    my $mode     = -e $lockpath ? "<" : ">";

    open my $fh,$mode,$lockpath 
	or die "Couldn't open lockfile $lockpath: $!";
    warn "[$$] waiting on session lock..." if DEBUG;
    flock ($fh,LOCK_EX);
    warn "[$$] ...got session lock" if DEBUG;
    $self->lockfh($fh);
}

sub unlock {
    my $self     = shift;
    warn "[$$] session unlock" if DEBUG;
    return unless $self->lockfh;
    close $self->lockfh;
    $self->lockfh(undef);
}

sub lockfile {
    my $self   = shift;
    my $id     = shift;
    my ($a) = $id =~ /^(.{2})/;
    return (File::Spec->catfile($self->{lockdir},$a),
	    $id);
}

sub flush {
  my $self = shift;
  return unless $$ == $self->{pid};
  warn "[$$] session flush for ",$self->id if DEBUG;
  $self->{session}->flush if $self->{session};
  warn "[$$] SESSION FLUSH ERROR: ",$self->{session}->errstr 
      if $self->{session}->errstr;
}

sub modified {
  my $self = shift;
  $self->{session}->_set_status(CGI::Session::STATUS_MODIFIED());
}

sub lockfh {
    my $self = shift;
    my $d    = $self->{lockfh};
    $self->{lockfh} = shift if @_;
    return $d;
}

sub id {
  shift->{session}->id;
}

sub session { shift->{session} }

sub page_settings {
  my $self        = shift;
  my $hash        = $self->config_hash;
  $hash->{page_settings} ||= {};
  $hash->{page_settings}{userid} = $self->id;     # store the id in our state
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
  if (@_) {
    $self->{session}->param('.source' => shift());
  }
  return $source;
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
