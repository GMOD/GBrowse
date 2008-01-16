package Bio::Graphics::Glyph::wiggle_xyplot;

use strict;
use base qw(Bio::Graphics::Glyph::xyplot Bio::Graphics::Glyph::smoothing);
use IO::File;

# we override the draw method so that it dynamically creates the parts needed
# from the wig file rather than trying to fetch them from the database
sub draw {
  my $self = shift;
  my ($gd,$dx,$dy) = @_;

  my $feature     = $self->feature;
  my ($wigfile)   = $feature->attributes('wigfile');

  warn "wigfile = $wigfile";

  return $self->draw_wigfile($feature,$wigfile,@_) if $wigfile;

  my ($densefile) = $feature->attributes('densefile');
  return $self->draw_densefile($feature,$densefile,@_) if $densefile;

  return $self->SUPER::draw(@_);
}

sub draw_wigfile {
  my $self = shift;
  my $feature = shift;
  my $wigfile = shift;

  eval "require Bio::Graphics::Wiggle" unless Bio::Graphics::Wiggle->can('new');
  my $wig = Bio::Graphics::Wiggle->new($wigfile) or die;

  my $chr         = $feature->seq_id;
  my $panel_start = $self->panel->start;
  my $panel_end   = $self->panel->end;
  my $start       = $feature->start > $panel_start ? $feature->start : $panel_start;
  my $end         = $feature->end   < $panel_end   ? $feature->end   : $panel_end;

  $self->wig($wig);
  $self->create_parts_for_dense_feature($wig,$start,$end);

  $self->SUPER::draw(@_);
}

sub wig {
  my $self = shift;
  my $d = $self->{wig};
  $self->{wig} = shift if @_;
  $d;
}

sub draw_densefile {
  my $self = shift;
  my $feature = shift;
  my $densefile = shift;

  my ($denseoffset) = $feature->attributes('denseoffset');
  my ($densesize)   = $feature->attributes('densesize');
  $denseoffset ||= 0;
  $densesize   ||= 1;

  my $smoothing      = $self->get_smoothing;
  my $smooth_window  = $self->smooth_window;
  my $start          = $self->smooth_start;
  my $end            = $self->smooth_end;

  my $fh         = IO::File->new($densefile) or die "can't open $densefile: $!";
  eval "require Bio::Graphics::DenseFeature" unless Bio::Graphics::DenseFeature->can('new');
  my $dense = Bio::Graphics::DenseFeature->new(-fh=>$fh,
					       -fh_offset => $denseoffset,
					       -start     => $feature->start,
					       -smooth    => $smoothing,
					       -recsize   => $densesize,
					       -window    => $smooth_window,
					      ) or die "Can't initialize DenseFeature: $!";
  $self->create_parts_for_dense_feature($dense,$start,$end);
  $self->SUPER::draw(@_);
}

sub create_parts_for_dense_feature {
  my $self = shift;
  my ($dense,$start,$end) = @_;

  my $span = $self->width;
  my $data = $dense->values($start,$end,$span);
  my $points_per_span = ($end-$start+1)/$span;
  my @parts;

  for (my $i=0; $i<$span;$i++) {
    my $offset = $i * $points_per_span;
    my $value  = shift @$data;
    push @parts,Bio::Graphics::Feature->new(-score => $value,
					    -start => int($start + $i * $points_per_span),
					    -end   => int($start + $i * $points_per_span));
  }
  $self->{parts} = [];
  $self->add_feature(@parts);
}

sub minmax {
  my $self  = shift;
  my $parts = shift;
  if (my $wig = $self->wig) {
    my $max = $self->option('max_score');
    my $min = $self->option('min_score');
    $max = $wig->max unless defined $max;
    $min = $wig->min unless defined $min;
    return ($min,$max);
  } else {
    return $self->SUPER::minmax($parts);
  }
}

sub subsample {
  my $self = shift;
  my ($data,$start,$span) = @_;
  my $points_per_span = @$data/$span;
  my @parts;
  for (my $i=0; $i<$span;$i++) {
    my $offset = $i * $points_per_span;
    my $value  = $data->[$offset + $points_per_span/2];
    push @parts,Bio::Graphics::Feature->new(-score => $value,
					    -start => int($start + $i * $points_per_span),
					    -end   => int($start + $i * $points_per_span));
  }
  return @parts;
}

sub create_parts_for_segment {
  my $self = shift;
  my ($seg,$start,$end) = @_;
  my $seg_start = $seg->start;
  my $seg_end   = $seg->end;
  my $step      = $seg->step;
  my $span      = $seg->span;

  # clip, because wig files do no clipping
  $seg_start = $start      if $seg_start < $start;
  $seg_end   = $end        if $seg_end   > $end;

  return unless $start < $end;

  # get data values across the area
  my @data = $seg->values($start,$end);

  # create a series of parts
  my @parts;
  for (my $i = $start; $i <= $end ; $i += $step) {
    my $data_point = shift @data;
    push @parts,Bio::Graphics::Feature->new(-score => $data_point,
					   -start => $i,
					   -end   => $i + $step - 1);
  }
  $self->{parts} = [];
  $self->add_feature(@parts);
}


1;

__END__

=head1 NAME

Bio::Graphics::Glyph::wiggle_xyplot - An xyplot plot compatible with dense "wig"data

=head1 SYNOPSIS

  See <Bio::Graphics::Panel> and <Bio::Graphics::Glyph>.

=head1 DESCRIPTION

This glyph works like the regular xyplot but takes value data in
Bio::Graphics::Wiggle file format:

TODO! UPDATE DOCUMENTATION FOR DENSE FILES

 reference = chr1
 ChipCHIP Feature1 1..10000 wigfile=./test.wig;wigstart=0
 ChipCHIP Feature2 10001..20000 wigfile=./test.wig;wigstart=656
 ChipCHIP Feature3 25001..35000 wigfile=./test.wig;wigstart=1312

The "wigfile" attribute gives a relative or absolute pathname to a
Bio::Graphics::Wiggle format file. The optional "wigstart" option
gives the offset to the start of the data. If not specified, a linear
search will be used to find the data. The data consist of a packed
binary representation of the values in the feature, using a constant
step such as present in tiling array data.

=head2 OPTIONS

The same as the regular xyplot glyph, except that the "wigfile" and
"wigstart" options are also recognized.

TODO: add "smoothing" "densefile", "denseoffset", and "densesize" options.

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

Lincoln Stein E<lt>steinl@cshl.eduE<gt>.

Copyright (c) 2007 Cold Spring Harbor Laboratory

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut
