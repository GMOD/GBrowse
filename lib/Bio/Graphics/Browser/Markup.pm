package Bio::Graphics::Browser::Markup;

use strict;
use Carp 'croak';
use Bio::Graphics::Panel;

=head1 NAME

Bio::Graphics::Browser::Markup - Markup routines for sequences in text form

=head1 VERSION (CVS-info)

 $RCSfile: Markup.pm,v $
 $Revision: 1.3.14.1 $
 $Author: lstein $
 $Date: 2007-10-17 01:48:21 $

=head1 SYNOPSIS

 use Bio::Graphics::Browser::Markup;

 my $string = join '','a'..'z','a'..'z','a'..'z';
 my $markup = Bio::Graphics::Browser::Markup->new;

 $markup->add_style(cds=>'UPPERCASE');
 $markup->add_style(exon     =>'Text-decoration: underline');
 $markup->add_style(variation=>'Font-weight: bold');
 $markup->add_style(italic=>'Font-style: oblique');
 $markup->add_style(yellow=>'BGCOLOR blue');
 $markup->add_style(green=>'BGCOLOR red');
 $markup->add_style(orange=>'BGCOLOR orange');
 $markup->add_style(mango=>'FGCOLOR red');
 $markup->add_style(br=>'<br>');
 $markup->markup(\$string,[
			  ['cds',1=>10],
			  ['cds',12=>15],
			  ['variation',20=>41],
			  ['exon',0=>29],
			  ['exon',32=>40], 
			  ['italic',18=>29],
			  ['yellow',5=>40],
			  ['green',20=>50],
			  ['orange',30=>60],
			  ['mango',0=>36],
			  ['br',10=>10],
			  ['br',20=>20],
			  ['br',30=>30],
			  ['br',40=>40],
			  ['br',50=>50],
			  ['br',60=>60],
			  ]);
 print $string,"\n";

=head1 DESCRIPTION

This module marks up a string with HTML cascading stylesheet styles in
such a way that intersecting regions contain the union of the two
intersecting styles.  It also handles colors in such a way that
intersecting colors are added up.

=head1 METHODS


=head2 $annotator = Bio::Graphics::Browser::Markup->new

Create a new Markup object.

=cut

my $SYNTHETIC_SYMBOL = "CLR00000000000";

sub new {
  my $class = shift;
  my $self  = {
	       colors  => {},
	       seq     => 0,
	       symbols => {},
	      };
  return bless $self,ref($class) || $class;
}


=head2 $old_style = $annotator->add_style($symbolic_name=>$style)

Add an annotation style.

$symbolic name is a unique identifier to be used for ornamenting the
string.

$style is one of:

   - a CSS/2 stylesheet entry of form "style: value"
   - the word   "UPPERCASE"         (make uppercase)
   - the word   "LOWERCASE"         (make lowercase)
   - the phrase "FGCOLOR #RRGGBB"   (foreground color)
   - the phrase "FGCOLOR color-name"
   - the phrase "BGCOLOR #RRGGBB"   (background color)
   - the phrase "BGCOLOR color-name"
   - an HTML tag, indicated by a leading "E<lt>" character
   - anything else, will be inserted blindly

When calculating intersected regions, styles will be aggregated, upper
and lowercasing will be performed directly on the data, colors will be
additive, and HTML will be inserted blindly.

An invalid color name will cause this module to die.  Valid color
names can be obtained this way:

 perl -MBio::Graphics::Panel \
      -e 'print join "\n",sort Bio::Graphics::Panel->color_names'

=cut

sub add_style {
  my $self = shift;
  my ($symbolic_name,$style) = @_;

  my $entry;

  if ($style =~ /^(UPPER|LOWER)CASE$/) {  # upper/lower case
    $entry = [uclc => $1];
  }

  elsif ($style =~ /^(FG|BG)COLOR\s+\#([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])/){ # a hex color
    $entry = [lc($1).'color' => [hex $2, hex $3, hex $4]];
  }

  elsif ($style =~ /^(FG|BG)COLOR\s+(\w+)/) {  # a symbolic color
    my $rgb = Bio::Graphics::Panel->color_name_to_rgb($2) or croak "invalid color name";
    $entry = [lc($1).'color' => $rgb];
  }

  elsif ($style =~ /^[\w-]+:.+/) {  # css entry
    $entry = [style => $style ];
  }

  elsif ($style =~ /^<.+>$/) { # html
    $entry = [html  => $style];
  }

  else {  # something else, just insert it blindly
    $entry = [literal => $style];
  }

  $self->{symbols}{$symbolic_name} = $entry;
}


