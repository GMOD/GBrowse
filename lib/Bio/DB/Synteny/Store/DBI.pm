package Bio::DB::Synteny::Store::DBI;
use strict;

use base 'Bio::DB::Synteny::Store';

use constant MINBIN   => 1000;
use constant MAXBIN   => 1_000_000_000;
use constant EPSILON  => 1e-7;  # set to zero if you trust mysql's floating point comparisons
use constant POSRANGE => 200;
use constant FORMAT   => 'clustalw';
use constant VERBOSE  => 0;
use constant MAPRES   => 100;

use DBI;

use Bio::DB::GFF::Util::Binning qw/ bin bin_bot bin_top /;
use Bio::DB::GFF::Util::Rearrange qw(rearrange);

sub new_instance {
    my $class = shift;

    my ($dsn,
        $user,
        $pass,
        $dbi_options,
        $writeable,
        $create,
        $others,
        ) = rearrange(['DSN',
                       'USER',
                       ['PASS','PASSWD','PASSWORD'],
                       ['OPTIONS','DBI_OPTIONS','DBI_ATTR'],
                       ['WRITE','WRITEABLE'],
                       'CREATE',
                     ],@_);
    $dbi_options  ||= {};

    $dsn or $class->throw("Usage: ".$class."->init(-dsn => \$dbh || \$dsn)");

    my $dbh;
    if (ref $dsn) {
        $dbh = $dsn;
    } else {
        # try to magically prepend dbi:XX: to dsn's if left out
        if( $dsn !~ /^dbi:/ and my ($probable_driver_name) = $class =~ /DBI::([^:]+)$/ ) {
            $dsn = "dbi:$probable_driver_name:dbname=$dsn"
        }
        $dbh = DBI->connect( $dsn, $user, $pass, $dbi_options );
        $dbh->{mysql_auto_reconnect} = 1;
    }

    $dbh->{RaiseError} = $dbh->{PrintError} = 1;

    my $self = bless {
        dbh       => $dbh,
        writeable => $writeable,
    }, ref $class || $class;

    if ($create) {
        $self->init_database( 'erase' );
    }

    return $self;
}

sub dbh   { shift->{dbh}   }
sub nomap { shift->{nomap} }

sub add_alignment {
    my ( $self, $q, $s ) = @_;

    my ($src1,$ref1,$start1,$end1,$strand1,$seq1,$map1) = @$q;
    my ($src2,$ref2,$start2,$end2,$strand2,$seq2,$map2) = @$s;
    $_ ||= {} for $map1, $map2;
    # not using the cigar strings right now
    $_ = ''   for $seq1, $seq2;

    # prepare the insertion query if necessary
    my $sth_hit = $self->{sth_hit_insert} ||= $self->dbh->prepare(<<END);
       INSERT INTO alignments
         ( hit_name
           , src1, ref1, start1, end1, strand1, seq1, bin
           , src2, ref2, start2, end2, strand2, seq2
         )
         values ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? )
END

    # standardize hit names
    my $hit1 = 'H' . sprintf( '%010s', ++($self->{hit_idx}) );
    my $bin1 = scalar bin($start1,$end1,MINBIN);
    my $bin2 = scalar bin($start2,$end2,MINBIN);
    my $hit2 = $hit1.'r';

    # force ref strand to always be positive and invert target strand as required
    $self->invert(\$strand1,\$strand2) if $strand1 eq '-';

    $sth_hit->execute($hit1,$src1,$ref1,$start1,$end1,$strand1,$seq1,$bin1,
                      $src2,$ref2,$start2,$end2,$strand2,$seq2);

    # reciprocal hit is also saved to facilitate switching amongst reference sequences
    $self->invert(\$strand1,\$strand2) if $strand2 eq '-';

    $sth_hit->execute($hit2,$src2,$ref2,$start2,$end2,$strand2,$seq2,$bin2,
                      $src1,$ref1,$start1,$end1,$strand1,$seq1);

    # saving pair-wise coordinate maps -- these are needed for gridlines
    unless ( $self->nomap ) {
        $self->add_map( $hit1, $src1, $map1 );
        $self->add_map( $hit1, $src2, $map2 );
    }
}



sub add_map {
    my ( $self, $hit, $src, $map ) = @_;

    my $sth_map = $self->{sth_map_insert} ||= $self->dbh->prepare(<<'');
INSERT INTO map ( hit_name, src1, pos1, pos2 )
     VALUES ( ?, ?, ?, ? )

    for my $pos (sort {$a<=>$b} keys %$map) {
        next unless $pos && $map->{$pos};
        $sth_map->execute( $hit, $src, $pos, $map->{$pos} );
    }
}

# a method to get the nearest residue position match
# (for truncating hits and gridlines).  Return the nearest mapped
# source residue and the corresponding target residue.
sub get_nearest_position_match {
  my $self  = shift;
  my ($hit,$src,$pos,$range) = @_;

  my @hits = ref $hit && $hit->parts > 1 ? @{$hit->parts} : ($hit);
  $range ||= POSRANGE;
  
  for my $h (@hits) {
    my $min = $pos - int($range/2);
    my $max = $pos + int($range/2);
    my $sth = $self->position_handle;
    my $hname = ref $h ? $h->name : $h;
    $hname =~ s/r|\.\d+//g;
    $sth->execute($hname,$src,$min,$max);
    my %match;
    while (my @row = $sth->fetchrow_array) {
      $match{abs($row[0] - $pos)} = \@row;
    }  

    my ($nearest) = map {$match{$_}} sort {$a <=> $b} keys %match;
    $nearest ||= [undef,undef];    
    return @$nearest if ref $nearest && defined $nearest->[0];
  }
}

# a method to get a range of exact grid coordinates
# for synteny data with sparse gridlines that are
# not suitable for rounding off to the nearest multiple of 10
sub grid_coords_by_range {
  my $self  = shift;
  my ($hit,$src) = @_;

  my @hits = ref $hit && $hit->parts > 1 ? @{$hit->parts} : ($hit);
  my @pairs;
  my $sth = $self->position_handle;

  for my $h (@hits) {
    my $hname = ref $h ? $h->name : $h;
    $hname =~ s/r|\.\d+//g;
    $sth->execute($hname,$src,$hit->start,$hit->end);
    my $pairs = $sth->fetchall_arrayref;
    push @pairs, @$pairs;
  }
  
  return @pairs;
}


# Check to see of grid-lines are possible.  Some data sources
# may lack the grid coordinate data (not that there is anything
# wrong with that).
sub _has_map {
  my $dbh = shift;
  my $sth = $dbh->prepare('SELECT count(*) FROM map');
  $sth->execute;
  my ($count) = $sth->fetchrow_array;
  return $count;
}


sub position_handle {
  my $self = shift;

  unless (defined $self->{position_query}) {
    my $query = <<END;
select pos1,pos2 from map
WHERE hit_name = ?
AND src1 = ?
AND pos1 >= ?
AND pos1 <= ?
END
;
    $self->{position_query} = $self->dbh->prepare_cached($query);

  }

  return $self->{position_query};
}

sub get_synteny_by_range {
  my $self = shift;
  my ($src,            # a symbolic data source, like "worm"
      $ref,            # reference for search range - contig or chromosome name
      $start,          # start of search range
      $end,            # end of search range
      $tgt             # optional data source target, like "yeast"
     ) = rearrange([qw(SRC REF START END TGT)],@_);
  my ($query,@args) = $self->make_range_query($src,$ref,$start,$end,$tgt);
  my $sth           = $self->dbh->prepare_cached($query);
  $sth->execute(@args);
  my %HITS;
  while (my($hit,
	    $src,$ref1,$start1,$end1,$strand1,$seq1,
	    $tgt,$ref2,$start2,$end2,$strand2,$seq2) = $sth->fetchrow_array) {
    $HITS{$hit} ||= Bio::DB::Synteny::Block->new($hit);
    $HITS{$hit}->add_part([$src,$ref1,$start1,$end1,$strand1,$seq1],
			  [$tgt,$ref2,$start2,$end2,$strand2,$seq2]
			 );
  }
  return values %HITS;
}

sub make_range_query {
  my $self = shift;
  my ($src,$ref,$start,$end,$tgt) = @_;
  my $query = <<'';
       SELECT
              hit_name
            , src1, ref1, start1, end1, strand1, seq1
            , src2, ref2, start2, end2, strand2, seq2
       FROM alignments

  my @where;
  my @args;

  if (defined $src) {
    push @where,'src1=?';
    push @args,$src;
  }

  if (defined $ref) {
    push @where,'ref1=?';
    push @args,$ref;
  }

  if (defined $start and defined $end) {
    my ($range_part,@range_args) = $self->bin_query($start,$end);
    push @where,$range_part;
    push @args,@range_args;
  }

  if (defined $tgt) {
    push @where,'src2=?';
    push @args,$tgt;
  }

  if (@where) {
    $query .= "\n      WHERE ".join(' AND ',@where);
  }

  return ($query,@args);
}

# stolen from Bio::DB::GFF::Adaptor::dbi
sub bin_query {
  my $self = shift;
  my ($start,$end) = @_;
  my ($query,@args);

  $start = 0     unless defined($start);
  $end  = MAXBIN unless defined($end);

  my @bins;
  my $minbin = MINBIN;
  my $maxbin = MAXBIN;
  my $tier = $maxbin;
  while ($tier >= $minbin) {
    my ($tier_start,$tier_stop) = (bin_bot($tier,$start)-EPSILON(),bin_top($tier,$end)+EPSILON());
    if ($tier_start == $tier_stop) {
      push @bins,'bin=?';
      push @args,$tier_start;
    } else {
      push @bins,'bin between ? and ?';
      push @args,($tier_start,$tier_stop);
    }
    $tier /= 10;
  }

  my $bin_part = join("\n\t OR ",@bins);
  $query = "($bin_part) AND end1>=? AND start1<=?";
  return ($query,@args,$start,$end);
}

1;
