package TileGenerator;
use strict;
use Bio::Graphics::Panel;
use Digest::MD5 qw(md5);
use POSIX;

# max number of hardlinks to a single file, minus some margin
use constant MAX_LINKS => 30000;

# We render large tiles and then break them up into smaller tiles;
# this is the number of smaller tiles in each large tile
my $small_per_large = 128;

# amount of extra space on the ends of large tiles
# this gets left out when we copy out the small tiles
my $global_padding = 100; #pixels

sub new {
    my ($class, %args) = @_;

    my $self = {
        'px_per_tile' => $args{-tilewidth_pixels},
    };
    
    bless $self, $class;
    return $self;
}

sub px_per_tile { shift->{px_per_tile}; }

# method to render a range of tiles
# NB tiles used 0-based indexing
sub renderTileRange {
    my ($self,
        $first_tile,
        $last_tile,
        $db,
        $landmark_name,
        $tile_prefix,
        $is_global,
        $big_panel,
        $big_track,
        $panel_args,
        $track_settings,
        $tile_callback) = @_;

    my $image_height = $big_panel->height;

    my $rendering_tilewidth = $self->px_per_tile * $small_per_large;

    my $first_large_tile = floor($first_tile / $small_per_large);
    my $last_large_tile = ceil($last_tile / $small_per_large);

    my $total_featsize = 0;
    my $num_feats = 0;
    
    # @per_tile_glyphs is a list with one element per rendering tile,
    # each of which is a list of the glyphs that overlap that tile.
    my @per_tile_glyphs;
    if (!$is_global) {
        foreach my $glyph ($big_track->parts) {
            my @box = $glyph->box;
            my @rtile_indices =
                floor($box[0] / $rendering_tilewidth)
                ..ceil($box[2] / $rendering_tilewidth);

            foreach my $rtile_index (@rtile_indices) {
                push @{$per_tile_glyphs[$rtile_index]}, $glyph;
            }
        }
    }

    my $blankTile;
    my $linkCount = 0;
    my (%tileHash, %tileLinkCount);

    local *TILE;
    for (my $x = $first_large_tile; $x <= $last_large_tile; $x++) {
        my $large_tile_gd;
        my $pixel_offset = (0 == $x) ? 0 : $global_padding;

        if ($linkCount > MAX_LINKS) {
            undef $blankTile;
            $linkCount = 0;
        }

        # we want to skip rendering whole tile if it's blank, but only if
        # there's a blank tile to which to hardlink that's already rendered
        if (defined($per_tile_glyphs[$x]) || (!defined($blankTile))) {

            # rendering tile bounds in pixel coordinates
            my $rtile_left = ($x * $rendering_tilewidth) 
		- $pixel_offset;
            my $rtile_right = (($x + 1) * $rendering_tilewidth)
		+ $global_padding - 1;

            # rendering tile bounds in bp coordinates
            my $first_base = int($rtile_left / $big_panel->scale) + $big_panel->start;
            my $last_base = int(($rtile_right + 1) / $big_panel->scale) + $big_panel->start - 1;

            if (($big_panel->start == $first_base)
                && ($last_base > $big_panel->end)) {
                $big_panel->{gd} = undef;
                $large_tile_gd = $big_panel->gd();
            } else {
                # set up the per-rendering-tile panel, with the right
                # bp coordinates and pixel width
                my %tpanel_args = %$panel_args;
                $tpanel_args{-start} = $first_base;
                $tpanel_args{-end} = $last_base;
                $tpanel_args{-stop} = $last_base;
                $tpanel_args{-width} = $rtile_right - $rtile_left + 1;
                my $tile_panel = Bio::Graphics::Panel->new(%tpanel_args);
                my $scale_diff = $tile_panel->scale - $big_panel->scale;
                if (abs($scale_diff) > 1e-11) {
                    printf "scale difference: %e\n", $scale_diff;
                    print "big panel scale: " . $big_panel->scale . " big panel start: " . $big_panel->start . " big panel end: " . $big_panel->end . " big panel width: " . $big_panel->width . " small panel scale: " . $tile_panel->scale . " pixel_offset: $pixel_offset first_base: $first_base last_base: $last_base rtile_left: $rtile_left rtile_right: $rtile_right small panel width: " . $tile_panel->width . "\n";
                }

                if ($is_global) {
                    # for global features we can just render everything
                    # using the per-tile panel
                    # this arithmetic has been double checked
                    my @segments = 
                        $db->segment(-name => $landmark_name,
                                     -start => $first_base - $big_panel->start + 1,
                                     -end => $last_base - $big_panel->start + 1);
                    my $small_segment = $segments[0];
                    my $small_track;
                    if ($small_segment) {
                        $small_track = $tile_panel->add_track($small_segment,
                                                              @$track_settings);
                    } else {
                        $small_track = $tile_panel->add_track(@$track_settings);
                    }                        
                    if ($tile_panel->height < $big_panel->height) {
                        $tile_panel->pad_bottom($tile_panel->pad_bottom
                                                + ($big_panel->height
                                                   - $tile_panel->height));
                        $tile_panel->extend_grid(1);
                    }
                    $large_tile_gd = $tile_panel->gd();
                } else {
                    # add generic track to the tile panel, so that the
                    # gridlines have the right height
                    $tile_panel->add_track(-glyph => 'generic', 
                                           @$track_settings,
                                           -height => $image_height);
                    $large_tile_gd = $tile_panel->gd();
                    #print "got tile panel gd " . tv_interval($start_time) . "\n";
                    
                    if (defined $per_tile_glyphs[$x]) {
                        # some glyphs call set_pen on the big_panel;
                        # we want that to go to the right GD object
                        $big_panel->{gd} = $large_tile_gd;
                    
                        #move rendering onto the tile
                        $big_panel->pad_left(-$rtile_left);

                        # draw the glyphs for the current rendering tile
                        foreach my $glyph (@{$per_tile_glyphs[$x]}) {
                            # some positions are calculated
                            # using the panel's pad_left, and sometimes
                            # they're calculated using the x-coordinate
                            # passed into the draw method.  We want them
                            # both to be -$rtile_left.
                            $glyph->draw($large_tile_gd, -$rtile_left, 0);
                        }
                    }
                }
                $tile_panel->finished;
                $tile_panel = undef;
            }
        }

        # now to break up the large tile into small tiles and write them to PNG on disk...

        my @small_tile_boxes;
        foreach my $glyph (@{$per_tile_glyphs[$x]}) {
            my $box = [$glyph->feature, $glyph->box];
            my $first_small = floor($box->[1] / $self->px_per_tile);
            my $last_small = floor($box->[3] / $self->px_per_tile);
            my $small_begin = $x * $small_per_large;
            $first_small = $small_begin
                if $first_small < $small_begin;
            $last_small = ($small_begin + $small_per_large) - 1
                if $last_small > ($small_begin + $small_per_large) - 1;

            $first_small -= $small_begin;
            $last_small -= $small_begin;
            my @tile_indices = $first_small .. $last_small;

            foreach my $tile_index (@tile_indices) {
                push @{$small_tile_boxes[$tile_index]}, $box;
            }
        }

      SMALLTILE:
        for (my $y = 0; $y < $small_per_large; $y++) {
            my $small_tile_num = $x * $small_per_large + $y;
            if ( ($small_tile_num >= $first_tile)
                 && ($small_tile_num <= $last_tile) ) { # do we print it?

                my $outfile = "${tile_prefix}${small_tile_num}.png";
                &$tile_callback($tile_prefix, $small_tile_num,
                                $small_tile_boxes[$y]);

                if (!$is_global && !defined($small_tile_boxes[$y])) {
                    if (defined($blankTile)) {
                        link $blankTile, $outfile
                            || die "could not link blank tile: $!\n";
                        $linkCount++;
                        next SMALLTILE;
                    } else {
                        $blankTile = $outfile;
                    }
                }

                my $small_tile_gd = GD::Image->new($self->px_per_tile,
                                                   $image_height,
                                                   0);
                
                # can copy beyond panel width because of pad_right
                $small_tile_gd->copy($large_tile_gd,
                                     0, 0,
                                     $y * $self->px_per_tile + $pixel_offset, 0,
                                     $self->px_per_tile, $image_height);

                my $pngData = $small_tile_gd->png(4);
                if (!$is_global) {
                    # many tiles are identical (especially at high zoom)
                    # so we're not generating the tile if we've seen
                    # one with the same md5 already
                    # TODO: consider collisions in more depth (sha1?)
                    # ideally we'd compare the actual image data if
                    # the hash matches (to catch hash collisions), but
                    # that would mean either keeping the image data in memory
                    # (memory hog) or reading it off the disk (slow)
                    # TODO: measure memory/IO cost of those options
                    my $imageHash = md5($pngData);

                    if ($tileHash{$imageHash}) {
                        if ($tileLinkCount{$imageHash} > MAX_LINKS) {
                            $tileLinkCount{$imageHash} = 0;
                            undef $tileHash{$imageHash};
                        } else {
                            link $tileHash{$imageHash}, $outfile;
                            $tileLinkCount{$imageHash} += 1;
                            next SMALLTILE;
                        }
                    } else {
                        $tileHash{$imageHash} = $outfile;
                        $tileLinkCount{$imageHash} = 1;
                    }
                } else {
                    $small_tile_boxes[$y] = undef;
                }

                open (TILE, ">${outfile}")
                    or die "ERROR: could not open ${outfile}!\n";
                print TILE $pngData
                    or die "ERROR: could not write to ${outfile}!\n";
            }
        }
    }
}

return 1;
