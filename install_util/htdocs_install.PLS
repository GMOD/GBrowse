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

my $origdir = cwd;
my $homedir = "$Bin/..";
                                                                                
chdir $homedir or die "couldn't cd to $homedir: $!\n";
                                                                                
foreach (@ARGV) {
  $_ =~ s/^\'(.*)\'$/$1/;
}

my %options = map {split /=/} @ARGV;
my $ht_target = "$options{HTDOCS}/gbrowse";

print "Installing stylesheet and images...\n";

if (! (-e $ht_target) ) {
    mkpath($ht_target,0,0777) or die "unable to make $ht_target directory\n";
}

my $localhtdocsdir = "htdocs";
opendir HTDOCS, $localhtdocsdir or die "unable to opendir $localhtdocsdir\n";
while (my $file = readdir(HTDOCS) ) {
    my $localfile = Bio::Root::IO->catfile($localhtdocsdir, $file);
    if (-f $localfile) {
        my $installfile = Bio::Root::IO->catfile($ht_target, $file);
	chmod (0666, $installfile);
        copy_with_substitutions($localfile, $installfile)
           or die "unable to copy to $installfile\n";
	chmod (0444, $installfile);
    }
}
closedir HTDOCS; 

my $imagedir  = Bio::Root::IO->catfile($ht_target, "images");
my $buttondir = Bio::Root::IO->catfile($imagedir, "buttons");
if (! (-e $imagedir) ) {
    print "Making $imagedir...\n";
    mkdir($imagedir,0777) or die "unable to make $imagedir\n";
}
if (! (-e $buttondir) ) {
    print "Making $buttondir...\n";
    mkdir($buttondir,0777) or die "unable to make $buttondir\n";
}

my $localbuttondir = "htdocs/images/buttons";
opendir BUTTONS, $localbuttondir or die "unable to open $localbuttondir\n";
while (my $file = readdir(BUTTONS) ) {
    my $localfile = Bio::Root::IO->catfile($localbuttondir,$file);
    if (-f $localfile) {
        my $installfile = Bio::Root::IO->catfile($buttondir, $file);
	chmod (0666, $installfile);
        copy_with_substitutions($localfile, $installfile) 
            or die "unable to copy to $installfile\n"; 
	chmod (0444, $installfile);
    }
}
closedir BUTTONS;

my $helpdir = Bio::Root::IO->catfile($imagedir, "help");
if (! (-e $helpdir) ) {
    print "Making $helpdir...\n";
    mkdir($helpdir,0777) or die "unable to make $helpdir\n";
}

my $localhelpdir = "htdocs/images/help";
opendir HELP, $localhelpdir or die "unable to open $localhelpdir\n";
while (my $file = readdir(HELP) ) {
    my $localfile = Bio::Root::IO->catfile($localhelpdir, $file);
    if (-f "./htdocs/images/help/$file") {
        my $installfile = Bio::Root::IO->catfile($helpdir, $file);
	chmod (0666, $installfile);
        copy_with_substitutions($localfile, $installfile) 
            or die "unable to copy to $installfile\n";
	chmod (0444, $installfile);
    }
}
closedir HELP;

print "Installing temporary directory...\n";

my $tmpdir = Bio::Root::IO->catfile($ht_target, "tmp");
if (! (-e $tmpdir) ) {
    print "Making $tmpdir...\n";
    mkdir($tmpdir,0777) or die "unable to make $tmpdir\n";
    chmod 0777, $tmpdir or die "unable to make $tmpdir world writable\n";
}

print "Installing documentation...\n";
#this need to be replaced with:
#  a pod2html dohicky (it can create the html in the htdocs dir directly)
#  a wanted subroutine to do File::Find's work
#  also need to modify gbrowse/index.html
for my $localfile ("DISCLAIMER") {
  my $installfile = Bio::Root::IO->catfile($ht_target,basename($localfile));
  chmod (0666, $installfile);
  copy_with_substitutions($localfile,$installfile);
  chmod(0444,$installfile);
}

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

print "Installing tutorial...\n";
copy_tree("./docs/tutorial",$ht_target);

print "Installing sample_data...\n";
copy_tree("./sample_data",$ht_target);

print "Installing contrib...\n";
copy_tree("./contrib",$ht_target);

print "Installing sample data files...\n";
copy_tree("./htdocs/databases","$ht_target");
chmod 0777,glob("$ht_target/databases/*");

print "\n\n#############################################################################\n";
print "GBrowse is now installed.  Read INSTALL for further setup instructions.\n";
print "Go to http://localhost/gbrowse/ for the online tutorial and reference manual.\n";
print "#############################################################################\n";

chdir $origdir or die "couldn't cd to $origdir: $!\n";
exit 0;

sub copy_tree {
  my ($src,$dest) = @_;
  if (-f $src) {
    copy_with_substitutions($src,$dest) or die "copy_with_substitutions($src,$dest): $!";
    return 1;
  }
  croak "$src doesn't exist" unless -e $src;
  croak "Usage: copy_tree(\$src,\$dest).  Can't copy a directory into a file or vice versa" 
    unless -d $src && -d $dest;
  croak "Can't read from $src" unless -r $src;
  croak "Can't write to $dest" unless -w $dest;

  my $tgt = basename($src);

  # create the dest if it doesn't exist
  mkdir ("$dest/$tgt",0777) or die "mkdir($dest/$tgt): $!" unless -d "$dest/$tgt";
  my $d = IO::Dir->new($src) or die "opendir($src): $!";
  while (my $item = $d->read) {
    # bunches of things to skip
    next if $item eq 'CVS';
    next if $item =~ /^\./;
    next if $item =~ /~$/;
    next if $item =~ /^\#/;
    if (-f "$src/$item") {
      copy_with_substitutions("$src/$item","$dest/$tgt") or die "copy_with_substitutions('$src/$item','$dest/$tgt'): $!";
    } elsif (-d "$src/$item") {
      copy_tree("$src/$item","$dest/$tgt");
    }
  }
  1;
}

sub copy_with_substitutions {
  my ($localfile,$install_file) = @_;
  open (IN,$localfile) or warn "Couldn't open $localfile: $!";
  my $basename = basename($localfile);
  my $dest = -d $install_file ? "$install_file/$basename" : $install_file;
  open (OUT,">$dest") or die "Couldn't open $install_file for writing: $!";
  if (-T IN) {
    while (<IN>) {
      s/\$(\w+)/$options{$1}||"\$$1"/eg;
      print OUT;
    }
  }
  else {
    binmode OUT;
    my $buffer;
    print OUT $buffer while read(IN,$buffer,5000);
  }
  close OUT;
  close IN;
}

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;

