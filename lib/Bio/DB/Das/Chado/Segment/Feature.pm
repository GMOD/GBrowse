=head1 NAME

Bio::DB::Das::Chado::Segment::Feature -- 

=head1 SYNOPSIS

See L<Bio::DB::Das::Chado>.

=head1 DESCRIPTION

=head1 API

=cut

package Bio::DB::Das::Chado::Segment::Feature;

use strict;

use Bio::DB::Chado::Segment;
use Bio::SeqFeatureI;
use Bio::Root::Root;
use Bio::LocationI;

use vars qw($VERSION @ISA $AUTOLOAD);
@ISA = qw(Bio::DB::Chado::Segment Bio::SeqFeatureI 
	  Bio::Root::Root);

$VERSION = '0.01';
#' 

*segments = \&sub_SeqFeature;
my %CONSTANT_TAGS = ();

=head2 new

 Title   : new
 Usage   : $f = Bio::DB::Das::Chado::Segment::Feature->new(@args);
 Function: create a new feature object
 Returns : new Bio::DB::Das::Chado::Segment::Feature object
 Args    : see below
 Status  : Internal

This method is called by Bio::DB::GFF to create a new feature using
information obtained from the GFF database.  It is one of two similar
constructors.  This one is called when the feature is generated
without reference to a RelSegment object, and should therefore use its
default coordinate system (relative to itself).

The 11 arguments are positional:

  $factory      a Bio::DB::GFF adaptor object (or descendent)
  $srcseq       the source sequence
  $start        start of this feature
  $stop         stop of this feature
  $method       this feature's GFF method
  $source       this feature's GFF source
  $score	this feature's score
  $fstrand      this feature's strand (relative to the source
                      sequence, which has its own strandedness!)
  $phase        this feature's phase
  $group        this feature's group
  $db_id        this feature's internal database ID

=cut

# 'This is called when creating a feature from scratch.  It does not have
# an inherited coordinate system.
sub new {
  my $package = shift;
  my ($factory,
      $srcseq,
      $start,$stop,
      $method,$source,
      $score,$fstrand,$phase,
      $group,$db_id,$group_id,
      $tstart,$tstop) = @_;

  my $self = bless { },$package;
  ($start,$stop) = ($stop,$start) if defined($fstrand) and $fstrand eq '-';

  my $class =  $group ? $group->class : 'Sequence';

  @{$self}{qw(factory sourceseq start stop strand class)} =
    ($factory,$srcseq,$start,$stop,$fstrand,$class);

  # if the target start and stop are defined, then we use this information to create 
  # the reference sequence
  # THIS SHOULD BE BUILT INTO RELSEGMENT
  if (0 && $tstart ne '' && $tstop ne '') {
    if ($tstart < $tstop) {
      @{$self}{qw(ref refstart refstrand)} = ($group,$start - $tstart + 1,'+');
    } else {
      @{$self}{'start','stop'} = @{$self}{'stop','start'};
      @{$self}{qw(ref refstart refstrand)} = ($group,$tstop + $stop - 1,'-');
    }

  } else {
    @{$self}{qw(ref refstart refstrand)} = ($srcseq,1,'+');
  }

  @{$self}{qw(type fstrand score phase group db_id group_id absolute)} =
    (Bio::DB::GFF::Typename->new($method,$source),$fstrand,$score,$phase,
     $group,$db_id,$group_id,$factory->{absolute});

  $self;
}

=head2 strand

 Title   : strand
 Usage   : $strand = $f->strand
 Function: get the feature strand
 Returns : +1, 0 -1
 Args    : none
 Status  : Public

Returns the strand of the feature.  Unlike the other methods, the
strand cannot be changed once the object is created (due to coordinate
considerations).

=cut

sub strand {
  my $self = shift;
  return 0 unless $self->{fstrand};
  if ($self->absolute) {
    return Bio::DB::GFF::RelSegment::_to_strand($self->{fstrand});
  }
  return $self->SUPER::strand;
}

