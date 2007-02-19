#!/usr/bin/perl -w
#
# BUGS:
#   - Serious errors recalling GD::Font primitives... WHY?
#
# TODO:
#   - This is extremely inefficient in many ways:
#       - constantly opening/closing DB connections (should use mod_perl to
#         instantiate ONE db-connected object like BatchTiledImage or
#         TiledImage, and just keep it alive across many queries)
#       - fetching tiles 1-by-1 instead of tile ranges (should use
#         BatchTiledImage)
#   - Any security holes?  (YES if you run in debug mode, otherwise dunno...)
#-------------------------------------------------------------------------------

use strict;
use CGI qw/:standard/;
use Fcntl qw(:DEFAULT :flock);

# REPLACE THE FOLLOWING BY PATH TO YOUR 'Generic-Genome-Browser/ajax/server/' dir!
#use lib '.';
use TiledImage;

# set to 1 for debugging mode (prints trace of what's going on to HTML instead of
# returning image - but NOTE that some stuff will be 'warn'ed to the Apache log)
my $d = 0;

my $document_root = $ENV{'DOCUMENT_ROOT'} or die "Can't get document root";
my $request_uri = $ENV{'REQUEST_URI'} or die "Can't get requested URI";

die "Illegal tile URI requested ($request_uri)"
  unless $request_uri =~
    /^(\/.+)\/+([^\/]+)\/+([^\/]+)\/+([^\/]+)\/+(ruler)?tile(\d+)\.png$/;

my ($root, $landmark, $track, $zoom, $tilenum) = ($1, $2, $3, $4, $6);
my $tile = join ('/', $document_root, $request_uri);

if ($d) {
  print header ('text/html');
  print '<b>Environment:</b><br>',
        join ("<br>", map { $_ . '=' . $ENV{$_} } sort keys %ENV),
	'<hr>';
  print "requested URI: $request_uri <br>";
  print join ('<br>', $tile, $landmark, $track, $zoom, $tilenum), '<hr>';
}

# make sure all the dirs that we need are there
my $current_dir = $document_root;
foreach my $subdir ($root, $landmark, $track, $zoom)
{
  $current_dir = join ('/', $current_dir, $subdir);
  mkdir $current_dir or
    die "Can't find or make $current_dir" unless (-e $current_dir);
}

# restore tiled image object
my $tiledimage_name = join ('__', $landmark, $track, $zoom);

print "trying to create tile $tile (tiledimage_name = $tiledimage_name)<br>" if $d;

my $tiledImage = new TiledImage (
				 #-verbose => 2,  #D!!!
				 -primdb => 'DBI:mysql:gdtile',  # TODO: this should be figured out automatically!
				 -tiledimage_name => $tiledimage_name
				);

print "total dimensions: ", $tiledImage->width, 'x', $tiledImage->height, '<br>' if $d;

# the PROPER WAY
my $gd = $tiledImage->renderTile ($tilenum * 1000, 0, 1000, $tiledImage->height);  # TODO: tile width should not be hardcoded in!

# the only way that works (do this in slices which don't invoke GD::Font)
#my $gd = $tiledImage->renderTile (550, 0, 10, $tiledImage->height);

exit 0 if $d;

# return tile
print header ('image/png');
my $png = $gd->png;
print $png;

# output tile to file
open (TILE, ">$tile") or die ("$0: $!");
flock (TILE, LOCK_SH) or die ("$0: $!");
print TILE $png;
flock (TILE, LOCK_UN);
close (TILE);

exit 0;
