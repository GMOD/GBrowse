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
use File::Basename qw( basename fileparse );
use Carp 'croak';
use IO::Dir;
use File::Path 'mkpath';
use Bio::Root::IO;
use Cwd;
use FindBin '$Bin';

use lib 'install_util';
use InstallUtil;
use vars qw(%options);

my $origdir = cwd;
my $homedir = "$Bin/..";

chdir $homedir or die "couldn't cd to $homedir: $!\n";

foreach (@ARGV) {
  $_ =~ s/^\'(.*)\'$/$1/;
}

my %options = map {split /=/} @ARGV;
my $ht_target = "$options{HTDOCS}/gbrowse";

if (! (-e $ht_target) ) {
    mkpath($ht_target,0,0777) or die "unable to make $ht_target directory\n";
}

print "Installing temporary directory...\n";

my $tmpdir = Bio::Root::IO->catfile($ht_target, "tmp");
if (! (-e $tmpdir) ) {
    print "Making $tmpdir...\n";
    mkdir($tmpdir,0777) or die "unable to make $tmpdir\n";
    chmod 0777, $tmpdir or die "unable to make $tmpdir world writable\n";
}

print "Installing htdocs...\n";
copy_tree(source => "./htdocs", target => $ht_target, substitute => 1);

print "Installing sample_data...\n";
copy_tree(source => "./sample_data", target => $ht_target, substitute => 1);

print "Installing contrib...\n";
copy_tree(source => "./contrib", target => $ht_target, substitute => 1);

print "Installing tutorial...\n";
copy_tree(source => "./docs/tutorial", target => $ht_target, substitute => 1);

print "Installing documentation...\n";

#this need to be replaced with:
#  a pod2html dohicky (it can create the html in the htdocs dir directly)
#  a wanted subroutine to do File::Find's work
#  also need to modify gbrowse/index.html
copy_with_substitutions('./DISCLAIMER',$ht_target);

#installing pod docs
my $docdir = Bio::Root::IO->catfile($ht_target, "docs");
if (! (-e $docdir) ) {
    mkdir($docdir,0777) or die "unable to make $docdir\n";
}
my $poddir = Bio::Root::IO->catfile($docdir, "pod");
if (! (-e $poddir) ) {
    mkdir($poddir,0777) or die "unable to make $poddir\n";
}

my $localpoddir = "docs/pod/";
my @localpodfiles = glob($localpoddir . "*.pod"); 
for my $localfile ( @localpodfiles ) {
     my ($name,undef,undef) = fileparse($localfile, "\.pod");
     my $installfile = Bio::Root::IO->catfile("$ht_target/docs/pod","$name.html"); 
     system("pod2html", "--infile=$localfile",
                        "--outfile=$installfile",
                        "--htmlroot=/gbrowse",
                        "--htmldir=$ht_target ",
                        "--podpath=$localpoddir",
                        "--title=$name");
}
#get rid of pod2html junk
unlink './pod2htmi.x~~';
unlink './pod2htmd.x~~';

chmod 0777,glob("$ht_target/databases/*");

print "\n\n#############################################################################\n";
print "GBrowse is now installed.  Read INSTALL for further setup instructions.\n";
print "Go to http://localhost/gbrowse/ for the online tutorial and reference manual.\n";
print "#############################################################################\n";

chdir $origdir or die "couldn't cd to $origdir: $!\n";
exit 0;

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;

