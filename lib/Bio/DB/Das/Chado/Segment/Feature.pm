=head1 NAME

Bio::DB::Das::Chado::Segment::Feature -- 

=head1 SYNOPSIS

See L<Bio::DB::Das::Chado>.

=head1 DESCRIPTION

=head1 API

=cut

package Bio::DB::Das::Chado::Segment::Feature;

use strict;

use Bio::DB::Das::Chado::Segment;
use Bio::SeqFeatureI;
use Bio::Root::Root;
use Bio::LocationI;

use vars qw($VERSION @ISA $AUTOLOAD);
@ISA = qw(Bio::DB::Das::Chado::Segment Bio::SeqFeatureI 
	  Bio::Root::Root);

$VERSION = '0.02';
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

This method is called by Bio::DB::Das::Chado::Segment to create a new feature using
information obtained from the chado database.  

The 10 arguments are positional:

  $factory      a Bio::DB::Das::Chado adaptor object (or descendent)
  $parent       the parent feature object (if it exists)
  $srcseq       the source sequence
  $start        start of this feature
  $stop         stop of this feature
  $type         this feature's type (gene, arm, exon, etc)
  $strand       this feature's strand (relative to the source
                      sequence, which has its own strandedness!)
  $group        this feature's group (a GFF holdover)
  $db_id        this feature's internal database ID (feature.feature_id)
  $feature_id   the parents feature_id (srcfeature_id)

=cut

# 'This is called when creating a feature from scratch.  It does not have
# an inherited coordinate system.
sub new { 
  my $package = shift;
  my ($factory,
      $parent,
      $srcseq,
      $start,$end,
      $type,
      $strand,
      $group,       # ie, gene name  (GFF legacy)
      $db_id,$feature_id) = @_;

  my $self = bless { },$package;

#check that this is what you want!
  #($start,$end) = ($end,$start) if defined($strand) and $strand == -1;

  @{$self}{qw(factory parent sourceseq start end strand )} =
    ($factory,$parent,$srcseq,$start,$end,$strand);

  @{$self}{qw(type group db_id absolute)} =
    ($type,$group,$db_id,$factory->{absolute});

  @{$self}{qw(feature_id srcfeature_id score ) } = 
    ($feature_id,$parent->{srcfeature_id},0);

  $self;
}

sub length {
  my $self = shift;
  return $self->end - $self->start +1 ;
}

sub type {shift->{type}}
sub seq_id { shift->{sourceseq} }
*info = \&display_name; #for compatability with broken generic glyphs

=head2 group

 Title   : group
 Usage   : $group = $f->group([$new_group])
 Function: get or set the feature group
 Returns : A string (feature name)
 Args    : a new group (optional)
 Status  : Public

This method gets or sets the feature group.  The group is a
hold over from GFF and is mostly synonymous with name.

=cut

sub group  { 
  my $self = shift;
  my $d    = $self->{group};
  $self->{group} = shift if @_;
  $d;
}


=head2 method

 Title   : method
 Usage   : $method = $f->method([$newmethod])
 Function: get or set the feature method
 Returns : a string
 Args    : a new method (optional)
 Status  : Public

This method gets the feature type (analogous to method, like in GFF). 

=cut

sub method { 
  my $self = shift;
  return $self->{type}
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
  return 0 unless $self->{strand};
  return $self->{strand};
}

=head2 display_id

 Title   : display_id
 Usage   : $display_id = $f->display_id([$display_id])
 Function: get or set the feature display id
 Returns : a string (the feature name)
 Status  : Public

This method is an alias for group().  It is provided for
Bio::SeqFeatureI compatibility.

=cut

sub display_name  { 
  my $self = shift;
  return $self->{group}
}

=head2 sub_SeqFeature

 Title   : sub_SeqFeature
 Usage   : @feat = $feature->sub_SeqFeature([$type])
 Function: get subfeatures
 Returns : a list of Bio::DB::Das::Chado::Segment::Feature objects
 Args    : a feature method (optional)
 Status  : Public

This method returns a list of any subfeatures that belong to the main
feature.  For those features that contain heterogeneous subfeatures,
you can retrieve a subset of the subfeatures by providing a type 
to filter on.

For AcePerl compatibility, this method may also be called as
segments().

=cut

