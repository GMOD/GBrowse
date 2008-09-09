package Bio::Graphics::Browser::Session;
use strict;
use warnings;

use CGI::Session;

sub new {
  my $class    = shift;
  my ($driver,$id,$args,$default_source) = @_;
  $CGI::Session::NAME = 'gbrowse_sess';
  my $session         = CGI::Session->new($driver,$id,$args);
  my $self = bless {
		    session => $session,
		   },$class;
  $self->source($default_source) unless defined $self->source;
  $self;
}

sub flush {
  my $self = shift;
  $self->{session}->flush if $self->{session};
}

sub modified {
  my $self = shift;
  $self->{session}->_set_status(CGI::Session::STATUS_MODIFIED());
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
  shift->flush;
}

1;
