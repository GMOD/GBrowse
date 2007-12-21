package Bio::DB::GFF::SyntenyBlock;

use strict;
use constant SRC    => 0;
use constant SEQID  => 1;
use constant START  => 2;
use constant STOP   => 3;
use constant STRAND => 4;
use constant SEQ    => 5;

*ref = \&seqid;

sub new {
  my $class = shift;
  my $name  = shift;
  return bless {
		src     => [undef,undef,undef,undef,undef,undef],
		tgt     => [undef,undef,undef,undef,undef,undef],
		name    => $name,
		},ref($class) || $class;
}

sub name    { shift->{name}      }
sub src1    { shift->{src}[SRC]  }
sub src2    { shift->{tgt}[SRC]  }

sub seqid   { shift->{src}[SEQID]  }
sub strand  { shift->{src}[STRAND] }
sub target  { shift->{tgt}[SEQID]  }
sub seq     { shift->{src}[SEQ]    }
sub tseq    { shift->{tgt}[SEQ]    }
sub length  { 
  my $self = shift;
  return $self->end - $self->start;
}
sub tlength {
  my $self = shift;
  return $self->tend - $self->tstart;
}


# make these getter/setters in case they
# must be adjusted later
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

sub tstrand { shift->{tgt}[STRAND] }

# sorted parts list
sub parts   { 
  my $self = shift;
  my $parts = $self->{parts} ? [sort {$a->start <=> $b->start} @{$self->{parts}}]
      : [$self];
  return $parts; 
}

sub src     { shift->{src}         }
sub tgt     { shift->{tgt}         }

sub coordinates {
  my $self = shift;
  return @{$self->{src}},@{$self->{tgt}};
}

sub add_part {
  my $self = shift;
  my ($src,$tgt) = @_;
  for (['src',$src],['tgt',$tgt]) {
    my $parent   = $self->{$_->[0]};
    my $part     = $_->[1];
    $parent->[SRC]    ||= $part->[SRC];
    $parent->[SEQID]  ||= $part->[SEQID];
    $parent->[STRAND] ||= $part->[STRAND];
    $parent->[SEQ]    ||= $part->[SEQ];
    $parent->[START]   = $part->[START] if !defined($parent->[START])  or $parent->[START] > $part->[START];
    $parent->[STOP]    = $part->[STOP]  if !defined($parent->[STOP])   or $parent->[STOP]  < $part->[STOP];
  }
  if (++$self->{cardinality} > 1) {
    my $subpart = $self->new($self->name . ".$self->{cardinality}");
    $subpart->add_part($src,$tgt);
    $self->{parts} ||= [];
    push @{$self->{parts}},$subpart;
    return $subpart->name;
  }
}

1;