=head2 display_id

 Title   : display_id
 Usage   : $display_id = $f->display_id([$display_id])
 Function: get or set the feature display id
 Returns : a Bio::DB::GFF::Featname object
 Args    : a new display_id (optional)
 Status  : Public

This method is an alias for group().  It is provided for
Bio::SeqFeatureI compatibility.

=cut

sub display_name  {
# return 'gene name'

}

=head2 sub_SeqFeature

 Title   : sub_SeqFeature
 Usage   : @feat = $feature->sub_SeqFeature([$method])
 Function: get subfeatures
 Returns : a list of Bio::DB::Das::Chado::Segment::Feature objects
 Args    : a feature method (optional)
 Status  : Public

This method returns a list of any subfeatures that belong to the main
feature.  For those features that contain heterogeneous subfeatures,
you can retrieve a subset of the subfeatures by providing a method
name to filter on.

For AcePerl compatibility, this method may also be called as
segments().

=cut

sub sub_SeqFeature {
  my $self = shift;
  my $type = shift;
  my $subfeat = $self->{subfeatures} or return;
  $self->sort_features;
  my @a;
  if ($type) {
    my $features = $subfeat->{lc $type} or return;
    @a = @{$features};
  } else {
    @a = map {@{$_}} values %{$subfeat};
  }
  return @a;
}

=head2 add_subfeature

 Title   : add_subfeature
 Usage   : $feature->add_subfeature($feature)
 Function: add a subfeature to the feature
 Returns : nothing
 Args    : a Bio::DB::Das::Chado::Segment::Feature object
 Status  : Public

This method adds a new subfeature to the object.  It is used
internally by aggregators, but is available for public use as well.

=cut

sub add_subfeature {
  my $self    = shift;
  my $feature = shift;
  my $type = $feature->method;
  my $subfeat = $self->{subfeatures}{lc $type} ||= [];
  push @{$subfeat},$feature;
}

=head2 attach_seq

 Title   : attach_seq
 Usage   : $sf->attach_seq($seq)
 Function: Attaches a Bio::Seq object to this feature. This
           Bio::Seq object is for the *entire* sequence: ie
           from 1 to 10000
 Example :
 Returns : TRUE on success
 Args    : a Bio::PrimarySeqI compliant object

=cut

sub attach_seq { # nothing!?! what is this for (also probably nothing
                 }


=head2 location

 Title   : location
 Usage   : my $location = $seqfeature->location()
 Function: returns a location object suitable for identifying location 
	   of feature on sequence or parent feature  
 Returns : Bio::LocationI object
 Args    : none

=cut

sub location {
   my $self = shift;
   require Bio::Location::Split unless Bio::Location::Split->can('new');
   require Bio::Location::Simple unless Bio::Location::Simple->can('new');

   my $location;
   if (my @segments = $self->segments) {
       $location = Bio::Location::Split->new(-seq_id => $self->seq_id);
       foreach (@segments) {
          $location->add_sub_Location($_->location);
       }
   } else {
       $location = Bio::Location::Simple->new(-start  => $self->start,
					      -end    => $self->stop,
					      -strand => $self->strand,
					      -seq_id => $self->seq_id);
   }
   $location;
}

=head2 entire_seq

 Title   : entire_seq
 Usage   : $whole_seq = $sf->entire_seq()
 Function: gives the entire sequence that this seqfeature is attached to
 Example :
 Returns : a Bio::PrimarySeqI compliant object, or undef if there is no
           sequence attached
 Args    : none


=cut

sub entire_seq {
    my $self = shift;
    $self->factory->segment($self->sourceseq);
}

=head2 merged_segments

 Title   : merged_segments
 Usage   : @segs = $feature->merged_segments([$method])
 Function: get merged subfeatures
 Returns : a list of Bio::DB::Das::Chado::Segment::Feature objects
 Args    : a feature method (optional)
 Status  : Public

This method acts like sub_SeqFeature, except that it merges
overlapping segments of the same time into contiguous features.  For
those features that contain heterogeneous subfeatures, you can
retrieve a subset of the subfeatures by providing a method name to
filter on.

A side-effect of this method is that the features are returned in
sorted order by their start tposition.

=cut

#'

sub merged_segments {
  my $self = shift;
  my $type = shift;
  $type ||= '';    # prevent uninitialized variable warnings

  my $truename = overload::StrVal($self);

  return @{$self->{merged_segs}{$type}} if exists $self->{merged_segs}{$type};
  my @segs = map  { $_->[0] } 
             sort { $a->[1] <=> $b->[1] ||
		    $a->[2] cmp $b->[2] }
             map  { [$_, $_->start, $_->type] } $self->sub_SeqFeature($type);

  # attempt to merge overlapping segments
  my @merged = ();
  for my $s (@segs) {
    my $previous = $merged[-1] if @merged;
    my ($pscore,$score) = (eval{$previous->score}||0,eval{$s->score}||0);
    if (defined($previous) 
	&& $previous->stop+1 >= $s->start
	&& $previous->score == $s->score
       ) {
      if ($self->absolute && $self->strand < 0) {
	$previous->{start} = $s->{start};
      } else {
	$previous->{stop} = $s->{stop};
      }
      # fix up the target too
      my $g = $previous->{group};
      if ( ref($g) &&  $g->isa('Bio::DB::GFF::Homol')) {
	my $cg = $s->{group};
	$g->{stop} = $cg->{stop};
      }
    } elsif (defined($previous) 
	     && $previous->start == $s->start 
	     && $previous->stop == $s->stop) {
      next;
    } else {
      my $copy = $s->clone;
      push @merged,$copy;
    }
  }
  $self->{merged_segs}{$type} = \@merged;
  @merged;
}

=head2 sub_types

 Title   : sub_types
 Usage   : @methods = $feature->sub_types
 Function: get methods of all sub-seqfeatures
 Returns : a list of method names
 Args    : none
 Status  : Public

For those features that contain subfeatures, this method will return a
unique list of method names of those subfeatures, suitable for use
with sub_SeqFeature().

=cut

sub sub_types {
  my $self = shift;
  my $subfeat = $self->{subfeatures} or return;
  return keys %$subfeat;
}

=head2 Autogenerated Methods

 Title   : AUTOLOAD
 Usage   : @subfeat = $feature->Method
 Function: Return subfeatures using autogenerated methods
 Returns : a list of Bio::DB::Das::Chado::Segment::Feature objects
 Args    : none
 Status  : Public

Any method that begins with an initial capital letter will be passed
to AUTOLOAD and treated as a call to sub_SeqFeature with the method
name used as the method argument.  For instance, this call:

  @exons = $feature->Exon;

is equivalent to this call:

  @exons = $feature->sub_SeqFeature('exon');

=cut

=head2 SeqFeatureI methods

The following Bio::SeqFeatureI methods are implemented:

primary_tag(), source_tag(), all_tags(), has_tag(), each_tag_value().

=cut

sub primary_tag {
  # return cvtype, eg, 'exon'
}

sub source_tag  {
  # returns source (manual curation, computation method, etc
  # not sure where to get this.
}
sub all_tags {
  my $self = shift;
  my @tags = keys %CONSTANT_TAGS;
  # autogenerated methods
  if (my $subfeat = $self->{subfeatures}) {
    push @tags,keys %$subfeat;
  }
  @tags;
}
*get_all_tags = \&all_tags;

sub has_tag {
  my $self = shift;
  my $tag  = shift;
  my %tags = map {$_=>1} $self->all_tags;
  return $tags{$tag};
}
sub each_tag_value {
  my $self = shift;
  my $tag  = shift;
  return $self->$tag() if $CONSTANT_TAGS{$tag};
  $tag = ucfirst $tag;
  return $self->$tag();  # try autogenerated tag
}

