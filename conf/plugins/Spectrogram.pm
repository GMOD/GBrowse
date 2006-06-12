# $Id: Spectrogram.pm,v 1.1 2006-06-12 14:04:09 sheldon_mckay Exp $
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
intensive and will increase latency when the spectromgram
track is turned on in gbrowse.

The graphical rendering of the spectrogram depends on the
glyph module Bio::Graphics::Glyph::spectrogram.  

=head1 FEEDBACK

See the GMOD website for information on bug submission http://www.gmod.org.

=head1 AUTHOR - Sheldon McKay

Email E<lt>mckays@cshl.eduE<gt>

=cut

package Bio::Graphics::Browser::Plugin::Spectrogram;
use strict;
use Bio::Graphics::Browser::Plugin;
use CGI ':standard';
use CGI::Carp 'fatalsToBrowser';
use GD;
use Math::FFT;
use Statistics::Descriptive;
use List::Util qw/shuffle max/;

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
  p("The plugin was written by Sheldon McKay");
}

sub config_defaults {
  { win => 1024,
    inc => 512,
    binsize => 1,
    y_unit  => 1,
    quantile => 99.99 }
}

sub reconfigure {
  my $self = shift;
  my $conf = $self->configuration;
  $conf->{win}  = $self->config_param('win');
  $conf->{inc}  = $self->config_param('inc');
  $conf->{min}  = $self->config_param('min');
  $conf->{max}  = $self->config_param('max');
  $conf->{type} = $self->config_param('measure');
  $conf->{remove_DC} = $self->config_param('remove_DC');
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
    print h2(font( {color => 'red'}, 
		   "Spectrogram.pm error: window size must be greater than the overlap" ) );
    return;
  }

  # extend the segment a bit so we can slide the window
  # all the way to the end of the sequence
  my $db = $segment->factory;
  $segment = $db->segment( $segment->ref, $segment->start, ($segment->end + $win) );
  my $seq     = lc eval{$segment->seq} or die "No sequence found for $segment $@";  
  my $offset  = $segment->start;
  my $end     = $segment->length;
 
  die "Window size $win can not exceed the sequence length $end\n"
      if $win && $win > $end;
  
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

  my $key = "DNA spectrogram: window size  $win; overlap $inc";
  if ($conf->{min}) {
    $key .= "; $conf->{type} range $conf->{min}-$conf->{max}";
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

    # Digitize the DNA and calculate the DFT
    my ($g,$a,$t,$c) = make_numeric($sub_seq);
    dft(\$_) for ($g,$a,$t,$c);

    # get rid of DC component
    if ($conf->{remove_DC} ) {
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
  # percentile to avoid saturation 
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

sub configure_form {
  my $self = shift;
  my $conf = $self->configuration;
  my $msg = <<END;
Window size = the number of bases in the sliding window used
to calculate the spectrogram.\\n
Increment = the overlap between windows.\\n
END
;
  my $form = p() .p( 'Window size: ', 
		     popup_menu( -name  => $self->config_name('win'),
				 -values => [128,256,512,1024,2048,4096,8192],
				 -default => $conf->{win} ),
		     'Increment: ',
		     textfield( -name  => $self->config_name('inc'),
				-value => $conf->{inc},
				-size  => 4 ) . _js_help($msg) );
  
  $msg = <<END;
Selecting these options will restrict the frequency or
period range of the spectrogram to reduce the required
space and computation time.\\n
period = size (bp) of structure or repeat unit
-- calculated as 2*(window size)/frequency.\\n
frequency = integer between 0 and window size.
END
;
              
  $form .=   p( 'Restrict ',
		popup_menu( -name   => $self->config_name('measure'),
			    -values => [qw/period frequency/],
			    -defaults => [$conf->{measure}] ),
		' to between ',
		textfield( -name  => $self->config_name('min'),
			   -value => $conf->{min},
                           -size  => 4 ),
		' and ',
                textfield( -name  => $self->config_name('max'),
			   -value => $conf->{max},
                           -size  => 4 ) . ' ' . _js_help($msg) );

  $msg = <<END;
Lowering the saturation value will reduce the dominance of very bright
spots on the spectrogramn by setting an arbitrary maximum value
(expressed as a percentile rank).  Setting a lower saturation will
reduce the effects of stronge signals elsewhere in the spectrogram
and help to emphasize less intense features.
END
;

  $form .=   p( 'Saturate color intensity at the ',
                textfield( -name   => $self->config_name('quantile'),
                           -value  => $conf->{quantile},
                           -size   => 5 ),
		'th percentile ' . _js_help($msg) );


  $msg = <<END;
The "DC component", in this case, is a very strong strong signal
at frequency 0 (the very top of the spectrogram), with some bleed
over to frequency 1.  Removing the DC component noise makes
fainter spots more visible by decreasing the overall range.  
The brightness of the spectrogam can be manipulated using this 
option together with the saturation value.

END
;

  $form .=    p( checkbox( -name => $self->config_name('remove_DC'),
			   -checked => 'checked',
			   -label => 'Remove DC component' ),
		 ' ' . _js_help($msg) );


  $msg = <<END;
This value controls the height of each frequency bin (default 1 px)
END
;

  $form .=     p( 'Row height ',
		  textfield( -name => $self->config_name('y_unit'),
			     -value => $conf->{y_unit},
			     -size  => 2 ),
			     ' pixels ' . _js_help($msg) );
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


sub remote {
  my $self = shift;
  my ($id,$seq,$url,@bases) = @_;
  unless ($url =~ /^http/i) {
    $url = "http://$url";
  }
  my $ua       = LWP::UserAgent->new;
  my $request  = HTTP::Request->new('POST', $url);
  $request->content( "seq_name=$id;seq=$seq;G=$bases[0];A=$bases[1];T=$bases[2];G=$bases[3];" );
  my $response = $ua->request( $request );
  my $output   = $response->content;

  die $self->error("Some sort of HTTP error")
      unless $ua && $request && $response && $output;

  return $output;

}

sub dft {
  my $array = shift;
  my $fft   = Math::FFT->new($$array);
  my $dft = $fft->rdft;
  $$array = magnitude(@$dft);
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

