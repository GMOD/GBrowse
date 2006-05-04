package Bio::Graphics::Glyph::ideogram;

# $Id: ideogram.pm,v 1.3.6.1.2.5 2006-05-04 22:13:10 lstein Exp $
# Glyph to draw chromosome ideograms

use strict qw/vars refs/;
use vars '@ISA';
use Bio::Graphics::Glyph;
use GD;

@ISA = 'Bio::Graphics::Glyph';

sub draw_component {
    my $self = shift;
    my $gd   = shift;
    my ( $left, $top ) = @_;

    my $arcradius = $self->option('arcradius') || 7;

    my $feat = $self->feature;
    my ( $x1, $y1, $x2, $y2 ) = $self->bounds(@_);

    my $stain = $feat->attributes('stain');

# Some genome sequences don't contain substantial telomere sequence (i.e. Arabidopsis)
# We can suggest their presence at the tips of the chromosomes by setting fake_telomeres = 1
# in the configuration file, resulting in the tips of the chromosome being painted black.
    my $fake_telomeres = $self->option('fake_telomeres') || 0;

    my ($bgcolor_index) = $self->option('bgcolor') =~ /$stain:(\S+)/;
    $bgcolor_index ||= 'white';
    my $black = $gd->colorAllocate( 0, 0, 0 );

    # a default centromere color
    my $cm_color = $self->{cm_color} = $gd->colorAllocate( 102, 102, 153 );
    my $bgcolor = $self->factory->translate_color($bgcolor_index);
    my $fgcolor = $self->fgcolor;

    if ( $feat->method =~ /^(cytoband|chromosome_band)$/i ) {

        # are we at the end of the chromosome?
        if ( $feat->start <= 1 ) {

            # left telomere
            my $status = $self->panel->flip ? 0 : 1;
            $bgcolor = $black if $fake_telomeres;
            $self->draw_telomere(
                $gd,      $x1,      $y1,        $x2, $y2,
                $bgcolor, $fgcolor, $arcradius, $status
            );
        }
        elsif ( $feat->stop >= $self->panel->end - 1000 ) {

            # right telomere
            my $status = $self->panel->flip ? 1 : 0;
            $bgcolor = $black if $fake_telomeres;
            $self->draw_telomere(
                $gd,      $x1,      $y1,        $x2, $y2,
                $bgcolor, $fgcolor, $arcradius, $status
            );
        }

        # or a stalk?
        elsif ( $stain eq 'stalk' ) {
            $self->draw_stalk( $gd, $x1, $y1, $x2, $y2, $bgcolor, $fgcolor );
        }

        # or a mouse-style chromosome tip?
        elsif ( $stain eq 'tip' ) {
            $self->draw_tip( $gd, $x1, $y1, $x2, $y2, $bgcolor, $fgcolor );
        }

        # or a regular band?
        else {
            my $svg = 1 if $self->panel->image_class =~ /SVG/;

            if ( $bgcolor_index =~ /var/ && $svg ) {
                $bgcolor = $self->{cm_color};
            }
            elsif ( $bgcolor_index =~ /var/ ) {
                my $var_tile = $self->create_tile('left');
                $gd->setTile($var_tile);
                $self->draw_cytoband( $gd, $x1, $y1, $x2, $y2, gdTiled,
                    $fgcolor );
            }
            else {
                $self->draw_cytoband( $gd, $x1, $y1, $x2, $y2, $bgcolor,
                    $fgcolor );
            }
        }
    }

    # or a centromere?
    elsif ( $feat->method eq 'centromere' ) {

        # patterns not yet supported in GD::SVG
        if ( $self->panel->image_class =~ /SVG/ ) {
            $self->draw_centromere( $gd, $x1, $y1, $x2, $y2, $cm_color,
                $fgcolor );
        }
        else {
            my $tile = $self->create_tile('right');
            $gd->setTile($tile);
            $self->draw_centromere( $gd, $x1, $y1, $x2, $y2, gdTiled,
                $fgcolor );
        }
    }
}

sub draw_cytoband {
    my $self = shift;
    my ( $gd, $x1, $y1, $x2, $y2, $bgcolor, $fgcolor, $tip ) = @_;

    my $svg = 1 if $self->panel->image_class =~ /SVG/;

    # draw the filled box
    $self->filled_box(@_);

    return 1 if $svg || $tip;

    $gd->line( $x1, $y1 + 1, $x1, $y2 - 1, $bgcolor );
    $gd->line( $x2, $y1 + 1, $x2, $y2 - 1, $bgcolor );
}

sub draw_tip {
    my $self = shift;
    $self->draw_cytoband( @_, 1 );
}

sub draw_centromere {
    my ( $self, $gd, $x1, $y1, $x2, $y2, $bgcolor, $fgcolor ) = @_;

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
    my ($self, $gd,      $x1,      $y1,        $x2,
        $y2,   $bgcolor, $fgcolor, $arcradius, $state
        )
        = @_;
    my $arcsize = abs( $y1 - $y2 );

    my $bwidth = $x2 - $x1;

    my ( $x, $y );
    my $outside_arc = 2 * $arcradius;

    if ( $state == 1 ) {    # left telomere
        $x = $x1 + $arcradius;
        $y = $y1 + $arcsize / 2;

        # move the telomere a bit if the terminal band is too narrow
        if ( $bwidth < $arcradius ) {
            $x -= $arcradius - $bwidth;
        }

        # gdArc makes for a slightly smoother telomere arc
        $self->draw_cytoband( $gd, $x, $y1, $x2, $y2, $bgcolor, $fgcolor );
        $gd->filledArc( $x, $y, $arcradius * 2,
            $arcsize, 90, 270, $fgcolor, gdArc );
        $gd->filledArc(
            $x, $y,
            $arcradius * 2 - 1.5,
            $arcsize - 3,
            90, 270, $bgcolor, gdArc
        );
    }
    else {    # right telomere
        $x = $x2 - $arcradius;
        $y = $y1 + $arcsize / 2;

        if ( $bwidth < $arcradius ) {
            $x += $arcradius - $bwidth;
        }

        $self->draw_cytoband( $gd, $x1, $y1, $x, $y2, $bgcolor, $fgcolor );
        $gd->filledArc( $x, $y, $arcradius * 2,
            $arcsize, 270, 90, $fgcolor, gdArc );
        $gd->filledArc(
            $x, $y,
            $arcradius * 2 - 1.5,
            $arcsize - 3,
            270, 90, $bgcolor, gdArc
        );
    }

    # GD::SVG hack :(
    if ( $self->panel->image_class =~ /SVG/ ) {
        $self->draw_cytoband( $gd, $x - 1, $y1 + 2, $x + 1, $y2 - 2, $bgcolor,
            $bgcolor );
    }
}

# for acrocentric stalk structure, draw a narrower cytoband
sub draw_stalk {
    my $self = shift;
    my ( $gd, $x1, $y1, $x2, $y2, $bgcolor, $fgcolor ) = @_;

    my $height = $self->height;
    my $shave_off = $height > 10 ? int( $height / 10 + 0.5 ) : 2;
    $_[2] += $shave_off;
    $_[4] -= $shave_off;

    $gd->line( $x1,     $y1,   $x1,     $_[2], $fgcolor );
    $gd->line( $x1,     $_[4], $x1,     $y2,   $fgcolor );
    $gd->line( $x2 - 1, $y1,   $x2 - 1, $_[2], $fgcolor );
    $gd->line( $x2 - 1, $_[4], $x2 - 1, $y2,   $fgcolor );

    $self->draw_cytoband(@_);
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
        $tile = GD::Image->new( 5, 5 );
        $tile->fill( 1, 1, $tile->colorAllocate( 255, 255, 255 ) );
        $tile->line( 5, 0, 0, 5, $tile->colorAllocate( 0, 0, 0 ) );
    }

    return $tile;
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
 ChrX    UCSC    chromosome_band        136700001       139000000       .       .       .       ID=Xq27.1;Name=Xq27.1;Alias=ChrXq27.1;stain=gpos75;
 ChrX    UCSC    chromosome_band        139000001       140700000       .       .       .       ID=Xq27.2;Name=Xq27.2;Alias=ChrXq27.2;stain=gneg;
 ChrX    UCSC    chromosome_band        140700001       145800000       .       .       .       ID=Xq27.3;Name=Xq27.3;Alias=ChrXq27.3;stain=gpos100;
 ChrX    UCSC    chromosome_band        145800001       153692391       .       .       .       ID=Xq28;Name=Xq28;Alias=ChrXq28;stain=gneg;
 ChrY    UCSC    chromosome_band        1       1300000 .       .       .       ID=Yp11.32;Name=Yp11.32;Alias=ChrYp11.32;stain=gneg;
 ChrY    UCSC    chromosome_band        1300001 2600000 .       .       .       ID=Yp11.31;Name=Yp11.31;Alias=ChrYp11.31;stain=gpos50;
 ChrY    UCSC    chromosome_band        2600001 9700000 .       .       .       ID=Yp11.2;Name=Yp11.2;Alias=ChrYp11.2;stain=gneg;
 ChrY    UCSC    chromosome_band        12800001        14800000        .       .       .       ID=Yq11.21;Name=Yq11.21;Alias=ChrYq11.21;stain=gneg;
 ChrY    UCSC    chromosome_band        14800001        19300000        .       .       .       ID=Yq11.221;Name=Yq11.221;Alias=ChrYq11.221;stain=gpos50;
 ChrY    UCSC    chromosome_band        19300001        21800000        .       .       .       ID=Yq11.222;Name=Yq11.222;Alias=ChrYq11.222;stain=gneg;
 ChrY    UCSC    chromosome_band        21800001        25800000        .       .       .       ID=Yq11.223;Name=Yq11.223;Alias=ChrYq11.223;stain=gpos50;
 ChrY    UCSC    chromosome_band        25800001        27700000        .       .       .       ID=Yq11.23;Name=Yq11.23;Alias=ChrYq11.23;stain=gneg;
 ChrY    UCSC    chromosome_band        27700001        50286555        .       .       .       ID=Yq12;Name=Yq12;Alias=ChrYq12;stain=gvar;
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
    print qq/$chr\tUCSC\tchromosome_band\t$start\t$stop\t.\t.\t.\tID=$chr_stripped$band;Name=$chr_stripped$band;Alias=$chr$band;stain=$stain;\n/;
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

Gudmundur A. Thorisson E<lt>mummi@cshl.eduE<gt>

Copyright (c) 2001-2005 Cold Spring Harbor Laboratory

=head1 CONTRIBUTORS

Sheldon McKay E<lt>mckays@cshl.edu<gt>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut







