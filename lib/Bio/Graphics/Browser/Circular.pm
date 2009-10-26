package Bio::Graphics::Browser::Circular;
# $Id: Circular.pm,v 0.001 2009/08/24  Exp $

=head1 NAME

Bio::Graphics::Browser::Circular -- Extension for the Generic Genome Browser to create circular feature objects

=head1 SYNOPSIS

use Bio::Graphics::Browser::Circular 'make_circular';

my $conf = Bio::Graphics::Browser::Circular->new($db,$start,$stop);

$feature = $conf->make_circular($feature,$segment);

=head1 DESCRIPTION

This package provides methods for creating a Bio::SeqFeatureI-compliant feature object that, 
when displayed in Bio::Graphics::Panel, will appear to wrap around the end of the panel in a circular manner.

The module will only create a circular feature if the following conditions are met: 

  *the region=circular attribute is found in the gff file 
  *either the panel stop is greater than the absolute segment length or the start is negative.

Otherwise, it will return the feature as-is without modification.

The module has two distinct method sets. It can create a generic circular feature, and/or
adjust a segment's start/stop values to allow the Bio::Graphics::Panel to move beyond its absolute boundaries.
The separate function was written exclusively for use in the Generic Genome Browser. 

A standalone Bio::Graphics::Panel object shouldn't require these other methods, 
although they are available for use with:

use Bio::Graphics::Browser::Circular 'adjust';


=head1 METHODS

The remainder of this document describes the methods available to the
programmer.

=cut

use strict;
use base qw(Exporter Bio::Graphics::Browser);


our @EXPORT = qw( new make_circular );

our @EXPORT_OK = qw( adjust_bounds adjust_segment calculate_circular_bounds );

our %EXPORT_TAGS = (
		    all => [ @EXPORT, @EXPORT_OK ],	
		    adjust => [ @EXPORT_OK ],
		    make_circular => [ @EXPORT ],	
		   );



our $VERSION = '0.01';

=head2 new()

my $conf = Bio::Graphics::Browser::Circular->new($db,$start,$stop);

Create a new Bio::Graphics::Browser::Circular object.
Requires a database object and start/stop. Returns a Bio::Graphics::Browser::Circular object.

This method was created for standalone scripts that call Bio::Graphics::Panel directly. 
It is not meant to be used in gbrowse since it already piggybacks on adjust_bounds() which
Bio::Graphics::Browser calls directly.

=cut

sub new {
  my ($class,$db,$start,$stop) = @_;

  my $self = bless {}, $class;

  adjust_bounds($self,$start,$stop,$db);

  return $self;

}

=head2 adjust_bounds()

Checks the gff for circular compatibility, and stores the new circular settings in $self.
Returns either the new calculated start/stop, if the selected area goes beyond the region, or returns the original start/stop.

=cut

sub adjust_bounds {
  my ($self,$start,$stop,$db) = @_;

  my $region = get_circular_region($self,$db);

  return ($start,$stop) if !$region || ( $stop < $region->stop && $start > $region->start );   

  my ($new_start,$new_stop) = $self->calculate_circular_bounds($start,$stop,$region->start,$region->stop);

  $self->{settings}->{start} = $new_start;
  $self->{settings}->{stop} = $new_stop;

  return ($new_start,$new_stop) if $new_stop < $region->stop;

  $self->{absolute_start}  = $region->start;
  $self->{absolute_stop}  = $region->stop;

  return ($new_start,$new_stop);
}

=head2 calculate_circular_bounds()

Calculates the new start/stop points of the panel's selected area relative to the whole region's absolute bounds.

The math follows 3 simple rules:
  * if the area is larger than both absolute bounds (start/stop), shrink it back to the region's bounds.
  * if area start & stop is greater than absolute stop or less than absolute start, take the modulus of the two numbers.
    i.e. shrink the area back to within panel bounds.
  * if the area length is greater than the absolute length, shrink the area to the absolute length relative to area start.

=cut

sub calculate_circular_bounds {

  my $self = shift;

  my ($start,$stop,$absstart,$absstop) = @_; 

  ($start, $stop) = ($absstart,$absstop) if ($start < $absstart && $stop > $absstop);

  ($start, $stop) = (($start % $absstop),($stop % $absstop)) 
    if (($start > $absstop && $stop > $absstop) || 
    ($start < 0 && $stop < 0));

  $start = ($start % $absstop) if $start < (-2*$absstop);
  $stop = ($stop % $absstop) if $stop > (2*$absstop);
  
  ($start,$stop) = (($absstop + $start),($absstop + $stop)) if $start < 0;
  $stop = $start + $absstop - 1 if $stop - $start > $absstop;

  return ($start,$stop);

}

=head2 adjust_segment()

$conf->adjust_segment($segment,$start,$stop);

Changes the segment start/stop. Hack to allow the panel to go beyond it's absolute stop. 
If adjust_segment() is passed a start/stop, it will use those to change the segment. 
Otherwise, it will use the start/stop stored in $self. This method should not be called
without a Bio::Graphics::Browser::Circular object.

=cut

sub adjust_segment { 
  my $self = shift;
  return unless $self->{absolute_stop};
  my $segment = shift;
  my ($start,$stop);

  if (@_) {
    ($start,$stop) = @_; 
  }
  else { 
    ($start,$stop) = ( ($self->{settings}->{stop} - $self->{absolute_stop} + 1),$self->{settings}->{stop} );
  }
  $segment->{start} = $start;
  exists $segment->{end} ? $segment->{end} = $stop : $segment->{stop} = $stop;

  $segment->{origin} = $self->{absolute_stop};
}

=head2 get_circular_region()

Checks the gff file for the region=circular attribute tag 
If present, this should always be in the region line of the gff file.
Returns the whole segment (useful for determining absolute start/stop).
At present this only works on Bio::DB::GFF and Bio::DB::SeqFeature::Store.

This in an internal method used by make_circular() and not meant to be called separately.

=cut

sub get_circular_region {
  my $self = shift;
  my $db = shift;

  my $region; 

  my @attribute_methods_to_try = qw(get_features_by_attribute get_feature_by_attribute);
  for (@attribute_methods_to_try) {
    ($region) = eval { $db->$_(region => 'circular') }; 
    last if defined $region;
  }

  return $region;
}

=head2 encircles_panel()

Checks to see if a subfeature is long enough to display near both the panel end and start, 
effectively wrapping around the panel. Used by the clone() method.
(a subfeatures should be cloned if it is large enough to display twice in the panel)

This in an internal method used by make_circular() and not meant to be called separately.

=cut

sub encircles_panel {
  my $feature = shift;
  my $segment = $feature->{segment};
  my $subfeature = $feature->{subfeatures}[$feature->{number}];
  return ($segment->stop >= ($subfeature->start + $segment->{origin})) ? 1 : 0; 
}

=head2 inside_panel()

Checks to see where a subfeature is relative to its panel. This is used to sort subfeatures
to either add_to_segments() or shift_region_length().
Returns true if a subfeature is within the panel display, and false if it is outside the panel.

This in an internal method used by make_circular() and not meant to be called separately.

=cut

sub inside_panel {
  my $feature = shift;
  my $subfeature = $feature->{subfeatures}[$feature->{number}];
  my $settings = $feature->{settings};
  my $segment = $feature->{segment};
  return ($segment->start <= $subfeature->stop && $segment->stop >= $subfeature->start) ? 1 : 0;
}

=head2 collides()

Compares a single subfeature against its related subfeatures to check if it will cause a glyph collision. 
This is used to determine if two subglyphs that span the origin should be merged 
to make them display as one contiguous segment, ( used by merge_segments() and clone() )
or for clonable segments that are sufficiently long enough to wrap around the panel at certain ranges, 
thus colliding with themselves if duplicated ( used by shift_region_length() ).

This in an internal method used by make_circular() and not meant to be called separately.

=cut

sub collides {
  my $feature = shift;
  my $subfeature = shift;
  my @subfeatures = @_;
  grep {($subfeature->start + $feature->{segment}->{origin}) eq ($_->stop + 1)} @subfeatures;
}

=head2 merge_features()

Merges two subfeatures that span the origin. This prevents the typical panel bump behavior 
that causes two separate glyphs that are close enough together to stagger position 
and bump the second glyph above/below the first. This method extends the glyph length to create a single merged feature.

This in an internal method used by make_circular() and not meant to be called separately.

=cut

sub merge_features {
  my $feature = shift;
  my $id = $feature->{number};
  my @subfeatures = @{$feature->{subfeatures}};
  my $subfeature = $subfeatures[$id]; 
  $id = $id - scalar(@subfeatures)/2;
  $subfeature->{stop} += abs($subfeatures[$id]->stop - $subfeatures[$id]->start);
}

=head2 clone()

Copy any subfeature large enough to encircle the panel.
This method calls Bio::Graphics::Browser's clone_feature() method.

This in an internal method used by make_circular() and not meant to be called separately.

=cut

sub clone {
  my $feature = shift;
  my $segment = $feature->{segment};
  my @subfeatures = @{$feature->{subfeatures}};
  my $subfeature = $subfeatures[$feature->{number}]; 

  return if collides($feature,$subfeature,@subfeatures);

  my $clone = $feature->clone_feature($subfeature);
  $_ += $segment->{origin} for @{$clone}{qw(start stop)}; 
  _add_to_segments($feature,$clone);
}

=head2 shift_region_length()

Shifts a subfeature's start/stop the length of the region. 
This is used to move subfeatures outside the panel to the inside.

This in an internal method used by make_circular() and not meant to be called separately.

=cut

sub shift_region_length {
  my $feature = shift;

  my $segment = $feature->{segment};
  my $origin = $segment->{origin};
  my @subfeatures = @{$feature->{subfeatures}};
  my $subfeature = $subfeatures[$feature->{number}]; 
  
  return if collides($feature,$subfeature,@subfeatures);

  $_ += $origin for @{$subfeature}{qw(start stop)}; 
  return if $subfeature->start > $segment->stop;

  _add_to_segments($feature,$subfeature);
}

=head2 _add_to_segments()

Adds subfeatures to the segments array stored in $self. This combines all the subfeatures together to create one giant feature.

This in an internal method used by make_circular() and not meant to be called separately.

=cut

sub _add_to_segments {
  my $feature = shift;
  my $subfeature = shift;
  push @{$feature->{args}{-segments}}, $subfeature;
}

=head2 add_to_segments()

Adds, merges, and/or clones subfeatures contained within the panel.

This in an internal method used by make_circular() and not meant to be called separately.

=cut

sub add_to_segments {
  my $feature = shift;
  my @subfeatures = @{$feature->{subfeatures}};
  my $subfeature = $subfeatures[$feature->{number}]; 

  my $half = scalar(@subfeatures)/2;
  merge_features($feature) if collides($feature,$subfeatures[$feature->{number}-$half],$subfeature); 

  _add_to_segments($feature,$subfeature);

  clone($feature) if encircles_panel($feature);
}

=head2 make_circular()

$feature = $conf->make_circular($feature,$segment);

Creates a new circular feature from the old feature.
Arguments: feature, whole segment
Returns a new Bio::Graphics::Feature compatible feature, or the original feature if it can't be made circular.

=cut

sub make_circular {
  my $self = shift;
  my $feature = shift;
  return $feature unless $self->{absolute_stop};
  my $segment = shift;

  $self->{feature} = $feature;
  $self->{segment} = $segment;
  @{$self->{subfeatures}} = $feature->segments ? $feature->segments : $feature;

  $self->{args} = { -segments => [],
		    -strand => $feature->strand,
		    -type   => $feature->primary_tag,
		    -source => $feature->source,
		    -name   => $feature->display_name
		  };

  my @subfeatures = @{$self->{subfeatures}};

  for ($self->{number} = 0; 
       $self->{number} < scalar(@subfeatures); 
       $self->{number}++) 
  { inside_panel($self) ? add_to_segments($self) : shift_region_length($self) }

  return Bio::Graphics::Feature->new(%{$self->{args}}) if scalar @{$self->{args}{-segments}};
}

1;
