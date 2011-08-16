=head1 NAME

Bio::DB::Synteny::Loader::MSA - load a Bio::DB::Synteny::Store from a
multiple sequence alignment

=head1 SYNOPSIS

  my $store  = Bio::DB::Synteny::Store->new( ... );
  my $loader = Bio::DB::Synteny::Store::Loader::MSA->new(
                   -store => $store,
               );
  $loader->load( $file_1, $file_2 );

=head1 DESCRIPTION

Loads multiple sequence alignments directly into a
L<Bio::DB::Synteny::Store> using L<Bio::AlignIO>.

=head1 METHODS

=cut

package Bio::DB::Synteny::Store::Loader::MSA;
use strict;

use base 'Bio::DB::Synteny::Store::Loader';

use Bio::AlignIO;
use Bio::DB::GFF::Util::Rearrange qw(rearrange);

use constant VERBOSE  => 0;
use constant DEFAULT_MAPRES   => 100;

=head2 new( -store => $store, -format => $format )

Construct and configure a new loader object, which will load into the
given store.  Arguments and options:

=over 4

=item -store

The L<Bio::DB::Synteny::Store> object, which is the data store to load into.

=item -format

The file format of the input files.  This can be any string format
name supported by BioPerl's L<Bio::AlignIO> system.

=cut

sub new {
    my $class = shift;
    my $self = $class->SUPER::new( @_ );

    my ( $format, $mapres ) = rearrange([qw[ FORMAT MAPRES ]], @_ );
    $self->{format} = $format || $class->throw('-format argument required for MSA loader');
    $self->{mapres} = $mapres || DEFAULT_MAPRES;
    return $self;
}

sub format  { shift->{'format'} }
sub mapres  { shift->{mapres}   }

=head2 load( filename, filename, ... )

Load the given files.

=cut

sub load {
    my $self = shift;

    while (my $infile = shift) {
        print "Processing alignment file $infile...\n" if $self->verbose;
        my $alignIO = Bio::AlignIO->new( -file   => $infile,
                                         -format => $self->format );

        while (my $aln = $alignIO->next_aln) {
            my $len = $aln->length;
            #print STDERR "Processing Multiple Sequence Alignment " . ++$aln_idx . " (length $len)\t\t\t\r" if $self->verbose;
            next if $aln->num_sequences < 2;
            my %seq;
            $self->{map} = {};
            for my $seq ($aln->each_seq) {
                my $seqid = $seq->id;
                my ($species,$ref,$strand) = $self->check_name_format($seqid,$seq);
                next if $seq->seq =~ /^-+$/;
                # We have to tell the sequence object what its strand is
                $seq->strand($strand eq '-' ? -1 : 1);
                $seq{$species} = [$ref, $seq->display_name, $seq->start, $seq->end, $strand, $seq->seq, $seq];
            }

            # make all pairwise hits and grid coordinates
            my @species = keys %seq;

            for my $p (map_pairwise(@species)) {
                my ($s1,$s2) = @$p;
                my $array1 = $seq{$s1};
                my $array2 = $seq{$s2};

                my $seq1 = $$array1[6];
                my $seq2 = $$array2[6];

                unless ($self->store->nomap) {
                    my $map = {};
                    $array1->[7] = $self->make_map($seq1,$seq2,$map);
                    $array2->[7] = $self->make_map($seq2,$seq1,$map);
                }

                $self->make_hit($s1 => $array1, $s2 => $array2);
            }
        }
    }
}

