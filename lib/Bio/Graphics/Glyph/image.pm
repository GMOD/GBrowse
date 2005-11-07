package Bio::Graphics::Glyph::image;

use strict;
use base 'Bio::Graphics::Glyph::generic';

#
#       |--------------------| true position  ('height' high)
#       .                    .
#      .                      .     diagonal  (vertical spacing high)
#     .                        .
#    +--------------------------+
#    |                          |
#    |                          |
#    |                          |   image
#    |                          |
#    |                          |
#    |                          |
#    +--------------------------+

use constant VERTICAL_SPACING => 20;

sub new {
  my $self  = shift->SUPER::new(@_);
  $self->_get_image();
  return $self;
}

sub _get_image {
  my $self    = shift;
  my $image   = $self->image_path            or return;
  my $format  = $self->_guess_format($image) or return;
  my $gd      =   $format eq 'png' ? GD::Image->newFromPng($image,1)
                : $format eq 'jpg' ? GD::Image->newFromJpeg($image,1)
		: $format eq 'gif' ? GD::Image->newFromGif($image)
		: $format eq 'gd'  ? GD::Image->newFromGd($image)
		: $format eq 'gd2' ? GD::Image->newFromGd2($image)
		: undef;
  $gd or return;
  $self->{image} = $gd;
}

sub _guess_format {
  my $self = shift;
  my $path = shift;
  return 'png'  if $path =~ /\.png$/i;
  return 'jpg'  if $path =~ /\.jpe?g$/i;
  return 'gif'  if $path =~ /\.gif(87)?$/i;
  return 'gd'   if $path =~ /\.gd$/i;
  return 'gd2'  if $path =~ /\.gd2$/i;
}

sub image_path {
  my $self = shift;
  my $feature  = $self->feature   or return;
  my $dirname  = $self->image_dir or return;
  my $basename = $self->option('image');

  # can't get it from callback, so try looking for an 'image' attribute
  if (!$basename && $feature->can('has_tag') && $feature->has_tag('image')) {
    ($basename)  = $feature->get_tag_values('image');
  }

  return unless $basename;
  return "$dirname/$basename";
}

sub pad_left {
  my $self = shift;
  my $pad          = $self->SUPER::pad_left;
  my $image        = $self->{image} or return $pad;
  my $width_needed = ($image->width - $self->width)/2;
  return $pad > $width_needed ? $pad : $width_needed;
}

sub pad_right {
  my $self = shift;
  my $pad          = $self->SUPER::pad_right;
  my $image        = $self->{image} or return $pad;
  my $width_needed = ($image->width - $self->width)/2;
  return $pad > $width_needed ? $pad : $width_needed;
}

sub pad_bottom {
  my $self   = shift;
  my $pb     = $self->SUPER::pad_bottom;
  my $image  = $self->{image} or return $pb;
  $pb       += $self->vertical_spacing;
  $pb       += $image->height;
  return $pb;
}

sub vertical_spacing {
  my $self  = shift;
  my $vs    = $self->option('vertical_spacing');
  return $vs if defined $vs;
  return VERTICAL_SPACING;
}

sub draw_description {
  my $self = shift;
  my ($gd,$left,$top,$partno,$total_parts) = @_;
  $top += $self->{image}->height+$self->vertical_spacing if $self->{image};
  $self->SUPER::draw_description($gd,$left,$top,$partno,$total_parts);
}

sub draw_label {
  my $self = shift;
  my ($gd,$left,$top,$partno,$total_parts) = @_;
  $left += $self->pad_left;
  $self->SUPER::draw_label($gd,$left,$top,$partno,$total_parts);
}

sub image_dir {
  my $self = shift;
  return $self->option('image_dir');
}

sub draw_component {
  my $self  = shift;
  my $gd    = shift;
  my($x1,$y1,$x2,$y2) = $self->bounds(@_);
  #my $image = $self->{image} or return $self->SUPER::draw($gd,@_);
  $self->SUPER::draw_component($gd,@_);
  my $image  = $self->{image} or return;

  my $fgcolor = $self->fgcolor;
  my $bgcolor = $self->bgcolor;
  my $height  = $self->option('height');
  my $half    = 4;

  my $delta = (($x2-$x1) - $image->width)/2;
  my($x,$y) = ($x1+$delta,$y1+$self->vertical_spacing+$self->height);
  $gd->copy($image,$x,$y,0,0,$image->width,$image->height);

  $gd->line($x1,$y2+2,$x1,$y2+$half,$fgcolor);
  $gd->line($x2,$y2+2,$x2,$y2+$half,$fgcolor);
  $gd->line($x1,$y2+$half,$x,$y-$half,$fgcolor);
  $gd->line($x2,$y2+$half,$x+$image->width-1,$y-$half,$fgcolor);
  $gd->line($x,$y-$half,$x,$y-2,$fgcolor);
  $gd->line($x+$image->width-1,$y-$half,$x+$image->width-1,$y-2,$fgcolor);
}


1;
