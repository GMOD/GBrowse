package Bio::Graphics::Glyph::wiggle_density;

# $Id: wiggle_density.pm,v 1.1.2.6 2007-10-17 01:48:22 lstein Exp $

use strict;
use base qw(Bio::Graphics::Glyph::box Bio::Graphics::Glyph::smoothing);

sub min_score {
  shift->option('min_score');
}

sub max_score {
  shift->option('max_score');
}

sub draw {
  my $self = shift;
  my ($gd,$left,$top,$partno,$total_parts) = @_;
  my $feature   = $self->feature;

  my ($wigfile) = $feature->attributes('wigfile');
  if ($wigfile) {
    $self->draw_wigfile($feature,$wigfile,@_);
    $self->draw_label(@_)       if $self->option('label');
    $self->draw_description(@_) if $self->option('description');
    return;
  }

  my ($densefile) = $feature->attributes('densefile');
  if ($densefile) {
    $self->draw_densefile($feature,$densefile,@_);
    $self->draw_label(@_)       if $self->option('label');
    $self->draw_description(@_) if $self->option('description');
    return;
  }

  return $self->SUPER::draw(@_);

}

sub draw_wigfile {

  my $self    = shift;
  my $feature = shift;
  my $wigfile = shift;
  my ($gd,$left,$top) = @_;

  my ($wigoffset) = $feature->attributes('wigstart');

  eval "require Bio::Graphics::Wiggle" unless Bio::Graphics::Wiggle->can('new');
  my $wig = Bio::Graphics::Wiggle->new($wigfile) or die;

  my ($x1,$y1,$x2,$y2) = $self->bounds($left,$top);
  my $chr              = $feature->seq_id;
  my $panel_start = $self->panel->start;
  my $panel_end   = $self->panel->end;
  my $start       = $feature->start > $panel_start ? $feature->start : $panel_start;
  my $end         = $feature->end   < $panel_end   ? $feature->end   : $panel_end;

  # filler -- this will get erased by the real data when it comes
  my $middle = ($y1+$y2)/2;
  my $fgcolor = $self->fgcolor;
  $gd->line($x1,$middle-3,$x1,$middle+3,$fgcolor);   # vertical span
  $gd->line($x1,$middle,$x2,$middle,$fgcolor); # horizontal span
  $gd->line($x2,$middle-3,$x2,$middle+3,$fgcolor);   # vertical span

  # find all overlapping segments in the wig file
  my $iterator = $wig->segment_iterator($chr,$start,$end);
  $iterator->offset($wigoffset) if $wigoffset;
  while (my $seg = $iterator->next_segment) {
    $self->draw_segment($gd,
			$start,$end,
			$seg,
			$seg->start,$seg->end,
			$seg->step,$seg->span,
			$x1,$y1,$x2,$y2);
  }

}

sub draw_densefile {
  my $self = shift;
  my $feature   = shift;
  my $densefile = shift;
  my ($gd,$left,$top) = @_;

  my ($denseoffset) = $feature->attributes('denseoffset');
  my ($densesize)   = $feature->attributes('densesize');
  $denseoffset ||= 0;
  $densesize   ||= 1;

  my $panel_start = $self->panel->start;
  my $panel_end   = $self->panel->end;
  my $start       = $feature->start > $panel_start ? $feature->start : $panel_start;
  my $end         = $feature->end   < $panel_end   ? $feature->end   : $panel_end;

  my $smooth_window = int (($end - $start)/$self->width);
  $smooth_window    = 1 unless $smooth_window > 2;
  my $smoothing     = $self->get_smoothing;

  my $fh         = IO::File->new($densefile) or die "can't open $densefile: $!";
  eval "require Bio::Graphics::DenseFeature" unless Bio::Graphics::DenseFeature->can('new');
  my $dense = Bio::Graphics::DenseFeature->new(-fh=>$fh,
					       -fh_offset => $denseoffset,
					       -start     => $feature->start,
					       -smooth    => $smooth_window > 1 ? 'mean' : 'none',
					       -recsize   => $densesize,
					       -window    => $smooth_window,
					      ) or die "Can't initialize DenseFeature: $!";

  my ($x1,$y1,$x2,$y2) = $self->bounds($left,$top);
  $self->draw_segment($gd,
		      $start,$end,
		      $dense,$start,$end,
		      1,1,
		      $x1,$y1,$x2,$y2);
}

