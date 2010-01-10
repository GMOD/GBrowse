#!/usr/bin/perl

use strict;

use Getopt::Long;
use DBI;

my ($dsn,$admin,$pprompt);

GetOptions('dsn=s'   => \$dsn,
           'admin=s' => \$admin,
           'p'       => \$pprompt) or die <<EOF;
Usage: $0

Initializes an empty GBrowse user accounts database. Options:

   -dsn       DBI-style database source identifier
                 [default "DBI:mysql:gbrowse_login;user=gbrowse;password=gbrowse"]
   -admin     DB admin user and password in format "user:password" [default "root:<empty>"]
   -p         Prompt for password

Currently mysql and SQLite databases are supported. When creating a mysql database
you must provide the -admin option to specify a user and password that has database create
privileges on the server.

When creating a SQLite database, the script will use the -admin option to set the user and
group ownership of the created database. The web user must have read/write privileges to this 
database.
EOF
    ;

$dsn         ||= 'DBI:mysql:gbrowse_login;user=gbrowse;password=gbrowse';

my ($admin_user,$admin_pass) = split ':',$admin;
$admin_user ||= 'root';
$admin_pass ||= '';

if ($pprompt) {
    print STDERR "DB Admin password: ";
    $admin_pass = <STDIN>;
    chomp($admin_pass);
    print STDERR "\n";
}

my ($db) =~ $dsn =~ /DBI:[^:]+:([^;]+)/;
print STDERR "Warning: This will (re)initialize the database named $db, erasing all\n";
print STDERR "data that may have been there. Press \"Y\" to continue: ";

exit 0 unless <STDIN> =~ /^[Yy]/;

# Try to create the indicated database
if ($dsn =~ /^DBI:mysql:([^;]+)/) {
    my $login_db  = $1;
    my ($db_user) = $dsn =~ /user=([^;]+)/;
    my ($db_pass) = $dsn =~ /password=([^;]+)/;

    my ($host) = $dsn =~ /host=([^;]+)/;
    my ($port) = $dsn =~ /port=([^;]+)/;
    my $admin_dsn = "DBI:mysql:mysql";
    $admin_dsn   .= ";hostname=$host"        if $host;
    $admin_dsn   .= ";port=$port"            if $port;
    $admin_dsn   .= ";user=$admin_user"      if $admin_user;
    $admin_dsn   .= ";password=$admin_pass"  if $admin_pass;

    print STDERR "Creating $dsn\n";
    my $dbh    = DBI->connect($admin_dsn)
	or die DBI->errstr;
    $dbh->do("DROP DATABASE IF EXISTS $login_db");
    $dbh->do("CREATE DATABASE $login_db") or die DBI->errstr;
    $dbh->do("GRANT ALL PRIVILEGES on $login_db.* TO '$db_user'\@'%' IDENTIFIED BY '$db_pass' WITH GRANT OPTION") or die DBI->errstr;
    $dbh->disconnect;

    $dbh = DBI->connect($dsn) or die DBI->errstr;

    print STDERR "Loading schema...\n";
    load_schema($dbh,'mysql');
    print STDERR "Done.\n";
	
}
elsif ($dsn =~ /^DBI:SQLite:/) {
    print STDERR "Creating $dsn\n";
    my $dbh = DBI->connect($dsn) or die DBI->errstr;
    print STDERR "Loading schema...\n";
    load_schema($dbh,'sqlite');
    print STDERR "Using sudo to set ownership to $admin_user:$admin_pass. You may be prompted for your login password now.\n";
    my ($path) = $dsn =~ /dbname=([^;]+)/;
    unless ($path) {
	($path) = $dsn =~ /DBI:SQLite:([^;]+)/;
    }
    die "Couldn't figure out location of database index from $dsn" unless $path;
    system "sudo chown $admin_user $path";
    system "sudo chgrp $admin_pass $path";
    print STDERR "Done.\n";
    
}

exit 0;

sub load_schema {
    my ($dbh,$driver) = @_;
    while (<DATA>) {
	chomp;
	last if /^\*\*\s*$driver/i;
    }
    local $/ = ';';
    while (<DATA>) {
	chomp;
	last if /\s*\*\*/;
	next unless /\S/;
	$dbh->do($_) or die $dbh->errstr;
    }
}

__END__

** mysql **
DROP TABLE IF EXISTS users;
CREATE TABLE users (
    userid        varchar(32) not null UNIQUE key,
    username      varchar(32) not null PRIMARY key,
    email         varchar(64) not null UNIQUE key,
    pass          varchar(32) not null,
    remember          boolean not null,
    openid_only       boolean not null,
    confirmed         boolean not null,
    cnfrm_code    varchar(32) not null,
    last_login      timestamp not null,
    created          datetime not null
) ENGINE=InnoDB;

DROP TABLE IF EXISTS openid_users;
CREATE TABLE openid_users (
    userid        varchar(32) not null,
    username      varchar(32) not null,
    openid_url   varchar(128) not null PRIMARY key
) ENGINE=InnoDB;

** SQLite **
DROP TABLE IF EXISTS users;
CREATE TABLE users (
    userid        varchar(32) not null UNIQUE,
    username      varchar(32) not null PRIMARY key,
    email         varchar(64) not null UNIQUE,
    pass          varchar(32) not null,
    remember          boolean not null,
    openid_only       boolean not null,
    confirmed         boolean not null,
    cnfrm_code    varchar(32) not null,
    last_login      timestamp not null,
    created          datetime not null
);

DROP TABLE IF EXISTS openid_users;
CREATE TABLE openid_users (
    userid        varchar(32) not null,
    username      varchar(32) not null,
    openid_url   varchar(128) not null PRIMARY key
);

