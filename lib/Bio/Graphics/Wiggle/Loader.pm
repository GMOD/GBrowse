package Bio::Graphics::Wiggle::Loader;

=head1 SYNOPSIS

  my $loader = Bio::Graphics::Wiggle::Loader->new('/base/directory/for/wigfiles');
  my $fh = IO::File->new('uploaded_file.txt');
  $loader->load($fh);

  my $gff3_file   = $loader->featurefile('gff3',$method,$source);
  my $featurefile = $loader->featurefile('featurefile');

=head1 USAGE

This module loads Bio::Graphics::Wiggle files from source files that
use Jim Kent's "WIG" format:

http://genome.ucsc.edu/google/goldenPath/help/wiggle.html

Several data sets can be grouped together in a single WIG source
file. The load() method accepts the path to a WIG source file, and
will create one or more .wig databases of quantitative data in the
directory indicated when you created the loader. Call the
featurefile() method to return a text file in either GFF3 or
Bio::Graphics::FeatureFile format, suitable for loading into a gbrowse
database.

=head2 METHODS

=over 4

=item $loader = Bio::Graphics::Wiggle::Loader->new('/base/directory')

Create a new loader. Specify the base directory in which the loaded
.wig files will be created.

=item $loader->load($fh)

Load the data from a source WIG file opened on a filehandle.

=item $data = $loader->featurefile($type [,$method,$source])

Return the data corresponding to a GFF3 or
Bio::Graphics::FeatureFile. The returned file will have one feature
per WIG track, and a properlyl formatted "wigfile" attribute that
directs Bio::Graphics to the location of the quantitative data.

$type is one of "gff3" or "featurefile". In the case of "gff3", you
may specify an optional method and source for use in describing each
feature. In the case of "featurefile", the returned file will contain
GBrowse stanzas that describe a reasonable starting format do display
the data.

=back

=cut

use strict;

use Carp 'croak';
use IO::Seekable;
use Bio::Graphics::Wiggle;
use Text::Shellwords;

sub new {
  my $class = shift;
  my $base  = shift or croak "Usage: Bio::Graphics::Wiggle::Loader->new('/base/path')";
  -d $base && -w _  or croak "$base is not a writeable directory";
  return bless {
		base            => $base,
		tracks          => {},
		trackname       => 'track000',
		track_options   => {},
	       },ref $class || $class;
}

sub basedir  { shift->{base}     }
sub wigfiles { shift->{wigfiles} }
sub featurefile {
  my $self    = shift;
  my $type    = shift;
  my ($method,$source) = @_;
  $method ||= 'microarray_oligo';
  $source ||= '.';

  $type ||= 'featurefile';
  $type =~ /^(gff3|featurefile)$/i or croak "featurefile type must be one of 'gff3' or 'featurefile'";

  my @lines;
  my $tracks = $self->{tracks};

  for my $track (sort keys %$tracks) {
    my $options    = $tracks->{$track}{display_options};
    my $name       = $options->{name} ||= $track;

    if ($type eq 'gff3') {

      push @lines,"##gff-version 3";
    }

    else {

      # stanza
      push @lines,"[$track]";
      push @lines,"glyph       = ".($options->{visibility}=~/pack/
				    ? 'wiggle_density' : 'wiggle_xyplot');
      push @lines,"key         = $options->{name}"
	if $options->{name};
      push @lines,"description = $options->{description}"
	if $options->{description};
      if (my $color = $options->{color}) {
	push @lines,"fgcolor   = ".format_color($color);
      }
      if (my $color = $options->{altColor}) {
	push @lines,"bgcolor   = ".format_color($color);
      }
      if (my ($low,$hi) = split /:/,$options->{viewLimits}) {
	push @lines,"min_score   =  $low";
	push @lines,"max_score   =  $hi";
      }
      if (my ($max,$default,$min) = split/:/,$options->{maxHeightPixels}) {
	push @lines,"height  = $default";
      }
      push @lines,"smoothing        = $options->{windowingFunction}"
	if $options->{windowingFunction};
      push @lines,"smoothingWindow  = $options->{smoothingWindow}"
	if $options->{smoothingWindow};
      push @lines,'';
    }
    push @lines,'';
  }


  for my $track (sort keys %$tracks) {
    my $seqids     = $tracks->{$track}{seqids};
    my $options    = $tracks->{$track}{display_options};
    my $name       = $options->{name};

    # data, sorted by chromosome
    my @seqid  = sort keys %$seqids;

    for my $seqid (@seqid) {

      if ($type eq 'gff3') {
	push @lines,join "\t",($seqid,$source,$method,
			       $seqids->{$seqid}{start},
			       $seqids->{$seqid}{end},
			       '.','.','.',
			       "Name=$name;wigfile=$seqids->{$seqid}{wigpath}"
			      );
      } else {
	push @lines,'';
	push @lines,"reference=$seqid";
	push @lines,"$track $seqid.data $seqids->{$seqid}{start}..$seqids->{$seqid}{end} wigfile=$seqids->{$seqid}{wigpath}";
      }

    }

  }

  return join "\n",@lines;
}

