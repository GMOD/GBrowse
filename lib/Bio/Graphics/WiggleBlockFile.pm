package Bio::Graphics::WiggleBlockFile;

=head1 NAME

Bio::Graphics::WiggleBlockFile -- Binary storage for dense genomic features

=head1 SYNOPSIS

 # all positions are 1-based

 my $wig = Bio::Graphics::WiggleBlockFile->new('./test.wig',
                                      $writeable,
                                     { seqid => $seqid,
                                       step  => $step,
                                       min   => $min,
                                       max   => $max });

 $wig->erase;

 my $seqid = $wig->seqid('new_id');
 my $max   = $wig->max($new_max);
 my $min   = $wig->min($new_min);
 my $step  = $wig->step($new_step);   # data stored at modulus step == 0; all else is blank

 $wig->set_value($position => $value);    # store $value at position (same as above)
 $wig->set_range($start=>$end,$value);    # store $value from $start to $end (same as above)

 my $value = $wig->value($position);      # fetch value from position
 my $values = $wig->values($start,$end);  # fetch range of data from $start to $end
 my $values = $wig->values($start,$end,$samples);  # fetch $samples data points from $start to $end


IMPORTANT NOTE: This implementation is still not right. See
http://genomewiki.ucsc.edu/index.php/Wiggle for a more space-efficient
implementation.

=head1 DESCRIPTION

This module stores "wiggle" style quantitative genome data for display
in a genome browser application. The data for each chromosome (or
contig, or other reference sequence) is stored in a single file in the
following format:

  256 byte header
      50 bytes seqid, zero-terminated C string
      4  byte long integer, value of "step" (explained later)
      4  byte perl native float, the "min" value
      4  byte perl native float, the "max" value
      null padding to 256 bytes for future use

The remainder of the file consists of 8-bit unsigned scaled integer
values. This means that all quantitative data will be scaled to 8-bit
precision!

=head1 METHODS

=head2 Constructor and Accessors

=over 4

=item $wig = Bio::Graphics::WiggleBlockFile->new($filename,$writeable,{options})

Open/create a wiggle-format data file:

  $filename  -- path to the file to open/create
  $writeable -- boolean value indicating whether file is
                writeable. Missing files will only be created
                if $writeable set to a true value.
  {options}  -- hash ref of the following named options, only valid
                when creating a new wig file with $writeable true.

        option name    description                  default
        -----------    -----                        -------
          seqid        name/id of sequence          empty name
          min          minimum value of data points 0
          max          maximum value of data points 255
          step         data density                 1

The "step" can be used to create sparse files to save space. By
default, step is set to 1, in which case a data value will be stored at
each base of the sequence. By setting step to 10, data values will be
stored at every 10th position; when retrieving data, the value stored
at the closest lower step position will be extended through the entire
step interval. For example, consider this step 5 data set:

    1  2  3  4  5  6  7  8  9 10 11 12 13 14
   20  .  .  .  . 60  .  .  .  . 80  .  .  .

We have stored the values "20" "60" and "80" at positions 1, 6 and 11,
respectively. When retrieving this data, it will appear as if
positions 1 through 5 have a value of 20, positions 6-10 have a value
of 60, and positions 11-14 have a value of 80.

Note that no locking is performed by this module. If you wish to allow
multi-user write access to the databases files, you will need to
flock() the files yourself.

=item $seqid = $wig->seqid(['new_id'])
=item $max   = $wig->max([$new_max])
=item $min   = $wig->min([$new_min])
=item $step  = $wig->step([$new_step])

These accessors get or set the corresponding values. Setting is only
allowed if the file was opened for writing. Note that changing the
min, max and step after writing data to the file under another
parameter set may produce unexpected results, as the existing data is
not automatically updated to be consistent.

=back

=head2 Setting Data

=over 4

=item $wig->set_value($position => $value)

This method sets the value at $position to $value. If a step>1 is in
force, then $position will be rounded down to the nearest multiple of
step.

=item $wig->set_range($start=>$end, $value)

This method sets the value of all bases between $start and $end to
$value, honoring step.

=item $sig->set_values($position => \@values)

This method writes an array of values into the datababase beginning at
$position (or the nearest lower multiple of step). If step>1, then
values will be written at step intervals.

=back

=head2 Retrieving Data

=item $value = $wig->value($position)

Retrieve the single data item at position $position, or the nearest
lower multiple of $step if step>1.

=item $values = $wig->values($start=>$end)

Retrieve the values in the range $start to $end and return them as an
array ref. Note that you will always get an array of size
($end-$start+1) even if step>1; the data in between the step intervals
will be filled in.

=item $values = $wig->values($start=>$end,$samples)

Retrieve a sampling of the values between $start and $end. Nothing
very sophisticated is done here; the code simply returns the number of
values indicated in $samples, selected at even intervals from the
range $start to $end. The return value is an arrayref of exactly
$samples values.

=back


=cut

# read/write genome tiling data, to be compatible with Jim Kent's WIG format
use strict;
use warnings;
use IO::File;
use Carp 'croak','carp','confess';

use constant HEADER_LEN => 256;
use constant HEADER => '(Z50LFF)@'.HEADER_LEN; # seqid, step, min, max
use constant BODY   => 'C';

sub new {
  my $class          = shift;
  my ($path,$write,$options) = @_;
  my $mode = $write ? 'w+' : 'r';
  my $fh = IO::File->new($path,$mode) or die "$path: $!";

  $options ||= {};

  my $self = bless {fh      => $fh,
		    write   => $write,
		    dirty   => scalar keys %$options
		   }, ref $class || $class;

  my $stored_options = eval {$self->_readoptions} || {};
  my %merged_options = (%$stored_options,%$options);
  $merged_options{seqid} ||= 'chrUnknown';
  $merged_options{min}   ||= 0;
  $merged_options{max}   ||= 255;
  $merged_options{step}  ||= 1;
  $self->{options} = \%merged_options;
  return $self;
}

sub DESTROY {
  my $self = shift;
  if ($self->{dirty} && $self->{write}) {
    $self->_writeoptions($self->{options});
  }
}

sub erase {
  my $self = shift;
  $self->fh->truncate(HEADER_LEN);
}

sub fh     { shift->{fh}    }
sub seek   { shift->fh->seek(shift,0) }
sub tell   { shift->fh->tell()        }

sub _option {
  my $self   = shift;
  my $option = shift;
  my $d      = $self->{options}{$option};
  if (@_) {
    $self->{dirty}++;
    $self->{options}{$option} = shift;
    delete $self->{scale} if $option eq 'min' or $option eq 'max';
  }
  return $d;
}

sub seqid { shift->_option('seqid',@_) }
sub min   { shift->_option('min',@_) }
sub max   { shift->_option('max',@_) }
sub step  { shift->_option('step',@_) }

sub _readoptions {
  my $self = shift;
  my $fh = $self->fh;
  my $header;
  $fh->read($header,HEADER_LEN) == HEADER_LEN or die "read failed: $!";
  my ($seqid,$step,$min,$max) = unpack(HEADER,$header);
  return { seqid => $seqid,
	   step  => $step,
	   min   => $min,
	   max   => $max };
}

sub _writeoptions {
  my $self    = shift;
  my $options = shift;
  my $fh = $self->fh;
  my $header = pack(HEADER,@{$options}{qw(seqid step min max)});
  $fh->seek(0,0);
  $fh->print($header) or die "write failed: $!";
}

sub set_value {
  my $self = shift;
  croak "usage: \$wig->set_value(\$position => \$value)"
    unless @_ == 2;
  $self->value(@_);
}

sub set_range {
  my $self = shift;
  croak "usage: \$wig->set_range(\$start_position => \$end_position, \$value)"
    unless @_ == 3;
  $self->value(@_);
}

