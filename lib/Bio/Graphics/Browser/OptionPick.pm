package Bio::Graphics::Browser::OptionPick;

=head1 NAME

Bio::Graphics::Browser::OptionPick -- Pick options

=head1 SYNOPSIS

 use Bio::Graphics::Browser::OptionPick;
 my $picker = Bio::Graphics::Browser::OptionPick->new($config);

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

my @GRADIENT =
  ('white','#D3D3D3','#A9A9A9','gray','black','red','yellow','blue','green','orange','magenta','cyan',
   '#FFCCCC','#FFAAAA','#FF9999','#EE7777','#EE5555','#EE3333','#EE2222','#DD0000','#DD2222','#EE3344','#EE5566',
   '#EE6699','#EE88BB','#EEAADD','#EEBBFF','#EEBBFF','#EEBBFF','#DDBBFF','#DDBBFF','#CCBBFF','#CCCCFF','#CCCCFF',
   '#AAAAEE','#8899EE','#7777DD','#5566CC','#3355BB','#2233BB','#0022AA','#2244AA','#3366BB','#5588CC','#7799CC',
   '#88BBDD','#AADDDD','#CCFFEE','#BBFFCC','#AAFFAA','#99EE88','#77EE66','#66EE44','#55EE22','#44EE00','#66EE11',
   '#77EE11','#99EE22','#AAEE22','#CCEE33','#DDEE33','#FFFF44');
my %LABELS = (
	      '#D3D3D3' => 'light gray',
	      'gray'    => 'dark gray',
	      '#A9A9A9' => 'gray',
	     );

sub new {
  my $self   = shift;
  my $config = shift;
  return bless {config => $config},ref $self || $self;
}

sub translate {
  my $self = shift;
  my $str =  shift;
  return $self->{config}->tr($str) || $str;
}

sub config { shift->{config} }


sub color_pick {
  my $self = shift;
  my ($form_name,$default_color,$current_color) = @_;

  if (ref($default_color)) {  # CODE or something else horrible
    $default_color = $self->translate('DYNAMIC_VALUE');
  }

  $current_color ||= $default_color;

  my $menu = qq(<select name="$form_name"
                style="background-color:$current_color"
                onChange="this.style.background=this.options[this.selectedIndex].value">\n);

  my $default = $self->translate('DEFAULT');

  # add default color
  my $selected = $default_color eq $current_color ? 'selected' : '';
  $menu .= qq(<option value="$default_color" style="background-color:$default_color"$selected>$default_color $default</option>\n);

  my $index = 0;
  for my $color (@GRADIENT) {
    next if $color eq $default_color;
    my $selected    = $color eq $current_color ? 'selected' : '';
    my $description = $LABELS{$color} || ($color =~ /^\#/ ? 'gradient'.$index++ : $color);
    my $fontcolor   = $color eq 'white' ? 'black' : 'white';
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

  my $dynamic =  $self->translate('DYNAMIC_VALUE');
  my %seen;
  my @values = grep {!$seen{$_}++} map { ref($_) || /^CODE\(/ ? $dynamic : $_ } @$values;

  $current ||= $default;
  my $def = $self->translate('DEFAULT');

  return CGI::popup_menu(-name    => $name,
			 -values  => \@values,
			 -default => $current,
			 -labels  => {$default => "$default $def"},
			 -override=>1);
}

1;
