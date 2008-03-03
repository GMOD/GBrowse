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
use CGI 'escape';

use vars '%color_name';

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
  $type =~ /^(gff3|featurefile)$/i 
    or croak "featurefile type must be one of 'gff3' or 'featurefile'";

  my @lines;
  my $tracks = $self->{tracks};

  my $gff3_header;

  for my $track (sort keys %$tracks) {
    my $options    = $tracks->{$track}{display_options};
    my $name       = $options->{name} ||= $track;

    if ($type eq 'gff3') {
      push @lines,"##gff-version 3","" unless $gff3_header++;
    }

    else {

      $options->{visibility} ||= 'pack';
      $options->{color}      ||= '0,0,0';
      $options->{altColor}   ||= '0,0,0';

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
      if (exists $options->{viewLimits} and my ($low,$hi) = split ':',$options->{viewLimits}) {
	push @lines,"min_score   =  $low";
	push @lines,"max_score   =  $hi";
      }
      if (exists $options->{maxHeightPixels} and my ($max,$default,$min) = 
	  split ':',$options->{maxHeightPixels}) {
	push @lines,"height  = $default";
      }
      push @lines,"smoothing        = $options->{windowingFunction}"
	if $options->{windowingFunction};

      # smoothing window max value = 16px
      my $smoothing_window = $options->{smoothingWindow} || 0;
      if ($smoothing_window > 16) {
	croak("The smoothing window is set to $smoothing_window px.  Allowed values are 0-16\n");
      }

      push @lines,"smoothing window = $options->{smoothingWindow}"
	if $options->{smoothingWindow};
      push @lines,'';
    }
  }


  for my $track (sort keys %$tracks) {
    my $seqids     = $tracks->{$track}{seqids};
    my $options    = $tracks->{$track}{display_options};
    my $name       = escape($options->{name});
    my $note       = escape($options->{description});
    my @attributes;
    push @attributes,qq(Name=$name)        if defined $name;
    push @attributes,qq(Note=$note)        if defined $note;

    # data, sorted by chromosome
    my @seqid  = sort keys %$seqids;

    for my $seqid (@seqid) {
      my $attributes = join ';',(@attributes,"wigfile=$seqids->{$seqid}{wigpath}");
      if ($type eq 'gff3') {
	push @lines,join "\t",($seqid,$source,$method,
			       $seqids->{$seqid}{start},
			       $seqids->{$seqid}{end},
			       '.','.','.',
			       $attributes
			      );
      } else {
	push @lines,'';
	push @lines,"reference=$seqid";
	push @lines,"$track $seqid.data $seqids->{$seqid}{start}..$seqids->{$seqid}{end} $attributes";
      }

    }

  }

  return join("\n",@lines)."\n";
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
      $self->process_track_line($_);
      next;
    }

    if (/^fixedStep/) {
      $self->process_fixed_step_declaration($_);
      $format = 'fixed';
    }

    if (/^variableStep/) {
      $self->process_variable_step_declaration($_);
      $format = 'variable';
    }

    if (/^\S+\s+\d+\s+\d+\s+-?[\dEe.]+/) {
      $format    = 'bed';
    }

    if ($format ne 'none') {
      # remember where we are, find min and max values, return
      my $pos = tell($infh);
      $self->minmax($infh,$format eq 'bed' ? $_ : '');
      seek($infh,$pos,0);

      $self->process_bed($infh,$_)        if $format eq 'bed';
      $self->process_fixedline($infh)     if $format eq 'fixed';
      $self->process_variableline($infh)  if $format eq 'variable';

      $format = 'none';
    }

    redo LINE if defined $_ && /^(track|variableStep|fixedStep)/;
  }

  return 1;
}

sub process_track_line {
  my $self      = shift;
  my $line      = shift;
  my @tokens    = shellwords($line);
  shift @tokens;
  my %options = map {split '='} @tokens;
  $options{type} eq 'wiggle_0' or croak "invalid/unknown wiggle track type $options{type}";
  delete $options{type};
  $self->{trackname}++;
  $self->current_track->{display_options} = \%options;
}

sub process_fixed_step_declaration {
  my $self  = shift;
  my $line  = shift;
  my @tokens    = shellwords($line);
  shift @tokens;
  my %options = map {split '='} @tokens;
  exists $options{chrom}        or croak "invalid fixedStep line: need a chrom option";
  exists $options{start}        or croak "invalid fixedStep line: need a start option";
  exists $options{step}         or croak "invalid fixedStep line: need a step  option";
  $self->{track_options} = \%options;
}

