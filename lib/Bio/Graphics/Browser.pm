package Bio::Graphics::Browser;
# $Id: Browser.pm,v 1.2 2002-01-31 06:29:39 lstein Exp $

use strict;
use File::Basename 'basename';
use Carp 'carp';
use GD 'gdMediumBoldFont';

use constant DEFAULT_WIDTH => 800;
use vars '$VERSION';
$VERSION = '1.00';

sub new {
  my $class    = shift;
  my $self = bless { },ref($class) || $class;
  $self;
}

sub sources {
  my $self = shift;
  my $conf = $self->{conf} or return;
  return keys %$conf;
}

# get/set current source (not sure if this is wanted)
sub source {
  my $self = shift;
  my $d = $self->{source};
  if (@_) {
    my $source = shift;
    unless ($self->{conf}{$source}) {
      carp("invalid source: $source");
      return $d;
    }
    $self->{source} = $source;
  }
  $d;
}

sub setting {
  my $self = shift;
  $self->config->setting('general',@_);
}

sub citation {
  my $self = shift;
  my $label = shift;
  $self->config->setting($label=>'citation');
}

sub description {
  my $self = shift;
  my $source = shift;
  my $c = $self->{conf}{$source}{data} or return;
  return $c->setting('general','description');
}

sub config {
  my $self = shift;
  my $source = $self->source;
  $self->{conf}{$source}{data};
}

sub default_labels {
  my $self = shift;
  $self->config->default_labels;
}

sub default_label_indexes {
  my $self = shift;
  $self->config->default_label_indexes;
}

sub feature2label {
  my $self = shift;
  my $feature = shift;
  return $self->config->feature2label($feature);
}

sub make_link {
  my $self = shift;
  my $feature = shift;
  return $self->config->make_link($feature);
}

sub labels {
  my $self = shift;
  my $order = shift;
  my @labels = $self->config->labels;
  if ($order) { # custom order
    return @labels[@$order];
  } else {
    return @labels;
  }
}

sub width {
  my $self = shift;
  my $d = $self->{width};
  $self->{width} = shift if @_;
  $d;
}

sub header {
  my $self = shift;
  my $header = $self->config->code_setting(general => 'header');
  return $header->(@_) if ref $header eq 'CODE';
  return $header;
}

sub footer {
  my $self = shift;
  my $footer = $self->config->code_setting(general => 'footer');
  return $footer->(@_) if ref $footer eq 'CODE';
  return $footer;
}

# Generate the image and the box list, and return as a two-element list.
# arguments:
# $segment       A feature iterator that responds to next_feature() methods
# $feature_files A list of Bio::Graphics::FeatureFile objects containing 3d party features
# $show          An array of booleans indicating which labels should be shown
# $options       An array of options, where 0=auto, 1=force bump, 2=force label
# $order         An array of label indexes indicating order of tracks
sub image_and_map {
  my $self = shift;
  my ($segment,$feature_files,$show,$order,$options) = @_;

  my @labels = $self->labels;

  my $width = $self->width;
  my $conf  = $self->config;
  my $max_labels = $conf->setting(general=>'label density') || 10;
  my $max_bump   = $conf->setting(general=>'bump density')  || 50;

  my @feature_types = map {$conf->label2type($labels[$_])} grep {$show->[$_]} (0..@labels-1);

  # Create the tracks that we will need
  my $panel = Bio::Graphics::Panel->new(-segment => $segment,
					-width   => $width,
					-keycolor => 'moccasin',
					-grid => 1,
				       );
  $panel->add_track($segment   => 'arrow',
		    -double => 1,
		    -tick=>2,
		   );

  my (%tracks,%options,@blank_tracks);
  $order ||= [0..$self->labels-1];

  for (my $i = 0; $i < @$order; $i++) {
    my $l        = $order->[$i];
    my $label    = $labels[$l];

    # skip this if it isn't in the @$show array
    next unless $show->[$l];
    # if we don't have a configured label, then it is a third party annotation
    unless ($label) {
      push @blank_tracks,$i;
      next;
    }

    my $track = $panel->add_track(-glyph => 'generic',
				  -key   => $label,
				  $conf->style($label),
				 );
    $tracks{$label}  = $track;
    $options{$label} = $options->[$l];
  }

  if (@feature_types) {  # don't do anything unless we have features to fetch!
    my $iterator = $segment->features(-type=>\@feature_types,-iterator=>1);
    my (%similarity,%feature_count);

    while (my $feature = $iterator->next_feature) {

      my $label = $self->feature2label($feature);
      my $track = $tracks{$label} or next;

      $feature_count{$label}++;

      # special case to handle paired EST reads
      if ($feature->method =~ /^(similarity|alignment)$/) {
	push @{$similarity{$label}},$feature;
	next;
      }
      $track->add_feature($feature);
    }

    # handle the similarities as a special case
    for my $label (keys %similarity) {
      my $set = $similarity{$label};
      my %pairs;
      for my $a (@$set) {
	(my $base = $a->name) =~ s/\.[fr35]$//i;
	push @{$pairs{$base}},$a;
      }
      my $track = $tracks{$label};
      foreach (values %pairs) {
	$track->add_group($_);
      }
    }

    # configure the tracks based on their counts
    for my $label (keys %tracks) {
      next unless $feature_count{$label};
      $options{$label} ||= 0;
      my $do_bump  = $options{$label} >= 1 || $feature_count{$label} <= $max_bump;
      my $do_label = $options{$label} >= 2 || $feature_count{$label} <= $max_labels;
      $tracks{$label}->configure(-bump  => $do_bump,
				 -label => $do_label,
				 -description => $do_label && $tracks{$label}->option('description'),
				);
    }
  }

  # add additional features, if any
  $feature_files ||= [];
  my $offset = 0;
  for my $track (@blank_tracks) {
    my $feature = $order->[$track];

    # Implicitly, the third party features begin at the end of our internal
    # feature label list.
    my $file    = $feature_files->[$feature - @labels];
    next unless $file && ref($file);
    $track += $offset + 1;
    my $inserted = $file->render($panel,$track,$options->[$feature]);
    $offset += $inserted;
  }

  my $boxes    = $panel->boxes;
  my $gd       = $panel->gd;
  return ($gd,$boxes);
}

# generate the overview, if requested, and return it as a GD
sub overview {
  my $self = shift;
  my ($partial_segment) = @_;

  my $segment = $partial_segment->factory->segment($partial_segment->ref);

  my $conf  = $self->config;
  my $width = $self->width;
  my $panel = Bio::Graphics::Panel->new(-segment => $segment,
					-width   => $width,
					-bgcolor => $self->setting('overview bgcolor') || 'wheat',
				       );
  $panel->add_track($segment   => 'arrow',
		    -double    => 1,
		    -label     => sub {"Overview of ".$segment->ref},
		    -labelfont => gdMediumBoldFont,
		    -units     => $self->setting('overview units') || 'M',
		    -tick      => 2,
		   );
  if (my $landmarks  = $self->setting('overview landmarks') || ($conf->label2type('overview'))[0]) {
    my $max_bump   = $conf->setting(general=>'bump density') || 50;

    my @types = split /\s+/,$landmarks;
    my $track = $panel->add_track(-glyph  => 'generic',
				  -height  => 3,
				  -fgcolor => 'black',
				  -bgcolor => 'black',
				  $conf->style('overview'),
				 );
    my $iterator = $segment->features(-type=>\@types,-iterator=>1,-rare=>1);
    my $count;
    while (my $feature = $iterator->next_feature) {
      $track->add_feature($feature);
      $count++;
    }
    $track->configure(-bump  => $count <= $max_bump,
		      -label => $count <= $max_bump
		     );
  }

  my $gd = $panel->gd;
  my $red = $gd->colorClosest(255,0,0);
  my ($x1,$x2) = $panel->map_pt($partial_segment->start,$partial_segment->end);
  my ($y1,$y2) = (0,$panel->height-1);
  $x1 = $x2 if $x2-$x1 <= 1;
  $x2 = $panel->right-1 if $x2 >= $panel->right;
  $gd->rectangle($x1,$y1,$x2,$y2,$red);

  return ($gd,$segment->length);
}

sub read_configuration {
  my $self        = shift;
  my $conf_dir    = shift;
  $self->{conf} ||= {};

  die "$conf_dir: not a directory" unless -d $conf_dir;

  opendir(D,$conf_dir) or die "Couldn't open $conf_dir: $!";
  my @conf_files = map { "$conf_dir/$_" } grep {/\.conf$/} readdir(D);
  close D;

  # try to work around a bug in Apache/mod_perl which appears when
  # running under linux/glibc 2.2.1
  unless (@conf_files) {
    @conf_files = glob("$conf_dir/*.conf");
  }

  # get modification times
  my %mtimes     = map { $_ => (stat($_))[9] } @conf_files;

  for my $file (sort {$b cmp $a} @conf_files) {
    my $basename = basename($file,'.conf');
    next if $self->{conf}{$basename}
      && $self->{conf}{$basename}{mtime} >= $mtimes{$_};

    my $config = Bio::Graphics::BrowserConfig->new(-file => $file) or next;
    $self->{conf}{$basename}{data}  = $config;
    $self->{conf}{$basename}{mtime} = $mtimes{$file};
    $self->{source} = $basename;
  }
  $self->{width} = DEFAULT_WIDTH;
  1;
}

sub merge {
  my $self = shift;
  my ($features,$max_range) = @_;
  $max_range ||= 100_000;

  my (%segs,@merged_segs);
  push @{$segs{$_->ref}},$_ foreach @$features;
  foreach (keys %segs) {
    push @merged_segs,_low_merge($segs{$_},$max_range);
  }
  return @merged_segs;
}

sub _low_merge {
  my ($features,$max_range) = @_;
  my $db = $features->[0]->factory;

  my ($previous_start,$previous_stop,$statistical_cutoff,@spans);

  my @features = sort {$a->low<=>$b->low} @$features;

  # run through the segments, and find the mean and stdev gap length
  # need at least 10 features before this becomes reliable
  if (@features >= 10) {
    my ($total,$gap_length,@gaps);
    for (my $i=0; $i<@$features-1; $i++) {
      my $gap = $features[$i+1]->low - $features[$i]->high;
      $total++;
      $gap_length += $gap;
      push @gaps,$gap;
    }
    my $mean = $gap_length/$total;
    my $variance;
    $variance += ($_-$mean)**2 foreach @gaps;
    my $stdev = sqrt($variance/$total);
    $statistical_cutoff = $stdev * 2;
  } else {
    $statistical_cutoff = $max_range;
  }

  my $ref = $features[0]->ref;

  for my $f (@features) {
    my $start = $f->low;
    my $stop  = $f->high;

    if (defined($previous_stop) &&
	( $start-$previous_stop >= $max_range ||
	  $previous_stop-$previous_start >= $max_range ||
	  $start-$previous_stop >= $statistical_cutoff)) {
      push @spans,$db->segment($ref,$previous_start,$previous_stop);
      $previous_start = $start;
      $previous_stop  = $stop;
    }

    else {
      $previous_start = $start unless defined $previous_start;
      $previous_stop  = $stop;
    }

  }
  push @spans,$db->segment($ref,$previous_start,$previous_stop);
  return @spans;
}


package Bio::Graphics::BrowserConfig;
use strict;
use Bio::Graphics::FeatureFile;
use Text::Shellwords;
use Carp 'croak';

use vars '@ISA';
@ISA = 'Bio::Graphics::FeatureFile';

sub labels {
  grep { $_ ne 'overview' } shift->configured_types;
}

sub label2type {
  my $self = shift;
  my $label = shift or return;
  return shellwords($self->setting($label,'feature'));
}

sub label2index {
  my $self = shift;
  my $label = shift;
  unless ($self->{label2index}) {
    my $index = 0;
    $self->{label2index} = { map {$_=>$index++} $self->labels };
  }
  return $self->{label2index}{$label};
}

sub invert_types {
  my $self = shift;
  my $config  = $self->{config} or return;
  my %inverted;
  for my $label (keys %{$config}) {
    next if $label eq 'overview';   # special case
    my $feature = $config->{$label}{feature} or next;
    foreach (shellwords($feature)) {
      $inverted{$_} = $label;
    }
  }
  \%inverted;
}

sub default_labels {
  my $self = shift;
  my $defaults = $self->setting('general'=>'default features');
  return shellwords($defaults);
}

