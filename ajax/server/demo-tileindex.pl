#!/usr/bin/perl -w

use TiledImage;
use TileIndex;
use GD::Image;

# create a new image
my $im = new TiledImage(100,100);
# $im->verbose(1);
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

# draw a polygon
my $poly = GD::Polygon->new;
$poly->addPt(15,15);
$poly->addPt(85,15);
$poly->addPt(50,85);
$im->filledPolygon ($poly, $red);

# draw strings
$im->string(GD::gdLargeFont, 10, 10, "hi world", $blue);

# stringFT doesn't seem to work (TrueType installed?)
# $im->stringFT($blue,"Times",9,0,10,10,"hello world");

$im->verbose(0);
my @dim = (10, 10);

my $index = TileIndex->new ($im);
# uncomment to pack tilenames into XML:
# $index->coordDir (undef);
$index->build (@dim);
my $filename = $index->save;

print "\n\nGenerated index file: $filename\n\n";
