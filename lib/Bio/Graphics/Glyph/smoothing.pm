package Bio::Graphics::Glyph::smoothing;

use strict;

sub get_smoothing {
  my $self = shift;
  return $self->option('smoothing') or 'mean';
}

1;
