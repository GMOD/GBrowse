=head1 NAME

Bio::DB::Das::Chado::Segment::Feature

=head1 SYNOPSIS

See L<Bio::DB::Das::Chado>.

=head1 DESCRIPTION

Not yet written

=head1 API

=cut

package Bio::DB::Das::Chado::Segment::Feature;

use strict;

use Bio::DB::Das::Chado::Segment;
use Bio::SeqFeatureI;
use Bio::Root::Root;
use Bio::LocationI;
use Data::Dumper;
use URI::Escape;

use constant DEBUG => 0;

use vars qw($VERSION @ISA $AUTOLOAD %CONSTANT_TAGS);
@ISA = qw(Bio::DB::Das::Chado::Segment Bio::SeqFeatureI
          Bio::Root::Root);

$VERSION = '0.12';
%CONSTANT_TAGS = ();

use overload '""' => 'asString';

=head2 new

 Title   : new
 Usage   : $f = Bio::DB::Das::Chado::Segment::Feature->new(@args);
 Function: create a new feature object
 Returns : new Bio::DB::Das::Chado::Segment::Feature object
 Args    : see below
 Status  : Internal

This method is called by Bio::DB::Das::Chado::Segment to create a new
feature using information obtained from the chado database.

The 11 arguments are positional:

  $factory      a Bio::DB::Das::Chado adaptor object (or descendent)
  $parent       the parent feature object (if it exists)
  $srcseq       the source sequence
  $start        start of this feature
  $stop         stop of this feature
  $type         a Bio::DB::GFF::Typename (containing a method and source)
  $score        the feature's score
  $strand       this feature's strand (relative to the source
                sequence, which has its own strandedness!)
  $phase        this feature's phase (often with respect to the 
                previous feature in a group of related features)
  $group        this feature's featureloc.locgroup (NOT a GFF holdover)
  $uniquename   this feature's internal unique database
                     name (feature.uniquename)
  $feature_id   the feature's feature_id

This is called when creating a feature from scratch.  It does not have
an inherited coordinate system.

=cut

sub new {
  my $package = shift;
  my ($factory,
      $parent,
      $srcseq,
      $start,$end,
      $type,
      $score,
      $strand,
      $phase,
      $group,
      $uniquename,
      $feature_id) = @_;

  my $self = bless { },$package;

  #check that this is what you want!
  #($start,$end) = ($end,$start) if defined($strand) and $strand == -1;

  $self->factory($factory);
  $self->parent($parent) if $parent;
  $self->seq_id($srcseq);
  $self->start($start);
  $self->end($end);
  $self->score($score);
  $self->strand($strand);
  $self->phase($phase);

  $self->type($type);
  $self->group($group);
  $self->uniquename($uniquename);
#  $self->absolute($factory->absolute);
  $self->absolute(1);

  $self->feature_id($feature_id);

  if ($srcseq && !$parent) {
    $parent = $factory->segment( -name => $srcseq,
                                 -start=> $start,
                                 -stop => $end,
                               ); 
  }

  $self->srcfeature_id($parent->srcfeature_id() ) 
           if (defined $parent && $parent->can('srcfeature_id'));

  return $self;
}

######################################################################
# feature and featureloc db value slots
######################################################################

=head1 feature and featureloc accessors

Methods below are accessors for data that is drawn directly from the
Chado dataabase and can be considered "primary" accessors for this
class.

=cut

=head2 feature_id()

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

=head2 group()

  Title   : group
  Usage   : $group = $f->group([$new_group]);
  Function: Returns a feature name--this is here to maintain backward 
            compatibility with GFF and gbrowse.
  Returns : value of group (a scalar)
  Args    : on set, new value (a scalar or undef, optional)


=cut

sub group {
  my $self = shift;

  return $self->{'group'} = shift if @_;
  return $self->{'group'};
}

=head2 srcfeature_id()

  Title   : srcfeature_id
  Usage   : $obj->srcfeature_id($newval)
  Function: ???
  Returns : value of srcfeature_id (a scalar)
  Args    : on set, new value (a scalar or undef, optional)


=cut

sub srcfeature_id {
  my $self = shift;

  return $self->{'srcfeature_id'} = shift if @_;
  return $self->{'srcfeature_id'};
}

=head2 strand()

  Title   : strand
  Usage   : $obj->strand()
  Function: Returns the strand of the feature.  Unlike the other
            methods, the strand cannot be changed once the object is
            created (due to coordinate considerations).
            corresponds to featureloc.strand
  Returns : -1, 0, or 1
  Args    : on set, new value (a scalar or undef, optional)


=cut

sub strand {
  my $self = shift;

  return $self->{'strand'} = shift if @_;
  return $self->{'strand'} || 0;
}

=head2 phase

=over

=item Usage

  $obj->phase()        #get existing value
  $obj->phase($newval) #set new value

=item Function

=item Returns

value of phase (a scalar)

=item Arguments

new value of phase (to set)

=back

=cut

sub phase {
    my $self = shift;
    return $self->{'phase'} = shift if defined($_[0]);
    return $self->{'phase'};
}


=head2 type()

  Title   : type
  Usage   : $obj->type($newval)
  Function: holds a Bio::DB::GFF::Typename object
  Returns : returns a Bio::DB::GFF::Typename object
  Args    : on set, new value

=cut

sub type {
  my $self = shift;

  return $self->{'type'} = shift if @_;
  return $self->{'type'};
}

=head2 uniquename()

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

######################################################################
# ISA Bio::SeqFeatureI
######################################################################

=head1 SeqFeatureI methods

Bio::DB::Das::Chado::Segment::Feature implements the Bio::SeqFeatureI
interface.  Methods described below, L<Bio:SeqFeatureI> for more
details.

=cut

=head2 attach_seq()

 Title   : attach_seq
 Usage   : $sf->attach_seq($seq)
 Function: Attaches a Bio::Seq object to this feature. This
           Bio::Seq object is for the *entire* sequence: ie
           from 1 to 10000
 Example :
 Returns : TRUE on success
 Args    : a Bio::PrimarySeqI compliant object

=cut

sub attach_seq {
  my ($self) = @_;

  $self->throw_not_implemented();
}

=head2 display_name()

  Title   : display_name
  Function: aliased to uniquename() for Bio::SeqFeatureI compatibility

=cut

*display_name = \&group;

=head2 entire_seq()

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

=head2 get_all_tags()

  Title   : get_all_tags
  Function: aliased to all_tags() for Bio::SeqFeatureI compatibility

=cut

*get_all_tags = \&all_tags;

=head2 get_SeqFeatures()

  Title   : get_SeqFeatures
  Function: aliased to sub_SeqFeature() for Bio::SeqFeatureI compatibility

=cut

*get_SeqFeatures = \&sub_SeqFeature;

=head2 get_tag_values()

  Title   : get_tag_values
  Usage   :
  Function: ???
  Returns :
  Args    :


=cut

sub get_tag_values {
  my $self = shift;
  my $tag  = shift;
  return $self->$tag() if $CONSTANT_TAGS{$tag};
  $tag = ucfirst $tag;
  return $self->$tag();  # try autogenerated tag
}

=head2 get_tagset_values()

  Title   : get_tagset_values
  Usage   :
  Function: ???
  Returns :
  Args    :


=cut

sub get_tagset_values {
  my ($self,%arg) = @_;

  $self->throw_not_implemented();
}

=head2 gff_string()

  Title   : gff_string
  Usage   :
  Function: ???
  Returns :
  Args    :


=cut

sub gff_string {
  my $self = shift;
  my ($recurse,$parent) = @_;
  my ($start,$stop) = ($self->start,$self->stop);

  # the defined() tests prevent uninitialized variable warnings, when dealing with clone objects
  # whose endpoints may be undefined
  ($start,$stop) = ($stop,$start) if defined($start) && defined($stop) && $start > $stop;

  my $strand = ('-','.','+')[$self->strand+1];
  my $ref = $self->refseq;
  my $n   = ref($ref) ? $ref->name : $ref;
  my $phase = $self->phase;
  $phase = '.' unless defined $phase;

  my ($class,$name) = ('','');
  my @group;
  if (my $g = $self->group) {
    $class = $g->can('class') && $g->class ? $g->class : '';
    $name  = $g->can('name')  && $g->name  ? $g->name  : '';
    $name  = "$class:$name" if length($class) and length($name);
    push @group,[ID =>  $name] if !defined($parent) || $name ne $parent;
  }

  push @group,[Parent => $parent] if defined $parent && $parent ne '';

  if (my $t = $self->target) {
    $strand = '-' if $t->stop < $t->start;
    push @group, $self->flatten_target($t,3);
  }

  my @attributes = $self->attributes;
  while (@attributes) {
    push @group,[shift(@attributes),shift(@attributes)]
  }
  my $group_field = join ';',map {join '=',uri_escape($_->[0]),uri_escape($_->[1])} grep {$_->[0] =~ /\S/ and $_->[1] =~ /\S/} @group;
  my $string = join("\t",$n,$self->source||'.',$self->method||'.',$start||'.',$stop||'.',
                    $self->score||'.',$strand||'.',$phase||'.',$group_field);
  $string .= "\n";
  if ($recurse) {
    foreach ($self->sub_SeqFeature) {
      $string .= $_->gff_string(1,$name);
    }
  }
  $string;
}

=head2 has_tag()

  Title   : has_tag
  Usage   :
  Function: ???
  Returns :
  Args    :


=cut

sub has_tag { 
  my $self = shift;
  my $tag  = shift;
  my %tags = map {$_=>1} $self->all_tags;
  return $tags{$tag};
}

=head2 primary_tag()

  Title   : primary_tag
  Function: aliased to type() for Bio::SeqFeatureI compatibility

=cut

*primary_tag = \&method;

=head2 seq()

  Title   : seq
  Usage   :
  Function: ???
  Returns :
  Args    :

=cut

#sub seq {
#  my ($self,%arg) = @_;
#
#  $self->throw_not_implemented();
#}

=head2 seq_id()

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

=head2 source_tag()

  Title   : source_tag
  Function: aliased to source() for Bio::SeqFeatureI compatibility

=cut

*source_tag = \&source;

######################################################################
# ISA Bio::SeqFeatureI
######################################################################

=head1 Bio::RangeI methods

Bio::SeqFeatureI in turn ISA Bio::RangeI.  Bio::RangeI interface
methods described below, L<Bio::RangeI> for details.

=cut

=head2 end()

  Title   : end
  Function: inherited, L<Bio::DB::Das::Chado::Segment>

=cut

=head2 start()

  Title   : start
  Function: inherited, L<Bio::DB::Das::Chado::Segment>

=cut

=head2 strand()

  Title   : strand
  Function: inherited, L<Bio::DB::Das::Chado::Segment>

=cut



###############################################################
# get/setters and their composites, alphabetical
###############################################################

=head1 other get/setters

=cut

=head2 abs_strand()

  Title   : abs_strand
  Usage   : $obj->abs_strand($newval)
  Function: aliased to strand() for backward compatibility

=cut

*abs_strand = \&strand;

=head2 class()

  Title   : class
  Function: aliased to method()for backward compatibility

=cut

*class = \&type;

=head2 db_id()

  Title   : db_id
  Function: aliased to uniquename() for backward compatibility

=cut

*db_id = \&uniquename;

=head2 factory()

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

=head2 id()

  Title   : id
  Function: aliased to uniquename() for backward compatibility

=cut

*id  = \&uniquename;

=head2 info()

  Title   : info
  Function: aliased to uniquename() for backward compatibility
            with broken generic glyphs primarily

=cut

*info = \&uniquename;

=head2 length()

  Title   : length
  Usage   : $obj->length()
  Function: convenience for end - start + 1
  Returns : length of feature in basepairs
  Args    : none

=cut

sub length {
  my ($self) = @_;
  my $len = $self->end() - $self->start() +1;
  return $len;
}

=head2 method()

 Title   : method
 Usage   : $obj->method
 Function: returns a Feature's method (SOFA type)
 Returns : the Features SOFA type
 Args    : none

=cut

sub method {
  my $self = shift;
  return $self->type->method();
}

=head2 name()

  Title   : name
  Function: aliased to group for backward compatibility

=cut

*name = \&group;

=head2 parent()

  Title   : parent
  Usage   : $obj->parent($newval)
  Function: ???
  Returns : value of parent (a scalar)
  Args    : on set, new value (a scalar or undef, optional)


=cut

sub parent {
  my $self = shift;

  return $self->{'parent'} = shift if @_;
  return $self->{'parent'};
}

=head2 score()

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

=head2 target()

  Title   : target
  Usage   : $feature->target
  Function: returns a Bio::DB::Das::Chado::Segment that corresponds
            to the target of a similarity pair
  Returns : a Bio::DB::Das::Chado::Segment object
  Args    : none

=cut

sub target {
  my ($self) = shift;

  my $self_id = $self->feature_id;

#so, we need to construct a segment that corresponds to to the 
#target sequence.  So, what do I need from chado:
#
#  - the feature_id of the target (from featureloc.srcfeature_id
#      where featureloc.rank > 0 ; when rank = 0, it corresponds
#      to the feature's coords on the 'main' sequence)
#  - featureloc.fmin and fmax for the target
#  - feature.name

  my $query = "SELECT fl.srcfeature_id,fl.fmin,fl.fmax,f.name,f.uniquename
               FROM featureloc fl JOIN feature f 
                    ON (fl.feature_id = ? AND fl.srcfeature_id=f.feature_id)
               WHERE fl.rank > 0";

  my $sth = $self->factory->dbh->prepare($query);
  $sth->execute($self_id);

# While it is theoretically possible for there to be more than 
# on target per feature, Bio::Graphics::Browser doesn't support it

  my $hashref = $sth->fetchrow_hashref;

  if ($$hashref{'name'}) {
      my $segment = Bio::DB::Das::Chado::Segment->new(
                $$hashref{'name'},
                $self->factory,
                $$hashref{'fmin'}+1,
                $$hashref{'fmax'},
                $$hashref{'uniquename'},
                1,  #new arg to tell Segment this is a Target
           );
      return $segment;
  }
  return; #didn't get anything
}

*hit = \&target;

#####################################################################
# other methods
######################################################################

=head1 Other methods

=cut

=head2 all_tags()

  Title   : all_tags
  Usage   :
  Function: ???
  Returns :
  Args    :


=cut

sub all_tags {
  my $self = shift;
  my @tags = keys %CONSTANT_TAGS;
  # autogenerated methods
  if (my $subfeat = $self->subfeatures) {
    push @tags,keys %$subfeat;
  }
  @tags;
}

=head2 source()

  Title   : source
  Usage   : $f->source();
  Function: caches and returns the source from a GFF file, this is stored
            in featureprop with a tag of 'GFF_Source'
  Returns : See above
  Args    : none

=cut

sub source {
    my $self = shift;

    return $self->type->source();
}

=head2 segments()

  Title   : segments
  Function: aliased to sub_SeqFeature() for compatibility


=cut

*segments = \&sub_SeqFeature;

=head2 subfeatures

  Title   : subfeatures
  Usage   : $obj->subfeatures($newval)
  Function: returns a list of subfeatures
  Returns : value of subfeatures (a scalar)
FIXME THIS SHOULD RETURN A LIST OR AN ARRAY AND BE DOCUMENTED AS SUCH
NOT RETURN AN ARRAYREF OR HASHREF.  FOR ADDING/SETTING ELEMENTS WE
NEED ADD_ AND SET_ METHODS
  Args    : on set, new value (a scalar or undef, optional)


=cut

sub subfeatures {
  my $self = shift;

  return $self->{'subfeatures'} = shift if @_;
  return $self->{'subfeatures'};
}


=head2 sub_SeqFeature()

 Title   : sub_SeqFeature
 Usage   : @feat = $feature->sub_SeqFeature([$type])
 Function: This method returns a list of any subfeatures
           that belong to the main feature.  For those
           features that contain heterogeneous subfeatures,
           you can retrieve a subset of the subfeatures by
           providing an array of types to filter on.

           For AcePerl compatibility, this method may also
           be called as segments().
 Returns : a list of Bio::DB::Das::Chado::Segment::Feature objects
 Args    : a feature method (optional)
 Status  : Public

=cut

sub sub_SeqFeature {
  my($self,@type) = @_;

  #first call, cache subfeatures
  #Bio::SeqFeature::CollectionI?
  #like SeqFeature::Generic?
  if(!$self->subfeatures ){

    my $parent_id = $self->feature_id();
    my $inferCDS = $self->factory->inferCDS;

    my $typewhere = '';
    if (@type > 0) {
      my @id_list = map { $self->factory->name2term($_) } @type;


      # if CDS features were requested, and inferCDS is set, add
      # polypeptide and exon features to the list so they can be fetched too
      if ($inferCDS &&  grep {'CDS'} @type ) {
          push @id_list, 
               ( $self->factory->name2term('exon'), 
                 $self->factory->name2term('polypeptide') ); 
      }

      $typewhere = " and child.type_id in (". join(',',@id_list)  .")" ;

      warn "type:@type, type_id:@id_list" if DEBUG;
    }

    my $handle = $self->factory->dbh();

    $self->factory->dbh->trace(2) if DEBUG;

    my $partof =  $self->factory->name2term('part_of');
    my $derivesfrom = $self->factory->name2term('derives_from');
    $self->throw("part_of cvterm wasn't found.  is DB sane?") unless $partof;
    $partof = join ',', @$partof if ref($partof) eq 'ARRAY';
    $partof .= ",$derivesfrom";

    warn "partof = $partof" if DEBUG;

    my $sql = "
    select child.feature_id, child.name, child.type_id, child.uniquename, parent.name as pname,
      childloc.fmin, childloc.fmax, childloc.strand, childloc.locgroup, childloc.phase, af.significance as score,
      childloc.srcfeature_id
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
    left join
       analysisfeature as af on
        (child.feature_id = af.feature_id)
    where parent.feature_id = $parent_id
          and childloc.rank = 0
          and fr0.type_id in ($partof)
          $typewhere
    ";

#Recursive Mapping
#Construct a query that recursively maps clone's features on the underlying chromosome
  if ($self->factory->recursivMapping){

    #Notes on the interbase computation :
    #$self->start is already converted to base coordinates, so  we need to substract the unit which has been added by this conversion
    $sql="
   select child.feature_id, child.name, child.type_id, child.uniquename, parent.name as pname,
         (childloc.fmin + ".$self->start." - parentloc.fmin -1)  AS fmin,
        (childloc.fmax + ".$self->start." - parentloc.fmin -1)  AS fmax,
          (childloc.strand * ".$self->strand." * parentloc.strand)  AS strand,
         childloc.locgroup, childloc.phase, af.significance as score,
          CASE WHEN  (
                     parentloc.srcfeature_id=
                           (select distinct srcfeature_id from featureloc where feature_id=".$self->feature_id." and rank=0)
                     )
               THEN ".$self->srcfeature_id."
               ELSE childloc.srcfeature_id  END as srcfeature_id
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
       inner join
         featureloc as parentloc on
           (parent.feature_id = parentloc.feature_id)
       left join
          analysisfeature as af on
           (child.feature_id = af.feature_id)
       where parent.feature_id = $parent_id
             and childloc.rank = 0
             and fr0.type_id in ($partof)
             $typewhere";
  }

#END Recursive Mapping

    $sql =~ s/\s+/ /gs if DEBUG;
    warn $sql if DEBUG;

    my $sth = $self->factory->dbh->prepare($sql);
    $sth->execute or $self->throw("subfeature query failed");

    #$self->factory->dbh->trace(0) if DEBUG;

    my $rows = $sth->rows;
    return if ($rows<1);    #nothing retrieve during query

    my @p_e_cache;
    while (my $hashref = $sth->fetchrow_hashref) {

      next unless $$hashref{srcfeature_id} == $self->srcfeature_id;

      # this problem can't be solved this way--group really needs to return 'name'
      # in order for the adaptor to work with gbrowse
      # next unless $$hashref{locgroup} eq $self->group; #look out, subfeatures may reside on other segments

      my $stop  = $$hashref{fmax};
      my $interbase_start = $$hashref{fmin};
      my $base_start = $interbase_start +1;

      my $source_query = $self->factory->dbh->prepare("
            select d.accession from dbxref d,feature_dbxref fd
            where fd.feature_id = $$hashref{feature_id} and
                  fd.dbxref_id  = d.dbxref_id and
                  d.db_id = ".$self->factory->gff_source_db_id);
      $source_query->execute();

      my ($source) = $source_query->fetchrow_array;
      my $type_obj = Bio::DB::GFF::Typename->new(
           $self->factory->term2name($$hashref{type_id}),
           $source
      );

      warn "creating new subfeat, $$hashref{name}, $base_start, $stop" if DEBUG;

      my $feat = Bio::DB::Das::Chado::Segment::Feature->new (
                    $self->factory,
                    $self,
                    $self->ref,
                    $base_start,$stop,
                    $type_obj,
                    $$hashref{score},
                    $$hashref{strand},
                    $$hashref{phase},
                    $$hashref{name},
                    $$hashref{uniquename},
                    $$hashref{feature_id}
                                                            );
      $self->add_subfeature($feat);

      if ($inferCDS && ($feat->type =~ /exon/ or $feat->type =~ /polypeptide/ )) {
          #saving an object to an array saves a reference to the object--
          #we don't want that, so we have to use the clone method to make a copy
          push @p_e_cache, $feat->clone;
      }
    }

    #now deal with converting polypeptide and exons to CDS

    if (@p_e_cache > 0) {
        #get the polypeptide at the top of the list
        #and get the exons in translation order
        my @sorted = sort {
                       $b->type cmp $a->type
                       || $a->start * $a->strand <=> $b->start * $b->strand
                          } @p_e_cache;

        my ($start,$stop);
        my $poly = shift @sorted;

        if ($poly->type->method =~ /poly/) {
            $start = $poly->start;
            $stop  = $poly->end;
        }
        else {
            #if there's no polypeptide feature, there's no point in continuing
            return @{$self->subfeatures()};
        }

        warn "poly:$poly,start:$start, stop:$stop" if DEBUG;
        warn $poly->start if DEBUG;
        warn $poly->end if DEBUG;

        my @temp_array;
        for (my $i=0; $i < scalar @sorted; $i++) {
            my $feat = $sorted[$i];

            (delete $sorted[$i] && next) 
                   if ($feat->start < $start and $feat->end < $start);
            (delete $sorted[$i] && next) 
                   if ($feat->start > $stop  and $feat->end > $stop);

            $feat->type->method('CDS');

            if ($feat->start < $start) {
                $feat->start($start);
            }
            if ($feat->end > $stop) {
                $feat->end($stop);
            }

            push @temp_array, $feat;
        }

        return unless scalar @temp_array;

        @sorted=$self->_calc_phases(@temp_array) 
                 if (!(defined $temp_array[0]->phase) );

        for (@sorted) {
            $self->add_subfeature($_);
        }
    }
  }

#this shouldn't be necessary, as filtering took place via the query
#  if($types){
#    my %oktypes;
#    my %ok = map {$oktypes{$_} => 1} @$types;
#    return grep { $ok{ $_->type } } $self->subfeatures();
#  }

  my @subfeatures = @{$self->subfeatures()};

   # warn "subfeature array:@subfeatures\n";

  return  @subfeatures;
}

=head2 _calc_phases

 Title   : _calc_phases
 Usage   : $feature->_calc_phases(@exons)
 Function: calculstes phases for exons without phases 
 Returns : a list of exon feature objects with phases
 Args    : a list of sorted (by transcription order) exons
 Status  : private

=cut

sub _calc_phases {
  my $self = shift;
  my @exons = @_;

      #  L0 is length of the first segment measured from the start site
      #  Li is length of the current segment measured from its splice start
      #  P0 is the phase of the first segment, always 0
      #  Pi is the phase of the current segment
      #  P(i+1) = 3 - (Li - Pi) mod 3

  $exons[0]->phase(0);

  for (my $i = 0; $i < (scalar @exons) -1; $i++) {
    next unless defined $exons[$i];
    my $phase = (3 - ($exons[$i]->length - $exons[$i]->phase) % 3) % 3;
    $exons[$i+1]->phase($phase);

    warn $exons[$i]->parent." ".$exons[$i]." ".$exons[$i]->start." ".$exons[$i]->phase." ".$exons[$i+1]->phase() if DEBUG;
  } 

  return @exons;
}

=head2 add_subfeature()

 Title   : add_subfeature
 Usage   : $feature->add_subfeature($feature)
 Function: This method adds a new subfeature to the object.
           It is used internally by aggregators, but is
           available for public use as well.
 Returns : nothing
 Args    : a Bio::DB::Das::Chado::Segment::Feature object
 Status  : Public


=cut

sub add_subfeature {
  my $self    = shift;
  my $subfeature = shift;

   #  warn "in add_subfeat:$subfeature";

  return undef unless ref($subfeature);
  return undef unless $subfeature->isa('Bio::DB::Das::Chado::Segment::Feature');

  push @{$self->{subfeatures}}, $subfeature;
  return $subfeature;
}

=head2 location()

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

*merged_segments = \&sub_SeqFeature;

=head2 clone()

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


=head2 sub_types()

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
  $self->warn("this method appears to be broken, check subfeatures() return value");
  my $subfeat = $self->subfeatures or return;
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

sub AUTOLOAD {
  my($pack,$func_name) = $AUTOLOAD=~/(.+)::([^:]+)$/;
  my $sub = $AUTOLOAD;
  my $self = $_[0];

  # ignore DESTROY calls
  return if $func_name eq 'DESTROY';

  # fetch subfeatures if func_name has an initial cap
  #return sort {$a->start <=> $b->start} $self->sub_SeqFeature($func_name) if $func_name =~ /^[A-Z]/;
  return $self->sub_SeqFeature($func_name) if $func_name =~ /^[A-Z]/;

  # error message of last resort
  #$self->throw(qq(Can't locate object method "$func_name" via package "$pack"));
}

=head2 adjust_bounds()

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

  $self->warn("this method appears to be broken, check subfeatures() return value");

  if (my $subfeat = $self->subfeatures) {
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

  ( $self->start(),$self->stop(),$self->strand() );
}

=head2 sort_features()

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
  my $subfeat = $self->subfeatures or return;
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

=head2 asString()

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
  $factory->attributes($id,@_);
}

=head2 synonyms()

 Title   : synonyms
 Usage   : @synonyms = $feature->synonyms
 Function: return a list of synonyms for a feature
 Returns : a list of strings
 Args    : none
 Status  : Public

Looks in the synonym table to collect all synonyms of a feature.

=cut


sub synonyms {
  #returns an array with synonyms
  my $self = shift;
  my $dbh = $self->factory->dbh();
 
  my $sth = $dbh->prepare("
    select s.name from synonym s, feature_synonym fs
    where ? = fs.feature_id and
          fs.synonym_id = s.synonym_id
  ");
  $sth->execute($self->feature_id()) or $self->throw("synonym query failed");
 
  my $name = $self->display_name;
  my @synonyms;
  while (my $hashref = $sth->fetchrow_hashref) {
    push @synonyms, $$hashref{name} if ($$hashref{name} ne $name);
  }

  return @synonyms;
}

=head2 cmap_link()

 Title   : cmap_link
 Usage   : $link = $feature->cmap_link
 Function: returns a URL link to the corresponding feature in cmap
 Returns : a string
 Args    : none
 Status  : Public

Returns a link to a cmap installation (which is assumed to be on the
same host as gbrowse).  In addition to the cmap tables being present
in chado, this method also assumes the presence of a link table called
feature_to_cmap.  See the cmap documentation for more information.

This function is intended primarily to be used in gbrowse conf files. 
For example:

  link       = sub {my $self = shift; return $self->cmap_link();}

=cut


sub cmap_link {
  # Use ONLY if CMap is installed in chado and
  # the feature_to_cmap table is also installed
  # This table is provided with CMap.
  my $self = shift;
  my $data_source = shift;
 
  my $dbh = $self->factory->dbh();

  my $sth = $dbh->prepare("
    select  cm_f.feature_name,
            cm_m.accession_id as map_aid
    from    cmap_feature cm_f,
            cmap_map cm_m,
            feature_to_cmap ftc
    where   ? = ftc.feature_id
            and cm_f.accession_id=ftc.cmap_feature_aid
            and cm_f.map_id=cm_m.map_id
  ");
  $sth->execute($self->feature_id()) or $self->throw("cmap link query
failed");
  my $link_str='';
  if (my $hashref = $sth->fetchrow_hashref) {
   
$link_str='/cgi-bin/cmap/viewer?ref_map_aids='.$$hashref{map_aid}.'&data_source='.$data_source.'&highlight='.$$hashref{'feature_name'};
  }

  return $link_str;
}

1;
