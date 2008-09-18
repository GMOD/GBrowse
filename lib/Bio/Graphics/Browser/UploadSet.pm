package Bio::Graphics::Browser::UploadSet;
# API for handling uploaded files

use strict;
use base 'Bio::Graphics::Browser::UserData';

use Bio::Graphics::Browser::Util 'shellwords';
use CGI 'cookie','param';
use Digest::MD5 'md5_hex';
use Carp qw/carp croak/;
use constant DEBUG=>0;

sub new {
  my $package = shift;
  my $config  = shift;
  my $state   = shift;

  warn "initializing uploaded files..." if DEBUG;
  my $self =  bless {
		     config        => $config,
		     state         => $state,
		     files         => {},
		    },ref $package || $package;
  my @urls = grep {/^file:/} @{$state->{tracks}};
  foreach (@urls) {
    warn "adding $_" if DEBUG;
    $self->_add_file($self->name_file($_));
  }
  $self;
}

sub files         { keys %{shift->{files}}         }
sub url2path      { shift->{files}{shift()}        }
sub _add_file     {
  my $self = shift;
  my $url  = shift;
  my $path = shift;
  $self->{files}{$url} = $path;
}
sub _del_file     { delete shift->{files}{shift()} }

sub upload_file {
  my $self       = shift;
  my $filehandle = shift;
  my $state   = $self->state;

  # $fh is a CGI string/filehandle object, so be careful
  warn "upload_file($filehandle), fileno=",
    fileno($filehandle)," content type=$ENV{CONTENT_TYPE}" if DEBUG;
  return unless defined fileno($filehandle);

  my ($filename)  = "$filehandle" =~ /([^\/\\:]+)$/;
  my $url = $self->new_file($filename);

  $url       = $self->new_file($filename);
  my $fh_out = $self->open_file($url,'>') or return;

  my $fh_in   = $self->maybe_unzip($filename,$filehandle) || $filehandle;
  $self->process_uploaded_file($fh_in,$fh_out);
  close $fh_out;
  warn "url = $url, file=",$self->url2path($url) if DEBUG;
  return $url;
}

sub new_file {
  my $self      = shift;
  my $filename  = shift;

  unless ($filename) {
    $filename = $self->new_file_name();
  }

  my $state = $self->state;
  $filename =~ s/^file://;
  my ($url,$path) = $self->name_file($filename);
  warn "url = $url" if DEBUG;
  $self->_add_file($url=>$path);
  return $url;
}

sub new_file_name {
  my $self      = shift;
  my $rand = int(10000*rand);
  return "file:upload.$rand";
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
  my $state = $self->state;

  my $path = $self->url2path($url);
  unless ($path) {  # unregistered cruft file
    (undef,$path) = $self->name_file($url);
  }
  $self->unlink_wigfiles($path);
  unlink $path;
  delete $state->{features}{$url};
  $state->{tracks} = [grep {$_ ne $url} @{$state->{tracks}}];
  warn "clear_uploaded_file(): deleting file = $url" if DEBUG;
  $self->_del_file($url);
}

sub unlink_wigfiles {
  my $self = shift;
  my $path = shift;
  open F,$path or return;
  while (<F>) {
    chomp;
    my ($wigfile) = /wigfile=([^\;]+)/ or next;
    unlink $wigfile;
  }
  close F;
}

sub feature_file {
  my $self = shift;
  my ($url,$coordinate_mapper) = @_;
  my @args              = $coordinate_mapper ? (-map_coords=>$coordinate_mapper) : ();

  my $fh   = $self->open_file($url) or return;
  my $safe = $self->config->setting('allow remote callbacks') || 0;
  my $feature_file = Bio::Graphics::FeatureFile->new(-file             => $fh,
						     -smart_features   => 1,
						     -allow_whitespace => 1,
						     -safe_world       => $safe,
						     @args,
						    );
  close $fh;
  $feature_file->name($url);
  $feature_file;
}

sub annotate {
  my $self              = shift;
  my ($segment,$feature_files,
      $fast_mapper,$slow_mapper,
      $max_segment_length
     ) = @_;  # $segment is not actually used

  my $possibly_too_big  = $segment->length > $max_segment_length;
  my $state             = $self->state;

  for my $url ($self->files) {
    next unless $state->{features}{$url}{visible};
    my $has_overview_sections = $self->probe_for_overview_sections($self->open_file($url));
    next if $possibly_too_big && !$has_overview_sections;
    my $feature_file = $self->feature_file($url,
					   ($has_overview_sections
					    ? $slow_mapper
					    : $fast_mapper)
					  )
      or next;
    $feature_file->name($url);
    $feature_files->{$url} = $feature_file;
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

=item $upload_set = Bio::Graphics::Browser::UploadSet->new($config,$state)

Initialize uploaded files according to the configuration and page
state.  Returns an object.

=item $conf = $upload_set->config

Returns the configuration object.

=item $state = $upload_set->state

Returns the page state hash

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

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut
