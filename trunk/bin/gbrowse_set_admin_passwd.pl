#!/usr/bin/perl

use strict;

use FindBin '$Bin';
use lib "$Bin/../lib";
use GBrowse::ConfigData;
use Bio::Graphics::Browser2;
use Bio::Graphics::Browser2::UserDB;
use Getopt::Long;

my ($name,$pass);

my @ORIGINAL_ARGV = @ARGV;

GetOptions('name=s'        => \$name,
	   'password=s'    => \$pass) or die <<EOF;
Usage: $0 [options]

Sets the administrator\'s login name and password. This login name
will have the ability to upload public tracks to GBrowse.

   -name      Login name for admin user [default "admin"].
   -pass      Login password for admin user.

This script uses the "user_account_db" and "admin_account" options
in the currently installed GBrowse.conf configuration file to find 
the appropriate accounts database and the name of the administrator.
If a password is not provided on the command line, you will be 
prompted for it on standard input.

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
my $userdb  = Bio::Graphics::Browser2::UserDB->new($globals);

$name ||= $globals->admin_account;

unless ($pass) {
    print STDERR "New password for $name: ";
    system "stty -echo";
    $pass = <STDIN>;
    chomp($pass);
    print STDERR "\n";

    my $newpass;
    print STDERR "New password for $name (confirm): ";
    $newpass = <STDIN>;
    chomp($newpass);
    print STDERR "\n";
    system "stty echo";
    die "Passwords don't match!\n" unless $pass eq $newpass;
}

$userdb->delete_user_by_username($name);

# this creates a new session for the admin user
my $session     = $globals->session;
my $sessionid   = $session->id;
my $uploadsid   = $session->uploadsid;
$session->flush();

my ($status,undef,$message) = 
    $userdb->do_add_user($name,'admin@nowhere.net','GBrowse Administrator',$pass,$sessionid,'allow admin');
warn $message,"\n";
$userdb->set_confirmed_from_username($name);

warn "Admin account \"$name\" is now registered with sessionid=$sessionid, uploadsid=$uploadsid.\n" if $message =~ /success/i;

exit 0;

__END__