sub value {
  my $self     = shift;
  my $position = shift;

  my $offset   = $self->_calculate_offset($position);
  $self->seek($offset) or die "Seek failed: $!";

  if (@_ == 2) {
    my $end       = shift;
    my $new_value = shift;
    my $scaled_value  = $self->scale($new_value);
    my $step      = $self->step;

    if ($step == 1) { # special efficient case
      $self->fh->print(pack('C*',($scaled_value)x($end-$position+1))) or die "Write failed: $!";
    } else {
      for (my $i=$position; $i<=$end; $i+=$step) {
	$self->seek($offset)                      or die "Seek failed: $!";
	$self->fh->print(pack('C',$scaled_value)) or die "Write failed: $!";
	$offset += 5;
      }
    }
  }

  elsif (@_==1) {
    my $new_value     = shift;
    my $scaled_value  = $self->scale($new_value);
    $self->fh->print(pack('C',$scaled_value)) or die "Write failed: $!";
    return $new_value;
  }

  else { # retrieving data
    my $buffer;
    $self->fh->read($buffer,1) or die "Read failed: $!";
    my $scaled_value = unpack('C',$buffer);
    return $self->unscale($scaled_value);
  }
}

sub _calculate_offset {
  my $self     = shift;
  my $position = shift;
  my $step = $self->step;
  return HEADER_LEN + $step * int(($position-1)/$step);
}

sub set_values {
  my $self = shift;
  croak "usage: \$wig->set_values(\$position => \@values)"
    unless @_ == 2 and ref $_[1] eq 'ARRAY';
  $self->values(@_);
}

# read or write a series of values
sub values {
  my $self  = shift;
  my $start = shift;
  if (ref $_[0] && ref $_[0] eq 'ARRAY') {
    $self->_store_values($start,@_);
  } else {
    $self->_retrieve_values($start,@_);
  }
}

sub _retrieve_values {
  my $self = shift;
  my ($start,$end,$samples) = @_;

  # generate list of positions to sample from
  my $span = ($end-$start+1);
  $samples ||= $span;

  my $offset   = $self->_calculate_offset($start);
  my $step     = $self->step;
  my $interval = $span/$samples;

  $self->seek($offset);
  my $packed_data;
  $self->fh->read($packed_data,$span);

  # pad data up to required amount
  $packed_data .= "\0" x ($span-length($packed_data)) if length $packed_data < $span;

  my @data;
  $#data = $samples-1; # preextend array -- did you know that Perl can do this?
  for (my $i=0; $i<$samples; $i++) {
    my $index = $step * int($i*$interval/$step);
    $data[$i] = unpack('C',substr($packed_data,$index,1));
  }
  return $self->unscale(\@data);
}

sub _store_values {
  my $self = shift;
  my ($position,$data) = @_;

  # where does data start
  my $offset = $self->_calculate_offset($position);
  my $fh     = $self->fh;
  my $step   = $self->step;

  my $scaled = $self->scale($data);

  if ($step == 1) { # special case
    $self->seek($offset);
    my $packed_data = pack('C*',@$scaled);
    $fh->print($packed_data);
  }

  else {
    for my $value (@$data) {
      $self->seek($offset);
      $fh->print(pack('C',$scaled));
      $offset += $step;
    }
  }
}

# zero means "no data"
# everything else is scaled from 1-255
sub scale {
  my $self           = shift;
  my $values         = shift;
  my $scale = $self->_get_scale;
  my $min   = $self->{options}{min};
  if (ref $values && ref $values eq 'ARRAY') {
    my @return = map {
      my $v = 1 + int (($_ - $min)/$scale);
      $v = 1 if $v < 1;
      $v = 255 if $v > 255;
      $v;
    } @$values;
    return \@return;
  } else {
    return int (($values - $min)/$scale);
  }
}

sub unscale {
  my $self         = shift;
  my $values       = shift;
  my $scale = $self->_get_scale;
  my $min   = $self->{options}{min};

  if (ref $values && ref $values eq 'ARRAY') {
    my @return = map {$_ ? (($_-1) * $scale + $min) : 0} @$values;
    return \@return;
  } else {
    return $values * $scale + $min;
  }
}

sub _get_scale {
  my $self = shift;
  unless ($self->{scale}) {
    my $min  = $self->{options}{min};
    my $max  = $self->{options}{max};
    my $span = $max - $min;
    $self->{scale} = $span/254;
  }
  return $self->{scale};
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
