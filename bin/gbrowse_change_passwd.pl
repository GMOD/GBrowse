#!/usr/bin/perl

use strict;

use FindBin '$Bin';
use lib "$Bin/../lib";
use GBrowse::ConfigData;
use Bio::Graphics::Browser2;
use Bio::Graphics::Browser2::UserDB;
use Getopt::Long;

my @ORIGINAL_ARGV = @ARGV;

use constant USAGE => <<END;
Usage: $0 user [pass]

Changes the password for the indicated user.
If no password is provided on the command line, then
a new random password will be chosen.

This script uses the "user_account_db"  option in the currently 
installed GBrowse.conf configuration file to find 
the appropriate accounts database.
END
    ;
if ($ARGV[0] =~ /^--?h/) {
    die USAGE;
}

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

my $name = shift or die "Please provide a username. Run $0 --help for help\n";
my $pass = shift || get_random_password();

my $uid = $userdb->userid_from_username($name);
$uid || die "unknown user: $name\n";

$userdb->set_password($uid,$pass);
warn "Account \"$name\": password successfully set to $pass.\n";

exit 0;

sub get_random_password {
    my $p = '';
    my @a = ('a'..'z','A'..'Z',0..9);
    for (1..10) {
	$p .= $a[rand @a];
    }
    return $p;
}

__END__
