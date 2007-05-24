package Bio::Graphics::Wiggle;

=head1 NAME

Bio::Graphics::Wiggle -- Binary storage for dense genomic features

=head1 SYNOPSIS

 my $wig = Bio::Graphics::Wiggle->new('./test.wig','writable') or die;

 $offset = $wig->add_segment('chr1',0,100,1000),"\n";
 $wig->add_values(1..10);

 $offset = $wig->add_segment('chr1',2000,100,1000),"\n";
 $wig->add_values([map {$_*10.1} (1..10)]);

 $offset = $wig->add_segment('chr2',0,100,1000),"\n";
 $wig->add_values(1..10);

 undef $wig;
 $wig = Bio::Graphics::Wiggle->new('./test.wig');

 my $iterator = $wig->segment_iterator('chr1',0,500);
 while (my $seg = $iterator->next_segment) {
    print $seg->seqid," ",$seg->start,' ',$seg->step,' ',$seg->span,"\n";
    print "\t",join ' ',$seg->values,"\n";
 }

 my $seg = $sig->segment_iterator('chr2')->next_segment;
 my @values = $seg->values($seg->start,1000);  # fetch span = 1000 bp
}

=cut

# read/write genome tiling data, to be compatible with Jim Kent's WIG format
use strict;
use warnings;
use IO::File;
use Carp 'croak','carp','confess';

use constant HEADER_LEN => 256;
use constant HEADER => '(Z50LLLLl)@'.HEADER_LEN; # seqid, start, end, step, span, next_block
use constant BODY   => 'f';

sub new {
  my $self          = shift;
  my ($path,$write) = @_;
  my $mode = $write ? 'w+' : 'r';
  my $fh = IO::File->new($path,$mode) or die "$path: $!";
  if ($write) { $fh->seek(0,SEEK_END) };
  return bless {fh          => $fh,
		write       => $write,
		last_offset => $fh->tell,
	       }, ref $self || $self;
}

sub fh     { shift->{fh}    }
sub seek   { shift->fh->seek(shift,0) }
sub tell   { shift->fh->tell()        }
sub append { shift->fh->seek(0,2)     }

# args
# (seqid,start,end)
# please use half-open intervals for start and end
sub segment_iterator {
  my $self = shift;
  return Bio::Graphics::WiggleIterator->new($self,@_);
}

sub segment {
  my $self = shift;
  my $offset = shift;
  Bio::Graphics::WiggleSegment->new($self,$offset);
}

sub find_segment {
  my $self = shift;
  my ($offset,$seqid,$start,$end) = @_;

  $offset||= 0;

  $start ||= 0;
  $end   ||= 999_999_999_999;

  my $fh   = $self->fh;

  my ($seqname,$strt,$nd, $step,$span,$next,$found);
  while ($offset >= 0 && !defined $found) {
    warn "offset = $offset";
    $fh->seek($offset,0)                                   or last;
    ($seqname,$strt,$nd, $step,$span,$next) = $self->readheader or last;
    next if defined $seqid && $seqid ne $seqname;
    next unless $end > $strt;
    next if $span && $start >= $nd;
    $found = $offset;
  } continue {
    $offset = $next;
  }
  return $found;
}

sub writable { shift->{write} }
sub current_offset {
  my $self = shift;
  $self->{offset} = shift if @_;
  $self->{offset};
}
sub current_header {
  my $self = shift;
  my $d    = $self->{current_header} || [];
  if (@_) {
    my ($seqname,$start, $end, $step, $span, $next) = @_;
    $self->{current_header} = [$seqname,$start, $end, $step, $span, $next];
  }
  return wantarray ? @$d : $d;
}
sub end {
  my $self = shift;
  $self->{end} = shift if @_;
  $self->{end};
}
sub span {
  my $self = shift;
  $self->{span} = shift if @_;
  $self->{span};
}

sub add_segment {
  my $self = shift;
  die "usage: \$wig->add_segment(\$seqname,\$start,\$step,\$span)" unless @_ >= 3;
  my ($seqname,$start,$step,$span) = @_;
  $span ||= $step;
  die "file not open for writing" unless $self->writable;
  my $fh      = $self->fh;
  my $current = $self->update_current(1);
  $self->writeheader($seqname,$start, $start, $step, $span,-1);
  $self->current_offset($current);
  $self->current_header($seqname,$start, $start, $step, $span,-1);
  return $current;
}

