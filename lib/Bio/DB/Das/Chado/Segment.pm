# $Id: Segment.pm,v 1.45 2004-01-20 20:48:09 scottcain Exp $

=head1 NAME

Bio::DB::Das::Chado::Segment - DAS-style access to a chado database

=head1 SYNOPSIS

  # Get a Bio::Das::SegmentI object from a Bio::DB::Das::Chado database...

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

use vars '@ISA', '$VERSION';
@ISA     = qw(Bio::Root::Root Bio::SeqI Bio::Das::SegmentI Bio::DB::Das::Chado);
$VERSION = 0.11;

# construct a virtual segment that works in a lazy way
sub new {

    #validate that the name/accession is valid, and start and end are valid,
    #then return a new segment

    my $self = shift;

    my ( $name, $factory, $base_start, $end, $db_id ) = @_;

    warn "$name, $factory\n"                      if DEBUG;
    warn "base_start = $base_start, end = $end\n" if DEBUG;

    $self->Bio::Root::Root->throw("start value less than 1\n")
      if ( defined $base_start && $base_start < 1 );
    $base_start = $base_start ? int($base_start) : 1;
    my $interbase_start = $base_start - 1;

    my $quoted_name = $factory->{dbh}->quote( lc $name );

    warn "quoted name:$quoted_name\n" if DEBUG;

    my $srcfeature_query = $factory->{dbh}->prepare( "
       select srcfeature_id from featureloc
       where feature_id = ?
         " );

    my $landmark_is_src_query = $factory->{dbh}->prepare( "
       select f.name,f.feature_id,f.seqlen,f.type_id
       from feature f
       where f.feature_id = ?
         " );

    my $feature_query = $factory->{dbh}->prepare( "
       select f.name,f.feature_id,f.seqlen,f.type_id,fl.fmin,fl.fmax
       from feature f, featureloc fl
       where fl.feature_id = ? and
             ? = f.feature_id
         " );

    my $fetch_uniquename_query = $factory->{dbh}->prepare( "
       select name,fmin,fmax,uniquename from feature
       where feature_id = ?
         ");

    my $ref = _search_by_name( $factory, $quoted_name, $db_id );

    #returns either a feature_id scalar (if there is only one result)
    #or an arrayref (of feature_ids) if there is more than one result
    #or nothing if there is no result

    if ( ref $ref eq 'ARRAY' ) {    #more than one result returned

        my @segments;

        foreach my $feature_id (@$ref) {

            $fetch_uniquename_query->execute($feature_id )
              or Bio::Root::Root->throw("fetching uniquename from feature_id failed") ;

            my $hashref = $fetch_uniquename_query->fetchrow_hashref;
            $base_start = $$hashref{fmin} + 1;
            $end        = $$hashref{fmax};
            $db_id      = $$hashref{uniquename};            

            push @segments, $factory->segment($name,$factory,$base_start,$end,$db_id);
        }

        if (@segments < 2) {
            return $segments[0]; #I don't think this should ever happen
        }
        elsif (wantarray) {
            return @segments;
        }
        else {
            warn "The query for $name returned multiple segments\nPlease call in a list context to get them all";
            Bio::Root::Root->throw("multiple segment exception") ;
        }
    }
    elsif ( ref $ref eq 'SCALAR' ) {    #one result returned

        my $landmark_feature_id = $$ref;

        $srcfeature_query->execute($landmark_feature_id)
           or Bio::Root::Root->throw("finding srcfeature_id failed");

        my $hash_ref      = $srcfeature_query->fetchrow_hashref;
        my $srcfeature_id =
            $$hash_ref{'srcfeature_id'}
          ? $$hash_ref{'srcfeature_id'}
          : $landmark_feature_id;

        warn "srcfeature_id:$srcfeature_id" if DEBUG;
 
        if ( $landmark_feature_id == $srcfeature_id ) {

            $landmark_is_src_query->execute($landmark_feature_id)
              or Bio::Root::Root->throw("something else failed");
            $hash_ref = $landmark_is_src_query->fetchrow_hashref;

        }
        else {

            $feature_query->execute($landmark_feature_id,$srcfeature_id)
              or Bio::Root::Root->throw("something else failed");
            $hash_ref = $feature_query->fetchrow_hashref;
 
        }

        $name = $$hash_ref{'name'};
        my $length = $$hash_ref{'seqlen'};
        my $type   = $factory->{cvname}{ $$hash_ref{'type_id'} };

        if ( $$hash_ref{'fmin'} ) {
            $interbase_start = $$hash_ref{'fmin'};
            $base_start      = $interbase_start + 1;
            $end             = $$hash_ref{'fmax'};
        }

        warn "base_start:$base_start, end:$end, length:$length" if DEBUG;

        $self->Bio::Root::Root::throw("end value greater than length\n")
          if ( defined $end && $end > $length );
        $end    = $end ? int($end) : $length;
        $length = $end - $interbase_start;

        return bless {
            factory       => $factory,
            start         => $base_start,
            end           => $end,
            length        => $length,
            srcfeature_id => $srcfeature_id,
            class         => $type,
            name          => $name
          },
          ref $self || $self;

    }
    else {
        warn "no segment found" if DEBUG;
        return;    #nothing returned
    }
}

=head2 _search_by_name

=cut

sub _search_by_name {
    my ( $factory, $quoted_name, $db_id ) = @_;

      # if there is a db_id sent, short circuit the search
    if ($db_id) {
        my $sth = $factory->{dbh}->prepare( "
       select feature_id from feature where uniquename = ?"); 

        $sth->execute($db_id) 
            or Bio::Root::Root->throw("getting feature_id from uniquename failed");

        my $hashref = $sth->fetchrow_hashref;
        my $feature_id = $$hashref{'feature_id'};
        return \$feature_id;
    }

    my $sth = $factory->{dbh}->prepare( "
             select name,feature_id,seqlen from feature
             where lower(name) = $quoted_name  " );

    $sth->execute or Bio::Root::Root->throw("unable to validate name/length");

    my $rows_returned = $sth->rows;
    if ( $rows_returned == 0 ) {    #look in synonym for an exact match
        my $isth = $factory->{dbh}->prepare( "
       select fs.feature_id from feature_synonym fs, synonym s
       where fs.synonym_id = s.synonym_id and
       lower(s.synonym_sgml) = $quoted_name
        " );
        $isth->execute
          or Bio::Root::Root->throw("query for name in synonym failed");
        $rows_returned = $isth->rows;

        if ( $rows_returned == 0 ) {  #look in dbxref for accession number match
            $isth = $factory->{dbh}->prepare( "
         select feature_id from feature_dbxref fd, dbxref d
         where fd.dbxref_id = d.dbxref_id and
               lower(d.accession) = $quoted_name " );
            $isth->execute
              or Bio::Root::Root->throw("query for accession failed");
            $rows_returned = $isth->rows;

            return if $rows_returned == 0;

            if ( $rows_returned == 1 ) {
                my $hashref    = $isth->fetchrow_hashref;
                my $feature_id = $$hashref{'feature_id'};
                return \$feature_id;
            }
            else {
                my @feature_ids;
                while ( my $hashref = $isth->fetchrow_hashref ) {
                    push @feature_ids, $$hashref{'feature_id'};
                }
                return \@feature_ids;
            }

        }
        elsif ( $rows_returned == 1 ) {
            my $hashref    = $isth->fetchrow_hashref;
            my $feature_id = $$hashref{'feature_id'};
            return \$feature_id;
        }
        else {
            my @feature_ids;
            while ( my $hashref = $isth->fetchrow_hashref ) {
                push @feature_ids, $$hashref{'feature_id'};
            }
            return \@feature_ids;
        }

    }
    elsif ( $rows_returned == 1 ) {
        my $hashref    = $sth->fetchrow_hashref;
        my $feature_id = $$hashref{'feature_id'};
        return \$feature_id;
    }
    else {
        my @feature_ids;
        while ( my $hashref = $sth->fetchrow_hashref ) {
            push @feature_ids, $$hashref{'feature_id'};
        }
        return \@feature_ids;
    }
}

sub class {
    my $self = shift;
    return $self->{class};
}

=head2 seq_id

 Title   : seq_id
 Usage   : $ref = $s->seq_id
 Function: return the ID of the landmark
 Returns : a string
 Args    : none
 Status  : Public

=cut

sub seq_id { shift->{name} }

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
*low = \&start;

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

sub end { shift->{end} }
*high = \&end;
*stop = \&end;

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

    my ( $types, $attributes, $rangetype, $iterator, $callback );
    if ( $_[0] =~ /^-/ ) {
        ( $types, $attributes, $rangetype, $iterator, $callback ) =
          $self->_rearrange(
            [qw(TYPE ATTRIBUTES RANGETYPE ITERATOR CALLBACK RARE)], @_ );

        #  warn "$types\n";
    }
    else {
        $types = \@_;
    }

    warn "@$types\n" if ( defined $types and DEBUG );

    my $feat = Bio::DB::Das::Chado::Segment::Feature->new();
    my @features;
    $rangetype ||= 'overlaps';

    # set range variable

    my $base_start      = $self->start;
    my $interbase_start = $base_start - 1;
    my $rend            = $self->end;
    my $sql_range;
    if ( $rangetype eq 'contains' ) {

        $sql_range = " fl.fmin >= $interbase_start and fl.fmax <= $rend ";

    }
    elsif ( $rangetype eq 'contained_in' ) {

        $sql_range = " fl.fmin <= $interbase_start and fl.fmax >= $rend ";

    }
    else {    #overlaps is the default

        $sql_range = " fl.fmin <= $rend and fl.fmax >= $interbase_start ";

    }

    # set type variable

    my %termhash = %{ $self->{factory}->{cvterm_id} };

    my @keys;
    foreach my $type (@$types) {
        my @tempkeys = grep( /^\Q$type\E\s*$/i, keys %termhash );
        push @keys, @tempkeys;
    }

    my $sql_types = '';

    if ( scalar @keys != 0 ) {
        $sql_types .= "(f.type_id = " . $termhash{ $keys[0] };

        if ( scalar @keys > 1 ) {
            for ( my $i = 1 ; $i < ( scalar @keys ) ; $i++ ) {
                $sql_types .=
                  " OR \n     f.type_id = " . $termhash{ $keys[$i] };
            }
        }
        $sql_types .= ") and ";
    }

    #$self->{factory}->{dbh}->trace(1);

    my $srcfeature_id = $self->{srcfeature_id};

    $self->{factory}->{dbh}->do("set enable_seqscan=0");

    #  $self->{factory}->{dbh}->do("set enable_hashjoin=0");

    my $sth = $self->{factory}->{dbh}->prepare( "
    select distinct f.name,fl.fmin,fl.fmax,fl.strand,f.type_id,f.uniquename,f.feature_id
    from feature f, featureslice($interbase_start, $rend) fl
    where
      $sql_types
      fl.srcfeature_id = $srcfeature_id and
      f.feature_id  = fl.feature_id
    order by type_id,fmin
       " );
    $sth->execute or $self->throw("feature query failed");

    #   $self->{factory}->{dbh}->do("set enable_hashjoin=1");
    $self->{factory}->{dbh}->do("set enable_seqscan=1");

    # Old query (doesn't use RTree index):
    #
    #    select distinct f.name,fl.fmin,fl.fmax,fl.strand,f.type_id,f.feature_id
    #    from feature f, featureloc fl
    #    where
    #      $sql_types
    #      fl.srcfeature_id = $srcfeature_id and
    #      f.feature_id  = fl.feature_id and
    #      $sql_range
    #    order by type_id

    #$self->{factory}->{dbh}->trace(0);
    #take these results and create a list of Bio::SeqFeatureI objects
    #
    #check if the type id is 'alignment hsp' and find/create the parent
    #'alignment hit' object; otherwise do normal stuff

    my %termname = %{ $self->{factory}->{cvname} };
    while ( my $hashref = $sth->fetchrow_hashref ) {

        my $stop            = $$hashref{fmax};
        my $interbase_start = $$hashref{fmin};
        my $base_start      = $interbase_start + 1;

        $feat = Bio::DB::Das::Chado::Segment::Feature->new(
            $self->{factory},      $self,
            $self->seq_id,         $base_start,
            $stop,                 $termname{ $$hashref{type_id} },
            $$hashref{strand},     $$hashref{name},
            $$hashref{uniquename}, $$hashref{feature_id}
        );

        push @features, $feat;

        my $fstart = $feat->start() if DEBUG;
        my $fend   = $feat->end()   if DEBUG;

#  warn "$feat->{annotation}, $$hashref{nbeg}, $fstart, $$hashref{nend}, $fend\n" if DEBUG;
    }

    if ($iterator) {
        warn "using Bio::DB::Das::ChadoIterator\n" if DEBUG;
        return Bio::DB::Das::ChadoIterator->new( \@features );
    }
    else {
        return \@features;
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
    my ( $ref, $class, $base_start, $stop, $strand ) =
      @{$self}{qw(sourceseq class start end strand)};

    my $feat_id = $self->{srcfeature_id};

    my $has_start = defined $base_start;
    my $has_stop  = defined $stop;

    my $reversed;
    if ( $has_start && $has_stop && $base_start > $stop ) {
        $reversed++;
        ( $base_start, $stop ) = ( $stop, $base_start );
    }
    elsif ( $strand < 0 ) {
        $reversed++;
    }

    my $sth;
    if ( !$has_start and !$has_stop ) {
        $sth = $self->{factory}->{dbh}->prepare( "
     select residues from feature
     where feature_id = $feat_id " );
    }
    elsif ( !$has_start ) {
        $sth = $self->{factory}->{dbh}->prepare( "
     select substring(residues for $stop) from feature
     where feature_id = $feat_id " );
    }
    elsif ( !$has_stop ) {
        $sth = $self->{factory}->{dbh}->prepare( "
     select substring(residues from $base_start) from feature
     where feature_id = $feat_id " );
    }
    else {    #has both start and stop
        my $sslen = $stop - $base_start + 1;
        $sth = $self->{factory}->{dbh}->prepare( "
     select substring(residues from $base_start for $sslen) from feature
     where feature_id = $feat_id " );
    }

    $sth->execute or $self->throw("seq query failed");

    my $array_ref = $sth->fetchrow_arrayref;
    my $seq       = $$array_ref[0];

    if ($reversed) {
        $seq = reverse $seq;
        $seq =~ tr/gatcGATC/ctagCTAG/;
    }

    return $seq;
}

*protein = *dna = \&seq;

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

sub factory          { shift->{factory} }
sub alphabet         { return 'dna'; }
sub display_id       { shift->{name} }
sub display_name     { shift->{name} }
sub accession_number { shift->{name} }
sub desc             { shift->{name} }

sub get_feature_stream {
    my $self     = shift;
    my @args     = @_;
    my $features = $self->features(@args);
    warn "get_feature_stream args: @_\n"  if DEBUG;
    warn "using get_feature_stream\n"     if DEBUG;
    warn "feature array: $features\n"     if DEBUG;
    warn "first feature: $$features[0]\n" if DEBUG;
    return Bio::DB::Das::ChadoIterator->new($features);
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
    my %h    = %$self;
    return bless \%h, ref($self);
}

sub sourceseq { shift->{sourceseq} }
*abs_ref   = \&sourceseq;
*abs_start = \&start;
*abs_end   = \&end;

1;