sub sub_SeqFeature {
  my $self = shift;
  my $type = shift;

  my $parent_id = $self->{feature_id};

  my $typewhere = '';
  if ($type) {
    $type = lc $type;
    my %termhash = %{$self->{factory}->{cvterm_id}};
    $typewhere = " and child.type_id = $termhash{$type} ";
  }

  my $handle = $self->{factory}->{dbh};

#  print "$parent_id\n";
#  print "$handle\n";

#  $self->{factory}->{dbh}->trace(2);

  my $sth = $self->{factory}->{dbh}->prepare("
    select child.feature_id, child.name, child.type_id, parent.name as pname,
           childloc.min, childloc.max, childloc.strand, childloc.phase
    from feature as parent
    inner join
      feature_relationship as fr0 on
        (parent.feature_id = fr0.subjfeature_id)
    inner join
      feature as child on
        (child.feature_id = fr0.objfeature_id)
    inner join
      featureloc as childloc on
        (child.feature_id = childloc.feature_id)
    where parent.feature_id = $parent_id
          $typewhere;
    ");
  $sth->execute or $self->throw("subfeature query failed"); 

  my @features;
  my %termname = %{$self->{factory}->{cvtermname}};
  while (my $hashref = $sth->fetchrow_hashref) {

    my $stop  = $$hashref{max};
    my $start = $$hashref{min};

    my $feat = Bio::DB::Das::Chado::Segment::Feature->new (
                       $self->{factory},
                       $self,
                       $self->ref,
                       $start,$stop,
                       $termname{$$hashref{type_id}},
                       $$hashref{strand},
                       $$hashref{name},
                       $$hashref{name}, $$hashref{feature_id}); 

    push @features, $feat;

  }
#  my $subfeat = $self->{subfeatures} or return;
#  $self->sort_features;
#  my @a;
#  if ($type) {
#    my $features = $subfeat->{lc $type} or return;
#    @a = @{$features};
#  } else {
#    @a = map {@{$_}} values %{$subfeat};
#  }

  
  return @features;
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
#  my $feature = shift;
#  my $type = $feature->method;
#  my $subfeat = $self->{subfeatures}{lc $type} ||= [];
#  push @{$subfeat},$feature;
  $self->throw("not implemented");
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

sub attach_seq { # nothing!?! what is this for (also probably nothing warn "in sub attach_seq { # nothing!?! what is this for (also probably nothing\n";
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
    $self->SUPER::seq();
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
   #   my $g = $previous->{group};
   #   if ( ref($g) &&  $g->isa('Bio::DB::GFF::Homol')) { # always false here
   #     my $cg = $s->{group};
   #     $g->{stop} = $cg->{stop};
   #   }
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

=head2 clone

 Title   : clone
 Usage   : $feature = $f->clone
 Function: make a copy of the feature
 Returns : a new Bio::DB::Das::Chado::Segment::Feature object
 Args    : none
 Status  : Public

This method returns a copy of the feature.

=cut

sub clone { 
  my $self = shift;
  my $clone = $self->SUPER::clone;

  if (ref(my $t = $clone->type)) {
    my $type = $t->can('clone') ? $t->clone : bless {%$t},ref $t;
    $clone->type($type);
  }

  if (ref(my $g = $clone->group)) {
    my $group = $g->can('clone') ? $g->clone : bless {%$g},ref $g;
    $clone->group($group);
  }

  if (my $merged = $self->{merged_segs}) {
    $clone->{merged_segs} = { %$merged };
  }

  $clone;
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
   shift->{type};
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
	$self->{strand} = $strand unless defined $self->{strand};
	if ($start <= $stop) {
	  $self->{start} = $start if !defined($self->{start}) || $start < $self->{start};
	  $self->{stop}  = $stop  if !defined($self->{stop})  || $stop  > $self->{stop};
	} else {
	  $self->{start} = $start if !defined($self->{start}) || $start > $self->{start};
	  $self->{stop}  = $stop  if !defined($self->{stop})  || $stop  < $self->{stop};
	}

	# fix up endpoints of targets too (for homologies only)
#	my $h = $feat->group;
#	next unless $h && $h->isa('Bio::DB::GFF::Homol'); # always false (for now)
#	next unless $g && $g->isa('Bio::DB::GFF::Homol');
#	($start,$stop) = ($h->{start},$h->{stop});
#	if ($h->strand >= 0) {
#	  $g->{start} = $start if !defined($g->{start}) || $start < $g->{start};
#	  $g->{stop}  = $stop  if !defined($g->{stop})  || $stop  > $g->{stop};
#	} else {
#	  $g->{start} = $start if !defined($g->{start}) || $start > $g->{start};
#	  $g->{stop}  = $stop  if !defined($g->{stop})  || $stop  < $g->{stop};
#	}
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

=head2 score

 Title   : score
 Usage   : $score = $f->score([$newscore])
 Function: get or set the feature score
 Returns : a string
 Args    : a new score (optional)
 Status  : Public

This method gets or sets the feature score.

=cut

sub score  {
  my $self = shift;
  my $d    = $self->{score};
  $self->{score} = shift if @_;
  $d;
}

1;
