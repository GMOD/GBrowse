#!/usr/bin/perl -w

###########################################################################
#
# Prototype pre-renderer of tiles for the new GBrowse.  Based on bits and
# pieces of 'gbrowse_img' and 'Browser.pm', (the 'image_and_map' function)
# incorporated into one standalone script that uses our TiledImagePanel.pm
# module (which is a modification of Bio::Graphics::Panel with essentially
# the same functionality, except using the TiledImage object instead of
# GD::Image, making it possible to render tiles of very large images).
#
# !!! NOTES:
# - Remember that 'arrow.pm' had to be hacked!
# - Load args to this program from a config file?
# - TODO: Make script check for nonexistent/not implemented arguments
#
###########################################################################

use strict;
use Bio::DB::GFF;
use Bio::Graphics;
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Util;
use GD::SVG;                       # this may be necessary later !!!
use TiledImagePanel;               # our clone of 'Panel.pm' that returns TiledImage object instead of GD::Image
use BatchTiledImage;
use Data::Dumper;


# --- BEGIN MANUAL PARAMETER SPECIFICATIONS ---
my $rendering_tilewidth = 32000;  # tile width (in pixels) for RENDERING via TiledImage (bigger tiles
                                  # render faster, so we render big chunks, then break them up into pieces)
my $tilewidth_pixels = 1000;      # actual width (in pixels) of tiles for client; the TiledImage tiles get
                                  # broken up into these after rendering; note that it must be true that:
                                  #   $tilewidth_pixels % $tilewidth_pixels_final = 0
                                  # otherwise we will have leftover, unrendered pixels!

my $xmlfile = 'tileinfo.xml';     # XML file name to save settings/etc. to

# default output is to the current directory
my $default_outdir = `pwd`;
chomp $default_outdir;
$default_outdir .= '/';

# try to find a configuration file directory (check the usual suspects)
my $default_confdir;
foreach my $dir (qw [
		     /usr/local/apache2/conf/gbrowse.conf/
		     /usr/local/conf/gbrowse.conf/
		     /etc/httpd/conf/gbrowse.conf/
		     /Library/WebServer/conf/gbrowse.conf/
		    ]) {
  if (-e $dir) {
    $default_confdir = $dir;
    last;
  }
}
# --- END MANUAL PARAMETER SPECIFICATIONS ---

# Parse command line arguments and load configuration data

my %args;
for (my $i = 0; $i < @ARGV; $i++) {
    if (substr($ARGV[$i], 0, 1) eq '-') {  # find command line params...
	$args{$ARGV[$i]} = $ARGV[$i+1];    # ...and save them
    }
}

print_usage() if exists $args{'-?'} or exists $args{'-help'} or exists $args{'--help'};
my $exit_early = 1 if exists $args{'--exit-early'};
my $no_xml = 1 if exists $args{'--no-xml'};
my $render_gridlines = exists $args{'--render-gridlines'} ? 1 : 0;

print
    "-------------------------------------------------------------------------\n",
    " Script was invoked with parameters: @ARGV \n";

# set mode (i.e. what does the user want this script to do?) - note the XML file is ALWAYS output
my ($fill_database, $render_tiles);
if (exists $args{'-m'}) {
    if    ($args{'-m'} == 0) { ($fill_database, $render_tiles) = (1, 1); }
    elsif ($args{'-m'} == 1) { ($fill_database, $render_tiles) = (1, 0); }
    elsif ($args{'-m'} == 2) { ($fill_database, $render_tiles) = (0, 1); }
    elsif ($args{'-m'} == 3) { ($fill_database, $render_tiles) = (0, 0); }
    else                     { die "ERROR: invalid '-m' parameter!\n"; }
} else {
    print " Using default mode (fill database and render tiles)...\n";
    ($fill_database, $render_tiles) = (1, 1);  # defaults
}

print " XML file will NOT be generated...\n" if $no_xml;

my ($persistent,  $verbose, $primdb);  # these get passed to TiledImage

if (exists $args{'-p'}) {
    if    ($args{'-p'} == 0) { $persistent = 0; }
    elsif ($args{'-p'} == 1) { $persistent = 1; }
    else                     { die "ERROR: invalid '-p' parameter!\n"; }
} else {
    print " Using default setting: primitives will NOT be deleted...\n" if $fill_database or $render_tiles;
    $persistent = 1;
}

$primdb = $args{'-primdb'};

