# $Id: Chado.pm,v 1.14 2003-01-30 20:10:12 scottcain Exp $
# Das adaptor for Chado

=head1 NAME

Bio::DB::Das::Chado - DAS-style access to a chado database

=head1 SYNOPSIS

  # Open up a feature database
 $db = Bio::DB::Das::Chado->new(
				 driver   => 'postgres',
				 dbname => 'chado',
				 host   => 'localhost',
				 user   => 'scain',
				 pass   => undef,
				 port   => undef,
				) or die;

  @segments = $db->segment(-name  => '2L',
                           -start => 1,
			   -end   => 1000000);

  # segments are Bio::Das::SegmentI - compliant objects

  # fetch a list of features
  @features = $db->features(-type=>['type1','type2','type3']);

  # invoke a callback over features
  $db->features(-type=>['type1','type2','type3'],
                -callback => sub { ... }
		);


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

  Chado is the GMOD database schema, and chado is a specific instance
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

package Bio::DB::Das::Chado;
use strict;

use Bio::DB::Das::Chado::Segment;
use Bio::Root::Root;
use Bio::DasI;
use Bio::PrimarySeq;
use DBI;
use DBD::Pg;
use vars qw($VERSION @ISA);

use constant SEGCLASS      => 'Bio::DB::Das::Chado::Segment';
use constant DEBUG =>0;

$VERSION = 0.01;
@ISA     = qw(Bio::Root::Root Bio::DasI);

=head2 new

 Title   : new
 Usage   : $db    = Bio::DB::Das::Chado(
				    driver    => 'Pg',
				    dbname    => 'chado',
				    host      => 'localhost',
				    user      => 'jimbo',
				    pass      => 'supersecret',
				    port      => 3306,
                                       );

 Function: Open up a Bio::DB::DasI interface to a Chado database
 Returns : a new Bio::DB::Das::Chado object
 Args    : 
         

=cut

# create new database accessor object
# takes all the same args as a Bio::DB::BioDB class
sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);

  my ($dsn,undef,$username,undef,$password) = @_;

  my $dbh = DBI->connect( $dsn, $username, $password )
    or $self->throw("unable to open db handle");

    warn "$dbh\n" if DEBUG;

# get the cvterm relationships here and save for later use

  my $sth = $dbh->prepare("select cvterm_id,termname from cvterm")
    or warn "unable to prepare select cvterms";
  $sth->execute or $self->throw("unable to select cvterms");

  my $cvterm_id  = {};
  my $cvtermname = {};
  while (my $hashref = $sth->fetchrow_hashref) {
    $$cvterm_id{$$hashref{termname}}   = $$hashref{cvterm_id};
    $$cvtermname{$$hashref{cvterm_id}} = $$hashref{termname};
  }
  

  warn "in chado.pm: $cvterm_id\n" if DEBUG;

  return bless {dbh        => $dbh,
                cvterm_id  => $cvterm_id,
                cvtermname => $cvtermname}, ref $self ||$self;
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
  # lets the Segment class handle all the lifting.
  return $self->_segclass->new($name,$self,$start,$end);
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
  my ($types,$callback,$attributes,$iterator) = 
       $self->_rearrange([qw(TYPES CALLBACK ATTRIBUTES ITERATOR)],
			@_);


    warn "Chado,features: $types\n" if DEBUG;
  my @features = $self->_segclass->features(-types => $types,
                                            -attributes => $attributes,
                                            -callback => $callback,
                                            -iterator => $iterator );


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

=head2 get_feature_by_name

=cut

sub get_feature_by_name {
  my $self = shift;

  my ($name, $start, $stop) = $self->_rearrange([qw(NAME START END)],@_);

  my @features;
  if ($name =~ s/[?*]\s*$/%/) {
    # get feature_id
    # foreach feature_id, get the feature info
    # then get src_feature stuff (chromosome info) and create a parent feature,

    my $quoted_name = $self->{dbh}->quote($name);
    my $sth = $self->{dbh}->prepare("
       select fs.feature_id from feature_synonym fs, synonym s
       where fs.synonym_id = s.synonym_id and
       synonym ilike $quoted_name
       ");
    $sth->execute or throw("getting the feature_ids failed");


    # prepare sql queries for use in while loops
    my $isth =  $self->{dbh}->prepare("
       select f.feature_id, f.name, f.type_id, 
              fl.nbeg,fl.nend,fl.strand,fl.phase, fl.srcfeature_id
       from feature f, featureloc fl 
       where
         f.feature_id = ? and
         fl.feature_id = f.feature_id and
         f.feature_id = fl.feature_id
       order by fl.srcfeature_id
        ");

    my $jsth = $self->{dbh}->prepare("select name from gbrowse_assembly
                                      where feature_id = ?");

    # getting feature info    
    while (my $feature_id_ref = $sth->fetchrow_hashref) {
      $isth->execute($$feature_id_ref{'feature_id'}) 
             or $self->throw("getting feature info failed");
   
      #getting chromosome info 
      my $old_srcfeature_id=0;
      my $parent_segment;
      while (my $hashref = $isth->fetchrow_hashref) {

        if ($$hashref{'srcfeature_id'} != $old_srcfeature_id) {
          $jsth->execute($$hashref{'srcfeature_id'})
                 or die ("getting assembly info failed");
          my $src_name = $jsth->fetchrow_hashref;
          $parent_segment =
             Bio::DB::Das::Chado::Segment->new($$src_name{'name'},$self);
          $old_srcfeature_id=$$hashref{'srcfeature_id'};
        }
        #now build the feature

        my %termname = %{$self->{cvtermname}};

        my $feat = Bio::DB::Das::Chado::Segment::Feature->new(
                      $self,
                      $parent_segment,
                      $parent_segment->seq_id,
                      $$hashref{'nbeg'},$$hashref{'nend'},
                      $termname{$$hashref{'type_id'}},
                      $$hashref{'strand'},
                      $$hashref{'name'},
                      $$hashref{'name'},$$hashref{'feature_id'}
        ); 
        push @features, $feat;
      } 
 
    } 
  } else {
    $self->throw("multiword searching not supported yet");
  }

  @features;
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
[$name,$description,$score], where $name is the feature ID (accession?),
$description is a human-readable description such as a locus line, and
$score is the match strength.

=cut

=head2

search_notes is the sub to support keyword wildcard searching


sub search_notes {
  my $self = shift;
  my ($search_string,$limit) = @_;
  my $limit_str;
  if (defined $limit) {
    $limit_str = " LIMIT $limit ";
  } else {
    $limit_str = "";
  } 

# so here's the plan:
# if there is only 1 word, do 1-3
#  1. search for accessions like $string.'%'--if any are found, quit and return them
#  2. search for feature.name like $string.'%'--if found, keep and continue
#  3. search somewhere in analysis like $string.'%'--if found, keep and continue
# if there is more than one word, don't search accessions
#  4. search each word anded together like '%'.$string.'%' --if found, keep and continue
#  5. search somewhere in analysis like '%'.$string.'%'

  $self->{dbh}->trace(1);

  my @search_str = split /\s+/, $search_string;
  my $qsearch_term = $self->{dbh}->quote($search_str[0]);
  my $like_str = "( (dbx.accession ~* $qsearch_term OR \n"
        ."           f.name        ~* $qsearch_term) ";
  for (my $i=1;$i<(scalar @search_str);$i++) {
    $qsearch_term = $self->{dbh}->quote($search_str[$i]);
    $like_str .= "and \n";
    $like_str .= "          (dbx.accession ~* $qsearch_term OR \n"
                ."           f.name        ~* $qsearch_term) ";
  } 
  $like_str .= ")";

  my $sth = $self->{dbh}->prepare("
     select dbx.accession,f.name,0 
     from feature f, dbxref dbx
     where
        f.dbxrefstr = dbx.dbxrefstr and 
        $like_str 
     $limit_str
    ");
  $sth->execute or throw ("couldn't execute keyword query");

  my @results;
  while (my ($acc, $name, $score) = $sth->fetchrow_array) {
    $score = sprintf("%.2f",$score);
    push @results, [$acc, $name, $score];
  }
  @results;
}

=cut


=head2 _segclass

 Title   : _segclass
 Usage   : $class = $db->_segclass
 Function: returns the perl class that we use for segment() calls
 Returns : a string containing the segment class
 Args    : none
 Status  : reserved for subclass use

=cut

sub _segclass { return SEGCLASS }

sub absolute {return}

sub DESTROY {
        my $self = shift;
        $self->{dbh}->disconnect;
        return;
}

package Bio::DB::Das::ChadoIterator;

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

