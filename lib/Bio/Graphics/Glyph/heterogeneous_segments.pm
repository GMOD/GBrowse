package Bio::Graphics::Glyph::heterogeneous_segments;

# this glyph acts like graded_segments but the bgcolor of each segment is
# controlled by the source field of the feature. Use the source field name
# to set the background color:
# -waba_strong => 'blue'
# -waba_weak   => 'red'
# -waba_coding => 'green' 

use strict;
use Bio::Graphics::Glyph::graded_segments;
use vars '@ISA';
@ISA = 'Bio::Graphics::Glyph::graded_segments';

# override draw method to calculate the min and max values for the components
sub draw {
  my $self = shift;

  # bail out if this isn't the right kind of feature
  # handle both das-style and Bio::SeqFeatureI style,
  # which use different names for subparts.
  my @parts = $self->parts;
  return $self->SUPER::draw(@_) unless @parts;

  # figure out the colors
  $self->{source2color} ||= {};
  my $fill = $self->bgcolor;
  for my $part (@parts) {
    my $s = eval { $part->feature->source_tag } or next;
    $self->{source2color}{$s} ||= $self->color(lc($s)."_color") || $fill;
    $part->{partcolor} = $self->{source2color}{$s};
  }
  
  $self->Bio::Graphics::Glyph::generic::draw(@_);
}


# synthesize a key glyph
sub keyglyph {
  my $self = shift;
  
  my $scale = 1/$self->scale;  # base pairs/pixel

  # two segments, at pixels 0->50, 60->80
  my $offset = $self->panel->offset;

  my $feature =
    Bio::Graphics::Feature->new(
				-segments=>[ [ 0*$scale +$offset,25*$scale+$offset],
					     [ 25*$scale +$offset,50*$scale+$offset],
					     [ 50*$scale+$offset, 75*$scale+$offset]
					   ],
				-name => $self->option('key'),
				-strand => '+1');
  my @sources = grep {/_color$/} $self->factory->options;
  foreach (@sources) {s/_color$//}
  ($feature->segments)[0]->source_tag($sources[1]);
  ($feature->segments)[1]->source_tag($sources[0]);
  ($feature->segments)[2]->source_tag($sources[2]);
  my $factory = $self->factory->clone;
  $factory->set_option(label => 1);
  $factory->set_option(bump  => 0);
  $factory->set_option(connector  => 'solid');
  my $glyph = $factory->make_glyph(0,$feature);
  return $glyph;
}

# component draws a shaded box
sub draw_component {
  my $self = shift;
  my $gd = shift;
  my ($left,$top) = @_;
  my $color = $self->{partcolor};
  my @rect = $self->bounds(@_);
  $self->filled_box($gd,@rect,$color,$color);
}

1;
