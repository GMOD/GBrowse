# $Id: Segment.pm,v 1.24 2003-03-05 21:11:29 scottcain Exp $

=head1 NAME

Bio::DB::Das::Chado::Segment - DAS-style access to a chado database

=head1 SYNOPSIS

  # Get a Bio::Das::SegmentI object from a Bio::DB::Das::Chado database...

  $segment = $das->segment(-name=>'Landmark',
                           -start=>$start,
te that there is currently a hack in Segment.pm to make it work with
chado/gadfly: the search space for names of segments is in a small
table named gbrowse_assembly, which contains only chromosome arms,
as extracted directly from the feature table.  This is done because
gbrowse generally only creates segments out of a large reference
sequence (like an arm), and there is no good, fast way to look up
arm names in chado: the feature table is too big (affecting performance
of a common command), and the synonym tables does not contain arm
names.  In order for Segment.pm to be a general chado tool, this
will have to be addressed, as it is possible that another use of
Segment.pm may need to create a segment out of something else.

                           -end => $end);

  @features = $segment->overlapping_features(-type=>['type1','type2']);
  # each feature is a Bio::SeqFeatureI-compliant object

  @features = $segment->contained_features(-type=>['type1','type2']);

  @features = $segment->contained_in(-type=>['type1','type2']);

  $stream = $segment->get_feature_stream(-type=>['type1','type2','type3'];
  while (my $feature = $stream->next_seq) {
     # do something with feature
  }

  $count = $segment->features_callback(-type=>['type1','type2','type3'],
                                       -callback => sub { ... { }
                                       );

=head1 DESCRIPTION

Note that there is currently a hack in Segment.pm to make it work with
chado/gadfly: the search space for names of segments is in a small
table named gbrowse_assembly, which contains only chromosome arms,
as extracted directly from the feature table.  This is done because
gbrowse generally only creates segments out of a large reference
sequence (like an arm), and there is no good, fast way to look up
arm names in chado: the feature table is too big (affecting performance
of a common command), and the synonym tables does not contain arm
names.  In order for Segment.pm to be a general chado tool, this 
will have to be addressed, as it is possible that another use of 
Segment.pm may need to create a segment out of something else.

Bio::DB::Das::Chado::Segment is a simplified alternative interface to
sequence annotation databases used by the distributed annotation
system. In this scheme, the genome is represented as a series of
landmarks.  Each Bio::DB::Das::Chado::Segment object ("segment") corresponds
to a genomic region defined by a landmark and a start and end position
relative to that landmark.  A segment is created using the Bio::DasI
segment() method.

Features can be filtered by the following attributes:

  1) their location relative to the segment (whether overlapping,
          contained within, or completely containing)

  2) their type

  3) other attributes using tag/value semantics

Access to the feature list uses three distinct APIs:

  1) fetching entire list of features at a time

  2) fetching an iterator across features

  3) a callback

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

package Bio::DB::Das::Chado::Segment;

use strict;
use Bio::Root::Root;
use Bio::Das::SegmentI;
use Bio::DB::Das::Chado::Segment::Feature;
use constant DEBUG => 0;

use vars '@ISA','$VERSION','$ASSEMBLY_TYPE';
@ISA = qw(Bio::Root::Root Bio::SeqI Bio::Das::SegmentI);
$VERSION = 0.02;
$ASSEMBLY_TYPE = 'arm'; #this should really be set in a config file
                        # well, it shouldn't really need to be anywhere, 
                        # it is just a speed hack

# construct a virtual segment that works in a lazy way
sub new {
 #validate that the name/accession is valid, and start and end are valid,
 #then return a new segment

  my $self  = shift;

  my ($name,$factory,$start,$end) = @_;

    warn "$name, $factory\n" if DEBUG;
    warn "start = $start, end = $end\n" if DEBUG;

  $self->throw("start value less than 1\n") if (defined $start && $start < 1);
  $start = $start ? int($start) : 1; 

#moved length determination to constructor, now it will be there from
# 'the beginning'.

  my $quoted_name = $factory->{dbh}->quote($name);

  warn "$quoted_name\n" if DEBUG;

  my $cvterm_id = $factory->{cvterm_id};

  my $sth = $factory->{dbh}->prepare ("
             select name,feature_id,seqlen from gbrowse_assembly
             where type_id = ". $$cvterm_id{$ASSEMBLY_TYPE} ." and
                   name ilike $quoted_name  ");

    warn "prepared:$sth\n" if DEBUG ;

  $sth->execute or $self->throw("unable to validate name/length");

    warn "executed\n" if DEBUG;

  my $hash_ref = {};
  my $length;
  my $rows_returned = $sth->rows;
  if ($rows_returned != 1) { #look in synonym for an exact match
    my $isth = $factory->{dbh}->prepare ("
       select fs.feature_id from feature_synonym fs, synonym s
       where fs.synonym_id = s.synonym_id and
       synonym ilike $quoted_name
        "); 
    $isth->execute or $self->throw("query for name failed"); 
    $rows_returned = $isth->rows;

    if ($rows_returned != 1) { #look in dbxref for accession number match
      $isth = $factory->{dbh}->prepare ("
         select feature_id from feature_dbxref fd, dbxref d
         where fd.dbxrefstr = d.dbxrefstr and
               d.accession ilike $quoted_name ");
      $isth->execute or $self->throw("query for accession failed");
      $rows_returned = $isth->rows;

      return if $rows_returned != 1;
    }

    $hash_ref = $isth->fetchrow_hashref;

    my $landmark_feature_id = $$hash_ref{'feature_id'};

    $sth = $factory->{dbh}->prepare ("
       select ga.name,ga.feature_id,ga.seqlen,fl.min,fl.max
       from gbrowse_assembly ga, featureloc fl
       where fl.feature_id = $landmark_feature_id and
             fl.srcfeature_id = ga.feature_id
         ");
    $sth->execute or throw("synonym to assembly query failed");
    
  }

  $hash_ref = $sth->fetchrow_hashref;
  $length =  $$hash_ref{'seqlen'};
  my $srcfeature_id = $$hash_ref{'feature_id'};
  $name = $$hash_ref{'name'};

  if ($$hash_ref{'min'}) {
    $start = $$hash_ref{'min'};
    $end   = $$hash_ref{'max'};
  }

    warn "length:$length, srcfeature_id:$srcfeature_id\n" if DEBUG;

  $self->throw("end value greater than length\n") if (defined $end && $end > $length);
  $end = $end ? int($end) : $length;
  $length = $end - $start +1;

  return bless {factory       => $factory,
                start         => $start,
                end           => $end,
                length        => $length,
                srcfeature_id => $srcfeature_id,
                name          => $name }, ref $self || $self;
}


=head2 seq_id

 Title   : seq_id
 Usage   : $ref = $s->seq_id
 Function: return the ID of the landmark
 Returns : a string
 Args    : none
 Status  : Public

=cut

sub seq_id {  shift->{name} } 

=head2 start

 Title   : start
 Usage   : $s->start
 Function: start of segment
 Returns : integer
 Args    : none
 Status  : Public

This is a read-only accessor for the start of the segment.  Alias
to low() for Gadfly compatibility.

=cut

sub start { shift->{start} } 

=head2 end

 Title   : end
 Usage   : $s->end
 Function: end of segment
 Returns : integer
 Args    : none
 Status  : Public

This is a read-only accessor for the end of the segment. Alias to
high() for Gadfly compatibility.

=cut

sub end   { shift->{end} } 

=head2 length

 Title   : length
 Usage   : $s->length
 Function: length of segment
 Returns : integer
 Args    : none
 Status  : Public

Returns the length of the segment.  Always a positive number.

=cut

sub length { shift->{length} } 

=head2 features

 Title   : features
 Usage   : @features = $s->features(@args)
 Function: get features that overlap this segment
 Returns : a list of Bio::SeqFeatureI objects
 Args    : see below
 Status  : Public

Note: There is a hack in this method to increase speed that may or
may not work well with a given instance of postgres/chado.  For the
query to find features, Seq Scans (same as Table Scans in some other
database) have been disabled, in order to force the use of an index.

This method will find all features that intersect the segment in a
variety of ways and return a list of Bio::SeqFeatureI objects.  The
feature locations will use coordinates relative to the reference
sequence in effect at the time that features() was called.

The returned list can be limited to certain types, attributes or
range intersection modes.  Types of range intersection are one of:

   "overlaps"      the default
   "contains"      return features completely contained within the segment
   "contained_in"  return features that completely contain the segment

Two types of argument lists are accepted.  In the positional argument
form, the arguments are treated as a list of feature types.  In the
named parameter form, the arguments are a series of -name=E<gt>value
pairs.

  Argument    Description
  --------   ------------

  -types      An array reference to type names in the format
	      "method:source"

  -attributes A hashref containing a set of attributes to match

  -rangetype  One of "overlaps", "contains", or "contained_in".

  -iterator   Return an iterator across the features.

  -callback   A callback to invoke on each feature

The -attributes argument is a hashref containing one or more
attributes to match against:

  -attributes => { Gene => 'abc-1',
                   Note => 'confirmed' }

Attribute matching is simple string matching, and multiple attributes
are ANDed together.  More complex filtering can be performed using the
-callback option (see below).

If -iterator is true, then the method returns an object reference that
implements the next_seq() method.  Each call to next_seq() returns a
new Bio::SeqFeatureI object.

If -callback is passed a code reference, the code reference will be
invoked on each feature returned.  The code will be passed two
arguments consisting of the current feature and the segment object
itself, and must return a true value. If the code returns a false
value, feature retrieval will be aborted.

-callback and -iterator are mutually exclusive options.  If -iterator
is defined, then -callback is ignored.

=cut

sub features {
  my $self = shift;

    warn "Segment->features() args:@_\n" if DEBUG;

  my ($types,$attributes,$rangetype,$iterator,$callback);
  if ($_[0] =~ /^-/) {
    ($types,$attributes,$rangetype,$iterator,$callback) =
      $self->_rearrange([qw(TYPE ATTRIBUTES RANGETYPE ITERATOR CALLBACK RARE)],@_);
  } else {
    $types = \@_;
  }

  warn "@$types\n" if (defined $types and DEBUG);

  my $feat     = Bio::DB::Das::Chado::Segment::Feature->new ();
  my @features;
  $rangetype ||='overlaps';

# set range variable 

  my $rstart = $self->start;
  my $rend   = $self->end;
  my $sql_range;
  if ($rangetype eq 'contains') {

    $sql_range = " fl.min >= $rstart and fl.max M= $rend ";

  } elsif ($rangetype eq 'contained_in') {

    $sql_range = " fl.min <= $rstart and fl.max >= $rend ";

  } else { #overlaps is the default

    $sql_range = " fl.min <= $rend and fl.max >= $rstart ";

  }

# set type variable 

  my %termhash = %{$self->{factory}->{cvterm_id}};

  my @keys;
  foreach my $type (@$types) {
    my @tempkeys = grep(/\b\Q$type\E\b/i , keys %termhash );
    push @keys, @tempkeys;
  }

  my $sql_types = '';

  if (scalar @keys != 0) {
    $sql_types .= "(f.type_id = ".$termhash{$keys[0]};

    if (scalar @keys > 1) {
      for(my $i=1;$i<(scalar @keys);$i++) {
        $sql_types .= " OR \n     f.type_id = ".$termhash{$keys[$i]};
      }
    }
    $sql_types .= ") and ";
  }

#$self->{factory}->{dbh}->trace(1);

  my $srcfeature_id = $self->{srcfeature_id};

  $self->{factory}->{dbh}->do("set enable_seqscan=0");
  my $sth = $self->{factory}->{dbh}->prepare("
    select distinct f.name,fl.min,fl.max,fl.strand,f.type_id,f.feature_id
    from feature f, featureloc fl
    where
      $sql_types 
      fl.srcfeature_id = $srcfeature_id and
      f.feature_id  = fl.feature_id and
      $sql_range
       ");
   $sth->execute or $self->throw("feature query failed"); 
   $self->{factory}->{dbh}->do("set enable_seqscan=1");

#$self->{factory}->{dbh}->trace(0);
#take these results and create a list of Bio::SeqFeatureI objects

  my %termname = %{$self->{factory}->{cvtermname}};
  while (my $hashref = $sth->fetchrow_hashref) {

    my $stop  = $$hashref{max};
    my $start = $$hashref{min};

#    warn "-->$$hashref{name}<--\n";

    $feat = Bio::DB::Das::Chado::Segment::Feature->new (
                       $self->{factory},
                       $self,
                       $self->seq_id,
                       $start,$stop,
                       $termname{$$hashref{type_id}},
                       $$hashref{strand},
                       $$hashref{name},
                       $$hashref{name},$$hashref{feature_id});  

    push @features, $feat;
 
    my $fstart = $feat->start() if DEBUG;
    my $fend   = $feat->end()   if DEBUG;  
  #  warn "$feat->{annotation}, $$hashref{nbeg}, $fstart, $$hashref{nend}, $fend\n" if DEBUG;
  }

  if ($iterator) {
   warn "using Bio::DB::Das::ChadoIterator\n" if DEBUG;
    return Bio::DB::Das::ChadoIterator->new(\@features);
  } else {
    return @features;
  }
}
=head2 seq

 Title   : seq
 Usage   : $s->seq
 Function: get the sequence string for this segment
 Returns : a string
 Args    : none
 Status  : Public

Returns the sequence for this segment as a simple string.

=cut

sub seq {
  my $self = shift;

  my $feat_id = $self->{srcfeature_id};
  my $sth = $self->{factory}->{dbh}->prepare("
     select residues from feature 
     where feature_id = $feat_id ");
  $sth->execute or $self->throw("seq query failed");

  my $hash_ref = $sth->fetchrow_hashref;
  return $$hash_ref{'residues'};
}


=head2 factory

 Title   : factory
 Usage   : $factory = $s->factory
 Function: return the segment factory
 Returns : a Bio::DasI object
 Args    : see below
 Status  : Public

This method returns a Bio::DasI object that can be used to fetch
more segments.  This is typically the Bio::DasI object from which
the segment was originally generated.

=cut

#'

sub factory {shift->{factory} } 
sub alphabet {return 'dna'; } 
sub display_id {shift->{name} };
sub display_name {shift->{name} } 
sub accession_number {shift->{name} } 
sub desc {shift->{name} } 


sub get_feature_stream {
  my $self = shift;
  my @args = @_;
  my @features = $self->features(@args);
    warn "get_feature_stream args: @_\n" if DEBUG;
    warn "using get_feature_stream\n" if DEBUG;
    warn "feature array: @features\n" if DEBUG;
  return Bio::DB::Das::ChadoIterator->new(\@features);
}

=head2 clone

 Title   : clone
 Usage   : $copy = $s->clone
 Function: make a copy of this segment
 Returns : a Bio::DB::GFF::Segment object
 Args    : none
 Status  : Public

This method creates a copy of the segment and returns it.

=cut

# deep copy of the thing
sub clone {
  my $self = shift;
  my %h = %$self;
  return bless \%h,ref($self);
}


1;
