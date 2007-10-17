# $Id: pairwise_plot.pm,v 1.1.8.2.2.1 2007-10-17 01:48:22 lstein Exp $

package Bio::Graphics::Glyph::pairwise_plot;

# Triangle plot for showing pairwise quantitative relationships.
# Developed for drawing LD.  Might be useful for something else.
# To work, must be passed a feature that contains multiple subfeatures.
# The parent feature must have a pair() method, which given two subfeatures
# returns an intensity value between 0 (off) and 1 (saturated)

# There needs to be an option for point features, so that the
# plot is drawn to the center of the interval between subfeatures.

use strict;
use Math::Trig;

use vars '@ISA';
use Bio::Graphics::Glyph::generic;
@ISA = 'Bio::Graphics::Glyph::generic';

sub maxdepth {
  my $self = shift;
  my $md   = $self->Bio::Graphics::Glyph::maxdepth;
  return $md if defined $md;
  return 1;
}

# return angle in radians
sub angle {
  my $self  = shift;
  my $angle = $self->{angle} ||= $self->option('angle') || 45;
  $self->{angle} = shift if @_;
  deg2rad($angle);
}

sub slope {
  my $self = shift;
  return $self->{slope} if exists $self->{slope};
  return $self->{slope} = tan($self->angle);
}

sub x2y {
  my $self = shift;
  shift() * $self->slope;
}

sub intercept {
  my $self = shift;
  my ($x1,$x2) = @_;
  my $mid = ($x1+$x2)/2;
  my $y   = $self->x2y($mid-$x1);
  return (int($mid+0.5),int($y+0.5));
}

# height calculated from width
sub layout_height {
  my $self = shift;
  return $self->{height} if exists $self->{height};
  return $self->{height} = $self->x2y($self->width)/2;
}

sub calculate_color {
  my $self = shift;
  my ($s,$rgb) = @_;
  return $self->{colors}{$s} if exists $self->{colors}{$s};
  return $self->{colors}{$s} = 
    $self->panel->translate_color(map { 255 - (255-$_) * $s} @$rgb);
}

sub draw {
  my $self = shift;
  my $gd   = shift;
  my ($left,$top,$partno,$total_parts) = @_;
  my $fgcolor = $self->fgcolor;

  my ($red,$green,$blue) = $self->panel->rgb($self->bgcolor);

  my @points = $self->get_points();
  $gd->line($self->left+$left, $top+1,
	    $self->right+$left,$top+1,
	    $fgcolor);

  my $points = $self->option('point');

  my @parts = sort {$a->left<=>$b->left} $self->parts;
  $_->draw_component($gd,$left,$top-10) foreach @parts;

  # assumption: parts are not overlapping
  my @points;
  if ($points) {
    @points = map { int (($parts[$_]->right+$parts[$_+1]->left)/2)} (0..$#parts-1);
    unshift @points,int($parts[0]->left);
    push @points,int($parts[-1]->right);
  }

  for (my $ia=0;$ia<@parts-1;$ia++) {
    for (my $ib=$ia+1;$ib<@parts;$ib++) {
      my ($l1,$r1,$l2,$r2);
      if (@points) {
	($l1,$r1) = ($points[$ia]+1,$points[$ia+1]-1);
	($l2,$r2) = ($points[$ib]+1,$points[$ib+1]-1);
      } else {
	($l1,$r1) = ($parts[$ia]->left,$parts[$ia]->right);
	($l2,$r2) = ($parts[$ib]->left,$parts[$ib]->right);
      }

      my $intensity = eval{$self->feature->pair_score($parts[$ia],$parts[$ib])};
      warn $@ if $@;
      $intensity    = 1.0 unless defined $intensity;
      my $c         = $self->calculate_color($intensity,[$red,$green,$blue]);

      # left corner
      my ($lcx,$lcy) = $self->intercept($l1,$l2);
      my ($tcx,$tcy) = $self->intercept($r1,$l2);
      my ($rcx,$rcy) = $self->intercept($r1,$r2);
      my ($bcx,$bcy) = $self->intercept($l1,$r2);
      my $poly = GD::Polygon->new();
      $poly->addPt($lcx+$left,$lcy+$top);
      $poly->addPt($tcx+$left,$tcy+$top);
      $poly->addPt($rcx+$left,$rcy+$top);
      $poly->addPt($bcx+$left,$bcy+$top);
      $gd->filledPolygon($poly,$c);
    }
  }
}

sub get_points {
  my $self = shift;
  my @points;
  my @parts = $self->parts;
  return unless @parts;

  for my $g (@parts) {
    push @points,$g->left;
    push @points,$g->right;
  }
  @points;
}

# never allow our internal parts to bump;
sub bump { 0 }

1;

__END__

=head1 NAME

Bio::Graphics::Glyph::pairwise_plot - The "pairwise plot" glyph

=head1 SYNOPSIS

 use Bio::Graphics;

 # create the panel, etc.  See Bio::Graphics::Panel
 # for the synopsis

 # Create one big feature using the PairFeature
 # glyph (see end of synopsis for an implementation)
 my $block = PairFeature->new(-start=>  2001,
 			      -end  => 10000);

 # It will contain a series of subfeatures.
 my $start = 2001;
 while ($start < 10000) {
   my $end = $start+120;
   $block->add_SeqFeature($bsg->new(-start=>$start,
				    -end  =>$end
				   ),'EXPAND');
   $start += 200;
 }

 $panel->add_track($block,
 		   -glyph => 'pairwise_plot',
		   -angle => 45,
		   -bgcolor => 'red',
		   -point => 1,
		  );

 print $panel->png;

 package PairFeature;
 use base 'Bio::SeqFeature::Generic';

 sub pair_score {
   my $self = shift;
   my ($sf1,$sf2) = @_;
   # simple distance function
   my $dist  = $sf2->end    - $sf1->start;
   my $total = $self->end   - $self->start;
   return sprintf('%2.2f',1-$dist/$total);
 }

=head1 DESCRIPTION

This glyph draws a "triangle plot" similar to the ones used to show
linkage disequilibrium between a series of genetic markers.  It is
basically a dotplot drawn at a 45 degree angle, with each
diamond-shaped region colored with an intensity proportional to an
arbitrary scoring value relating one feature to another (typically a
D' value in LD studies).

This glyph requires more preparation than other glyphs.  First, you
must create a subclass of Bio::SeqFeature::Generic (or
Bio::Graphics::Feature, if you prefer) that has a pair_score() method.
The pair_score() method will take two features and return a numeric
value between 0.0 and 1.0, where higher values mean more intense.

You should then create a feature of this new type and use
add_SeqFeature() to add to it all the genomic features that you wish
to compare.

Then add this feature to a track using the pairwise_plot glyph.  When
the glyph renders the feature, it will interrogate the pair_score()
method for each pair of subfeatures.

=head2 OPTIONS

In addition to the common options, the following glyph-specific
options are recognized:

  Option      Description                  Default
  ------      -----------                  -------

  -point      If true, the plot will be         0
              drawn relative to the
              midpoint between each adjacent
              subfeature.  This is appropriate
              for point-like subfeatures, such
              as SNPs.

  -angle      Angle to draw the plot.  Values   45
              between 1 degree and 89 degrees
              are valid.  Higher angles give
              a more vertical plot.

  -bgcolor    The color of the plot.            cyan

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
L<Bio::Graphics::Glyph::xyplot>,
L<Bio::DB::GFF>,
L<Bio::SeqI>,
L<Bio::SeqFeatureI>,
L<Bio::Das>,
L<GD>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.edu<gt>.

Copyright (c) 2004 Cold Spring Harbor Laboratory

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut
