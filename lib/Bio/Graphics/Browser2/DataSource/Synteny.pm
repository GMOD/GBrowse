package Bio::Graphics::Browser2::DataSource::Synteny;
use strict;
use warnings;
use base 'Bio::Graphics::Browser2::DataSource';

sub is_synteny { 1 }


## methods for dealing with data sources
sub data_sources {
  return sort grep {!/^\s*=~/} shift->SUPER::configured_types();
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
  my ($regex_key) = grep { $dsn =~ /^$_$/ } map { $_ =~ s/^=~//; $_ } grep { $_ =~ /^=~/ } keys(%{$self->{config}});
  if ($regex_key) {
      my $path = $self->resolve_path( $self->setting( "=~".$regex_key => 'path' ), 'config' );
      my @matches = ($dsn =~ /$regex_key/);
      for (my $i = 1; $i <= scalar(@matches); $i++) {
	  $path =~ s/\$$i/$matches[$i-1]/;
      }
      return $self->resolve_path($path, 'config');
  }
  my $path = $self->setting( $dsn => 'path' ) or return;
  $self->resolve_path( $path, 'config' );
}

1;
