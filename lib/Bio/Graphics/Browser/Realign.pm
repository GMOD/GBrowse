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
use constant DEFAULT_MATRIX => { 'N' => 0,
				 'MATCH' => 1,
				 'MISMATCH' => -1,
				 'GAP' => -1,
				 'GAP_EXTEND' => 0
				 };

# take two sequences as strings, align them and return
# a three element array consisting of gapped seq1, match string, and
# gapped seq2.
sub align {
  my ($seq1,$seq2) = @_;
  my $align = __PACKAGE__->new(src=>$seq1,target=>$seq2);
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

# Construct a new alignment object.  May be time consuming.
sub new {
    my ($class,%args) = @_;
    $args{'matrix'} = { %{DEFAULT_MATRIX()},$args{'matrix'} ? %{$args{'matrix'}}:()};
    croak 'new() requires parameters of "src" and "target"'
	unless $args{'src'} && $args{'target'};
    my $self =  bless \%args,$class;
    $self->_do_alignment;
    return $self;
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
    my $self = shift;
    my($src,$tgt) = @{$self}{'src','target'};
    my @alignment;

    my $score = $self->{'matrix'};
    my ($max_score,$max_row,$max_col);
    my $scores = [(0)x(length($tgt)+1)];

    print join(' ',map {sprintf("%-4s",$_)} (' ',split('',$tgt))),"\n" if DEBUG;
    for (my $row=0;$row<length($src);$row++) {
      my $s = uc substr($src,$row,1);
      my @row = (0);
      for (my $col=0;$col<length($tgt);$col++) {
	my $t = uc substr($tgt,$col,1);

	# what happens if we extend the both strands one character?
	my $extend = $scores->[$col];
	$extend += ($t eq 'N' || $s eq 'N') ? $score->{N} :
	           ($t eq $s)               ? $score->{MATCH} :
                                              $score->{MISMATCH};

        # what happens if we extend the src strand one character, gapping the tgt?
	my $gap_tgt  = $row[$#row] + (($row[$#row]!~/gap/) ? $score->{GAP} 
	                                                  : $score->{GAP_EXTEND});

        # what happens if we extend the tgt strand one character, gapping the src?
	my $gap_src  = $scores->[$col+1] + (($scores->[$col+1]!~/gap/) ? $score->{GAP} 
	                                                     : $score->{GAP_EXTEND});

	# find the best score among the possibilities
	my $score;
	if ($extend >= $gap_src && $extend >= $gap_tgt) {
	    $score = "$extend extend";
	} elsif ($gap_src >= $gap_tgt) {
	    $score = "$gap_src gap_src";
	} else {
	    $score = "$gap_tgt gap_tgt";
	}

	# save it for posterity
	push(@row,$score);
	($max_score,$max_row,$max_col) = ($score+=0,$row,$col) if $score >= $max_score;
      }
      print join(' ',($s,map {sprintf("%4d",$_)} @row[1..$#row])),"\n" if DEBUG;
      $scores = \@row;
      push(@alignment,[@row[1..$#row]]);
    }
    $self->{'score'}     = $max_score;
    $self->{'alignment'} = $self->_trace_back($max_row,$max_col,\@alignment);
}

sub _trace_back {
    my $self = shift;
    my ($row,$col,$m) = @_;
    my @alignment;
    while ($row >= 0 && $col >= 0) {
	$alignment[$row] = $col;
	my $score = $m->[$row][$col];
	$row--,$col--,next if $score =~ /extend/;
	$col--,       next if $score =~ /tgt/;
	undef($alignment[$row]),$row--,next if $score =~ /src/;
    }
    return \@alignment;
}

1;
