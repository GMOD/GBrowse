package Bio::Graphics::Glyph::ideogram;

# $Id: ideogram.pm,v 1.3.6.1.2.5.2.7 2008-05-08 03:07:18 sheldon_mckay Exp $
# Glyph to draw chromosome ideograms

use strict qw/vars refs/;
use vars '@ISA';
use Bio::Graphics::Glyph;
use GD;

use Data::Dumper;

@ISA = qw/Bio::Graphics::Glyph/;

sub draw {
  my $self = shift;
  my @parts = $self->parts;
  @parts = $self if !@parts && $self->level == 0;
  return $self->SUPER::draw(@_) unless @parts;

  # Draw the whole chromosome first (in case
  # there are missing data).
  my $draw_chromosome = @parts > 1 || $parts[0]->can('level') && $parts[0]->level;
  $self->draw_component(@_) if $draw_chromosome;


  $parts[0]->{single}++ if @parts == 1;

  # if the bands are subfeatures of an aggregate chromosome,
  # we can draw the centomere and telomeres last to improve
  # the appearance
  my @last;
  for my $part (@parts) {
    my ($stain) = $part->feature->attributes('stain') || $part->feature->attributes('Stain');
    push @last, $part and next if
	$stain eq 'stalk' ||
        $part->feature->method =~ /centromere/i ||
        $part->feature->start <= 1 ||
        $part->feature->stop >= $self->panel->end - 1000;
    my $tile = $part->create_tile('left');
    $part->draw_component(@_);
  }

  for my $part (@last) {
    my $tile;
    if ($part->feature->method =~ /centromere/) {
      $tile = $self->create_tile('right');
    }
    else {
      $tile = $part->create_tile('left'); 
    }
    $part->draw_component(@_);
  }
}

sub draw_component {
  my $self = shift;
  my $gd   = shift;
  my $feat = $self->feature;
  my $arcradius = $self->option('arcradius') || 7;
  my ( $x1, $y1, $x2, $y2 ) = $self->bounds(@_);

  # The band has to be at least one pixel wide
  $x2++ if $x2 == $x1;
  
  # force odd width so telomere arcs are centered
  $y2++ if ($y2 - $y1) % 2;
  
  my ($stain) = $feat->attributes('stain') || $feat->attributes('Stain');

  # Some genome sequences don't contain substantial telomere sequence (i.e. Arabidopsis)
  # We can suggest their presence at the tips of the chromosomes by setting fake_telomeres = 1
  # in the configuration file, resulting in the tips of the chromosome being painted black.
  my $fake_telomeres = $self->option('fake_telomeres') || 0;

  my ($bgcolor_index) = $self->option('bgcolor') =~ /$stain:(\S+)/ if $stain;
  ($bgcolor_index,$stain) = qw/white none/ if !$stain;

  my $black = $gd->colorAllocate( 0, 0, 0 );
  my $cm_color = $self->{cm_color} = $gd->colorAllocate( 102, 102, 153 );
  my $bgcolor = $self->factory->translate_color($bgcolor_index);
  my $fgcolor = $self->fgcolor;

  # special color for gvar bands
  my $svg = 1 if $self->panel->image_class =~ /SVG/;
  if ( $bgcolor_index =~ /var/ && $svg ) {
    $bgcolor = $self->{cm_color};
  }
  elsif ( $bgcolor_index =~ /var/ ) {
    $bgcolor = gdTiled;
  }
  if ( $feat->method !~ /centromere/i && $stain ne 'acen') {
    # are we at the end of the chromosome?
    if ( $feat->start <= 1 && $stain ne 'tip') {
      # left telomere
      my $status = 1 unless $self->panel->flip;
      # Is this is a full-length chromosome?
      $status = -1 if $feat->stop >= $self->panel->end - 1000;

      $bgcolor = $black if $fake_telomeres && $status != -1;
      $self->draw_telomere( $gd, $x1, $y1, $x2, $y2, $bgcolor, $fgcolor,
        $arcradius, $status );
    }
    elsif ( $feat->stop >= $self->panel->end - 1000 && $stain ne 'tip') {
      # right telomere
      my $status = $self->panel->flip ? 1 : 0;
      $bgcolor = $black if $fake_telomeres;
      $self->draw_telomere( $gd, $x1, $y1, $x2, $y2, $bgcolor, $fgcolor,
        $arcradius, $status );
    }

    # or a stalk?
    elsif ( $stain eq 'stalk') {
      $self->draw_stalk( $gd, $x1, $y1, $x2, $y2, $bgcolor, $fgcolor );
    }

    # or a regular band?
    else {
      $self->draw_cytoband( $gd, $x1, $y1, $x2, $y2, $bgcolor, $fgcolor );
    }
  }

  # or a centromere?
  else {
    # patterns not yet supported in GD::SVG
    if ( $svg ) {
      $self->draw_centromere( $gd, $x1, $y1, $x2, $y2, $cm_color, $fgcolor );
    }
    else {
      my $tile = $self->create_tile('right');
      $self->draw_centromere( $gd, $x1, $y1, $x2, $y2, gdTiled, $fgcolor );
    }
  }
}