sub load {
  my $self  = shift;
  my $infh  = shift;
  my $format = 'none';

 LINE: while (<$infh>) {
    chomp;
    next if /^#/;
    next unless /\S/;

    if (/^track/) {
      $self->process_track_line();
      next;
    }

    if (/^fixedStep/) {
      $self->process_fixed_step_declaration();
      $format = 'fixed';
    }

    if (/^variableStep/) {
      $self->process_variable_step_declaration();
      $format = 'variable';
    }

    if (/^\S+\s+\d+\s+\d+\s+-?[\dEe.]+/) {
      $format    = 'bed';
    }

    if ($format ne 'none') {
      # remember where we are, find min and max values, return
      my $pos = tell($infh);
      $self->minmax($format,$infh,$format eq 'bed' ? $_ : '');
      seek($infh,$pos,0);

      $self->process_bed($infh,$_)        if $format eq 'bed';
      $self->process_fixedline($infh)     if $format eq 'fixed';
      $self->process_variableline($infh)  if $format eq 'variable';

      $format = 'none';
    }

    redo LINE if /^track/;
  }

  return 1;
}

sub process_track_line {
  my $self      = shift;
  my @tokens    = shellwords($_);
  shift @tokens;
  my %options = map {split/=/} @tokens;
  $options{type} eq 'wiggle_0' or croak "invalid/unknown wiggle track type $options{type}";
  delete $options{type};
  $self->{trackname}++;
  $self->current_track->{display_options} = \%options;
}

sub process_fixed_step_declaration {
  my $self  = shift;
  my @tokens    = shellwords($_);
  shift @tokens;
  my %options = map {split/=/} @tokens;
  exists $options{chrom}        or croak "invalid fixedStep line: need a chrom option";
  exists $options{start}        or croak "invalid fixedStep line: need a start option";
  exists $options{step}         or croak "invalid fixedStep line: need a step  option";
  $self->{track_options} = \%options;
}

sub process_variable_step_declaration {
  my $self  = shift;
  my @tokens    = shellwords($_);
  shift @tokens;
  my %options = map {split/=/} @tokens;
  exists $options{chrom}        or croak "invalid variableStep line: need a chrom option";
  $self->{track_options} = \%options;
}

sub current_track {
  my $self = shift;
  return $self->{tracks}{$self->{trackname}} ||= {};
}

sub minmax {
  my $self   = shift;
  my ($format,$infh,$oops) = @_;
  local $_;

  my $seqids = $self->current_track->{seqids} ||= {};

  if ($format eq 'bed') {
    if ($oops) {
      my ($chrom,$start,$end,$value) = split /\s+/,$oops;
      $self->updatemm($chrom,$value);
    }
    while (<$infh>) {
      chomp;
      last if /^track/;
      next if /^#/;
      my ($chrom,$start,$end,$value) = split /\s+/;
      $self->updatemm($chrom,$value);
    }
  }

  elsif ($format eq 'fixed') {
    while (<$infh>) {
      last if /^track/;
      next if /^#/;
      chomp;
      $self->updatemm($self->{track_options}{chrom},$_);
    }
  }

  elsif ($format eq 'variable') {
    while (<$infh>) {
      last if /^track/;
      next if /^#/;
      chomp;
      my ($start,$value) = split /\s+/;
      $self->updatemm($self->{track_options}{chrom},$value);
    }
  }
}

sub updatemm {
  my $self = shift;
  my ($chrom,$value) = @_;
  my $seqids = $self->current_track->{seqids};
  if (!exists $seqids->{$chrom}{min} ||
      $value < $seqids->{$chrom}{min}) {
    $seqids->{$chrom}{min} = $value;
  }
  if (!exists $seqids->{$chrom}{max} ||
      $value > $seqids->{$chrom}{max}) {
    $seqids->{$chrom}{max} = $value;
  }
}

