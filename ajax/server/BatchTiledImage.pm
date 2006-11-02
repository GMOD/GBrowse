package BatchTiledImage;

use TiledImage;
use GD::Image;
use Carp;

@ISA = qw(TiledImage);

# Constructor
sub new {
    my ($class, %args) = @_;
    my (%myArgs, %baseClassArgs);

    my %argAllowed = map (($_ => 1), qw(-renderTiles -firstTile -lastTile -tileWidth -renderWidth -tilePrefix));
    while (my ($arg, $val) = each %args) {
	if ($argAllowed{$arg}) {
	    $arg =~ s/^-//;
	    $myArgs{$arg} = $val;
	} else {
	    $baseClassArgs{$arg} = $val;
	}
    }

    my $self = TiledImage->new (%baseClassArgs);
    while (my ($arg, $val) = each %myArgs) {
	$self->{$arg} = $val;
    }

    # default params
    $self->{'renderTiles'} = 1 unless defined $self->{'renderTiles'};
    $self->{'tileWidth'} = 1000 unless defined $self->{'tileWidth'};   # default tile width
    $self->{'renderWidth'} = 100000 unless defined $self->{'renderWidth'};  # default render width
    $self->{'firstTile'} = 0 unless defined $self->{'firstTile'};
    $self->{'lastTile'} = $self->width / $self->tileWidth unless defined $self->{'lastTile'};
    $self->{'tilePrefix'} = 'TILE' unless defined $self->{'tilePrefix'};  # default tile prefix

    # other member vars
    $self->{'lastTileRendered'} = undef;

    # bless and return
    bless $self, $class;
    return $self;
}

# method to render a range of tiles
# NB tiles used 0-based indexing
sub renderTileRange {
    my ($self, $first_tile, $last_tile) = @_;

    if ($self->renderTiles) {

	# check bounds
	$first_tile = $self->firstTile if !defined($first_tile) || $first_tile < $self->firstTile;
	$last_tile = $self->lastTile if !defined($last_tile) || $last_tile > $self->lastTile;

	# get values of some member vars
	my $tilewidth_pixels = $self->tileWidth;
	my $rendering_tilewidth = $self->renderWidth;
	my $tile_prefix = $self->tilePrefix;
	my $image_height = $self->height;

	# we are going to render (i.e. make GD objects for) really large tiles, then break them up
	# into smaller tiles prior to conversion and printing to PNG; the reason for this is that
	# large tiles mean we have to recall less GD primitives from the TiledImage database, as
	# very frequently glyphs will overlap multiple tiles... so that means a glyph overlapping
	# multiple tiles gets recalled more often, once for each tile... but bigger tiles means less
	# overlap, so less database access, so smaller runtime

	# these should really divide evenly, and of course no one will MISUSE the script, right? !!!
	my $small_per_large = int ($rendering_tilewidth / $tilewidth_pixels);  # small tiles per large tile
	if ($small_per_large * $tilewidth_pixels != $rendering_tilewidth) {
	    croak "Error: -renderWidth needs to be an integer multiple of -tileWidth";
	}
	
	my $first_large_tile = floor($first_tile / $small_per_large);
	my $last_large_tile = ceiling($last_tile / $small_per_large);

	local *TILE;
	for (my $x = $first_large_tile; $x <= $last_large_tile; $x++) {
	    my $large_tile_gd = $self->renderTile($x * $rendering_tilewidth, 0,
						  $rendering_tilewidth, $image_height);

	    # now to break up the large tile into small tiles and write them to PNG on disk...
	    for (my $y = 0; $y < $small_per_large; $y++) {
		my $small_tile_num = $x * $small_per_large + $y;
		if ( ($small_tile_num >= $first_tile) && ($small_tile_num <= $last_tile) ) {  # do we print it?
		    my $outfile = "${tile_prefix}${small_tile_num}.png";
		    open (TILE, ">${outfile}") or die "ERROR: could not open ${outfile}!\n";
			
		    my $small_tile_gd = new GD::Image($tilewidth_pixels, $image_height);
		    $small_tile_gd->copy($large_tile_gd, 0, 0, $y * $tilewidth_pixels, 0, $tilewidth_pixels, $image_height);

		    print TILE $small_tile_gd->png or die "ERROR: could not write to ${outfile}!\n";

		    warn "done printing ${outfile}\n" if $self->verbose;
		}
	    }
	}
    }
}

# subroutine to render all tiles to the left of a given X-coord, then wipe all redundant (leftward) primitives from database
sub renderAndWipe {
    my ($self, $x) = @_;

    my $lastTileRendered = $self->lastTileRendered;
    $lastTileRendered = -1 unless defined $lastTileRendered;

    my $lastTileToRender = int ($x / $self->tileWidth) - 1;

    $self->renderTileRange ($lastTileRendered + 1, $lastTileToRender);
    $self->GDEraseLeftmostPrimitives ($x) unless $self->persistent;

    $self->lastTileRendered ($lastTileToRender);
}

# subroutine to render all tiles
# simply calls renderAndWipe at the rightmost edge of the image
sub renderAllTiles {
    my ($self) = @_;
    $self->renderAndWipe ($self->width);
}

# --- HELPER FUNCTIONS ----

sub ceiling {
    my $i = shift;
    my $i_int = int($i);  # remember that 'int' truncates toward 0

    return $i_int + 1 if $i_int != $i and $i > 0;
    return $i_int;
}

sub floor {
    my $i = shift;
    my $i_int = int($i);  # remember that 'int' truncates toward 0
    
    return $i_int if $i >= 0 or $i_int == $i;
    return $i_int - 1;
}

# end of package
return 1;
