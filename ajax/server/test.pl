#!/usr/bin/perl -w

use TiledImage;
use GD::Image;

# create a new image
my $im = new TiledImage(100,100);
#my $im = new GD::Image(100,100);

# allocate some colors
my $white = $im->colorAllocate(255,255,255);
my $black = $im->colorAllocate(0,0,0);
my $red = $im->colorAllocate(255,0,0);
my $blue = $im->colorAllocate(0,0,255);

# make the background transparent and interlaced
$im->transparent($white);
$im->interlaced('true');

# Put a black frame around the picture
$im->rectangle(0,0,99,99,$black);

# Draw a blue oval
$im->arc(50,50,95,75,0,360,$blue);

# Can't fill it with red, since fill doesn't work if started offscreen
# $im->fill(50,50,$red);

# save one big tile
#open TILE, ">BIGTILE.png";
#print TILE $im->png;
#close TILE;
#exit;

# render and save four tiles
for ($x = 0; $x < 100; $x += 50) {
    for ($y = 0; $y < 100; $y += 50) {
	warn "Rendering tile at ($x,$y)\n";
	$tile = $im->renderTile ($x, $y, 50, 50);
	open TILE, ">TILE.$x.$y.png";
	warn "printing PNG";
	print TILE $tile->png;
	close TILE;
    }
}
