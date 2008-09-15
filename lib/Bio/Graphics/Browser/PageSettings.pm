package Bio::Graphics::Browser::PageSettings;
use strict;

use Bio::Graphics::Browser::Util 'shellwords';
use CGI::Session;
use constant COOKIE_NAME => 'gbrowse_sess';

sub new {
  my $class    = shift;
  my $config   = shift;
  my $id       = shift;
  $CGI::Session::NAME = COOKIE_NAME;
  my $dir             = $config->tmpdir('sessions');
  my $driver          = $config->setting('session driver') || 'driver:file';
  my $session_args    = $config->setting('session args');
  my %args            = $session_args ? shellwords($session_args)
                                      : (Directory => $dir);

  my $session         = CGI::Session->new($driver,$id,\%args) or die "Couldn't get session";
  $session->expire($config->source,
		   $config->remember_settings_time);
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

sub session { shift->{session} }

sub page_settings {
  my $self = shift;
  my $hash = $self->config_hash;
  return $hash->{page_settings} ||= {};
}

sub plugin_settings {
  my $self        = shift;
  my $plugin_name = shift;
  my $hash        = $self->config_hash;
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
  my $source  = $self->source;
  my $session = $self->{session};
  $session->param($source=>{}) unless $session->param($source);
  return $session->param($source);
}

1;
