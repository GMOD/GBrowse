package Bio::Graphics::Glyph::wiggle_density;

# $Id: wiggle_density.pm,v 1.1.2.3 2007-05-24 04:18:44 lstein Exp $

use strict;
use base 'Bio::Graphics::Glyph::box';
use Bio::Graphics::Wiggle;

sub min_score {
  shift->option('min_score') || 0.0;
}

sub max_score {
  shift->option('max_score') || 1.0;
}

sub draw {
  my $self = shift;
  my ($gd,$left,$top,$partno,$total_parts) = @_;
  my $feature   = $self->feature;
  my ($wigfile) = $feature->attributes('wigfile');
  my ($wigoffset) = $feature->attributes('wigstart');
  return $self->SUPER::draw(@_) unless $wigfile;
  my $wig = Bio::Graphics::Wiggle->new($wigfile) or die;

  my ($x1,$y1,$x2,$y2) = $self->bounds($left,$top);
  my $chr              = $feature->seq_id;
  my $start            = $feature->start;
  my $end              = $feature->end;

  # filler -- this will get erased by the real data when it comes
  my $middle = ($y1+$y2)/2;
  my $fgcolor = $self->fgcolor;
  $gd->line($x1,$middle-3,$x1,$middle+3,$fgcolor);   # vertical span
  $gd->line($x1,$middle,$x2,$middle,$fgcolor); # horizontal span
  $gd->line($x2,$middle-3,$x2,$middle+3,$fgcolor);   # vertical span

  # find all overlapping segments in the wig file
  warn "\nsearching for $start->$end";
  my $iterator = $wig->segment_iterator($chr,$start,$end);
  my $idx = 0;
  while (my $seg = $iterator->next_segment) {
    warn "got ",$seg->start,"->",$seg->end;
    $self->draw_segment($gd,$seg,$start,$end,$x1,$y1,$x2,$y2,$idx++);
  }

  $self->draw_label(@_)       if $self->option('label');
  $self->draw_description(@_) if $self->option('description');
}

sub draw_segment {
  my $self = shift;
  my ($gd,$seg,$start,$end,$x1,$y1,$x2,$y2,$idx) = @_;
  my $seg_start = $seg->start;   # adjust for zero-based coordinates
  my $seg_end   = $seg->end;
  my $step      = $seg->step;
  my $span      = $seg->span;

  # clip, because wig files do no clipping
  $seg_start = $start      if $seg_start < $start;
  $seg_end   = $end        if $seg_end   > $end;

  # figure out where we're going to start
  my $scale  = $self->scale;  # pixels per base pair
  my $pixels_per_span = $scale * $span;
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

  # number of data points should be equal to length/step...
#  @data == $span/$step
#    or die "number of data points should be equal to length/step: span=$span, step=$step, datapoints = ",
#      scalar @data;

  warn scalar(@data)," data points";

  my $min_value = $self->min_score;
  my $max_value = $self->max_score;

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
    $self->filled_box($gd,$x1,$y1,$x1+$pixels_per_span,$y2,$idx,$idx) unless $idx == 0;
    $x1 += $pixels_per_step;
  }

}

sub calculate_color {
  my $self = shift;
  my ($s,$rgb,$min_score,$max_score) = @_;
  return map { 255 - (255-$_) * min(max( ($s-$min_score)/($max_score-$min_score), 0), 1) } @$rgb;
}

sub min { $_[0] < $_[1] ? $_[0] : $_[1] }
sub max { $_[0] > $_[1] ? $_[0] : $_[1] }

sub get_description {
  my $self = shift;
  my $feature = shift;
  return join '',"wigFile = ",$feature->attributes('wigfile'),'; wig_offset=',$feature->attributes('wigstart');
}

1;
