package Bio::Graphics::Browser::Session;
use strict;
use warnings;

use CGI::Session;
use Fcntl 'LOCK_EX';
use File::Spec;
use File::Path 'mkpath';

sub new {
  my $class    = shift;
  my ($driver,$id,$args,$default_source) = @_;
  $CGI::Session::NAME = 'gbrowse_sess';
  $id               ||= CGI->cookie($CGI::Session::NAME);
  my $self            = bless {},$class;
  $self->lock($id);
  $self->{session}    = CGI::Session->new($driver,$id,$args);
  $self->source($default_source) unless defined $self->source;
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
    flock ($fh,LOCK_EX);
    $self->lockfh($fh);
}

sub unlock {
    my $self     = shift;
    close $self->lockfh;
}

sub lockfile {
    my $self   = shift;
    my $id     = shift;
    my $tmpdir = File::Spec->tmpdir;
    my ($a) = $id =~ /^(.{2})/;
    return (File::Spec->catfile($tmpdir,'gbrowse','locks',$a),
	    $id);
}

sub flush {
  my $self = shift;
  $self->{session}->flush if $self->{session};
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
  my $hash                 = $self->config_hash;
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
  my $source = $self->source;
  my $session = $self->{session};
  $session->param($source=>{}) unless $session->param($source);
  return $session->param($source);
}

sub DESTROY {
    my $self = shift;
    $self->flush;
    $self->unlock;
}

1;
