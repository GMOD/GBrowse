# $Id: Segment.pm,v 1.84.4.3 2005-03-30 20:27:51 scottcain Exp $

=head1 NAME

Bio::DB::Das::Chado::Segment - DAS-style access to a chado database

=head1 SYNOPSIS

  # Get a Bio::Das::SegmentI object from a Bio::DB::Das::Chado database...

  $segment = $das->segment(-name => 'Landmark',
                           -start=> $start,
                           -stop => $stop);

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
use Carp qw(carp croak cluck);
use Bio::Root::Root;
use Bio::Das::SegmentI;
use Bio::DB::Das::Chado::Segment::Feature;
use Bio::DB::GFF::Typename;
use constant DEBUG => 0;

use vars '@ISA','$VERSION';
@ISA = qw(Bio::Root::Root Bio::SeqI Bio::Das::SegmentI Bio::DB::Das::Chado);
$VERSION = 0.11;

use overload '""' => 'asString';

# construct a virtual segment that works in a lazy way
sub new {
 #validate that the name/accession is valid, and start and end are valid,
 #then return a new segment

    my $self = shift;

    my ( $name, $factory, $base_start, $stop, $db_id ) = @_;

    warn "$name, $factory\n"                      if DEBUG;
    warn "base_start = $base_start, stop = $stop\n" if DEBUG;

#    $self->Bio::Root::Root->throw("start value less than 1\n")
#      if ( defined $base_start && $base_start < 1 );
    $base_start = $base_start ? int($base_start) : 1;
    my $interbase_start = $base_start - 1;

    my $quoted_name = $factory->dbh->quote( lc $name );

    warn "quoted name:$quoted_name\n" if DEBUG;

    my $srcfeature_query = $factory->dbh->prepare( "
       select srcfeature_id from featureloc
       where feature_id = ?
         " );

    my $landmark_is_src_query = $factory->dbh->prepare( "
       select f.name,f.feature_id,f.seqlen,f.type_id
       from feature f
       where f.feature_id = ?
         " );

    my $feature_query = $factory->dbh->prepare( "
       select f.name,f.feature_id,f.seqlen,f.type_id,fl.fmin,fl.fmax
       from feature f, featureloc fl
       where fl.feature_id = ? and
             ? = f.feature_id
         " );

    my $fetch_uniquename_query = $factory->dbh->prepare( "
       select f.name,fl.fmin,fl.fmax,f.uniquename from feature f, featureloc fl
       where f.feature_id = ? and
             f.feature_id = fl.feature_id 
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
            $base_start = $base_start ? $base_start : $$hashref{fmin} + 1;
            $stop       = $stop       ? $stop       : $$hashref{fmax};
            $db_id      = $$hashref{uniquename};

            next if (!defined ($base_start) or !defined($stop) or !defined($db_id));

            warn "calling factory->segment with name:$name, start:$base_start, stop:$stop, db_id:$db_id\n" if DEBUG;
            push @segments, $factory->segment(-name=>$name,-start=>$base_start,-stop=>$stop,-db_id=>$db_id);
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

            $name = $$hash_ref{'name'};

            my $length = $$hash_ref{'seqlen'};
            my $type   = $factory->term2name( $$hash_ref{'type_id'} );

            if ( $$hash_ref{'fmin'} ) {
                $interbase_start = $$hash_ref{'fmin'};
                $base_start      = $interbase_start + 1;
                $stop            = $$hash_ref{'fmax'};
            }

            warn "base_start:$base_start, stop:$stop, length:$length" if DEBUG;

            if( defined($stop) and $stop > $length ){
                $self->warn("end value ($stop) greater than length ($length),"
                           ." truncating to $length");
                $stop = $length;
            }
            $stop    = $stop ? int($stop) : $length;
            $length  = $stop - $interbase_start;

            warn "base_start:$base_start, stop:$stop, length:$length" if DEBUG;

            return bless {
                factory       => $factory,
                start         => $base_start,
                end           => $stop,
                length        => $length,
                srcfeature_id => $srcfeature_id,
                class         => $type,
                name          => $name,
              },
              ref $self || $self;
        }

        else { #return a Feature object for the feature_id
            my ($feat) = $self->features(
                          -feature_id => $landmark_feature_id,
                          -factory    => $factory,
                          -start      => $base_start,
                          -stop       => $stop, );
            return $feat;
        }
    }
    else {
        warn "no segment found" if DEBUG;
        return;    #nothing returned
    }
}

=head2 name

 Title   : name
 Usage   : $segname = $seg->name();
 Function: Returns the name of the segment
 Returns : see above
 Args    : none
 Status  : public

=cut

sub name {
  my $self = shift;
  return $self->{'name'}
}

=head2 _search_by_name

 Title   : _search_by_name 
 Usage   : _search_by_name($name);
 Function: Searches for segments based on a name
 Returns : Either a scalar (a feature_id) or an arrary ref (containing feature_ids)
 Args    : A string (name)
 Status  : private (used by new)

=cut

sub _search_by_name {
  my ($factory,$quoted_name,$db_id) = @_;

  my $sth; 
  if ($db_id) {
    $sth = $factory->dbh->prepare ("
             select name,feature_id,seqlen from feature
             where uniquename = \'$db_id\'  ");

  } else {
    $sth = $factory->dbh->prepare ("
             select name,feature_id,seqlen from feature
             where lower(name) = $quoted_name  ");
  }
 
  $sth->execute or Bio::Root::Root->throw("unable to validate name/length");
  
  my $rows_returned = $sth->rows;
  if ($rows_returned == 0) { #look in synonym for an exact match
    my $isth = $factory->dbh->prepare ("
       select fs.feature_id from feature_synonym fs, synonym s
       where fs.synonym_id = s.synonym_id and
       lower(s.synonym_sgml) = $quoted_name
        ");
    $isth->execute or Bio::Root::Root->throw("query for name in synonym failed");
    $rows_returned = $isth->rows;
    
    if ($rows_returned == 0) { #look in dbxref for accession number match
      $isth = $factory->dbh->prepare ("
         select feature_id from feature_dbxref fd, dbxref d
         where fd.dbxref_id = d.dbxref_id and
               lower(d.accession) = $quoted_name ");
      $isth->execute or Bio::Root::Root->throw("query for accession failed");
      $rows_returned = $isth->rows;
      
      return if $rows_returned == 0;

      if ($rows_returned == 1) {
        my $hashref = $isth->fetchrow_hashref;
        my $feature_id = $$hashref{'feature_id'};
        return \$feature_id;
      } else {
        my @feature_ids;
        while (my $hashref = $isth->fetchrow_hashref) {
          push @feature_ids, $$hashref{'feature_id'};
        }
        return \@feature_ids; 
      }

    } elsif ($rows_returned == 1) {
      my $hashref = $isth->fetchrow_hashref;
      my $feature_id = $$hashref{'feature_id'};
      return \$feature_id;
    } else {
       my @feature_ids;
       while (my $hashref = $isth->fetchrow_hashref) {
         push @feature_ids, $$hashref{'feature_id'};
       }
       return \@feature_ids;
    }

  } elsif ($rows_returned == 1) {
    my $hashref = $sth->fetchrow_hashref;
    my $feature_id = $$hashref{'feature_id'};
    return \$feature_id;
  } else {
     my @feature_ids;
     while (my $hashref = $sth->fetchrow_hashref) {
       push @feature_ids, $$hashref{'feature_id'};
     }
     return \@feature_ids;
  }
}

=head2 class

  Title   : class
  Usage   : $obj->class($newval)
  Function: Returns the segment class (synonymous with type)
  Returns : value of class (a scalar)
  Args    : on set, new value (a scalar or undef, optional)


=cut

sub class {
  my $self = shift;

  return $self->{'class'} = shift if @_;
  return $self->{'class'};
}

=head2 type

  Title   : type
  Usage   : $obj->type($newval)
  Function: alias of class() for backward compatibility
  Returns : value of type (a scalar)
  Args    : on set, new value (a scalar or undef, optional)


=cut

*type = \&class;

=head2 seq_id

 Title   : seq_id
 Usage   : $ref = $s->seq_id
 Function: return the ID of the landmark, aliased to name() for backward compatibility
 Returns : a string
 Args    : none
 Status  : Public

=cut

*seq_id = \&name;

=head2 start

 Title   : start
 Usage   : $s->start
 Function: start of segment
 Returns : integer
 Args    : none
 Status  : Public

=cut

sub start {
  my $self = shift;
  return $self->{'start'} = shift if @_;
  return $self->{'start'} if $self->{'start'};
  return undef;

} 

=head2 low

 Title   : low
 Usage   : $s->low
 Function: start of segment
 Returns : integer
 Args    : none
 Status  : Public

Alias of start for backward compatibility

=cut

*low = \&start;

=head2 end

 Title   : end
 Usage   : $s->end
 Function: end of segment
 Returns : integer
 Args    : none
 Status  : Public

=cut

sub end {
  my $self = shift;
  return $self->{'end'} = shift if @_;
  return $self->{'end'} if $self->{'end'};
  return undef;
}

=head2 high

 Title   : high
 Usage   : $s->high
 Function: end of segment
 Returns : integer
 Args    : none
 Status  : Public

Alias of end for backward compatiblity

=cut

*high = \&end;

=head2 stop

 Title   : stop
 Usage   : $s->stop
 Function: end of segment
 Returns : integer
 Args    : none
 Status  : Public

Alias of end for backward compatiblity

=cut

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

  my ($types,$attributes,$rangetype,$iterator,$callback,$base_start,$stop,$feature_id,$factory);
  if ($_[0] and $_[0] =~ /^-/) {
    ($types,$attributes,$rangetype,$iterator,$callback,$base_start,$stop,$feature_id,$factory) =
      $self->_rearrange([qw(TYPE 
                            ATTRIBUTES 
                            RANGETYPE 
                            ITERATOR 
                            CALLBACK 
                            START
                            STOP
                            FEATURE_ID
                            FACTORY)],@_);
  #  warn "$types\n";
  } else {
    $types = \@_;
  }

  warn "@$types\n" if (defined $types and DEBUG);

  $factory ||=$self->factory();
  my $feat     = Bio::DB::Das::Chado::Segment::Feature->new();
  my @features;


  my ($interbase_start,$rend,$srcfeature_id,$sql_types);
  unless ($feature_id) {
    $rangetype ||='overlaps';

# set range variable 

    my $base_start = $self->start;
    $interbase_start = $base_start -1;
    $rend       = $self->end;
    my $sql_range;
    if ($rangetype eq 'contains') {

      $sql_range = " fl.fmin >= $interbase_start and fl.fmax <= $rend ";

    } elsif ($rangetype eq 'contained_in') {

      $sql_range = " fl.fmin <= $interbase_start and fl.fmax >= $rend ";

    } else { #overlaps is the default

      $sql_range = " fl.fmin <= $rend and fl.fmax >= $interbase_start ";

    }

# set type variable 

    $sql_types = '';

    my $valid_type = undef;
    if (scalar @$types != 0) {

      warn "first type:$$types[0]\n" if DEBUG;

      my $temp_type = $$types[0];
      my $temp_source = '';
      if ($$types[0] =~ /(.*):(.*)/) {
          $temp_type   = $1;
          $temp_source = $2;
      }

      $valid_type = $factory->name2term($temp_type);
      $self->throw("feature type: '$temp_type' is not recognized") unless $valid_type;

      my $temp_dbxref = $factory->source2dbxref($temp_source);
      if ($temp_source && $temp_dbxref) {
          $sql_types .= "((f.type_id = $valid_type and fd.dbxref_id = $temp_dbxref)"; 
      } else {
          $sql_types  .= "((f.type_id = $valid_type)";
      }

      if (scalar @$types > 1) {
        for(my $i=1;$i<(scalar @$types);$i++) {
      
          $temp_type   = $$types[$i]; 
          $temp_source = '';
          if ($$types[$i] =~ /(.*):(.*)/) {
              $temp_type = $1;
              $temp_source = $2;
          }
          warn "more types:$$types[$i]\n" if DEBUG; 

          $valid_type = $factory->name2term($temp_type);
          $self->throw("feature type: '$temp_type' is not recognized") unless $valid_type;

          $temp_dbxref=$factory->source2dbxref($temp_source);
          if ($temp_source && $temp_dbxref) {
              $sql_types .= " OR \n     (f.type_id = $valid_type and fd.dbxref_id = $temp_dbxref)";
          } else {
              $sql_types .= " OR \n     (f.type_id = $valid_type)";
          }
        }
      }
      $sql_types .= ") and ";
    }

#  $factory->dbh->trace(1) if DEBUG;

    $srcfeature_id = $self->{srcfeature_id};

  }
  my $select_part = "select distinct f.name,fl.fmin,fl.fmax,fl.strand,fl.phase,"
                   ."fl.locgroup,fl.srcfeature_id,f.type_id,f.uniquename,"
                   ."f.feature_id, af.significance as score, "
                   ."dbx.dbxref_id ";

  my $order_by    = "order by f.type_id,fl.fmin ";

  my $where_part;
  my $from_part;
  if ($feature_id) {
    $from_part    = "from (feature f join featureloc fl using (feature_id)) "
                   ."left join feature_dbxref fd using (feature_id) "
                   ."left join dbxref dbx on (dbx.dbxref_id = fd.dbxref_id) "
                   ."left join analysisfeature af using (feature_id)";

    $where_part   = "where f.feature_id = $feature_id and fl.rank=0 and dbx.db_id=".$factory->gff_source_db_id;
  } else {
    $from_part   = "from (feature f join featureslice($interbase_start, $rend) fl using (feature_id)) "
                  ."left join feature_dbxref fd using (feature_id) "
                  ."left join dbxref dbx on (dbx.dbxref_id = fd.dbxref_id) "
                  ."left join analysisfeature af using (feature_id)";

    $where_part  = "where $sql_types "
                  ."fl.srcfeature_id = $srcfeature_id and fl.rank=0 "
                  ."and dbx.db_id=".$factory->gff_source_db_id;
  }

  my $query       = "$select_part\n$from_part\n$where_part\n$order_by\n";

  $factory->dbh->do("set enable_seqscan=0");
#  $factory->dbh->do("set enable_hashjoin=0");

  warn "Segement->features query:$query" if DEBUG;

  my $sth = $factory->dbh->prepare($query);

   $sth->execute or $self->throw("feature query failed"); 
#   $factory->dbh->do("set enable_hashjoin=1");
   $factory->dbh->do("set enable_seqscan=1");

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




#$factory->dbh->trace(0);
#take these results and create a list of Bio::SeqFeatureI objects
#

#  my $sth_srcfeature_id_to_name = $self->factory->dbh->prepare("
#    select name from feature where feature_id = ?;");

  while (my $hashref = $sth->fetchrow_hashref) {

    warn "dbstart:$$hashref{fmim}, dbstop:$$hashref{fmax}" if DEBUG;
    warn "start:$base_start, stop:$stop\n" if DEBUG;

    if ($feature_id && 
        defined($stop) && $stop != $$hashref{fmax} ) {
      $stop = $$hashref{fmin} + $stop + 1;  
    } else {
      $stop = $$hashref{fmax};
    }
    if ($feature_id && 
        defined($base_start) && $base_start != ($$hashref{fmin}+1) ) {
      my $interbase_start = $$hashref{fmin} + $base_start - 1;
      $base_start = $interbase_start + 1;
    } else {
      my $interbase_start = $$hashref{fmin};
      $base_start         = $interbase_start +1;
    }
    warn "base_start:$base_start, end:$stop" if DEBUG;

    my $source = $factory->dbxref2source($$hashref{dbxref_id}) || "" ;
    my $type   = Bio::DB::GFF::Typename->new(
                     $factory->term2name($$hashref{type_id}),
                     $source);

    $feat = Bio::DB::Das::Chado::Segment::Feature->new(
                       $factory,
                       $feature_id? undef :$self, #only give the segment as the
                                            # parent if the feature_id wasn't 
                                            # provided
                                 
                       $feature_id ?
                           $factory->srcfeature2name($$hashref{'srcfeature_id'})
                          :$self->seq_id,

                       $base_start,$stop,
                       $type,
                       $$hashref{score},
                       $$hashref{strand},
                       $$hashref{phase},
                       $$hashref{name},
                       $$hashref{uniquename},$$hashref{feature_id});

    push @features, $feat;

    my $fstart = $feat->start() if DEBUG;
    my $fend   = $feat->end()   if DEBUG;  
  #  warn "$feat->{annotation}, $$hashref{nbeg}, $fstart, $$hashref{nend}, $fend\n" if DEBUG;
  }

  if ($iterator) {
   warn "using Bio::DB::Das::ChadoIterator\n" if DEBUG;
    return Bio::DB::Das::ChadoIterator->new(\@features);
  } elsif (wantarray) {
    return @features;
  } else {
    return \@features;
  }
}

=head2 get_all_SeqFeature, get_SeqFeatures, top_SeqFeatures, all_SeqFeatures
                                                                                      
 Title   : get_all_SeqFeature, get_SeqFeatures, top_SeqFeatures, all_SeqFeatures
 Usage   : $s->get_all_SeqFeature()
 Function: get the sequence string for this segment
 Returns : a string
 Args    : none
 Status  : Public

Several aliases of features() for backward compatibility

=cut

*get_all_SeqFeature = *get_SeqFeatures = *top_SeqFeatures = *all_SeqFeatures = \&features;

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
  my %arg = @_;
  my ($ref,$class,$base_start,$stop,$strand)
    = @{$self}{qw(sourceseq class start end strand)};

  if($arg{self}){
    my $r_id    = $self->feature_id;
  	 
    $self->warn("FIXME: incomplete implementation of alternate sequence selection") if $self->verbose;
  	 
    my $sth = $self->factory->dbh->prepare("
      select residues from feature
      where feature_id = $r_id ");

    $sth->execute or $self->throw("seq query failed");
  	 
    my $array_ref = $sth->fetchrow_arrayref;
    my $seq = $$array_ref[0];
  	 
    return $seq;
  }

  my $feat_id = $self->{srcfeature_id};

  my $has_start = defined $base_start;
  my $has_stop  = defined $stop;

  my $reversed;
  if ($has_start && $has_stop && $base_start > $stop) {
    $reversed++;
    ($base_start,$stop) = ($stop,$base_start);
  } elsif ($strand < 0 ) {
    $reversed++;
  }

  my $sth;
  if (!$has_start and !$has_stop) {
    $sth = $self->factory->dbh->prepare("
     select residues from feature
     where feature_id = $feat_id ");
  } elsif (!$has_start) {
    $sth = $self->factory->dbh->prepare("
     select substring(residues for $stop) from feature
     where feature_id = $feat_id ");
  } elsif (!$has_stop) {
    $sth = $self->factory->dbh->prepare("
     select substring(residues from $base_start) from feature
     where feature_id = $feat_id ");
  } else { #has both start and stop
    my $sslen = $stop-$base_start+1;
    $sth = $self->factory->dbh->prepare("
     select substring(residues from $base_start for $sslen) from feature
     where feature_id = $feat_id ");
  }

  $sth->execute or $self->throw("seq query failed");

  my $array_ref = $sth->fetchrow_arrayref;
  my $seq = $$array_ref[0]; 

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

sub factory {shift->{factory} } 

=head2 srcfeature_id

  Title   : srcfeature_id
  Usage   : $obj->srcfeature_id($newval)
  Function: undocumented method by Scott Cain
  Returns : value of srcfeature_id (a scalar)
  Args    : on set, new value (a scalar or undef, optional)


=cut

sub srcfeature_id {
  my $self = shift;

  return $self->{'srcfeature_id'} = shift if @_;
  return $self->{'srcfeature_id'};
}

=head2 alphabet

  Title   : alphabet
  Usage   : $obj->alphabet($newval)
  Function: undocumented method by Scott Cain
  Returns : scalar 'dna'
  Args    : on set, new value (a scalar or undef, optional)


=cut

sub alphabet {
  return 'dna';
}

=head2 display_id, display_name, accession_number, desc

  Title   : display_id, display_name, accession_number, desc
  Usage   : $s->display_name()
  Function: Alias of name()
  Returns : string
  Args    : none

Several aliases for name; it may be that these could do something better than
just giving back the name.

=cut

*display_id = *display_name = *accession_number = *desc = \&name;

=head2 get_feature_stream

  Title   : get_feature_stream
  Usage   :
  Function: undocumented method by Scott Cain
  Returns :
  Args    :

=cut

sub get_feature_stream {
  my $self = shift;
  my @args = @_;
  my $features = $self->features(@args);
    warn "get_feature_stream args: @_\n" if DEBUG;
    warn "using get_feature_stream\n" if DEBUG;
    warn "feature array: $features\n" if DEBUG;
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

=cut

# deep copy of the thing
sub clone {
  my $self = shift;
  my %h = %$self;
  return bless \%h,ref($self);
}

=head2 sourceseq

  Title   : sourceseq
  Usage   : $obj->sourceseq($newval)
  Function: undocumented method by Scott Cain
  Returns : value of sourceseq (a scalar)
  Args    : on set, new value (a scalar or undef, optional)


=cut

sub sourceseq {
  my $self = shift;

  return $self->{'sourceseq'} if $self->{'sourceseq'};

  my $dbh  = $self->factory->dbh;
  my $sth  = $dbh->prepare ("
      select name from feature where feature_id = ?");
  $sth->execute($self->srcfeature_id)
      or $self->throw("getting sourceseq name query failed"); 

  return if $sth->rows < 1;
  my $hashref = $sth->fetchrow_hashref;
  
  $self->{'sourceseq'} = $$hashref{'name'};
  return $self->{'sourceseq'};
 
}

=head2 abs_ref

  Title   : abs_ref
  Usage   : $obj->abs_ref()
  Function: Alias of sourceseq
  Returns : value of sourceseq (a scalar)
  Args    : none

Alias of sourceseq for backward compatibility

=cut

*abs_ref = \&sourceseq;

=head2 abs_start

  Title   : abs_start
  Usage   : $obj->abs_start()
  Function: Alias of start
  Returns : value of start (a scalar)
  Args    : none

=cut

*abs_start = \&start;

=head2 abs_end

  Title   : abs_end
  Usage   : $obj->abs_end()
  Function: Alias of end
  Returns : value of end (a scalar)
  Args    : none

=cut

*abs_end   = \&end;

=head2 asString
                                                                                
 Title   : asString
 Usage   : $s->asString
 Function: human-readable string for segment
 Returns : a string
 Args    : none
 Status  : Public
                                                                                
Returns a human-readable string representing this sequence.  Format
is:
                                                                                
   sourceseq:start,stop
                                                                                
=cut
                                                                                
sub asString {
  my $self = shift;
  my $label = $self->refseq;
  my $start = $self->start;
  my $stop  = $self->stop;
  return "$label:$start,$stop";
}


1;
