package Bio::Graphics::Browser2::ExternalData;

# base class for Bio::Graphics::Browser::RemoteSet;

use strict;
use Carp 'croak';
use Bio::Graphics::Browser2::Util 'error';
use Bio::Graphics::Wiggle;

use constant DEBUG => 0;

sub new {
  croak 'virtual base class';
}

sub uploadid      { croak "virtual method" }
sub config        { shift->{config}        }
sub state         { shift->{state}         }

sub readline {
  my $self = shift;
  my $fh   = shift;
  my $line;
  while (<$fh>) {
    chomp;
    next if /^\s*$/; # blank
    next if /^\s*#/; # comment
    s/[\r]//g;       # get rid of carriage returns from Macintosh/DOS systems
    $line .= $_;
    return $line unless $line =~ s/\\$//;
  }
  return $line;
}


# this converts .wig files and other UCSC formats into feature files that we can handle
sub convert_ucsc_file {
  my $self = shift;
  my ($in,$out) = @_;

  eval "require Bio::Graphics::Wiggle::Loader;1" 
    unless Bio::Graphics::Wiggle::Loader->can('new');

  my $dummy_name = $self->name_file('foo');
  $dummy_name    =~ s/foo$//; # get the directory part only!

  eval {
      my $loader = Bio::Graphics::Wiggle::Loader->new($dummy_name);
      $loader->load($in);
      my $featurefile = $loader->featurefile('featurefile');
      print $out $featurefile;
  };
  error($@) if $@;
}

sub convert_feature_file {
  my $self = shift;
  my ($in,$out) = @_;
  while ($_ = <$in>) {
      chomp;
      print $out $_,"\n";
  }
}

sub process_uploaded_file {
  my $self          = shift;
  my ($infh,$outfh) = @_;

  local $/ = $self->_guess_eol($infh);

  my $pos = tell($infh);
  my $first_line = $self->readline($infh);
  return unless defined $first_line;
  seek($infh,$pos,0);
  if ($first_line =~ /^(track|browser)/) {
    $self->convert_ucsc_file($infh,$outfh);
  } else {
    $self->convert_feature_file($infh,$outfh);
  }
}

sub maybe_unzip {
    my $self     = shift;
    my $filename = shift;
    my $fh       = shift;

    # If the file is in gzip format,
    # try to intercept and decompress the file
    if ($filename =~ /^(.+)\.gz$/) {
	$fh ||= IO::File->new($filename);
	$fh->binmode(1) if $fh->can('binmode');
	require File::Temp;
	my $fname = File::Temp->tmpnam;
	my $unzip = IO::File->new("|gunzip -c > $fname") or die $!;
	$unzip->binmode(1);
	my $buffer;
	$unzip->print($buffer) while read($fh,$buffer,1024);
	$unzip->close;
	$fh = IO::File->new($fname);
	$fh->binmode(1);
	unlink $fname;
	return $fh;
    }
    return;
}

sub _guess_eol {
    my $self = shift;
    my $fh   = shift;
    my $buffer;
    my $pos = tell($fh);
    read($fh,$buffer,1024);
    seek($fh,$pos,0);   # back to where we were
    return "\015\012" if $buffer =~ /\015\012/;
    return "\015"     if $buffer =~ /\015/;
    return "\012"     if $buffer =~ /\012/;
}

sub name_file {
  my $self      = shift;
  my $filename  = shift;
  my $strip     = shift;

  my $state     = $self->state;
  my $config    = $self->config;
  my $id        = $self->uploadid || $state->{userid} or return;

  my ($url,$path) = $self->file2path($config,$id,$filename,$strip);
  warn "name_file() returns => ($url,$path)" if DEBUG;
  return ($url,$path);
}

sub file2path {
    my $self  = shift;
    my ($config,$id,$filename,$strip) = @_;
    $strip        = 1 unless defined $strip;    

    # keep last non-[\\\/:] part of name
    my ($name) = $strip ? $filename =~ /([^:\\\/]+)$/ : $filename;
    $name                  =~ tr!-/!__!; # get rid of hyphens and slashes
    my $tmpdir    = $config->userdata($id);
    my $path      = File::Spec->catfile($tmpdir,$name);
    my $url       = "file:$name";
    return wantarray ? ($url,$path) : $path;
}

sub http_proxy {
  my $self   = shift;
  my $config = $self->config;
  my $proxy  = $config->setting('proxy') || '';
  return $config->setting('http proxy') || $proxy || '';

}

sub ftp_proxy {
  my $self   = shift;
  my $config = $self->config;
  my $proxy  = $config->setting('proxy') || '';
  return $config->setting('ftp proxy') || $proxy || '';
}

# ugly hack, but needed for performance gains when looking at really big data sets
sub probe_for_overview_sections {
  my $self = shift;
  my $fh   = shift;
  my $overview;
  my $pos = tell($fh);
  while (<$fh>) {
    next unless /\S/;       # skip blank lines
    last unless /[\#\[=]/;  # not a configuration section
    if (/^section\s*=.*(region|overview)/) {
      $overview++;
      last;
    }
  }
  seek($fh,$pos,0);
  return $overview;
}


1;
