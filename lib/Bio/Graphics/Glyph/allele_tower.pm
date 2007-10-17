package Bio::Graphics::Glyph::allele_tower;

# $Id: allele_tower.pm,v 1.4.6.2.6.2 2007-10-17 01:48:21 lstein Exp $
# Glyph for drawing each allele found at a SNP position in a column.

use strict;
use vars '@ISA';
@ISA = 'Bio::Graphics::Glyph::generic';
use Bio::Graphics::Glyph::generic;

# Give enough height to fit in the alleles
sub height {
  my $self = shift;
  my @alleles = $self->feature->attributes('Alleles');
  @alleles    = split /\//,$self->option('alleles') unless @alleles >= 2;
  my $size = 2 + 10 * ($#alleles +1);
  return $size;
}

# Need to make room for the allele bars if there is room
sub pad_right {
  my $self = shift;
  my $right = $self->SUPER::pad_right;
  return $right > 55 ? $right : 55 if $self->label;
  my $width = GD::Font->Small->width * 2.5;
  return $width > $right ? $width : $right;
}

sub draw_component {
  my $self = shift;
  my $gd = shift;
  my $fg = $self->fgcolor;

  # find the center and vertices
  my ($x1,$y1,$x2,$y2) = $self->calculate_boundaries(@_);

  my $feature = $self->feature;
  my @alleles = $feature->attributes('Alleles');
  @alleles    = split /\//,$self->option('alleles') unless @alleles == 2;

  if (@alleles) {
    # If it is on the minus strand
    if (my $strand = $self->option('ref_strand') <0){
      foreach (@alleles) {
	tr/ACTG/TGAC/ if $self->option('complement');
      }
      $fg = $self->bgcolor if $self->bgcolor;
    }

    for (my $i=0;$i<@alleles;$i++) {
      my $position = -2+ $i * 10;       # Space out each allele

      # for the allele frequency horizontal bars (maf lines)
      # x1, x2 are the same,  y2 is bigger than y1
      my $maf = defined ($self->option('maf'))? $self->option('maf') : "NO";

      # If the MAF freq = 0, the major allele will be length 44 + 6
      my $bar_length = $maf*44 +6 unless $maf eq "NO";
      my $y_delta = ($y2- $y1)/(2 * ($#alleles +1));  # correct for height

      if (my $minor_allele = $self->option('minor_allele')){
	if ($alleles[$i] eq $minor_allele) {
	  # Print the letter
	  $gd->string(GD::Font->Small,$x1-1, 
		      $position + $y1, $alleles[$i], $fg);
	}
	else {
	  # If this is the major allele, the bar length must be 44 +6 - maf length
	  $bar_length = 44-($maf*44) +6 unless $maf eq "NO";
	  # Print the letter
	  $gd->string(GD::Font->MediumBold,$x1-1, 
		      $position + $y1, $alleles[$i], $fg);

	}
	# Print the line for the allele freq. bar
	if ($self->label){
	  $gd->line($x1+6,           $y1 + (2*$i +1)*$y_delta, 
		    $x1+$bar_length, $y1 + (2*$i +1)*$y_delta, $fg) 
	    unless $maf eq "NO";
	}

      }
      # if no minor allele is defined, use the small fonts for both
      else {
	$gd->string(GD::Font->Small,$x1-1, $position + $y1, $alleles[$i], $fg);
      }
    } # end of for
  }
}

;

__END__

=head1 NAME

Bio::Graphics::Glyph::allele_tower - The "allele_tower" glyph

=head1 SYNOPSIS

  See <Bio::Graphics::Panel> and <Bio::Graphics::Glyph>.

=head1 DESCRIPTION

This glyph draws a letter for each allele found at a SNP position, one above the other (i.e. in a column). For example:
    A      
    G   

See also http://www.hapmap.org/cgi-perl/gbrowse/gbrowse 'genotyped SNPs' for an example.

The common options are available (except height which is calculated
based on the number of alleles).  In addition, if you give the glyph
the minor allele frequency (MAF) and indicate which is the minor
allele, the glyph will display these differences.


=head2 GETTING THE ALLELES

To specify the alleles, create an "Alleles" attribute for the feature.
There should be two such attributes.  For example, for a T/G
polymorphism, the GFF load file should look like:

 Chr3  .  SNP   12345 12345 . . . SNP ABC123; Alleles T ; Alleles G

Alternatively, you can pass an "alleles" callback to the appropriate
section of the config file.  This option should return the two alleles
separated by a slash:

  alleles = sub {
	my $snp = shift;
	my @d   = $snp->attributes('AllelePair');
	return join "/",@d;
    }

=head2 OPTIONS

 . Glyph Colour
 . Different colour for alleles on the reverse strand
 . Print out the complement for alleles on the reverse strand
 . Major allele shown in bold
 . Horizontal histogram to show allele frequency

=head3 GLYPH COLOR

The glyph color can be configured to be different if the feature is on the plus or minus strand.  Use fgcolor to define the glyph color for the plus strand and bgcolor for the minus strand.  For example:

   fgcolor     = blue
   bgcolor     = red

For this option to work, you must also set ref_strand to return the strand of the feature:
   ref_strand        = sub {shift->strand}

=head3 REVERSE STRAND ALLELES

If the alleles on the negative strand need to be the complement of what is listed in the GFF files, (e.g. A/G becomes T/C), set the complement option to have value 1

complement   = 1

For this option to work, you must also set ref_strand to return the strand of the feature:

ref_strand        = sub {shift->strand}

=head3 MAJOR/MINOR ALLELE

Use the 'minor_allele' option to return the minor allele for the SNP.  If you use this option, the major allele will appear in bold type.

=head3 ALLELE FREQUENCY HISTOGRAMS

Use the 'maf' option to return the minor allele frequency for the SNP.  If you use this option, a horizontal histogram will be drawn next to the alleles, to indicate their relative frequencies. e.g.

 A______
 C__

Note: The 'label' option must be set to 1 (i.e. on) and the
'minor_allele' option must return a valid allele for this to work.

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
L<Bio::Graphics::Glyph::allele_tower>,
L<Bio::DB::GFF>,
L<Bio::SeqI>,
L<Bio::SeqFeatureI>,
L<Bio::Das>,
L<GD>

=head1 AUTHOR

Fiona Cunningham E<lt>cunningh@cshl.eduE<gt> in Lincoln Stein's lab E<lt>steinl@cshl.eduE<gt>.

Copyright (c) 2003 Cold Spring Harbor Laboratory

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut
