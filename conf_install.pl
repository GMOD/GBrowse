#!/usr/bin/perl
use strict;
use warnings;

#Perform installation of gbrowse apache configuration files

use File::Copy;

# get configuration stuff from command line
my $CONF = $ARGV[0];

#start the installation...
print "Installing sample configuration files...\n";
my $dir = "$CONF/gbrowse.conf";

if (! (-e $dir)) {
    mkdir $dir or die "unable to make $dir directory\n";
}

opendir CONFDIR, "./conf" or die "unable to opendir ./conf\n";
while (my $conffile = readdir(CONFDIR) ) {
    if (-f "./conf/$conffile") {
        if (-f "$dir/$conffile") {
	    print "   Found $conffile in $dir. Skipping...\n";
        } else {
	    copy("./conf/$conffile", "$dir/$conffile") or die "unable to copy to$dir/$conffile\n";
        }
    }
}
closedir CONFDIR;

if (! (-e "$dir/plugins")) {
    mkdir "$dir/plugins" or die "unable to mkdir $dir/plugins\n";
}

opendir PLUGINS, "./conf/plugins" or die "unable to opendir ./conf/plugins\n";
while (my $pluginfile = readdir(PLUGINS) ) {
    if (-f "./conf/plugin/$pluginfile") {
        copy($pluginfile, "$dir/plugins/$pluginfile") or die "unable to copy to $dir/plugins/$pluginfile\n";
    } 
}
closedir PLUGINS;

if (! (-e "$dir/languages")) {
    mkdir "$dir/languages" or die "unable to mkdir $dir/languages\n";
}

opendir LANGDIR, "./conf/languages" or die "unable to opendir ./conf/languages\n";
while (my $langfile = readdir(LANGDIR)) {
    if (-f "./conf/languages/$langfile") {
        copy($langfile, "$dir/languages/$langfile") or die "unable to copy to $dir/languages/$langfile\n";
    }
}
closedir LANGDIR;

