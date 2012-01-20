package Bio::Graphics::Browser2::OptionPick;

=head1 NAME

Bio::Graphics::Browser2::OptionPick -- Pick options

=head1 SYNOPSIS

 use Bio::Graphics::Browser2::OptionPick;
 my $picker = Bio::Graphics::Browser2::OptionPick->new($render_object);

 print start_html(),
  start_form(),
  $picker->('bgcolor','orange','blue'),
  end_form(),
  end_html();

=head1 Author

Copyright 2007 Cold Spring Harbor Laboratory.

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut


use strict;
use Bio::Graphics::Panel;
use Bio::Graphics::Glyph::heat_map;

# my @GRADIENT =
#   ('white','#D3D3D3','#A9A9A9','gray','black','red','yellow','blue','green','orange','magenta','cyan',
#    '#FFCCCC','#FFAAAA','#FF9999','#EE7777','#EE5555','#EE3333','#EE2222','#DD0000','#DD2222','#EE3344','#EE5566',
#    '#EE6699','#EE88BB','#EEAADD','#EEBBFF','#EEBBFF','#EEBBFF','#DDBBFF','#DDBBFF','#CCBBFF','#CCCCFF','#CCCCFF',
#    '#AAAAEE','#8899EE','#7777DD','#5566CC','#3355BB','#2233BB','#0022AA','#2244AA','#3366BB','#5588CC','#7799CC',
#    '#88BBDD','#AADDDD','#CCFFEE','#BBFFCC','#AAFFAA','#99EE88','#77EE66','#66EE44','#55EE22','#44EE00','#66EE11',
#    '#77EE11','#99EE22','#AAEE22','#CCEE33','#DDEE33','#FFFF44');
my $heatmap = 'Bio::Graphics::Glyph::heat_map';
my $bgp     = 'Bio::Graphics::Panel';

my @GRADIENT = sort {
    my ($r1,$g1,$b1) = $bgp->color_name_to_rgb($a);
    my ($r2,$g2,$b2) = $bgp->color_name_to_rgb($b);
    my ($h1,$s1,$v1) = $heatmap->RGBtoHSV($r1,$g1,$b1);
    my ($h2,$s2,$v2) = $heatmap->RGBtoHSV($r2,$g2,$b2);
    return $h1<=>$h2 || $s1<=>$s2 || $v1<=>$v2;
} grep {!/gradient/} Bio::Graphics::Panel->color_names;
my %LABELS = ();

sub new {
  my $self   = shift;
  my $render_object = shift;
  return bless {render_object => $render_object},ref $self || $self;
}

sub translate {
  my $self = shift;
  my $str =  shift;
  return $self->{render_object}->tr($str) || $str;
}

sub render_object { shift->{render_object} }


sub color_pick {
  my $self = shift;
  my ($form_name,$default_color,$current_color,$class) = @_;
  $class ||= 'color_picker';

  my ($bgcolor,$fontcolor);
  my $dynamic    = $self->translate('DYNAMIC_VALUE');

  if (ref($default_color)) {  # CODE or something else horrible
      $default_color = $dynamic;
      $bgcolor       = 'white';
      $fontcolor     = 'black';
  } else {
      $bgcolor     = $default_color;
      my ($r,$g,$b)   = Bio::Graphics::Panel->color_name_to_rgb($default_color);
      my $avg         = ($r+$g+$b)/3;
      $fontcolor   = $avg > 128 ? 'black' : 'white';
  }

  $current_color ||= $default_color;

  my ($current_bg,$current_fg);
  if ($current_color eq $dynamic) {
      $current_bg = 'white';
      $current_fg = 'black';
  } else {
      $current_bg = $current_color;
      my ($r,$g,$b)   = Bio::Graphics::Panel->color_name_to_rgb($current_color);
      my $avg         = ($r+$g+$b)/3;
      $current_fg     = $avg > 128 ? 'black' : 'white';
  }

  my $menu = qq(<select name="$form_name"
                class="$class",
                style="background-color:$current_bg;color:$current_fg"
                onChange="var s=this.options[this.selectedIndex];Element.extend(s);this.style.background=s.getStyle('background-color');this.style.color=s.style.color">\n);

  my $default = $self->translate('DEFAULT');

  # add default color
  my $selected = $default_color eq $current_color ? 'selected' : '';
  $menu .= qq(<option value="$default_color" style="color:$fontcolor;background-color:$bgcolor"$selected>$default_color $default</option>\n);

  my $index = 0;
  for my $color (@GRADIENT) {
    next if $color eq $default_color;
    my $selected    = $color eq $current_color ? 'selected' : '';
    my $description  = $color;
    my ($r,$g,$b)   = Bio::Graphics::Panel->color_name_to_rgb($color);
    my $avg         = ($r+$g+$b)/3;
    my $fontcolor   = $avg > 128 ? 'black' : 'white';
    $menu .= qq(<option value="$color" bgcolor="$color" style="background-color:$color;color:$fontcolor"$selected>$description</option>\n);
  }
  $menu .= "</select\n>";
  return $menu;
}

sub popup_menu {
  my $self = shift;
  my %args = @_;
  my $name    = $args{-name};
  my $current = $args{-current};
  my $default = $args{-default};
  my $values  = $args{-values};
  my $id      = $args{-id};
  my $class   = $args{-class};
  my $labels  = $args{-labels}  || {};
  my $scripts = $args{-scripts} || {};

  my $dynamic =  $self->translate('DYNAMIC_VALUE');
  my %seen;
  my @values = grep {!$seen{$_}++} map { ref($_) || /^CODE\(/ ? $dynamic : $_ } @$values;

  $current ||= $default;
  my $def    = $self->translate('DEFAULT');
  my $def_label = $labels->{$default} || $default;
  my %labels    = (%$labels,$default => "$def_label $def");
  my @extra     = $id ? (-id => $id) : ();
  push @extra,(-class=>$class) if $class;

  return CGI::popup_menu(-name    => $name,
			 -values  => \@values,
			 -default => $current,
			 -labels  => \%labels,
                         %$scripts,
                         @extra,
			 -override=>1);
}

1;
