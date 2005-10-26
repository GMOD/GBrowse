package Bio::Graphics::Browser::PageSettings;
use strict;

use CGI::Session;

sub new {
  my $class    = shift;
  my $config   = shift;
  my $dir      = $config->tmpdir('sessions');
  my $session  = CGI::Session->new('driver:file',undef,{Directory=>$dir});

  my $self = bless {
		    session => $session,
		   },$class;
  $self;
}

sub flush {
  shift->{session}->flush;
}

sub id {
  shift->{session}->id;
}

sub page_settings {
  my $self   = shift;
  my $hash = $self->config_hash;
  return $hash->{page_settings} ||= {};
}

sub plugin_settings {
  my $self = shift;
  my $plugin_name = shift;
  my $hash = $self->config_hash;
  return $hash->{plugins}{$plugin_name} ||= {};
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

1;
