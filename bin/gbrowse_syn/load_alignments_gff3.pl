#!/usr/bin/perl -w
# $Id: load_alignments_gff3.pl,v 1.1.2.2 2009-07-19 09:15:43 sheldon_mckay Exp $

use strict;
use Getopt::Long;
use DBI;
use Bio::DB::GFF::Util::Binning 'bin';
use Bio::DB::SeqFeature::Store;

use constant MINBIN   => 1000;
use constant FORMAT   => 'clustalw';
use constant VERBOSE  => 0;

use vars qw/$format $tempfile $outfh $user $pass $dsn $hit_idx $verbose/;

$| = 1;
GetOptions(
	   'format=s'    => \$format,
           'user=s'      => \$user,
	   'pass=s'      => \$pass,
	   'dsn=s'       => \$dsn,
	   'verbose'     => \$verbose
	   );

my $usage = "Usage: load_alignments_gff3.pl -u username -p password -d database [-f format, -v] file1, file2 ... filen\n\n";

$dsn     || die $usage;
$user    || die $usage;
$format  ||= FORMAT;
$verbose ||= VERBOSE;

my ($dbh,$sth_hit,$sth_map) = prepare_database($dsn,$user,$pass);

my $idx;
while (my $infile = shift) {

  print STDERR "Loading file $infile\n" if $verbose;

  my $db      = Bio::DB::SeqFeature::Store->new( -adaptor => 'memory',
                                                 -dsn     => $infile );

  my $matches = $db->get_seq_stream('match');
  
  while (my $match = $matches->next_seq) {
    my ($species1) = $match->each_tag_value('species1');
    my ($species2) = $match->each_tag_value('species2');
    my ($map1)  = $match->each_tag_value('map1');
    my ($map2)  = $match->each_tag_value('map2');
    my $ref     = $match->seq_id;
    my $start   = $match->start;
    my $end     = $match->end;
    my $strand  = $match->strand > 0 ? '+' : '-';
    my $target  = $match->target();
    my $ref2    = $target->ref;
    my $start2  = $target->start;
    my $end2    = $target->end;
    my $strand2 = $target->strand > 0 ? '+' : '-';
   

    my %map1 = split /\s+/, $map1;
    my %map2 = split /\s+/, $map2;

    load_alignment($species1,$ref,$start,$end,$strand,'.',$species2,$ref2,$start2,$end2,$strand2,'.',\%map1,\%map2);
  }
}


  

sub prepare_database {
  my ($dns,$user,$pass) = @_;
  $dsn = "dbi:mysql:$dsn" unless $dsn =~ /^dbi/;

  my $dbh = DBI->connect($dsn, $user, $pass) or die DBI->errstr;
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

  $dbh->do('alter table alignments disable keys');
  $dbh->do('alter table map');
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

  for my $pos (sort {$a<=>$b} keys %map1) {
    next unless $pos && $map1{$pos};
    $sth_map->execute($hit1,$src1,$pos,$map1{$pos}) or die $sth_map->errstr; 
  }

  # reciprocal hit is also saved to facilitate switching amongst reference sequences
  invert(\$strand1,\$strand2) if $strand2 eq '-';
  
  $sth_hit->execute($hit2,$src2,$ref2,$start2,$end2,$strand2,$seq2,$bin2,
		    $src1,$ref1,$start1,$end1,$strand1,$seq1) or warn $sth_hit->errstr;


  # saving pair-wise coordinate maps -- these are needed for gridlines
  for my $pos (sort {$a<=>$b} keys %map2) {
    next unless $pos && $map2{$pos};
    $sth_map->execute($hit1,$src2,$pos,$map2{$pos}) or die $sth_map->errstr;
  }

  print STDERR "Processed pair-wise alignment $hit_idx\n" if $verbose;

}

sub done {
  $dbh->do('alter table alignments enable keys');
  print "\nDone!\n\n";
}

sub invert {
  my $strand1 = shift;
  my $strand2 = shift;
  $$strand1 = $$strand1 eq '+' ? '-' : '+';
  $$strand2 = $$strand2 eq '+' ? '-' : '+'; 
}
