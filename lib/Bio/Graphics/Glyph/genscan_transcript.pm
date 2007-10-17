package Bio::Graphics::Glyph::genscan_transcript;
# $Id: genscan_transcript.pm,v 1.1.14.1 2007-10-17 01:48:22 lstein Exp $

use strict;
use Bio::Graphics::Glyph::transcript;
use vars '@ISA';
@ISA = qw( Bio::Graphics::Glyph::transcript);

#Make sure to warn draw_component in Glyph.pm that we want an arrow, not a box.
sub new
{
    my ($class, @args) = @_;
    my $self = $class->SUPER::new(@args);
    $self->factory->set_option(strand_arrow => 1);
    return $self;
}

#Do nothing - no arrows unless we did not see start or end of the gene.
#Then we have to indicate direction.
sub arrow
{
    my ($self, @args) = @_;
    if ($self->feature->has_tag("middleOfGene"))
    {
        #Never draw an arrow - the filled arrows are enough of an indication.
        #$self->SUPER::arrow(@args);
    }
	
}

sub draw_component
{
    my ($self, @args) = @_;
    my $tag = $self->feature->primary_tag();
    if ($tag eq "polyA" or $tag eq "prom")
    {
        my $gd = shift @args;
        my($x1,$y1,$x2,$y2) = $self->bounds(@args);
    
        my $fg = $self->fgcolor;
    
        # now draw a circle
        my $xmid   = (($x1+$x2)/2);  my $width  = abs($x2-$x1);
        my $ymid   = (($y1+$y2)/2);  my $height = abs($y2-$y1);
        
        if ($tag eq "polyA")
        {
            #only point ovals allowed now
            my $r = 6;
            $gd->arc($xmid,$ymid,$r,$r,0,360,$fg);
        }
        else
        {        
            my ($vx1,$vy1,$vx2,$vy2,$vx3,$vy3);
        
            #make an equilateral
            my ($p,$q) = ($self->option('height'),($x2-$x1)/2);
            $q = $p/sqrt(3); #2;
            $x1 = $xmid - $q; $x2 = $xmid + $q;
            $y1 = $ymid - $q; $y2 = $ymid + $q;
            
            if($self->feature->strand == -1){$vx1=$x2;$vy1=$y1;$vx2=$x2;$vy2=$y2;$vx3=$x2-$p;$vy3=$ymid;}
            else{$vx1=$x1;$vy1=$y1;$vx2=$x1;$vy2=$y2;$vx3=$x1+$p;$vy3=$ymid;}
        
            # now draw the triangle
            $gd->line($vx1,$vy1,$vx2,$vy2,$fg);
            $gd->line($vx2,$vy2,$vx3,$vy3,$fg);
            $gd->line($vx3,$vy3,$vx1,$vy1,$fg);
        }

        my $red = $gd->colorAllocate(255,0,0);
    
        #Shift y by 1 to avoid filling the connector line
        $gd->fillToBorder($xmid,$ymid+1,$fg,$red);
    }
    else
    {
        $self->Bio::Graphics::Glyph::draw_component(@args);
    }
}


__END__

=head1 NAME

Bio::Graphics::Glyph::genscan_transcript - The glyph showing Genscan predictions

=head1 SYNOPSIS

  See L<Bio::Graphics::Panel> and L<Bio::Graphics::Glyph>.

=head1 DESCRIPTION

A special kind of segmented transcript glyph that shows the exon predictions
produced by the Genscan program. See http://genes.mit.edu/GENSCAN.html.
Promoter and polyA sites are indicated by triangles and circles respectively.
The triangles point in the direction of the predicted gene. If promoters are absent
in a prediction, a direction arrow is drawn at one end of the glyph.

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

In addition, the alignment glyph recognizes the following
glyph-specific options:

  Option         Description                  Default
  ------         -----------                  -------

  -arrow_length  Length of the directional   8
                 arrow.

=head1 BUGS

Please report them.

=head1 SEE ALSO

L<Bio::Graphics::Browser::Plugin::Genscan>
L<Bio::Graphics::Panel>,
L<Bio::Graphics::Glyph>,
L<Bio::Graphics::Glyph::arrow>,
L<Bio::Graphics::Glyph::cds>,
L<Bio::Graphics::Glyph::crossbox>,
L<Bio::Graphics::Glyph::diamond>,
L<Bio::Graphics::Glyph::dna>,
L<Bio::Graphics::Glyph::dot>,
L<Bio::Graphics::Glyph::ellipse>,
L<Bio::Graphics::Glyph::extending_arrow>,
L<Bio::Graphics::Glyph::generic>,
L<Bio::Graphics::Glyph::graded_segments>,
L<Bio::Graphics::Glyph::heterogeneous_segments>,
L<Bio::Graphics::Glyph::line>,
L<Bio::Graphics::Glyph::pinsertion>,
L<Bio::Graphics::Glyph::primers>,
L<Bio::Graphics::Glyph::rndrect>,
L<Bio::Graphics::Glyph::segments>,
L<Bio::Graphics::Glyph::ruler_arrow>,
L<Bio::Graphics::Glyph::toomany>,
L<Bio::Graphics::Glyph::transcript>,
L<Bio::Graphics::Glyph::transcript2>,
L<Bio::Graphics::Glyph::translation>,
L<Bio::Graphics::Glyph::triangle>,
L<Bio::DB::GFF>,
L<Bio::SeqI>,
L<Bio::SeqFeatureI>,
L<Bio::Das>,
L<GD>


=head1 AUTHOR

Simon Ilyushchenko E<lt>simonf@simonf.comE<gt>

Copyright (c) 2003 Cold Spring Harbor Laboratory

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.


=cut