# Make coordinate maps at the specified resolution
sub make_map {
  my ($self,$s1,$s2,$map) = @_;
  $s1 && $s2 || return {};
  unless (UNIVERSAL::can($s1,'isa')) {
    warn "WTF? $s1 $s2\n" and next;
  }

  $self->column_to_residue_number($s1,$s2);
  my $coord = nearest($self->mapres,$s1->start);
  $coord += $self->mapres if $coord < $s1->start;
  my @map;

  my $reverse = $s1->strand ne $s2->strand;

  # have to get the column number from residue position, then
  # the matching residue num from the column number
  while ($coord < $s1->end) {
    my $col     = $self->column_from_residue_number($s1,$coord);
    my $coord2  = $self->residue_from_column_number($s2,$col) if $col;
    push @map, ($coord,$coord2) if $coord2;
    $coord += $self->mapres;
  }
  return { @map };
}

sub column_to_residue_number {
    my $self = shift;

    for my $seq (@_) {
        my $str = $seq->seq;
        my $id  = $seq->id;
        next if $self->{map}{$id};
        my $rev = $seq->strand < 0;
        my $res = $rev ? $seq->end - 1 : $seq->start + 1;
        my @cols = split '', $str;

        my $pos;
        my $col;
        for my $chr (@cols) {
            unless ($chr eq '-') {
                $rev ? $res-- : $res++;
            }

            $col++;
            $self->{map}{$id}{col}{$col} = $res;
            $self->{map}{$id}{res}{$res} ||= $col;
        }
    }
}

sub column_from_residue_number {
  my ( $self, $seq, $res ) = @_;
  my $id = $seq->id;
  return $self->{map}{$id}{res}{$res};
}

sub residue_from_column_number {
  my ( $self, $seq, $col ) = @_;
  my $id = $seq->id;
  print"WTF? $seq $id $col\n" unless $id &&$col;
  return $self->{map}{$id}{col}{$col};
}

sub make_hit {
  my ($self,$s1,$aln1,$s2,$aln2,$fh) = @_;
  my $rightnum = $self->store->nomap ? 7 : 8;
  die "wrong number of keys @$aln1" unless @$aln1 == $rightnum;
  die "wrong number of keys @$aln2" unless @$aln2 == $rightnum;
  my $map1 = $aln1->[7] || {};
  my $map2 = $aln2->[7] || {};

  # not using these yet
  my ($cigar1,$cigar2) = qw/. ./;

  $self->store->add_alignment(
      [$s1,@{$aln1}[0,2..4],$cigar1,$map1],
      [$s2,@{$aln2}[0,2..4],$cigar2,$map2],
      );
}

sub map_pairwise {
  my @out;
  for my $i (0..$#_) {
    for my $j ($i+1..$#_) {
      push @out, [$_[$i], $_[$j]];
    }
  }
  return @out;
}

# stolen from Math::Round
sub nearest {
  my $targ = abs(shift);
  my $half = 0.50000000000008;
  my @res  = map {
    if ($_ >= 0) { $targ * int(($_ + $half * $targ) / $targ); }
    else { $targ * POSIX::ceil(($_ - $half * $targ) / $targ); }
  } @_;

  return (wantarray) ? @res : $res[0];
}

sub check_name_format {
    my ( $self, $name, $seq ) = @_;

  my $nogood = <<"  END";

I am sorry, I do not like the format of the sequence name: '$name'

This will not work unless you use the name format described below for
each sequence in the alignment.

We need the species, sequence name, strand, start and end for each
sequence in the alignment.

  Name format:
    species-sequence(strand)/start-end

  Where:

    species     name of species, genome, strain, etc
                (the name must exclude '-' characters)

    sequence    name of reference sequence
                (the name must exclude '/' characters)

    strand      orientation of the alignment relative to the reference
                sequence; + or -

    start       start coordinate of the alignment relative to the
                reference sequence (integer)

    end         end coordinate of the alignment relative to the
                reference sequence (integer)

  Examples:
    c_elegans-I(+)/1..2300
    myco_bovis-chr1(-)/15000..25000

  END
  ;

  die $nogood unless $seq->start && $seq->end;
  die $nogood unless $name =~ /^([^-]+)-([^\(]+)\(([+-])\)$/;
  return ($1,$2,$3);
}

1;