=head2 $style = $annotator->style($symbolic_name)

Get the style corresponding to symbolic name, or undef if the name is
unrecognized.

=cut

sub style {
  my $self     = shift;
  my $symbolic = shift;
  return $self->{symbols}{$symbolic}[1];
}

=head2 $style = $annotator->get_style($symbolic_name)

Get a list of CSS/2 styles corresponding to symbolic name.  Will die
if the name is not recognized or does not correspond to an entry of
type "style".

=cut

sub get_style {
  my $self     = shift;
  my $symbolic = shift;
  croak "invalid style" unless $self->{symbols}{$symbolic}[0] eq 'style';
  return split /[:;]\s*/,$self->{symbols}{$symbolic}[1];
}



=head2 $flag = $annotator->valid_symbol($symbolic_name)

Return true if the symbolic name is valid.

=cut

sub valid_symbol {
  my $self     = shift;
  my $symbolic = shift;
  return exists $self->{symbols}{$symbolic};
}


=head2 $result = $annotator->markup(\$sequence,\@annotated_regions)

Mark up the string referenced by $sequence, according to the regions
contained in $annotated_regions.

$sequence is a scalar ref, which will be modified in place (make a
copy of it if you need to).  $annotated_regions is a arrayref to the
following list:

  ([symbolic_name,start,end], [symbolic_name,start,end], ....)

The result indicates whether the markup was successful.

IMPORTANT: Regions are numbered using space-oriented coordinates,
which means that start=0 means to insert in front of the first base
pair, and an end equal to the sequence length will insert after the
last base pair:

  0 1 2 3 4 5 6 7     perl string coordinates
  1 2 3 4 5 6 7 8     sequence coordinates
  g a t c g a t c     sequence
 0 1 2 3 4 5 6 7 8    space coordinates

 To select first base:                    start=0, end=1
 To insert markup between bases 1 and 2:  start=1, end=1
 To select last base:                     start=7, end=8
 To select entire sequence:               start=0, end=8

This means that some munging of the sequence annotation must be
performed, but it keeps the notation unambiguous.

=cut

sub markup {
  my $self    = shift;
  my ($sequence,$regions) = @_;

  $self->{seq} = 0;  # package global

  # classify regions by type
  my %regions;
  foreach (@$regions) {
    my $type = $self->{symbols}{$_->[0]}[0] or croak "Unknown region type: $_->[0]";
    push @{$regions{$type}},$_;
  }

  # pull out the regions that ask for upper/lower case and
  # give them the special treatment
  foreach (@{$regions{uclc}}) {
    my ($style,$start,$end) = @$_;
    $self->{symbols}{$style}[1] eq 'UPPER' ? substr($$sequence,$start,$end-$start) =~ tr/a-z/A-Z/
                                            : substr($$sequence,$start,$end-$start) =~ tr/A-Z/a-z/;
  }

  my @style_regions;

  # meld the "color" regions into a set of additive regions
  push @style_regions,$self->_add_colors('Color',$regions{fgcolor})            if $regions{fgcolor};
  push @style_regions,$self->_add_colors('Background-color',$regions{bgcolor}) if $regions{bgcolor};

  # add the "style" regions
  push @style_regions,@{$regions{style}} if $regions{style};

  my @tags = $self->_unify(\@style_regions);

  # add HTML markup
  push @tags,$self->_linearize_html($regions{html});

  # add literals
  push @tags,map { [$self->{symbols}{$_->[0]}[1],$_->[1],$self->{seq}++] } @{$regions{literal}} 
    if $regions{literal};

  # insert the tags in their proper place
  $self->_add_markup($sequence,\@tags);

  1;
}

