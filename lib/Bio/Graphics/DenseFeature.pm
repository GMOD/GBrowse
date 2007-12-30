package Bio::Graphics::DenseFeature;

=head1 NAME

Bio::Graphics::DenseFeature -- Low-level access to dense quantitative data

=head1 SYNOPSIS

 my $dense = Bio::Graphics::DenseFeature->new(-fh         => $file_handle,          # required
                                              -fh_offset  => $offset_in_bytes,      # defaults to zero
                                              -start      => $offset_in_bases,      # defaults to 1
                                              -recsize    => $record_size_in_bytes, # defaults to 1
                                              -smooth     => $smoothing_function,   # {'none','max','min','mean','median'}, defaults to "none"
                                              -window     => $smoothing_window,     # defaults to 1/100 of (stop-start)
                                              -unpack     => $unpack_pattern);      # defaults to 'C'

 my @data  = $dense->values($start,$end);  # one-based coordinates!

=cut

# read/write genome tiling data, to be compatible with Jim Kent's WIG format
use strict;
use warnings;
use IO::File;
use Carp 'croak','carp','confess';


use constant DEFAULT_OFFSET   => 0;
use constant DEFAULT_START    => 1;
use constant DEFAULT_RECSIZE  => 1;
use constant DEFAULT_SMOOTH   => 'none';
use constant DEFAULT_UNPACK   => 'C';

my %smooth_funcs = (
		    'median' => \&_median,
		    'mean'   => \&_mean,
		    'max',   => \&_max,
		    'min'    => \&_min,
		    );


sub new {
  my $class         = shift;
  my %args          = @_;
  my $fh            = $args{-fh}    or croak "must provide filehandle";
  my $offset        = $args{-offset}  || DEFAULT_OFFSET;
  my $start         = $args{-start}   || DEFAULT_START;
  my $recsize       = $args{-recsize} || DEFAULT_RECSIZE;
  my $unpack        = $args{-unpack}  || DEFAULT_UNPACK;
  my $smooth        = $args{-smooth}  || DEFAULT_SMOOTH;
  my $window        = $args{-window};
  my $self          = bless {fh      => $fh,
			     offset  => $offset,
			     start   => $start,
			     recsize => $recsize,
			     unpack  => $unpack,
			    },$class;
  $self->smoothing($smooth);
  $self->window($window);
  return $self;
}

sub fh     { shift->{fh}    }
sub seek   { shift->fh->seek(shift,0) }
sub tell   { shift->fh->tell()        }
sub append { shift->fh->seek(0,2)     }

sub offset  { shift->{offset}  }
sub start   { shift->{start}   }
sub recsize { shift->{recsize} }
sub unpack_pattern { shift->{unpack} }
sub smoothing {
  my $self = shift;
  my $d    = $self->{smooth};
  $self->{smooth} = shift if @_;
  $d;
}
sub window {
  my $self = shift;
  my $d    = $self->{window};
  $self->{window} = shift if @_;
  $d;
}

sub values {
  my $self          = shift;
  my ($start,$end)  = @_;
  my $size          = $self->recsize;
  my $read_start    = $self->offset + ($start-1) * $size;
  my $bytes_to_read = ($end-$start+1) * $size;
  $self->seek($read_start,0);
  my $data;
  my $bytes = $self->fh->read($data,$bytes_to_read);
  die "read error: $!" unless $bytes == $bytes_to_read;
  my $pattern = "(".$self->unpack_pattern.")*";
  my @data = unpack $pattern,$data;
  my $result = $self->smooth(\@data);
  return wantarray ? @$result: $result;
}

sub smooth {
  my $self = shift;
  my $data = shift;
  my $smoothing = $self->smoothing;
  return $data if $smoothing eq 'none';
  my $window    = $self->window;

  my $func = $smooth_funcs{$smoothing} 
    or die "unknown smooth function: $smoothing";
  $func->($data,$window);  # changes $data in situ
  return $data;
}

sub _mean {
  my ($data,$window) = @_;
  my $offset = int($window/2 + 1);
  my @data = @{$data}[0..$window-1];

  my $rolling_value = 0;
  $rolling_value += $_ foreach @data;
  $data->[$offset] = $rolling_value / $window;

  for (my $i=$offset+1; $i<@$data-$offset; $i++) {
    my $previous = shift @data;
    my $new      = $data->[$i+$offset];
    push @data, $new;
    $rolling_value -= $previous;
    $rolling_value += $new;
    $data->[$i] = $rolling_value/$window;
  }
}

sub _median {
  my ($data,$window) = @_;
  my @data = @{$data}[0..$window-1];

  my $rolling_value = find_median(\@data);

  for (my $i=1; $i<@$data-$window; $i++) {
    my $previous = shift @data;
    my $new      = $data->[$i+$window];
    push @data,$new;
    $rolling_value = find_median(\@data);
    $data->[$i] = $rolling_value;
  }
}

sub _max {
  my ($data,$window) = @_;
  my @data = @{$data}[0..$window-1];

  my $rolling_value = find_max(\@data);
  $data->[0] = $rolling_value;

  for (my $i=1; $i<@$data-$window; $i++) {
    my $previous = shift @data;
    my $new      = $data->[$i+$window];
    push @data,$new;
    $rolling_value = find_max(\@data) if $previous == $rolling_value;
    $data->[$i]    = $rolling_value;
  }
}

sub _min {
  my ($data,$window) = @_;
  my @data = @{$data}[0..$window-1];

  my $rolling_value = find_min(\@data);
  $data->[0] = $rolling_value;

  for (my $i=1; $i<@$data-$window; $i++) {
    my $previous = shift @data;
    my $new      = $data->[$i+$window];
    push @data,$new;
    $rolling_value = find_min(\@data) if $previous == $rolling_value;
    $data->[$i]    = $rolling_value;
  }
}

sub find_max {
  my $data = shift;
  my $val = $data->[0];
  foreach (@$data) {
    $val = $_ if $_ > $val;
  }
  $val
}

sub find_min {
  my $data = shift;
  my $val = $data->[0];
  foreach (@$data) {
    $val = $_ if $_ < $val;
  }
  $val
}

sub find_median {
  my $data = shift;
  my @data = sort {$a <=> $b} @$data;
  my $middle = @data/2;
  if (@data % 2) {
    return $data[$middle];
  } else {
    return ($data[$middle-1]+$data[$middle])/2;
  }
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

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut
