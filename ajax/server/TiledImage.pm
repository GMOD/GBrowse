package TiledImage;

use GD::Image;
use Data::Dumper;
use DBI;
use Carp;

# DBI path to database
my $gdtile_database =  "DBI:mysql:gdtile";

# Global table of TiledImage's for cleanup
my %tiledImageCleanup;

# Private methods.
# Code to do (X,Y)-translation for various different intercepted subroutines.
# subroutine to generate a closure that translates an argument list
sub makeGDPrimitiveArglistTranslator {
    my @xyIndexList = @_;
    return sub {
	my ($self, $xstart, $ystart, @arglist) = @_;
	foreach my $xyIndex (@xyIndexList) {
	    $arglist[$$xyIndex[0]] -= $xstart;
	    $arglist[$$xyIndex[1]] -= $ystart;
	}
	return @arglist;
    }
}

# polygon translator
sub GDPolygonTranslate {
    my ($self, $xstart, $ystart, $poly, @arglist) = @_;

    my $translatedPoly = new GD::Polygon;
    foreach my $xy (@{$poly->{'points'}}) {
	$translatedPoly->addPt ($$xy[0] - $xstart, $$xy[1] - $ystart);
    }

    return ($translatedPoly, @arglist);
}

# translators
my $copyTranslate = makeGDPrimitiveArglistTranslator ([1,2]);
my $stringTranslate = makeGDPrimitiveArglistTranslator ([1,2]);
my $stringFTTranslate = makeGDPrimitiveArglistTranslator ([4,5]);
my $xyTranslate = makeGDPrimitiveArglistTranslator ([0,1]);
my $xyxyTranslate = makeGDPrimitiveArglistTranslator ([0,1], [2,3]);

# Code to get the (xmin,ymin,xmax,ymax) bounding-box for intercepted subroutines.
# bounding box getters
sub GDPixelBounds { my ($self, $x, $y) = @_; return ($x, $y, $x+1, $y+1) }
sub GDLineBounds { my ($self, $x1, $y1, $x2, $y2, $col) = @_; return (min($x1,$x2), min($y1,$y2), max($x1,$x2), max($y1,$y2)); }
sub GDPolygonBounds { my ($self, $poly) = @_; return $poly->bounds() }
sub GDEllipseBounds { my ($self, $x, $y, $w, $h) = @_; return ($x-$w, $y-$h, $x+$w, $y+$h) }  # is this twice as big as it should be?
sub GDCopyBounds { my ($self, $im, $destx, $desty, $srcx, $srcy, $w, $h) = @_; return ($destx, $desty, $destx+$w-1, $desty+$h-1) }
sub GDStringBounds { my ($self, $font, $x, $y, $text) = @_; return ($x, $y, $x + length($text)*$font->width, $y + $font->height) }
sub GDStringUpBounds { my ($self, $font, $x, $y, $text) = @_; return ($x, $y, $x + $font->width, $y + length($text)*$font->height) }
sub GDStringFTBounds { my ($self, @args) = @_; my @bb = $self->im->stringFT (@args); return @bb ? @bb[0,1,4,5] : () }

# min & max of a list
sub min {
    my ($x, @y) = @_;
    foreach my $y (@y) {
	$x = $y if $y < $x;
    }
    return $x;
}

sub max {
    my ($x, @y) = @_;
    foreach my $y (@y) {
	$x = $y if $y > $x;
    }
    return $x;
}


# The %intercept hash: a function intercept table.
# Each value is a reference to a hash of references to interception subroutines.
# Possible interception subroutines:
#  'translator'
#  'boundsGetter'
#  'imageStorer'
#  'imageRetriever'
my %intercept =
    ('setPixel' => {'translator' => $xyTranslate, 'boundsGetter' => \&GDPixelBounds},

     'line' => {'translator' => $xyxyTranslate, 'boundsGetter' => \&GDLineBounds},
     'dashedLine' => {'translator' => $xyxyTranslate, 'boundsGetter' => \&GDLineBounds},

     'rectangle' => {'translator' => $xyxyTranslate, 'boundsGetter' => \&GDLineBounds},
     'filledRectangle' => {'translator' => $xyxyTranslate, 'boundsGetter' => \&GDLineBounds},

     'polygon' => {'translator' => \&GDPolygonTranslate, 'boundsGetter' => \&GDPolygonBounds},  # [AVU 12/5/05] added line for bugfix
     'openPolygon' => {'translator' => \&GDPolygonTranslate, 'boundsGetter' => \&GDPolygonBounds},
     'unclosedPolygon' => {'translator' => \&GDPolygonTranslate, 'boundsGetter' => \&GDPolygonBounds},
     'filledPolygon' => {'translator' => \&GDPolygonTranslate, 'boundsGetter' => \&GDPolygonBounds},
     'fillPoly' => {'translator' => \&GDPolygonTranslate, 'boundsGetter' => \&GDPolygonBounds},

     'ellipse' => {'translator' => $xyTranslate, 'boundsGetter' => \&GDEllipseBounds},
     'filledEllipse' => {'translator' => $xyTranslate, 'boundsGetter' => \&GDEllipseBounds},
     'arc' => {'translator' => $xyTranslate, 'boundsGetter' => \&GDEllipseBounds},
     'filledArc' => {'translator' => $xyTranslate, 'boundsGetter' => \&GDEllipseBounds},

     'copy' => {'translator' => $copyTranslate, 'boundsGetter' => \&GDCopyBounds,
		'imageStorer' => \&GDStoreImage, 'imageRetriever' => \&GDRetrieveImage},
     'copyMerge' => {'translator' => $copyTranslate, 'boundsGetter' => \&GDCopyBounds,
		'imageStorer' => \&GDStoreImage, 'imageRetriever' => \&GDRetrieveImage},
     'copyMergeGray' => {'translator' => $copyTranslate, 'boundsGetter' => \&GDCopyBounds,
		'imageStorer' => \&GDStoreImage, 'imageRetriever' => \&GDRetrieveImage},
     'copyResized' => {'translator' => $copyTranslate, 'boundsGetter' => \&GDCopyBounds,
		'imageStorer' => \&GDStoreImage, 'imageRetriever' => \&GDRetrieveImage},
     'copyResampled' => {'translator' => $copyTranslate, 'boundsGetter' => \&GDCopyBounds,
		'imageStorer' => \&GDStoreImage, 'imageRetriever' => \&GDRetrieveImage},
     'copyRotated' => {'translator' => $copyTranslate, 'boundsGetter' => \&GDCopyBounds,
		'imageStorer' => \&GDStoreImage, 'imageRetriever' => \&GDRetrieveImage},

     'string' => {'translator' => $stringTranslate, 'boundsGetter' => \&GDStringBounds},
     'stringUp' => {'translator' => $stringTranslate, 'boundsGetter' => \&GDStringUpBounds},
     'char' => {'translator' => $stringTranslate, 'boundsGetter' => \&GDStringBounds},
     'charUp' => {'translator' => $stringTranslate, 'boundsGetter' => \&GDStringUpBounds},

     'stringFT' => {'translator' => $stringFTTranslate, 'boundsGetter' => \&GDStringFTBounds},
     'stringFTcircle' => {'translator' => $stringFTTranslate, 'boundsGetter' => \&GDStringFTBounds},

     'setBrush' => {'imageStorer' => \&GDStoreImage, 'imageRetriever' => \&GDRetrieveImage},

    );

# List of unimplemented functions:-- these will throw an error if called
# (all others are silently passed to a dummy GD object)
my %unimplemented = map (($_=>1),
			 qw (copyRotate90 copyRotate180 copyRotate270
			     copyFlipHorizontal copyFlipVertical copyTranspose
			     copyReverseTranspose rotate180
			     flipHorizontal flipVertical
			     fill fillToBorder));

# Subroutine interceptions.
# Each of the following can take a ($subroutine, @argument_list) array,
# representing a call to a GD::Image object, $im, of the form $im->$subroutine (@argument_list).

# $self->intercepts ($subroutine)
# returns true if this TiledImage object intercepts the named subroutine
# (i.e. it has an entry in the %intercept hash).
sub intercepts {
    my ($self, $sub) = @_;
    return exists $intercept{$sub};
}

# $self->translate ($xOrigin, $yOrigin, $subroutine, @argument_list)
# "translates" all (X,Y)-coordinates in the argument list of the named subroutine,
# offsetting them relative to the specified (X,Y) origin.
# Control is dispatched to a "translator" via the %intercept hash.
sub translate {
    my ($self, $xstart, $ystart, $sub, @args) = @_;
    my $translator = $intercept{$sub}->{'translator'};
    return defined($translator) ? &$translator ($self, $xstart, $ystart, @args) : @args;
}

# $self->getBoundingBox ($subroutine, @argument_list)
# returns the (xMin,yMin,xMax,yMax) bounding box for the named subroutine
# with the given argument list.
# Control is dispatched to a "bounding-box getter" via the %intercept hash.
sub getBoundingBox {
    my ($self, $sub, @args) = @_;
    my $boundsGetter = $intercept{$sub}->{'boundsGetter'};
    return defined($boundsGetter) ? &$boundsGetter ($self, @args) : ();
}

# $self->storeImages ($subroutine, @argument_list)
# stores any GD::Image objects in the argument list, and replaces them with database image IDs.
# Control is dispatched to an "image storer" via the %intercept hash.
sub storeImages {
    my ($self, $sub, @args) = @_;
    my $imageStorer = $intercept{$sub}->{'imageStorer'};
    @args = &$imageStorer ($self, @args) if defined $imageStorer;
    return @args;
}

# $self->retrieveImages ($subroutine, @argument_list)
# replaces any database image IDs the argument list with references to GD::Image objects.
# Control is dispatched to an "image retriever" via the %intercept hash.
sub retrieveImages {
    my ($self, $sub, @args) = @_;
    my $imageRetriever = $intercept{$sub}->{'imageRetriever'};
    @args = &$imageRetriever ($self, @args) if defined $imageRetriever;
    return @args;
}

# Special-case interceptions of specific GD::Image methods
# intercept clone
sub clone {
    my ($self) = @_;
    my $clone = {%$self};
    bless $clone, ref ($self);
    $clone->im ($self->im->clone);
    return $clone;
}

# hackily intercept getPixel
sub getPixel {
    my ($self, $x, $y) = @_;
    my $im = $self->renderTile ($x, $y, 1, 1);
    return $im->getPixel (0, 0);
}

# apparently some glyphs call this subroutine to see if a drawing method has
# been implemented in the version of BioPerl at hand (a backward compatability
# check), so we must intercept immediately instead of storing in database
sub can {
    my ($self, $method_name) = @_;
    #warn "CHECKING FOR $method_name IN can()...\n"; #D!!!
    return $self->intercepts($method_name);
}

# Database access
sub GDConnect {
    my $gdtile = DBI->connect ($gdtile_database, "") or die "Couldn't connect to database: " . DBI->errstr;
    return $gdtile;
}

sub GDFetchTiledImageDimensions {
    my ($gdtile, $tiledimage_id) = @_;
    my $sth = $gdtile->prepare("SELECT width, height FROM tiledimage WHERE tiledimage_id = " . $tiledimage_id);
    $sth->execute()
	or die "Couldn't execute statement: " . $sth->errstr;
    my ($width, $height) = $sth->fetchrow_array;
    return ($width, $height);
}

sub GDCreateTiledImage {
    my ($gdtile, $width, $height) = @_;
    $gdtile->do ("INSERT INTO tiledimage (width, height) VALUES ($width, $height)");
    my $sth = $gdtile->prepare("SELECT LAST_INSERT_ID()");
    $sth->execute()
	or die "Couldn't execute statement: " . $sth->errstr;
    my ($tiledimage_id) = $sth->fetchrow_array;
    return $tiledimage_id;
}

sub GDPrepareQueries {
    my ($gdtile) = @_;
    my $global_sth = $gdtile->prepare('SELECT command_order, command FROM global_primitive WHERE tiledimage_id = ?')
	or die ("Couldn't prepare statement: " . $gdtile->errstr);

    my $bb_sth = $gdtile->prepare('SELECT command_order, command FROM primitive WHERE x0 <= ? AND y0 <= ? AND x1 >= ? AND y1 >= ? AND tiledimage_id = ?')
	or die ("Couldn't prepare statement: " . $gdtile->errstr);
    return ($global_sth, $bb_sth);
}

sub GDDeletePrimitives {
    my ($self) = @_;
    # use explicit hashrefs instead of AUTOLOAD'ed accessors,
    # so that this method can be called by the signal handlers
    $self->{'gdtile'}->do ("DELETE FROM primitive WHERE tiledimage_id = " . $self->{'id'});
}

sub GDDisconnect {
    my ($self) = @_;
    # use explicit hashrefs instead of AUTOLOAD'ed accessors,
    # so that this method can be called by the signal handlers
    $self->{'gdtile'}->disconnect if defined $self->{'gdtile'};
}

sub GDStoreImage {
    my ($self, $image, @otherArgs) = @_;

    # get PNG data
    croak "Not a GD::Image" unless ref($image) eq "GD::Image";
    my $image_data = $image->png;
    croak "Bad image data" unless defined $image_data;

    # INSERT PNG data into image table
#    warn "inserting: INSERT INTO image (image_data) VALUES (?)" if $self->verbose == 2;
    my $sth = $self->gdtile->prepare("INSERT INTO image (image_data) VALUES (?)")
	or die "Couldn't prepare statement: " . $self->gdtile->errstr;

    $sth->execute ($image_data)
	or die "Couldn't execute statement: " . $sth->errstr;

    # get image ID
    my $id_sth = $self->gdtile->prepare("SELECT LAST_INSERT_ID()");
    $id_sth->execute()
	or die "Couldn't execute statement: " . $id_sth->errstr;
    my ($image_id) = $id_sth->fetchrow_array;

    # return
    return ($image_id, @otherArgs);
}

sub GDRetrieveImage {
    my ($self, $image_id, @otherArgs) = @_;

    # get PNG data from image table
    my $sth = $self->gdtile->prepare("SELECT image_data FROM image WHERE image_id = $image_id")
	or die "Couldn't prepare statement: " . $self->gdtile->errstr;

    $sth->execute()
	or die "Couldn't execute statement: " . $sth->errstr;

    # create image from PNG data & remember it in image_cache.
    # NB if we just create a GD::Image object here, bugs occur in setBrush,
    # maybe cos Perl thinks it can safely delete the brush image (due to absence of refs to object?)
    # keeping the image in image_cache seems to work (because it fool Perls into keeping the GD::Image around?)
    while (my ($image_data) = $sth->fetchrow_array) {
	$self->image_cache->{$image_id} = GD::Image->newFromPngData ($image_data);
    }

    # return
    return ($self->image_cache->{$image_id}, @otherArgs);
}

sub GDRecordPrimitive {
    my ($self, $command, @bb) = @_;

    # which table should this go into?
    my @cols = qw(tiledimage_id command_order command);
    my $table;
    if (@bb) {
	push @cols, qw(x0 y0 x1 y1);
	$table = 'primitive';
    } else {
	$table = 'global_primitive';
    }

    # INSERT subroutine & argument list into table
    my $command_order = $self->n_primitives ($self->n_primitives + 1);
    $self->gdtile->do ("INSERT INTO $table ("
		       . join (',', @cols)
		       . ") VALUES ("
		       . join (',', $self->id, $command_order, "\"$command\"", @bb)
		       . ")");
}

sub GDEraseLeftmostPrimitives {
    my ($self, $x) = @_;
    $self->gdtile->do ("DELETE FROM global_primitive WHERE x1 < $x");
}

# The following two methods for querying tables of GD primitives both
# return a coderef that's an iterator over (command_order, command) pairs
sub GDGetGlobalPrimitives {
    my ($self) = @_;
    $self->global_sth->execute ($self->id)
	or die "Couldn't execute statement: " . $self->global_sth->errstr;
    
    return sub { $self->global_sth->fetchrow_array};
}

sub GDGetBoundedPrimitives {
    my ($self, $xmin, $ymin, $xmax, $ymax) = @_;
    $self->bb_sth->execute($xmax,$ymax,$xmin,$ymin,$self->id)
	or die "Couldn't execute statement: " . $self->bb_sth->errstr;

    return sub { $self->bb_sth->fetchrow_array };
}

# AUTOLOAD method: catches all methods by default
sub AUTOLOAD {
    my ($self, @args) = @_;
    my @originalArgs = @args;

    # get subroutine name
    my $sub = our $AUTOLOAD;
    $sub =~ s/.*:://;

    # check for DESTROY
    return if $sub eq "DESTROY";

    # check for unimplemented methods
    if ($unimplemented{$sub}) {
	croak "Subroutine $sub unimplemented";
    }

    # check for accessors
    if (exists $self->{$sub}) {
	croak "Usage: $sub() or $sub(newValue)" if @args > 1;
	return
	    @args
	    ? $self->{$sub} = $args[0]
	    : $self->{$sub};
    }

    # check for intercept: if so, get bounding box & store any images
    my @bb;
    if ($self->intercepts($sub)) {
	@bb =  $self->getBoundingBox ($sub, @args);
	@args = $self->storeImages ($sub, @args);

	# update global bounding box
	if (@bb) {
	    $self->xmin ($bb[0]) if !defined ($self->xmin) || $bb[0] < $self->xmin;
	    $self->ymin ($bb[1]) if !defined ($self->ymin) || $bb[1] < $self->ymin;
	    $self->xmax ($bb[2]) if !defined ($self->xmax) || $bb[2] >= $self->xmax;
	    $self->ymax ($bb[3]) if !defined ($self->ymax) || $bb[3] >= $self->ymax;
	}
    }

    # get string representation and store in SQL database
    my $dumper = Data::Dumper->new ([[$sub,@args]]);
    $dumper->Indent(0)->Terse(1)->Purity(1);
    my $command = $dumper->Dump;
    $command =~ s/\\/\\\\/g;  # escape backslashes

    # record primitive
    $self->GDRecordPrimitive ($command, @bb);

    # log primitive
    warn "Recorded $sub (@originalArgs) with ", (@bb>0 ? "bounding box (@bb)" : "no bounding box"), "\n" if $self->verbose == 2;

    # delegate
    $self->im->$sub (@originalArgs);
}

# This needs to be called manually to cleanup and disconnect from database after done with the object;
# otherwise, database connections remain open and clog database until instantiating script exits
#
# MAYBE TAKE THIS METHOD OUT AND MAKE INSTANTIATING SCRIPT CALL 'cleanup' DIRECTLY ANYWAY? !!!
sub finish {
    my $self = shift;
    warn "TiledImage.pm IS CLEANING UP AND DISCONNECTING FROM DATABASE in finish()...\n" if $self->verbose; 
    $self->cleanup;
    # there was stuff here, but now it is gone... call 'cleanup' directly? !!!
}

# Destructor - TEMPORARILY (?) DISABLED due to DBI connectivity problems, destruction is now the responsibility of the caller
#sub DESTROY {
#    my ($self) = @_;
#    warn "TiledImage.pm IS CLEANING UP AND DISCONNECTING FROM DATABASE in destructor...\n" if $self->verbose;
#    $self->cleanup;
#    $self->gdtile->disconnect if $self->gdtile;  #  just in case we didn't close the database connection using finish() 
#}

