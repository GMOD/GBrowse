package Bio::Graphics::Glyph::allele_tower;

# $Id: allele_tower.pm,v 1.1 2004-02-07 00:57:51 mummi Exp $
# Glyph for drawing each allele found at a SNP position in a column.

use strict;
use vars '@ISA';
@ISA = 'Bio::Graphics::Glyph::generic';
use Bio::Graphics::Glyph::generic;

sub height {
  my $self = shift;
  my @alleles;
  if (my $d = $self->option('alleles')) {
    @alleles = split /\//, $d;
  }
  my $size = 10 * ($#alleles +1);
  return $size;
}

sub draw_component {
  my $self = shift;
  my $gd = shift;
  my $fg = $self->fgcolor;

  # find the center and vertices
  my ($x1,$y1,$x2,$y2) = $self->calculate_boundaries(@_);

  if (my $d = $self->option('alleles')) {
    my @alleles = split /\//, $d;

    # If it is on the minus strand
    if (my $strand = $self->option('ref_strand') <0){
      foreach (@alleles) {
	tr/ACTG/TGAC/ if $self->option('complement');
      }
	  $fg = $self->bgcolor if $self->bgcolor;
    }


  for (my $i=0;$i<@alleles;$i++) {

      # Space out each allele
      my $position = -2 + $i * 10;
      $gd->string(GD::Font->Small,$x1-1, $position + $y1, $alleles[$i], $fg);
    }
  }
}

;

__END__

=head1 NAME

Bio::Graphics::Glyph::allele_tower - The "allele_tower" glyph

=head1 SYNOPSIS

  See <Bio::Graphics::Panel> and <Bio::Graphics::Glyph>.

=head1 DESCRIPTION

This glyph draws each allele found at a SNP position in a column. See www.hapmap.org/cgi-perl/gbrowse/gbrowse 'genotyped SNPs' for an example. The common options are available (except height which is calculated based on the number of alleles).  


=head2 GETTING THE ALLELES

To specify the alleles, load these as an attribute in the last column of the GFF, and then use the  'alleles' option to return the alleles e.g.

  alleles = sub {
	my $snp = shift;
	return $snp->attributes('Alleles');
	}

=head2 OPTIONS

=head3 GLYPH COLOR

The glyph color and be configured to be different if the feature is on the plus or minus strand.  Use fgcolor to define the glyph color for the plus strand and bgcolor for the minus strand.  For example:

   fgcolor     = blue
   bgcolor     = red

For this option to work, you must also set ref_strand to return the strand of the feature:
   ref_strand        = sub {shift->strand}

=head3 REVERSE

If the alleles on the negative strand need to be the complement of what is listed in the GFF files, (e.g. A/G becomes T/C), set the complement option to have value 1

complement   = 1

For this option to work, you must also set ref_strand to return the strand of the feature:

ref_strand        = sub {shift->strand}

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

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut
