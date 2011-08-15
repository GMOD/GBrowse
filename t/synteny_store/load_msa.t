use strict;

use Test::More tests => 5;
use File::Temp;

use Bio::DB::Synteny::Store;

use_ok( 'Bio::DB::Synteny::Store::Loader::MSA' );

my $database_tempfile = File::Temp->new;
$database_tempfile->close;

my $store = Bio::DB::Synteny::Store->new(
    -adaptor => 'DBI::SQLite',
    -dsn     => "dbi:SQLite:dbname=$database_tempfile",
    -create  => 1,
);

can_ok( $store, 'add_alignment', 'add_map' );

#system "ls -l $database_tempfile";

my $loader = Bio::DB::Synteny::Store::Loader::MSA->new(
    -store  => $store,
    -format => 'clustalw',
    );

can_ok( $loader, 'load' );

$loader->load( 't/data/rice_subset.aln' );

for (['alignments',8],['map',444]) {
  is(
    $store->dbh->selectrow_arrayref("select count(*) from $_->[0]")->[0],
    $_->[1],
    "got right number of rows in $_->[0] table"
    );
}

#system "ls -l $unzipped $database_tempfile";

#######
