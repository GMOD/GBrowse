#!/usr/bin/perl -w
use strict;

#Perform installation of gbrowse apache configuration files

use File::Basename;
use File::Copy;
use Config;


# determine platform for filepath parsing
my $platform;
if ($Config{'osname'} =~ /win/i) {
    $platform = 'MSWin32';
} else {
    $platform = 'linux';
}
fileparse_set_fstype($platform);


# get configuration stuff from command line
my $CONF = $ARGV[0];
my $Bin  = $ARGV[1];

#start the installation...
print "Installing sample configuration files...\n";
my $dir = "$CONF/gbrowse.conf";

if (! (-e $dir)) {
    mkdir $dir or die "unable to make $dir directory\n";
}

opendir CONFDIR, "./conf" or die "unable to opendir ./conf\n";
while (my $conffile = readdir(CONFDIR) ) {
    my $basename = basename($conffile, []); 
    if (-f $conffile) {
        if (-f "$dir/$basename") {
	    print "   Found $basename in $dir. Skipping...\n";
        } else {
	    copy($conffile, "$dir/$basename") or die "unable to copy $conffile\n";
        }
    }
}
closedir CONFDIR;

if (! (-e "$dir/plugins")) {
    mkdir "$dir/plugins" or die "unable to mkdir $dir/plugins\n";
}

opendir PLUGINS, "./conf/plugins" or die "unable to opendir ./conf/plugins\n";
while (my $pluginfile = readdir(PLUGINS) ) {
    my $basename = basename($pluginfile, []);
    if (-f $pluginfile) {
        copy($pluginfile, "$dir/plugins/$basename") or die "unable to copy $pluginfile\n";
    } 
}
closedir PLUGINS;

if (! (-e "$dir/languages")) {
    mkdir "$dir/languages" or die "unable to mkdir $dir/languages\n";
}

opendir LANGDIR, "./conf/languages" or die "unable to opendir ./conf/languages\n";
while (my $langfile = readdir(LANGDIR)) {
    my $basename = basename($langfile, []);
    if (-f $langfile) {
        copy($langfile, "$dir/languages/$basename") or die "unable to copy $langfile\n";
    }
}
closedir LANGDIR;

