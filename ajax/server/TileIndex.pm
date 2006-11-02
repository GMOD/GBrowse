package TileIndex;

use TiledImage;
use Cwd;
use Digest::MD5 qw(md5_hex);
use Data::Stag;

# tag names
my $index_tag = 'tile_map';
my $full_size_tag = 'map_size';
my $tile_size_tag = 'tile_size';
my $auto_path_tag = 'auto_path';
my $image_path_tag = 'image_path';
my $prefix_tag = 'prefix';
my $suffix_tag = 'suffix';
my $nest_limit_tag = 'max_nest';
my $tiles_tag = 'tile_images';
my $tile_tag = 't';
my $x_tag = 'x';
my $y_tag = 'y';
my $image_tag = 'i';

# constructor
sub new {
    my ($class, $im) = @_;
    my $self = { 'im' => $im,
		 'stag' => Data::Stag->new ($index_tag=>[]),
		 'imageDir' => "md5_image",
		 'coordDir' => "tiles",
		 'indexDir' => "md5_map",
		 'imageSuffix' => ".png",
		 'indexSuffix' => ".xml",
		 'imageNestLimit' => 7,   # 16^7 ~= 10^8 tiles
		 'coordNestLimit' => undef,
		 'indexNestLimit' => 0,
	     };
    bless $self, $class;
    return $self;
}

# accessors
sub AUTOLOAD {
    my ($self, @args) = @_;
    my $sub = our $AUTOLOAD;
    $sub =~ s/.*:://;

    # check for DESTROY
    return if $sub eq "DESTROY";

    # check for accessors
    if (exists $self->{$sub}) {
	die "Usage: $sub() or $sub(newValue)" if @args > 1;
	return
	    @args
	    ? $self->{$sub} = $args[0]
	    : $self->{$sub};
    }

    # throw an error
    die "Unimplemented method '$sub' called";
}

# accessor for Stag index
sub index {
    my ($self) = @_;
    my ($index) = $self->stag->find ($index_tag);
    return $index;
}

# turn a directory name into a valid existing path
sub makePath {
    my ($name) = @_;
    mkdir $name unless -d $name;
    $name =~ s:([^/])$:$1/:;
    return $name;
}

# given a directory name (e.g. "ABCDE..."),
# make a valid relative path to it in the form "A/B/C/..."
sub makeNestedPath {
    my ($name, $prefix, $nestLimit) = @_;
    $prefix = makePath ($prefix);
    $nestLimit = -1 unless defined $nestLimit;
    for (my $i = 0; $i < length($name) && $i != $nestLimit; ++$i) {
	my $subdir = substr ($name, $i, 1);
	$prefix = makePath ($prefix . $subdir);
    }
    return $prefix . $name;
}

# method to get an MD5 digest and turn it into a filename stub
sub md5Filename {
    my ($data, $prefix, $nestLimit) = @_;
    my $md5 = md5_hex ($data);
    $md5 =~ tr:+/:@_:;
    # return path-stub and filename-stub
    return (makeNestedPath ($md5, $prefix, $nestLimit), $md5);
}

# method to turn tile (x,y)-coords into a filename stub
sub coordFilename {
    my ($self, $x, $y) = @_;
    my $coord = "${x}_${y}";
    return (makeNestedPath ($coord, $self->coordDir, $self->coordNestLimit), $coord);
}

# method to save an image file and return MD5 filename
sub imageMD5 {
    my ($self, $png) = @_;
    my ($md5, $md5_root) = md5Filename ($png, $self->imageDir, $self->imageNestLimit);
    my $filename = $md5 . $self->imageSuffix;
    local *FILE;
    unless (-e $filename) {
	local *FILE;
	open FILE, ">$filename" or die "$filename: $!";
	print FILE $png;
	close FILE or die "$filename: $!";
    }
    my $fullpath = getcwd() . '/' . $filename;
    return ($fullpath, $md5_root);
}

# method to create a tile, save it with an md5Filename, and link to it with a coordFilename.
sub addTile {
    my ($self, $nx, $ny, $width, $height) = @_;

    # generate image data
    my ($xmin, $ymin) = ($nx * $width, $ny * $height);
    my $tile = $self->im->renderTile ($xmin, $ymin, $width, $height);
    my $png = $tile->png;

    # save to file with MD5 filename
    my ($fullpath, $md5_root) = $self->imageMD5 ($png);

    # make link to file with coord-derived filename
    if (defined $self->coordDir) {
	my ($linkname, $coord) = $self->coordFilename ($nx, $ny);
	symlink $fullpath, $linkname . $self->imageSuffix;
    } else {
	# no coordDir defined for filesystem; record tiles in XML index instead
	my ($tiles) = $self->index->find ($tiles_tag);
	$tiles->add ($tile_tag, [[$x_tag => $nx],
				 [$y_tag => $ny],
				 [$image_tag => $md5_root]]);
    }
}

# method to build a tile index
sub build {
    my ($self, $tileWidth, $tileHeight) = @_;
    my ($w, $h) = ($self->im->width, $self->im->height);
    my $n = int ($w / $tileWidth) * int ($h / $tileHeight);
    my $auto_path = defined ($self->coordDir) ? 1 : 0;

    $self->index->set ($full_size_tag => [[$x_tag => $w],
					  [$y_tag => $h]]);

    $self->index->set ($tile_size_tag => [[$x_tag => $tileWidth],
					   [$y_tag => $tileHeight]]);

    $self->index->set (($auto_path ? $auto_path_tag : $image_path_tag)
		       => [[$prefix_tag => ($auto_path ? $self->coordDir : $self->imageDir) . '/'],
			   [$suffix_tag => $self->imageSuffix],
			   $auto_path
			   ? (defined($self->coordNestLimit) ? [$nest_limit_tag => $self->coordNestLimit] : ())
			   : (defined($self->imageNestLimit) ? [$nest_limit_tag => $self->imageNestLimit] : (),
			      [$tiles_tag => []])]);

    for (my $xmin = 0, $nx = 0; $xmin < $w; ++$nx, $xmin += $tileWidth) {
	for (my $ymin = 0, $ny = 0; $ymin < $h; ++$ny, $ymin += $tileHeight) {
	    $self->addTile ($nx, $ny, $tileWidth, $tileHeight);
	}
    }
}

# method to build & then save a tile index, returning autogenerated filename
sub save {
    my ($self, $filename) = @_;
    my $xml = $self->stag->xml;
    if (!defined $filename) {
	my ($md5, $md5_root) = md5Filename ($xml, $self->indexDir, $self->indexNestLimit);
	$filename = $md5 . $self->indexSuffix;
    }
    local *FILE;
    unless (-e $filename) {
	local *FILE;
	open FILE, ">$filename" or die "$filename: $!";
	print FILE $xml;
	close FILE or die "$filename: $!";
    }
    return $filename;
}

# end of package
1;
