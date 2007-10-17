package Bio::Graphics::Browser::PadAlignment;

use strict;
use Bio::Graphics::Browser::Markup;
use constant DEBUG=>0;
use Data::Dumper;

=head1 NAME

Bio::Graphics::Browser::PadAlignment - Insert pads into a multiple alignment

=head1 VERSION (CVS-info)

 $RCSfile: PadAlignment.pm,v $
 $Revision: 1.20.6.3.2.1 $
 $Author: lstein $
 $Date: 2007-10-17 01:48:21 $

=head1 SYNOPSIS

 use Bio::Graphics::Browser::PadAlignment;

 my @dnas = (
	     dna1 =>'FFFFgatcGATCgatcGATCgatcGATCgatcGBATCgatcGATCatcGATCgatcGATCgatcGATCgatcGATgatcGATCgatcNNNNGATC',
	     dna2 =>'FFgatcGATCGATCgatcNNGATCgatcGATCgatcGATCgatcGATCgatcGATCtcGATBCgatcGATCatcGATCgatcNNNNGATCFFFF',
	     dna3 =>'FFFFgatcGATCgatcGATCgatcGATCgatcBBBGATCgatcGATCatcGATCBgatcGATCgatcGATCgatcGATgatcGATCgatcNNNNGATCFF',
	     dna4 =>'ZZFFFFgatcGATCgatcGATCgatcGATCgatc',
	     dna5 =>'ATBGGATtcttttttt',
	   );

 #                   target  st  en  tst ten
 my @alignments = ([ 'dna2', 4,  11,  2, 9      ],
 		   [ 'dna2', 16, 23,  10, 17    ],
		   [ 'dna2', 24, 32,  20, 28    ],
		   [ 'dna2', 34, 44,  29, 39    ],
		   [ 'dna2', 45, 59,  41, 55    ],
		   [ 'dna2', 62, 66,  56, 60    ],
		   [ 'dna2', 67, 74,  62, 69    ],
		   [ 'dna2', 76, 86,  71, 81    ],
		   [ 'dna2', 91, 94,  86, 89    ],

		   [ 'dna3',  4,  31, 4, 31    ],
		   [ 'dna3',  33, 33, 34, 34    ],
		   [ 'dna3',  34, 51, 36, 53    ],
		   [ 'dna3',  52, 86, 55, 89    ],
		   [ 'dna3',  91, 94, 94, 97    ],

		   [ 'dna4',  0,  31, 2,  33    ],

		   [ 'dna5',  17, 18, 0, 1    ],
		   [ 'dna5',  41, 43, 4,   6    ],
		   [ 'dna5',  85, 86, 7,   8    ],
		  );


 my $align = Bio::Graphics::Browser::PadAlignment->new(\@dnas,\@alignments);

 my @padded = $align->padded_sequences;
 print join "\n",@padded,"\n";
 # ..FFFFgatcGATCgatcGATCgatc--GATCgatcG-B-ATCgatcGATC-atcGATC-gatcGATCgatcGAT-CgatcGATgatcGATCgatcNNNNGATC....
 # ....FFgatcGATC----GATCgatcNNGATCgatcG---ATCgatcGATCgatcGATC-gatcGATC--tcGATBCgatcGATCatcGATCgatcNNNNGATCFFFF
 # ..FFFFgatcGATCgatcGATCgatc--GATCgatcBBBGATCgatcGATC-atcGATCBgatcGATCgatcGAT-CgatcGATgatcGATCgatcNNNNGATCFF..
 # ZZFFFFgatcGATCgatcGATCgatc--GATCgatc........................................................................
 # ...................AT-----------------BG-------GAT--------------------------------------------tcttttttt.....

 my $pretty = $align->alignment;
 print $pretty,"\n";
 # dna1   1 ..FFFFgatc GATCgatcGA TCgatc--GA TCgatcG-B- ATCgatcGAT C-atcGATC- gatcGATCga tcGAT-Cgat
 # dna2   1 ....FFgatc GATC----GA TCgatcNNGA TCgatcG--- ATCgatcGAT CgatcGATC- gatcGATC-- tcGATBCgat
 # dna3   1 ..FFFFgatc GATCgatcGA TCgatc--GA TCgatcBBBG ATCgatcGAT C-atcGATCB gatcGATCga tcGAT-Cgat
 # dna4   1 ZZFFFFgatc GATCgatcGA TCgatc--GA TCgatc.... .......... .......... .......... ..........
 # dna5   1 .......... .........A T--------- ---------- -----BGGAT ---------- ---------- ----------

 # dna1  72 cGATgatcGA TCgatcNNNN GATC....
 # dna2  67 cGATCatcGA TCgatcNNNN GATCFFFF
 # dna3  75 cGATgatcGA TCgatcNNNN GATCFF..
 # dna4  35 .......... .......... ........
 # dna5   8 ---------- ----tctttt ttt.....