if (exists $args{'-v'}) {
    if    ($args{'-v'} == 2) { $verbose = 2; }
    elsif ($args{'-v'} == 1) { $verbose = 1; }
    elsif ($args{'-v'} == 0) { $verbose = 0; }
    else                     { die "ERROR: invalid '-v' parameter!\n"; }
} else {
    print " Using default setting: NOT in verbose mode...\n" if $fill_database or $render_tiles;
    $verbose = 0;
}

# do output directory and XML file stuff
my $outdir = $args{'-o'};
unless ($outdir) {
    $outdir = $default_outdir;
    print " Using default output directory (${outdir})...\n" unless !$render_tiles and $no_xml;
}

unless (-e $outdir || !$render_tiles) {
    mkdir $outdir or die "ERROR: cannot make output directory ${outdir}! ($!)\n";
}

unless ($no_xml) {
    open XMLFILE, ">${outdir}/${xmlfile}" or die "ERROR: cannot open '${outdir}/${xmlfile}' ($!)\n";
}

# do database '.conf' directory stuff
my $CONF_DIR = $args{'-c'};
if ($CONF_DIR) {
  die "ERROR: cannot access '.conf' directory (${CONF_DIR})!\n" unless -e $CONF_DIR;
} else {
  if ($default_confdir) {
    $CONF_DIR = $default_confdir;
    print " Using a default '.conf' directory (${CONF_DIR})...\n";
  } else {
    die "ERROR: no default '.conf' directory found and you did not provide one explicitly (-c option)... cannot continue!\n";
  }
}

# load stuff from config file
$CONF_DIR = conf_dir($CONF_DIR);
my $CONFIG = open_config($CONF_DIR);  # create Bio::Graphics::Browser configuration object

# if more than one possible source (i.e. more than one '.conf' file in $CONF_DIR) exists,
# the user needs to make a choice
my ($source, @sources) = ($args{'-s'}, $CONFIG->sources);
if (@sources > 1) {
    if ($source) {
	$CONFIG->source($source) or die "ERROR: no such source! (the choices are: @sources)\n";
    }
    else {
	die "ERROR: multiple sources found - you must specify a single source! (the choices are: @sources)\n";
    }
} else {
    $source = $CONFIG->source;
    die "ERROR: no sources that can be loaded from ${CONF_DIR}!\n" if !$source;
}

print " Configuration file directory: ${CONF_DIR}\n";

my $source_name = $CONFIG->setting('description');  # get human-readable description

my $db = open_database($CONFIG);      # create Bio::DB::GFF::Adaptor::<adaptor name> object, where
                                      # <adaptor name> is what is specified in the '.conf' file

print " Source: ${source} (${source_name})\n";

# get landmark info
my $conf = $CONFIG->config;  # a Bio::Graphics::BrowserConfig object, which uses 
                             # the Bio::Graphics::FeatureFile package

my $landmark_name = $args{'-l'};  # for passing to BioGraphics
die "ERROR: you must provide a landmark name!\n" if !$landmark_name;

# note that @segments should always be a 1-element array, since we are forcing only one landmark
# per script execution and we are considering the ENTIRE landmark
my @segments = $CONFIG->name2segments($landmark_name, $db, undef, 1);  # this should return the range of the entire landmark
my $segment = $segments[0];

die "ERROR: problem loading landmark! (are you sure the name is correct? you provided: ${landmark_name})\n"
    if !$segment;

# get landmark dimensions
my ($landmark_start, $landmark_end, $landmark_length) = ($segment->start, $segment->end, $segment->length);
my $landmark = "${landmark_name}:${landmark_start}..${landmark_end}";

print
    " Landmark: ${landmark} (${source_name})\n",
    " Landmark length: ${landmark_length} bases\n";

# NB: the following paths are landmark specific (TODO: when we implement looping over multiple
# landmarks, the following will have to be in the loop body)

my $outdir_tiles = "${outdir}/tiles/";
unless (-e $outdir_tiles || !$render_tiles) {
    mkdir $outdir_tiles or die "ERROR: cannot make tile output directory ${outdir_tiles}! ($!)\n";
}
$outdir_tiles .= "${landmark_name}/";  # append landmark-specific subdir
unless (-e $outdir_tiles || !$render_tiles) {
    mkdir $outdir_tiles or die "ERROR: cannot make tile output directory ${outdir_tiles}! ($!)\n";
}
print " Output directory: ${outdir}\n" unless !$render_tiles and $no_xml;

my ($html_outdir, $html_outdir_tiles);
unless ($no_xml) {
    $html_outdir = $args{'-h'};
    die "ERROR: you must provide an HTML path!" if !$html_outdir;
    $html_outdir_tiles = "${html_outdir}/tiles/${landmark_name}/";
}

print
    "-------------------------------------------------------------------------\n";

my @track_labels = ('ruler', $CONFIG->labels); # get all the labels (i.e. tracks) possible, add the genomic ruler track
my $num_tracks = @track_labels; 

print
    " Numbered track labels (from '.conf' file):\n",
    " ";
for (my $num = 1; $num <= $num_tracks; $num++) {
    print "  ($num) $track_labels[$num-1]";  # subtract 1 for 0-based array indexing
}
print "\n";

# get the zoom levels from the '.conf' file
my @zooms_from_config = split(" ", $CONFIG->setting('zoom levels'));

# parse zoom levels into an internal format, which is an array of references where each reference
# is to a sub-array that lists:
#  - the name of the zoom level,
#  - the resolution in bases per 1000 pixels, and
#  - units to use for major tick marks in the genomic ruler (see %UNITS hack in 'arrow.pm'!!!)
# and also into a hash form, so we can use the first of the above as a key to get the latter two values
my (@zoom_levels, %zoom_levels);
my ($unit, $suffix, $divisor) = ('bp', '', '1');
my %suffices = (1e3 => 'k', 1e6 => 'M', 1e9 => 'G', 1e12 => 'T', 1e15 => 'P', 1e18 => 'E');  # should be enough

foreach my $zoom (sort {$a <=> $b} @zooms_from_config) {
    last if $zoom >= $landmark_length;  # there's no point in having zoom levels this large
    ($suffix, $divisor) = ('', 1);
    my @sorted_keys = sort {$a <=> $b} keys %suffices;
    for (my $i = 0; $zoom >= $sorted_keys[$i]; $i++) {  # look up which units to use in the suffix
	$divisor = $sorted_keys[$i];
	$suffix = $suffices{$divisor};
    }
    
    my $zoom_level_name = $zoom / $divisor . $suffix . $unit;
    push @zoom_levels, [$zoom_level_name, $zoom, $suffix];

    $zoom_levels{$zoom_level_name} = [$zoom, $suffix];
}

push @zoom_levels, ['entire_landmark', $landmark_length, $suffix];  # add zoom level for viewing the whole landmark
$zoom_levels{'entire_landmark'} = [$landmark_length, $suffix];

my $default_zoom_level_name = $zoom_levels[-1][0];    # default to the largest zoom level available
my @zoom_level_names = map { $_->[0] } @zoom_levels;  # get our processed results for SORTED output to user

my $num_zooms = @zoom_level_names;
print
    " Numbered zoom levels:\n",
    " ";
for (my $num = 1; $num <= $num_zooms; $num++) {
    print "  ($num) $zoom_level_names[$num-1]";
}
print "\n";

print
    " There are $num_tracks tracks, $num_zooms zoom levels total\n",
    "-------------------------------------------------------------------------\n";

# parse the "maximum zoom level to print labels for" parameter (eventually, we will make this determination
# automatic, but for now... !!!)
my $max_label_zoom = exists $args{'-z'} ? int($args{'-z'}) : $num_zooms;
die "ERROR: -z parameter is out of allowed range 1 to ${num_zooms}! (you specified $max_label_zoom)\n"
    if ($max_label_zoom < 1) or ($max_label_zoom > $num_zooms);

# build a hash of hashes of tuples (arrays) storing the range of tiles that are going to be printed for
# each track and zoom level combination; initialize this to print everything, which may be overridden
# later if user sets the '-r' option(s); hash is keyed by track name and zoom level name as they appear
# in @track_labels and @zoom_level_names
my %tile_ranges_to_render;
foreach my $track (@track_labels) {                    # go through each track...
    foreach my $zoom_level_name (@zoom_level_names) {  # ...and each zoom level, save maximum range of tiles
	$tile_ranges_to_render{$track}{$zoom_level_name} = [1, ceiling($landmark_length / $zoom_levels{$zoom_level_name}->[0])];
    }
}

my $print_tile_nums = 1 if exists $args{'--print-tile-nums'};

my %print_track_and_zoom;  # keeps track of any tracks and zoom levels that we should flat-out ignore;
                           # keys to the hash are as they appear in @track_labels and @zoom_level_names