sub draw_cytoband {
  my $self = shift;
  my ( $gd, $x1, $y1, $x2, $y2, $bgcolor, $fgcolor) = @_;

  # draw the filled box
  $self->filled_box($gd, $x1, $y1, $x2, $y2, $bgcolor, $bgcolor) if defined $bgcolor;
  
  # outer border
  $gd->line($x1,$y1,$x2,$y1,$fgcolor);
  $gd->line($x1,$y2,$x2,$y2,$fgcolor);
}

sub draw_centromere {
  my $self = shift;
  my ( $gd, $x1, $y1, $x2, $y2, $bgcolor, $fgcolor ) = @_;

  # blank slate
  $self->wipe(@_);

  # draw a sort of hour-glass shape to represent the centromere
  my $poly = GD::Polygon->new;
  $poly->addPt( $x1, $y1 );
  $poly->addPt( $x1, $y2 );
  $poly->addPt( $x2, $y1 );
  $poly->addPt( $x2, $y2 );

  $gd->filledPolygon( $poly, $bgcolor );    # filled
  $gd->line( $x2, $y1 + 1, $x2, $y2 - 1, $fgcolor );
  $gd->polygon( $poly, $fgcolor );          # outline
}

sub draw_telomere {
  my $self = shift;
  #warn "telomere\n";
  my ($gd, $x1, $y1, $x2, $y2,
      $bgcolor, $fgcolor, $arcradius, $state ) = @_;
  
  $state ||= '0';

  # blank slate 
  $self->wipe(@_);

  # For single, unaggregated bands, make the terminal band
  # a bit wider to accomodate the arc
  if ($self->{single}) {
    $x1 -= 5 if $state == 1;
    $x2 += 5 if $state == 0;
  }

  # state should be one of:
  # 0 right telomere
  # 1 left telomere
  # -1 round at both ends (whole chromosome)
  my $outline++ if $state == -1;

  my $arcsize = $y2 - $y1;
  my $bwidth  = $x2 - $x1;
  my $new_x1  = $x1 + $arcradius - 1;
  my $new_x2  = $x2 - $arcradius;
  my $new_y   = $y1 + int($arcsize/2 + 0.5);
  
  my $orange = $self->panel->translate_color('lemonchiffon');
  my $bg     = $self->panel->bgcolor;

  $self->draw_cytoband( $gd, $x1, $y1, $x2, $y2, $bgcolor, $fgcolor );

  if ( $state ) {    # left telomere
    my $x = $new_x1;
    my $y = $new_y;

    # make an itinerant border with color unlikely to be used
    # as a panel bgcolor
    $gd->arc( $x, $y, $arcradius * 2,
	      $arcsize, 90, 270, $orange);
    $gd->line($x-1,$y1,$x1-3,$y1,$orange);
    $gd->line($x1-3,$y1,$x1-3,$y2,$orange);
    $gd->line($x1-3,$y2,$x-1,$y2,$orange);

    # carve away anything that does not look like a telomere
    $gd->fillToBorder($x1,$y1+1,$orange,$bg);
    $gd->fillToBorder($x1,$y2-1,$orange,$bg);

    # remove the border
    $gd->line($x-1,$y1,$x1-3,$y1,$bg);
    $gd->line($x1-3,$y1,$x1-3,$y2,$bg);
    $gd->line($x1-3,$y2,$x-1,$y2,$bg);
    $gd->arc( $x, $y, $arcradius * 2,
	      $arcsize, 90, 270, $fgcolor);    

    # remove that little blip at the vertex
    $gd->line($x1-1,$y-1,$x1-1,$y+1,$bg);
     
  }
  
  if ( $state < 1 ) {    # right telomere
    my $x = $new_x2;
    my $y = $new_y;

    $gd->arc( $x, $y, $arcradius * 2,
              $arcsize, 270, 90, $orange);
    $gd->line($x+1,$y1,$x2+3,$y1,$orange);
    $gd->line($x2+3,$y1,$x2+3,$y2,$orange);
    $gd->line($x2+3,$y2,$x+1,$y2,$orange);
    $gd->fillToBorder($x2,$y1+1,$orange,$bg);
    $gd->fillToBorder($x2,$y2-1,$orange,$bg);
    $gd->line($x+1,$y1,$x2+3,$y1,$bg);
    $gd->line($x2+3,$y1,$x2+3,$y2,$bg);
    $gd->line($x2+3,$y2,$x+1,$y2,$bg);
    $gd->arc( $x, $y, $arcradius * 2,
              $arcsize, 270, 90, $fgcolor);
    $gd->line($x2,$y-1,$x2,$y+1,$bg);
  }

  # GD::SVG hack :(
  if ( $self->panel->image_class =~ /SVG/ ) {
    $self->draw_cytoband( $gd, $new_x1 - 1, $y1 + 2, $new_x1 + 1, $y2 - 2, $bgcolor,
      $bgcolor );
  }
}

