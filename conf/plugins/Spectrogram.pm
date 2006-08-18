# $Id: Spectrogram.pm,v 1.3 2006-08-18 02:31:37 sheldon_mckay Exp $
# bioperl module for Bio::Graphics::Browser::Plugin::Spectrogram
# cared for by Sheldon McKay mckays@cshl.edu
# Copyright (c) 2006 Cold Spring Harbor Laboratory.

=head1 NAME

Bio::Graphics::Browser::Plugin::Spectrogram

=head1 SYNOPSIS

This module is not used directly.  It is an 'annotator'
plugin for gbrowse.

=head1 DESCRIPTION

The Spectrogram plugin builds up a spectrogram for
digitized DNA sequence using the short-time fourier
transform (STFT) method, adapted from the digital signal
processing world.  A sliding window of variable size and overlap
is used to calculate each "column" of the spectrogram, where the column
width is equal to the step, or overlap between windows.

For each window, we: 

1) digitize the DNA by creating four binary indicator
sequences:

    G A T C C T C T G A T T C C A A
  G 1 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0
  A 0 1 0 0 0 0 0 0 0 1 0 0 0 0 1 1
  T 0 0 1 0 0 1 0 1 0 0 1 1 0 0 0 0
  C 0 0 0 1 1 0 1 0 0 0 0 0 1 1 0 0

2) take the discrete fourier transform (DFT) for each of the 
four indicator sequences and square the values to get 
the magnitude.  

3) create a Bio::Graphics::Feature object that contains
the spectrogram data as attributes.  The features are passed
back to gbrowse as parts of a Bio::Graphics::Featurefile object.

The calculations for the real DFT are handled by
the xs module Math::FFT.  The actual algorithm
used is the fast fourier transfrom (FFT), which is much
faster than the original DFT algorithm but is limited in that
only base2 numbers (128, 256, 512, etc) can be used for window
sizes.  This is necessary to make the spectrogram calculation
fast enough for real-time use.  It should be noted, however,
that calculating spectrograms dynamically is computationally 
intensive and will increase latency when the spectrogram
track is turned on in gbrowse.

The graphical rendering of the spectrogram depends on the
glyph module Bio::Graphics::Glyph::spectrogram.  

=head1 FEEDBACK

See the GMOD website for information on bug submission http://www.gmod.org.

=head1 AUTHOR - Sheldon McKay

Email E<lt>mckays@cshl.eduE<gt>

=cut
;

package Bio::Graphics::Browser::Plugin::Spectrogram;

use lib '/home/smckay/lib';

use strict;
use Bio::Graphics::Browser::Plugin;
use CGI ':standard';
use CGI::Carp 'fatalsToBrowser';
use GD;
use Math::FFT;
use Statistics::Descriptive;
use List::Util qw/shuffle max/;

use Data::Dumper;

use vars '$VERSION','@ISA';
$VERSION = '0.01';

@ISA = qw/ Bio::Graphics::Browser::Plugin /;

sub name { 
  'DNA spectrogram';
}

sub type {
  'annotator';
}

sub verb {
 'Draw';
}

sub mime_type {
  'text/html';
}

sub description {
  p("This plugin calculates a spectrogram from digitized DNA sequences",
    " using Discrete Fourier Transforms") . 
  p("The plugin was written by Sheldon McKay <mckays\@cshl.edu>");
}

sub config_defaults {
  { win       => 512,
    inc       => 256,
    binsize   => 1,
    y_unit    => 1,
    quantile  => 99.99, 
    filter_01 => 1,
    min       => 2,
    max       => 4,
    type      => 'period'}
}

sub reconfigure {
  my $self = shift;
  my $conf = $self->configuration;
  $conf->{win}  = $self->config_param('win');
  $conf->{inc}  = $self->config_param('inc');
  $conf->{min}  = $self->config_param('min') || 0;
  $conf->{max}  = $self->config_param('max') || $conf->{win} - 1;
  $conf->{type} = $self->config_param('measure');
  $conf->{filter_01} = $self->config_param('filter_01');
  $conf->{quantile}  = $self->config_param('quantile') || 99.99;
  $conf->{y_unit}    = $self->config_param('y_unit')   || 1;
  $self->configuration($conf);
}

