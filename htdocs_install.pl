#!/usr/bin/perl -w
use strict;
use File::Copy;
use Bio::Root::IO;

my $ht_target = $ARGV[0]; #target directory

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
        copy($localfile, $installfile)
           or die "unable to copy to $installfile\n";
	chmod (0644, $installfile);
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
        copy($localfile, $installfile) 
            or die "unable to copy to $installfile\n"; 
	chmod (0644, $installfile);
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
        copy($localfile, $installfile) 
            or die "unable to copy to $installfile\n";
	chmod (0644, $installfile);
    }
}
closedir HELP;

my $tmpdir = Bio::Root::IO->catfile($ht_target, "tmp");
if (! (-e $tmpdir) ) {
    print "Making $tmpdir...\n";
    mkdir($tmpdir,0777) or die "unable to make $tmpdir\n";
#  this appears irrelevent now
#    my $mode = 0777;
#    chmod $mode, $tmpdir or die "unable to make $tmpdir world writable\n";
}

