# $Id: Chado_pf.pm,v 1.2 2002-11-22 22:36:54 scottcain Exp $
# Das adaptor for Chado_pf

=head1 NAME

Bio::DB::Das::Chado_pf - DAS-style access to a chado_pf database

=head1 SYNOPSIS

  # Open up a feature database
 $db = Bio::DB::Das::Chado_pf->new(
				 driver   => 'postgres',
				 dbname => 'chado_pf',
				 host   => 'localhost',
				 user   => 'scain',
				 pass   => undef,
				 port   => undef,
				) or die;

  @segments = $db->segment(-name  => 'NT_29921.4',
                           -start => 1,
			   -end   => 1000000);

  # segments are Bio::Das::SegmentI - compliant objects

  # fetch a list of features
  @features = $db->features(-type=>['type1','type2','type3']);

  # invoke a callback over features
  $db->features(-type=>['type1','type2','type3'],
                -callback => sub { ... }
		);

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

  Chado is the GMOD database schema, and chado_pf is a specific instance
of it.  It is still somewhat of a moving target, so this package will 
probably require several updates over the coming months to keep it working.

=head2 CAVEATS

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

=head1 AUTHOR - Scott Cain 

Email cain@cshl.org

=head1 APPENDIX

The rest of the documentation details each of the object
methods. Internal methods are usually preceded with a _

=cut

#'

package Bio::DB::Das::Chado_pf;
use strict;

#use Bio::DB::Chado_pf::BioDatabaseAdaptor;
use Bio::DB::Das::Chado_pf::Segment;
use Bio::Root::Root;
use Bio::DasI;
use vars qw($VERSION @ISA);

use constant SEGCLASS      => 'Bio::DB::Das::Chado_pf::Segment';
use constant ADAPTOR_CLASS => 'Bio::DB::Chado_pf::BioDatabaseAdaptor';

$VERSION = 0.01;
@ISA     = qw(Bio::Root::Root Bio::DasI);

=head2 new

 Title   : new
 Usage   : $db    = Bio::DB::Das::Chado_pf(
				    driver    => 'postgres',
				    dbname    => 'chado_pf',
				    host      => 'localhost',
				    user      => 'jimbo',
				    pass      => 'supersecret',
				    port      => 3306,
                                       );

 Function: Open up a Bio::DB::DasI interface to a Chado_pf database
 Returns : a new Bio::DB::Das::Chado_pf object
 Args    : ???
         

=cut

# create new database accessor object
# takes all the same args as a Bio::DB::BioDB class
sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);

  # may throw an exception on new_from_registry()
  # this must return the dbh
  my $chado_pf   = $self ->_adaptorclass->new_from_registry(@_);

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

sub segment {
  my $self = shift;
  my ($name,$start,$end,$class,$version) = $self->_rearrange([qw(NAME
								 START
								 END
								 CLASS
								 VERSION)],@_);
  #my $seq = eval{$self->biosql->get_Seq_by_acc($name)};
  my $seq = eval{$self->get_Seq_by_acc($name)};

  if (!$seq && $name =~ s/\.\d+$//) {  # workaround version ?bug in get_Seq_by_acc
    $seq = eval{$self->get_Seq_by_acc($name)}; #shouldn't be necessary in my code, but keep
  }
  return unless $seq;
  return $self->_segclass->new($seq,$self,$start,$end);
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
  my ($types,$callback,$attributes) = 
       $self->_rearrange([qw(TYPES CALLBACK ATTRIBUTES)],
			@_);
  #my @features = $self->_segclass->_filter([$self->biosql->top_SeqFeatures],
  #					   {types => $types},
  #					   $callback);


  #top_SeqFeatures -- a Bio::Root::Root or Bio::DasI method?
  my @features = $self->_segclass->_filter([$self->top_SeqFeatures],
                                          {types => $types},
                                          $callback);


  @features;
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
  #if lincoln didn't need to implement it, neither do I!
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


=head2 get_seq_stream

 Title   : get_seq_stream
 Usage   : my $seqio = $self->get_seq_stream(@args)
 Function: Performs a query and returns an iterator over it
 Returns : a Bio::SeqIO stream capable of returning Bio::Das::SegmentI objects
 Args    : As in features()
 Status  : public

This routine takes the same arguments as features(), but returns a
Bio::SeqIO::Stream-compliant object.  Use it like this:

  $stream = $db->get_seq_stream('exon');
  while (my $exon = $stream->next_seq) {
     print $exon,"\n";
  }

CURRENT LIMITATION: All features are read into memory first and then
returned one at a time.  Therefore this method offers no advantage
over features().

NOTE: In the interface this method is aliased to get_feature_stream(),
as the name is more descriptive.

=cut

sub get_seq_stream {
  my @features = shift->features(@_);
  return Bio::DB::Das::Chado_pfIterator->new(\@features);
}

sub get_Seq_by_acc {
#to take the place of biosql->get_Seq_by_acc($name)
  my $self = shift;
  my $id = shift;
  my $stream = $self->get_Stream_by_accession($id);
  return $stream->next_seq;
}

=head2 biosql

 Title   : biosql
 Usage   : $biosql  = $db->biosql([$biosql])
 Function: Get/set the underlying Bio::DB::BioSQL::BioDatabaseAdaptor
 Returns : An Bio::DB::BioSQL::BioDatabaseAdaptor
 Args    : A new Bio::DB::BioSQL::BioDatabaseAdaptor (optional)

=cut

#sub biosql {
#  my $self = shift;
#  my $d    = $self->{biosql};
#  $self->{biosql} = shift if @_;
#  $d;
#}

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


package Bio::DB::Das::Chado_pfIterator;

sub new {
  my $package  = shift;
  my $features = shift;
  return bless $features,$package;
}

sub next_seq {
  my $self = shift;
  return unless @$self;
  return shift @$self;
}

1;


