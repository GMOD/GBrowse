#!perl
use Config;
use File::Basename qw(&basename &dirname);
use Cwd;

$origdir = cwd;
chdir dirname($0);
$file = basename($0, '.PL','.PLS');
$file .= $^O eq 'VMS' ? '.com' : '.pl';

open OUT,">$file" or die "Can't create $file: $!";

print "Extracting $file (with variable substitutions)\n";

print OUT "$Config{startperl}\n";

print OUT <<'!NO!SUBS!';
use strict;
use File::Copy;
use Bio::Root::IO;
use File::Path 'mkpath';
use Cwd;
use FindBin '$Bin';

use lib 'install_util';
use InstallUtil;
use vars qw(%options);

my $origdir = cwd;
my $homedir = "$Bin/..";

use constant DEBUG => 0;

chdir $homedir or die "couldn't cd to $homedir: $!\n";

foreach (@ARGV) {
  $_ =~ s/^\'(.*)\'$/$1/;
}

# get configuration stuff from command line
my %options = map {split /=/} @ARGV;
my $dir = "$options{CONF}";

#start the installation...
print "Installing sample configuration files...\n";

if (! (-e $dir)) {
    mkpath($dir,0,0777) or die "unable to make $dir directory\n";
}

move("conf","gbrowse.conf");
copy_tree( source => "gbrowse.conf" , target => "$dir");
move("gbrowse.conf","conf");

chdir $origdir or die "couldn't cd to $origdir: $!\n";
!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;
