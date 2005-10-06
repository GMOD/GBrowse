package Bio::DB::GFF::SyntenyIO;

use strict;
use DBI;
use Bio::DB::GFF::Util::Binning qw(bin bin_bot bin_top);
use Bio::DB::GFF::Util::Rearrange qw(rearrange);
use Bio::DB::GFF::SyntenyBlock;

use constant MINBIN => 1000;
use constant MAXBIN => 1_000_000_000;
use constant EPSILON  => 1e-7;  # set to zero if you trust mysql's floating point comparisons

sub new {
  my $class = shift;
  my $dsn   = shift;
  my $dbh;

  if (ref($dsn) && $dsn->isa('DBI::db')) {
    $dbh      = $dsn;
  } else {
    $dbh       = DBI->connect($dsn,@_) or die "$dsn: Can't open; ",DBI->errstr;
  }

  return bless {dbh=>$dbh},$class;
}

sub dbh { shift->{dbh} }

sub get_synteny_by_range {
  my $self = shift;
  my ($src,            # a symbolic data source, like "worm"
      $ref,            # reference for search range - contig or chromosome name
      $start,          # start of search range
      $end,            # end of search range
      $tgt             # optional data source target, like "yeast"
     ) = rearrange([qw(SRC REF START END TGT)],@_);
  my ($query,@args) = $self->make_range_query($src,$ref,$start,$end,$tgt);
  my $sth           = $self->dbh->prepare_cached($query) or die $self->dbh->errstr;
  $sth->execute(@args) or die $sth->errstr;
  my %HITS;
  while (my($hit,
	    $src,$ref1,$start1,$end1,$strand1,
	    $tgt,$ref2,$start2,$end2,$strand2) = $sth->fetchrow_array) {
    $HITS{$hit} ||= Bio::DB::GFF::SyntenyBlock->new($hit);
    $HITS{$hit}->add_part([$src,$ref1,$start1,$end1,$strand1],
			  [$tgt,$ref2,$start2,$end2,$strand2]
			 );
  }
  return values %HITS;
}

sub make_range_query {
  my $self = shift;
  my ($src,$ref,$start,$end,$tgt) = @_;
  my $query = "select hit_name,src1,ref1,start1,end1,strand1,src2,ref2,start2,end2,strand2\n\tFROM alignments";

  my @where = ();
  my @args  = ();

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
    $query .= "\n\tWHERE ".join(' AND ',@where);
  }

  return ($query,@args);
}

# stolen from Bio::DB::GFF::Adaptor::dbi
sub bin_query {
  my $self = shift;
  my ($start,$end) = @_;
  my ($query,@args);

  $start = 0       unless defined($start);
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
