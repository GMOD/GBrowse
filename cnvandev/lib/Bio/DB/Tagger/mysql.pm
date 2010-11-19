package Bio::DB::Tagger::mysql;

use strict;
use warnings;
use base 'Bio::DB::Tagger';

sub _table_definitions {
    my $self = shift;
    my $init = '';
    while (<DATA>) {
	last if /^__END__/;
	$init .= $_;
    }
    return split ";\n",$init;
}

sub _add_tags {
    my $self = shift;
    my ($objectname,$tags) = @_;

    my $dbh = $self->dbh;
    # create/get object id
    my $oid = $self->object_to_id($objectname,1);
    for my $tag (@$tags) {
	my $tid = $self->tag_to_id($tag->name,1);
	my $aid = $self->author_to_id($tag->author,1);
	my $value = $tag->value;
	$dbh->begin_work;
	eval {
	    local $dbh->{RaiseError}=1;
	    my $sth = $self->dbh->prepare(
		"REPLACE INTO tag (oid,tid,aid,tvalue) VALUES (?,?,?,?)"
		);
	    $sth->execute($oid,$tid,$aid,$value);
	    $dbh->commit;
	};
	if ($@) {
	    warn $@;
	    $dbh->rollback;
	}
    }
}


1;

__DATA__

DROP TABLE IF EXISTS tagname;
CREATE TABLE tagname (
    tid    int(11) auto_increment primary key,
    tname  varchar(255) not null,
    unique key(tname(64))
) ENGINE=InnoDB;

DROP TABLE IF EXISTS author;
CREATE TABLE author (
    aid     int(11) auto_increment primary key,
    aname   varchar(255) not null,
    unique key(aname(64))
) ENGINE=InnoDB;

DROP TABLE IF EXISTS object;
CREATE TABLE object (
    oid          int(11) auto_increment primary key,
    oname        varchar(512) not null,
    unique key(oname(64))
) ENGINE=InnoDB;

DROP TABLE IF EXISTS tag;
CREATE TABLE tag (
    oid         int(11) not null,
    tid         int(11) not null,
    aid         int(11) not null,
    tvalue      longblob,
    tmodified   timestamp,
    key(oid),
    key(tid,aid)
) ENGINE=InnoDB;

__END__
