package Bio::Graphics::Browser::Realign;
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

# Construct a new alignment object.  May be time consuming.
sub new {
    my ($class,$src,$tgt,$matrix) = @_;
    croak 'Usage: CAlign->new($src,$tgt [,\%matrix])'
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

# take two sequences as strings, align them and return
# a three element array consisting of gapped seq1, match string, and
# gapped seq2.
sub align {
  my ($seq1,$seq2,$matrix) = @_;
  my $align = __PACKAGE__->new($seq1,$seq2,$matrix);
  return $align->pads;
}

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
  return @result;
}

# return the score of the aligned region
sub score { return shift()->{'score'}; }

# return the start of the aligned region
sub start { 
    return shift()->{'alignment'}->[0];
}

# return the end of the aligned region
sub end {
    my $alignment = shift()->{'alignment'};
    return $alignment->[$#$alignment];
}

# return the alignment as an array
sub alignment { shift()->{'alignment'}; }

# return the alignment as three padded strings for pretty-printing, etc.
sub pads {
    my ($align,$src,$tgt) = @{shift()}{'alignment','src','target'};
    my ($ps,$pt,$last);
    $ps = '-' x $align->[0];  # pad up the source
    $pt = substr($tgt,0,$align->[0]);
    $last = $align->[0];
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