sub update_current {
  my $self = shift;
  my $adding_segment = shift;

  my $fh   = $self->fh;
  my $here = $fh->tell;
  return $here unless $here > 0;

  my ($seqname,$start,$end,$step,$span,$next) = $self->current_header;
  return $here unless $seqname;

  $end = $start + ($here - ($self->current_offset + HEADER_LEN))/4 * $step + $span;
  $next = $here if $adding_segment;

  $self->seek($self->current_offset,0);
  $self->writeheader($seqname,$start,$end,$step,$span,$next);
  $self->seek($here);
  return $here;
}

sub add_values {
  my $self  = shift;

  my $fh    = $self->fh;
  for my $value (@_) {
    my $data  = pack('f*',ref $value ? @$value : $value);
    $fh->print($data) or die "write error: $!";
  }

}

sub end_segment {
  my $self = shift;
  $self->update_current;
}

sub readheader {
  my $self = shift;
  my $fh   = $self->fh;
  my $header;
  $fh->read($header,HEADER_LEN) == HEADER_LEN or die "read failed: $!";
  return unpack(HEADER,$header);
}

sub writeheader {
  my $self = shift;
  my ($seqname,$start,$end, $step,$span,$next) = @_;
  my $fh = $self->fh;
  my $header = pack(HEADER,$seqname,$start,$end, $step,$span,$next);
  $fh->print($header) or die "write failed: $!";
}

sub DESTROY {
  shift->end_segment;
}

package Bio::Graphics::WiggleIterator;

sub new {
  my $self        = shift;
  my $wiggle_file = shift;
  my @search_args = @_;

  return bless {
		search_args => \@search_args,
		wiggle_file => $wiggle_file,
		offset      => 0,
		},ref $self || $self;
}

sub next_segment {
  my $self = shift;
  my $offset = $self->{wiggle_file}->find_segment($self->{offset},@{$self->{search_args}});
  return unless defined $offset;
  my $segment = $self->{wiggle_file}->segment($offset) or return;
  $self->{offset} = $segment->next;
  $segment;
}

package Bio::Graphics::WiggleSegment;

sub new {
  my $self = shift;
  my ($wig_file,$header_pos) = @_;
  $wig_file->seek($header_pos);
  my ($seqid,$start,$end,$step,$span,$next) = $wig_file->readheader() or return;
  return bless {
		seqid   => $seqid,
		start   => $start,
		end     => $end,
		step    => $step,
		span    => $span,
		next    => $next,
		wig     => $wig_file,
		value_offset  => $header_pos + Bio::Graphics::Wiggle::HEADER_LEN,
	       },ref $self || $self;
}

sub seqid  { shift->{seqid} }
sub seq_id { shift->{seqid} }
sub start  { shift->{start} }
sub end    { shift->{end}   }
sub step   { shift->{step}  }
sub span   { shift->{span}  }
sub next   { shift->{next}  }
sub wig    { shift->{wig}   }
sub value_offset { shift->{value_offset} }

sub values {
  my $self = shift;
  my ($start,$end) = @_;

  warn "values($start,$end)";

  $start ||= $self->start;
  $end   ||= $self->end;

  my $step        = $self->step;
  my $span        = $self->span;
  my $block_start = int (($start - $self->start)/$step);
  warn "block_start = $block_start";

  my $read_start  = $self->value_offset + $block_start * 4;
  my $read_length = int(($end-$start+1)/$step) * 4;
  return unless $read_length;
  warn "read_start = $read_start, read_length=$read_length";
  my $data;
  $self->wig->seek($read_start);
  $self->wig->fh->read($data,$read_length) or die "read error: $!";
  return unpack('f*',$data);
}

1;

__END__

=head1 SEE ALSO

L<Bio::Graphics::Panel>,
L<Bio::Graphics::Glyph>,
L<Bio::Graphics::Feature>,
L<Bio::Graphics::FeatureFile>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2007 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut
