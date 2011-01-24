package Bio::DB::Tagger;
# $Id$

use strict;
use warnings;
use Carp 'croak';
use DBI;
use Bio::DB::Tagger::Tag;

our $VERSION = '1.00';

=head1 NAME

Bio::DB::Tagger -- Simple object tagging system

=head1 SYNOPSIS

 use Bio::DB::Tagger;
 my $tagger = Bio::DB::Tagger->new(-dsn    => 'dbi:mysql:tagdb',
                                   -create => 1);

 $tagger->add_tags(-object => $object_name,
                   -tags   => \@tags);

 $tagger->set_tags(-object => $object_name,
                   -key    => $object_key,
                   -tags   => \@tags);

 $tagger->add_tag(-object  => $object_name,
                  -tag     => 'venue',
                  -value   => 'mermaid parade',
                  -author  => 'lincoln.stein@gmail.com');

 $tagger->add_tag(-object  => $object_name,
                  -tag     => $tag);

 $tagger->add_tag($object_name => $tag);

 $tagger->clear_tags($object_name);                      # delete all tags attached to object
 $tagger->delete_tag($object_name,$tag_name [,$value]);  # delete one tag attached to object

 $tagger->nuke_tag($tag_name);                           # delete this tag completely
 $tagger->nuke_object($object_name);
 $tagger->nuke_author($author_name);

 my @tags  = $tagger->get_tags($object_name [,$author]);
 print "first tag = $tags[0]\n";              # Tag stringify interface
 print "tag value = ",$tags[0]->value,"\n";   # object interface
 print "tag author= ",$tags[0]->author,"\n";  # object interface

 my $hasit    = $tagger->has_tag($object_name,$tag);

 my @objects  = $tagger->search_tag($tag);

 my @tags  = $tagger->tags;
 
 my $iterator = $tagger->tag_match('prefix');
 while (my $tag = $iterator->next_tag) { }

=head1 DESCRIPTION

This is a simple object tagger interface that provides relational
support for tagging objects (identified by string IDs) with arbitrary
string tags.

=head2 METHODS

=over 4

=item $tagger = Bio::DB::Tagger->new(@args)

Constructor for the tagger class. Arguments are:

  -dsn    <dsn>    A DBI data source, possibly including host and
                    password information

  -create <0|1>    If true, then database will be initialized with a
                    new schema. Database must already exist.

The dsn can be a preopened database handle or a dbi: data source
string.

=cut

sub new {
    my $class  = shift;

    unshift @_,'-dsn' if @_ == 1;
    my %args   = @_;
    my $dsn    = $args{-dsn};
    my $create = $args{-create};
    croak "Usage: $class->new(-dsn=>'dbi:...' [,-create=>1]"
	unless $dsn;

    my $dbh  = (ref $dsn && $dsn->isa('DBI::db'))
	          ? $dsn
                  : DBI->connect($dsn,undef,undef,{AutoCommit=>1});
    $dbh or croak "Could not connect to $dsn: ",DBI->errstr;
    
    my $driver  = $dbh->{Driver}{Name};
    my $package = __PACKAGE__.'::'.$driver;
    
    unless ($package->can('new') or eval "require $package; 1") {
	croak ($@,
	       "No Tagger interface for database driver $driver is available. ",
	       "Someone needs to write the package $package");
    }

    my $self = bless {dbh=>$dbh},$package;

    $self->initialize() if $create;
    return $self;
}

=item @objects = $tagger->search_tag($tag [,$value])

=item $object_arrayref = $tagger->search_tag($tag [,$value])

Return all object names and keys that are tagged with "$tag",
optionally qualified by tag value $value.

=cut

sub search_tag {
    my $self         = shift;
    my ($tag,$value) = @_;
    my $query = <<END;
SELECT distinct oname, okey
  FROM tag
   NATURAL JOIN tagname
   NATURAL JOIN object
  WHERE tname=?
END
;
    my @bind = ($tag);
    if (defined $value) {
	$query .= 'AND tvalue=?';
	push @bind,$value;
    }

    my $arrayref = $self->dbh->prepare($query)
	or croak $self->dbh->errstr;
    $arrayref->execute(@bind)
	or croak $self->dbh->errstr;

    my @result;
    while (my ($object,$key) = $arrayref->fetchrow_array) {
	push @result,
	Bio::DB::Tagger::Tag->new(-name=>$object,
				  -value=>$key);
    }
    return @result;
}

=item $boolean = $tagger->has_tag($object,$tag [,$value])

Returns true if indicated object has the indicated tag, or the
indicated combination of tag and value.

=cut

sub has_tag {
    my $self         = shift;
    my ($object,$tag,$value) = @_;
    my $query = <<END;
SELECT count(*)
  FROM tag
   NATURAL JOIN tagname
   NATURAL JOIN object
  WHERE oname=?
  AND   tname=?
END
;
    my $name = ref($tag) ? $tag->name : $tag;
    my @bind = ($object,$name);
    if (defined $value) {
	$query .= 'AND tvalue=?';
	push @bind,$value;
    }
    my ($count) = $self->dbh->selectrow_array($query,{},@bind)
	or croak $self->dbh->errstr;
    return $count;
}

=item @tags = $tagger->get_tag($object,$tag)

Returns all the tags of type $tag.

=cut

sub get_tag {
    my $self         = shift;
    my ($object,$tag,$value) = @_;
    my $query = <<END;
SELECT distinct tname,tvalue,aname,tmodified
  FROM tag
   NATURAL JOIN tagname
   NATURAL JOIN author
   NATURAL JOIN object
  WHERE oname=?
  AND   tname=?
END
;
    my $name = ref($tag) ? $tag->name : $tag;
    my @bind = ($object,$name);

    my $sth = $self->dbh->prepare($query)
	or croak $self->dbh->errstr;
    $sth->execute(@bind)
	or croak $self->dbh->errstr;
    my @result;
    while (my ($tag,$value,$author,$modified) = $sth->fetchrow_array) {
	push @result,
	Bio::DB::Tagger::Tag->new(-name=>$tag,
				  -value=>$value,
				  -author=>$author,
				  -modified=>$modified);
    }
    return @result;
}

=item $tags = $tagger->tags()

=item @tags = $tagger->tags()

Return a list of all tags in the database. In a list context, returns
the list of tags. In an array context, returns an array ref.

=cut

sub tags {
    my $self = shift;
    my $ary  = $self->dbh->selectcol_arrayref('SELECT tname FROM tagname');
    return wantarray ? @$ary : $ary;
}

=item $iterator = $tagger->tag_match('prefix')

Returns an iterator that matches all tags beginning with 'prefix'
(case insensitive). Call $iterator->next_tag() to get the next match.

=cut

sub tag_match {
    my $self   = shift;
    my $prefix = shift;
    my $sth   = $self->dbh->prepare(<<END) or croak $self->dbh->errstr;
SELECT tname 
  FROM tagname 
 WHERE tname LIKE ?
 ORDER BY tname
END
;
    $prefix =~ s/%/\\%/g;
    $prefix =~ s/_/\\_/g;
    $sth->execute($prefix.'%') or croak $sth->errstr;
    return Bio::DB::Tagger::Iterator->new($sth);
}

=item $iterator = $tagger->tag_match('prefix')

Returns an iterator that matches all tags beginning with 'prefix'
(case insensitive). Call $iterator->next_tag() to get the next match.

=cut

sub author_match {
    my $self   = shift;
    my $prefix = shift;
    my $sth   = $self->dbh->prepare(<<END) or croak $self->dbh->errstr;
SELECT aname
  FROM author
 WHERE aname LIKE ?
 ORDER BY aname
END
;
    $prefix =~ s/%/\\%/g;
    $prefix =~ s/_/\\_/g;
    $sth->execute($prefix.'%') or croak $sth->errstr;
    return Bio::DB::Tagger::Iterator->new($sth);
}

=item $tags = $tagger->tag_counts()

=item @tags = $tagger->tag_counts()

Return a set of Bio::DB::Tagger::Tag objects representing all known
tags. The tag values correspond to the number of times that tag has
been used to tag objects.

=cut

sub tag_counts {
    my $self = shift;
    my $sth  = $self->dbh->prepare(<<END) or croak $self->dbh->errstr;
SELECT tname,count(tname)
  FROM tag,tagname
 WHERE tag.tid=tagname.tid
 GROUP BY tag.tid
END
;
    $sth->execute() or croak $self->dbh->errstr;
    my @result;
    while (my($tagname,$count) = $sth->fetchrow_array) {
	push @result,
	Bio::DB::Tagger::Tag->new(-name  => $tagname,
				  -value => $count);
    }
    return wantarray ? @result : \@result;
}

=item $result = $tagger->add_tag(@args);

Add a tag to the database. The following forms are accepted:

 $tagger->add_tag($object_name=>$tag);

Add a Bio::DB::Tagger::Tag to the object named "$object_name".

 $tagger->add_tag(-object => $object_name,
                  -tag    => $tag);

The same as above using -option syntax.

 $tagger->add_tag(-object => $object_name,
                  -tag    => $tagname,
                  -value  => $tagvalue,
                  -author => $authorname);

Generate the tag from the options provided in B<-tag>, B<-value>
(optional) and B<-author> (optional), and then add the tag to the
object.

Returns true on success.

=cut

sub add_tag {
    my $self = shift;
    my ($objectname,$tag,%args);

    if (@_ == 2) {
	$objectname = shift;
	$tag        = shift;
    } else {
	%args    = @_;
	$tag        = $args{-tag};
	$objectname = $args{-object};
    }
    unless (ref $tag && $tag->isa('Bio::DB::Tagger::Tag')) {
	$tag = Bio::DB::Tagger::Tag->new(-name  => $tag,
					 -value => $args{-value},
					 -author=> $args{-author}
	    );
    }
    
    croak 'usage: add_tag(-object=>$object_name,-tag=>$tag)'
	unless defined $objectname && $tag;
    return if $self->has_tag($objectname,$tag);
    $self->_set_tags($objectname,[$tag]);
}

=item $result = $tagger->set_tags(@args);

Set the tags of an object, replacing all previous tags.

Arguments: B<-object>  Name of the object to tag.
           B<-tags>    List of Bio::DB::Tagger::Tag objects

Returns true on success.

=cut

sub set_tags {
    my $self = shift;
    my %args = @_;
    my $object = $args{-object};
    my $key    = $args{-key};
    my $tags   = $args{-tags};
    defined $object && $key && $tags && ref $tags eq 'ARRAY'
	or croak 'Usage: $tagger->set_tags(-object=>$object_name,-key=>$object_key,-tags=>[$tag1,$tag2...])';
    $self->_set_tags($object,$tags,1,$key);
}

=item $result = $tagger->set_tag(@args);

Set a tag, replacing all previous tags of the same name.

Arguments: B<-object>  Name of the object to tag.
           B<-tag>     A Bio::DB::Tagger::Tag object, or tag name

Returns true on success.

=cut

sub set_tag {
    my $self = shift;
    my %args;
    if (@_ == 2) {
	%args = (-object=> shift(),
		 -tag   => shift());
    } else {
	%args = @_;
    }

    my $object = $args{-object};
    my $tag    = $args{-tag};
    defined $object && $tag
	or croak 'Usage: $tagger->set_tag(-object=>$object_name,-tag=>$tag)';
    $tag = Bio::DB::Tagger::Tag->new(-name=>$tag,
				     -value=>$args{-value},
				     -author=>$args{-author}
	)
	unless ref $tag;
    $self->delete_tag($object,$tag);
    $self->add_tag($object,$tag);
}

=item $result = $tagger->clear_tags($objectname);

Clear all tags from the indicated object. Returns true if the
operation was successful.

=cut

sub clear_tags {
    my $self       = shift;
    my $objectname = shift;
    $self->_set_tags($objectname,[],1);
}

=item $result = $tagger->delete_tag($objectname,$tagname [,$tagvalue]);

Clear the one tag from the indicated object, filtering by tagname,
optionally by value.

=cut

sub delete_tag {
    my $self       = shift;
    my ($objectname,$tagname,$tagvalue) = @_;
    my $dbh  = $self->dbh;

    $dbh->begin_work;

    eval {
	my $query = <<END;
DELETE FROM tag
 USING tag,tagname,object
 WHERE tag.oid=object.oid
   AND tag.tid=tagname.tid
   AND object.oname=?
   AND tagname.tname=?
END
;
	my @bind = ($objectname,$tagname);
	if (defined $tagvalue) {
	    $query .= ' AND tag.value=?';
	    push @bind,$tagvalue;
	}
	$dbh->do($query,{},@bind) or die $dbh->errstr;

	# remove defunct tags
	my ($count)  = $dbh->selectrow_array(<<END);
SELECT count(*)
  FROM tag,tagname
  WHERE tag.tid=tagname.tid
    AND tagname.tname=?
END
;
	$self->nuke_tag($tagname)     if $count == 0;
	$dbh->commit;
    };
    if ($@) {
	warn $@;
	$dbh->rollback;
	return;
    }
    return 1;
}

=item $result = $tagger->nuke_object($objectname);

Removes the object named $objectname. Returns true if the operation
was successful.

=cut

sub nuke_object {
    my $self       = shift;
    my $objectname = shift;
    $self->_nuke_object($objectname,
			  'object',
			  'oname',
			  'oid');
}

=item $result = $tagger->nuke_author($authorname);

Removes the author named $authorname. Returns true if the operation
was successful.

=cut

sub nuke_author {
    my $self       = shift;
    my $authorname = shift;
    $self->_nuke_object($authorname,
			  'author',
			  'aname',
			  'aid');
}

=item $result = $tagger->nuke_tag($tagname);

Removes the tag named $tagname. Returns true if the operation was
successful.

=cut

sub nuke_tag {
    my $self    = shift;
    my $tagname = shift;
    $self->_nuke_object($tagname,
			'tagname',
			'tname',
			'tid');
}

sub _nuke_object {
    my $self       = shift;
    my ($name,$table,$namefield,$idfield) = @_;
    my $dbh        = $self->dbh;

    my $in_transaction = !$dbh->{AutoCommit};

    my $rows = 0;
    $dbh->begin_work unless $in_transaction;
    eval {
	my $query =<<END;
DELETE FROM $table,tag
      USING $table
      LEFT JOIN tag ON $table.$idfield=tag.$idfield
      WHERE $table.$namefield=?
END
;
	my $sth = $dbh->prepare($query);
	$rows = $sth->execute($name);
	$dbh->commit unless $in_transaction;
    };
    if ($@) {
	die $@ if $in_transaction;
	warn $@;
	$dbh->rollback unless $in_transaction;
	return;
    }
    return $rows;
}

sub _set_tags {
    my $self = shift;
    my ($objectname,$tags,$replace,$key) = @_;

    my $dbh = $self->dbh;
    $dbh->begin_work;
    eval {
	local $dbh->{RaiseError}=1;
	# create/get object id
	my $oid = $self->object_to_id($objectname,1,$key);
	$dbh->do("DELETE FROM tag WHERE oid=$oid")
	    if $replace;
	for my $tag (@$tags) {
	    my $tid = $self->tag_to_id($tag->name,1);
	    my $aid = $self->author_to_id($tag->author,1);
	    my $value = $tag->value;

	    my $sth = $dbh->prepare(
		"INSERT INTO tag (oid,tid,aid,tvalue) VALUES (?,?,?,?)"
		);
	    $sth->execute($oid,$tid,$aid,$value);
	}
	$dbh->commit;
    };
    if ($@) {
	warn $@;
	$dbh->rollback;
    }
}

=item @tags = $tagger->get_tags($object_name [,$author])

Return all tags assigned to the indicated object, optionally
filtering by the author.

=cut

sub get_tags {
    my $self           = shift;
    my ($oname,$aname) = @_;
    my $query = <<END;
SELECT distinct tname,tvalue,aname,tmodified
  FROM tag 
  NATURAL JOIN tagname
  NATURAL JOIN author
  NATURAL JOIN object
 WHERE  oname=?
END
;
    my @bind = ($oname);
    if (defined $aname) {
	$query .= ' AND aname=?';
	push @bind,$aname;
    }
    my $sth = $self->dbh->prepare($query)
	or croak $self->dbh->errstr;
    $sth->execute(@bind)
	or croak $self->dbh->errstr;
    my @result;
    while (my ($tag,$value,$author,$modified) = $sth->fetchrow_array) {
	push @result,
	Bio::DB::Tagger::Tag->new(-name=>$tag,
				  -value=>$value,
				  -author=>$author,
				  -modified=>$modified);
    }
    return @result;
}

=item $oid = $tagger->object_to_id($objectname [,$create] [,$key])

Fetch the object id (oid) of the object named "$objectname". If the
object doesn't exist, and $create is true, will create a new entry for
the object in the database.

=cut

sub object_to_id {
    my $self = shift;
    return $self->_name_to_id('object','oid','oname',@_);
}

=item $tid = $tagger->tag_to_id($tagname [,$create])

Fetch the tag id (tid) of the object named "$tagname". If the tag
doesn't exist, and $create is true, will create a new entry for the
tag in the database.

=cut

sub tag_to_id {
    my $self = shift;
    return $self->_name_to_id('tagname','tid','tname',@_);
}

=item $aid = $tagger->author_to_id($authorname [,$create])

Fetch the author id (aid) of the object named "$authorname". If the
tag doesn't exist, and $create is true, will create a new entry for
the author in the database.

=cut

sub author_to_id {
    my $self = shift;
    return $self->_name_to_id('author','aid','aname',@_);
}

sub _name_to_id {
    my $self = shift;
    my ($table,$index_col,$name_col,$name,$create,$key) = @_;
    my ($id) = $self->dbh->selectrow_array(
	"SELECT $index_col FROM $table WHERE $name_col=?",
	{},
	$name);
    return $id if defined $id;
    return unless $create;

    # we get here if oid is undef
    local $self->dbh->{RaiseError}=1;

    my $sth = $self->dbh->prepare("INSERT INTO $table ($name_col) VALUES (?)");
    $sth    = $self->dbh->prepare("INSERT INTO $table ($name_col, okey) VALUES (?, $key)")
        if ($table eq 'object') && (defined $key);

    $sth->execute($name);
    # in case someone else got there before us!
    ($id) = $self->dbh->selectrow_array(
	"SELECT $index_col FROM $table WHERE $name_col=?",
	{},
	$name);
    return $id;
}

=item $dbh = $tagger->dbh

Return underlying DBI handle.

=cut

sub dbh { return shift->{dbh} }

=item $tagger->initialize

Initialize the database with a fresh schema.

=cut

sub initialize {
    my $self = shift;
    my $dbh        = $self->dbh;
    my @statements = $self->_table_definitions;
    my $result     = 1;
    for my $s (@statements) {
	next unless $s =~ /\S/;
	$result &&= $dbh->do($s);
    }
    return $result;
}

=back

=cut

package Bio::DB::Tagger::Iterator;

sub new {
    my $class = shift;
    my $sth   = shift;
    return bless {sth=>$sth},ref $class || $class;
}

sub next_tag {
    my $self  = shift;
    my ($tag) = $self->{sth}->fetchrow_array or return;
    return $tag;
}

sub next { shift->next_tag }


=head1 SEE ALSO

L<Bio::Graphics::Browser>, L<Bio::DB::SeqFeature::Store>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2009 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

1;

__END__
