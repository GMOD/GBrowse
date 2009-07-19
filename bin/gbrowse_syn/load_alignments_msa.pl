#!/usr/bin/perl -w
# $Id: load_alignments_msa.pl,v 1.1.2.2 2009-07-19 09:15:43 sheldon_mckay Exp $

use strict;
use Bio::AlignIO;
use List::Util 'sum';
use Getopt::Long;
use DBI;
use Bio::DB::GFF::Util::Binning 'bin';

use constant MINBIN   => 1000;
use constant FORMAT   => 'clustalw';
use constant VERBOSE  => 0;

use vars qw/$format $tempfile $outfh $user $pass $dsn $hit_idx $aln_idx $verbose $nomap/;

$| = 1;
GetOptions(
	   'format=s'    => \$format,
           'user=s'      => \$user,
	   'pass=s'      => \$pass,
	   'dsn=s'       => \$dsn,
	   'verbose'     => \$verbose,
	   'nomap'       => \$nomap     
	   );

my $usage = "Usage: load_alignments_msa.pl -u username -p password -d database [-f format, -v, -n] file1, file2 ... filen\n\n";

$dsn     || die $usage;
$user    || die $usage;
$format  ||= FORMAT;
$verbose ||= VERBOSE;

my ($dbh,$sth_hit,$sth_map) = prepare_database($dsn,$user,$pass);

while (my $infile = shift) {
  print "Processing alignment file $infile...\n" if $verbose;
  my $alignIO = Bio::AlignIO->new( -file   => $infile, 
				   -format => $format);

  while (my $aln = $alignIO->next_aln) {
    print "Processing alignment " . ++$aln_idx . "\n" if $verbose; 
    next if $aln->num_sequences < 2;
    my %seq;
    my $map = {};
    for my $seq ($aln->each_seq) {
      my $seqid = $seq->id;
      my ($species,$ref,$strand) = check_name_format($seqid,$seq);
      next if $seq->seq =~ /^-+$/;
      $seq{$species} = [$ref, $seq->display_name, $seq->start, $seq->end, $strand, $seq->seq, $seq]; 
    }
    
    unless ($nomap) {
      print "Mapping coordinates for alignment $aln_idx... " if $verbose;
      map_coords($seq{$_},$map) for keys %seq;
      print "Done!\n" if $verbose;
    }

    # make all pairwise hits and grid coordinates
    my @species = keys %seq;
    
    for my $p (map_pairwise(@species)) {
      my ($s1,$s2) = @$p;
      my $array1 = $seq{$s1};
      my $array2 = $seq{$s2};

      unless ($nomap) {
	$array1->[6] = make_map($array1,$array2,$map);
	$array2->[6] = make_map($array2,$array1,$map);
      }
      make_hit($s1 => $array1, $s2 => $array2);
    }
  }
}  

sub make_map {
  my ($s1,$s2,$map) = @_;
  $s1 && $s2 || return {};
  my $seq1 = $s1->[1];
  my $seq2 = $s2->[1];
  my $coord = nearest(100,$s1->[2]);
  $coord += 100 if $coord < $s1->[2];
  my @map;
  
  my $reverse = $s2->[4] ne $s1->[4];
  my $strand2 = $reverse ? 'minus' : 'plus';
  
  while(1) {
    last if $coord >= $s1->[3];
    my $col = $map->{$seq1}{pmap}{plus}{$coord};
    my $coord2  = $map->{$seq2}{cmap}{$col}{$strand2};
    push @map, ($coord,$coord2) if $coord2;
    $coord += 100;
  }
  return {@map};
}

sub map_coords {
  my ($s,$map) = @_;
  my $forward_offset = $s->[2]-1;
  my $reverse_offset = $s->[3];
  my @chars = split '', $s->[5];
  my $cmap  = {};
  my $pmap = {};
  
  for my $col (1..@chars) {
    # forward strand map
    my $gap = $chars[$col-1] eq '-';
    $forward_offset++ unless $gap;
    $cmap->{$col}->{plus} = $forward_offset;
    push @{$pmap->{plus}->{$forward_offset}}, $col;
    # reverse strand map
    $reverse_offset-- unless $gap;
    $cmap->{$col}->{minus} = $reverse_offset;
    push @{$pmap->{minus}->{$reverse_offset}}, $col;
  }
  
  # position maps to middle of gap if gaps are present
  for my $coord (keys %{$pmap->{minus}}) {
      my $ary = $pmap->{minus}->{$coord};
      if (@$ary == 1) {
	  $ary = @$ary[0];
      }
      else {
	  # round down mean
	  $ary = int((sum(@$ary)/@$ary));
      }
      $pmap->{minus}->{$coord} = $ary;
  }
  for my $coord (keys %{$pmap->{plus}}) {
      my $ary = $pmap->{plus}->{$coord};
      if (@$ary == 1) {
          $ary = @$ary[0];
      }
      else {
          # round up mean
          $ary = int((sum(@$ary)/@$ary)+0.5);
      }
      $pmap->{plus}->{$coord} = $ary;
  }
  $map->{$s->[1]}{cmap} = $cmap;    
  $map->{$s->[1]}{pmap} = $pmap;
}



sub make_hit {
  my ($s1,$aln1,$s2,$aln2,$fh) = @_;
  die "wrong number of keys @$aln1" unless @$aln1 == 7;
  die "wrong number of keys @$aln2" unless @$aln2 == 7;
  my $map1 = $aln1->[6] || {};
  my $map2 = $aln2->[6] || {};

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

I am sorry, I do not like the sequence name: $name

This will not work unless you use the name format described below for each
sequence in the alignment.  

We need the species, sequence name, strand, start and end for
each sequence in the alignment.

  Name format:
    species-sequence(strand)/start-end
  
    where species   = name of species, genome, strain, etc (string with no '-' characters)
          sequence  = name of reference sequence (string with no '/' characters)
          (strand)  = orientation of the alignment (relative to the reference sequence; + or -)
          start     = start coordinate of the alignment relative to the reference sequence (integer)
          end       = end coordinate of the alignment relative to the reference sequence   (integer)

  Examples:
    c_elegans-I(+)/1..2300
    myco_bovis-chr1(-)/15000..25000

  END
  ;

  die $nogood unless $name =~ /^([^-]+)-([^\(]+)\(([+-])\)$/;
  die $nogood unless $seq->start && $seq->end;
  return ($1,$2,$3);
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
