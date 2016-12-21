#!/usr/bin/perl -w
# This script will load the gbrowse_syn alignment database directly from a
# multiple sequence alignment file.
BEGIN {
  # Check for DBI before running the script
  # Doing this here will allow the "compile" tests to pass for GBrowse
  # even if DBI is not installed.
  eval {
      require DBI;
      DBI->import;
  };

  if ($@) {
      die "The DBI perl module is required to run this script\n";
  }
}


use strict;
use Bio::AlignIO;
use List::Util 'sum';
use Getopt::Long;
use Bio::DB::GFF::Util::Binning 'bin';

use Data::Dumper;

use constant MINBIN   => 1000;
use constant FORMAT   => 'clustalw';
use constant VERBOSE  => 0;
use constant MAPRES   => 100;

use vars qw/$format $create $user $pass $dsn $aln_idx $verbose $nomap $mapres $hit_idx $pidx %map/;

$| = 1;
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

my $usage = 
"Usage:
  [MySQL]
     load_alignments_msa.pl -u username -p password -d database [-f format, -m map_resolution, -v, -n, -c] file1, file2 ... filen
  [SQLite]
     load_alignment_database.pl -d dbi:SQLite:dbname=/path/to/db [-f format, -m map_resolution, -v, -n, -c] file1, file2 ... filen\n\n";

$dsn     || die $usage;
$user    || $dsn =~ /SQLite/ || die "Error: no user name\n$usage";
$format  ||= FORMAT;
$verbose ||= VERBOSE;
$mapres  ||= MAPRES;

my ($dbh,$sth_hit,$sth_map) = prepare_database($dsn,$user,$pass);

while (my $infile = shift) {
  print "Processing alignment file $infile...\n" if $verbose;
  my $alignIO = Bio::AlignIO->new( -file   => $infile, 
				   -format => $format);

  while (my $aln = $alignIO->next_aln) {
    my $len = $aln->length;
    $pidx = 0;
    print STDERR "Processing Multiple Sequence Alignment " . ++$aln_idx . " (length $len)\t\t\t\r" if $verbose; 
    next if $aln->num_sequences < 2;
    my %seq;
    %map = ();
    my $map = {};
    for my $seq ($aln->each_seq) {
      my $seqid = $seq->id;
      my ($species,$ref,$strand) = check_name_format($seqid,$seq);
      next if $seq->seq =~ /^-+$/;
      $strand ||= $seq->start < $seq->end ? '+' : '-';
      # We have to tell the sequence object what its strand is
      $seq->strand($strand eq '-' ? -1 : 1) unless $seq->strand;
      $seq{$species} = [$ref, $seq->display_name, $seq->start, $seq->end, $strand, $seq->seq, $seq]; 
    }
    
    # make all pairwise hits and grid coordinates
    my @species = keys %seq;
    
    for my $p (map_pairwise(@species)) {
      my ($s1,$s2) = @$p;
      my $array1 = $seq{$s1};
      my $array2 = $seq{$s2};
      
      my $seq1 = $$array1[6];
      my $seq2 = $$array2[6];

      unless ($nomap) {
	$array1->[7] = make_map($seq1,$seq2,$map);
	$array2->[7] = make_map($seq2,$seq1,$map);
      }

      make_hit($s1 => $array1, $s2 => $array2);
    }
  }
}  

# Make coordinate maps at the specified resolution
sub make_map {
  my ($s1,$s2,$map) = @_;
  $s1 && $s2 || return {};
  unless (UNIVERSAL::can($s1,'isa')) {
    warn "WTF? $s1 $s2\n" and next;
  }
  
  column_to_residue_number($s1,$s2);
  my $coord = nearest($mapres,$s1->start);
  $coord += $mapres if $coord < $s1->start;
  my @map;
  
  my $reverse = $s1->strand ne $s2->strand;
 
  # have to get the column number from residue position, then
  # the matching residue num from the column number 
  while ($coord < $s1->end) {
    my $col     = column_from_residue_number($s1,$coord);
    my $coord2  = residue_from_column_number($s2,$col) if $col;
    push @map, ($coord,$coord2) if $coord2;
    $coord += $mapres;
  }
  return {@map};
}

sub column_to_residue_number {
  for my $seq (@_) {
    my $str = $seq->seq;
    my $id  = $seq->id;
    next if $map{$id};
    my $rev = $seq->strand < 0;
    my $res = $rev ? $seq->end - 1 : $seq->start + 1;
    my @cols = split '', $str;
    
    my $pos;
    my $col;
    for my $chr (@cols) {
      unless ($chr eq '-') {
	$rev ? $res-- : $res++;
      }

      $col++;
      $map{$id}{col}{$col} = $res;
      $map{$id}{res}{$res} ||= $col;
    }
  }
}

sub column_from_residue_number {
  my ($seq, $res) = @_;
  my $id = $seq->id;
  return $map{$id}{res}{$res};  
}

sub residue_from_column_number {
  my ($seq, $col) = @_;
  my $id = $seq->id;
  print"WTF? $seq $id $col\n" unless $id &&$col;
  return $map{$id}{col}{$col};
}

