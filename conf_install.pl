#!/usr/bin/perl -w
use strict;

#Perform installation of gbrowse apache configuration files

use File::Copy;
use Config;

# get configuration stuff from command line
my $dir = $ARGV[0];

my $delim = '/';
if ($Config{'osname'} =~ /win/i) {
    $dir =~ s!\/!\\!g;
    $delim = '\\';    
}

#start the installation...
print "Installing sample configuration files...\n";

if (! (-e $dir)) {
    mkdir($dir,0777) or die "unable to make $dir directory\n";
}

opendir CONFDIR, "conf" or die "unable to opendir conf\n";
while (my $conffile = readdir(CONFDIR) ) {
    if (-f "conf" . $delim . $conffile) {
        if (-f $dir . $delim . $conffile) {
	    print "   Found $conffile in $dir. Skipping...\n";
        } else {
	    copy("conf" . $delim . $conffile, $dir . $delim . $conffile) 
                or die "unable to copy to $dir/$conffile\n";
        }
    }
}
closedir CONFDIR;

my $plugindir = $dir . $delim . "plugins";
if (! (-e $plugindir)) {
    mkdir($plugindir,0777) or die "unable to mkdir $plugindir\n";
}

opendir PLUGINS, "conf/plugins" or die "unable to opendir ./conf/plugins\n";
while (my $pluginfile = readdir(PLUGINS) ) {
    if (-f "./conf/plugins/$pluginfile") {
        copy("conf/plugins" . $delim . $pluginfile, $plugindir . $delim . $pluginfile) 
            or die "unable to copy to $dir/plugins/$pluginfile\n";
    } 
}
closedir PLUGINS;

my $langdir = $dir . $delim . 'languages';
if (! (-e $langdir)) {
    mkdir($langdir,0777) or die "unable to mkdir $langdir\n";
}

opendir LANGS, "conf/languages" or die "unable to opendir ./conf/languages\n";
while (my $langfile = readdir(LANGS)) {
    if (-f "./conf/languages/$langfile") {
        copy("conf/languages" . $delim . $langfile, $langdir . $delim . $langfile) 
            or die "unable to copy to $dir/languages/$langfile\n";
    }
}
closedir LANGS;