=head2 Internal Methods (not for external use; documentation incomplete)

=over 4

=item @events = $annotator->_add_colors($style_tag,$regions)

=back

=cut

# calculate the intersection of the regions with additive colors
sub _add_colors {
  my $self    = shift;
  my ($style_tag,$regions) = @_;

  # convert regions into events
  my $events  = $self->_regions_to_events($regions);

  # insert new color events whenever we see two or more start events in a row
  my @events;
  my $current_color = [0,0,0];
  my $current_position;

  for my $e (@$events) {
    my ($event,$symbol,$position) = @$e;
    my $rgb   = $self->{symbols}{$symbol}[1] or croak "unknown color style";
    my $cc = join '',@$current_color;

    if ($event eq 'start') {
      push @events,[$self->_color_symbol($style_tag,$current_color),$current_position,$position]
	if defined $current_position && $cc != 0;
      $current_color    = $self->_add_color($current_color,$rgb);
    }

    else { # event eq 'end'
      push @events,[$self->_color_symbol($style_tag,$current_color),$current_position,$position]
	if defined $current_position && $cc != 0;
      $current_color = $self->_subtract_color($current_color,$rgb);
    }
    $current_position = $position;
  }
  return @events;
}

=over 4

=item $style_symbol = $annotator->_add_colors($style_tag,$regions)

=back

=cut

sub _color_symbol {
  my $self = shift;
  my ($style_tag,$color) = @_;
  my $html_color = $self->_to_html_color($color);
  if (!$self->{colors}{$style_tag,$html_color}) {
    my $synthetic =  $self->{colors}{$style_tag,$html_color} = $SYNTHETIC_SYMBOL++;
    $self->add_style($synthetic,"$style_tag: $html_color");
  }
  $self->{colors}{$style_tag,$html_color}
}

=over 4

=item $color = $annotator->_add_color($color1,$color2)

=back

=cut

sub _add_color {
  my $self = shift;
  my ($a_color,$b_color) = @_;
  my @result;
  for (0..2) {
    my $result = $a_color->[$_] + $b_color->[$_];
    push @result,$result;
  }
  \@result;
}


=over 4

=item $color = $annotator->_subtract_color($color1,$color2)

=back

=cut

sub _subtract_color {
  my $self = shift;
  my ($a_color,$b_color) = @_;
  my @result;
  for (0..2) {
    my $result = $a_color->[$_] - $b_color->[$_];
    push @result,$result;
  }
  \@result;
}

=over 4

=item $html_color = $annotator->_to_html_color($color)

=back

=cut

sub _to_html_color {
  my $self = shift;
  my $rgb  = shift;
  my @hex  = map {sprintf("%02X",$_ % 256)} @$rgb;
  return '#'.join '',@hex;
}

=over 4

=item @tag_positions = $annotator->_unify($region_definitions)

=back

=cut

sub _unify {
  my $self    = shift;
  my $regions = shift;

  # convert regions into events
  my $events = $self->_regions_to_events($regions);

  my @result;
  my %current_symbols;
  my $open = 0;

  for my $e (@$events) {
    my ($event,$symbol,$position,$seq) = @$e;

    if ($event eq 'start') {
      $current_symbols{$symbol}++;

      if ($open++) {
	if ($result[-1][1] < $position) { # this test inhibits empty <span></span> sections
	  push @result,[qq(</span>),$position,$self->{seq}++];
	} else {
	  pop @result; # suppress empty tag sections
	}
      }

      my $style = $self->_to_style(\%current_symbols);
      push @result,[qq(<span style="$style">),$position,$self->{seq}++];
    }

    elsif ($event eq 'end') {
      $current_symbols{$symbol}--;

      if ($open--) { # this test inhibits empty <span></span> sections
	if ($result[-1][1] < $position) {
	  push @result,[qq(</span>),$position,$self->{seq}++];
	} else {
	  pop @result; # suppress empty tag sections
	}
      }
      next unless $open;

      my $style = $self->_to_style(\%current_symbols);
      push @result,[qq(<span style="$style">),$position,$self->{seq}++];
    }
  }
  die "programmer error: open tags != close tags" if $open != 0;
  return @result;
}