sub annotate {
  my $self    = shift;
  my $segment = shift or die "No segment";
  my $conf    = $self->configuration;

  my $win     = $conf->{win};
  my $inc     = $conf->{inc};
  my $ltype   = $conf->{ltype};

  # sanity check for window size
  if ($inc >= $win) {
    complain("Spectrogram.pm error: window size must be greater than the overlap");
    return;
  }
  
  # and for maximum period or frequency
  if ($conf->{max} && $conf->{max} > $win) {
    
    complain("maximum $conf->{type} can not exceed ".
	     " the window size: resetting to $win.");
    $conf->{max} = $win;
  }

  # extend the segment a bit so we can slide the window
  # all the way to the end of the sequence
  my $db = $segment->factory;
  ($segment) = $db->segment( $segment->ref, $segment->start, ($segment->end + $win) );

  # API-change alert!
  my $seq_obj = $segment->seq;
  my $seq;
  if ($seq_obj && ref $seq_obj) {
    $seq = lc eval{$seq_obj->seq};
  }
  elsif ($seq_obj) {
    $seq = lc $seq_obj;
  }

  $seq ||  die "No sequence found for $segment $@";

  my $offset  = $segment->start;
  my $end     = $segment->length;
 
  my (@g,@a,@t,@c,@offsets,@meta_array,@coords);

  my ($min_f,$max_f);
  if ( $conf->{min} || $conf->{max} ) {
    my $max  = $conf->{max} || $win;
    my $min  = $conf->{min} || 0;
    my $type = $conf->{type}; 

    if ($type eq 'period') {
      $min_f = int(2*$win/($max)) - 1;
      $max_f = $min ? int(2*$win/($min)) - 1 : $win-1;
    }
    else {
 
     unless (int $min == $min) {
       complain("minumum frequency value should be an integer between",
		"0 and ".($win-2));
       return;
     }
     unless (int $max == $max) {
       complain("minumum frequency value should be an integer between",
		"1 and ".($win-1));
       return;
     }

      $min_f = $min;
      $max_f = $max || $win-1;
    }
  }
  else {
    $min_f = 0;
    $max_f = $win-1;
  }

  $min_f-- unless $min_f == 0;
  $max_f++ unless $max_f == $win;

  my $key = join('; ',"window size $win", "overlap $inc", 
		 "saturation $conf->{quantile}th percentile");
  if ($conf->{min}) {
    $key .= "; $conf->{type} range $conf->{min}-$conf->{max}";
  }
  if ($conf->{filter_01}) {
    $key .="; 0-1 Hz filter ON";
  }

  my $feature_list = $self->new_feature_list;
  my $link = sub { shift->url || 0 };
  $feature_list->add_type( spectrogram => { glyph  => 'spectrogram',
					    bump   => 0,
					    height => $conf->{y_unit} * ($max_f - $min_f + 1),
					    key    => $key,
					    win    => $win,
					    link   => $link } );

  my $start = 0;
  until ( $start > ( $end - $win ) ) {
    my $sub_seq = substr $seq, $start, $win;

    # Digitize the DNA
    my ($g,$a,$t,$c) = make_numeric($sub_seq);

    # take the magnitude of the DFT
    dft(\$_) for ($g,$a,$t,$c);

    # get rid of DC component
    if ($conf->{filter_01} ) {
      for ($g,$a,$t,$c) {
	$_->[0] = 0;
	$_->[1] = 0;
      }
    }
    
    push @g, [@{$g}[$min_f..$max_f]];
    push @a, [@{$a}[$min_f..$max_f]];
    push @t, [@{$t}[$min_f..$max_f]];
    push @c, [@{$c}[$min_f..$max_f]];
    push @coords, [$start + $offset + 1, $start + $offset + $inc];

    $start += $inc;
  }

  # max out the intensity range at the nth
  # percentile to avoid saturation of color intensity 
  my $stat = Statistics::Descriptive::Full->new;
  $stat->add_data(map {@$_} @g,@a,@t,@c);
  my $max = $stat->percentile($conf->{quantile});
  my @labels = $min_f .. $max_f;
  @labels = map {$_ ? 2*$win/$_ : $win} @labels if $conf->{type} eq 'period';
  my $first = 1;
  for my $coords (@coords) {
    my ($start, $end) = @$coords;
    
    # make a link for zooming in
    my $url = url;
    my $pad = int $segment->length/20;
    my $z_start = $start - $pad;
    my $z_stop  = $end   + $pad;
    my $name = $segment->ref .":$z_start..$z_stop";
    $url .= "?name=$name";

    my $G = shift @g;
    my $A = shift @a;
    my $T = shift @t;
    my $C = shift @c;

    my $atts = { g   => $G,
		 a   => $A,
		 t   => $T,
		 c   => $C,
		 max => $max };
    
    # y-axis labels for first column
    if ($first) {
      $atts->{labels} = [$conf->{type},@labels];
      $first = 0;
    }
    
    $atts->{g} = $G;
    
    my $sf = Bio::Graphics::Feature->new( -type   => 'spectrogram',
					  -source => 'calculated',
					  -start  => $start,
					  -end    => $end,
					  -ref    => $segment->ref,
					  -url    => $url,
					  -attributes    => $atts );
    
    $feature_list->add_feature($sf);
    
  }
  
  return $feature_list;
}

sub complain {
  my @msg = @_;
  print h3(font( {color => 'red'}, 'Spectrogram.pm error: ', @msg) );
}

sub configure_form {
  my $self = shift;
  my $conf = $self->configuration;
  my $banner = $self->browser_config->header || '';;

  my $msg = <<END;
Window size and overlap = the width and overlap of sliding window used
to calculate the spectrogram.\\n
Note: larger window sizes and/or smaller overlaps increase
computation time.\\n
END
;
  my $form = h3({-class => 'searchtitle'}, 'Spectrogram size ', _js_help($msg)) . 
      p( 'Sliding window size: ', 
	 popup_menu( -name  => $self->config_name('win'),
		     -values => [8,16,32,64,128,256,512,1024,2048,4096,8192],
		     -default => $conf->{win} ),
	 ' bp' . br. br . 'Window overlap: ',
	 textfield( -name  => $self->config_name('inc'),
		    -value => $conf->{inc},
		    -size  => 4 ),
	 'bp');
  
  $msg = <<END;
Restricting the range of periods or frequencies displayed will
reduce the vertical height of the image and speed up image
loading.\\n
period = size (bp) of structure or repeat unit,
calculated as 2*(window size)/frequency.\\n
frequency = integer between 0 and (window size - 1).\\n
Row height = the height of each frequency row in the
spectrogram (minimum 1 pixel)
END
;

  $form .= br .  h3({-class => 'searchtitle'}, 'Display options ', _js_help($msg)) .
      p( 'Restrict ',
	 popup_menu( -name   => $self->config_name('measure'),
		     -values => [qw/period frequency/],
		     -default => $conf->{type} ),
	 ' to between ',
	 textfield( -name  => $self->config_name('min'),
		    -value => $conf->{min},
		    -size  => 4 ),
	 ' and ',
	 textfield( -name  => $self->config_name('max'),
		    -value => $conf->{max},
		    -size  => 4 ),
	 br . br . 'Row height',
         textfield( -name => $self->config_name('y_unit'),
                    -value => $conf->{y_unit},
                    -size  => 2 ),
         ' px ' );	 

  $msg = <<END;
Lowering the saturation value will reduce the dominance of very bright
colors on the spectrogramn by setting an arbitrary maximum value
(expressed as a percentile rank).  Setting a lower saturation will
reduce the effects of very high amplitude signals elsewhere in 
the spectrogram and help to emphasize less intense features.\\n
The higher the saturation value is set, the darker the "background"
of the spectrogram.
END
;

  $form .=  br . h3({-class => 'searchtitle'}, 'Image brightness') .
    p( 'Saturate color intensity at the ',
       textfield( -name   => $self->config_name('quantile'),
		  -value  => $conf->{quantile},
		  -size   => 5 ),
       'th percentile ' . _js_help($msg) );


  $msg = <<END;
There is a very large amplitude signal at frequency 0 Hz
(the very top of the spectrogram), with some bleed over to 1 Hz.
Filtering out these frequencies will help make the fainter
spots more visible by decreasing the overall range of signal
magnitudes.\\n
The brightness of the spectrogram can be manipulated using this 
option together with the saturation value.

END
;

  my @checked = (checked => 'checked') if $conf->{filter_01};
   $form .=    p( checkbox( -name => $self->config_name('filter_01'),
			   @checked,
			   -label => 'Filter out 0-1 Hz' ),
		 ' ' . _js_help($msg) );

  $form .= hidden( -name => 'configured', -value => 1 );
  return $banner.$form;

}

sub make_numeric {
  my $seq = lc shift;
  my @seq = split q{}, $seq;

  my @G = map { $_ eq 'g' ? 1 : 0 } @seq;
  my @A = map { $_ eq 'a' ? 1 : 0 } @seq;
  my @T = map { $_ eq 't' ? 1 : 0 } @seq;
  my @C = map { $_ eq 'c' ? 1 : 0 } @seq;

  return (\@G,\@A,\@T,\@C);
}

sub dft {
#  my $self = shift;
#  my $conf = $self->configuration;
#  my $remove_DC = $conf->{remove_DC};
  my $array = shift;
  my $fft   = Math::FFT->new($$array);

  # this is a call to the 'real' DFT (no imaginary numbers)
  # algorithm, which is actually implented via the FFT 
  # algorithm
  my $dft = $fft->rdft;
#  print pre(@{$dft}[0..5]);
 # my $s = Statistics::Descriptive::Full->new;
 # $s->add_data(@$dft);
 # my $mean = $s->mean;
 # @$dft = map {$_ - $mean} @$dft;
#  print pre(@{$dft}[0..5]);
  $dft = magnitude(@$dft);
  $$array = $dft;
}

sub magnitude {
  $_ = $_**2 for @_;
  return \@_;
}

sub _js_help {
  my $msg = _process_msg(shift);
  a( { -href    => 'javascript:void(0)',
         -title   => 'help',
       -onclick => "alert('$msg')" }, "[?]" );
}

sub _process_msg {
  my $msg = shift;
  $msg =~ s/\\n|\n\n/BREAK/gm;
  $msg =~ s/\n/ /gm;
  $msg =~ s/BREAK/\\n/g;
  $msg;
}

1;