# Public methods.
# Constructor
sub new {
    my ($class, %args) = @_;
    my ($width, $height, $tiledimage_id);

    #warn "ENTERING TiledImage CONSTRUCTOR; arguments are:\n"; #D!!!
    #foreach my $key (sort keys %args) { warn "$key => ", $args{$key}, "\n"; } #D!!!
    #warn "-------------------------------------------------\n"; #D!!!
    
    # correctness check
    if ($args{'-tiledimage_id'} && ($args{'-width'} || $args{'-height'})) {
	my $hash_contents;
	foreach my $key (sort keys %args) {
	    $hash_contents .= $key . '=>' . $args{$key} . ' ';
	}
        croak "You are not allowed to specify -tiledimage_id with a -width or with a -height parameter or vice versa (your params were parsed as: $hash_contents)";
    }

    my %allowed_args = ('-tiledimage_id' => 1, '-width' => 1, '-height' => 1, '-persistent' => 1, '-verbose' => 1);
    foreach my $param (keys %args) {
        if (! $allowed_args{$param}) {
	    my $hash_contents;
	    foreach my $key (sort keys %args) {
	        $hash_contents .= $key . '=>' . $args{$key} . ' ';
	    }
            croak "Invalid parameter ($param) in TiledImage constructor (your params were parsed as: $hash_contents)";
        }
        if (! exists $args{$param}) {
	    my $hash_contents;
	    foreach my $key (sort keys %args) {
	        $hash_contents .= $key . '=>' . $args{$key} . ' ';
	    }
            croak "No value for parameter ($param) in TiledImage constructor (your params were parsed as: $hash_contents)";
        }
    }

    # connect to database
    my $gdtile = GDConnect();

    # parse required constructor args
    if (exists $args{'-tiledimage_id'}) {
	($tiledimage_id) = $args{'-tiledimage_id'};
	($width, $height) = GDFetchTiledImageDimensions ($gdtile, $tiledimage_id);

    } elsif ( (exists $args{'-width'}) && (exists $args{'-height'}) ) {
	($width, $height) = ($args{'-width'}, $args{'-height'});
	($tiledimage_id) = GDCreateTiledImage ($gdtile, $width, $height);
    }

    my ($persistent, $verbose) = (1, 0);  # defaults

    # parse optional constructor args
    ($verbose) = $args{'-verbose'} if exists $args{'-verbose'} ;
    ($persistent) = $args{'-persistent'} if exists $args{'-persistent'};

    # create dummy GD image
    my $im = GD::Image->new (1, 1);

    # prepare SQL queries
    my ($global_sth, $bb_sth) = GDPrepareQueries ($gdtile);

    # create the proxy object
    my $self = { 'im' => $im,

		 'width' => $width,
		 'height' => $height,

		 'xmin' => undef,
		 'xmax' => undef,
		 'ymin' => undef,
		 'ymax' => undef,

		 'verbose' => $verbose,
		 'persistent' => $persistent,

		 'image_cache' => {},

		 'gdtile' => $gdtile,
		 'global_sth' => $global_sth,
		 'bb_sth' => $bb_sth,

		 'id' => $tiledimage_id,
		 'n_primitives' => 0,
	     };

    # bless it, and add to global table
    bless $self, $class;
    $tiledImageCleanup{$self} = 1;

    # return
    return $self;
}

