#!/usr/bin/perl

use strict;

use FindBin '$Bin';
use lib "$Bin/../lib";
use GBrowse::ConfigData;
use Bio::Graphics::Browser2;
use Bio::Graphics::Browser2::UserDB;
use Getopt::Long;

my ($name,$pass,$fullname,$email);

my @ORIGINAL_ARGV = @ARGV;

use constant USAGE => <<END;
Usage: $0 [-pass password -fullname name -email address] user

Creates a user account with the desired username and
password. If the account already exists, then the password
is reset.

   -pass      Login password for user.
   -fullname  User full name
   -email     User email address

This script uses the "user_account_db"  option in the currently 
installed GBrowse.conf configuration file to find 
the appropriate accounts database. If a password is not provided 
on the command line, you will be prompted for it on standard input.

WARNING: This script should be run as the web server user using
"sudo -u www-data $0". If it detects that it is not being run as this
user, it will attempt to sudo itself for you.
END

GetOptions('password=s'    => \$pass,
	   'fullname=s'    => \$fullname,
	   'email-s'       => \$email,
    ) or die USAGE;

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

$name=shift or die "Please provide a username. Run $0 --help for help\n";

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
$fullname ||= prompt("Enter user's full name (optional)");
$email    ||= prompt("Enter user's email address (optional)");

$fullname ||= $name;
$email    ||= "$name\@nowhere.net";

my $uid = $userdb->userid_from_username($name);

unless ($uid) {
# this creates a new session for the admin user
    my $session     = $globals->session;

    my $sessionid   = $session->id;
    my $uploadsid   = $session->uploadsid;
 
    $session->flush();

    my ($status,undef,$message) = 
	$userdb->do_add_user($name,$email,$fullname,$pass,$sessionid);
    warn $message,"\n";
    $userdb->set_confirmed_from_username($name);
    warn "Account \"$name\": now registered with sessionid=$sessionid, uploadsid=$uploadsid.\n" if $message =~ /success/i;
} else {
    $userdb->set_password($uid,$pass);
    warn "Account \"$name\": password successfully set.\n";
}

exit 0;

sub prompt {
    my $msg = shift;
    print STDERR "$msg: ";
    my $response = <STDIN>;
    chomp $response;
    return $response;
}

__END__
