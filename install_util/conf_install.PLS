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
                                                                                
print OUT <<"!GROK!THIS!";
$Config{startperl}
use strict;
                                                                                
#Perform installation of gbrowse apache configuration files
                                                                                
use File::Copy;
use Bio::Root::IO;

my \$working_dir = \'$origdir\/\';

!GROK!THIS!

print OUT <<'!NO!SUBS!';
foreach (@ARGV) {
  $_ =~ s/^\'(.*)\'$/$1/;
}

# get configuration stuff from command line
my %options = map {split /=/} @ARGV;
my $dir = "$options{CONF}/gbrowse.conf";

#start the installation...
print "Installing sample configuration files...\n";

if (! (-e $dir)) {
    mkdir($dir,0777) or die "unable to make $dir directory\n";
}

my $localconfdir = $working_dir . "conf";
opendir CONFDIR, $localconfdir or die "unable to opendir $localconfdir\n";
while (my $conffile = readdir(CONFDIR) ) {
  my $localfile = Bio::Root::IO->catfile($localconfdir, $conffile);
  if (-f $localfile) {
    my $installfile = Bio::Root::IO->catfile($dir, $conffile);
    copy_with_substitutions($localfile, $installfile)
      or die "unable to copy to $installfile\n";
  }
}
closedir CONFDIR;

my $plugindir = Bio::Root::IO->catfile($dir, "plugins");
if (! (-e $plugindir)) {
    mkdir($plugindir,0777) or die "unable to mkdir $plugindir\n";
}

my $localplugindir = $working_dir . "/conf/plugins";
opendir PLUGINS, $localplugindir or die "unable to opendir $localplugindir\n";
while (my $pluginfile = readdir(PLUGINS) ) {
    my $localfile = Bio::Root::IO->catfile($localplugindir,$pluginfile);
    if (-f $localfile) {
        my $installfile = Bio::Root::IO->catfile($plugindir, $pluginfile);
	chmod (0666, $installfile);
        copy($localfile, $installfile) 
            or die "$localfile unable to copy to $installfile : $!\n";
	chmod (0444, $installfile);
    } 
}
closedir PLUGINS;

my $langdir = Bio::Root::IO->catfile($dir, 'languages');
if (! (-e $langdir)) {
    mkdir($langdir,0777) or die "unable to mkdir $langdir\n";
}

my $locallangdir = $working_dir . "/conf/languages";
opendir LANGS, $locallangdir or die "unable to opendir $locallangdir\n";
while (my $langfile = readdir(LANGS)) {
    my $localfile = Bio::Root::IO->catfile($locallangdir, $langfile);
    if (-f $localfile) {
        my $installfile = Bio::Root::IO->catfile($langdir, $langfile);
        chmod (0666, $installfile);
        copy($localfile, $installfile) 
            or die "unable to copy to $installfile\n";
        chmod (0444, $installfile);
    }
}
closedir LANGS;


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
!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;