=over 4

=item $style_fragment = $annotator->_to_style($symbols)

=back

=cut

sub _to_style {
  my $self = shift;
  my $symbols = shift;
  my @active  = sort grep {$symbols->{$_}>0} keys %$symbols;
  my $symbol_key = join '-',@active;
  return $self->{_style_cache}{$symbol_key} 
    if exists $self->{_style_cache}{$symbol_key};

  my %attributes;
  foreach (@active) {
    next unless $symbols->{$_}>0;
    my %a = $self->get_style($_);
    %attributes = (%attributes,%a);
  }
  my @style;
  foreach (keys %attributes) {
    push @style,"$_: $attributes{$_}";
  }
  my $style = join '; ',@style;

  return $self->{_style_cache}{$symbol_key} = $style;
}

=over 4

=item @tag_positions = $annotator->_linearize_html($region_definitions)

=back

=cut

sub _linearize_html {
  my $self    = shift;
  my $regions = shift;
  my $events = $self->_regions_to_events($regions);
  my @result;
  my ($last_symbol,$last_position);
  foreach (@$events) {
    my ($event,$symbol,$pos,$seq) = @$_;
    if ($event eq 'end' 
	&& defined($last_symbol)
	&& $symbol eq $last_symbol 
	&& $pos    == $last_position) {
      my $tag = $self->{symbols}{$symbol}[1];
      $tag =~ s!>$! />!;
      push @result,[$tag,$pos,$self->{seq}++];
      undef $last_symbol;
      next;
    }

    if (defined $last_symbol) {
      my $tag = $self->{symbols}{$last_symbol}[1];
      push @result,[$tag,$pos,$self->{seq}++];
    }

    if ($event eq 'start') {
      $last_symbol   = $symbol;
      $last_position = $pos;
    }
    else {
      my $tag = $self->{symbols}{$last_symbol}[1];
      $tag =~ s!^<(\w+).*>$!</$1>!;
      push @result,[$tag,$pos,-$self->{seq}++];
      undef $last_symbol;
    }
  }
  if (defined $last_symbol) {
    my $tag = $self->{symbols}{$last_symbol}[1];
    push @result,[$tag,$last_position,$self->{seq}++];
  }

  @result;
}

=over 4

=item \@events = $annotator->_regions_to_events($regions)

turn a series of regions into a series of start and end events
because of the problem of events that start/stop in the same place
each event also gets a sequence that can be used to keep events
matched in a nested way

=back

=cut

sub _regions_to_events {
  my $self    = shift;
  my $regions = shift;
  my @events;
  foreach (@$regions) {
    $self->{seq}++;
    my ($symbol,$start,$end) = @$_;
    push @events,[start => $symbol,$start,$self->{seq}];
    push @events,[end   => $symbol,$end, $start == $end ? ++$self->{seq} : -$self->{seq}];
  }
  # now sort events according to their position, using the
  # sequence to resolve ties.  Notice the use of -$seq so
  # that the sorting order of end ties is reversed relative
  # to start ties.  This causes regions to nest properly.
  my @sorted_events = sort {$a->[2]<=>$b->[2] || $a->[3]<=>$b->[3]} @events;
  \@sorted_events;
}

=over 4

=item $annotator->_add_markup($string_to_modify,$tag_positions)

=back

=cut

sub _add_markup {
  my $self   = shift;
  my $string = shift;
  my $markups = shift;
  for my $m (sort {$b->[1]<=>$a->[1] || $b->[2]<=>$a->[2]} @$markups) {
    my ($thing,$position) = @$m;
    next if $position > length($$string);
    substr($$string,$position,0) = $thing;

  }
}


=head1 SEE ALSO

L<Bio::Graphics::Panel>,
L<Bio::Graphics::Glyph>,
L<Bio::Graphics::Feature>,
L<Bio::Graphics::FeatureFile>,
L<Bio::Graphics::Browser>,
L<Bio::Graphics::Browser::Plugin>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2002 Cold Spring Harbor Laboratory

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

1;

__END__
