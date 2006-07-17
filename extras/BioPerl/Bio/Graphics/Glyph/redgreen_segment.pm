package Bio::Graphics::Glyph::redgreen_segment;
#$Id: redgreen_segment.pm,v 1.1.2.4.2.12 2006-07-17 21:05:44 scottcain Exp $

use strict;
use Bio::Graphics::Glyph::graded_segments;
use vars '@ISA';
@ISA = 'Bio::Graphics::Glyph::graded_segments';

sub calculate_color {
  my $self = shift;
  my $val  = shift;
  return (0,0,0) unless $val =~ /^[\d.]+$/;
  return HSVtoRGB(120*(1-$val),1,255);
}

sub HSVtoRGB ($$$) {
  my ($h,$s,$v)=@_;
  my ($r,$g,$b,$i,$f,$p,$q,$t);

  if( $s == 0 ) {
    ## achromatic (grey)
    return ($v,$v,$v);
  }

  $h /= 60;                       ## sector 0 to 5
  $i = int($h);
  $f = $h - $i;                   ## factorial part of h
  $p = $v * ( 1 - $s );
  $q = $v * ( 1 - $s * $f );
  $t = $v * ( 1 - $s * ( 1 - $f ) );
  
  if($i<1) {
    $r = $v;
    $g = $t;
    $b = $p;
  } elsif($i<2){
    $r = $q;
    $g = $v;
    $b = $p;
  } elsif($i<3){
    $r = $p;
    $g = $v;
    $b = $t;
  } elsif($i<4){
    $r = $p;
    $g = $q;
    $b = $v;
  } elsif($i<5){
    $r = $t;
    $g = $p;
    $b = $v;
  } else {
    $r = $v;
    $g = $p;
    $b = $q;
  }
  return ($r,$g,$b);
}

sub mMin {
        my $n=10000000000000;
        map { $n=($n>$_) ? $_ : $n } @_;
        return($n);     
}

sub mMax {
        my $n=0;
        map { $n=($n<$_) ? $_ : $n } @_;
        return($n);     
}


1;

=head1 NAME

Bio::Graphics::Glyph::redgreen_segments - The "redgreen_segments" glyph

=head1 SYNOPSIS

See L<Bio::Graphics::Panel> and L<Bio::Graphics::Glyph>.

=head1 DESCRIPTION

This glyph is similar to the graded_segments glyph except that it
generates a green-E<gt>red gradient suitable for use with microarray data.
A feature score of 0 is full green; a feature score of 1.0 is full
red; intermediate scores are shades of yellow.

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

=head1 BUGS

Please report them.

=head1 SEE ALSO

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

Lincoln Stein E<lt>lstein@cshl.orgE<gt>

Copyright (c) 2001 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut
