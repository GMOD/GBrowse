package Bio::Graphics::Glyph::ideogram;

# $Id: ideogram.pm,v 1.3 2004-02-02 09:34:11 lstein Exp $
# Glyph to draw chromosome ideograms for the overview display

use strict;
use vars '@ISA';
use Bio::Graphics::Glyph;
@ISA = 'Bio::Graphics::Glyph';


sub draw_component {
  my $self = shift;
  my $gd = shift;
  my ($left,$top) = @_;
  my($x1,$y1,$x2,$y2) = $self->bounds(@_);

  use GD;
  my $feat = $self->feature;
  my $class = $feat->class;
  my $stain = $feat->attributes('Stain');
  my $arcradius = $self->option('arcradius') || 7;

  # Some genome sequences don't contain substantial telomere sequence (i.e. Arabidopsis)
  # We can suggest their presence at the tips of the chromosomes by setting fake_telomeres = 1
  # in the configuration file, resulting in the tips of the chromosome being painted black.
  my $fake_telomeres = $self->option('fake_telomeres') || 0;

  my ($bgcolor_index)  =  $self->option('bgcolor') =~ /$stain:(\S+)/;
  $bgcolor_index ||= 'white';
  my $black = $gd->colorAllocate(0,0,0);
  my($is_teltop,$is_telbot, $telomere_tip_color);
  if($class eq 'CytoBand')
  {
      if($feat->start == 1 || $feat->start == 0)
      {
	  $is_teltop  = 1;
	  $gd->arc($x1+$arcradius,$y1+$arcradius,
		   $arcradius*2,$arcradius*2,
		   180,270,$self->fgcolor);
	  $gd->arc($x1+$arcradius,$y2-$arcradius,
		   $arcradius*2,$arcradius*2,
		   90,180,$self->fgcolor);
	  $gd->line($x1+$arcradius,$y1,$x2,$y1,$self->fgcolor);
	  $gd->line($x1+$arcradius,$y2,$x2,$y2,$self->fgcolor);
	  $gd->line($x1,$y1+$arcradius,$x1,$y2-$arcradius,$self->fgcolor);
      }
      elsif($feat->stop >= $self->panel->end-1000)
      {
	  $is_telbot = 1;
	  $gd->arc($x2-$arcradius,$y1+$arcradius,
		   $arcradius*2,$arcradius*2,
		   270,0,$self->fgcolor);
	  $gd->arc($x2-$arcradius,$y2-$arcradius,
		   $arcradius*2,$arcradius*2,
		   0,90,$self->fgcolor);
	  $gd->line($x1,$y1,$x2-$arcradius,$y1,$self->fgcolor);
	  $gd->line($x1,$y2,$x2-$arcradius,$y2,$self->fgcolor);
	  $gd->line($x2,$y1+$arcradius,$x2,$y2-$arcradius,$self->fgcolor);
      }
      else
      {
	  #Just draw a regular box
	  $gd->rectangle($x1,$y1,$x2,$y2,$self->fgcolor);
      }
      
      #Time to put in the fill color
      #Special handling for the background color
      my $bgcolor = $self->factory->translate_color($bgcolor_index);
      if($bgcolor_index eq 'var')
      {
	  my $var_tile = $self->create_tile('left');
	  $gd->setTile($var_tile);
	  $gd->fill($x1+3,$y1+(($y2-$y1)/2),gdTiled); 
      }
      else
      {
	  if($x2-$x1 > 1)
	  {
	      $gd->fill($x1+1,$y1+(($y2-$y1)/2),$bgcolor);
	  }
	  #$gd->line($x1+1,$y1+(($y2-$y1)/2),$x1+1,$y1+(($y2-$y1)/2),$black);
	  if ($fake_telomeres) 
	  {
	      warn "got fake_telomeres";
	      $telomere_tip_color = $black;
	  }
	  else 
	  {
	      $telomere_tip_color = $bgcolor;
	  }
	  
	  if ($is_teltop) {
		# Fill inside the round part of the telomere...
		$gd->fill($x1+($arcradius/2), $y1+(($y2-$y1)/2), $telomere_tip_color);
		# and paint over the line between the telomere box and the arc
		# We back off the y-coordinates +/- 1 to keep the color inside the bounding
		# line sourrounding the feature.
		$gd->line($x1+$arcradius, $y1+1, $x1+$arcradius, $y2-1, $telomere_tip_color);
	  }
	  if ($is_telbot) {
		# Fill inside the round part of the telomere..
		$gd->fill($x2-($arcradius/2), $y1+(($y2-$y1)/2), $telomere_tip_color);
		# and paint over the line between the telomere box and the arc
		# We back off the y-coordinates +/- 1 to keep the color inside the bounding
		# line sourrounding the feature.
		$gd->line($x2-$arcradius, $y1+1, $x2-$arcradius, $y2-1, $telomere_tip_color);
	  }
	  $is_teltop or $gd->line($x1,$y1+1,$x1,$y2-1,$bgcolor);
	  $is_telbot or $gd->line($x2,$y1+1,$x2,$y2-1,$bgcolor);
	  $is_teltop or $gd->line($x1,$y1+1,$x1,$y2-1,$bgcolor);
	  $is_telbot or $gd->line($x2,$y1+1,$x2,$y2-1,$bgcolor);
      }
  }
  elsif($class eq 'Centromere')
  {
      #First do the arcs
      $gd->arc(($x1+$x2)/2-$arcradius,$y1+$arcradius,
	       $arcradius*2,$arcradius*2,
	       270,0,$self->fgcolor);
      $gd->arc(($x1+$x2)/2-$arcradius,$y2-$arcradius,
	       $arcradius*2,$arcradius*2,
	       0,90,$self->fgcolor);
      $gd->line($x1,$y1,($x1+$x2)/2-$arcradius,$y1,$self->fgcolor);
      $gd->line($x1,$y2,($x1+$x2)/2-$arcradius,$y2,$self->fgcolor);
      $gd->line(($x1+$x2)/2,$y1+$arcradius,($x1+$x2)/2,$y2-$arcradius,$self->fgcolor);

      $gd->arc(($x1+$x2)/2+$arcradius,$y1+$arcradius,
	       $arcradius*2,$arcradius*2,
	       180,270,$self->fgcolor);
      $gd->arc(($x1+$x2)/2+$arcradius,$y2-$arcradius,
	       $arcradius*2,$arcradius*2,
	       90,180,$self->fgcolor);
      $gd->line(($x1+$x2)/2+$arcradius,$y1,$x2,$y1,$self->fgcolor);
      $gd->line(($x1+$x2)/2+$arcradius,$y2,$x2,$y2,$self->fgcolor);

      $gd->line(($x1+$x2)/2-1,$y1+$arcradius-1,($x1+$x2)/2-1,$y2-$arcradius+1,$self->fgcolor);
      $gd->line(($x1+$x2)/2+1,$y1+$arcradius-1,($x1+$x2)/2+1,$y2-$arcradius+1,$self->fgcolor);

      my $centrom_tile = $self->create_tile('right');
      
      $gd->setTile($centrom_tile);
      $gd->line($x1,$y1,$x1,$y2,$self->fgcolor);
      $gd->line($x2,$y1,$x2,$y2,$self->fgcolor);
      $gd->fill($x1+1,$y1+(($y2-$y1)/2),gdTiled);
      $gd->fill($x2-1,$y1+(($y2-$y1)/2),gdTiled);
  }
}