=head1 DESCRIPTION

This is a utility module for pretty-printing the type of alignment
that comes out of gbrowse, namely a multiple alignment in which each
target is aligned to a reference genome without explicit pads or
other spaces.

For speed and ease of use, the module does not use form Bio::SeqI
objects, but raw strings and alignment data structures.  This may
change.

This module does B<not> perform multiple alignments!  It merely
pretty-prints them!

=head2 METHODS

This section describes the methods used by this class.

=over 4

=item $aligner = Bio::Graphics::Browser::PadAlignment->new(\@sequences,\@alignments)

Create a new aligner.  The two arguments are \@sequences, an array ref
to the list of sequences to be aligned, and \@alignments, an array ref
describing how the sequences are to be aligned.

\@sequences should have the following structure:

  [ name1 => $sequence1,
    name2 => $sequence2,
    name3 => $sequence3 ]

The sequences will be displayed in top to bottom order in the order
provided.  The first sequence in the list is special because it is the
reference sequence.  All alignments are relative to it.

\@alignments should have the following structure:

 [ [ target1, $start1, $end1, $tstart1, $tend1 ],
   [ target1, $start2, $end2, $tstart2, $tend2 ],
   ...
  ]

Each element of @alignments is an arrayref with five elements.  The
first element is the name of the target sequence, which must be one of
the named sequences given in @sequences.  The second and third
elements are the start and stop position of the aligned target segment
relative to the reference sequence, "name1" in the example given
above.  The fourth and fifth elements are the start and stop position
of the aligned target segment in the coordinate space of the target.

Example:

  @dnas = ('dna1' => 'ccccccaaaaaatttt',
	   'dna2' => 'aaaaaa');
  @alignment = ( ['dna2', 6, 11, 0, 5 ]);

Positions 0 to 5 of "dna2" align to positions 6-11 of "dna1".

Note that sequence positions are zero based.  This may change.

=item @lines = $aligner->padded_sequences

This inserts pads into the sequences and returns them as a list of
strings in the order specified in new().  In a scalar context, this
method will return a hashref in which the keys are the sequence names
and the values are their padded strings.

=item $map = $aligner->gap_map

This returns an arrayref indicating the position of each base in the
gapped reference sequence.  The indexes are base positions, and the
element values are their positions in the reference sequence as
returned by padded_sequences().

Note that the gap map only provides coordinate mapping for the
reference sequence.  For an alternative implementation that provides
gap maps for each of the targets (at the cost of speed and memory
efficiency) see the section after __END__ in the source file for this
module.

=item $align_string = $aligner->alignment(\%origins [,\%options])

This method returns a pretty-printed string of the aligned sequences.
You may provide a hashref of sequence origins in order to control the
numbers printed next to each line of the alignment.  The keys of the
%origins hashref are the names of the sequences, and the values are
the coordinate to be assigned to the first base of the sequence.  Use
a negative number if you wish to indicate that the sequence has been
reverse complemented (the negative number should indicate the
coordinate of the first base in the provided sequence).

An optional second argument, if present, contains a hash reference to
a set of option=>value pairs.  Three options are recognized:

   show_mismatches      0|1      if true, highlight mismatches in pink
   show_matches		0|1	 if true, hightligt matches in yellow
   color_code_proteins  0|1      if true, highlight amino acids thus:
                                        Acidic amino acids in red
                                        Basic amino acids in blue
                                        Hydrophobic amino acids in grey
                                        Polar amino acids in yellow
   flip                 0|1      if true, reverse complement the whole alignment

