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
use constant DEBUG => 0;

my $origdir = cwd;
my $homedir = "$Bin/..";

chdir $homedir or die "couldn't cd to $homedir: $!\n";

foreach (@ARGV) {
  $_ =~ s/^\'(.*)\'$/$1/;
}

# get configuration stuff from command line
my %options = map {split /=/} @ARGV;
my $dir = "$options{CONF}/gbrowse.conf";

#start the installation...
print "Installing sample configuration files...\n";

if (! (-e $dir)) {
    mkpath($dir,0,0777) or die "unable to make $dir directory\n";
}

installdir( source => "conf" , target => "$dir" , recurse => 1 );

sub installdir {
  my(%arg) = @_;
  my $source  = $arg{source};
  my $target  = $arg{target};
  my $recurse = $arg{recurse};

  if (! (-e $target)) {
    mkdir($target,0777) or die "unable to mkdir $target: $!";
  }

  opendir(my $SOURCE, $source) or die "unable to opendir('$source'): $!";
  while(my $file = readdir($SOURCE)){
    next if $file =~ /\.PMS$/;

    my $sourcefile = Bio::Root::IO->catfile($source,$file);
    my $targetfile = Bio::Root::IO->catfile($target,$file);

    if(-f $sourcefile){
      chmod(0666,$targetfile);
#      copy($sourcefile,$targetfile) or die "unable to write to $targetfile: $!";
      copy_with_substitutions($sourcefile,$targetfile) or die "unable to write to $targetfile: $!";
      print STDERR "    file $sourcefile -> $targetfile\n" if DEBUG;
      chmod(0444,$targetfile);
    } elsif(-d $sourcefile && $recurse){
      next if $file eq '.' or $file eq '..' or $file eq 'CVS';
      print STDERR "directory $sourcefile -> $targetfile\n" if DEBUG;
      installdir(source => $sourcefile, target => $targetfile, recurse => 1);
    }
  }
  closedir($SOURCE);
}

sub copy_with_substitutions {
  my ($localfile,$install_file) = @_;
  open (IN,$localfile) or die "Couldn't open $localfile: $!";
  open (OUT,">$install_file") or die "Couldn't open $install_file for writing: $!";
  while (<IN>) {
    s/\$(\w+)/$options{$1}||"\$$1"/eg;
    print OUT;
  }
  close OUT;
  close IN;
}

chdir $origdir or die "couldn't cd to $origdir: $!\n";
!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;