sub make_hit {
  my ($s1,$aln1,$s2,$aln2,$fh) = @_;
  my $rightnum = $nomap ? 7 : 8;
  die "wrong number of keys @$aln1" unless @$aln1 == $rightnum;
  die "wrong number of keys @$aln2" unless @$aln2 == $rightnum;
  my $map1 = $aln1->[7] || {};
  my $map2 = $aln2->[7] || {};

  # not using these yet
  my ($cigar1,$cigar2) = qw/. ./;

  load_alignment($s1,@{$aln1}[0,2..4],$cigar1,$s2,@{$aln2}[0,2..4],$cigar2,$map1,$map2);
}

sub map_pairwise {
  my @out;
  for my $i (0..$#_) {
    for my $j ($i+1..$#_) {
      push @out, [$_[$i], $_[$j]];
    }
  }
  return @out;
}

# stolen from Math::Round
sub nearest {
  my $targ = abs(shift);
  my $half = 0.50000000000008;
  my @res  = map {
    if ($_ >= 0) { $targ * int(($_ + $half * $targ) / $targ); }
    else { $targ * POSIX::ceil(($_ - $half * $targ) / $targ); }
  } @_;

  return (wantarray) ? @res : $res[0];
}

sub check_name_format {
  my $name = shift;
  my $seq  = shift;

  my $nogood = <<"  END";

  Problem with sequence name $name
  The Sequence name needs to contain some meta-data to identify
      the species, reference sequence and coordinates.


  Supported Sequence Name formats:

  # Downloaded via Ensembl Compara API
  species/seqid/start-end
      where species   = name of species, genome, strain, etc (string with no '-' characters)
            sequence  = name of reference sequence (string with no '/' characters)
            start     = start coordinate of the alignment relative to the reference sequence (integer)
            end       = end coordinate of the alignment relative to the reference sequence   (integer)
            in this format, the strand is + unless end < start

  # Legacy gbrowse_syn format
  species-seqid(strand)/start..end
      where (strand)  = orientation of the alignment (relative to the reference sequence; + or -)

  Examples:
    homo_sapiens/1/100000-200000
    c_elegans-I(+)/1..2300

  END
  ;

  die $nogood unless $name =~ /^([^-]+)-([^\(]+)\(([+-])\)$/  # Why did I do this?
              ||     $name =~ m!^([^/]+)/([^/]+)!;            # from Bio::LocatableSeq
  die $nogood unless $seq->start && $seq->end;
  return ($1,$2,$3);
}


sub prepare_database {
  my ($dns,$user,$pass) = @_;
  $dsn = "dbi:mysql:$dsn" unless $dsn =~ /^dbi/;

  my $dbh = DBI->connect($dsn, $user, $pass) or die DBI->errstr;

  if ($create) {
    # In SQLite, integer primary keys autoincrement when inserting NULL
    my $autoincrement = ($dsn =~ /SQLite/) ? "" : "not null auto_increment";
    my $strand_type   = ($dsn =~ /SQLite/) ? "text" : "enum('+','-')";
    $dbh->do('drop table if exists alignments') or die DBI->errstr;
    $dbh->do('drop table if exists map') or die DBI->errstr;
  
    $dbh->do(<<"    END;") or die DBI->errstr;
    create table alignments (
			 hit_id    int $autoincrement,
			 hit_name  varchar(100) not null,
			 src1      varchar(100) not null,
			 ref1      varchar(100) not null,
			 start1    int not null,
			 end1      int not null,
			 strand1   $strand_type not null,
			 seq1      mediumtext,
			 bin       double(20,6) not null,
			 src2      varchar(100) not null,
			 ref2      varchar(100) not null,
			 start2    int not null,
			 end2      int not null,
			 strand2   $strand_type not null,
			 seq2      mediumtext,
			 primary key(hit_id),
			 check(strand1 in ('+', '-')), -- parsed and ignored by MySQL
			 check(strand2 in ('+', '-'))  -- parsed and ignored by MySQL
			 )
    END;

    $dbh->do('create index alignments_idx on alignments (src1,ref1,bin,start1,end1)') or die DBI->errstr;
    $dbh->do(<<"    END;") or die DBI->errstr;
    create table map (
	  	  map_id int $autoincrement,
		  hit_name  varchar(100) not null,
                  src1 varchar(100),
		  pos1 int not null,
		  pos2 int not null,
		  primary key(map_id)
		  )
    END;

    $dbh->do('create index map_idx on map (hit_name);') or die DBI->errstr;
    if ($dsn =~ /SQLite/) {
        $dbh->do("PRAGMA synchronous = OFF;"); # makes writes much faster
    } else {
        $dbh->do('alter table alignments disable keys');
    }
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
  my ($src1,$ref1,$start1,$end1,$strand1,$seq1,$src2,$ref2,$start2,$end2,$strand2,$seq2,$map1,$map2) = @_;

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
  $dsn !~ /SQLite/ && $dbh->do('alter table alignments enable keys');
  print "\nDone!\n\n";
}

sub invert {
  my $strand1 = shift;
  my $strand2 = shift;
  $$strand1 = $$strand1 eq '+' ? '-' : '+';
  $$strand2 = $$strand2 eq '+' ? '-' : '+'; 
}
