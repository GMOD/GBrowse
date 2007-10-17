package Bio::Graphics::Browser::Realign;

=head1 NAME

Bio::Graphics::Browser::Realign - Perl extension for Smith-Waterman alignments

=head1 SYNOPSIS

  use Bio::Graphics::Browser::Realign 'align';
  my ($top,$middle,$bottom) = align('gattttttc','gattttccc');
  print join "\n",$top,$middle,$bottom,"\n";

  # produces:
  gatttttt--c
  ||||||    |
  gatttt--ccc


=head1 DESCRIPTION

This is a helper utility used by gbrowse to produce global alignments.
It uses slow Smith-Waterman, so is only appropriate for short segments
that are mostly aligned already.

It can be speeded up significantly by compiling
Bio::Graphics::Browser::CAlign, an XS extension.  To do this, build
gbrowse with the DO_XS=1 option:

  cd Generic-Genome-Browser
  perl Makefile.PL DO_XS=1

=head2 METHODS

=over 4

=cut

# file: Sequence/Alignment.pm

use strict;
use Carp;
use vars '@DEFAULTS';
use constant DEBUG=>0;

use vars qw(@ISA @EXPORT @EXPORT_OK);

require Exporter;
@ISA = 'Exporter';
@EXPORT    = ();
@EXPORT_OK = qw(align align_segs);

# The default scoring matrix introduces a penalty of -1 for opening
# a gap in the sequence, but no penalty for extending an already opened
# gap.  A nucleotide mismatch has a penalty of -1, and a match has a
# positive score of +1.  An ambiguous nucleotide ("N")  can match
# anything with no penalty.
use constant DEFAULT_MATRIX => { 'wildcard_match'  => 0,
				 'match'           => 1,
				 'mismatch'        => -1,
				 'gap'             => -1,
				 'gap_extend'      => 0,
				 'wildcard'        => 'N',
				 };

use constant SCORE => 0;
use constant EVENT => 1;
use constant EXTEND => 0;
use constant GAP_SRC => 1;
use constant GAP_TGT => 2;

my @EVENTS = qw(extend gap_src gap_tgt);

=item $aligner = Bio::Graphics::Browser::Realign->new($src,$target [,\%matrix])

The new() method takes two the two sequence strings to be aligned and
an optional weight matrix.  Legal weight matrix keys and their default
values are shown here:

   Key name       Default       Description
   --------       -------       -----------

   match            1           Award one point for an exact match.
   mismatch        -1           Penalize one point for a mismatch.
   wildcard_match   0           No penalty for a match to a wildcard (e.g. "n").
   gap             -1           Penalize one point to create a gap.
   gap_extend       0           No penalty for extending an existing gap.
   wildcard         'N'         The wildcard character.

The alignment algorithm is run when new() is called.

=cut

# Construct a new alignment object.  May be time consuming.
sub new {
    my ($class,$src,$tgt,$matrix) = @_;
    croak 'Usage: Realign->new($src,$tgt [,\%matrix])'
      unless $src && $tgt;
    my $self = bless {
		      src    => $src,
		      target => $tgt,
		      matrix => $matrix || {},
		      },$class;
    my $implementor = $class;
    if (eval {require Bio::Graphics::Browser::CAlign}) {
      $implementor = 'Bio::Graphics::Browser::CAlign';
    }
    my ($score,$alignment) = $implementor->_do_alignment($src,$tgt,$self->{matrix});
    $self->{score}     = $score;
    $self->{alignment} = $alignment;
    return $self;
}

=item $score = $aligner->score

Return the score from the alignment.

=cut

# return the score of the aligned region
sub score { return shift()->{'score'}; }

=item $start = $aligner->start

Return the start of the aligned region, in source sequence
coordinates.

=cut

# return the start of the aligned region
sub start { 
    return shift()->{'alignment'}->[0];
}

=item $end = $aligner->end

Return the end of the aligned region, in source sequence
coordinates.

=cut

# return the end of the aligned region
sub end {
    my $alignment = shift()->{'alignment'};
    return $alignment->[$#$alignment];
}

=item $arrayref = $aligner->alignment

Return an arrayref representing the alignment.  The array will be
exactly as long as the source sequence.  Its indexes correspond to
positions on the source sequence, and its values correspond to
positions on the target sequence.  An unaligned base is indicated as
undef.  Indexes are zero-based.

For example, this alignment:

  gatttttt--c
  ||||||    |
  gatttt--ccc

corresponds to this arrayref:

   index    value
   0[g]    0[g]
   1[a]    1[a]
   2[t]    2[t]
   3[t]    3[t]
   4[t]    4[t]
   5[t]    5[t]
   6[t]    undef
   7[t]    undef
   8[c]    8[c]

=cut

# return the alignment as an array
sub alignment { shift()->{'alignment'}; }

=item ($top,$middle,$bottom) = $aligner->pads

Returns the alignment as three padded strings indicating the top,
middle and bottom lines of a pretty-printed representation.

For example:

  print join "\n",$aligner->pads;

Will produce this output:

  gatttttt--c
  ||||||    |
  gatttt--ccc

=cut

# return the alignment as three padded strings for pretty-printing, etc.
sub pads {
    my ($align,$src,$tgt) = @{shift()}{'alignment','src','target'};
    my ($ps,$pt,$last);
    $ps = '-' x ($align->[0])        if defined $align->[0];  # pad up the source
    $pt = substr($tgt,0,$align->[0]) if defined $align->[0];
    $last = $align->[0] || 0;
    for (my $i=0;$i<@$align;$i++) {
	my $t = $align->[$i];
	if (defined $t) {
	    $pt .= $t-$last > 1 ? substr($tgt,$last+1,$t-$last): substr($tgt,$t,1);
	    $ps .= '-' x ($t-$last-1);
	    $last = $t;
	} else {
	    $pt .= '-';
	}
	$ps .= substr($src,$i,1);
    }
    # clean up the ends
    $ps .= substr($src,@$align);
    $pt .= substr($tgt,$last+1);
    $pt .= '-' x (length($ps) - length($pt)) if length($ps) > length($pt);
    $ps .= '-' x (length($pt) - length($ps)) unless length($ps) > length($pt);
    my $match = join('',
		     map { uc substr($ps,$_,1) eq uc substr($pt,$_,1) ? '|' : ' '  }
		     (0..length($pt)-1));
    return ($ps,$match,$pt);
}

=back

=head2 EXPORTED METHODS

No functions are exported by default, but the following two methods
can be imported explicitly.

=over 4

=cut

=item ($top,$middle,$bottom) = align($source,$target [,\%matrix])

Align the source and target sequences and return the padded strings
representing the alignment.  It is exactly equivalent to calling:

  Bio::Graphics::Browser::Realign->new($source,$target)->pads;

=cut

# take two sequences as strings, align them and return
# a three element array consisting of gapped seq1, match string, and
# gapped seq2.
sub align {
  my ($seq1,$seq2,$matrix) = @_;
  my $align = __PACKAGE__->new($seq1,$seq2,$matrix);
  return $align->pads;
}

=item $segs_arrayref = align_segs($source,$target [,\%matrix])

The align_segs() function aligns $source and $target and returns an
array of non-gapped segments.  Each element of the array corresponds
to a contiguous nongapped alignment in the format
[src_start,src_end,tgt_start,tgt_end].

This is useful for converting a gapped alignment into a series of
nongapped alignments.

In a list context this function will return a list of non-gapped
segments.

=cut

sub align_segs {
  my ($gap1,$align,$gap2) = align(@_);

  # create arrays that map residue positions to gap positions
  my @maps;
  for my $seq ($gap1,$gap2) {
    my @seq = split '',$seq;
    my @map;
    my $residue = 0;
    for (my $i=0;$i<@seq;$i++) {
      $map[$i] = $residue;
      $residue++ if $seq[$i] ne '-';
    }
    push @maps,\@map;
  }

  my @result;
  while ($align =~ /(\S+)/g) {
    my $align_end   = pos($align) - 1;
    my $align_start = $align_end  - length($1) + 1;
    push @result,[@{$maps[0]}[$align_start,$align_end],
		  @{$maps[1]}[$align_start,$align_end]];
  }
  return wantarray ? @result : \@result;
}

sub _do_alignment {
    my $class = shift;
    local $^W = 0;
    my($src,$tgt,$custom_matrix) = @_;
    my @alignment;
    $custom_matrix ||= {};
    my %matrix = (%{DEFAULT_MATRIX()},%$custom_matrix);

    my ($max_score,$max_row,$max_col);
    my $scores = [([0,EXTEND])x(length($tgt)+1)];

    print join(' ',map {sprintf("%-4s",$_)} (' ',split('',$tgt))),"\n" if DEBUG;
    my $wildcard = $matrix{wildcard};
    for (my $row=0;$row<length($src);$row++) {
      my $s = uc substr($src,$row,1);
      my @row = ([0,EXTEND]);
      for (my $col=0;$col<length($tgt);$col++) {
	my $t = uc substr($tgt,$col,1);

	# what happens if we extend the both strands one character?
	my $extend = $scores->[$col][SCORE];
	$extend += ($t eq $wildcard || $s eq $wildcard) ? $matrix{wildcard_match} :
	           ($t eq $s)               ? $matrix{match} :
                                              $matrix{mismatch};

        # what happens if we extend the src strand one character, gapping the tgt?
	my $gap_tgt  = $row[$#row][SCORE] + (($row[$#row][EVENT]>EXTEND) ? $matrix{gap_extend}
	                                                                 : $matrix{gap});

        # what happens if we extend the tgt strand one character, gapping the src?
	my $gap_src  = $scores->[$col+1][SCORE] + (($scores->[$col+1][EVENT] > EXTEND) ? $matrix{gap_extend}
	                                                                               : $matrix{gap});

	# find the best score among the possibilities
	my $score;
	if ($extend >= $gap_src && $extend >= $gap_tgt) {
	    $score = [$extend,EXTEND];
	} elsif ($gap_src >= $gap_tgt) {
	    $score = [$gap_src,GAP_SRC];
	} else {
	    $score = [$gap_tgt,GAP_TGT];
	}

	# save it for posterity
	push(@row,$score);
	($max_score,$max_row,$max_col) = ($score->[SCORE],$row,$col) if $score->[SCORE] >= $max_score;
      }
      print join(' ',($s,map {sprintf("%4d",$_->[SCORE])} @row[1..$#row])),"\n" if DEBUG;
      $scores = \@row;
      push(@alignment,[@row[1..$#row]]);
    }
    my $alignment = $class->_trace_back($max_row,$max_col,\@alignment);
    if (DEBUG) {
      for (my $i=0;$i<@$alignment;$i++) {
	printf STDERR ("%3d %1s %3d %1s\n",
		       $i,substr($src,$i,1),
		       $alignment->[$i],defined $alignment->[$i] ? substr($tgt,$alignment->[$i],1):'');
      }
    }

    return ($max_score,$alignment);
}

sub _trace_back {
    my $self = shift;
    my ($row,$col,$m) = @_;
    my @alignment;
    while ($row >= 0 && $col >= 0) {
      printf STDERR "row=%d, col=%d score=%d event=%s\n",$row,$col,$m->[$row][$col][SCORE],$EVENTS[$m->[$row][$col][EVENT]] if DEBUG;
	$alignment[$row] = $col;
	my $score = $m->[$row][$col];
	$row--,$col--,next if $score->[EVENT] == EXTEND;
	$col--,       next if $score->[EVENT] == GAP_TGT;
	undef($alignment[$row]),$row--,next if $score->[EVENT] == GAP_SRC;
    }
    return \@alignment;
}

1;

__END__

=back

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2003 Cold Spring Harbor Laboratory

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=head1 SEE ALSO

L<Bio::Graphics::Browser>.

=cut

