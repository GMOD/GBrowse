#!/usr/bin/perl -w
use strict;
use File::Basename qw( basename fileparse );
use Carp 'croak';
use IO::Dir;
use Bio::Root::IO;

my %options = map {split /=/} @ARGV;
my $ht_target = "$options{HTDOCS}/gbrowse";

# use Bio::Root::IO instead
#my $delim = '/';
#if ($Config{'osname'} =~ /win/i && $Config{'osname'} !~ /darwin/i ) {
#    $ht_target =~ s!\/!\\!g;
#    $delim = '\\';
#}


print "Installing stylesheet and images...\n";

if (! (-e $ht_target) ) {
    mkdir($ht_target,0777) or die "unable to make $ht_target directory\n";
}

opendir HTDOCS, "htdocs" or die "unable to opendir htdocs\n";
while (my $file = readdir(HTDOCS) ) {
    my $localfile = Bio::Root::IO->catfile('htdocs', $file);
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

opendir BUTTONS, "htdocs/images/buttons" or die "unable to open ./htdocs/images/buttons\n";
while (my $file = readdir(BUTTONS) ) {
    my $localfile = Bio::Root::IO->catfile('htdocs/images/buttons',$file);
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

opendir HELP, "htdocs/images/help" or die "unable to open htdocs/images/help\n";
while (my $file = readdir(HELP) ) {
    my $localfile = Bio::Root::IO->catfile('htdocs/images/help', $file);
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
for my $localfile (qw(./DISCLAIMER)) {
  my $installfile = Bio::Root::IO->catfile($ht_target,basename($localfile));
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

for my $localfile ( qw(./docs/pod/CONFIGURE_HOWTO.pod
                       ./docs/pod/ORACLE_AND_BIOSQL.pod
                       ./docs/pod/README-berkeley-gadfly.pod
                       ./docs/pod/PLUGINS_HOWTO.pod
                       ./docs/pod/README-gff-files.pod
                       ./docs/pod/INSTALL.pod ) ) {
     my ($name,undef,undef) = fileparse($localfile, "\.pod");
     my $installfile = Bio::Root::IO->catfile("$ht_target/docs/pod","$name.html"); 
     system("pod2html", "--infile=$localfile",
                        "--outfile=$installfile",
                       # "--outfile=$name.html",
                        "--htmlroot=/gbrowse",
                        "--htmldir=$ht_target ",
                        "--podpath=./docs/pod",
                        "--title=$name");
}


print "Installing tutorial...\n";
copy_tree('./docs/tutorial',$ht_target);

print "Installing sample_data...\n";
copy_tree('./sample_data',$ht_target);

print "Installing contrib...\n";
copy_tree('./contrib',$ht_target);

print "Installing sample data files...\n";
copy_tree('./htdocs/databases',"$ht_target");
chmod 0777,glob("$ht_target/databases/*");

print "\n\n#############################################################################\n";
print "GBrowse is now installed.  Read INSTALL for further setup instructions.\n";
print "Go to http://your.host/gbrowse/ for the online tutorial and reference manual.\n";
print "#############################################################################\n";

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
  open (IN,$localfile) or die "Couldn't open $localfile: $!";
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
    my $buffer;
    print OUT $buffer while read(IN,$buffer,5000);
  }
  close OUT;
  close IN;
}
