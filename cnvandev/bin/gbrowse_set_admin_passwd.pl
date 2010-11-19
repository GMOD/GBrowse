#!/usr/bin/perl

use strict;

use FindBin '$Bin';
use lib "$Bin/../lib";
use GBrowse::ConfigData;
use Bio::Graphics::Browser2;
use Getopt::Long;
use DBI;
use Digest::SHA qw(sha1);

my ($dsn,$name,$pass);

my @ORIGINAL_ARGV = @ARGV;

GetOptions('dsn=s'         => \$dsn,
	   'name=s'        => \$name,
	   'password=s'    => \$pass) or die <<EOF;
Usage: $0 [options]

Sets the administrator\'s login name and password. This login name
will have the ability to upload public tracks to GBrowse.

   -dsn       DBI-style database source identifier
                 [default "DBI:mysql:gbrowse_login;user=gbrowse;password=gbrowse"]
   -name      Login name for admin user [default "admin"].
   -pass      Login password for admin user.

Called without options, this script uses the values provided in the
installed GBrowse.conf file using the options "user_account_db" and
"admin_account". If the password is not provided on the command line,
you will be prompted for it on standard input.

WARNING: This script should be run as the web server user using
"sudo -u www-data $0". If it detects that it is not being run as this
user, it will attempt to sudo itself for you.
EOF
 ;

my $wwwuser = GBrowse::ConfigData->config('wwwuser');
my $uid     = (getpwnam($wwwuser))[2];
unless ($uid == $<) {
    print STDERR "Not running as $wwwuser. Trying to use sudo to remedy. You may be asked for your login password.\n";
    my @args = ('sudo','-u',$wwwuser,$0, @ORIGINAL_ARGV);
    exec @args;
    exit 0;
}

my $globals = Bio::Graphics::Browser2->open_globals or die "Couldn't open GBrowse.conf";

$dsn         ||= $globals->user_account_db;
$name        ||= $globals->admin_account;

unless ($pass) {
    print STDERR "New password for $name: ";
    system "stty -echo";
    $pass = <STDIN>;
    chomp($pass);
    print STDERR "\n";

    my $newpass;
    print STDERR "Confirm password for $name: ";
    $newpass = <STDIN>;
    chomp($newpass);
    print STDERR "\n";
    system "stty echo";
    die "Passwords don't match!\n" unless $pass eq $newpass;
}

my $dbh = DBI->connect($dsn) or die DBI->errstr;
my $session     = $globals->session;
my $userid      = $session->id;
$session->flush();

warn "admin userid set to $userid\n";
my $email       = 'nobody@nowhere.net';
my $hash_pass   = sha1($pass);
my $remember    = 1;
my $openid_only = 0;
my $confirmed   = 1;
my $cnfrm_code  = create_key(32);
my $now         = $dsn =~ /sqlite/i ? "datetime('now','localtime')" : 'now()';
$dbh->do("DELETE FROM users WHERE username=?",{},$name);
my $sth = $dbh->prepare("INSERT INTO users (userid,username,email,pass,remember,openid_only,confirmed,cnfrm_code,last_login,created) VALUES(?,?,?,?,?,?,?,?,$now,$now)") or die $dbh->errstr;
$sth->execute($userid,$name,$email,$hash_pass,$remember,$openid_only,$confirmed,$cnfrm_code) or die $dbh->errstr;

warn "Admin account \"$name\" is now registered.\n";

exit 0;

sub create_key {
    my $val = shift;
    my $key;
    my @char=('a'..'z','A'..'Z','0'..'9','_');
    foreach (1..$val) {$key.=$char[rand @char];}
    return $key;
}

__END__
