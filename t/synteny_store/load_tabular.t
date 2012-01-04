use strict;

use Test::More tests => 5;
use File::Temp;

use Bio::DB::Synteny::Store;

use_ok( 'Bio::DB::Synteny::Store::Loader::Tabular' );

SKIP: {
    eval { require DBI; my $s = DBI->connect( 'dbi:SQLite:dbname=:memory:' ) };
    skip 'DBD::SQLite not available, cannot test', 4 if $@;

    my $database_tempfile = File::Temp->new;
    $database_tempfile->close;

    my $store = Bio::DB::Synteny::Store->new(
        -adaptor => 'DBI::SQLite',
        -dsn     => "dbi:SQLite:dbname=$database_tempfile",
        -create  => 1,
        );

    can_ok( $store, 'add_alignment', 'add_map' );

    my $loader = Bio::DB::Synteny::Store::Loader::Tabular->new(
        -store  => $store,
        );

    can_ok( $loader, 'load' );

    $loader->load( 't/data/TOMvsPOT.subset.syntab' );

    for (['alignments',60],['map',0]) {
        is(
            $store->dbh->selectrow_arrayref("select count(*) from $_->[0]")->[0],
            $_->[1],
            "got right number of rows in $_->[0] table"
            );
    }

}
