
=head1 NAME

Bio::DB::Das::BioSQL::Segment - DAS-style access to a BioSQL database

=head1 SYNOPSIS

  # Get a Bio::Das::SegmentI object from a Bio::DB::Das::BioSQL database...

  #Should be created through Bio::DB::Das::BioSQL.

  @features = $segment->overlapping_features(-type=>['type1','type2']);
  # each feature is a Bio::SeqFeatureI-compliant object

  @features = $segment->contained_features(-type=>['type1','type2']);

  @features = $segment->contained_in(-type=>['type1','type2']);

  $stream = $segment->get_feature_stream(-type=>['type1','type2','type3'];
  while (my $feature = $stream->next_seq) {
     # do something with feature
  }

=head1 DESCRIPTION

Bio::DB::Das::BioSQL::Segment is a simplified alternative interface to
sequence annotation databases used by the distributed annotation
system. In this scheme, the genome is represented as a series of
landmarks.  Each Bio::DB::Das::BioSQL::Segment object ("segment") corresponds
to a genomic region defined by a landmark and a start and end position
relative to that landmark.  A segment is created using the Bio::DB::Das::BioSQL
segment() method.

The segment will load its features only when the features() method is called.
If start and end are not specified and features are requested, all the features
for the current segment will be retrieved, which may be slow.

Segment can be created as relative or absolute. If it's absolute ,all locations are given
beginning from segment's start, that is, they are between  [1 .. (end-start)].
Otherwise, they are given relative to the true start of the segment, irregardless of the start value.

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

package Bio::DB::Das::BioSQL::Segment;

use strict;
use Bio::Root::Root;
use Bio::Das::SegmentI;
use Bio::DB::Das::BioSQL::Iterator;
use constant DEBUG => 1;

*get_SeqFeatures = \&features;

use overload '""' => 'asString';

use vars '@ISA','$VERSION';
@ISA = qw(Bio::Root::Root Bio::SeqI Bio::Das::SegmentI);
$VERSION = 0.02;

#Construct a virtual segment.
sub new {
  my $self = shift;
  my ($bioseq, $dbadaptor, $start, $end, $absolute) =
       $self->_rearrange([qw(BIOSEQ DBADAPTOR START END ABSOLUTE)],
			@_);
       
  $start = 1 unless defined $start;
  $end   = $bioseq->length unless defined $end;
  
  #I'd like to do that. However, this means that $end will be greater than length,
  #and biosql code does not like it.
  #$bioseq->seq(substr($bioseq->seq, $start-1, ($end-$start)));
  
  return bless {bioseq    =>  $bioseq,
		dbadaptor =>  $dbadaptor,
		start  =>  $start,
		end    =>  $end,
		absolute => $absolute},ref $self || $self;
}

=head2 seq_id

 Title   : seq_id
 Usage   : $ref = $s->seq_id
 Function: return the ID of the landmark
 Returns : a string
 Args    : none
 Status  : Public

=cut

sub seq_id { shift->{bioseq}->accession_number; }

=head2 start

 Title   : start
 Usage   : $s->start
 Function: start of segment
 Returns : integer
 Args    : none
 Status  : Public

This is a read-only accessor for the start of the segment. 

=cut

sub start { shift->{start} }

=head2 end

 Title   : end
 Usage   : $s->end
 Function: end of segment
 Returns : integer
 Args    : none
 Status  : Public

This is a read-only accessor for the end of the segment.

=cut

sub end   { shift->{end} }


=head2 abs_start

 Title   : abs_start
 Usage   : $s->abs_start
 Function: start of segment
 Returns : integer
 Args    : none
 Status  : Public

Return the absolute start of the segment

=cut

sub abs_start
{
    return 1;
}

=head2 abs_end

 Title   : abs_end
 Usage   : $s->abs_end
 Function: end of segment
 Returns : integer
 Args    : none
 Status  : Public

Return the absolute end of the segment

=cut

sub abs_end
{
    my ($self) = @_;
    return $self->end - $self->start + 1;
}
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
  my ($start,$end) = @{shift()}{'start','end'};
  $end - $start + 1;
}


=head2 absolute

 Title   : absolute
 Usage   : $s->absolute
 Function: whether the positions are counted from the true start of the segment
            or from the start value
 Returns : boolean
 Args    : none
 Status  : Public

This is a read-only accessor.

=cut

sub absolute   {
    my $self = shift;
    my $d    = $self->{absolute};
    $self->{absolute} = shift if @_;
    $d;
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
  return () unless @_;
  my ($types,$attributes,$rangetype,$iterator,$callback);

  if ($_[0] =~ /^-/) {
    ($types,$attributes,$rangetype,$iterator,$callback) =
      $self->_rearrange([qw(TYPES ATTRIBUTES RANGETYPE ITERATOR CALLBACK)],@_);
  } else {
    $types = \@_;
  }

  if ($types && !ref $types) {
      $types = [$types];
  }
  
  my @features = $self->top_SeqFeatures();

  if ($types) {
      my %types = map {lc $_=>1} @$types;
      @features = grep {$types{lc $_->method}} @features;
  }

  if ($iterator) {
    return Bio::DB::Das::BioSQL::Iterator->new(\@features);
  } else {
    return @features;
  }
}

=head2 top_SeqFeatures

 Title   : top_SeqFeatures
 Usage   : $s->top_SeqFeatures
 Function: retrieve an array of features from the underlying BioDB object.
 Returns : an array
 Args    : none
 Status  : Private

First, make the adaptor retrieve the feature objects from the database.
Then, get the actual objects and adjust the features' locations if necessary.

=cut

sub top_SeqFeatures
{
    my ($self) = @_;

    $self->bioseq->adaptor->slow_attach_children($self->bioseq, $self->start, $self->end);
    
    my @result = map {$self->wrap_feature($_)} $self->bioseq->get_SeqFeatures();
    
    unless ($self->absolute)
    {
        foreach my $feat (@result)
        {
            #$feat->start($feat->start - $self->start);
            foreach my $loc ($feat->location->each_Location)
            {
                $loc->start($loc->start - $self->start + 1);
                $loc->end($loc->end - $self->start + 1);
            }
        }
    }
    return @result;
    
}


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

NOTE: In the interface this method is aliased to get_feature_stream(),
as the name is more descriptive.

=cut

sub get_seq_stream {
  my @features = shift->features(@_);
  return Bio::DB::Das::BioSQL::Iterator->new(\@features);
}

=head2 seq

 Title   : seq
 Usage   : $s->seq
 Function: get the sequence string for this segment
 Returns : a string
 Args    : none
 Status  : Public

Returns the sequence for this segment as a Bio::PrimarySeq object.

=cut

sub seq {
  my $self = shift;
  my $seq = Bio::PrimarySeq->new(-seq=>$self->bioseq->subseq($self->start,$self->end),
				 -id => $self->seq_id);
  return $seq;
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
  
=head2 asString

 Title   : asString
 Usage   : $s->asString
 Function: human-readable representation of the segment
 Returns : a string
 Args    : none
 Status  : Public

This method will return a human-readable representation of the
segment.  It is the overloaded method call for the "" operator.

Currently the format is:

  refseq:start,stop

=cut

sub asString {
   my $self = shift;
   my $label = $self->display_name;
   my $start = $self->start || '';
   my $stop  = $self->stop  || '';
   return "$label:$start,$stop";
}

sub name { shift->asString }
sub type { 'Segment' }
sub source_tag  {'BioSQL'}
sub class  {'Segment'}

#Have to return bioseq->obj, not the wrapper around it (bioseq),
#because some classes check for the exact class name.
sub primary_seq {return shift->bioseq->obj}
sub dna {return shift->seq}

#Forwarding various access methods to the underlying objects.
sub alphabet   { shift->bioseq->alphabet(@_) }
sub display_id { shift->bioseq->display_id(@_) }
sub accession_number { shift->bioseq->display_id(@_) }
sub desc       { shift->bioseq->desc(@_) }

sub display_name {shift->bioseq->display_id(@_)}
sub location {return shift}

sub is_circular {return shift->bioseq->is_circular}
sub annotation {return shift->bioseq->annotation}
sub species {return shift->bioseq->species}
sub version {return shift->bioseq->version}

sub subseq { shift->seq }

sub overlaps {
  my $self          = shift;
  my $other_segment = shift or return;
  my $start = $self->start;
  my $end   = $self->end;
  my $other_start = $other_segment->start;
  my $other_end   = $other_segment->end;

  return $end >= $other_start && $start <= $other_end;
}

# compatibility with Bio::DB::GFF::RelSegment
*abs_ref = \&accession_number;

sub wrap_feature {
    my $self = shift;
    return Bio::DB::Das::BioSQL::Feature->new(shift);
}

package Bio::DB::Das::BioSQL::Feature;

use base 'Bio::DB::Persistent::SeqFeature';

sub new {
    my $class = shift;
    my $obj   = shift;
    return bless $obj,ref $class || $class;
}
sub seq_id {
    my $self = shift;
    return eval{$self->seq->id};
}

sub ref { shift->seq_id }

sub display_name {
    my $self = shift;
    for my $tag (qw(name label locus_tag db_xref product)) {
	next unless $self->has_tag($tag);
	my ($value) = $self->get_tag_values($tag);
	return $value;
    }
    return $self->primary_tag."(".$self->primary_key.")";
}

sub attributes {
    shift->get_tag_values();
}
sub method { 
    shift->primary_tag;
}
sub type {
    my $self = shift;
    my $method = $self->primary_tag;
    my $source = $self->source_tag;
    $method .= ":$source" if defined $source;
    return $method;
}
sub name       { shift->display_name }
sub primary_id { shift->primary_key }
sub abs_ref   { shift->ref }
sub abs_start { shift->start }
sub abs_end   { shift->end  }
sub abs_stop  { shift->end  }
sub class     { shift->method  }

1;
