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
use FindBin;
use lib $FindBin::Bin . "/../lib/";
use Bio::DB::GFF;
use Bio::Graphics;
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Util;
use GD::SVG;                       # this may be necessary later !!!
use Bio::Graphics::Panel;
use Data::Dumper;
use Carp 'croak','cluck';
use Time::HiRes qw( gettimeofday tv_interval );
use XML::DOM;
use Fcntl qw( :flock :seek );
use AjaxTileGenerator;
use POSIX;

my $start_time = [gettimeofday];

# --- BEGIN MANUAL PARAMETER SPECIFICATIONS ---
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

my ($verbose);  # these get passed to TiledImage

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

# note that @segments should always be a 1-element array, since we are
# forcing only one landmark per script execution and we are considering
# the ENTIRE landmark
# this should return the range of the entire landmark
#my @segments = $CONFIG->name2segments($landmark_name, $db, 0, 0);
my @segments = $db->segment(-name => $landmark_name);
my $segment = $segments[0];

#$Data::Dumper::Maxdepth = 2;
#print "segs: " . Dumper(@segments) . "\n";

die "ERROR: problem loading landmark! (are you sure the name is correct? you provided: ${landmark_name})\n"
    if !$segment;

# get landmark dimensions
my ($landmark_start, $landmark_end, $landmark_length) = ($segment->start, $segment->end, $segment->length);
my $landmark = "${landmark_name}:${landmark_start}..${landmark_end}";

print
    " Landmark: ${landmark} (${source_name})\n",
    " Landmark length: ${landmark_length} bases\n";

# NB: the following paths are landmark specific
# (TODO: when we implement looping over multiple landmarks,
# the following will have to be in the loop body)

my $outdir_tiles = "${outdir}/tiles/";
unless (-e $outdir_tiles || !$render_tiles) {
    mkdir $outdir_tiles or die "ERROR: cannot make tile output directory ${outdir_tiles}! ($!)\n";
}
$outdir_tiles .= "${landmark_name}/";  # append landmark-specific subdir
unless (-e $outdir_tiles || !$render_tiles) {
    mkdir $outdir_tiles or die "ERROR: cannot make tile output directory ${outdir_tiles}! ($!)\n";
}
print " Output directory: ${outdir}\n" unless !$render_tiles and $no_xml;

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

push @zoom_levels, ['entire_landmark', $landmark_length, "M"];  # add zoom level for viewing the whole landmark
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

# threshold of the average number of features per tile
# above which we won't print labels
my $label_thresh = $args{'-p'} || 50;

# threshold of the average number of features per tile
# above which we switch to a density histogram
my $hist_thresh = $args{'-d'} || 300;

