package Bio::DB::Synteny::Store::DBI::SQLite;
use strict;

use base 'Bio::DB::Synteny::Store::DBI';

sub init_database {
    my ( $self, $erase ) = @_;

    my $dbh = $self->dbh;

    if( $erase ) { # drop the tables if they exist
        local $dbh->{RaiseError} = 0;
        local $dbh->{PrintError} = 0;
        $dbh->do( 'DROP TABLE alignments' );
        $dbh->do( 'DROP TABLE map' );
    }

    $dbh->do( <<'');
      CREATE TABLE alignments (
                         hit_id    INTEGER PRIMARY KEY AUTOINCREMENT,
                         hit_name  VARCHAR(100) NOT NULL,
                         src1      VARCHAR(100) NOT NULL,
                         ref1      VARCHAR(100) NOT NULL,
                         start1    INT NOT NULL,
                         end1      INT NOT NULL,
                         strand1   VARCHAR(1) NOT NULL,
                         seq1      TEXT,
                         bin       NUMERIC(20,6) NOT NULL,
                         src2      VARCHAR(100) NOT NULL,
                         ref2      VARCHAR(100) NOT NULL,
                         start2    INT NOT NULL,
                         end2      INT NOT NULL,
                         strand2   VARCHAR(1) NOT NULL,
                         seq2      TEXT
                         );

    $dbh->do( <<'');
      CREATE TABLE map (
                  map_id   INTEGER PRIMARY KEY AUTOINCREMENT,
                  hit_name VARCHAR(100) NOT NULL,
                  src1     VARCHAR(100),
                  pos1     INT NOT NULL,
                  pos2     INT NOT NULL
                  );

    $dbh->do( <<'');
      CREATE INDEX map_hit_name ON map (hit_name);

}

1;