sub default_label_indexes {
  my $self = shift;
  my @labels = $self->default_labels;
  return map {$self->label2index($_)} @labels;
}

# return a hashref in which keys are the thresholds, and values are the list of
# labels that should be displayed
sub summary_mode {
  my $self = shift;
  my $summary = $self->settings(general=>'summary mode') or return {};
  my %pairs = $summary =~ /(\d+)\s+{([^\}]+?)}/g;
  foreach (keys %pairs) {
    my @l = shellwords($pairs{$_});
    $pairs{$_} = \@l
  }
  \%pairs;
}

# override make_link to allow for code references
sub make_link {
  my $self     = shift;
  my $feature  = shift;
  my $label    = $self->feature2label($feature) or return;
  my $link     = $self->code_setting($label,'link');
  $link        = $self->code_setting(general=>'link') unless defined $link;
  return unless $link;
  return $link->($feature) if ref($link) eq 'CODE';
  return $self->link_pattern($link,$feature);
}


1;

__END__

=head1 NAME

Bio::Graphics::Browser - Support library for Generic Genome Browser

=head1 SYNOPSIS

This is a support library for the Generic Genome Browser
(http://www.gmod.org).

=head1 DESCRIPTION

Documention is pending.

=head1 SEE ALSO

L<Bio::Graphics>, L<Bio::Graphics::Panel>, the GGB installation
documentation.

=head1 AUTHOR

Lincoln Stein <lstein@cshl.org>.

Copyright (c) 2002 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut

THIS IS AN OLDER VERSION OF image_and_map() WHICH IS LESS PIPELINED
NOT SURE WHETHER IT IS ACTUALLY SLOWER THOUGH

# Generate the image and the box list, and return as a two-element list.
sub image_and_map {
  my $self = shift;
  my ($segment,$labels,$order) = @_;
  my %labels = map {$_=>1} @$labels;

  my $width = $self->width;
  my $conf  = $self->config;
  my $max_labels = $conf->setting(general=>'label density') || 10;
  my $max_bump   = $conf->setting(general=>'bump density')  || 50;
  my @feature_types = map {$conf->label2type($_)} @$labels;

  my $iterator = $segment->features(-type=>\@feature_types,
				    -iterator=>1);
  my ($similarity,$other) = $self->sort_features($iterator);

  my $panel = Bio::Graphics::Panel->new(-segment => $segment,
					-width   => $width,
					-keycolor => $self->setting('detailed bgcolor') || 'moccasin',
					-grid => 1,
				       );
  $panel->add_track($segment   => 'arrow',
		    -double => 1,
		    -bump =>1,
		    -tick=>2,
		   );

  # all the rest comes from configuration
  for my $label ($self->labels($order)) {  # use labels() method in order to preserve order in .conf file

    next unless $labels{$label};

    # handle similarities a bit differently
    if (my $set = $similarity->{$label}) {
      my %pairs;
      for my $a (@$set) {
	(my $base = $a->name) =~ s/\.[fr35]$//i;
	push @{$pairs{$base}},$a;
      }
      my $track = $panel->add_track(-glyph =>'segments',
				    -label => @$set <= $max_labels,
				    -bump  => @$set <= $max_bump,
				    -key   => $label,
				    $conf->style($label)
				   );
      foreach (values %pairs) {
	$track->add_group($_);
      }
      next;
    }

    if (my $set = $other->{$label}) {
      $panel->add_track($set,
			-glyph => 'generic',
			-label => @$set <= $max_labels,
			-bump  => @$set <= $max_bump,
			-key   => $label,
			$conf->style($label),

		       );
      next;
    }
  }

  my $boxes    = $panel->boxes;
  my $gd       = $panel->gd;
  return ($gd,$boxes);
}

sub sort_features {
  my $self     = shift;
  my $iterator = shift;

  my (%similarity,%other);
  while (my $feature = $iterator->next_feature) {

    my $label = $self->feature2label($feature);

    # special case to handle paired EST reads
    if ($feature->method =~ /^(similarity|alignment)$/) {
      push @{$similarity{$label}},$feature;
    }

    else {  #otherwise, just sort by label
      push @{$other{$label}},$feature;
    }
  }

  return (\%similarity,\%other);
}


