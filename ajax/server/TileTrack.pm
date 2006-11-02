package TileTrack;

use TileIndex;

my $legend_tag = "legend";
my $legend_width_tag = "width";
my $legend_path_tag = "path";

# constructor
sub new {
    my ($class, $im, $legend) = @_;
    die "Track height doesn't match legend" if defined($legend) && $im->height != $legend->height;
    my $self = TileIndex->new ($im);
    $self->{'legend'} = $legend;
    $self->{'legendFilename'} = "legend";
    bless $self, $class;
    return $self;
}

# override coordFilename
sub coordFilename {
    my ($self, $x, $y) = @_;
    die "Tile ($x,$y) out of bounds" if $y != 0;
    return (makeNestedPath ($x, $self->coordDir, $self->coordNestLimit), $x);
}

# override build
sub build {
    my ($self, $tileWidth) = @_;
    TileIndex::build ($self, $tileWidth, $self->im->height);
    my ($fullpath, $md5_root) = $self->imageMD5 ($self->legend->png);
    if (defined $self->legend) {
	my $legendPath = $self->coordDir . '/' . $self->legendFilename . $self->imageSuffix;
	symlink $fullpath, $legendPath;
	$self->index->set ($legend_tag => [[$legend_width_tag => $self->legend->width],
					   [$legend_path_tag => $legendPath]]);
    }
}

1;