# renderTile:--
# method to render a tile of given dimensions.
sub renderTile {
    my ($self, $xmin, $ymin, $width, $height) = @_;
    my ($xmax, $ymax) = ($xmin + $width - 1, $ymin + $height - 1);

    # print message
    warn "\nRendering tile ($xmin,$ymin)+($width,$height)\n" if $self->verbose == 2;

    # create GD image
    my $im = GD::Image->new ($width, $height);

    # create index hash of primitives
    my %sub_args;

    # Query database for stored GD::Image primitives that are global, affecting all tiles
    my $globalIterator = $self->GDGetGlobalPrimitives;
    while (my ($command_order, $command) = &$globalIterator()) {

	# recreate [$subroutine,@argument_list] primitive using 'eval' on Data::Dumper string
	my ($sub, @args) = @{eval $command};
	unless (defined $sub) {  # check subroutine is defined
	    warn $!;
	    die "Offending 'eval': $command\n";
	}

	# retrieve images
	@args = $self->retrieveImages ($sub, @args);

	# store primitive
	$sub_args{$command_order} = [$sub, @args];
    }

    # Query database for stored GD::Image primitives overlapping this tile
    my $boundedIterator = $self->GDGetBoundedPrimitives ($xmin, $ymin, $xmax, $ymax);
    while (my ($command_order, $command) = &$boundedIterator()) {

	# recreate [$subroutine,@argument_list] primitive using 'eval' on Data::Dumper string
	my ($sub, @args) = @{eval $command};
	unless (defined $sub) {  # check subroutine is defined
	    warn $!;
	    die "Offending 'eval': $command\n";
	}

	# check for interception: if so, retrieve images & translate coords
	if ($self->intercepts ($sub)) {
	    @args = $self->retrieveImages ($sub, @args);
	    @args = $self->translate ($xmin, $ymin, $sub, @args);

	    # store primitive
	    $sub_args{$command_order} = [$sub, @args];
	}
    }

    # Execute primitives
    my @command_order = sort { $a <=> $b } keys %sub_args;
    foreach my $command_order (@command_order) {
	my ($sub, @args) = @{$sub_args{$command_order}};

	warn "Replaying $sub (@args)\n" if $self->verbose == 2;
	$im->$sub (@args);

    }

    # flush image cache
    $self->image_cache ({});

    # return
    return $im;
}

# cleanup:--
# method to purge the database of primitives
sub cleanup {
    my ($self) = @_;

    #warn "the keys are: ", keys %$self, "\n";  #D!!!
    #foreach my $key (sort keys %$self) {
    #	warn "it is said that once upon a time $key = ", $self->{$key}, "\n";
    #}

    # use explicit hashrefs instead of AUTOLOAD'ed accessors,
    # so that this method can be called by the signal handlers
    if ($self->{'persistent'} == 0) {

	warn "Deleting primitives from database\n"; # if $self->verbose;
	$self->GDDeletePrimitives;
    }

    # drop from cleanup list
    delete $tiledImageCleanup{$self} if exists $tiledImageCleanup{$self};

    $self->GDDisconnect;
}

# THERE IS CLEARLY A PROBLEM WITH THESE SIGNAL HANDLERS, SO I'M TAKING THEM
# OUT AND PLACING THE HANDLER IN 'generate_tiles.pl' - it will be the
# responsibility of the instantiating script to clean up and disconnect! [AVU 2/4/06] !!!

# global_cleanup
# method to call cleanup on all existing TiledImage's
#sub global_cleanup {
#    warn "in global_cleanup";
#    my @tiledImage = keys %tiledImageCleanup;
#    foreach my $tiledImage (@tiledImage) {
#	cleanup ($tiledImage);
#    }
#}

# signal handlers
#my $oldSigInt = $SIG{'INT'};
#$SIG{'INT'} = sub {
#    warn "caught SIG{INT}"; #D!!!
#    foreach my $tiledImage (keys %tiledImageCleanup) {  # if program was interrupted, we should clean up database
#	 $tiledImage->{'persistent'} = 0;               # entries made so far, no matter what the user specified
#    }
#    global_cleanup();
#    &$oldSigInt() if defined $oldSigInt;
#};

#my $oldSigKill = $SIG{'KILL'};
#$SIG{'KILL'} = sub {
#    warn "caught SIG{KILL}"; #D!!!
#    foreach my $tiledImage (keys %tiledImageCleanup) {  # if program was interrupted, we should clean up database
#	$tiledImage->{'persistent'} = 0;               # entries made so far, no matter what the user specified
#    }
#    global_cleanup();
#    &$oldSigKill() if defined $oldSigKill;
#};

# End of package
1;
