package Bio::Graphics::Glyph::ideogram;

# $Id: ideogram.pm,v 1.4 2005-05-10 23:53:40 mummi Exp $
# Glyph to draw chromosome ideograms for the overview display

use strict;
use vars '@ISA';
use Bio::Graphics::Glyph;
use Data::Dumper;
@ISA = 'Bio::Graphics::Glyph';


sub draw_component {
  my $self = shift;
  my $gd = shift;
  my ($left,$top) = @_;

  use GD;
  my $arcradius = $self->option('arcradius') || 7;
  my $feat = $self->feature;
  my $fake_telomeres = $self->option('fake_telomeres') || 0;
  warn "Drawing '$feat', name=",$feat->name,", method='",$feat->method,"' from ",$feat->start," to ", $feat->stop;
  #warn Dumper($feat);

  my($x1,$y1,$x2,$y2) = $self->bounds(@_);
  
  my $stain = $feat->attributes('stain');
  
  # Some genome sequences don't contain substantial telomere sequence (i.e. Arabidopsis)
      # We can suggest their presence at the tips of the chromosomes by setting fake_telomeres = 1
      # in the configuration file, resulting in the tips of the chromosome being painted black.
      
      my ($bgcolor_index)  =  $self->option('bgcolor') =~ /$stain:(\S+)/;
      $bgcolor_index ||= 'white';
      my $black = $gd->colorAllocate(0,0,0);
      my($is_teltop,$is_telbot, $telomere_tip_color);

      #Different handling for regular bands and the centromere
      if($feat->method eq 'cytoband')
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
      elsif($feat->method eq 'centromere')
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

#Disable bumping entirely, since it messes up the nice ideogram 
sub bump{my $self = shift; warn "in ideogram bump() (self=$self)"; return 0;}

sub label{return 1;}

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

  The band features would typically be formatted like this in GFF3:

...
ChrX    UCSC    cytoband        136700001       139000000       .       .       .       ID=Xq27.1;Name=Xq27.1;Alias=ChrXq27.1;stain=gpos75;
ChrX    UCSC    cytoband        139000001       140700000       .       .       .       ID=Xq27.2;Name=Xq27.2;Alias=ChrXq27.2;stain=gneg;
ChrX    UCSC    cytoband        140700001       145800000       .       .       .       ID=Xq27.3;Name=Xq27.3;Alias=ChrXq27.3;stain=gpos100;
ChrX    UCSC    cytoband        145800001       153692391       .       .       .       ID=Xq28;Name=Xq28;Alias=ChrXq28;stain=gneg;
ChrY    UCSC    cytoband        1       1300000 .       .       .       ID=Yp11.32;Name=Yp11.32;Alias=ChrYp11.32;stain=gneg;
ChrY    UCSC    cytoband        1300001 2600000 .       .       .       ID=Yp11.31;Name=Yp11.31;Alias=ChrYp11.31;stain=gpos50;
ChrY    UCSC    cytoband        2600001 9700000 .       .       .       ID=Yp11.2;Name=Yp11.2;Alias=ChrYp11.2;stain=gneg;
ChrY    UCSC    cytoband        12800001        14800000        .       .       .       ID=Yq11.21;Name=Yq11.21;Alias=ChrYq11.21;stain=gneg;
ChrY    UCSC    cytoband        14800001        19300000        .       .       .       ID=Yq11.221;Name=Yq11.221;Alias=ChrYq11.221;stain=gpos50;
ChrY    UCSC    cytoband        19300001        21800000        .       .       .       ID=Yq11.222;Name=Yq11.222;Alias=ChrYq11.222;stain=gneg;
ChrY    UCSC    cytoband        21800001        25800000        .       .       .       ID=Yq11.223;Name=Yq11.223;Alias=ChrYq11.223;stain=gpos50;
ChrY    UCSC    cytoband        25800001        27700000        .       .       .       ID=Yq11.23;Name=Yq11.23;Alias=ChrYq11.23;stain=gneg;
ChrY    UCSC    cytoband        27700001        50286555        .       .       .       ID=Yq12;Name=Yq12;Alias=ChrYq12;stain=gvar;
Chr1    UCSC    centromere      120000001       126900000       .       +       .       ID=Chr1_cent
Chr10   UCSC    centromere      38300001        41800000        .       +       .       ID=Chr10_cent
Chr11   UCSC    centromere      51600001        56700000        .       +       .       ID=Chr11_cent
Chr12   UCSC    centromere      33200001        36500000        .       +       .       ID=Chr12_cent

 which in this case is a GFF-ized cytoband coordinate file from UCSC:

http://hgdownload.cse.ucsc.edu/goldenPath/hg16/database/cytoBand.txt.gz

and the corresponding GBrowse config options would be like this to 
create a  nice ideogram overview track for the whole chromosome:

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
    my $chr_stripped = $chr;
    $chr_stripped =~ s/chr//i;
    print qq/$chr\tUCSC\tcytoband\t$start\t$stop\t.\t.\t.\tID=$chr_stripped$band;Name=$chr_stripped$band;Alias=$chr$band;stain=$stain;\n/;
}

foreach my $chr(sort keys %chrom_ends)
{

    print qq/$chr\tUCSC\tcentromere\t$centros{$chr}->{p}->{stop}\t$centros{$chr}->{q}->{start}\t.\t+\t.\tID=$chr\_cent\n/;
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
