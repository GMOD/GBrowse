package AjaxTileGenerator;

use strict;
use Bio::Graphics::Panel;
use POSIX;
use Fcntl qw( :flock :seek );
use XML::DOM;
use base qw(TileGenerator);

# max number of hardlinks to a single file, minus some margin
use constant MAX_LINKS => 30000;

sub new {
    my ($class, %args) = @_;
    my $self = $class->SUPER::new(%args);
    $self->{segment} = $args{-segment};
    $self->{features} = $args{-features};
#   $self->{browser} = $args{-browser};
#   $self->{browser_config} = $args{-browser_config};
    $self->{xmlpath} = $args{-xmlpath};
    $self->{render_gridlines} = $args{-render_gridlines};
    $self->{db} = $args{-db};
#    $self->{source_name} = $args{-source_name};
    return $self;
}

sub segment { shift->{segment} }
sub features { shift->{features} }
#sub browser { shift->{browser} }
#sub browser_config { shift->{browser_config} }
sub xmlpath { shift->{xmlpath} }
sub render_gridlines { shift->{render_gridlines} }
sub db { shift->{db} }
#sub source_name { shift->{source_name} }

sub renderTrackZoom {
    my ($self, $zoom_level, $track_defaults, $log, $render_tiles,
        $first_tile, $last_tile, $no_xml, $landmark_name, $label,
        $outdir_tiles) = @_;

    my @features = @{$self->features};
    my @track_settings = @{$track_defaults};

    #my %track_properties = $self->browser_config->style($label);
    my %track_properties = @track_settings;
    my $track_key = $track_properties{"-key"} || $label;

    #print join ("\n", map { $_ . "=>" . $track_properties{$_} } keys %track_properties) . "\n";

    my $tilewidth_bases = $zoom_level->[1] * ($self->px_per_tile / 1000);
    # give it an extra tile for a temp half-assed fix
    my $num_tiles = ceil($self->segment->length / $tilewidth_bases) + 1;
    my $image_width = ($self->segment->length / $zoom_level->[1]) * 1000; # in pixels

    # replace spaces and slashes in track name with underscores for writing file path prefixes
    my $track_name_underscores = $label;
    $track_name_underscores =~ s/[ \/]/_/g;

    # make output directories
    my $current_outdir = "${outdir_tiles}/${track_name_underscores}";
    unless (-e $current_outdir || !$render_tiles) {
        mkdir $current_outdir or die "ERROR: problem making output directory ${current_outdir}! ($!)\n";
    }

    $current_outdir = "${current_outdir}/" . $zoom_level->[0] . "/";
    unless (-e $current_outdir || !$render_tiles) {
        mkdir $current_outdir or die "ERROR: problem making output directory ${current_outdir} ($!)\n";
    }

    my $html_outdir = "tiles/${landmark_name}/${track_name_underscores}/" . $zoom_level->[0] . "/";

    my $tile_prefix = "${current_outdir}/tile";
    $tile_prefix = "${current_outdir}/rulertile"
      if $label eq 'ruler';

    my $bump_density = int($track_properties{'-bump density'} || 300);
    my $label_density = int($track_properties{'-label density'} || 50);

    # I'm really not sure how palatable setting this option here will be...
    # but we can't set it any earlier...
    #$self->browser->width($image_width); # set image width (in pixels)

    my @argv = (-start => $self->segment->start,
                -end => $self->segment->end,
                 # backward compatability with old BioPerl
                -stop => $self->segment->end,
                -bgcolor => "",
                -width => $image_width,
                -grid => $self->render_gridlines,
                -gridcolor => 'linen',
                 # we don't want no key, client will render that for us
                -key_style => 'none',
                -empty_tracks => 'key',
                # padding is probably 0 by default,
                # but we will specify just in case
                -pad_top => 0,
                -pad_left => 0,
                # to accomodate overrun of elements in "last" tile
                -pad_right => $self->px_per_tile,
                -image_class => 'GD'
               );

    my $panel = Bio::Graphics::Panel->new(@argv);

    # we use a dummy gd object to set up the main panel palette
    $panel->{gd} = GD::Image->new(1, 1);
    setupPalette($panel);

    my $track;
    my $is_global = 0;
    my $is_hist = 0;
    if ($label eq 'ruler') {
        my ($major, $minor) = $panel->ticks;
        @track_settings = (-glyph => 'arrow',
                           # double-headed arrow:
                           -double => 1,

                           # draw major and minor ticks:
                           -tick => 2,

                           # if we ever want unit labels, we may 
                           # want to bring this back into action...!!!
                           #-units => $conf->setting(general => 'units') || '',
                           -unit_label => '',

                           # if we ever want unit dividers to be
                           # loaded from $conf, we'll have to use
                           # the commented-out option below, 
                           # instead of hardcoding...!!!
                           #-unit_divider => $conf->setting(general => 'unit_divider') || 1,
                           #-unit_divider => 1,

                           # forcing the proper unit use for
                           # major tick marks
                           -units_forced => $zoom_level->[2],
                           -major_interval => $major,
                           -minor_interval => $minor,
                          );
        $track = $panel->add_track($self->segment, @track_settings);
        $is_global = 1;
    } elsif ($track_properties{"-global feature"}) {
        $track = $panel->add_track($self->segment, @track_settings);
        $is_global = 1;
    } elsif (($#features  / $num_tiles) >  $bump_density) {
        # generate a feature density histogram
        my @bins;
        my $binsize = $tilewidth_bases / 100;
        foreach my $feat (@features) {
            foreach my $bin (($feat->start / $binsize)
                             ..($feat->end / $binsize)) {
                $bins[$bin]++;
            }
        }

        my @histfeatures;
        foreach my $bin (0..$#bins) {
            next unless $bins[$bin];
            push @histfeatures,
              new Bio::Graphics::Feature (-start   => $bin * $binsize,
                                          -end     => ($bin + 1) * $binsize - 1,
                                          -strand  => 1,
                                          -primary => 'bin',
                                          -score   => $bins[$bin]
                                         );
        }

        my $bigFeature = 
          new Bio::Graphics::Feature (-start    => $self->segment->start,
                                      -end      => $self->segment->end,
                                      -strand   => 1,
                                      -primary  => 'binAgg',
                                      -segments => \@histfeatures
                                     );

        $track = $panel->add_track([$bigFeature],
                                   @track_settings,
                                   -glyph      => "xyplot",
                                   -graph_type => "boxes",
                                   -scale      => "both",
                                   -height     => 200,
                                   -bump       => 0);
        $is_hist = 1;
    } else {
        $track = $panel->add_track(@track_settings);

        # NOTE: $track is a Bio::Graphics::Glyph::track object

        # go through all the features and add them (but only if we have features)
        if (@features) {
            foreach my $feature (@features) {
                &$log(" adding feature ${feature}...", 2);
                $track->add_feature($feature);
	    }

            # if the average number of features per tile is
            # less than $label_thresh, we print labels
            if (($#features  / $num_tiles) < $label_density) {
                $track->configure(-bump => 1, -label => 1, -description => 1);
            } else {
                $track->configure(-bump => 1, -label => 0, -description => 0);
            }
        }
    }

    &$log("track is set up", 1);

    # get image height, now that the panel is fully constructed
    my $image_height = $panel->height;

    &$log("track is laid out", 1);

    my $blankHtml;
    my $linkCount = 0;
    my $tile_callback = sub {
        my ($tile_prefix, $tile_num, $tile_boxes) = @_;

        my $tileURL = $html_outdir."tile".${tile_num}.".png";

        if ($linkCount > MAX_LINKS) {
            undef $blankHtml;
            $linkCount = 0;
        }

        my $outhtml = "${tile_prefix}${tile_num}.html";
        if (!$is_global && !$is_hist && !defined($tile_boxes)) {
            if (defined($blankHtml)) {
                link $blankHtml, $outhtml
                  || die "could not link blank tile: $!\n";
                $linkCount++;
                return;
            } else {
                $blankHtml = $outhtml;
            }
        }

        $tile_boxes = () if ($is_global || $is_hist);

        $self->writeHTML($outhtml, $tile_num, $image_height,
                         $label, $tileURL, $tile_boxes);
    };

    $tile_callback = sub {} if $label eq 'ruler';

    if ($render_tiles) {
        $self->renderTileRange($first_tile,
                               $last_tile,
                               $self->db,
                               $landmark_name,
                               $tile_prefix,
                               $is_global,
                               $panel,
                               $track,
                               {@argv},
                               \@track_settings,
                               $tile_callback
                              );
    }
    $panel->finished();
    $panel = undef;

    unless ($no_xml) {
        my $xml = new IO::File;
        $xml->open($self->xmlpath, O_RDWR)
          or die "ERROR: cannot open '" . $self->xmlpath . "' ($!)\n";
        flock($xml, LOCK_EX)
          or die "couldn't lock XML: $!";
        my $doc;
        my $parser = new XML::DOM::Parser;
        $doc = $parser->parse($xml) or die "couldn't parse XML: $!";
        my $root = $doc->getDocumentElement;
        my @landmark = ensureChild($root, "landmark",
                                   "id" => $landmark_name);
        setAtts($landmark[0],
            "start" => $self->segment->start, "end" => $self->segment->end);
        if ($label eq 'ruler') {
            setAtts(ensureChild($landmark[0], "ruler"),
                    "tiledir" => "tiles/${landmark_name}/ruler/",
                    "height" => $image_height);
        } else {
            my @tracks = ensureChild($landmark[0], "tracks");
            my @this_track = ensureChild($tracks[0], "track",
                                         "name" => $label,
                                         "key" => $track_key);
            my @this_zoom = ensureChild($this_track[0], "zoomlevel",
                                        "name" => $zoom_level->[0]);
            setAtts($this_zoom[0],
                    "tileprefix" => $html_outdir,
                    "unitspertile" => $tilewidth_bases,
                    "height" => $image_height,
                    "numtiles" => $num_tiles);
        }
        $xml->truncate(0) or die "couldn't truncate XML: $!";
        $xml->seek(0, SEEK_SET) or die "couldn't seek to XML start: $!";
        $xml->print($doc->toString . "\n") or die "couldn't write XML: $!";
        $xml->close or die "couldn't close XML: $!";
    }

    return $image_height;
}

# checks that the given parent element has at least one
# child with the given tag name and (optional) attribute values.
# if there's no such child, creates one.
sub ensureChild {
    my ($parent, $tag, %atts) = @_;
    my $filter = sub {
        my $node = shift;
        foreach my $key (keys %atts) {
            return 0 if $node->getAttribute($key) ne $atts{$key};
        }
        return 1;
    };
    my @children = grep &$filter($_), $parent->getElementsByTagName($tag);
    return @children if @children;
    my $child = $parent->appendChild($parent->getOwnerDocument->createElement($tag));
    setAtts($child, %atts);
    return $child;
}

# sets multiple attributes on a given element
sub setAtts {
    my ($node, %atts) = @_;
    $node->setAttribute($_, $atts{$_}) foreach keys %atts;
    return $node;
}

sub area {
    # writes out the area html 
    # since using this I am less happy with fact that all changes
    # (even javascript) then have to be pre rendered including mouseovers etc
    # a better way would be upload the area/coordinate data and then
    # update the area element with the parameters
    my ($x1,$y1,$x2,$y2,$feat)=@_;
    my $str="<area shape=rect coords=\"$x1,$y1,$x2,$y2\" href=\"javascript:MenuComponent_showDescription('<b>Feature</b>','<b>Name:</b>&nbsp;" . $feat->display_name . "<br><b>ID:</b>&nbsp;" . $feat->primary_id . "<br><b>Type:</b>&nbsp;" . $feat->primary_tag . "<br><b>Source:</b>&nbsp;" . $feat->source_tag . "<br>";
    foreach my $key ( $feat->get_all_tags() ) {
        $str .= "<b>$key</b>&nbsp;"
                . join(", ", $feat->get_tag_values($key)) . "<br>";
    }
    return $str . "')\">\n";
}

sub writeHTML {
    my ($self,
        $xhtmlfile,
        $tile_num,
        $image_height,
        $track_label,
        $tileURL,
        $small_tile_glyphs) = @_;

    # have to check that all the coords are in the rectangles
    my $lower_limit = $tile_num * $self->px_per_tile;
    my $upper_limit = ($tile_num + 1) * $self->px_per_tile;

    # make the image map per tile, including all the html that will be
    # imported into the div element big problem I can see here is how
    # to not make storing the features so redundant
    open (HTMLTILE, ">${xhtmlfile}")
        or die "ERROR: could not open ${xhtmlfile}!\n";

    if ($small_tile_glyphs) {
        print HTMLTILE "<img src=\"$tileURL\" ismap usemap=\"#tilemap_${track_label}_${tile_num}\" border=0>\n";
        print HTMLTILE "<map name=\"tilemap_${track_label}_${tile_num}\">\n";
        foreach my $box (@{$small_tile_glyphs}) {
            next unless $box->[0]->can('primary_tag');
            my ($x1, $y1, $x2, $y2) = @{$box}[1..4];

            # adjust coordinates to the correct tile
            $x1=$x1-$lower_limit;
            $x2=$x2-$lower_limit;   

            # tidy up coord edges
            $x2=$self->px_per_tile if ( $x2 > $self->px_per_tile );
            $x1=0 if ( $x1 < 0 );

            print HTMLTILE area($x1,$y1,$x2,$y2,$box->[0]);
        }
        print HTMLTILE "</map>\n";
    } else {
        print HTMLTILE "<img src=\"$tileURL\" border=0>";
    }
    close HTMLTILE or die "couldn't close HTMLTILE: $!\n";
}

sub setupPalette {
    my ($panel) = @_;
    my $gd = $panel->{gd};
    my %translation_table;
    foreach my $name ('white','black', $panel->color_names) {
        my @rgb = $panel->color_name_to_rgb($name);
        my $idx = $gd->colorAllocate(@rgb);
        $translation_table{$name} = $idx;
    }
    $panel->{translations} = \%translation_table;
}

return 1;