sub draw_segment {
  my $self = shift;
  my ($gd,
      $start,$end,
      $seg,
      $seg_start,$seg_end,
      $step,$span,
      $x1,$y1,$x2,$y2) = @_;

  # clip, because wig files do no clipping
  $seg_start = $start      if $seg_start < $start;
  $seg_end   = $end        if $seg_end   > $end;

  # figure out where we're going to start
  my $scale  = $self->scale;  # pixels per base pair
  my $pixels_per_span = $scale * $span + 1;
  my $pixels_per_step = $scale * $step;

  # if the feature starts before the data starts, then we need to draw
  # a line indicating missing data (this only happens if something went
  # wrong upstream)
  if ($seg_start > $start) {
    my $terminus = $self->map_pt($seg_start);
    $start = $seg_start;
    $x1    = $terminus;
  }
  # if the data ends before the feature ends, then we need to draw
  # a line indicating missing data (this only happens if something went
  # wrong upstream)
  if ($seg_end < $end) {
    my $terminus = $self->map_pt($seg_end);
    $end = $seg_end;
    $x2    = $terminus;
  }

  return unless $start < $end;

  # get data values across the area
  my @data = $seg->values($start,$end);

  my $min_value = $self->min_score;
  my $max_value = $self->max_score;

  unless (defined $min_value && defined $max_value) {
    ($min_value,$max_value) = $self->minmax(\@data);
  }

  # allocate colors
  my @rgb = $self->panel->rgb($self->bgcolor);
  my %color_cache;
  for (my $i = $start; $i <= $end ; $i += $step) {
    my $data_point = shift @data;
    next unless defined $data_point;
    $data_point    = $min_value if $min_value > $data_point;
    $data_point    = $max_value if $max_value < $data_point;
    my ($r,$g,$b)  = $self->calculate_color($data_point,\@rgb,$min_value,$max_value);
    my $idx        = $color_cache{$r,$g,$b} ||= $self->panel->translate_color($r,$g,$b);
    $self->filled_box($gd,$x1,$y1,$x1+$pixels_per_span,$y2,$idx,$idx); # unless $idx == 0;
    $x1 += $pixels_per_step;
  }

}

sub calculate_color {
  my $self = shift;
  my ($s,$rgb,$min_score,$max_score) = @_;
  return map { int(255 - (255-$_) * min(max( ($s-$min_score)/($max_score-$min_score), 0), 1)) } @$rgb;
}

sub min { $_[0] < $_[1] ? $_[0] : $_[1] }
sub max { $_[0] > $_[1] ? $_[0] : $_[1] }

sub minmax {
  my $self = shift;
  my $data = shift;
  my $min  = +999_999_999;
  my $max  = -999_999_999;
  for (@$data) {
    $min = $_ if $_ < $min;
    $max = $_ if $_ > $max;
  }
  return ($min,$max);
}

sub get_description {
  my $self = shift;
  my $feature = shift;
  return join '',"wigFile = ",$feature->attributes('wigfile'),'; wig_offset=',$feature->attributes('wigstart');
}

1;

__END__

=head1 NAME

Bio::Graphics::Glyph::wiggle_density - A density plot compatible with dense "wig"data

=head1 SYNOPSIS

  See <Bio::Graphics::Panel> and <Bio::Graphics::Glyph>.

=head1 DESCRIPTION

This glyph works like the regular density but takes value data in
Bio::Graphics::Wiggle file format:

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

The same as the regular graded_segments glyph, except that the
"wigfile" and "wigstart" options are also recognized.

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
