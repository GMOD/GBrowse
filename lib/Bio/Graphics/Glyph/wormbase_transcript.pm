package Bio::Graphics::Glyph::wormbase_transcript;

use strict;
use Bio::Graphics::Glyph::transcript2;
use vars '@ISA','$VERSION';
@ISA = 'Bio::Graphics::Glyph::transcript2';
$VERSION = '1.03';

use constant DEFAULT_UTR_COLOR => '#D0D0D0';

sub pad_top {
  my $self = shift;
  my $top  = $self->option('pad_top');
  return defined $top ? $top : $self->SUPER::pad_top;
}

sub bgcolor {
  my $self = shift;
  my $feature = $self->feature;
  if ($feature->can('primary_tag') && $feature->primary_tag =~ /UTR/) {
    return $self->color('utr_color') if $self->option('utr_color');
    return $self->color(DEFAULT_UTR_COLOR);
  }
  if ($feature->strand >= 0) {
    return $self->color('forwardcolor');
  } else {
    return $self->color('reversecolor');
  }
}

sub draw_component {
  my $self = shift;
  my $feature = $self->feature;
  return if $feature->can('primary_tag') && $feature->primary_tag eq 'exon';
  $self->SUPER::draw_component(@_);
}

sub get_description {
  my $self    = shift;
  my $feature = shift;

  # fetch modularity-breaking acedb sequence object information
  # for backward compatibility with wormbase requirements
  if ($feature->isa('Ace::Sequence::Transcript')) {
    return eval {
      my $t       = $feature->info;
      my $id      = $t->Brief_identification;
      my $comment = $t->Locus;
      $comment   .= $comment ? " ($id)" : $id if $id;
      $comment;
    };
  } else {
    return join '; ',eval { $feature->notes };
  }
}

# Override _subseq() so that segments() is called before merged_segments()
# rather than other way around.
sub _subseq {
  my $class   = shift;
  my $feature = shift;
  if ($feature->can('segments')) {
    my @segs = sort {$a->start<=>$b->start} $feature->segments;
    return @segs if @segs;
  }
  return $class->SUPER::_subseq($feature);
}

1;

__END__

=head1 NAME

Bio::Graphics::Glyph::wormbase_transcript - The "wormbase_transcript" glyph

=head1 SYNOPSIS

  See L<Bio::Graphics::Panel> and L<Bio::Graphics::Glyph>.

=head1 DESCRIPTION

This glyph is used for drawing transcripts.  It is like "transcript2"
except that if the underlying feature is an Ace::Sequence object, the
description is derived from some wormbase-specific fields, including
info(), brief_identification() and locus().  Otherwise, the
description is obtained from the notes() field.

In addition, this glyph can show different bgcolors depending on the
direction of transcription, and will display 5'UTR and 3'UTR
components in a light shade of gray.

=head2 OPTIONS

The following options are standard among all Glyphs.  See
L<Bio::Graphics::Glyph> for a full explanation.

  Option      Description                      Default
  ------      -----------                      -------

  -fgcolor      Foreground color	       black

  -outlinecolor	Synonym for -fgcolor

  -bgcolor      Background color               turquoise

  -fillcolor    Synonym for -bgcolor

  -linewidth    Line width                     1

  -height       Height of glyph		       10

  -font         Glyph font		       gdSmallFont

  -connector    Connector type                 0 (false)

  -connector_color
                Connector color                black

  -label        Whether to draw a label	       0 (false)

  -description  Whether to draw a description  0 (false)

  -strand_arrow Whether to indicate            0 (false)
                 strandedness

In addition, the alignment glyph recognizes the following
glyph-specific options:

  Option         Description                  Default
  ------         -----------                  -------

  -forwardcolor  Bgcolor for forward          Same as -bgcolor.
                    transcripts

  -reversecolor  Bgcolor for reverse          Same as -bgcolor.
                    transcripts

  -utr_color    Color for 5'UTR and 3'UTR      gray
                 features

=head1 BUGS

Please report them.

=head1 SEE ALSO

L<Bio::Graphics::Panel>,
L<Bio::Graphics::Track>,
L<Bio::Graphics::Glyph::transcript2>,
L<Bio::Graphics::Glyph::anchored_arrow>,
L<Bio::Graphics::Glyph::arrow>,
L<Bio::Graphics::Glyph::box>,
L<Bio::Graphics::Glyph::primers>,
L<Bio::Graphics::Glyph::segments>,
L<Bio::Graphics::Glyph::toomany>,
L<Bio::Graphics::Glyph::transcript>,

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>

Copyright (c) 2001 Cold Spring Harbor Laboratory

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut
