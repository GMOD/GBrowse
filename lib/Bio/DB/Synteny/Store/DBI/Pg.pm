package Bio::DB::Synteny::Store::DBI::Pg;
use strict;

use base 'Bio::DB::Synteny::Store::DBI';

sub init_database {
    my ( $self, $erase ) = @_;

    my $dbh = $self->dbh;

    if( $erase ) { # drop the tables if they exist
        local $dbh->{RaiseError} = 0;
        local $dbh->{PrintError} = 0;
        $dbh->do( 'DROP TABLE alignments, map' );
    }

    $dbh->do( <<EOSQL );
      CREATE TABLE alignments (
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

      ALTER TABLE alignments ADD CONSTRAINT strand1_val CHECK( strand1='+' OR strand1 ='-' );
      ALTER TABLE alignments ADD CONSTRAINT strand2_val CHECK( strand2='+' OR strand2 ='-' );

      CREATE TABLE map (
	  	  map_id serial not null,
		  hit_name  varchar(100) not null,
                  src1 varchar(100),
		  pos1 int not null,
		  pos2 int not null,
		  primary key(map_id)

		  );

      CREATE INDEX map_hit_name ON map (hit_name) DEFERRABLE INITIALLY DEFERRED;

EOSQL

}

1;
