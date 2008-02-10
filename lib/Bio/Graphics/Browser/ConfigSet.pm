package Bio::Graphics::Browser::ConfigSet;

=head1 NAME

Bio::Graphics::Browser::ConfigSet -- a base class for track config sets

=head1 SYNOPSIS

 use Bio::Graphics::Browser::ConfigSet::basic;
 my $options = Bio::Graphics::Browser::ConfigSet::basic->new();
 my @glyphs  = $basic->options('glyph');


This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut


use strict;
use Carp 'croak';


sub new {
  my $self  = shift;
  my $self = bless {}, ref $self || $self;
  $self->initialize();
  return $self;  
}


# a generic getter/setter for lists of possibe values
# for config options. The set-specific values are defined in 
# the initialize method of each ConfigSet (inheriting subclass)
sub options {
  my ($self,$option,@values) = @_;
  $option or croak("No option specified!");
  $self->{$option} = \@values if @values;
  $self->_process_colors();
  return wantarray ? @{$self->{option}} : $self->{option};
}

sub _process_colors {
  my $self = shift;
  my @colors = grep /color/, keys %$self;
  for my $c (@colors) {
    my @hexed;
    for my $color (@{$self->{$c}}) {
      s/^([0-9A-Fa-f]{6})$/\#$1/;
      push @hexed, $_;
    }
    $self->{$c} = \@hexed;
  }
  $self->{bgcolor} ||= $self->{fgcolor} if $self->{fgcolor};
  $self->{fgcolor} ||= $self->{bgcolor} if $self->{bgcolor};
}

1;