=back


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

# A specific package for padding multiple alignments into an ASCII text string.
# It is designed for cases in which all alignments are against
# a single reference sequence, such as ESTs against a genome.  The reference
# sequence must be the first one provided.

# for efficiency, we use zero-based coordinates throughout.

# IMPORTANT NOTE: see the section after __END__ for a slightly
# different implementation which keeps a separate gap map for each 
# sequence in the alignment

# define the types of amino acids -- this was done by an undergrad and is subject to change
# modified according to: http://www.ann.com.au/MedSci/amino.htm, method 1

my %aa_type = (
	       K=> "basic_aa",
	       R=> "basic_aa",
	       H=> "basic_aa",
	       S=> "polar_aa",
	       T=> "polar_aa",
	       N=> "polar_aa",
	       Q=> "polar_aa",
	       C=> "polar_aa",
	       Y=> "polar_aa",
	       D=> "acidic_aa",
	       E=> "acidic_aa",
	       G=> "npolar_aa",
	       A=> "npolar_aa",
	       V=> "npolar_aa",
	       L=> "npolar_aa",
	       I=> "npolar_aa",
	       P=> "npolar_aa",
	       M=> "npolar_aa",
	       F=> "npolar_aa",
	       C=> "npolar_aa",
	       W=> "npolar_aa",
	       X=> "special_aa",
	       "*" => "special_aa"
	      );

sub new {
  my $class = shift;
  my $dnas   = shift;  # array ref of DNAs in the order in which they will be printed
                       # in format [ [name1=>dna1],[name2=>dna2]...]
  my $aligns = shift;  # array ref of alignments in format [ [targetname,srcstart,srcend,targetstart,targetend] ]

  # remap data structures
  my $count = 0;
  my (@dnas,%dnas);
  while (my($name,$dna) = splice(@$dnas,0,2)) {
    $dnas{$name} = $count++;
    push @dnas,$dna;
  }
  return bless {
		names  => \%dnas,
		dnas   => \@dnas,
		aligns => $aligns
		};
}

# return a hashref in which the keys are the
# dna names and the values are the padded strings
sub padded_sequences {
  my $self = shift;
  my @lines;

  my @dnas = @{$self->{dnas}};

  # initialize top line with src sequences
  $lines[0] = $dnas[0];
  my $len = length($lines[0]); 
  for (my $i = 1; $i < @dnas; $i++) {
    $lines[$i]  = '-' x $len;
  }

  # running total of number of gaps, indexed by position on source
  my @gap_map = 0..length($dnas[0])-1;

  # place where DNA[$i] left off
  my @last_end;
  my @added = (length($dnas[0])-1);

  # leader sequence to add back after gapping
  my @leader = (0);

  # alignments must be sorted according to target
  foreach (sort {$a->[0] cmp $b->[0]
		   || $a->[1] <=> $b->[1]
		 } @{$self->{aligns}}) {
    my ($targ, $start, $end,
	$tstart,$tend) = @{$_};

    defined ($targ = $self->{names}{$targ}) or next;

    warn "$start $end $tstart $tend\n" if DEBUG;

    my $src = 0;   # first DNA is the reference

    # position in src coordinates where we last stopped
    my $last_src    = $last_end[$targ][$src]  ||= -1;

    # position in target coordinates where we last stopped
    my $last_target = $last_end[$targ][$targ] ||= -1;

    if ($last_src >= 0 && $last_target >= 0) {
      # This section adds the unaligned region between the last place that
      # we stopped and the current alignment
      my $gap       = 0;
      my $tpos      = $last_target+ 1;
      my $spos      = $gap_map[$last_src]+1;
      warn "last_src=$last_src, spos=$spos" if DEBUG;
      my $deficit   = ($tstart-$last_target) - ($gap_map[$start] - $gap_map[$last_src]);
      warn "add $deficit gaps" if DEBUG;
      if ($deficit > 0) {
	for (my $i=0; $i<@lines; $i++) {
	  eval {substr($lines[$i],$spos,0) = '-'x$deficit};
	}
	@gap_map[$start..$#gap_map] = map {$_+$deficit} @gap_map[$start..$#gap_map];
      }
      while ($tpos < $tstart) {
	eval { substr($lines[$targ],$spos++,1) = substr($dnas[$targ],$tpos++,1) };
      }
    }

    else {  # remember to add the extra stuff at beginning
      $leader[$src]  = $start  if !defined $leader[$src]  || $start < $leader[$src];
      $leader[$targ] = $tstart if !defined $leader[$targ] || $tstart< $leader[$targ];
    }

    # insert the aligned bit now
    for (my $pos = $start; $pos <= $end; $pos++) {
      my $gap_pos = $gap_map[$pos];
      defined $gap_pos or next;
      warn "inserting $gap_pos with ",substr($dnas[$targ],$tstart,1),"\n" if DEBUG;
      eval {substr($lines[$targ],$gap_pos,1) = substr($dnas[$targ],$tstart++,1) };
    }

    $last_end[$targ][$src]  = $end;
    $last_end[$targ][$targ] = $tend;

    $added[$targ] = $tend;

    warn join("\n",@lines),"\n\n" if DEBUG;
  }

  # take care of the extra stuff at the end
  for (my $i=1; $i < @dnas; $i++) {
    my $last_bit = length($dnas[$i]) - $added[$i];
    next unless defined $gap_map[$last_end[$i][0]];
    local $^W = 0; # prevent uninit variable warnings
    eval {substr($lines[$i],$gap_map[$last_end[$i][0]]+1,$last_bit)
	    = substr($dnas[$i],$added[$i]+1,$last_bit) };
  }

  # take care of the extra unaligned stuff at the beginning
  my $max = 0;
  for (my $i=0; $i < @dnas; $i++) {
    $leader[$i] ||= 0;      # to prevent uninit variable warnings
    next unless $leader[$i];
    my ($leading_gaps) = $lines[$i] =~ /^(-+)/;
    my $leading_pads   = length($leading_gaps||'');

    warn "\$leader[$i] = $leader[$i], \$leading_pads = $leading_pads\n" if DEBUG;

    my $insert_length = $leading_pads >= $leader[$i] ? $leader[$i] : $leading_pads;
    my $append_length = $leading_pads >= $leader[$i] ? 0           : $leader[$i]-$leading_pads;
    warn "insert length = $insert_length, append_length=$append_length\n" if DEBUG;

    if ($insert_length > 0) {
      substr($lines[$i],$leading_pads-$insert_length,$insert_length) =
	substr($dnas[$i],$leader[$i]-$insert_length,$insert_length);
      $leader[$i] -= $insert_length;
    }
    if ($append_length > 0) {
      substr($lines[$i],0,0) = $i>0 ? substr($dnas[$i],0,$append_length) : '-'x$append_length;
    }

    $max = $append_length if $append_length > $max;
  }
  warn "\n" if DEBUG;
  warn join("\n",@lines),"\n\n" if DEBUG;

  warn "finished adding stuff for everything but reference sequence\n" if DEBUG;

  for (my $i=0; $i<@dnas; $i++) {
    warn "i = $i, max = $max, leader = $leader[$i]\n" if DEBUG;
    my $delta = $max - $leader[$i];
    next unless $delta > 0;
    substr($lines[$i],0,0) = '-'x$delta;
  }

  warn join("\n",@lines),"\n\n" if DEBUG;

  # change starts and ends to . characters
  $max = 0;
  foreach (@lines) {
    $max = length if $max < length;
  }
  foreach (@lines) {
    my $deficit = $max - length;
    s/^(-+)/'.'x length $1/e;
    s/(-+)$/'.'x length $1/e;
    $_ .= '.' x $deficit if $deficit > 0;
  }

  $self->{gaps} = \@gap_map;

  return @lines if wantarray;

  my %names = reverse %{$self->{names}};
  my %result = map {$names{$_} => $lines[$_]} 0..$#lines;
  return \%result;
}

sub gap_map {
  my $self  = shift;
  $self->padded_sequences unless $self->{gaps};
  my $map   = $self->{gaps};
  return $map;
}

sub alignment {
  my $self            = shift;
  my $origins         = shift;
  my $options         = shift || {};

  my $show_mismatches = $options->{show_mismatches};
  my $show_matches = $options->{show_matches};
  my $show_similarities = $options->{show_similarities};
  my $color_code_proteins = $options->{color_code_proteins};
  warn "color code = $color_code_proteins" if DEBUG;
  my $flip            = $options->{flip};

  my @lines = $self->padded_sequences;
  my %names = reverse %{$self->{names}};  # index to name

  $origins ||= {};

  foreach (values %names) {
    $origins->{$_} = 1 unless defined $origins->{$_};
  }

  my $longest_name = 0;
  foreach (values %names) {
    my $offset    = $origins->{$_};
    my $length    = length($_);
    $length      += 2 if $offset < 0;
    $longest_name = $length if $length > $longest_name;
  }
  my $longest_line = 0;
  for (my $i=0; $i<@lines; $i++) {
    my $offset    = abs($origins->{$names{$i}});
    $longest_line = length($self->{dnas}[$i])+$offset 
       if (length($self->{dnas}[$i])+$offset > $longest_line);
  }

  $longest_line = length $longest_line;  # looks like an error but isn't

  # if flip is set, then we do amazing things to reorganize the display!
  if ($flip) {
    for (my $i = 0; $i < @lines; $i++) {
      $lines[$i] = reverse $lines[$i];
      $lines[$i] =~ tr/gatcGATC/ctagCTAG/;
      my $name   = $names{$i};
      $origins->{$name} *= -1;
    }
  }
  
  # use markup to insert word and line breaks
  my $markup = Bio::Graphics::Browser::Markup->new;
  $markup->add_style(space    => ' ');
  $markup->add_style(newline  => "\n");
  $markup->add_style(mismatch => "BGCOLOR pink");
  $markup->add_style(match => "BGCOLOR darkorange");
  $markup->add_style(conserved => "BGCOLOR tan");

  # Styles for printing protein alignments
  $markup->add_style(acidic_aa => "BGCOLOR lightgreen");
  $markup->add_style(basic_aa => "BGCOLOR lightskyblue");
  $markup->add_style(npolar_aa => "BGCOLOR lightgrey");
  $markup->add_style(polar_aa => "BGCOLOR burlywood");
  $markup->add_style(special_aa => "BGCOLOR red");

  # add word and line breaks
  for (my $i=0; $i < @lines; $i++) {
    my $pad = \$lines[$i];
    my @markup;
    for (my $j=0; $j < length $$pad; $j += 10) {
      push (@markup,[$j % 80 ? 'space':'newline',
                     $j => $j]);
    }
    $markup->markup($pad,\@markup);
  }

  my (@padded, @labels, @fixed);

  for (my $i = 0; $i < @lines; $i++) {
    my @segments = split "\n",$lines[$i];
    for (my $j = 0; $j < @segments; $j++) {
      $padded[$j][$i] = $segments[$j];
      $fixed[$j][$i] = $segments[$j];
    }
    my $origin  = $origins->{$names{$i}};
    $labels[$i] = $origin                                      if $origin >= 0;
    $labels[$i] = length($self->{dnas}[$i]) + abs($origin) - 1 if $origin <  0;
  }

  my $result;
  my @length;

  #$i: number of blocks; $j: number of sequences
  for (my $i = 0; $i < @padded; $i++) {
    for (my $j = 0; $j < @{$padded[$i]}; $j++) {

      next unless $padded[$i][$j];
      my $origin = $origins->{$names{$j}};
      my $offset = $padded[$i][$j] =~ tr/. -/. -/;
      my $skipit = $offset == length($padded[$i][$j]); 
      my @markup;

      #warn "Block ", $i, "\tsequence ", $j, "\t", $origin, "\t", $offset, "\t", $skipit, "\n";

      if ($color_code_proteins){
        if ($j==0) {                            # colouring reference seq
          for(my $q=0; $q<length $padded[$i][$j]; $q++) {
            my $refPos = substr($padded[$i][$j],$q,1);
            next if $refPos =~ /^[.\s-]$/;                               # move on if not amino acid
            push(@markup,[$aa_type{$refPos},$q=>$q+1]);
          } # end for
        }

	else {
          my @markup;
          for (my $r=0; $r<length $padded[$i][$j]; $r++) {
            my $targ = substr($padded[$i][$j],$r,1);
            next if $targ =~  /^[.\s-]$/;
            push(@markup,[$aa_type{$targ}, $r => $r+1]);
          }
        }
      }

      elsif ($show_mismatches) {
        if ($j>0) {
          for (my $r=0; $r<length $padded[$i][$j]; $r++) {
            my $targ = substr($padded[$i][$j],$r,1);
            next if $targ =~  /^[.\s-]$/;
            my $source = substr($padded[$i][0],$r,1);
            next if $source=~ /^[.\s-]$/;

            push(@markup,['mismatch',$r => $r+1])
              if (lc($source) ne lc($targ)); 

          }
        }
      }

      elsif ($show_matches) {
        for (my $r=0; $r<length $padded[$i][$j]; $r++) {

          my $targ = substr($padded[$i][$j],$r,1);
          my $identical = 1;
          my $conserved = 1;

          for (my $m=0; $m<@{$fixed[$i]}; $m++){
            my $source = substr($fixed[$i][$m],$r,1);

            if(($source =~ /[.\s-]/)||($targ =~ /[.\s-]/)){
              $identical = undef;
            } elsif (lc($source) ne lc($targ)){
              $identical = undef;
            }

            if(($source =~ /[.\s-]/)||($targ =~ /[.\s-]/)){
              $conserved = undef;
            }elsif (($aa_type{$source}) ne ($aa_type{$targ})){
              $conserved = undef;
            }
          }
          push(@markup,['match',$r => $r+1]) if ($identical);
          push(@markup,['conserved',$r => $r+1]) if ($conserved);
        }
      }

      elsif ($show_similarities) { #highligt resides same to the reference protein
        if ($j == 0){
          for (my $r=0; $r<length $padded[$i][$j]; $r++) {
            my $identical = undef;
            my $conserved = undef;

            my $targ = substr($padded[$i][$j],$r,1);
            next if ($targ =~ /^[.\-]$/);

            for (my $m=1; $m<@{$fixed[$i]}; $m++){
              my $source = substr($fixed[$i][$m],$r,1);
              next if ($source =~ /^[.\-]$/);

              if (($source !~ /^[.\s-]$/) && ($targ !~ /^[.\s-]$/) && (lc($source) eq lc($targ))){
                $identical = 1;
              }

              if (($source !~ /^[.\s-]$/) && ($targ !~ /^[.\s-]$/) && 
                  (lc($aa_type{$source}) eq lc($aa_type{$targ})) &&
                  (lc($source) ne lc($targ))
                 ){
                $conserved = 1;
              }
            }
            push(@markup,['conserved',$r => $r+1]) if ($conserved);
            push(@markup,['match',$r => $r+1]) if ($identical);
          }
        }

	else {
          for (my $r=0; $r<length $padded[$i][$j]; $r++) {

            my $targ = substr($padded[$i][$j],$r,1);
            my $identical = undef;
            my $conserved = undef;

            my $source = substr($fixed[$i][0],$r,1);
            next if ($source =~ /^[.\-]$/);

            if (($source !~ /[.\s-]/) && (lc($source) eq lc($targ))){
              $identical = 1;
            }

            if (($source !~ /^[.\s-]$/) && ($targ !~ /^[.\s-]$/) && 
                (lc($aa_type{$source}) eq lc($aa_type{$targ})) &&
                (lc($source) ne lc($targ))
               ){
              $conserved = 1;
            }

            push(@markup,['conserved',$r => $r+1]) if ($conserved);
            push(@markup,['match',$r => $r+1]) if ($identical);
          }
        }
      }

      $length[$i][$j] = length $padded[$i][$j];
      $markup->markup(\$padded[$i][$j],\@markup) if @markup;

      my $l = $longest_name;
      $result .= $skipit ? ""
                       : sprintf ("\%${l}s \%${longest_line}d %s\n",
                                  $origin < 0 ? "($names{$j})"
                                                : $names{$j},
                                    $labels[$j],$padded[$i][$j]);

      $labels[$j] += $length[$i][$j] - $offset  if $origin >= 0;
      $labels[$j] -= $length[$i][$j] - $offset  if $origin < 0;
    }
    $result .= "\n"; # unless $result && $result =~ /^[.\s]+$/;  # skip completely empty lines
  }	
  return $result;
}

1;

__END__

use constant SRC   => 0;
use constant TARG  => 1;

use constant REF   => 0;
use constant START => 1;
use constant END   => 2;

my @dnas = (
#               10        20          30          40         50         60         70         80        90
#      012345678901234567890123  456789012 3 45678901234 5678901 234567890123456 78901234 56789012345678901234
      'FFFFgatcGATCgatcGATCgatc--GATCgatcG-B-ATCgatcGATC-atcGATC-gatcGATCgatcGAT-CgatcGAT-gatcGATCgatcNNNNGATC',
        'FFgatcGATC----GATCgatcNNGATCgatcG---ATCgatcGATCgatcGATC-gatcGATC--tcGATBCgatcGATC-atcGATCgatcNNNNGATCFFFF',
#        0123456789    0123456789012345678   9012345678901234567 89012345  678901234567890 12345678901234567890123
      'FFFFgatcGATCgatcGATCgatc--GATCgatcBBBGATCgatcGATC-atcGATCBgatcGATCgatcGAT-CgatcGAT-gatcGATCgatcNNNNGATCFF',
#      012345678901234567890123  45678901234567890123456 78901234567890123456789 01234567 8901234567890123456789
#               10        20          30        40         50        60         70         80        90
    'ZZFFFFgatcGATCgatcGATCgatc--GATCgatc',
#    01234567890123456789012345  67890123
#             10        20          30
	               'AT-----------------BG-------GAT---------------------------------------------tcttttttt',
#                       01                 23       456                                             78
	   );

#                  ref st  en    tar tst ten
my @alignments = ([ [0, 4,  11],  [1,  2, 9]      ],
		  [ [0, 16, 23],  [1,  10, 17]    ],
		  [ [0, 24, 32],  [1,  20, 28]    ],
		  [ [0, 34, 44],  [1,  29, 39]    ],
		  [ [0, 45, 59],  [1,  41, 55]    ],
		  [ [0, 62, 66],  [1,  56, 60]    ],
		  [ [0, 67, 74],  [1,  62, 69]    ],
		  [ [0, 76, 86],  [1,  71, 81]    ],
		  [ [0, 91, 94],  [1,  86, 89]    ],

		  [ [0,  4, 31],  [2,   4, 31]    ],
		  [ [0,  33, 33], [2,  34, 34]    ],
		  [ [0,  34, 51], [2,  36, 53]    ],
		  [ [0,  52, 86], [2,  55, 89]    ],
		  [ [0,  91, 94], [2,  94, 97]    ],

		  [ [0,  0,  31], [3,  2,  33]    ],

		  [ [0,  17, 18], [4,  00, 01]    ],
		  [ [2,  34, 35], [4,  2,   3]    ],
		  [ [0,  41, 43], [4,  4,   6]    ],
		  [ [0,  85, 86], [4,  7,   8]    ],

		 );

foreach (@dnas) { s/-//g };

my @lines;

# initialize top line with src sequences
$lines[0] = $dnas[0];
my $len = length($lines[0]); 
for (my $i = 1; $i < @dnas; $i++) {
  $lines[$i]  = '-' x $len;
}

# running total of number of gaps, indexed by position on source
my @gap_map;
foreach (@dnas) { 
  push @gap_map,[0..length($_)-1]
}

# place where DNA[$i] left off
my @last_end;
my @added = (length $dnas[0]-1);

# alignments must be sorted according to target
foreach (sort {$a->[TARG][REF] <=> $b->[TARG][REF]
		 || $a->[TARG][START] <=> $b->[TARG][START]
	       } @alignments) {
  my ($src, $start, $end)  = @{$_->[SRC]};
  my ($targ,$tstart,$tend) = @{$_->[TARG]};

  # position in src coordinates where we last stopped
  my $last_src    = $last_end[$targ][$src]  ||= -1;

  # position in target coordinates where we last stopped
  my $last_target = $last_end[$targ][$targ] ||= -1;

  # This section adds the unaligned region between the last place that
  # we stopped and the current alignment
  my $gap       = 0;
  for (my $targ_pos=$tstart-1, my $j=$start-1; $targ_pos > $last_target; $targ_pos--, $j--) {
    if ($j > $last_src) { # still room
      my $pos = $gap_map[$src][$j];
      substr($lines[$targ],$pos,1) = substr($dnas[$targ],$targ_pos,1);
    }
    else {  # we've overrun -- start gapping above
      my $pos = $gap_map[$src][$start];
      for (my $i=0; $i<@lines; $i++) {
	substr($lines[$i],$pos,0) = '-' unless $i==$targ;  # gap all segments
      }
      substr($lines[$targ],$pos+$gap++,0) = substr($dnas[$targ],$targ_pos,1);
    }
  }
  if ($gap > 0) {
    for (my $i=0; $i<@lines; $i++) {
      next if $i == $targ;
      for (@{$gap_map[$i]}[$start..$#{$gap_map[$i]}]) { $_ += $gap }  # update gap map
    }
  }

  # insert the aligned bit now
  for (my $pos = $start; $pos <= $end; $pos++) {
    my $gap_pos = $gap_map[$src][$pos];
    substr($lines[$targ],$gap_pos,1) = substr($dnas[$targ],$tstart++,1);
  }

  $last_end[$targ][$src]  = $end;
  $last_end[$targ][$targ] = $tend;

  $added[$targ] = $tend;

  #print join("\n",@lines),"\n\n";
}

# take care of the extra stuff at the end
for (my $i=1; $i < @dnas; $i++) {
  my $last_bit = length($dnas[$i]) - $added[$i];
  substr($lines[$i],$gap_map[0][$last_end[$i][0]]+1,$last_bit)
    = substr($dnas[$i],$added[$i]+1,$last_bit);
}

# change starts and ends to . characters
my $max = 0;
foreach (@lines) {
  $max = length if $max < length;
}
foreach (@lines) {
  my $deficit = $max - length;
  s/^(-+)/'.'x length $1/e;
  s/(-+)$/'.'x length $1/e;
  $_ .= '.' x $deficit if $deficit > 0;
}


print join("\n",@lines),"\n";

# use markup to insert word and line breaks
my $markup = Bio::Graphics::Browser::Markup->new;
$markup->add_style(space   => ' ');
$markup->add_style(newline => "\n");
for (my $i=0; $i < @lines; $i++) {
  my $pad = \$lines[$i];
  my @markup;
  # add word and line breaks
  for (my $j=0; $j < length $$pad; $j += 10) {
    push (@markup,[$j % 80 ? 'space':'newline',
		   $j => $j]);
  }
  $markup->markup($pad,\@markup);
}

my @padded;
for (my $i = 0; $i < @lines; $i++) {
  my @segments = split "\n",$lines[$i];
  for (my $j = 0; $j < @segments; $j++) {
    $padded[$j][$i] = $segments[$j];
  }
}

my @labels = (1) x @lines;

for (my $i = 0; $i < @padded; $i++) {
  for (my $j = 0; $j < @{$padded[$i]}; $j++) {
    next unless $padded[$i][$j];
    printf ("%5d %s\n",$labels[$j],$padded[$i][$j]);
    my $offset = $padded[$i][$j] =~ tr/. -/. -/;
    $labels[$j] = length($padded[$i][$j]) - $offset + 1;
  }
  print "\n";
}


sub segment {
  my ($str,$start,$stop) = @_;
  my $length = $stop-$start+1;
  return unless $length > 0;
  return substr($str,$start,$length);
}
