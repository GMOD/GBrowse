#-*-Perl-*-
## Bioperl Test Harness Script for Modules

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use ExtUtils::MakeMaker;
use Bio::Root::IO;
use FindBin '$Bin';
use constant TEST_COUNT => 29;
use Data::Dumper;

BEGIN {
    # to handle systems with no installed Test module
    # we include the t dir (where a copy of Test.pm is located)
    # as a fallback
    eval { require Test; };
    if( $@ ) {
        use lib 't';
    }
    use Test;
    plan test => TEST_COUNT;
}

use lib '.','..','./blib/lib','../lib';
use lib "$ENV{HOME}/cvswork/bioperl-live/";
use Bio::DB::Das::Chado;

sub bail ($;$) {
  my $count = shift;
  my $explanation = shift;
  for (1..$count) {
    skip($explanation,1);
  }
  exit 0;
}

sub fail ($) {
  my $count = shift;
  for (1..$count) {
    ok(0);
  }
  exit 0;
}

my (@f,$f,@s,$s,$seq1,$seq2);

my %args = (
          -dsn   => 'dbi:Pg:dbname=test',
          -user  => $ENV{DBUSER},
          -pass  => $ENV{DBPASS},
          -inferCDS => 0,
);

open (SAVEERR,">&STDERR");
my $foo = \*SAVEERR;
open (STDERR,">/dev/null");
my $db = eval { Bio::DB::Das::Chado->new(%args) };
open (STDERR,">&SAVERR");

unless ($db) {
  skip('No test database running',1) for 1..TEST_COUNT;
  exit 0;
}

ok($db);

# there should be one gene named 'abc-1'
@f = $db->get_feature_by_name('abc-1');

ok(@f==1);

$f = $f[0];
# there should be three subfeatures of type "exon" and three of type "CDS"
ok($f->get_SeqFeatures('exon')==3);

#since inferCDS is off, this wouldn't pass.
#ok($f->get_SeqFeatures('CDS')==3);

# the sequence of feature abc-1 should match the sequence of the first exon at the beginning
$seq1 = $f->seq->seq;
#get the first exon
my @objs = sort {$a->start<=>$b->start} $f->get_SeqFeatures('exon');
$seq2 = $objs[0]->seq->seq;
ok(substr($seq1,0,length $seq2) eq $seq2);

# sequence lengths should match
ok(length $seq1 == $f->length);

# if we pull out abc-1 again we should get the same object
# chado adaptor doesn't overload eq (SeqFeature does?)
#($s) = $db->get_feature_by_name('abc-1');
#ok($f eq $s);

# we should get two objects when we ask for abc-1 using get_features_by_alias
# this also depends on selective subfeature indexing
@f = $db->get_features_by_alias('abc-1');
ok(@f==2);

# the two features should be different
# chado adaptor doesn't overload ne
#ok($f[0] ne $f[1]);

# test that targets are working
($f) = $db->get_feature_by_name('match1');
ok(defined $f);
$s = $f->target;
ok(defined $s);
ok($s->seq_id  eq 'CEESC13F');
$seq1 = $s->seq->seq;
ok(substr($seq1,0,10) eq 'ttgcgttcgg');

# can we fetch subfeatures?
# gene3.a has the Index=1 attribute, so we should fetch it
($f) = $db->get_feature_by_name('gene3.a');
ok($f);

# gene 3.b doesn't have an index, so we shouldn't get it
#($f) = $db->get_feature_by_name('gene3.b');
#ok(!$f);

# test three-tiered genes
($f) = $db->get_feature_by_name('gene3');
ok($f);
my @transcripts = $f->get_SeqFeatures;
ok(@transcripts == 2);
ok($transcripts[0]->method eq 'mRNA');
ok($transcripts[0]->source eq 'confirmed');

# test that exon #2 is shared between the two transcripts
# it shouldn't get anything unless we tell it to infer CDSs
my @exons1      = $transcripts[0]->get_SeqFeatures('CDS');
ok(@exons1 == 0);

