package Bio::Graphics::Browser::ConfigSet::quantitative;

=head1 NAME

Bio::Graphics::Browser::ConfigSet::quantitative -- quantitative tracks

=head1 SYNOPSIS

 use Bio::Graphics::Browser::ConfigSet::quantitative;
 my $quant = Bio::Graphics::Browser::ConfigSet::quantitative->new();
 my @glyphs  = $quant->options('glyph');


This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut


use strict;
use Carp qw/carp croak/;
use base Bio::Graphics::Browser::ConfigSet;

use constant OPTIONS => ( 
  bgcolor    => [qw/
   white D3D3D3 A9A9A9 gray black red yellow blue green orange magenta cyan'
   FFCCCC FFAAAA FF9999 EE7777 EE5555 EE3333 EE2222 DD0000 DD2222 EE3344 EE5566
   EE6699 EE88BB EEAADD EEBBFF EEBBFF EEBBFF DDBBFF DDBBFF CCBBFF CCCCFF CCCCFF
   AAAAEE 8899EE 7777DD 5566CC 3355BB 2233BB 0022AA 2244AA 3366BB 5588CC 7799CC
   88BBDD AADDDD CCFFEE BBFFCC AAFFAA 99EE88 77EE66 66EE44 55EE22 44EE00 66EE11
   77EE11 99EE22 AAEE22 CCEE33 DDEE33 FFFF44/],
  glyphs     => [qw/xyplot whisker_plot graded_segments heat_map wiggle_density wiggle_xyplot/],
  height     => [5..20],
  scale      => [0..1],
  #etc...
}


# set initial options -- can be reset later
sub initialize {
  my $self = shift;
  my %options = OPTIONS;
  for my $option (keys %options) {
    $self->{$option} = $options{$option};
  }
}

1;
