package Bio::Graphics::GBrowse_run;

use strict;
use Bio::Graphics::Browser;

sub new {
  my $class             = shift;
  my ($config,$options) = @_;
  return bless {config=>$config,
		options=>$options},$class;
}

sub config {
  my $self = shift;
  return $self->{config};
}

sub options {
  my $self = shift;
  return $self->{options};
}

sub translate {
  my $self = shift;
  my $tag  = shift;
  my @args = @_;
  return $self->config->tr($tag,@args);
}


1;
