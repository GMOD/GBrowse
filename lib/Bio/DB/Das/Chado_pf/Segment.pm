# $Id: Segment.pm,v 1.5 2002-12-03 03:22:54 scottcain Exp $

=head1 NAME

Bio::DB::Das::Chado_pf::Segment - DAS-style access to a chado_pf database

=head1 SYNOPSIS

NOTES: required methods:
        seq_id
        start
        end
        length
        features
        seq
        factory

  # Get a Bio::Das::SegmentI object from a Bio::DB::Das::Chado_pf database...

  $segment = $das->segment(-name=>'Landmark',
                           -start=>$start,
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

Bio::DB::Das::Segment is a simplified alternative interface to
sequence annotation databases used by the distributed annotation
system. In this scheme, the genome is represented as a series of
landmarks.  Each Bio::DB::Das::Segment object ("segment") corresponds
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

package Bio::DB::Das::Chado_pf::Segment;

use strict;
use Bio::Root::Root;
use Bio::Das::SegmentI;
use constant DEBUG => 1;

use vars '@ISA','$VERSION';
@ISA = qw(Bio::Root::Root Bio::SeqI Bio::Das::SegmentI);
$VERSION = 0.01;

# construct a virtual segment that works in a lazy way
sub new {
 #validate that the name/accession is valid, and start and end are valid,
 #then return a new segment
  my $self = shift;
  my ($name,$dbadaptor,$start,$end) = @_;

  throw("start value less than 1\n") if (defined $start && $start < 1);
  $start ||= 1;

#can I cache this value?
  my $length = $self->length;
  throw("end value greater than length\n") if (defined $end && $end >= $length);
  $end ||= $length;

  return $self;
}


=head2 seq_id

 Title   : seq_id
 Usage   : $ref = $s->seq_id
 Function: return the ID of the landmark
 Returns : a string
 Args    : none
 Status  : Public

=cut

sub seq_id {  shift->name; }

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

sub length {

  if (self->length) {
    return self->length;
  } else {
    my $quoted_name = $dbadaptor->quote($self->$name);
    my $sth = $dbadaptor->prepare ("
     select seqlen from feature where feature_id in  
       (select f.feature_id
        from dbxref dbx, feature f, feature_dbxref fd
        where f.type_id = 6 and
           f.feature_id = fd.feature_id and
           fd.dbxref_id = dbx.dbxref_id and
           dbx.accession = $name) ");
    $sth->execute or return;

    my $hash_ref = $sth->fetchrow_hashref;
    return $$hash_ref{'seqlen'};
  }
}

=head2 features

 Title   : features
 Usage   : @features = $s->features(@args)
 Function: get features that overlap this segment
 Returns : a list of Bio::SeqFeatureI objects
 Args    : see below
 Status  : Public

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

NOTE: In his implementation, -attributes does exactly nothing, and features()
is wildly inefficient because it works by calling top_SeqFeatures and then
filters by position in the Perl layer, rather than filtering by position in
the SQL layer.

=cut

sub features {
  my $self = shift;
  my ($types,$attributes,$rangetype,$iterator,$callback);
  if ($_[0] =~ /^-/) {
    ($types,$attributes,$rangetype,$iterator,$callback) =
      $self->_rearrange([qw(TYPES ATTRIBUTES RANGETYPE ITERATOR CALLBACK)],@_);
  } else {
    $types = \@_;
  }
  my %filter_args;
  $filter_args{rangetype} = $rangetype || 'overlaps';
  $filter_args{range}     = [$self->start,$self->end];
  $filter_args{types}     = $types if $types && ref $types eq 'ARRAY' && @$types;

  my @features          = $self->bioseq->top_SeqFeatures;
  my @filtered_features = $self->_filter(\@features,\%filter_args,$callback);
  if ($iterator) {
    return Bio::DB::Das::Chado_pfIterator->new(\@filtered_features);
  } else {
    return @filtered_features;
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


   #sql to get the sequence
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

sub factory {shift->{dbadaptor}}

=head2 bioseq

 Title   : bioseq
 Usage   : $bioseq = $s->bioseq
 Function: return the underlying Bio::Seq object
  Returns : a Bio::Seq object
 Args    : none
 Status  : Public

=cut

sub bioseq { shift->{bioseq} }

=head2 _filter

 Title   : _filter
 Usage   : @filtered = $s->_filter($features,$filter_args,$callback);
 Function: filter a list of Bio::SeqFeatureI features
 Returns : a list of features filtered as specified
 Args    :
  $features      an arrayref of Bio::SeqFeatureI features
  $filter_args   a hashref specifying the filtering
  $callback      a coderef to be invoked on each filtered feature

  The keys to the filtering hashref are
    'rangetype'  one of "overlaps", "contains", and "contained_in"
    'range'      an arrayref containing start and endpoints
    'types'      an arrayref containing list of feature types to filter on

 Status  : for internal use

=cut

sub _filter {
  my $self = shift;
  my ($features,$args,$callback) = @_;

  my @filter = "sub {";
  push @filter,"my \$feature = shift;";

  if (my $range = $args->{range}) {
    my $rangetype = $args->{rangetype};
    my ($rstart,$rend) = @$range;
    push @filter,"my(\$start,\$end) = (\$feature->location->start,\$feature->location->end);";
    if ($rangetype eq 'overlaps') {
      push @filter,"return unless $rstart <= \$end;";
      push @filter,"return unless $rend   >= \$start;";
    } elsif ($rangetype eq 'contains') {
      push @filter,"return unless $rstart <= \$start;";
      push @filter,"return unless $rend   >= \$end;";
    } elsif ($rangetype eq 'contained_in') {
      push @filter,"return unless $rstart >= \$start;";
      push @filter,"return unless $rend   <= \$end;";
    }
  }

  if (my $types = $args->{types}) {
    my $l = join '|',map {quotemeta($_)} @$types;
    my $regexp = "^($l)\$";
    push @filter,"my \$type = \$feature->primary_tag;";
    push @filter,"return unless \$type =~ /$regexp/;";
  }

  push @filter,"return 1;";
  push @filter,"}";

  my $filter = join "\n",@filter;  # to make it easier to see
  warn $filter,"\n" if DEBUG;
  my $code = eval $filter or $self->throw("Couldn't create filter, compile error = @_");

  if ($callback) {
    foreach my $f (grep {$code->($_)} @$features) {
      last unless $callback->($f,$self);
    }
    return;
  }

  grep {$code->($_)} @$features;

}

sub alphabet   { shift->bioseq->alphabet(@_) }
sub display_id { shift->bioseq->display_id(@_) }
sub accession_number { shift->bioseq->display_id(@_) }
sub desc       { shift->bioseq->desc(@_) }


1;
