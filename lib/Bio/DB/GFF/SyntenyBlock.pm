package Bio::DB::GFF::SyntenyBlock;

use strict;
use constant SRC    => 0;
use constant SEQID  => 1;
use constant START  => 2;
use constant STOP   => 3;
use constant STRAND => 4;

*ref = \&seqid;

sub new {
  my $class = shift;
  my $name  = shift;
  return bless {
		src     => [undef,undef,undef,undef,undef],
		tgt     => [undef,undef,undef,undef,undef],
		name    => $name,
		},ref($class) || $class;
}

sub name    { shift->{name}      }
sub src1    { shift->{src}[SRC]  }
sub src2    { shift->{tgt}[SRC]  }

sub seqid   { shift->{src}[SEQID]  }
sub start   { shift->{src}[START]  }
sub end     { shift->{src}[STOP]    }
sub strand  { shift->{src}[STRAND] }

sub target  { shift->{tgt}[SEQID]  }
sub tstart  { shift->{tgt}[START]  }
sub tend    { shift->{tgt}[STOP]    }
sub tstrand { shift->{tgt}[STRAND] }

sub parts   { shift->{parts}       }
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
    $parent->[START]   = $part->[START] if !defined($parent->[START]) or $parent->[START]> $part->[START];
    $parent->[STOP]    = $part->[STOP]   if !defined($parent->[STOP])   or $parent->[STOP]  < $part->[STOP];
  }
  if (++$self->{cardinality} > 1) {
    my $subpart = $self->new($self->name . ".$self->{cardinality}");
    $subpart->add_part($src,$tgt);
    $self->{parts} ||= [];
    push @{$self->{parts}},$subpart;
  }
}

1;