if (exists $args{'-r'}) {
    my @subsets = split(',', $args{'-r'});

    if (@subsets == 0) {
	die "ERROR: you did not specify any subsets after the '-r' parameter!\n";
    }

    foreach my $subset (@subsets) {
	unless ($subset =~ /t(\d+)z(\d+)r(\d+)-(\d+)/) {
	    die "ERROR: malformed subset specification ($subset) after the '-r' parameter!\n";
	}
	my ($track_num, $zoom_level_num, $first_tile, $last_tile) = ($1, $2, $3, $4);
	my ($max_lower_bound, $max_upper_bound) =
	    ($tile_ranges_to_render{$track_labels[$track_num-1]}{$zoom_level_names[$zoom_level_num-1]}->[0],
	     $tile_ranges_to_render{$track_labels[$track_num-1]}{$zoom_level_names[$zoom_level_num-1]}->[1]);
	
	# do some correctness checks to prevent trouble
	die "ERROR: you can't have an upper bound that is smaller than the lower bound in your range specification ($subset)!\n"
	    if ($last_tile < $first_tile);
	die "ERROR: track number in subset specification ($subset) is out of range! (tracks are numbered from 1 to $num_tracks)\n"
	    if ( ($track_num > $num_tracks) || ($track_num < 1) );
	die "ERROR: zoom level number in subset specification ($subset) is out of range! (tracks are numbered from 1 to $num_zooms)\n"
	    if ( ($zoom_level_num > $num_zooms) || ($zoom_level_num < 1) );
	die
	    "ERROR: tile number range in subset specification ($subset) is out of max allowed range ",
	    "(which is $max_lower_bound to $max_upper_bound tiles for this track and zoom level)!\n"
	    if ( ($first_tile < $max_lower_bound) || ($last_tile > $max_upper_bound) );
	
	# record that we are printing the subset
	$print_track_and_zoom{$track_labels[$track_num-1]}{$zoom_level_names[$zoom_level_num-1]} = 1;
	
	# record the range that we are printing (overwrite old range)
	$tile_ranges_to_render{$track_labels[$track_num-1]}{$zoom_level_names[$zoom_level_num-1]}->[0] = $first_tile;
	$tile_ranges_to_render{$track_labels[$track_num-1]}{$zoom_level_names[$zoom_level_num-1]}->[1] = $last_tile;
    }
} else {
    # no subset specified, so we print EVERYTHING
    foreach my $track (@track_labels) {
	foreach my $zoom_level_name (@zoom_level_names) {
	    $print_track_and_zoom{$track}{$zoom_level_name} = 1;
	}
    }
}

if ($print_tile_nums) {  # output track names, zoom level names, and tile ranges
    if (exists $args{'-r'}) {
	print " The script will be applied to the following tiles:\n";
    } else {
	print " The script will be applied to ALL tiles:\n";
    }
    my $track_num = 1;
    foreach my $track (@track_labels) {
	my $zoom_level_num = 1;
	foreach my $zoom_level_name (@zoom_level_names) {
	    print
		"   track $track_num ($track) zoomlevel $zoom_level_num (", $zoom_levels{$zoom_level_name}->[0], ")",
		" firsttile ", $tile_ranges_to_render{$track}{$zoom_level_name}->[0],
	        " lasttile ", $tile_ranges_to_render{$track}{$zoom_level_name}->[1], "\n"
		if $print_track_and_zoom{$track}{$zoom_level_name};
	    $zoom_level_num++;
	}
	$track_num++;
    }
    print "-------------------------------------------------------------------------\n";
}

exit if $exit_early;  # bail out if the user just wanted results of parsing the '.conf' file

# start generating the XML file
unless ($no_xml) {
    print XMLFILE
	"<?xml version=\"1.0\"?>\n",
	"<settings>\n",
	"  <defaults zoomlevelname=\"${default_zoom_level_name}\" />\n",
	"  <landmark name=\"${source_name}\" start=\"${landmark_start}\" end=\"${landmark_end}\" id=\"${landmark_name}\" />\n",
	"  <tile width=\"${tilewidth_pixels}\" />\n";
}

## Render the genomic ruler for all zoom levels

my $ruler_dir = "${outdir_tiles}/ruler";
unless (-e $ruler_dir || !$render_tiles) {
  mkdir $ruler_dir or die "ERROR: problem with output directory ${outdir_tiles}! ($!)\n";
}

my $html_ruler_dir = "${html_outdir_tiles}/ruler" unless $no_xml;

foreach my $zoom_level (@zoom_levels) {
    my $zoom_level_name = $zoom_level->[0];

    next unless $print_track_and_zoom{'ruler'}{$zoom_level_name};  # skip zoom levels we're not filling or rendering

    my $tilewidth_bases = $zoom_level->[1];

    my $num_tiles = ceiling($landmark_length / $tilewidth_bases) + 1;  # 1 extra tile for the overrun
    my $image_width = ceiling($tilewidth_pixels * $landmark_length / $tilewidth_bases);  # in pixels

    $CONFIG->width ($image_width);  # set image width (in pixels) - necessary?

    warn "----- GENERATING RULER TRACK AT ZOOM LEVEL $zoom_level_name... -----\n" if $verbose;

    # check/create output dir here, to pass to BatchTiledImage... IH 4/11/2006
    my $current_ruler_dir = "${ruler_dir}/${zoom_level_name}/";
    if ($render_tiles and !(-e $current_ruler_dir)) {
      mkdir $current_ruler_dir or die "ERROR: could not make ${current_ruler_dir}!\n";
    }
    my $tile_prefix = "${current_ruler_dir}/rulertile";
    my $tiledimage_name = join ('__', $landmark_name, 'ruler', $zoom_level_name);

    ## Construct fake GD (i.e. BatchTiledImage) object; how to do this depends on whether
    ## the graphics primitives are already in the database or not

    # TODO: safety check to make sure -primdb is specified if we're using existing primitives?

    my ($ruler_fake_gd, $track_height);
    my %tiledImageArgs = (
	# args to BatchTiledImage constructor
	-renderTiles => $render_tiles,
	-firstTile => $tile_ranges_to_render{'ruler'}{$zoom_level_name}->[0] - 1,  # NB change from 1-based to 0-based coords
	-lastTile  => $tile_ranges_to_render{'ruler'}{$zoom_level_name}->[1] - 1,  # NB change from 1-based to 0-based coords
	-tileWidth => $tilewidth_pixels,
	-renderWidth => $rendering_tilewidth,
	-tilePrefix => $tile_prefix,

	# args to TiledImage constructor
	-persistent => $persistent,
	-verbose => $verbose,
	-primdb => $primdb,
	-tiledimage_name => $tiledimage_name,
    );

    if ($fill_database) {
      # create our clone of 'Panel.pm' that returns pseudo-GD::Image objects
      my $ruler_panel =
          TiledImagePanel->new (
		-start => $landmark_start,
		-end => $landmark_end,
		-stop => $landmark_end,  # backward compatability with old BioPerl
		-bgcolor => $CONFIG->setting('detail bgcolor') || 'white',
		-width => $image_width,
		-grid => $render_gridlines,
		-gridcolor => 'linen',
		-key_style => 'none',  # don't want no key
		-empty_tracks => $conf->setting(general => 'empty_tracks') || 'key',
		-pad_top => 0,  # probably 0 by default, but we will specify just in case
		-pad_left => 0,
		-pad_right => $tilewidth_pixels,  # to accomodate for stuff overruning borders of last tile
          );

      # add genomic ruler (i.e. arrow segment); there is a description of the track options at the end of:
      #   /usr/local/share/perl/5.8.4/Bio/Graphics/Glyph/arrow.pm (for a default BioPerl installation) - NOTE THAT IT IS HACKED !!!
      $ruler_panel->add_track (
			       $segment => 'arrow',
			       # double-headed arrow:
			       -double => 1,

			       # draw major and minor ticks:
			       -tick => 2,

			       # if we ever want unit labels, we may want to bring this back into action...!!!
			       #-units => $conf->setting(general => 'units') || '',
			       -unit_label => '',

			       # if we ever want unit dividers to be loaded from $conf, we'll have to use
			       # the commented-out option below, instead of hardcoding...!!!
			       #-unit_divider => $conf->setting(general => 'unit_divider') || 1,
			       #-unit_divider => 1,

			       # forcing the proper unit use for major tick marks
			       -units_forced => $zoom_level->[2]
			      );

      $ruler_fake_gd = $ruler_panel->gd (%tiledImageArgs);
      $track_height = $ruler_panel->height;
    }
    else {
      # if we're not filling database, primitives must be there already, so just create a
      # pseudo-GD::Image object through which to fetch them
      $ruler_fake_gd = BatchTiledImage->new (%tiledImageArgs);
      $track_height = $ruler_fake_gd->height;
    }

    $ruler_fake_gd->renderAllTiles if $render_tiles;
    $ruler_fake_gd->finish;  # clean up

    # if we got this far with no fatal error, we can print info about this track to XML file
    print XMLFILE ("  <ruler tiledir=\"${html_ruler_dir}/\" height=\"${track_height}\" />\n") unless $no_xml;
}