# build a hash of hashes of tuples (arrays) storing the range of tiles that are going to be printed for
# each track and zoom level combination; initialize this to print everything, which may be overridden
# later if user sets the '-r' option(s); hash is keyed by track name and zoom level name as they appear
# in @track_labels and @zoom_level_names
my %tile_ranges_to_render;
foreach my $track (@track_labels) {                    # go through each track...
    foreach my $zoom_level_name (@zoom_level_names) {  # ...and each zoom level, save maximum range of tiles
        $tile_ranges_to_render{$track}{$zoom_level_name} = [1, ceil($landmark_length / ($zoom_levels{$zoom_level_name}->[0] * ($tilewidth_pixels / 1000)))];
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
} elsif (exists $args{'-t'}) {
    my @tracklist = map {$_ - 1} split(",", $args{'-t'});
    foreach my $zoom_level_name (@zoom_level_names) {
        foreach my $track (@tracklist) {
            $print_track_and_zoom{$track_labels[$track]}{$zoom_level_name} = 1;
        }
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
    } elsif (exists $args{'-t'}) {
        print " The script will be applied to track " . $args{'-t'} . ": " . $track_labels[$args{'-t'} - 1] . "\n";
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

my $log = sub {
    my ($message, $level) = @_;
    warn "$message: " . tv_interval($start_time) . "\n" if ($verbose >=$level);
};

unless ($no_xml) {
    my $xml = new IO::File;
    $xml->open("${outdir}/${xmlfile}", O_RDWR | O_CREAT)
      or die "ERROR: cannot open '${outdir}/${xmlfile}' ($!)\n";
    flock($xml, LOCK_EX)
      or die "couldn't lock XML: $!";
    my $doc;
    if (-z "${outdir}/${xmlfile}") {
        $doc = initXml($default_zoom_level_name, $source_name,
                       $segment->start, $segment->end,
                       $landmark_name, $tilewidth_pixels, $source);
        $xml->print($doc->toString . "\n") or die "couldn't write XML: $!";
    }
    $xml->close or die "couldn't close XML: $!";
}

# iterate over tracks (i.e. labels)
for (my $label_num = 0; $label_num < @track_labels; $label_num++)
{
    my $label = ($track_labels[$label_num]);

    next unless $print_track_and_zoom{$label};

    my $image_height;
    my $track_name;
    my @feature_types;
    my @features;

    if ($label ne 'ruler') {
        my %track_properties = $conf->style($label);
        $track_name = $track_properties{"-key"};

        # get feature types in form suitable for Bio::DB::GFF
        @feature_types = $conf->label2type($label, $landmark_length);
        @features = $segment->features(-type => \@feature_types)
          if (@feature_types);
    }

    # sometimes the track name is unspecified, so use the label instead
    $track_name = $label unless $track_name;

    my $atg = new AjaxTileGenerator(-tilewidth_pixels => $tilewidth_pixels,
                                    -segment          => $segment,
                                    -features         => \@features,
                                    -browser          => $CONFIG,
                                    -browser_config   => $conf,
                                    -xmlpath          => "${outdir}/${xmlfile}",
                                    -render_gridlines => $render_gridlines,
                                    -db               => $db,
                                    -source_name      => $source_name
                                   );

    &$log("=== GENERATING TRACK $label ($track_name)... ===", 1);

    my $lang = $CONFIG->language;

    # iterate over zoom levels
    foreach my $zoom_level (reverse(@zoom_levels)) {
	my $zoom_level_name = $zoom_level->[0];

        next unless $print_track_and_zoom{$label}{$zoom_level_name};  # skip if not printing

        &$log("----- GENERATING ZOOM LEVEL ${zoom_level_name}... ----- ", 1);

        my @track_settings = ($conf->default_style, $conf->i18n_style($label, $lang, $segment->length));

        $atg->renderTrackZoom($zoom_level,
                              \@track_settings,
                              $log,
                              $render_tiles,
                              # NB change from 1-based to 0-based coords
                              $tile_ranges_to_render{$label}{$zoom_level_name}->[0] - 1,
                              $tile_ranges_to_render{$label}{$zoom_level_name}->[1] - 1,
                              $no_xml,
                              $landmark_name,
                              $label,
                              $outdir_tiles
                             );

        &$log("tiles for track $label zoom $zoom_level_name rendered", 1)
          if $render_tiles;

    } # ends loop iterating through zoom levels
}  # ends the 'for' loop iterating through @track_labels

# sets multiple attributes on a given element
sub setAtts {
    my ($node, %atts) = @_;
    $node->setAttribute($_, $atts{$_}) foreach keys %atts;
    return $node;
}

sub initXml {
    my ($default_zoom_level_name, $source_name, 
        $landmark_start, $landmark_end, $landmark_name,
        $tilewidth_pixels, $source) = @_;
    my $doc = new XML::DOM::Document();
    $doc->setXMLDecl($doc->createXMLDecl("1.0"));
    my $root = $doc->appendChild($doc->createElement("settings"));
    my $config = setAtts($root->appendChild($doc->createElement("config")),
            "name" => $source_name);
    $config->appendChild($doc->createElement("defaults"))
        ->setAttribute("zoomlevelname", $default_zoom_level_name);
    $config->appendChild($doc->createElement("tile"))
        ->setAttribute("width", $tilewidth_pixels);
    $config->appendChild($doc->createElement("classicurl"))
        ->setAttribute("url", "http://128.32.184.78/cgi-bin/gbrowse/${source}/");
    return $doc;
}

sub print_usage {
    print <<ENDUSAGE;
USAGE
  generate-tiles.pl -l <landmark> [-c <config dir>] [-o <output dir>]
                    [-h <HTML path>] [-s <source>] [-m <mode>]
                    [-v <verbose>] [-r <selection>]
                    [-t <track list>]
                    [-d <density plot threshold>] [-p <label threshold>]
                    [--exit-early] [--print-tile-nums] [--no-xml]
                    [--render-gridlines]
where the options are:
  -l <landmark>
        name of landmark you want to render
  -c <config dir>
        directory containing browser and track info in the '.conf' file
        (default is '${default_confdir}')
  -o <output directory>
        directory to which '${xmlfile}' and the 'tiles' directory will be
        written to (default is '${default_outdir}')
  -s <source>
        source of configuration info in <config dir> (if there is more than
        one '.conf' file)
  -m <mode>
        specifies what you want this script to do:
          0 = fill database with GD primitives, render tiles, generate XML
              file (default)
          1 = fill database with GD primitives and generate XML file only
          2 = render tiles and generate XML file only ('gdtile' MySQL database
              must be filled already)
          3 = do nothing except generate XML file and dump info
  -v <verbose>
        sets whether to run in verbose mode (that is, output activities of the
        program's internals to standard error):
          0 = verbose off (default)
          1 = verbose on (regular)
          2 = verbose on (extreem - prints trace of every instance of
              recording or replaying database primitives and of every tile
              that is rendered - WARNING, VERY VERBOSE!)
  -t <track list>
        Specify the tracks to render (e.g. -t 1,2,3,4)
        default: render all tracks
  -r <selection>
        Use this to render only a subset of all possible tiles, tracks and
        zoom levels (default is render ALL tiles); note that CURRENTLY, the
        RANGE part of this option DOES NOT apply to loading the database with
        primitives or generating the XML file - i.e you can select which
        tracks and zoom levels to load into database or write to XML file with
        this, but NOT which tile ranges, since the range feature works for
        RENDERING only.

        <selection> is a comma-delimited concatenation (no whitespace) of any
        number of strings of the form:
          t<track number>z<zoom level number>r<tile number range>
        where <tile number range> is in the form:
          <start>-<end>
        and <track number>, <zoom level number>, and the full range of tiles
        for each track and zoom level can be obtained by running this script
        with the --print-tile-nums option (ALSO: please specify only ONE range
        per track and zoom level combination!)

        EXAMPLE: t1z5r100-500,t2z5r100-500 (print tiles 100 through 500,
                                            inclusive, for tracks 1 and 2,
                                            zoom level 5)
  -d <number of features>
        average number of features per tile above which we switch to a
        density histogram
        default: 200
  -p <number of features>
        average number of features per tile above which we won't print labels
        default: 50
  --exit-early
        a debug option; when enabled, the script exits after loading and
        outputting database info, but before doing anything else
  --print-tile-nums
        print how many tiles will be in each track at each zoom level (useful
        for getting tile ranges for '-r' option)
  --no-xml
        do not generate the XML file in any of the modes
  --render-gridlines
        render gridlines (default is do not render gridlines, since it
        increases the rendering time)

Use global paths everywhere for the least surprises.
ENDUSAGE
    
    exit 0;
}
