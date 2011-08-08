#!/usr/bin/perl -w 

use strict;

# load_alignment_database.pl  -- a script to load the database for gbrowse_syn.

# The expected file format is tab-delimited (shown below):
# species1  ref1  start1 end1 strand1  cigar_string1 \
# species2  ref2  start2 end2 strand2  cigar_string2 \
# coords1... | coords2...

# the coords (coordinate) format:
# pos1_species1 pos1_species2 ... posn_species1 posn_species2 | \
# pos1_species2 pos1_species1 ... posn_species2 posn_species1

# where pos is the matching sequence coordinate (ungapped) in each
# species.


use strict;

use Getopt::Long;
use DBI;
use Bio::DB::GFF::Util::Binning 'bin';

use constant MINBIN   => 1000;

use constant VERBOSE  => 0;
use constant MAPRES   => 100;

use vars qw/$format $create $user $pass $dsn $aln_idx $verbose $nomap $mapres $hit_idx $pidx %map/;

GetOptions(
	   'format=s'    => \$format,
           'user=s'      => \$user,
	   'pass=s'      => \$pass,
	   'dsn=s'       => \$dsn,
           'map=i'       => \$mapres,
	   'verbose'     => \$verbose,
	   'nomap'       => \$nomap,
	   'create'      => \$create
	   );

my $usage = "Usage: load_alignment_database.pl -u username -p password -d database [-m map_resolution, -v, -n, -c] file1, file2 ... filen\n\n";

$dsn     || die $usage;
$user    || die $usage;

$verbose ||= VERBOSE;
$mapres  ||= MAPRES;

my ($dbh,$sth_hit,$sth_map) = prepare_database($dsn,$user,$pass);

while (<>) {
  chomp;
  my ($src1,$ref1,$start1,$end1,$strand1,$seq1,
      $src2,$ref2,$start2,$end2,$strand2,$seq2,@maps) = split "\t";

  # deal with coordinate maps
  my ($switch,@map1,@map2);
  for (@maps) {
    if ($_ eq '|') {
      $switch++;
      next;
    }
    $switch ? push @map2, $_ : push @map1, $_;    
  }
  my %map1 = @map1;
  my %map2 = @map2;
  
  load_alignment($src1,$ref1,$start1,$end1,$strand1,$seq1,
                 $src2,$ref2,$start2,$end2,$strand2,$seq2,\%map1,\%map2);
}

done();





sub prepare_database {
  my ($dns,$user,$pass) = @_;
  $dsn = "dbi:mysql:$dsn" unless $dsn =~ /^dbi/;

  my $dbh = DBI->connect($dsn, $user, $pass) or die DBI->errstr;

  if ($create) {
    $dbh->do('drop table if exists alignments') or die DBI->errstr;
    $dbh->do('drop table if exists map') or die DBI->errstr;

    $dbh->do(<<"    END;") or die DBI->errstr;
    create table alignments (
			 hit_id    serial not null,
			 hit_name  varchar(100) not null,
			 src1      varchar(100) not null,
			 ref1      varchar(100) not null,
			 start1    int not null,
			 end1      int not null,
			 strand1   varchar(1) not null,
			 seq1      text,
			 bin       numeric(20,6) not null,
			 src2      varchar(100) not null,
			 ref2      varchar(100) not null,
			 start2    int not null,
			 end2      int not null,
			 strand2   varchar(1) not null,
			 seq2      text,
			 primary key(hit_id)
			 );

    alter table alignments add constraint strand1_val CHECK( strand1='+' OR strand1 ='-' );
    alter table alignments add constraint strand2_val CHECK( strand2='+' OR strand2 ='-' );
    END;

    $dbh->do(<<"    END;") or die DBI->errstr;
    create table map (
	  	  map_id serial not null,
		  hit_name  varchar(100) not null,
                  src1 varchar(100),
		  pos1 int not null,
		  pos2 int not null,
		  primary key(map_id)
		  );
    create index map_hit_name on map (hit_name);
    END;
  }

  my $hit_insert = $dbh->prepare(<<END) or die $dbh->errstr;
insert into alignments (hit_name,src1,ref1,start1,end1,strand1,seq1,bin,src2,ref2,start2,end2,strand2,seq2)
values(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
END
;

  my $map_insert = $dbh->prepare('insert into map (hit_name,src1,pos1,pos2) values(?,?,?,?)');

  return $dbh, $hit_insert, $map_insert;
}

sub load_alignment {
  my ($src1,$ref1,$start1,$end1,$strand1,$seq1,
      $src2,$ref2,$start2,$end2,$strand2,$seq2,$map1,$map2) = @_;

  # not using the cigar strings right now
  ($seq1,$seq2) = ('','');  

  $map1 ||= {};
  $map2 ||= {};

  my %map1 = %$map1;
  my %map2 = %$map2;

  # standardize hit names
  my $hit1 = 'H' . sprintf('%010s', ++$hit_idx);
  my $bin1 = scalar bin($start1,$end1,MINBIN);
  my $bin2 = scalar bin($start2,$end2,MINBIN);
  my $hit2 = "${hit1}r";

  # force ref strand to always be positive and invert target strand as required
  invert(\$strand1,\$strand2) if $strand1 eq '-';

  $sth_hit->execute($hit1,$src1,$ref1,$start1,$end1,$strand1,$seq1,$bin1,
		    $src2,$ref2,$start2,$end2,$strand2,$seq2) or warn $sth_hit->errstr;

  unless ($nomap) {
    for my $pos (sort {$a<=>$b} keys %map1) {
      next unless $pos && $map1{$pos};
      $sth_map->execute($hit1,$src1,$pos,$map1{$pos}) or die $sth_map->errstr; 
    }
  }

  # reciprocal hit is also saved to facilitate switching amongst reference sequences
  invert(\$strand1,\$strand2) if $strand2 eq '-';

  $sth_hit->execute($hit2,$src2,$ref2,$start2,$end2,$strand2,$seq2,$bin2,
		    $src1,$ref1,$start1,$end1,$strand1,$seq1) or warn $sth_hit->errstr;


  # saving pair-wise coordinate maps -- these are needed for gridlines
  unless ($nomap) {
    for my $pos (sort {$a<=>$b} keys %map2) {
      next unless $pos && $map2{$pos};
      $sth_map->execute($hit1,$src2,$pos,$map2{$pos}) or die $sth_map->errstr;
    }
  }

  print STDERR "Processed pair-wise alignment ".++$pidx."\r" if $verbose;
}

sub done {
  $dbh->do('create index alignments_index1 on alignments (src1,ref1,bin,start1,end1);alter table alignments enable keys');
  print "\nDone!\n\n";
}

sub invert {
  my $strand1 = shift;
  my $strand2 = shift;
  $$strand1 = $$strand1 eq '+' ? '-' : '+';
  $$strand2 = $$strand2 eq '+' ? '-' : '+';
}