# Render the genomic tiles for all tracks and zoom levels
print XMLFILE "  <tracks>\n" unless $no_xml;

# iterate over tracks (i.e. labels)
for (my $label_num = 0; $label_num < @track_labels; $label_num++)
{
    next if ($track_labels[$label_num] eq 'ruler');  # skip ruler, we render it above

    my $label = ($track_labels[$label_num]);
    my %track_properties = $conf->style($label);
    my $track_name = $track_properties{"-key"};

    # sometimes the track name is unspecified, so use the label instead
    $track_name = $label unless $track_name;

    print XMLFILE "    <track name=\"${track_name}\">\n" unless $no_xml;

    warn "=== GENERATING TRACK $label ($track_name)... ===\n" if $verbose;

    # get feature types in form suitable for Bio::DB::GFF
    my @feature_types = $conf->label2type($label, $landmark_length);

    my $lang = $CONFIG->language;

    # iterate over zoom levels
    my $zoom_level_num = 0;
    foreach my $zoom_level (@zoom_levels) {
    	$zoom_level_num++;
	my $zoom_level_name = $zoom_level->[0];

        next unless $print_track_and_zoom{$label}{$zoom_level_name};  # skip if not printing

	my $tilewidth_bases = $zoom_level->[1] * $tilewidth_pixels / 1000;
	my $num_tiles = ceiling($landmark_length / $tilewidth_bases) + 1;  # give it an extra tile for a temp half-assed fix
	my $image_width = ceiling($tilewidth_pixels * $landmark_length / $tilewidth_bases);  # in pixels

	# I'm really not sure how palatable setting this option here will be... but we can't
	# set it any earlier...
	$CONFIG->width($image_width);  # set image width (in pixels)

	warn "----- GENERATING ZOOM LEVEL ${zoom_level_name}... -----\n" if $verbose;

	# create the track that we will need

	# replace spaces and slashes in track name with underscores for writing file path prefixes
	my $track_name_underscores = $track_name;
	$track_name_underscores =~ s/[ \/]/_/g;

	# make output directories
	my $current_outdir = "${outdir_tiles}/${track_name_underscores}/";
	unless (-e $current_outdir || !$render_tiles) {
	    mkdir $current_outdir or die "ERROR: problem making output directory ${current_outdir}! ($!)\n";
	}
	my $html_current_outdir = "${html_outdir_tiles}/${track_name_underscores}/" unless $no_xml;

	$current_outdir = "${current_outdir}/${zoom_level_name}/";
	unless (-e $current_outdir || !$render_tiles) {
	    mkdir $current_outdir or die "ERROR: problem making output directory ${current_outdir} ($!)\n";
	}

	$html_current_outdir = "${html_current_outdir}/${zoom_level_name}/" unless $no_xml;

	my $tile_prefix = "${current_outdir}/tile";
	my $tiledimage_name = join ('__', $landmark_name, $track_name_underscores, $zoom_level_name);

	## Construct fake GD (i.e. BatchTiledImage) object; how to do this depends on whether
	## the graphics primitives are already in the database or not

	# TODO: safety check to make sure -primdb is specified if we're using existing primitives?

	my ($fake_gd, $track_height);
	my %tiledImageArgs = (
		# args to BatchTiledImage constructor
		-renderTiles => $render_tiles,
		-firstTile => $tile_ranges_to_render{$label}{$zoom_level_name}->[0] - 1,  # NB change from 1-based to 0-based coords
		-lastTile  => $tile_ranges_to_render{$label}{$zoom_level_name}->[1] - 1,  # NB change from 1-based to 0-based coords
		-tileWidth => $tilewidth_pixels,
		-renderWidth => $rendering_tilewidth,
		-tilePrefix => $tile_prefix,
		-htmlOutdir => $html_current_outdir,

		# args to TiledImage constructor
		-persistent => $persistent,
		-verbose => $verbose,
		-trackNum => $label_num,
                -primdb => $primdb,
		-tiledimage_name => $tiledimage_name
	);

	if ($fill_database) {
	  # create our clone of 'Panel.pm' that returns pseudo-GD::Image objects
	  my $panel =
	      TiledImagePanel->new (
	            -start => $landmark_start,
		    -end => $landmark_end,
		    -stop => $landmark_end,  # backward compatability with old BioPerl
		    -key_color => $CONFIG->setting('key bgcolor') || 'moccasin',
		    -bgcolor => $CONFIG->setting('detail bgcolor') || 'white',
		    -width => $image_width,
		    -grid => $render_gridlines,
		    -gridcolor => 'linen',
		    -key_style => 'none',  # we don't want no key, client will render that for us
		    -empty_tracks => $conf->setting(general => 'empty_tracks') || 'key',
		    -pad_top => 0,  # padding is probably 0 by default, but we will specify just in case
		    -pad_left => 0,
		    -pad_right => $tilewidth_pixels,  # to accomodate overrun of elements in "last" tile
		    -image_class => 'GD'
	      );

	  # if the glyph is the magic "dna" glyph (for backward compatibility), or if the section
	  # is marked as being a "global feature", then we apply the glyph to the entire segment
	  my $track;
	  if ($conf->setting($label=>'global feature')) {
	    $panel->add_track($segment,
			      $conf->default_style,
			      $conf->i18n_style($label,$lang),
			     );
	  }
	  else {
	    my @settings = ($conf->default_style, $conf->i18n_style($label, $lang, $landmark_length));
	    $track = $panel->add_track(-glyph => 'generic', @settings);  # $track is a Bio::Graphics::Glyph::track object
	  }

	  # go through all the features and add them (but only if we have features)
	  if (@feature_types) {
	    my $iterator = $segment->get_feature_stream(-type => \@feature_types);

            while (my $feature = $iterator->next_seq) {
	      warn " adding feature ${feature}...\n" if $verbose == 2;
	      $track->add_feature($feature);
	    }

	    # configure the tracks (does this need to be done if tracks are global features?)
	    my $count = 1;
	    my $do_bump = $CONFIG->do_bump($label, 0, $count, $CONFIG->bump_density);
	    my $do_label = $CONFIG->do_label($label, 0, $count, $CONFIG->label_density, $landmark_length);
	    my $do_description =
		$CONFIG->do_description($label, 0, $count, $CONFIG->label_density, $landmark_length);

	    if ($zoom_level_num <= $max_label_zoom) {
	        $track->configure(-bump => $do_bump, -label => $do_label, -description => $do_description);
	    } else {
	        $track->configure(-bump => 0, -label => 0, -description => 0);
	    }
	  }

	  my $boxes = $panel->boxes;
	  $fake_gd = $panel->gd (%tiledImageArgs, -annotate => $boxes);
	  $track_height = $panel->height;
	}
	else {
	  # if we're not filling database, primitives must be there already, so just create a
	  # pseudo-GD::Image object through which to fetch them
	  $fake_gd = BatchTiledImage->new (%tiledImageArgs);
	  $track_height = $fake_gd->height;
	}

	$fake_gd->renderAllTiles if $render_tiles;
	$fake_gd->finish;  # clean up

	# if we got this far with no fatal error, we can print info about this track to XML file
	print XMLFILE
	    "      <zoomlevel tileprefix=\"${html_current_outdir}\" name=\"${zoom_level_name}\" ",
	    "unitspertile=\"${tilewidth_bases}\" height=\"${track_height}\" numtiles=\"${num_tiles}\" />\n"
	    	unless ($no_xml);

    } # ends loop iterating through zoom levels

    print XMLFILE "    </track>\n" unless $no_xml;

}  # ends the 'for' loop iterating through @track_labels

