package Bio::DB::Synteny::Store::DBI::mysql;
use strict;

use base 'Bio::DB::Synteny::Store::DBI';

sub init_database {
    my ( $self, $erase ) = @_;

    my $dbh = $self->dbh;

    if( $erase ) { # drop the tables if they exist
        $dbh->do( 'DROP TABLE IF EXISTS alignments' );
        $dbh->do( 'DROP TABLE IF EXISTS map' );
    }

    $dbh->do( <<'' );
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

    $dbh->do( <<'' );
    create table map (
                 map_id int not null auto_increment,
                 hit_name  varchar(100) not null,
                 src1 varchar(100),
                 pos1 int not null,
                 pos2 int not null,
                 primary key(map_id),
                 index(hit_name)
                 )

}

1;
