# Das adaptor for BioSQL

=head1 NAME

Bio::DB::Das::BioSQL - DAS-style access to a BioSQL database

=head1 SYNOPSIS

 # Open up a feature database
 $db = Bio::DB::Das::BioSQL->new(
				 driver   => 'mysql',
				 dbname => 'biosql',
				 biodbname => 'test',
				 host   => 'swiss',
				 user   => 'lstein',
				 pass   => undef,
				 port   => undef,
				 namespace   => 'namespace',
				 version   => version_number,
				) or die;

  @segments = $db->segment(-name  => 'NT_29921.4',
                           -start => 1,
			   -end   => 1000000);

  # segments are Bio::Das::SegmentI - compliant objects

  # fetch a list of features
  @features = $db->features(-segment=>$segment, -type=>['type1','type2','type3']);

  $stream   = $db->get_seq_stream(-type=>['type1','type2','type3']);
  while (my $feature = $stream->next_seq) {
     # each feature is a Bio::SeqFeatureI-compliant object
  }

  # get all feature types
  @types   = $db->types;

  # count types
  %types   = $db->types(-enumerate=>1);

  @feature = $db->get_feature_by_name($class=>$name);
  @feature = $db->get_feature_by_target($target_name);
  @feature = $db->get_feature_by_attribute($att1=>$value1,$att2=>$value2);
  $feature = $db->get_feature_by_id($id);

  $error = $db->error;

=head1 DESCRIPTION

Bio::DB::Das::BioSQL is a simplified alternative interface to sequence
annotation databases used by the distributed annotation system (see
L<Bio::Das>). In this scheme, the genome is represented as a series of
features, a subset of which are named.  Named features can be used as
reference points for retrieving "segments" (see
L<Bio::DB::Das::Segment>), and these can, in turn, be used as the
basis for exploring the genome further.

In addition to a name, each feature has a "class", which is
essentially a namespace qualifier and a "type", which describes what
type of feature it is.  Das uses the GO consortium's ontology of
feature types, and so the type is actually an object of class
Bio::Das::FeatureTypeI (see
L<Bio::Das::FeatureTypeI>). Bio::DB::Das::BioSQL provides methods for
interrogating the database for the types it contains and the counts of
each type.

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the evolution of this and other
Bioperl modules. Send your comments and suggestions preferably to one
of the Bioperl mailing lists.  Your participation is much appreciated.

  bioperl-l@bio.perl.org

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
the bugs and their resolution.  Bug reports can be submitted via email
or the web:

  bioperl-bugs@bio.perl.org
  http://bio.perl.org/bioperl-bugs/

=head1 AUTHORS - Lincoln Stein, Vsevolod (Simon) Ilyushchenko

Email lstein@cshl.edu, simonf@cshl.edu

=head1 APPENDIX

The rest of the documentation details each of the object
methods. Internal methods are usually preceded with a _

=cut

#'

package Bio::DB::Das::BioSQL;
use strict;

use Bio::DB::Das::BioSQL::BioDatabaseAdaptor;
use Bio::DB::Das::BioSQL::Segment;
use Bio::Root::Root;
use Bio::DasI;
use vars qw($VERSION @ISA);

use constant SEGCLASS => 'Bio::DB::Das::BioSQL::Segment';
use constant ADAPTOR_CLASS => 'Bio::DB::Das::BioSQL::BioDatabaseAdaptor';

$VERSION = 0.02;
@ISA     = qw(Bio::Root::Root Bio::DasI);

# Install horrible patch for gbrowse compatibility
use Bio::SeqFeature::Generic;
use Bio::DB::GFF::Util::Rearrange 'rearrange';

=head2 new

 Title   : new
 Usage   : $db    = Bio::DB::Das::BioSQL(
				    driver    => 'mysql',
				    dbname    => 'biosql',
				    biodbname => 'swissprot',
				    host      => 'localhost',
				    user      => 'jimbo',
				    pass      => 'supersecret',
				    port      => 3306,
                                       );

 Function: Open up a Bio::DB::DasI interface to a BioSQL database
 Returns : a new Bio::DB::Das::BioSQL object
 Args    : See L<Bio::DB::Das::BioSQL::BioDatabaseAdaptor->new_from_registry()
           The new() method takes the same arguments exactly.

=cut

# create new database accessor object
# takes all the same args as a Bio::DB::BioDB class
sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);
  
  # may throw an exception on new_from_registry()
  my $biosql   = $self ->_adaptorclass->new_from_registry(@_);

  $self->biosql($biosql);
  $self;
}

=head2 segment

 Title   : segment
 Usage   : $db->segment(@args);
 Function: create a segment object
 Returns : segment object(s)
 Args    : see below

This method generates a Bio::Das::SegmentI object (see
L<Bio::Das::SegmentI>).  The segment can be used to find overlapping
features and the raw sequence.

When making the segment() call, you specify the ID of a sequence
landmark (e.g. an accession number, a clone or contig), and a
positional range relative to the landmark.  If no range is specified,
then the entire region spanned by the landmark is used to generate the
segment.

Arguments are -option=E<gt>value pairs as follows:

 -name         ID of the landmark sequence.

 -class        A namespace qualifier.  It is not necessary for the
               database to honor namespace qualifiers, but if it
               does, this is where the qualifier is indicated.

 -version      Version number of the landmark.  It is not necessary for
               the database to honor versions, but if it does, this is
               where the version is indicated.

 -start        Start of the segment relative to landmark.  Positions
               follow standard 1-based sequence rules.  If not specified,
               defaults to the beginning of the landmark.

 -end          End of the segment relative to the landmark.  If not specified,
               defaults to the end of the landmark.

The return value is a list of Bio::Das::SegmentI objects.  If the method
is called in a scalar context and there are no more than one segments
that satisfy the request, then it is allowed to return the segment.
Otherwise, the method must throw a "multiple segment exception".

=cut

sub get_feature_by_name
{
  my ($self) = shift;
  my ($name,$start,$end,$class,$version,$id) = $self->_rearrange([qw(NAME
					 			     START
								     END
								     CLASS
								     VERSION
                                                                     FEATURE_ID
                                                  )],@_);
  if ($id) {
      return $self->get_feature_by_primary_key($id);
  }
  my @seq = $self->biosql->fetch_Seq_by_accession($name);
  return unless @seq;
  return map {$self->_segclass->new(-bioseq => $_, -dbadaptor => $self)} @seq;
}

sub get_feature_by_primary_key {
    my $self = shift;
    my $key  = shift;
    my $adaptor = $self->biosql->db->get_object_adaptor("Bio::SeqFeatureI");
    map {Bio::DB::Das::BioSQL::Segment->wrap_feature($_)} $adaptor->find_by_primary_key($key);
}

sub get_feature_by_primary_id {shift->get_feature_by_primary_key(@_)}

sub segment {
  my $self = shift;
  my ($name,$start,$end,$class,$version, $absolute) =
    rearrange([['NAME','REF'],'START',['END','STOP'],qw(CLASS VERSION ABSOLUTE)],@_);

  my @seq = $self->biosql->fetch_Seq_by_accession($name);
  
  return unless @seq;
  return map {$self->_segclass->new(-bioseq => $_, -dbadaptor => $self, -start => $start, -end => $end, -absolute => $absolute)} @seq;
}


=head2 features

 Title   : features
 Usage   : $db->features(@args)
 Function: get all features, possibly filtered by type
 Returns : a list of Bio::SeqFeatureI objects
 Args    : see below
 Status  : public

This routine will retrieve features in the database regardless of
position.  It can be used to return all features, or a subset based on
their type

Arguments are -option=E<gt>value pairs as follows:

  -types     List of feature types to return.  Argument is an array
             of Bio::Das::FeatureTypeI objects or a set of strings
             that can be converted into FeatureTypeI objects.

  -callback   A callback to invoke on each feature.  The subroutine
              will be passed each Bio::SeqFeatureI object in turn.

  -attributes A hash reference containing attributes to match.

The -attributes argument is a hashref containing one or more attributes
to match against:

  -attributes => { Gene => 'abc-1',
                   Note => 'confirmed' }

Attribute matching is simple exact string matching, and multiple
attributes are ANDed together.

If one provides a callback, it will be invoked on each feature in
turn.  If the callback returns a false value, iteration will be
interrupted.  When a callback is provided, the method returns undef.

=cut

sub features {
    my $self = shift;
    my ($types,$callback,$attributes, $segment) = 
       $self->_rearrange([qw(TYPES CALLBACK ATTRIBUTES SEGMENT)],
			@_);
    my @features = $segment->top_SeqFeatures();
    return @features;
}

=head2 types

 Title   : types
 Usage   : $db->types(@args)
 Function: return list of feature types in database
 Returns : a list of Bio::Das::FeatureTypeI objects
 Args    : see below

This routine returns a list of feature types known to the database. It
is also possible to find out how many times each feature occurs.

Arguments are -option=E<gt>value pairs as follows:

  -enumerate  if true, count the features

The returned value will be a list of Bio::Das::FeatureTypeI objects
(see L<Bio::Das::FeatureTypeI>.

If -enumerate is true, then the function returns a hash (not a hash
reference) in which the keys are the stringified versions of
Bio::Das::FeatureTypeI and the values are the number of times each
feature appears in the database.

NOTE: This currently raises a "not-implemented" exception, as the
BioSQL API does not appear to provide this functionality.

=cut

sub types {
  my $self = shift;
  my ($enumerate) =  $self->_rearrange([qw(ENUMERATE)],@_);
  $self->throw_not_implemented;
}

=head2 search_notes

 Title   : search_notes
 Usage   : $db->search_notes($search_term,$max_results)
 Function: full-text search on features, ENSEMBL-style
 Returns : an array of [$name,$description,$score]
 Args    : see below
 Status  : public

This routine performs a full-text search on feature attributes (which
attributes depend on implementation) and returns a list of
[$name,$description,$score], where $name is the feature ID,
$description is a human-readable description such as a locus line, and
$score is the match strength.

THIS METHOD CURRENTLY RETURNS EMPTY BECAUSE I CAN'T GET FETCH_BY_QUERY()
TO WORK.

=cut



=head2 biosql

 Title   : biosql
 Usage   : $biosql  = $db->biosql([$biosql])
 Function: Get/set the underlying Bio::DB::Das::BioSQL::BioDatabaseAdaptor
 Returns : An Bio::DB::Das::BioSQL::BioDatabaseAdaptor
 Args    : A new Bio::DB::Das::BioSQL::BioDatabaseAdaptor (optional)

=cut

sub biosql
{
    my $self = shift;
    if (@_) {$self->{biosql} = shift;}
    return $self->{biosql};
}

=head2 _segclass

 Title   : _segclass
 Usage   : $class = $db->_segclass
 Function: returns the perl class that we use for segment() calls
 Returns : a string containing the segment class
 Args    : none
 Status  : reserved for subclass use

=cut

sub _segclass { return SEGCLASS }

=head2 _adaptorclass

 Title   : _adaptorclass
 Usage   : $class = $db->_adaptorclass
 Function: returns the perl class that we use as a BioSQL database adaptor
 Returns : a string containing the segment class
 Args    : none
 Status  : reserved for subclass use

=cut

sub _adaptorclass { return ADAPTOR_CLASS }



1;


