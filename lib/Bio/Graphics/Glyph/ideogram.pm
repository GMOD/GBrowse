package Bio::Graphics::Glyph::ideogram;

# $Id: ideogram.pm,v 1.11 2006-02-21 05:21:50 sheldon_mckay Exp $
# Glyph to draw chromosome ideograms

use strict qw/vars refs/;
use vars '@ISA';
use Bio::Graphics::Glyph;
use Bio::Graphics::Glyph::heat_map;
use GD;

@ISA = qw/Bio::Graphics::Glyph Bio::Graphics::Glyph::heat_map/;

sub draw {
  my $self = shift;

  my @parts = $self->parts;
  @parts = $self if !@parts && $self->level == 0;
  return $self->SUPER::draw(@_) unless @parts;

  # Draw the sides for the whole chromosome (in case
  # there are missing data).
  $self->draw_component(@_) unless @parts == 1;

  # Make unaggregated bands invisible if requested.
  # This is for making image maps for individual
  # bands of whole aggregate chromosomes.
  $self->{invisible} ||= $self->option('invisible') 
      unless @parts > 1;

  for my $part (@parts) {
    $part->{single}++ if @parts == 1;
    my $tile = $part->create_tile('left');
    $part->draw_component(@_);
  }
}

sub draw_component {
  my $self = shift;
  my $gd   = shift;
  my $feat = $self->feature;

  my $arcradius = $self->option('arcradius') || 7;
  my ( $x1, $y1, $x2, $y2 ) = $self->bounds(@_);
  # force odd width so telomere arcs are centered
  $y2 ++ if ($y2 - $y1) % 2;
  
  my $stain = $feat->attributes('stain');

  # Some genome sequences don't contain substantial telomere sequence (i.e. Arabidopsis)
  # We can suggest their presence at the tips of the chromosomes by setting fake_telomeres = 1
  # in the configuration file, resulting in the tips of the chromosome being painted black.
  my $fake_telomeres = $self->option('fake_telomeres') || 0;

  my ($bgcolor_index) = $self->option('bgcolor') =~ /$stain:(\S+)/;
  $bgcolor_index ||= 'white';
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
  if ( $feat->method ne 'centromere' ) {
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
  $self->filled_box($gd, $x1, $y1, $x2, $y2, $bgcolor, $bgcolor);
  
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
  $gd->line( $x2 - 1, $y1 + 1, $x2 - 1, $y2 - 1, $fgcolor );
  $gd->polygon( $poly, $fgcolor );          # outline
}

sub draw_telomere {
  my $self = shift;
  my ($gd, $x1, $y1, $x2, $y2,
      $bgcolor, $fgcolor, $arcradius, $state ) = @_;
  
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
  $gd->line( $x2-1, $y1, $x2-1, $y2, $fgcolor );
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

This glyph draws a section of a chromosome ideogram. It relies
on certain data from the feature to determine which color should
be used (stain) and whether the segment is a telomere or 
centromere or a regular cytoband. The centromeres and 'var'-marked
bands get the usual diagonal black-on-white pattern which is 
hardwired in the glyph, the colors of others is configurable.
For GD::SVG images, a solid color is substituted for the diagonal
black-on-white pattern.

The cytobandband features would typically be formatted like this in GFF3:

 ...
 ChrX    UCSC    cytoband        136700001       139000000       .       .       .       Parent=ChrX;Name=Xq27.1;Alias=ChrXq27.1;stain=gpos75;
 ChrX    UCSC    cytoband        139000001       140700000       .       .       .       Parent=ChrX;Name=Xq27.2;Alias=ChrXq27.2;stain=gneg;
 ChrX    UCSC    cytoband        140700001       145800000       .       .       .       Parent=ChrX;Name=Xq27.3;Alias=ChrXq27.3;stain=gpos100;
 ChrX    UCSC    cytoband        145800001       153692391       .       .       .       Parent=ChrX;Name=Xq28;Alias=ChrXq28;stain=gneg;
 ChrY    UCSC    cytoband        1       1300000 .       .       .       Parent=ChrY;Name=Yp11.32;Alias=ChrYp11.32;stain=gneg;

 which in this case is a GFF-ized cytoband coordinate file from UCSC:

 http://hgdownload.cse.ucsc.edu/goldenPath/hg16/database/cytoBand.txt.gz

 and the corresponding GBrowse config options would be like this to 
 create an ideogram overview track for the whole chromosome:

 The 'chromosome' feature below would aggregated from bands and centromere using the default 
 chromosome aggregator

 [CYT:overview]
 feature       = chromosome
 glyph         = ideogram
 fgcolor       = black
 bgcolor       = gneg:white gpos25:silver gpos50:gray gpos:gray  gpos75:darkgray gpos100:black acen:cen gvar:var
 arcradius     = 6
 height        = 25
 bump          = 0
 label         = 0

 A script to reformat UCSC annotations to  GFF3 format can be found at
 the end of this documentation.

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

=head1 UCSC TO GFF CONVERSION SCRIPT

The following short script can be used to convert a UCSC cytoband annotation file
into GFF format.  If you have the lynx web-browser installed you can
call it like this in order to download and convert the data in a
single operation:

  fetchideogram.pl http://hgdownload.cse.ucsc.edu/goldenPath/hg16/database/cytoBand.txt.gz

Otherwise you will need to download the file first. Note the difference between this script
and input data from previous versions of ideogram.pm: UCSC annotations are used in place
of NCBI annotations.


#!/usr/bin/perl

use strict;
my %stains;
my %centros;
my %chrom_ends;


foreach (@ARGV) {
    if (/^(ftp|http|https):/) {
	$_ = "lynx --dump $_ |gunzip -c|";
    } elsif (/\.gz$/) {
	$_ = "gunzip -c $_ |";
    }
    print STDERR "Processing $_\n";
}

print "##gff-version 3\n";
while(<>)
{
    chomp;
    my($chr,$start,$stop,$band,$stain) = split /\t/;
    $start++;
    $chr = ucfirst($chr);
    if(!(exists($chrom_ends{$chr})) || $chrom_ends{$chr} < $stop)
    {
	$chrom_ends{$chr} = $stop;
    }
    my ($arm) = $band =~ /(p|q)\d+/;
    $stains{$stain} = 1;
    if ($stain eq 'acen')
    {
	$centros{$chr}->{$arm}->{start} = $stop;
	$centros{$chr}->{$arm}->{stop} = $start;
	next;
    }
    $chr =~ s/chr//i;
    print qq/$chr\tUCSC\tcytoband\t$start\t$stop\t.\t.\t.\tParent=$chr_stripped;Name=$chr;Alias=$chr$band;stain=$stain;\n/;
}

foreach my $chr(sort keys %chrom_ends)
{
    print qq/$chr\tUCSC\tcentromere\t$centros{$chr}->{p}->{stop}\t$centros{$chr}->{q}->{start}\t.\t+\t.\tParent=$chr;Name=$chr\_cent\n/;
}



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

Gudmundur A. Thorisson E<lt>mummi@cshl.eduE<gt>

Copyright (c) 2001-2006 Cold Spring Harbor Laboratory

=head1 CONTRIBUTORS

Sheldon McKay E<lt>mckays@cshl.edu<gt>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut







