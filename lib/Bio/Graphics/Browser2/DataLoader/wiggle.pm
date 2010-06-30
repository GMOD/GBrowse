package Bio::Graphics::Browser2::DataLoader::wiggle;

# $Id$
use strict;
use base 'Bio::Graphics::Browser2::DataLoader';
use File::Basename 'basename','dirname';
use IO::String;

my $HASBIGWIG;

sub start_load {
    my $self   = shift;

    my $loader = Bio::Graphics::Wiggle::Loader::Nosample->new(
	$self->data_path,
	$self->track_name,
	);
    $loader->status_setter($self);
    $self->wigloader($loader);
}
# we are doing nothing during load_line except letting the
# base class make a copy of the file in SOURCES. finish_load()
# will do all the work
sub load_line { }

sub finish_load {
    my $self      = shift;
    my $wigloader = $self->wigloader;

    my $sourcefh  = IO::File->new($self->source_file,'<');
    $self->set_status('indexing data');
    $wigloader->load($sourcefh);


    $self->set_status('creating config file');
    $self->close_conf;  # the featurefile loader will handle the conf for us
    my $featurefiledata = $wigloader->featurefile('featurefile');

    eval "require Bio::Graphics::Browser2::DataLoader::featurefile"
	unless Bio::Graphics::Browser2::DataLoader::featurefile->can('new');
    my $ff_loader   = Bio::Graphics::Browser2::DataLoader::featurefile->new(
	$self->track_name,
	$self->data_path,
	$self->conf_path,
	$self->settings,
	$self->loadid,
	);
    $ff_loader->open_conf;
    $ff_loader->start_load;

    my @ff_lines = split "\n",$featurefiledata;

    $ff_loader->load_line($_) foreach @ff_lines;
    $ff_loader->finish_load;
    $ff_loader->close_conf;
    $self->add_track($_) foreach $ff_loader->tracks;
    $self->wigloader(undef);  # to avoid memory leak
}

sub wigloader {
    my $self = shift;
    my $d    = $self->{wigloader};
    $self->{wigloader} = shift if @_;
    return $d;
}

# overload wiggle loader so that we don't go to genome-wide statistics
# on very large files. Always explicitly calculate stats for file.
package Bio::Graphics::Wiggle::Loader::Nosample;

use base 'Bio::Graphics::Wiggle::Loader';

sub status_setter {
    my $self = shift;
    $self->{__status_setter} = shift;
}

sub set_status {
    my $self = shift;
    my $msg  = shift;

    my $ss = $self->{__status_setter} or return;
    $ss->set_status($msg);
}

sub report_status {
    my $self = shift;
    return unless $self->{__linecount}++ % 10000 == 0;
    $self->set_status("Indexed ",$self->{__linecount}-1," lines");
}

sub load {
    my $self = shift;
    $self->{__linecount} = 0;
    $self->SUPER::load(@_);
}

sub minmax {
  my $self   = shift;
  my ($infh,$bedline) = @_;
  local $_;

  my $transform  = $self->get_transform;

  my $seqids = ($self->current_track->{seqids} ||= {});
  my $chrom  = $self->{track_options}{chrom};

  $self->set_status('calculating descriptive statistics');

  my %stats;
  if ($bedline) {  # left-over BED line
      my @tokens = split /\s+/,$bedline;
      my $seqid  = $tokens[0];
      my $value  = $tokens[-1];
      $value = $transform->($self,$value) if $transform;
      $stats{$seqid} ||= Statistics::Descriptive::Sparse->new();
      $stats{$seqid}->add_data($value);
  }

  my $count;
  while (<$infh>) {
      last if /^track|fixedStep|variableStep/;
      next if /^\#/;
      my @tokens = split(/\s+/,$_) or next;
      my $seqid  = @tokens > 3 ? $tokens[0] : $chrom;
      $self->set_status("chromosome $seqid: line $count") if $count++ % 1000 == 0;
      my $value  = $tokens[-1];
      $value = $transform->($self,$value) if $transform;
      $stats{$seqid} ||= Statistics::Descriptive::Sparse->new();
      $stats{$seqid}->add_data($value);
  }

  for my $seqid (keys %stats) {
      $seqids->{$seqid}{min}    = $stats{$seqid}->min();
      $seqids->{$seqid}{max}    = $stats{$seqid}->max();
      $seqids->{$seqid}{mean}   = $stats{$seqid}->mean();
      $seqids->{$seqid}{stdev}  = $stats{$seqid}->standard_deviation();
  }
}

sub process_bed {
    my $self = shift;
    $self->report_status;
    $self->SUPER::process_bed(@_);
}

sub process_fixedline {
    my $self = shift;
    $self->report_status;
    $self->SUPER::process_fixedline(@_);
}

sub process_variableline {
    my $self = shift;
    $self->report_status;
    $self->SUPER::process_variableline(@_);
}


1;

