#!/usr/bin/perl

#$Id: scan_gbrowse.pl,v 1.1 2009-03-05 23:02:59 lstein Exp $

# This script scans the gbrowse at the indicated URL and returns track
# configuration stanzas for all tracks that are marked "discoverable."
# If the --cache <cachetime> argument is present, then results will be
# cached for <cachetime> seconds.

use strict;
use warnings;
use Getopt::Long;
use File::Spec;
use File::Basename 'basename';
use LWP::Simple;

use constant SECS_PER_DAY => 60*60*24;

my $cache_time = 0;

my $USAGE = <<USAGE;
Usage: $0 <gbrowse_url>

Scan the gbrowse2 instance at <gbrowse_url> for discoverable tracks
and create appropriate remote track configuration stanzas suitable for
incorporation into the local gbrowse2 config file.

Options:
       --cache <cachetime>  Cache the results in a temporary file 
                            for cachetime seconds.
USAGE
    ;

GetOptions('cache=i' => \$cache_time) or die $USAGE;
my $url = shift                       or die $USAGE;

my $tmpdir = File::Spec->catfile(File::Spec->tmpdir,'gbrowse_scanner'.'_'.(getpwuid($<))[0]);
unless (-e $tmpdir && -d _) {
    mkdir $tmpdir or die "Couldn't create $tmpdir: $!";
}
(my $fname = $url) =~ s!/!_!g;
my $cache_file = File::Spec->catfile($tmpdir,"$fname.cache");
my $dest_file  = File::Spec->catfile($tmpdir,"$fname.dest");
build_cache($url,$dest_file,$cache_file)
    unless -e $cache_file && ((-M $cache_file) * SECS_PER_DAY)<$cache_time;

open my $fh,'<',$cache_file or die "Couldn't open cache file $cache_file: $!";
print while <$fh>;
close $fh;
exit 0;

sub build_cache {
    my ($url,$dest,$cache) = @_;
    $url  =~ s/\?.+//;            # get rid of any CGI args there already
    my $source = basename($url);

    $url .= '/' unless $url =~ /\/$/;

    my $response = mirror("$url?gbgff=scan",$dest);
    if (is_error($response)) {
	die "Could not scan $url. Status code was $response";
    }
    open my $fh,'<',$dest    or die "Could not open $dest: $!";
    open my $out,'>',$cache  or die "Could not open $cache for writing: $!";

    my ($hostname)    = $url  =~ /^\w+:\/\/([^\/]+)/;
    (my $colon_escape = $url) =~ s/:/\\:/g;

    # paragraph mode to read stanzas
    local $/ = '';
    while (<$fh>) {
	my ($label,$rest)    = /\[([^\]]+)\]\s+(.+)/s;
	my $remote           = "$url?gbgff=1;s=1;t=$label;segment=\$segment";
	chomp($rest);
	print $out <<END;
[${hostname}_${source}_${label}]
remote feature = $remote
category       = Tracks from $colon_escape
$rest

END
    ;
    }
    close $out;
    close $fh;
}

__END__


