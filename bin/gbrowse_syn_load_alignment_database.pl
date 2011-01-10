#!/usr/bin/perl -w 
# $Id: load_alignment_database.pl,v 1.1.2.4 2009-06-03 08:09:26 sheldon_mckay Exp $
use strict;

# load_alignment_database.pl  -- a script to load the database for gbrowse_syn.

# The expected file format is tab-delimited (shown below):
# species1  ref1  start1 end1 strand1  cigar_string1 species2  ref2  start2 end2 strand2  cigar_string2 coords1... | coords2...
# the coordinate format: pos1_species1 pos1_species2 ... posn_species1 posn_species2 | pos1_species2 pos1_species1 ... posn_species2 posn_species1, 
# where pos is the matching sequence coordinate (ungapped) in each species.
#

use strict;
use Bio::DB::GFF::Util::Binning 'bin';
use Getopt::Long;

use constant MINBIN   => 1000;

use vars qw/$create $user $pass $dsn $verbose $create $aln_idx/;

$| = 1;
GetOptions(
           'user=s'      => \$user,
           'pass=s'      => \$pass,
           'dsn=s'       => \$dsn,
           'verbose'     => \$verbose,
           'create'      => \$create
           );

my $usage = "Usage: load_alignment_database.pl -u username -p password -d database [-v, -c] file1, file2 ... filen\n\n";

$dsn     || die "Error: no database name\n$usage";
$user    || die "Error: no user name\n$usage";

if ($create && $verbose) {
  print STDERR "\nNote: a new database $dsn will be initialized\n EXISTING DATA WILL BE DELETED\n\n";
}
elsif ($verbose) {
  print STDERR "\nNote: data will be appended to the existing database $dsn\n\n";
}


$dsn = "dbi:mysql:$dsn" unless $dsn =~ /^dbi/;
eval "require DBI; 1" or die "DBI module not installed. Cannot continue";
my $dbh = DBI->connect($dsn, $user, $pass);
unless ($dbh) {
  $dsn =~ s/\S+\:([^:]+)$/$1/;
  my $error = DBI->errstr;
  die <<END;

 Error: $error

 There was a problem opening a connection to database $dsn.
 Make sure you have used the correct username ($user), password ($pass) and that you have 
 created the database $dsn via your mysql client. 
 
 Consult the error message above for more information.
END
;
}

if ($create) {
  $dbh->do('drop table if exists alignments') or die DBI->errstr;
  $dbh->do('drop table if exists map') or die DBI->errstr;

  $dbh->do(<<END) or die DBI->errstr;
  create table alignments (
			 hit_id    int not null auto_increment,
			 hit_name  varchar(100) not null,
			 src1      varchar(100) not null,
			 ref1      varchar(100) not null,
			 start1    int not null,
			 end1      int not null,
			 strand1   enum('+','-') not null,
			 seq1      mediumtext,
			 bin       double(20,6) not null,
			 src2      varchar(100) not null,
			 ref2      varchar(100) not null,
			 start2    int not null,
			 end2      int not null,
			 strand2   enum('+','-') not null,
			 seq2      mediumtext,
			 primary key(hit_id),
			 index(src1,ref1,bin,start1,end1)
			 )
END
;

  $dbh->do(<<END) or die DBI->errstr;
  create table map (
		  map_id int not null auto_increment,
		  hit_name  varchar(100) not null,
                  src1 varchar(100),
		  pos1 int not null,
		  pos2 int not null,
		  primary key(map_id),
		  index(hit_name)
		  )
END
;
}

$dbh->do('alter table alignments disable keys');
$dbh->do('alter table map');
my $sth=$dbh->prepare(<<END) or die $dbh->errstr;
insert into alignments (hit_name,src1,ref1,start1,end1,strand1,seq1,bin,src2,ref2,start2,end2,strand2,seq2) 
values(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
END
;

my $sth2 = $dbh->prepare('insert into map (hit_name,src1,pos1,pos2) values(?,?,?,?)');

my $hit_idx;
while (<>) {
  chomp;
  my ($src1,$ref1,$start1,$end1,$strand1,$seq1,$src2,$ref2,$start2,$end2,$strand2,$seq2,@maps) = split "\t";

  # not using the cigar strings right now
   ($seq1,$seq2) = ('','');  

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

  # standardize hit names
  my $hit1 = 'H'.pad(++$hit_idx);
  my $bin1 = scalar bin($start1,$end1,MINBIN);
  my $bin2 = scalar bin($start2,$end2,MINBIN);
  my $hit2 = "${hit1}r";
  
  # force ref strand to always be positive and invert target strand as required
  invert(\$strand1,\$strand2) if $strand1 eq '-'; 

  $sth->execute($hit1,$src1,$ref1,$start1,$end1,$strand1,$seq1,$bin1,
		$src2,$ref2,$start2,$end2,$strand2,$seq2) or warn $sth->errstr;

  for my $pos (sort {$a<=>$b} keys %map1) {
    next unless $pos && $map1{$pos};
    $sth2->execute($hit1,$src1,$pos,$map1{$pos}) or die $sth->errstr; 
  }

  # reciprocal hit is also saved to facilitate switching amongst reference sequences
  invert(\$strand1,\$strand2) if $strand2 eq '-';
  
  $sth->execute($hit2,$src2,$ref2,$start2,$end2,$strand2,$seq2,$bin2,
		$src1,$ref1,$start1,$end1,$strand1,$seq1) or warn $sth->errstr;


  # saving pair-wise coordinate maps -- these are needed for gridlines
  for my $pos (sort {$a<=>$b} keys %map2) {
    next unless $pos && $map2{$pos};
    $sth2->execute($hit1,$src2,$pos,$map2{$pos}) or die $sth->errstr;
  }

  print STDERR " processed $hit1!\r" if $verbose;
}


$dbh->do('alter table alignments enable keys');

print "\nDone\n";

sub pad {
  my $num = shift;
  until ((length $num) >=6) {
    $num = '0' . $num;
  }
  $num;
}


sub invert {
  my $strand1 = shift;
  my $strand2 = shift;
  $$strand1 = $$strand1 eq '+' ? '-' : '+';
  $$strand2 = $$strand2 eq '+' ? '-' : '+'; 
}