sub process_bed {
  my $self = shift;
  my $infh = shift;
  my $oops = shift;
  $self->process_bedline($oops) if $oops;
  while (<$infh>) {
    last if /^track/;
    next if /^#/;
    chomp;
    $self->process_bedline($_);
  }
}

sub process_bedline {
  my $self = shift;
  my $line = shift;
  my ($seqid,$start,$end,$value) = split /\s+/,$line;
  $start++;   # to 1-based coordinates
  my $wigfile = $self->wigfile($seqid);
  $wigfile->set_range($start=>$end, $value);

  # update span
  $self->current_track->{seqids}{$seqid}{start} = $start
    unless exists $self->current_track->{seqids}{$seqid}{start}
      and $self->current_track->{seqids}{$seqid}{start} < $start;

  $self->current_track->{seqids}{$seqid}{end}   = $end
    unless exists $self->current_track->{seqids}{$seqid}{end}
      and $self->current_track->{seqids}{$seqid}{end} > $end;
}

sub process_fixedline {
  my $self  = shift;
  my $infh  = shift;
  my $seqid   = $self->{track_options}{chrom};
  my $wigfile = $self->wigfile($seqid);
  my $start   = $self->{track_options}{start};
  my $step    = $self->{track_options}{step};
  # update span
  $self->{track_options}{span} ||= 1;
  $self->current_track->{seqids}{$seqid}{start} = $start;
  $self->current_track->{seqids}{$seqid}{end}   =
    $self->current_track->{seqids}{$seqid}{start} + $self->{track_options}{span} - 1;
  while (<$infh>) {
    last if /^track/;
    next if /^#/;
    chomp;
    my $value = $_;
    $wigfile->set_value($start=>$value);

    # update span
    $self->current_track->{seqids}{$seqid}{end} = $start+$step-1;

    $start += $step;
  }
}

sub process_variableline {
  my $self  = shift;
  my $infh  = shift;
  my $seqid   = $self->{track_options}{chrom};
  my $span    = $self->{track_options}{span} || 1;
  my $wigfile = $self->wigfile($seqid);
  while (<$infh>) {
    last if /^track/;
    next if /^#/;
    chomp;
    my ($start,$value) = split /\s+/;
    $wigfile->set_value($start=>$value);

    # update span
    $self->current_track->{seqids}{$seqid}{start} = $start
      unless exists $self->current_track->{seqids}{$seqid}{start}
	and $self->current_track->{seqids}{$seqid}{start} < $start;

    $self->current_track->{seqids}{$seqid}{end} = $start + ($span-1)
      if $self->current_track->{seqids}{$seqid}{end} < $start + ($span-1);
  }
  $self->current_track->{seqids}{$seqid}{end} ||= $self->current_track->{seqids}{$seqid}{start};
}

sub wigfile {
  my $self  = shift;
  my $seqid = shift;
  my $ts    = time();
  my $current_track = $self->{trackname};
  unless (exists $self->current_track->{seqids}{$seqid}{wig}) {
    my $path    = "$self->{base}/$current_track.$seqid.$ts.wig";
    my $wigfile = Bio::Graphics::Wiggle->new(
					     $path,
					     1,
					     {
					      seqid => $seqid,
					      min  => $self->current_track->{seqids}{$seqid}{min},
					      max  => $self->current_track->{seqids}{$seqid}{max},
					      step => $self->{track_options}{step} || 1,
					      span => $self->{track_options}{span} || $self->{track_options}{step} || 1,
					     },
					    );
    $wigfile or croak "Couldn't create wigfile $wigfile: $!";
    $self->current_track->{seqids}{$seqid}{wig}     = $wigfile;
    $self->current_track->{seqids}{$seqid}{wigpath} = $path;
  }
  return $self->current_track->{seqids}{$seqid}{wig};
}

sub format_color {
  my $rgb = shift;
  my ($r,$g,$b) = split /,/,$rgb;
  return '#'.join '',map {sprintf("%02X",$_)}($r,$g,$b);
}

1;

__END__

=head1 SEE ALSO

L<Bio::Graphics::Wiggle>,
L<Bio::Graphics::Glyph::wiggle_xyplot>,
L<Bio::Graphics::Glyph::wiggle_density>,
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
