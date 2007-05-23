package Bio::Graphics::Browser::UploadSet;
# API for handling uploaded files

use strict;
use Bio::Graphics::Browser;
use CGI 'cookie','param';
use Digest::MD5 'md5_hex';
use Bio::Graphics::Wiggle;
use Text::Shellwords;
use Carp 'carp';
use constant DEBUG=>0;

sub new {
  my $package = shift;
  my $config        = shift;
  my $page_settings = shift;

  warn "initializing uploaded files..." if DEBUG;
  my $self =  bless {
		     config        => $config,
		     page_settings => $page_settings,
		     files         => {},
		    },ref $package || $package;
  my @urls = grep {/^file:/} @{$page_settings->{tracks}};
  foreach (@urls) {
    warn "adding $_" if DEBUG;
    $self->_add_file($self->name_file($_));
  }
  $self;
}

sub config        { shift->{config}                }
sub page_settings { shift->{page_settings}         }
sub files         { keys %{shift->{files}}         }
sub url2path      { shift->{files}{shift()}        }
sub _add_file     {
  my $self = shift;
  my $url  = shift;
  my $path = shift;
  $self->{files}{$url} = $path;
}
sub _del_file     { delete shift->{files}{shift()} }
sub readline {
  my $self = shift;
  my $fh   = shift;
  my $line;
  while (<$fh>) {
    chomp;
    next if /^\s*$/; # blank
    next if /^\s*#/; # comment
    s/[\r]//g;  # get rid of carriage returns from Macintosh/DOS systems
    $line .= $_;
    return $line unless $line =~ s/\\$//;
  }
  return $line;
}

sub upload_file {
  my $self       = shift;
  my $filehandle = shift;
  my $settings   = $self->page_settings;

  # $fh is a CGI string/filehandle object, so be careful
  warn "upload_file($filehandle), fileno=",fileno($filehandle)," content type=$ENV{CONTENT_TYPE}" if DEBUG;
  my ($filename)  = "$filehandle" =~ /([^\/\\:]+)$/;
  my $url         = $self->new_file($filename);
  my $fh_out      = $self->open_file($url,'>') or return;
  if (defined fileno($filehandle)) {
    my $first_line = $self->readline($filehandle);
    warn "first_line = $first_line";
    return unless defined $first_line;
    if ($first_line =~ /^track/) {
      $self->upload_ucsc_file($first_line,$filehandle,$fh_out);
    } else {
      $self->upload_feature_file($first_line,$filehandle,$fh_out);
    }
    close $fh_out;
  }
  warn "url = $url, file=",$self->url2path($url); # if DEBUG;
  return $url;
}

sub new_file {
  my $self      = shift;
  my $filename  = shift;

  unless ($filename) {
    my $rand = int(10000*rand);
    $filename = "upload.$rand";
  }

  my $settings = $self->page_settings;
  $filename =~ s/^file://;
  my ($url,$path) = $self->name_file($filename);
  warn "url = $url" if DEBUG;
  push @{$settings->{tracks}},$url unless $settings->{features}{$url};
  $settings->{features}{$url} = {visible=>1,options=>0,limit=>0};
  $self->_add_file($url=>$path);
  return $url;
}

sub open_file {
  my $self = shift;
  my ($url,$mode) = @_;
  $mode ||= "<";
  my $config = $self->config;
  my $path   = $self->url2path($url);
  warn "path = $path" if DEBUG;

  unless (open (F,"${mode}${path}")) {
    carp "Can't open the file named $url.  Perhaps it has been purged? (error: $!)";
    $self->clear_file($url);
    return;
  }

  return \*F;
}

sub clear_file {
  my $self     = shift;
  my $url      = shift;
  my $settings = $self->page_settings;

  my $path = $self->url2path($url);
  unless ($path) {  # unregistered cruft file
    (undef,$path) = $self->name_file($url);
  }
  unlink $path;
  delete $settings->{features}{$url};
  $settings->{tracks} = [grep {$_ ne $url} @{$settings->{tracks}}];
  warn "clear_uploaded_file(): deleting file = $url" if DEBUG;
  $self->_del_file($url);
}

sub name_file {
  my $self = shift;
  my $filename  = shift;
  my $settings  = $self->page_settings;
  my $config    = $self->config;

  # keep last non-[/\:] part of name
  my ($name) = $filename =~ /([^:\\\/]+)$/;
  $name =~ tr/-/_/;
  my $id = $settings->{id} or return;

  my (undef,$tmpdir) = $config->tmpdir($config->source."/uploaded_file/$id");
  my $path      = "$tmpdir/$name";
  my $url       = "file:$name";
  return ($url,$path);
}

sub feature_file {
  my $self = shift;
  my ($url,$coordinate_mapper) = @_;
  my @args              = $coordinate_mapper ? (-map_coords=>$coordinate_mapper) : ();

  my $fh = $self->open_file($url) or return;
  my $feature_file = Bio::Graphics::FeatureFile->new(-file           => $fh,
						     -smart_features =>1,
						     @args,
						    );
  close $fh;
  $feature_file;
}

sub annotate {
  my $self              = shift;
  my ($segment,$feature_files,$fast_mapper,$slow_mapper) = @_;  # $segment is not actually used

  my $settings          = $self->page_settings;

  for my $url ($self->files) {
    next unless $settings->{features}{$url}{visible};
    my $has_overview_sections = $self->probe_for_overview_sections($url);
    my $feature_file = $self->feature_file($url,$has_overview_sections ? $slow_mapper : $fast_mapper) or next;
    $feature_file->name($url);
    $feature_files->{$url} = $feature_file;
  }
}

# ugly hack, but needed for performance gains when looking at really big data sets
sub probe_for_overview_sections {
  my $self = shift;
  my $url  = shift;
  my $fh = $self->open_file($url) or return;
  my $overview;
  while (<$fh>) {
    next unless /\S/;       # skip blank lines
    last unless /[\#\[=]/;  # not a configuration section
    if (/^section\s*=.*(region|overview)/) {
      $overview++;
      last;
    }
  }
  close $fh;
  return $overview;
}

sub upload_feature_file {
  my $self = shift;
  my ($first_line,$in,$out) = @_;
  print $out $first_line,"\n";
  while ($_ = $self->readline($in)) {
    print $out $_,"\n";
  }
}

# this converts .wig files and other UCSC formats into feature files that we can handle
sub upload_ucsc_file {
  my $self = shift;
  my ($track_line,$in,$out) = @_;

  my $done;

  my $date = localtime();
  print $out "#Automatically converted on $date from wiggle format.\n";
  print $out "#Scroll down to the bottom to see track configuration sections.\n";

  my $count  = 0;
  while (!$done) {

    warn "TRACKLINE = $track_line";

    my %options = $track_line =~ /(\S+)=(\S+)/g;
    unless ($options{type} eq 'wiggle_0') {
      carp "not a track definition: $track_line";
      return;
    }
    my %track_options;
    $track_options{key}   = $options{name}              || "your data";
    $track_options{description} = $options{description} || "uploaded data";
    $track_options{name}        = $options{name}     || "your data";
    $track_options{bgcolor}     = $options{color}    || 'black';
    $track_options{fgcolor}     = $options{altColor} || 'black';
    if ($options{maxHeightPixels}) {
      my ($height) = $options{maxHeightPixels} =~ /\d+:(\d+):\d+/;
      $track_options{height} = $height if $height;
    }
    $track_options{graph_type} = exists $options{graphType}
      && $options{graphType} eq 'points' ? 'points' : 'boxes';

    my $wigfile;  # used later
    my $format;
    my (undef,$wigfilename)= $self->name_file("wigfile.".md5_hex(rand));

    # process the declaration line
    defined(my $next_line = $self->readline($in)) or return;
    warn "next_line = $next_line";

    # variable-step data
    if ($next_line =~ /variableStep\s+chrom=(\S+)(?:\s+span=(\d+))?/) {
      $format         = 'variableStep';
      my $reference   = $1;
      my $span        = $2 || 1;  # point-valued data? I am confused
      print $out "reference=$reference\n";
      while ($next_line = $self->readline($in)) {
	last if $next_line =~ /^track/;  # a track line
	my ($start,$score) =  $next_line =~ /^(\d+)\s+(.+)/;
	my $end = $start + $span;
	$start++;  # correct for interbase coordinates
	$track_options{min_score} = $score if !exists $track_options{min_score} || $track_options{min_score} > $score;
	$track_options{max_score} = $score if !exists $track_options{max_score} || $track_options{max_score} < $score;
	print $out "DATASET$count","\t","'$track_options{name}'","\t","$start-$end","\t","score=$score\n"
      }
    }

    # constant-step data
    elsif ($next_line =~ /fixedStep\s+chrom=(\S+)\s+start=(\d+)\s+step=(\d+)(?:\s+span=(\d+))?/) {
      warn "HERE I AM in fixedStep";
      $format       = 'fixedStep';
      my $reference = $1;
      my $start     = $2;
      my $step      = $3;
      my $span      = $4;
      my $end;
      # span is a problem, because it is optional. If it is not given, then we have
      # to figure it out from stepping through the file and fill it in later.
      if ($span) {
	$end = $start+$span;
      }
      else {
	$end = 'XXXXXXXXXXXX'; # 12 digits, enough for 30 human genomes
      }

      # start populating the wig binary file - we may need to fill in the span
      # after we fill the file
      $wigfile ||= Bio::Graphics::Wiggle->new($wigfilename,'writable') or die "Couldn't create wigfile";
      my $offset = $wigfile->add_segment($reference,$start-1,$step,$span||0);

      my $end_filepos;  # this will be fill-in position
      $start++;  # correct for interbase coordinates
      print $out "reference=$reference\n";
      print $out "DATASET$count","\t","'$track_options{name}'","\t","$start-";
      $end_filepos = tell($out);
      print $out $end,"\t","wigfile=$wigfilename;wigstart=$offset","\n";

      $span = 0;
      while ($next_line = $self->readline($in)) {
	last if $next_line =~ /^track/;  # track line
	$wigfile->add_values($next_line);  # add a binary value
	$span += $step;
	$track_options{min_score} = $next_line if !exists $track_options{min_score} || $track_options{min_score} > $next_line;
	$track_options{max_score} = $next_line if !exists $track_options{max_score} || $track_options{max_score} < $next_line;
      }

      # now we can go back and fill in the missing data
      if ($end =~ /XXXX/) { # check for the filler
	$end = $start + $span - 1;
	seek($out,$end_filepos,0); # seek to the place where the filler is
	print $out sprintf("%012d",$end);
	seek($out,0,2);            # seek to end of the file, for next line

	$wigfile->seek($offset);       # back to header position in wig file
	my($a,$b,$c,undef,$d) = $wigfile->readheader();
	$wigfile->seek($offset);
	$wigfile->writeheader($a,$b,$c,$span,$d);
	$wigfile->append;  # seek to end
      }
    }
    elsif ($next_line =~ /^(\S+)\s+(\d+)\s+(\d+)\s+(\S+)/) {  # handle BED lines here
      $format       = 'BED';
      my $reference = $1;
      my $start     = $2;
      my $end       = $3;
      my $score     = $4;
      my $ref       = '';
      print $out "reference=$reference\n";
      print $out join("\t","DATASET$count","'$track_options{name}'",($start+1).'-'.$end,"score=$score"),"\n";
      while (defined ($next_line = $self->readline($in))) {
	last if $next_line =~ /^track/;
	($ref,$start,$end,$score) = split /\s+/,$next_line;
	print $out "reference=$ref" unless $reference eq $ref;
	$reference = $ref;
	print $out join("\t","DATASET$count","'$track_options{name}'",($start+1).'-'.$end,"score=$score"),"\n";	
	$track_options{min_score} = $score if !exists $track_options{min_score} || $track_options{min_score} > $score;
	$track_options{max_score} = $score if !exists $track_options{max_score} || $track_options{max_score} < $score;
      }
    }

    # print track description
    $options{visibility} ||= 'dense';
    if ($format =~ /variableStep|BED/) {
      $track_options{glyph} = 'xyplot'          if     $options{visibility} eq 'full';
      $track_options{glyph} = 'graded_segments' unless $options{visibility} eq 'full';
    } elsif ($format eq 'fixedStep') {
      $track_options{glyph} = 'wiggle_plot'     if     $options{visibility} eq 'full';
      $track_options{glyph} = 'wiggle_density'  unless $options{visibility} eq 'full';
    }
    if (my ($low,$high) = split /:/,$options{viewLimits}) {
      $track_options{min_score}  = $low;
      $track_options{max_score}  = $high;
    }
    print $out "\n";
    print $out "[DATASET$count]\n";
    for (keys %track_options) {
      print $out $_,'=',$track_options{$_},"\n";
    }
    print $out "\n\n";
    $count++;

    if ($next_line =~ /^track/) {
      $track_line  = $next_line;
    } else {
      $done++;
    }
  }
}

1;

__END__

=head1 NAME

Bio::Graphics::Browser::UploadSet -- A set of uploaded feature files

=head1 SYNOPSIS

None.  Used internally by gbrowse & gbrowse_img.

=head1 METHODS

=over 4

=item $upload_set = Bio::Graphics::Browser::UploadSet->new($config,$page_settings)

Initialize uploaded files according to the configuration and page
settings.  Returns an object.

=item $conf = $upload_set->config

Returns the configuration object.

=item $settings = $upload_set->page_settings

Returns the page settings hash

=item $url = $upload_set->upload_file($filehandle)

Given a CGI.pm-style upload filehandle, upload the file to an
anonymous disk file, and return the symbolic trackname URL of the
uploaded file.

=item $url = $upload_set->new_file([$filename])

Create a new empty file with the indicated name and returns its
trackname URL.  If no name is given, one will be generated
automagically.

=item $fh = $upload_set->open_file($url [,$mode])

Attempts to open the URL for reading or writing, depending on the
provided $mode (which is one of ">", "<", ">>", etc).  If successful,
returns the filehandle.

=item $upload_set->clear_file($url)

Clears and unlinks the file.

=item ($url,$path) = $upload_set->name_file($filename)

Given a filename, generates a unique name for it under the user's
temporary upload space.  Returns the trackname URL and a physical path
to the actual file.

=item $upload_set->annotate($segment,$feature_files,$coordinate_mapper)

Annotates the given segment and returns the results in the
$feature_file hash.  The keys of the hash will be set to tracknames
defined in the uploaded files, and the values will be
Bio::Graphics::FeatureFile objects.  The $coordinate_mapper callback
is a code ref to a function that will transform coordinates from
relative to absolute coordinates.  The function takes a reference
sequence name and a list of [$start,$end] coordinate pairs, and
returns a similar function result, except that the sequence name and
coordinates are all in absolute coordinate space.

=back

=head1 SEE ALSO

L<Bio::Graphics::Browser>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2005 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut
