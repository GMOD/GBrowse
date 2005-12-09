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

my $origdir = cwd;
my $homedir = "$Bin/..";

chdir $homedir or die "couldn't cd to $homedir: $!\n";

foreach (@ARGV) {
  $_ =~ s/^\'(.*)\'$/$1/;
}

my %options = map {split /=/} @ARGV;
my $cgi_target = $options{CGIBIN};

print "Installing gbrowse CGI scripts...\n";

if (! (-e $cgi_target) ) {
    mkpath($cgi_target,0,0777) or die "unable to create $cgi_target directory\n";
}

my $cgidir = "cgi-bin";
chdir $cgidir;
foreach (glob('*')) {
  next if /README/;
  next if /CVS/;
  next if /^[.\#]/;
  next if /~$/;
  next if /\.PLS$/;
  next unless (-f $_);
  my $installfile = Bio::Root::IO->catfile($cgi_target, $_);
  warn "copying $_ to $installfile\n";
  copy($_, $installfile ) or die "unable to copy to $installfile\n";
  my $mode = 0755;
  chmod $mode, $installfile
    or die "unable to make $installfile world executable\n";
}

chdir $origdir or die "couldn't cd to $origdir: $!\n";
!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;

