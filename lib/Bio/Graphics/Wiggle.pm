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

use constant HEADER_LEN => 256;
use constant HEADER => '(Z50LLLl)@'.HEADER_LEN; # seqid, start, step, span, next_block
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

  warn "start = $start, end = $end";

  $offset ||= 0;

  $start ||= 0;
  $end   ||= 999_999_999_999;

  my $fh   = $self->fh;

  my ($seqname,$strt,$step,$span,$next,$found);
  while ($offset >= 0 && !defined $found) {
    $fh->seek($offset,0)                                   or last;
    ($seqname,$strt,$step,$span,$next) = $self->readheader or last;
    next if defined $seqid && $seqid ne $seqname;
    next unless $end > $strt;
    next if $span && $start >= $strt+$span;
    $found = $offset;
  } continue {
    $offset = $next;
  }
  return $found;
}

sub writable { shift->{write} }
sub last_offset {
  my $self = shift;
  $self->{last_offset} = shift if @_;
  $self->{last_offset};
}

sub add_segment {
  my $self = shift;
  my ($seqname,$start,$step,$span) = @_;
  die "file not open for writing" unless $self->writable;
  my $fh = $self->fh;
  my $current = $fh->tell;

  if ($current > 0) { # need to update the next pointer
    $self->seek($self->last_offset,0);
    my ($sn,$strt,$stp,$spn,$next) = $self->readheader();
    $self->seek($self->last_offset,0);
    $self->writeheader($sn,$strt,$stp,$spn,$current);
    $self->seek($current);
  }

  $self->last_offset($current);
  $self->writeheader($seqname,$start,$step,$span,-1);
  return $current;
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
  return $self->fh->tell;
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
  my ($seqname,$start,$step,$span,$next) = @_;
  my $fh = $self->fh;
  my $header = pack(HEADER,$seqname,$start,$step,$span,$next);
  $fh->print($header) or die "write failed: $!";
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
  my ($seqid,$start,$step,$span,$next) = $wig_file->readheader() or return;
  return bless {
		seqid   => $seqid,
		start   => $start,
		step    => $step,
		span    => $span,
		next    => $next,
		wig     => $wig_file,
		value_offset  => $header_pos + Bio::Graphics::Wiggle::HEADER_LEN,
	       },ref $self || $self;
}

sub seqid  { shift->{seqid} }
sub seq_id { shift->{seqid} }
sub start { shift->{start} }
sub step  { shift->{step}  }
sub span  { shift->{span}  }
sub next  { shift->{next}  }
sub wig   { shift->{wig}   }
sub value_offset { shift->{value_offset} }

sub values {
  my $self = shift;
  my ($start,$span) = @_;

  $start ||= $self->start;
  $span  ||= $self->span - $start;

  my $step        = $self->step;
  my $block_start = int (($start - $self->start)/$step);

  my $read_start  = $self->value_offset + $block_start * 4;
  my $read_length = $span/$step * 4;
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