sub process_variable_step_declaration {
  my $self  = shift;
  my $line  = shift;
  my @tokens    = shellwords($line);
  shift @tokens;
  my %options = map {split '='} @tokens;
  exists $options{chrom}        or croak "invalid variableStep line: need a chrom option";
  $self->{track_options} = \%options;
}

sub current_track {
  my $self = shift;
  return $self->{tracks}{$self->{trackname}} ||= {};
}

sub minmax {
  my $self   = shift;
  my ($infh,$bedline) = @_;
  local $_;

  my $seqids = $self->current_track->{seqids} ||= {};

  if ($bedline) {  # left-over BED line
      my ($chrom,$start,$end,$value) = split /\s+/,$bedline;
      $seqids->{$chrom}{min} = $value if $seqids->{$chrom}{min} > $value 
	  || !exists $seqids->{$chrom}{min};
      $seqids->{$chrom}{max} = $value if $seqids->{$chrom}{max} < $value 
	  || !exists $seqids->{$chrom}{max};
      while (<$infh>) {
	  chomp;
	  last if /^track/;
	  next if /^\#/;
	  my ($chrom,$start,$end,$value) = split /\s+/;
	  $seqids->{$chrom}{min} = $value if !exists $seqids->{$chrom}{min} || $seqids->{$chrom}{min} > $value;
	  $seqids->{$chrom}{max} = $value if !exists $seqids->{$chrom}{max} || $seqids->{$chrom}{max} < $value;
      }
  }
  
  else {
    my $chrom = $self->{track_options}{chrom};
    return if defined $seqids->{$chrom}{min};  # we've already parsed this chromosome
    my ($min,$max);
    while (<$infh>) {
	last if /^track/;
	next unless /\S/;
	next if /^\#/;
	next if /^(fixedStep|variableStep)/;
	chomp;
	my @tokens = split /\s+/;
	my $value = @tokens > 1 ? $tokens[1]  # variable line
                                : $tokens[0]; # fixed line
	$min = $value if !defined $min || $min > $value;
	$max = $value if !defined $max || $max < $value;
    }
    $seqids->{$chrom}{min} = $min;
    $seqids->{$chrom}{max} = $max;
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
  my $span    = $wigfile->span;

  # update start and end positions
  $self->{track_options}{span} ||= $wigfile->span || 1;
  my $chrom = $self->current_track->{seqids}{$seqid};
  $chrom->{start} = $start 
      if !defined $chrom->{start} || $chrom->{start} > $start;
  my $end = $chrom->{start} + $span - 1;
  $chrom->{end}   = $end
      if !defined $chrom->{end} || $chrom->{end} < $end;

  # write out data in 500K chunks for efficiency
  my @buffer;
  while (<$infh>) {
    last if /^(track|variableStep|fixedStep)/;
    next if /^#/;
    chomp;
    push @buffer,$_;
    if (@buffer >= 500_000) {
      $wigfile->set_values($start=>\@buffer);
      @buffer = ();
      my $big_step = $step * @buffer;
      $start += $big_step;
      $self->current_track->{seqids}{$seqid}{end} = $start + $big_step - 1 + $span;
    }

  }
  $wigfile->set_values($start=>\@buffer) if @buffer;
  $self->current_track->{seqids}{$seqid}{end} = $start + @buffer*$step - 1 + $span;
}

sub process_variableline {
  my $self  = shift;
  my $infh  = shift;
  my $seqid   = $self->{track_options}{chrom};
  my $chrom   = $self->current_track->{seqids}{$seqid};
  my $wigfile = $self->wigfile($seqid);
  my $span    = $wigfile->span;
  while (<$infh>) {
    last if /^(track|variableStep|fixedStep)/;
    next if /^#/;
    chomp;
    my ($start,$value) = split /\s+/ or next;
    $wigfile->set_value($start=>$value);

    # update span
    $chrom->{start} = $start 
	if !defined $chrom->{start} || $chrom->{start} > $start;
    my $end = $start + $span - 1;
    $chrom->{end}   = $end
	if !defined $chrom->{end} || $chrom->{end} < $end;

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
  my ($r,$g,$b) = split ',',$rgb;
  my $hex = '#'.join '',map {sprintf("%02X",$_)}($r,$g,$b);
  return translate_color($hex);
}

# use English names for the most common colors
sub translate_color {
  my $clr = shift;
  unless  (%color_name) {
    while (<DATA>) {
      chomp;
      my ($hex,$name) = split;
      $color_name{$hex} = $name;
    }
  }
  return $color_name{$clr} || $clr;
}

1;


__DATA__
#000000 black
#FFFFFF white
#0000FF blue
#00FF00 green
#FF0000 red
#FFFF00 yellow
#00FFFF cyan
#FF00FF magenta
#C0C0C0 gray


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
