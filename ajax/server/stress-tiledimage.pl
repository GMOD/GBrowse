#!/usr/bin/perl -w

use TiledImage;
use GD::Image;

# Stress-test TiledImage by creating an enormous wide tile
# with a zillion tick-marks and char's on it, like a big ruler.

my $width = 10**6;
my $height = 10;
my $ppb = 10;  # pixels per base

# create a new image
my $im = new TiledImage($width,$height);
$im->verbose(1);

# allocate some colors
my $white = $im->colorAllocate(255,255,255);
my $black = $im->colorAllocate(0,0,0);
my $red = $im->colorAllocate(255,0,0);
my $blue = $im->colorAllocate(0,0,255);

# make the background transparent and interlaced
$im->transparent($white);
$im->interlaced('true');

# Put a black frame around the picture
$im->rectangle(0,0,$width,$height,$black);

# Put a tick-mark every $ppb pixels
for (my $x = 0; $x < $width; $x += $ppb) {
    $im->line ($x, 0, $x, $ppb, $black);
}

# put a random char every tick
my @dna = qw(a c g t);
for (my $x = $ppb/2; $x < $width; $x += $ppb) {
    $im->char(GD::gdLargeFont, $x, $ppb, $dna[int rand 4], $blue);
}

# render tiles, do not save
my $tileWidth = 1000;
my $x = $im->width - 1;
$x -= ($x % $tileWidth);
for (; $x >= 0; $x -= $tileWidth) {
    my $tile = $im->renderTile ($x, 0, $tileWidth, $height);
    my $file = "TILE.$x.png";
#    open TILE, ">$file";
#    print TILE $tile->png;
#    close TILE;
    warn "Rendered tile at ($x,0)";
}