unless ($no_xml) {
    print XMLFILE "  </tracks>\n";
    print XMLFILE "  <classicurl url=\"http://genome.biowiki.org/cgi-bin/gbrowse\" />\n";  # TEMP INFO FOR DEMO TO LINK TO CLASSIC GBROWSE !!!
    print XMLFILE "</settings>\n";  # close out XML file
    close(XMLFILE);
}

exit;

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

sub print_usage {
    print
	"USAGE:\n",
	"  generate-tiles.pl -l <landmark> [-c <config dir>] [-o <output dir>]\n",
	"                    [-h <HTML path>] [-s <source>] [-m <mode>]\n",
	"                    [-p <persistent>] [-v <verbose>] [-r <selection>]\n",
	"                    [-z <zoom level number>]",
	"                    [--exit-early] [--print-tile-nums] [--no-xml]\n",
	"                    [--render-gridlines]\n",
	"where the options are:\n",
	"  -l <landmark>\n",
	"        name of landmark you want to render\n",
	"  -c <config dir>\n",
	"        directory containing browser and track info in the '.conf' file\n",
	"        (default is '${default_confdir}')\n",
	"  -o <output directory>\n",
	"        directory to which '${xmlfile}' and the 'tiles' directory will be\n",
	"        written to (default is '${default_outdir}')\n",
	"  -h <HTML path>\n",
	"        complete HTML path to the location that will contain '${xmlfile}'\n",
	"        and the 'tiles' directory for your genome\n",
	"  -s <source>\n",
	"        source of configuration info in <config dir> (is there is more than\n",
	"        one '.conf' file)\n",
	"  -m <mode>\n",
	"        specifies what you want this script to do:\n",
	"          0 = fill database with GD primitives, render tiles, generate XML\n",
	"              file (default)\n",
	"          1 = fill database with GD primitives and generate XML file only\n",
	"          2 = render tiles and generate XML file only ('gdtile' MySQL database\n",
	"              must be filled already)\n",
	"          3 = do nothing except generate XML file and dump info\n",
	"  -p <persistent>\n",
	"        sets whether GD primitives get deleted from MySQL 'gdtile' database at\n",
	"        end of execution:\n",
	"          0 = delete primitives\n",
	"          1 = keep primitives (default)\n",
	"  -primdb <dsn>\n",
	"        optional parameter to use a database to store graphical\n",
	"        primitives.  Slower, but uses less memory and allows for\n",
	"        rendering on demand.\n",
	"        example: -primdb DBI:mysql:gdtile\n",
	"  -v <verbose>\n",
	"        sets whether to run in verbose mode (that is, output activities of the\n",
	"        program's internals to standard error):\n",
	"          0 = verbose off (default)\n",
	"          1 = verbose on (regular)\n",
	"          2 = verbose on (extreem - prints trace of every instance of\n",
	"              recording or replaying database primitives and of every tile\n",
	"              that is rendered - WARNING, VERY VERBOSE!)\n",
	"  -r <selection>\n",
	"        Use this to render only a subset of all possible tiles, tracks and\n",
	"        zoom levels (default is render ALL tiles); note that CURRENTLY, the\n",
	"        RANGE part of this option DOES NOT apply to loading the database with\n",
	"        primitives or generating the XML file - i.e you can select which\n",
	"        tracks and zoom levels to load into database or write to XML file with\n",
	"        this, but NOT which tile ranges, since the range feature works for\n",
	"        RENDERING only.\n",
	"\n",
	"        <selection> is a comma-delimited concatenation (no whitespace) of any\n",
	"        number of strings of the form:\n",
	"          t<track number>z<zoom level number>r<tile number range>\n",
	"        where <tile number range> is in the form:\n",
	"          <start>-<end>\n",
	"        and <track number>, <zoom level number>, and the full range of tiles\n",
	"        for each track and zoom level can be obtained by running this script\n",
	"        with the --print-tile-nums option (ALSO: please specify only ONE range\n",
	"        per track and zoom level combination!)\n",
	"\n",
	"        EXAMPLE: t1z5r100-500,t2z5r100-500 (print tiles 100 through 500,\n",
	"                                            inclusive, for tracks 1 and 2,\n",
	"                                            zoom level 5)\n",
	"  -z <zoom level number>\n",
	"        the zoom level above which we will not print feature labels, as\n",
	"        feature labels can get very dense when we zoom out and clutter the\n",
	"        view; eventually, this will be set automatically, but is hardcoded\n",
	"        for now... zoom level numbers can be obtained with by running with\n",
	"        the --print-tile-nums parameter\n",
	"  --exit-early\n",
	"        a debug option; when enabled, the script exits after loading and\n",
	"        outputting database info, but before doing anything else\n",
	"  --print-tile-nums\n",
	"        print how many tiles will be in each track at each zoom level (useful\n",
	"        for getting tile ranges for '-r' option)\n",
	"  --no-xml\n",
	"        do not generate the XML file in any of the modes\n",
	"  --render-gridlines\n",
	"        render gridlines (default is do not render gridlines, since it\n",
	"        increases the rendering time)\n",
	"\n",
	"Use global paths everywhere for the least surprises.\n";
    
    exit 0;
}