sub AUTOLOAD {
  my($pack,$func_name) = $AUTOLOAD=~/(.+)::([^:]+)$/;
  my $sub = $AUTOLOAD;
  my $self = $_[0];

  # ignore DESTROY calls
  return if $func_name eq 'DESTROY';

  # fetch subfeatures if func_name has an initial cap
#  return sort {$a->start <=> $b->start} $self->sub_SeqFeature($func_name) if $func_name =~ /^[A-Z]/;
  return $self->sub_SeqFeature($func_name) if $func_name =~ /^[A-Z]/;

  # error message of last resort
  $self->throw(qq(Can't locate object method "$func_name" via package "$pack"));
}#'

=head2 adjust_bounds

 Title   : adjust_bounds
 Usage   : $feature->adjust_bounds
 Function: adjust the bounds of a feature
 Returns : ($start,$stop,$strand)
 Args    : none
 Status  : Public

This method adjusts the boundaries of the feature to enclose all its
subfeatures.  It returns the new start, stop and strand of the
enclosing feature.

=cut

# adjust a feature so that its boundaries are synched with its subparts' boundaries.
# this works recursively, so subfeatures can contain other features
sub adjust_bounds {
  my $self = shift;
  my $g = $self->{group};

  if (my $subfeat = $self->{subfeatures}) {
    for my $list (values %$subfeat) {
      for my $feat (@$list) {

	# fix up our bounds to hold largest subfeature
	my($start,$stop,$strand) = $feat->adjust_bounds;
	$self->{fstrand} = $strand unless defined $self->{fstrand};
	if ($start <= $stop) {
	  $self->{start} = $start if !defined($self->{start}) || $start < $self->{start};
	  $self->{stop}  = $stop  if !defined($self->{stop})  || $stop  > $self->{stop};
	} else {
	  $self->{start} = $start if !defined($self->{start}) || $start > $self->{start};
	  $self->{stop}  = $stop  if !defined($self->{stop})  || $stop  < $self->{stop};
	}

	# fix up endpoints of targets too (for homologies only)
	my $h = $feat->group;
	next unless $h && $h->isa('Bio::DB::GFF::Homol');
	next unless $g && $g->isa('Bio::DB::GFF::Homol');
	($start,$stop) = ($h->{start},$h->{stop});
	if ($h->strand >= 0) {
	  $g->{start} = $start if !defined($g->{start}) || $start < $g->{start};
	  $g->{stop}  = $stop  if !defined($g->{stop})  || $stop  > $g->{stop};
	} else {
	  $g->{start} = $start if !defined($g->{start}) || $start > $g->{start};
	  $g->{stop}  = $stop  if !defined($g->{stop})  || $stop  < $g->{stop};
	}
      }
    }
  }

  ($self->{start},$self->{stop},$self->strand);
}

=head2 sort_features

 Title   : sort_features
 Usage   : $feature->sort_features
 Function: sort features
 Returns : nothing
 Args    : none
 Status  : Public

This method sorts subfeatures in ascending order by their start
position.  For reverse strand features, it sorts subfeatures in
descending order.  After this is called sub_SeqFeature will return the
features in order.

This method is called internally by merged_segments().

=cut

# sort features
sub sort_features {
  my $self = shift;
  return if $self->{sorted}++;
  my $strand = $self->strand or return;
  my $subfeat = $self->{subfeatures} or return;
  for my $type (keys %$subfeat) {
      $subfeat->{$type} = [map { $_->[0] }
			   sort {$a->[1] <=> $b->[1] }
			   map { [$_,$_->start] }
			   @{$subfeat->{$type}}] if $strand > 0;
      $subfeat->{$type} = [map { $_->[0] }
			   sort {$b->[1] <=> $a->[1]}
			   map { [$_,$_->start] }
			   @{$subfeat->{$type}}] if $strand < 0;
  }
}

=head2 asString

 Title   : asString
 Usage   : $string = $feature->asString
 Function: return human-readabled representation of feature
 Returns : a string
 Args    : none
 Status  : Public

This method returns a human-readable representation of the feature and
is called by the overloaded "" operator.

=cut

sub asString {
  my $self = shift;
  my $type = $self->type;
  my $name = $self->group;
  return "$type($name)" if $name;
  return $type;
#  my $type = $self->method;
#  my $id   = $self->group || 'unidentified';
#  return join '/',$id,$type,$self->SUPER::asString;
}

sub name {
  my $self =shift;
  return $self->group || $self->SUPER::name;
}