# for acrocentric stalk structure, draw a narrower cytoband
sub draw_stalk {
  my $self = shift;
  my ( $gd, $x1, $y1, $x2, $y2, $bgcolor, $fgcolor, $inset ) = @_;
  
  # blank slate
  $self->wipe(@_);

  my $height = $self->height;
  $inset ||= $height > 10 ? int( $height / 10 + 0.5 ) : 2;
  $_[2] += $inset;
  $_[4] -= $inset;
  $self->draw_cytoband(@_);

  $gd->line( $x1, $y1, $x1, $y2, $fgcolor );
  $gd->line( $x2, $y1, $x2, $y2, $fgcolor );
}

sub create_tile {
  my $self      = shift;
  my $direction = shift;

  # Prepare tile to use for filling an area
  my $tile;
  if ( $direction eq 'right' ) {
    $tile = GD::Image->new( 3, 3 );
    $tile->fill( 1, 1, $tile->colorAllocate( 255, 255, 255 ) );
    $tile->line( 0, 0, 3, 3, $tile->colorAllocate( 0, 0, 0 ) );
  }
  elsif ( $direction eq 'left' ) {
    $tile = GD::Image->new( 4, 4 );
    $tile->fill( 1, 1, $tile->colorAllocate( 255, 255, 255 ) );
    $tile->line( 4, 0, 0, 4, $tile->colorAllocate( 0, 0, 0 ) );
  }

  $self->panel->gd->setTile($tile);
  return $tile;
}

# This overrides the Glyph::parts method until I
# can figure out how the bands get mangled there
sub parts {
  my $self  = shift;
  my $f     = $self->feature;
  my $level = $self->level + 1;
  my @subf  = sort {$a->start <=> $b->start} $f->segments;
  return  $self->factory->make_glyph($level,@subf);
}

# erase anthing that might collide.  This is for
# clean telomeres, centromeres and stalks
sub wipe {
  my $self = shift;
  my $whitewash = $self->panel->bgcolor;
  $self->filled_box(@_[0..4],$whitewash,$whitewash);
}

# Disable bumping entirely, since it messes up the ideogram
sub bump { return 0; }

sub label { return 1; }

1;

__END__

=head1 NAME

Bio::Graphics::Glyph::ideogram - The "ideogram" glyph

=head1 SYNOPSIS

  See L<Bio::Graphics::Panel> and L<Bio::Graphics::Glyph>.

=head1 DESCRIPTION