#make a new instance of the chado object with inferCDS turned on
%args = (
          -dsn   => 'dbi:Pg:dbname=test',
          -user  => $ENV{DBUSER},
          -pass  => $ENV{DBPASS},
          -inferCDS=>1,
);

#start over again now the inferCDS is on
$db          = Bio::DB::Das::Chado->new(%args);
($f)         = $db->get_feature_by_name('gene3');

@transcripts = $f->get_SeqFeatures;

@exons1      = $transcripts[0]->get_SeqFeatures('CDS');

#this test currently fails because the loader doesn't deal
#with UTRs correctly,
ok(@exons1 == 3);


my @exons2      = $transcripts[1]->get_SeqFeatures('CDS');

my ($shared1)   = grep {$_->display_name||'' eq 'shared_exon'} @exons1;
my ($shared2)   = grep {$_->display_name||'' eq 'shared_exon'} @exons2;
ok($shared1 && $shared2);

#no overloading of eq
#ok($shared1 eq $shared2);
#ok($shared1->primary_id eq $shared2->primary_id);

# test attributes
#print Dumper($shared1);
ok($shared1->phase == 0);
ok($shared1->strand eq +1);
ok(($f->attributes('expressed'))[0] eq 'yes');

# test autoloading
my ($gene3a) = grep { $_->display_name eq 'gene3.a'} @transcripts;
my ($gene3b) = grep { $_->display_name eq 'gene3.b'} @transcripts;
ok($gene3a);
ok($gene3b);

#AUTOLOAD doesn't work
#ok($gene3a->Is_expressed);
#ok(!$gene3b->Is_expressed);

# the representation of the 3'-UTR in the two transcripts a and b is
# different (not recommended but supported by the GFF3 spec). In the
# first case, there are two 3'UTRs existing as independent
# features. In the second, there is one UTR with a split location.
#ok($gene3a->Three_prime_UTR == 2);
#ok($gene3b->Three_prime_UTR == 1);
#my ($utr) = $gene3b->Three_prime_UTR;

my @utr = $gene3b->get_SeqFeatures('three_prime_UTR');
ok(@utr == 2);

my ($inferred_utr) = grep { $_->display_name eq 'straddle_exon' } @utr;
ok($inferred_utr->start == 2801);
ok($inferred_utr->end   == 2900);

#my $location = $utr->location;
#ok($location->isa('Bio::Location::Split'));

#fails because it's not a Bio::Location::Split
#ok($location->sub_Location == 2);

# ok, test that queries are working properly.
# find all features with the attribute "expressed"

# fails because there isn't a get_features_by_attribute method (yet)
#@f = $db->get_features_by_attribute({expressed=>'yes'});
#ok(@f == 2);

# find all top-level features on Contig3 -- there should be two

# fails because there isn't a get_features_by_location method (yet)
#@f = $db->get_features_by_location(-seq_id=>'Contig3');
#ok(@f == 2);

# find all top-level features on Contig3 of type 'Component'


#fails--don't know why
#@f = $db->features(-seq_id=>'Contig3',-type=>'contig');
#ok(@f==1);

#fails don't know why
# test iteration
#@f = $db->features;
my $feature_count;
#my $feature_count = @f;
#ok($feature_count > 0);

#fails -- get_seq_stream isn't implemented
my $i;
#my $i = $db->get_seq_stream;
#ok($i);

#my $count;
#while ($i->next_seq) { $count++ }
#ok($feature_count == $count);


# test getting descriptions and scores from analysis results

my ($match1) = $db->get_features_by_name('match1');
my $score    = $match1->score;
ok($score == 96);

my ($match5) = $db->get_features_by_name('match5');
$score =  $match5->score;
ok($score == 0);

my ($note) = $match5->notes;
ok('this is a note test' eq $note);

1;

__END__

