package Bio::Graphics::Glyph::phased_exons;

# This was an attempt to color the exons according to their phase, but it
# doesn't really achieve the desired effect.  What we really want is to color
# the exons by the peptide they produce.

# here's the scheme:
#[Ann Loraine Genes]
#feature      = transcript:curated
#glyph        = phased_exons
#bgcolor      = wheat
#fgcolor      = black
#0color       = blue
#1color       = cyan
#2color       = orange
#height       = 10
#description  = 1
#key          = Curated genes
#citation     = These are gene predictions that have been reviewed by WormBase curators.  Only
#	the CDS sections are represented.  For 5' and 3' termini, please examine the paired
#	5' and 3' ESTs, full-length cDNAs, and Worm Transcriptome Project (WTP) gene extents.



use strict;
use Bio::Graphics::Glyph::wormbase_transcript;
use vars '@ISA';
@ISA = 'Bio::Graphics::Glyph::wormbase_transcript';

sub bgcolor {
  my $self = shift;
  my $feature = $self->feature;
  warn "feature = $feature";
  my $color   = $self->SUPER::bgcolor;
  if (defined(eval{$feature->phase})) {
    my $frame = $feature->start %3;
    my $tag = "${frame}color";
    $color  ||= $self->color($tag);
  }
  return $color;
}

1;