This glyph draws a chromosome ideogram. It relies on certain data from 
the feature to determine which color should be used (stain) and whether 
the segment is a telomere, centromere or a regular cytoband.
The centromeres and 'var'-marked bands get a diagonal black-on-white pattern 
that is hardwired in the glyph, the colors of other bands  is configurable
(see options below). 

=head2 Cytoband data

The cytobandband features would typically be formatted like the example below.

  ##gff-version 3
  ##sequence-region 21 1 46944323
  21      ensembl chromosome      1       46944323        .       .       .       ID=21
  21      ensembl chromosome_band 1       2900000 .       .       .       Parent=21;Name=p13;Alias=p13;stain=gvar
  21      ensembl chromosome_band 2900001 6300000 .       .       .       Parent=21;Name=p12;Alias=p12;stain=stalk
  21      ensembl chromosome_band 6300001 10000000        .       .       .       Parent=21;Name=p11.2;Alias=p11.2;stain=gvar
  21      ensembl centromere      10000001        13200000        .       .       .       Parent=21;Name=21_cent;Alias=21_cent
  21      ensembl chromosome_band 13200001        15300000        .       .       .       Parent=21;Name=q11.2;Alias=q11.2;stain=gneg
  21      ensembl chromosome_band 15300001        22900000        .       .       .       Parent=21;Name=q21.1;Alias=q21.1;stain=gpos100
  21      ensembl chromosome_band 22900001        25800000        .       .       .       Parent=21;Name=q21.2;Alias=q21.2;stain=gneg
  21      ensembl chromosome_band 25800001        30500000        .       .       .       Parent=21;Name=q21.3;Alias=q21.3;stain=gpos75
  21      ensembl chromosome_band 30500001        34700000        .       .       .       Parent=21;Name=q22.11;Alias=q22.11;stain=gneg
  21      ensembl chromosome_band 34700001        36700000        .       .       .       Parent=21;Name=q22.12;Alias=q22.12;stain=gpos50
  21      ensembl chromosome_band 36700001        38600000        .       .       .       Parent=21;Name=q22.13;Alias=q22.13;stain=gneg
  21      ensembl chromosome_band 38600001        41400000        .       .       .       Parent=21;Name=q22.2;Alias=q22.2;stain=gpos50
  21      ensembl chromosome_band 41400001        46944323        .       .       .       Parent=21;Name=q22.3;Alias=q22.3;stain=gneg

=head2 How to obtain cytoband data

 See the GMOD wiki (below) for an example of a perl script to retrieve cytoband data from ensembl

 L<http://www.gmod.org/wiki/index.php/GBrowse_karyotype_ideogram.pl>

=head1 OPTIONS
  
=head2 Global glyph options:
  
See L<Bio::Graphics::Glyph::generic>
  
=head2 Glyph-specific options:

The ideogram glyph recognizes the following
glyph-specific options:
  
  Option            Description                      Default
  ------            -----------                      -------
 -arcradius         roundness of the centromere;      7
                    varies with the chromosome
                    width. 

 -fake_telomeres    whether to render fake telo-      false
                    meres, which are painted black
                    Otherwise, the left and right-
                    most bands are rounded.

 -bgcolor           A series of key:value pairs to    none
                    specify band colors by stain
                    (see below).

=head3 bgcolor
 
  bgcolor = gneg:white gpos25:gray gpos75:darkgray gpos100:black gvar:var stalk:#666666

=head4 stains

The keywords gneg, gpos, gvar, etc  are specified in the stain attribute of each
of the GFF features (see the sample GFF above).  There is no limitation imposed on the
keys; you may use whatever stain name that occurs in the data file. However, the
keywords I<stalk>, I<tip> and I<gvar> are reserved. 

=head4 stalk

The stain stalk will create a narrower band to represent the stalk that joins the 
satellite region to the centromere in the p-arm of human acrocentric chromosomes.

=head4 tip

The stain tip will create a terminal band that simulates extremely acrocentric 
rodent chromosomes.

=head4 gvar

The stain gvar will cause the band to be filled with a diagonal black-on-white
pattern.  If the image is generated with GD::SVG, a solid color is used instead.

=head1 AUTHORS

Sheldon McKay  E<lt>mckays@cshl.eduE<gt>,
Gudmundur A. Thorisson E<lt>mummi@cshl.eduE<gt> 

  
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.
    
=cut
