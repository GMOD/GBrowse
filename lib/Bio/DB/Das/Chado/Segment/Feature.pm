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
use Data::Dumper;

use constant DEBUG => 0;

use vars qw($VERSION @ISA $AUTOLOAD);
@ISA = qw(Bio::DB::Das::Chado::Segment Bio::SeqFeatureI 
	  Bio::Root::Root);

$VERSION = '0.11';

use overload
  '""'   => 'asString';

*get_SeqFeatures = \&sub_SeqFeature;
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
  $group        this feature's featureloc.locgroup (NOT a GFF holdover)
  $db_id        this feature's internal database ID (feature.uniquename)
  $feature_id   the feature's feature_id

=cut

# 'This is called when creating a feature from scratch.  It does not have
# an inherited coordinate system.
sub new { 
  my $package = shift;
  my ($factory,
      $parent,
      $srcseq,
      $base_start,$end,
      $type,
      $strand,
      $group,       # ie, gene name  (GFF legacy)
      $db_id,
      $feature_id) = @_;

  my $self = bless { },$package;

  #check that this is what you want!
  #($start,$end) = ($end,$start) if defined($strand) and $strand == -1;

  @{$self}{qw(factory parent seq_id start end strand )} =
    ($factory,$parent,$srcseq,$base_start,$end,$strand);

  @{$self}{qw(type group db_id absolute)} =
    ($type,$group,$db_id,$factory->{absolute});

  @{$self}{qw(feature_id srcfeature_id score ) } = 
    ($feature_id,$parent->{srcfeature_id},0);

  $self;
}




###############################################################
# get/setters and their composites, alphabetical
###############################################################

=head2 abs_strand

  Title   : abs_strand
  Usage   : $obj->abs_strand($newval)
  Function: aliased to strand() for backward compatibility

=cut

*abs_strand = \&strand;

=head2 class

  Title   : class
  Function: aliased to type()for backward compatibility

=cut

*class = \&type;

=head2 db_id

  Title   : db_id
  Function: aliased to uniquename() for backward compatibility

=cut

*db_id = \&uniquename;

=head2 factory

  Title   : factory
  Usage   : $obj->factory($newval)
  Function: ???
  Returns : value of factory (a scalar)
  Args    : on set, new value (a scalar or undef, optional)


=cut

sub factory {
  my $self = shift;

  return $self->{'factory'} = shift if @_;
  return $self->{'factory'};
}

=head2 feature_id

  Title   : feature_id
  Usage   : $obj->feature_id($newval)
  Function: holds feature.feature_id
  Returns : value of feature_id (a scalar)
  Args    : on set, new value (a scalar or undef, optional)


=cut

sub feature_id {
  my $self = shift;

  return $self->{'feature_id'} = shift if @_;
  return $self->{'feature_id'};
}

=head2 group

  Title   : group
  Usage   : $group = $f->group([$new_group]);
  Function: Store the feature's location group (featureloc.locgroup).
            This method gets or sets the feature group.  The group is
            NOT a hold over from GFF and is NOT synonymous with name;
            it is featureloc.locgroup.  If you want the feature's
            name, use uniquename().
  Returns : value of group (a scalar)
  Args    : on set, new value (a scalar or undef, optional)


=cut

sub group {
  my $self = shift;

  return $self->{'group'} = shift if @_;
  return $self->{'group'};
}

=head2 id

  Title   : id
  Function: aliased to uniquename() for backward compatibility

=cut

*id  = \&uniquename;

=head2 info

  Title   : info
  Function: aliased to uniquename() for backward compatibility
            with broken generic glyphs primarily

=cut

*info = \&uniquename;

=head2 length

  Title   : length
  Usage   : $obj->length()
  Function: convenience for end - start + 1
  Returns : length of feature in basepairs
  Args    : none

=cut

sub length {
  my ($self) = @_;
  my $len = $self->end - $self->start +1;
  return $len;
}

=head2 method

 Title   : method
 Function: aliased to uniquename for backward compatibility

=cut

*method = \&type;

=head2 name

  Title   : name
  Function: aliased to uniquename for backward compatibility

=cut

*name = \&uniquename

=head2 score

  Title   : score
  Usage   : $obj->score($newval)
  Function: holds the (alignment?) feature's score
  Returns : value of score (a scalar)
  Args    : on set, new value (a scalar or undef, optional)


=cut

sub score {
  my $self = shift;

  return $self->{'score'} = shift if @_;
  return $self->{'score'};
}

=head2 seq_id

  Title   : seq_id
  Usage   : $obj->seq_id($newval)
  Function: ???
  Returns : value of seq_id (a scalar)
  Args    : on set, new value (a scalar or undef, optional)


=cut

sub seq_id {
  my $self = shift;

  return $self->{'seq_id'} = shift if @_;
  return $self->{'seq_id'};
}

=head2 _strand

  Title   : _strand
  Usage   : $obj->_strand($newval)
  Function: internal method; sets the feature strand, see strand()
  Returns : value of _strand (a scalar)
  Args    : on set, new value (a scalar or undef, optional)


=cut

sub _strand {
  my $self = shift;

  return $self->{'strand'} = shift if @_;
  return $self->{'strand'};
}

=head2 strand

  Title   : strand
  Usage   : $obj->strand()
  Function: Returns the strand of the feature.  Unlike the other
            methods, the strand cannot be changed once the object is
            created (due to coordinate considerations).
  Returns : -1, 0, or 1
  Args    : none, readonly.


=cut

sub strand {
  my $self = shift;
  return $self->{'strand'} || 0;
}

=head2 target

  Title   : target
  Usage   : unimplemented
  Function: ???
  Returns : undef
  Args    :

=cut

sub target {
  my ($self,%arg) = @_;

  #my $group = $self->group or return;
  #return unless $group->can('start');
  #$group;

  return;
}

=head2 type

  Title   : type
  Usage   : $obj->type($newval)
  Function: holds feature.type (Sequence Ontology feature type)
  Returns : value of type (a scalar)
  Args    : on set, new value (a scalar or undef, optional)

=cut

sub type {
  my $self = shift;

  return $self->{'type'} = shift if @_;
  return $self->{'type'};
}

=head2 uniquename

  Title   : uniquename
  Usage   : $obj->uniquename($newval)
  Function: holds feature.uniquename
  Returns : value of uniquename (a scalar)
  Args    : on set, new value (a scalar or undef, optional)

=cut

sub uniquename {
  my $self = shift;

  return $self->{'uniquename'} = shift if @_;
  return $self->{'uniquename'};
}

##############################################################
# end of get/setters and their composites
##############################################################

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

  my %termhash = %{$self->{factory}->{cvterm_id}};
  my $typewhere = '';
  if ($type) {
    $type = lc $type;
    $typewhere = " and child.type_id = $termhash{$type} ";
  }

  my $handle = $self->{factory}->{dbh};

#  print "$parent_id\n";
#  print "$handle\n";
  $self->{factory}->{dbh}->trace(2) if DEBUG;

  my $partof = defined $termhash{'partof'} ? $termhash{'partof'}
                                           : $termhash{'part_of'};

  warn "partof = $partof" if DEBUG;

  my $sth = $self->{factory}->{dbh}->prepare("
 select child.feature_id, child.name, child.type_id, child.uniquename, parent.name as pname,
           childloc.fmin, childloc.fmax, childloc.strand, childloc.locgroup, childloc.phase
    from feature as parent
    inner join
      feature_relationship as fr0 on
        (parent.feature_id = fr0.object_id)
    inner join
      feature as child on
        (child.feature_id = fr0.subject_id)
    inner join
      featureloc as childloc on
        (child.feature_id = childloc.feature_id)
    where parent.feature_id = $parent_id
          and fr0.type_id = $partof
          $typewhere
    ");
  $sth->execute or $self->throw("subfeature query failed"); 

#  $self->{factory}->{dbh}->trace(0);# if DEBUG;

  my @features;
  my %termname = %{$self->{factory}->{cvname}};
  while (my $hashref = $sth->fetchrow_hashref) {

    next unless $$hashref{locgroup} eq $self->group; #look out, subfeatures may reside on other segments

    my $stop  = $$hashref{fmax};
    my $interbase_start = $$hashref{fmin};
    my $base_start = $interbase_start +1;

    my $feat = Bio::DB::Das::Chado::Segment::Feature->new (
                       $self->{factory},
                       $self,
                       $self->ref,
                       $base_start,$stop,
                       $termname{$$hashref{type_id}},
                       $$hashref{strand},
                       $$hashref{name},
                       $$hashref{uniquename}, $$hashref{feature_id}); 

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
   if (my @segments = $self->sub_SeqFeature) {
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

*merged_segments = \&sub_SeqFeature;

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

=head1 SeqFeatureI methods

=cut

=head2 display_name

  Title   : display_name
  Function: aliased to uniquename() for Bio::SeqFeatureI compatibility

=cut

*display_name = \&uniquename;

=head2 primary_tag

  Title   : primary_tag
  Function: aliased to type() for Bio::SeqFeatureI compatibility

=cut

*primary_tag = \&type;

sub source_tag  { 
  # returns source (manual curation, computation method, etc
  # not sure where to get this.
}
*source = \&source_tag;

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
  my $name = $self->uniquename;
  return "$type($name)" if $name;
  return $type;
#  my $type = $self->method;
#  my $id   = $self->group || 'unidentified';
#  return join '/',$id,$type,$self->SUPER::asString;
}

sub attributes {
  my $self = shift;
  my $factory = $self->factory;
  defined(my $id = $self->id) or return;
  $factory->attributes($id,@_)
}

sub synonyms {
  #returns an array with synonyms
  my $self = shift;
  my $dbh = $self->{factory}->{dbh};
 
  my $sth = $dbh->prepare("
    select s.name from synonym s, feature_synonym fs
    where ? = fs.feature_id and
          fs.synonym_id = s.synonym_id
  ");
  $sth->execute($self->{feature_id}) or $self->throw("synonym query failed");
 
  my $name = $self->display_name;
  my @synonyms;
  while (my $hashref = $sth->fetchrow_hashref) {
    push @synonyms, $$hashref{name} if ($$hashref{name} ne $name);
  }

  return @synonyms;
}


1;
