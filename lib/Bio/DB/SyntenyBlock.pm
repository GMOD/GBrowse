package Bio::DB::SyntenyBlock;

use strict;
use constant SRC    => 0;
use constant SEQID  => 1;
use constant START  => 2;
use constant STOP   => 3;
use constant STRAND => 4;
use constant SEQ    => 5;

## What does this do?
*ref = \&seqid;

=head1 NAME

Bio::DB::SyntenyBlock - 

=head1 USAGE

    my $sb = ...

    $sb->name; # Name of the current synteny block
    $sb->src;  # Source 'SeqFeature'
    $sb->tgt;  # Target 'SeqFeature'

    ## The src and tgt 'SeqFeature's together define a syntenic
    ## relationship between two sequences (and probably two species).

    ## Methods for the src 'SeqFeature'
    $sb->src1;   # species code
    $sb->seqid;  # sequence seqid
    $sb->start;  # start positon of the feature
    $sb->end;    # end   positon of the feature
    $sb->strand; # strand of the feature

    ## Methods for the tgt 'SeqFeature'
    $sb->src2;    # species code
    $sb->target;  # sequence seqid
    $sb->tstart;  # start positon of the feature
    $sb->tend;    # end   positon of the feature
    $sb->tstrand; # strand of the feature

=head1 DESCRIPTION

A synteny block is a named a pair of SeqFeatures, one indexed by 'src'
and one indexed by 'tgt'. The pair represents a syntentic block
relationship between the two 'SeqFeatures'.

A syntenic block can have one or more 'parts'. If there is more than
one part, the synteny block describes the whole range of sequence
covered by the parts. The seqids, sequences and strands of the
underlying parts are implicitly assumed to be the same accross the
part.

Subsequent parts are stored as 'parts', which seems buggy, because the
first part isn't one of the parts stored, and it's range will be lost
when we add the second part.

TODO: Really use SeqFeatures.
TODO: Implement as an alignment feature?

=cut



sub new {
  my $class = shift;
  my $name  = shift;
  return bless {
		src     => [undef,undef,undef,undef,undef,undef],
		tgt     => [undef,undef,undef,undef,undef,undef],
		name    => $name,
		},ref($class) || $class;
}

sub name    { shift->{name}        }
sub src     { shift->{src}         }
sub tgt     { shift->{tgt}         }

sub src1    { shift->{src}[SRC]    }
sub seqid   { shift->{src}[SEQID]  }
sub strand  { shift->{src}[STRAND] }
sub seq     { shift->{src}[SEQ]    }

sub src2    { shift->{tgt}[SRC]    }
sub target  { shift->{tgt}[SEQID]  }
sub tstrand { shift->{tgt}[STRAND] }
sub tseq    { shift->{tgt}[SEQ]    }

sub start   {
  my $self = shift;
  my $value = shift;
  $self->{src}[START] = $value if $value;
  return $self->{src}[START];
}

sub end     {
  my $self = shift;
  my $value = shift;
  $self->{src}[STOP] = $value if $value;
  return $self->{src}[STOP];
}

sub tstart  {
  my $self = shift;
  my $value = shift;
  $self->{tgt}[START] = $value if $value;
  return $self->{tgt}[START];
}

sub tend  { 
  my $self = shift;
  my $value = shift;
  $self->{tgt}[STOP] = $value if $value;
  return $self->{tgt}[STOP];
}

sub length  { 
  my $self = shift;
  return $self->end - $self->start;
}

sub tlength {
  my $self = shift;
  return $self->tend - $self->tstart;
}

sub coordinates {
  my $self = shift;
  return @{$self->{src}},@{$self->{tgt}};
}

# sorted parts list
sub parts   { 
  my $self = shift;
  my $parts = $self->{parts} ?
      [sort {$a->start <=> $b->start} @{$self->{parts}}] : [$self];
  return $parts; 
}

sub add_part {
  my $self = shift;
  my ($src,$tgt) = @_;

  for (['src',$src],
       ['tgt',$tgt]) {
    my $parent   = $self->{$_->[0]};
    my $part     = $_->[1];
    $parent->[SRC]    ||= $part->[SRC];
    $parent->[SEQID]  ||= $part->[SEQID];
    $parent->[STRAND] ||= $part->[STRAND];
    $parent->[SEQ]    ||= $part->[SEQ];
    $parent->[START]    = $part->[START]
        if !defined($parent->[START]) or $parent->[START] > $part->[START];
    $parent->[STOP]     = $part->[STOP] 
        if !defined($parent->[STOP])  or $parent->[STOP]  < $part->[STOP];
  }

  if (++$self->{cardinality} > 1) {
    my $subpart = $self->new($self->name . ".$self->{cardinality}");
    $subpart->add_part($src,$tgt);
    $self->{parts} ||= [];
    push @{$self->{parts}},$subpart;
    return $subpart->name;
  }
  else{
     ## What? What is returned here?
  }
}

1;