sub create_tile
{
    my $self = shift;
    my $direction = shift;

    #Prepare tile to use for filling an area
    my $tile = new GD::Image(5,5);
    $tile->fill(1,1,$tile->colorAllocate(255,255,255));
    if($direction eq 'right')
    {
	$tile->line(0,0,5,5,$tile->colorAllocate(0,0,0));
    }
    elsif($direction eq 'left')
    {
	$tile->line(5,0,0,5,$tile->colorAllocate(0,0,0));
    }
    return $tile;
}

sub bump{return 0;}

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

  The band features would typically be formatted like this in GFF:

Chr1    NCBI    cytoband        10811655        14102157        .       +       .       CytoBand 1p36.21; Stain gpos50
Chr1    NCBI    cytoband        14102158        19743020        .       +       .       CytoBand 1p36.13; Stain gneg
Chr1    NCBI    cytoband        19743021        21623308        .       +       .       CytoBand 1p36.12; Stain gpos25
Chr1    NCBI    cytoband        21623309        24913811        .       +       .       CytoBand 1p36.11; Stain gneg
Chr1    NCBI    cytoband        24913812        27029135        .       +       .       CytoBand 1p35.3; Stain gpos25
Chr1    NCBI    cytoband        120103374       123103375       .       +       .       Centromere Chr1_cent

 which in this case is a GFF-ized cytoband coordinate file from NCBI:

ftp://ftp.ncbi.nih.gov/genomes/H_sapiens/maps/mapview/BUILD.33/ISCN800_abc.gz

and the corresponding GBrowse config options would be like this to 
create a  nice ideogram overview track for the whole chromosome:

[CYT:overview]
feature       = cytoband
glyph         = ideogram
bgcolor       = gneg:white gpos25:silver gpos50:gray gpos:gray gpos75:darkgray gpos100:black acen:cen gvar:var
arcradius     = 6
height        = 25

A small script to convert NCBI format into GFF format can be found at
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

=head1 NCBI TO GFF CONVERSION SCRIPT

The following short script can be used to convert NCBI ideogram format
into GFF format.  If you have the lynx web-browser installed you can
call it like this in order to download and convert the data in a
single operation:

  fetchideogram.pl ftp://ftp.ncbi.nih.gov/genomes/H_sapiens/maps/mapview/BUILD.33/ISCN800_abc.gz

Otherwise you will need to download the file first.

 #!/usr/bin/perl

 use strict;

 foreach (@ARGV) {
   if (/^(ftp|http|https):/) {
     $_ = "lynx --dump $_ |";
   } elsif (/\.gz$/) {
     $_ = "gunzip -c $_ |";
   }
 }

 while (<>) {
   chomp;
   next unless /^[\dXY]+/;
   my ($chrom,$arm,$band,undef,undef,$start,$end,$stain) = split /\s+/;
   print join("\t",
	      "Chr$chrom",
	      'NCBI','cytoband',
	      $start,
	      $end,
	      '.',
	      '+',
	      '.',
	      "CytoBand $chrom$arm$band; Stain $stain"),"\n";
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

Gudmundur A. Thorisson<lt>mummi@cshl.orgE<gt>

Copyright (c) 2001 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut
