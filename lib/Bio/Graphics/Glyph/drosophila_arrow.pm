package Bio::Graphics::Glyph::drosophila_arrow;

use strict;
use vars '@ISA';
use Bio::Graphics::Glyph::anchored_arrow;
@ISA = qw(Bio::Graphics::Glyph::anchored_arrow);

sub label {
  my $self = shift;
  my $full = $self->SUPER::label;
  $full =~ s/^AE0*//;
  return $full;
}


1;
