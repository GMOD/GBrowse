#!perl

use Config;
use File::Basename qw(&basename &dirname);
use File::Spec;
use FindBin '$Bin';
use Cwd;

my %OPTIONS;
if (open F,"$Bin/GGB.def") {
  while (<F>) {
    next if /^\#/;
    chomp;
    $OPTIONS{$1} = $2 if /^(\w+)\s*=\s*(.+)/;
  }
  close F;
}

if($OPTIONS{PREFIXSTRIP}){
  $OPTIONS{CONF} =~ s/^$OPTIONS{PREFIX}//;
  $OPTIONS{LIB}  =~ s/^$OPTIONS{PREFIX}//;
}

$OPTIONS{CONF} ||= '/usr/local/apache/conf';

my $dir = dirname($0);
$file   = shift || File::Spec->catfile($dir,basename($0, '.PL','.PLS'));

open OUT,">$file" or die "Can't create $file: $!";

print "Extracting $file (with variable substitutions)\n";

my $startperl = $Config{startperl} ne '#!perl'
    ? $Config{startperl}
: "#!$Config{perlpath}";

print OUT <<"!GROK!THIS!";
$startperl -w

###################################################################
# Non-modperl users should change this variable if needed to point
# to the directory in which the configuration files are stored.
#
    \$CONF_DIR  = '$OPTIONS{CONF}/gbrowse.conf';
####################################################################
\$VERSION   = $OPTIONS{VERSION};

!GROK!THIS!

print OUT "use lib '$OPTIONS{LIB}';\n" if defined $OPTIONS{LIB};

# In the following, perl variables are not expanded during extraction.

print OUT <<'!NO!SUBS!';

use strict;
use CGI qw(:standard Map Area);
use CGI::Carp 'fatalsToBrowser';
use CGI::Toggle;
use CGI::Pretty 'html3';
use lib '/home/smckay/lib';
use Bio::Graphics;
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Util;
use Bio::Graphics::Browser::Render;
use Bio::Graphics::Browser::PageSettings;
use Bio::DB::GFF::SyntenyIO;
use Text::Shellwords;
use List::Util qw/min max sum/;
use Digest::MD5 'md5_hex';


use Data::Dumper;

use constant OVERVIEW_RATIO     => 0.6;
use constant DEBUG_EXTERNAL     => 0;
use constant DEFAULT_FINE_ZOOM  => '10%';
use constant IMAGEWIDTH         => 800;
use constant INTERIMAGE_PAD     => 5;
use constant VERTICAL_PAD       => 40;
use constant IMAGE_PAD          => 10;
use constant MIN_SEG_SIZE       => 10_000;
use constant BUTTONSDIR         => '/gbrowse/images/buttons/';
use constant FINEZOOM           => '20%';
use constant ALIGN_HEIGHT       => 6;
use constant MAX_GAP            => 0.3;
use constant MAX_SEGMENT        => 200_001;

use constant DEBUG => 1;

use vars qw($CONF_DIR $CONF $CONFIG $VERSION $MAP $DEFAULT_SEGMENT $MAX_SEGMENT $HEADER);


$HEADER = 0;

# initialization
$CONF_DIR  = conf_dir($CONF_DIR);    # conf_dir() is exported from Util.pm

# open_config() is exported from Util.pm
$CONF    = open_config($CONF_DIR,'conf');
$CONFIG  = Bio::Graphics::Browser::Render->new;
$CONFIG->read_configuration($CONF_DIR,'syn');

my ($source, $old_source) = $CONFIG->get_source();
my ($page_settings, $session) = $CONFIG->page_settings();

$MAP = db_map();

#print pre(Dumper $page_settings);
my $is_search = $CONFIG->is_search;
#my $features  = $is_search ? $CONFIG->get_features($page_settings) : [];

#my $is_search = is_search($page_settings);
my $features  = $is_search ? $CONFIG->get_features($page_settings) : [];

if (!@$features && $page_settings->{name} && $is_search) {
  @$features = do_keyword_search($page_settings->{name});
}

my $segments = $CONFIG->features2segments($features);
my @segments = @$segments;

#if (!@$features && $page_settings->{name} && $is_search) {
#  @$features = do_keyword_search($page_settings->{name});
#}

#my $segments = features2segments($features);
#my @segments = @$segments;

my $segment;
if ($is_search) {
  if (my $search_src  = param('search_src') )  {
    $CONFIG->setting('general', search_src => $search_src);
    my $landmark = param('name');
    $segment    = landmark2segment($search_src,$landmark) or fatal_error("no segment");
    $CONFIG->current_segment($segment);
  }
}

my %cookie = (-cookie => $CONFIG->make_cookie('gbrowse_syn_src' => $CONFIG->setting('gbrowse_syn_src')));
my $banner = $CONFIG->setting('header');
if (ref $banner) {
  $banner = &$banner;
}

my $style  = $CONFIG->setting('stylesheet');

print_header( %cookie, -style => $CONFIG->setting('stylesheet') );
print start_html( -title => $CONFIG->setting('description'),
		  -style => $style );
print $banner if $banner;


print h1("Synteny Browser for ".$CONFIG->setting('description'));
search_form($segment);
print $CONFIG->overview_panel($page_settings);

draw_image($segment) if $segment;

print $CONFIG->footer || end_html();

exit 0;

sub source_popup {
  my @sources = $CONFIG->sources;
  if (@sources > 1) {
    return popup_menu(-name=>'source',
		      -values=>\@sources,
		      -labels => { map {$_ => $CONFIG->description($_)} $CONFIG->sources},
		      -default => $CONFIG->source,
		      -override=>1,
		      -onChange => 'document.mainform.submit()'
		     );
  } else {
    return $CONFIG->description($CONFIG->source);
  }
}

sub landmark_search {
  my $settings = shift;
  return $CONFIG->setting('no search')
      ? '' : b($CONFIG->tr('Landmark')).':'.br.
      textfield(-name=>'name',-size=>25,-default=>$settings->{name});
}

sub species_search {
  my %labels = map {$_=>$MAP->{$_}{desc}} keys %$MAP;
  return b($CONFIG->tr('Species')).':'.br.
      popup_menu(-name=>'search_src',
		 -values=>[sort {$MAP->{$a}{desc} cmp $MAP->{$b}{desc}} keys %labels],
		 -labels=>\%labels,
		 -default=>$CONFIG->setting('search_src')
		 );
}

sub species_chooser {
  

}

sub search_form {
  my $segment = shift;
  my $sources = shift;
  print start_form(-name=>'mainform',-method => 'post');
  navigation_table($segment,$page_settings);
}

sub db_map {
  my %map;
  my @map = shellwords($CONFIG->setting('source_map'));
  while (my($symbol,$db,$desc) = splice(@map,0,3)) {
    $map{$symbol}{db}   = $db;
    $map{$symbol}{desc} = $desc;
  }
  \%map;
}

sub draw_image {
  my $segment = $CONFIG->current_segment or error("no segment");
  my $src     = $CONFIG->setting('search_src');
  my $max_segment = MAX_SEGMENT;

  if ( $segment->length > $max_segment) {
    my $units = $CONFIG->unit_label($max_segment);
    print h2("Sorry: the size of region $segment exceeds the maximum ($max_segment $units)");
    exit;
  }

  my $max_gap = $segment->length * MAX_GAP;

  my $io = Bio::DB::GFF::SyntenyIO->new($CONFIG->setting('join')) or die;

  my @hits = $io->get_synteny_by_range(-src   => $src,
				       -ref   => $segment->abs_ref,
				       -start => $segment->abs_start,
				       -end   => $segment->abs_end);
  
  unless (@hits) {
  #  die("No hits were found for segment $segment");
  }


  # hits coordinates should be min and max of part coordinates
  adjust_container(\@hits);

  # relate hits into "spans" sorted by target contig/chromosomes
  # %span = ( target_database,target_contig => { target, contig, start, end } } )
  my (%span,%hit2span,%instance);
  for my $h (sort {$a->tstart <=> $b->tstart} @hits) {
    my $src    = $h->src2;
    my $contig = $h->target;
    $instance{$src,$contig} ||= 0;
    my $key = join $;,$src,$contig,$instance{$src,$contig};

    # start a new span if the gap is too large 
    if ($span{$key} && ($h->tstart >= $span{$key}{end}+$max_gap)) {
      $key = join $;,$src,$contig,++$instance{$src,$contig};
    }

    $span{$key}{start} = $h->tstart
	if !defined $span{$key}{start} or $span{$key}{start} > $h->tstart;

    $span{$key}{end}   = $h->tend
	if !defined $span{$key}{end}   or $span{$key}{end}   < $h->tend;

    $span{$key}{src}    ||= $src;
    $span{$key}{contig} ||= $contig;
    $span{$key}{tstart} ||= $h->start;
    $span{$key}{tend}   ||= $h->end;
    ($span{$key}{tstart}) = sort {$a<=>$b} ($h->start,$span{$key}{tstart});
    ($span{$key}{tend})   = sort {$b<=>$a} ($h->end,$span{$key}{tend});
    $hit2span{$h} = $key;
  }

  # get rid of tiny spans
  my $src_fraction = $segment->length/20;
  my @unused_hits;
  for my $key (keys %span) {

    my $too_short = ($span{$key}{end} - $span{$key}{start}) < $src_fraction;
#	|| ($span{$key}{tend} - $span{$key}{tstart}) < $src_fraction;
    if ($too_short) {
      delete $span{$key};
      push @unused_hits, grep { $hit2span{$_} eq $key } @hits;
      @hits = grep { $hit2span{$_} ne $key } @hits;
    }
  }

#  print pre(Dumper \@unused_hits);

  # sort hits into upper and lower hits, based on this pattern:
  #
  #   1    3    5    7      upper spans
  #
  #   - - - - - - - - -     upper hits
  #
  #   - - - - - - - - -     lower hits
  #
  #   0    2    4    6      lower spans
  #
  # We greedily allocate spans to the closest hit - this is not the
  # best way to minimize distance between hits and spans, but it's ok
  # for now.

  my (%hit_positions);
  my $position = 0;
  my %position; 
  # on second thought, order by hit size to improve display
  # actually let's try sorting by species
  
  for my $h (sort {($b->end-$b->start)<=>($a->end-$a->start)} @hits) {
    my $src = $h->src2;
    $position{$src} ||= $position++;
    my $span_key = $hit2span{$h};
    $span{$span_key}{position} ||= $position{$src};
    $hit_positions{$h} ||= $span{$span_key}{position};
  }

  

  # we now create feature files for the reference
  my %source_colors;
  for my $key (keys %span) {
    $source_colors{$span{$key}{src}} ||= $CONFIG->setting($MAP->{$span{$key}{src}}{db}=>'color');
  }
  my $setcolor = sub {
    my $feature = shift;
    $source_colors{$feature->source};
  };

  # Create the middle (reference) panel
  my ($upper_ff,$lower_ff,%is_upper);
  for my $h (@hits) {
    my $src = $h->src2;
    $is_upper{$src} ||= $hit_positions{$h} % 2;
    my $ff       = $is_upper{$src} ? \$upper_ff : \$lower_ff;
    unless ($$ff) {
      $$ff = Bio::Graphics::FeatureFile->new;
      $$ff->add_type(BLOCK => {bgcolor=>$setcolor,
			       fgcolor=>$setcolor,
			       height=>ALIGN_HEIGHT,
			       glyph=>'segments',
			       label=>0,
			       box_subparts=>1});
    }
    add_hit_to_ff($$ff,$h);
  }


  my $orphan_hit = 0;
  for my $h (@unused_hits) {
    warn "I am an orphan! ".$h->start."..".$h->end."\n" if DEBUG;
    my $is_upper = ++$orphan_hit % 2;
    my $ff       = $is_upper ? \$upper_ff : \$lower_ff;
    add_hit_to_ff($$ff,$h);
  }

  my $width = $CONFIG->width || IMAGEWIDTH;

  my ($ref_img,$ref_boxes) = segment2image($segment,
					   $src,
					   { width           => $width,
					     features_top    => $upper_ff,
					     features_bottom => $lower_ff,
					     background      => 'white',
					   }
					   ) or die("no image");
  

  my $ref_title = $MAP->{$src}{desc} . ' '.format_segment($segment);

  # pad all of the span coordinates for a bit of regional context 
  for my $key (keys %span) {
    my $width = $span{$key}{end} - $span{$key}{start};
    $span{$key}{start} -= int $width/50;
    $span{$key}{end  } += int $width/50;
  }

  # we now create panels and corresponding hit feature files for each of the small
  # panels
  my $refwidth     = $CONFIG->width - INTERIMAGE_PAD;
  my $panel_count  = keys %span;
  my $panels_above = my @panels_above = grep { $span{$_}{position} % 2 } keys %span;
  my $panels_below = my @panels_below = grep {!($span{$_}{position} % 2) } keys %span;
  my $bases_above  = sum( map {$span{$_}{end} - $span{$_}{start}} @panels_above );
  my $bases_below  = sum( map {$span{$_}{end} - $span{$_}{start}} @panels_below );
  my ($pad_top,$pad_bottom) = (0,0);
  my ($img,$boxes);

  for my $key (keys %span) {
    my $panel_position   = $span{$key}{position};
    my $is_above         = $panel_position % 2;
    my $total_bases      = $is_above ? $bases_above : $bases_below;
    my $panels_here      = $is_above ? $panels_above : $panels_below;
    my $total_width      = $refwidth - $panels_here*INTERIMAGE_PAD + 2*INTERIMAGE_PAD;
    
    # make it just a bit smaller to be on the safe side...
#    $total_width        -= 10;

    my $src              = $span{$key}{src};
    my $contig           = $span{$key}{contig};
    my $end              = $span{$key}{end};
    my $start            = $span{$key}{start};
    my $bases            = $end - $start;
    my $name             = "$contig:$start..$end";
    my $segment          = landmark2segment($src,$name);
    my @relevant_hits    = grep {$hit2span{$_} eq $key} @hits;

    # width of inset panels scaled by size of target sequence
    my $scale      = $bases/$total_bases;
    my $width      = ($scale * $total_width);


    my $ff    = Bio::Graphics::FeatureFile->new;
    $ff->add_type(BLOCK => {
			    bgcolor=>$setcolor,
			    fgcolor=>$setcolor,
			    height=>ALIGN_HEIGHT,
			    glyph=>'segments',
			    label=>0,
			    box_subparts=>1});

    add_hit_to_ff($ff,$_,'invert') foreach @relevant_hits;

    my ($img,$boxes)     = segment2image($segment,
					 $src,
					 { width => $width,
					   $is_above ? (features_bottom => $ff) 
                                                     : (features_top    => $ff) }) or next;
    $span{$key}{image} = $img;
    $span{$key}{boxes} = $boxes;
    $span{$key}{title} = $MAP->{$src}{desc} . ' ' . format_segment($segment);

    $pad_top    = $img->height if $is_above  && $pad_top < $img->height;
    $pad_bottom = $img->height if !$is_above && $pad_bottom < $img->height;
  }

  # total height is height of reference + pad_top + pad_bottom + VERTICAL_PAD pixels of spacing
  my $total_height = $ref_img->height + $pad_top + $pad_bottom;
  $total_height   += VERTICAL_PAD  if $panels_above;
  $total_height   += VERTICAL_PAD  if $panels_below;
  $total_height   += INTERIMAGE_PAD;


  # create a master image for all panels
  my $gd = GD::Image->new($ref_img->width+2*INTERIMAGE_PAD,$total_height+1,1) or return;
  $gd->saveAlpha(0);
  $gd->alphaBlending(1);
  my $white       = $gd->colorAllocate(255,255,255);
  my $black       = $gd->colorAllocate(0,0,0);
  my $cyan        = $gd->colorAllocate(0,255,255);
  $gd->filledRectangle(0,0,$gd->width,$gd->height,$white);
  my $translucent = $gd->colorAllocateAlpha(0,0,255,90);

  for my $key (keys %span) {
    my $color            = $CONFIG->setting($MAP->{$span{$key}{src}}{db}=>'color');
    $span{$key}{tcolor}  = $gd->colorAllocateAlpha(Bio::Graphics::Panel->color_name_to_rgb($color),80);
    $span{$key}{bgcolor} = $gd->colorAllocateAlpha(Bio::Graphics::Panel->color_name_to_rgb($color),110);
    $span{$key}{border}  = $gd->colorResolve(Bio::Graphics::Panel->color_name_to_rgb($color));
  }

  my $ref_top    = $panels_above ? $pad_top + VERTICAL_PAD : INTERIMAGE_PAD;
  my $ref_bottom = $ref_top + $ref_img->height;

  # paste the individual panels into the picture
  my @map_items;
  my %x = ( above => INTERIMAGE_PAD, below => INTERIMAGE_PAD);

  # order the panels by hit order 
  my (@sorted_spans,%seen_span);
  for my $h (sort {$a->start <=> $b->start} @hits) {
    my $span = $hit2span{$h};
    push @sorted_spans, $span if ++$seen_span{$span} == 1;
  }

  for my $key (@sorted_spans) {
    my $is_above = $span{$key}{position} % 2;
    my $img = $span{$key}{image} or next;
    my $xi = $is_above ? 'above' : 'below';
    my $y  = $is_above ? $ref_top-VERTICAL_PAD()-$img->height : $ref_bottom+VERTICAL_PAD;
    $span{$key}{offsets} = [$x{$xi},$y];
    my @rect = ($x{$xi},$y,$x{$xi}+$img->width,$y+$img->height);
    $gd->copy($img,$x{$xi},$y,0,0,$img->width,$img->height);
    $gd->filledRectangle(@rect,$span{$key}{bgcolor});
    $gd->rectangle(@rect,$span{$key}{border});
    $x{$xi} += $img->width + INTERIMAGE_PAD;
    my $name = "$span{$key}{contig}:$span{$key}{start}..$span{$key}{end}";
    push @map_items,Area({shape=>'rect',
			  coords=>join(',',@rect),
			  href=>"?search_src=$span{$key}{src};name=$name",
			  title=>$span{$key}{title}});
  }

  # middle row (reference)
  my @rect = (INTERIMAGE_PAD,$ref_top,INTERIMAGE_PAD+$ref_img->width,$ref_top+$ref_img->height);
  $gd->copy($ref_img,INTERIMAGE_PAD,$ref_top,0,0,$ref_img->width,$ref_img->height);
  my $color   = $CONFIG->setting($MAP->{$src}{db}=>'color');
  my $bgcolor = $gd->colorAllocateAlpha(Bio::Graphics::Panel->color_name_to_rgb($color),110);
  my $border  = $gd->colorResolve(Bio::Graphics::Panel->color_name_to_rgb($color));
  $gd->filledRectangle(@rect,$bgcolor);
  $gd->rectangle(@rect,$border);
  push @map_items,Area({shape=>'rect',
			coords=>join(',',@rect),
			title=>$ref_title});

  # sort out the coordinates of all the hits so that we can join them
  # first the hits in the reference panel
  my (%ref_boxes,%panel_boxes);
  for my $box (@$ref_boxes) {
    my $feature = $box->[0];
    next unless $feature->type eq 'BLOCK';
    next if $feature->segments; # no top levels
    $ref_boxes{$feature->name} = 
      [INTERIMAGE_PAD+$box->[1],$ref_top+$box->[2],INTERIMAGE_PAD+$box->[3],$ref_top+$box->[4]];
    # for debugging
    $gd->rectangle(INTERIMAGE_PAD+$box->[1],$ref_top+$box->[2],INTERIMAGE_PAD+$box->[3],$ref_top+$box->[4],$black);
  }

  # now for the hits in each individual panel
  my (%tcolors,%flip);
  for my $key (keys %span) {
    defined $span{$key}{offsets} or next;
    my ($left,$top) = @{$span{$key}{offsets}};
    my $boxes  = $span{$key}{boxes};
    for my $box (@$boxes) {
      my $feature = $box->[0];
      next unless $feature->type eq 'BLOCK';
      next if $feature->segments; # no top levels
      $panel_boxes{$feature->name} = [$left+$box->[1],$top+$box->[2],$left+$box->[3],$top+$box->[4]];
      $tcolors{$feature->name} = $span{$key}{tcolor};
      $flip{$feature->name}++ if $feature->each_tag_value('flip');
    }
  }

  for my $feature (keys %ref_boxes) {
    next unless defined $ref_boxes{$feature} && defined $panel_boxes{$feature};
    my ($rx1,$ry1,$rx2,$ry2) = @{$ref_boxes{$feature}};
    my ($px1,$py1,$px2,$py2) = @{$panel_boxes{$feature}};
    my $poly = GD::Polygon->new();
    my $upper = $py2 < $ry1;
    if ($upper) { 
      # an upper panel
      # This works - but can be simplified!
      $poly->addPt($px1,$py2);
      $poly->addPt($px2,$py2);
      if ($flip{$feature}) {
	$poly->addPt($rx1,$ry1);
	$poly->addPt($rx2,$ry1);
      } else {
	$poly->addPt($rx2,$ry1);
	$poly->addPt($rx1,$ry1);
      }
    } else {
      $poly->addPt($px1,$py1);
      $poly->addPt($px2,$py1);
      if ($flip{$feature}) {
	$poly->addPt($rx1,$ry2);
	$poly->addPt($rx2,$ry2);
      } else {
	$poly->addPt($rx2,$ry2);
	$poly->addPt($rx1,$ry2);
      }
    }
    $gd->filledPolygon($poly,$tcolors{$feature});
  }

  my $url = $CONF->generate_image($gd);
  $CONFIG->section_setting(Details => 'open');
  print $CONFIG->toggle( 'Details',
			 table( {-width=>'100%'},
				Tr( td( {-align=>'center', -class => 'databody'},
					img({-src=>$url,-border=>0,-usemap=>'#mymap'} )))
				),
			 );


  print Map({-name=>'mymap'},@map_items);
}

sub segment2image {
  my ($segment,$src,$options) = @_;
  $segment or error("no segment");

  my $width           = $options->{width};
  my $features_top    = $options->{features_top};
  my $features_bottom = $options->{features_bottom};
  my $background      = $options->{background} || 'white';


  my $dsn = $MAP->{$src}{db} or return;

  my @tracks    = shellwords($CONFIG->setting($dsn => 'tracks'));
  my $ff_scale  = Bio::Graphics::FeatureFile->new;
  $ff_scale->add_type( SCALE => { fgcolor=> 'black', 
				  glyph  => 'arrow',
				  tick   => 2,
				  double => 1,
				  description => 0 } );

  $ff_scale->add_feature($segment=>'SCALE');

  my @labels;
  if ($features_top && $features_bottom) {
    @labels = ('ff_top','ff_scale',@tracks,'ff_bottom');
  } 
  elsif ($features_top) {
    @labels = ('ff_top',@tracks,'ff_scale');
  } 
  elsif ($features_bottom) {
    @labels = ('ff_scale',@tracks,'ff_bottom');
  } 
  else {
    @labels = ('ff_scale',@tracks);
  }

  my %ff_hash;
  $ff_hash{ff_top}    = $features_top    if $features_top;
  $ff_hash{ff_bottom} = $features_bottom if $features_bottom;
  $ff_hash{ff_scale}  = $ff_scale;

  # adjust settings
#  my ($old_width,$old_pad,$old_bgcolor) = ($CONF->width($width),
#					   $CONF->setting('general','image_padding'),
#					   $CONF->setting('general','detail bgcolor'));
  $CONFIG->width($width) if defined $width;
  $CONFIG->setting('general','image_padding' => INTERIMAGE_PAD);
  $CONFIG->setting('general','detail bgcolor'=> $background);

  my ($img,$boxes) = $CONFIG->image_and_map(
					    keystyle  => 'none',
					    segment   => $segment,
					    tracks    => \@labels,
					    title     => $MAP->{$src}{desc}.': '.format_segment($segment),
					    do_map    => 0,
					    noscale=>1,
					    feature_files=>\%ff_hash,
					    );

  # because of the mod_perl environment, we MUST put things back the way we found
  # them - there is probably a better way to do this.
  # $CONF->width($old_width);
  # $CONF->setting('general','image_padding',$old_pad);
  # $CONF->setting('general','detail bgcolor',$old_bgcolor);

  return ($img,$boxes,$segment);
}

sub format_segment {
  my $seg = shift;
  return $seg->ref.':'.$seg->start.'..'.$seg->end;
}

sub landmark2segment {
  my ($src,$landmark) = @_;
  my $dsn = $MAP->{$src}{db} or die "no database\n";
  $CONF->source($dsn);
  my $db = open_database();
  my ($segment) = $CONF->name2segments($landmark,$db);
  $segment;
}

sub add_hit_to_ff {
  my ($ff,$hit,$invert) = @_;
  my $feature;
  my $flip_hit = $hit->strand ne $hit->tstrand;
  my @attributes = $flip_hit ? (-attributes => {flip=>1}) : ();

  if ($invert) { # construct the feature from the target coordinates
    if (my $p = $hit->parts ) {
      my @segments = map {Bio::Graphics::Feature->new(
						      -name=>$_->name,
						      -start=>$_->tstart,
						      -end=>$_->tend,
						      -source=>$_->src2,
						      -type=>'BLOCK',
						      @attributes,
						     )} @$p;
      $feature = Bio::Graphics::Feature->new(-type    => 'BLOCK',
					     -name    => $hit->name,
					     -seqid   => $hit->target,
					     -source  => $hit->src2,
					     -segments=> \@segments,
					     @attributes,
					    );
    } 
    else {
      $feature = Bio::Graphics::Feature->new(-type => 'BLOCK',
					     -name => $hit->name,
					     -seqid=> $hit->target,
					     -start=> $hit->tstart,
					     -source  => $hit->src2,
					     -end  => $hit->tend,
					     @attributes,
					    );
    }

  } 
  else { # construct the feature from the src coordinates
    if (my $p = $hit->parts) {
      my @segments = map {Bio::Graphics::Feature->new(-start=>$_->start,
						      -end=>$_->end,
						      -source=>$_->src2,
						      -type=>'BLOCK',
						      -name=>$_->name,
						      @attributes,
						     )} @$p;
      $feature = Bio::Graphics::Feature->new(-type=>'BLOCK',
					     -name=>$hit->name,
					     -seqid=>$hit->seqid,
					     -source=>$hit->src2,
					     -segments=>\@segments,
					     @attributes,
					    );
    } 
    else {
      $feature = Bio::Graphics::Feature->new(-type=>'BLOCK',
					     -name=>$hit->name,
					     -seqid=>$hit->seqid,
					     -start=>$hit->start,
					     -source=>$hit->src2,
					     -end=>$hit->end,
					     @attributes
					    );
    }
  }
  $ff->add_feature($feature=>'BLOCK');
}

sub adjust_container {
  my $hits = shift;
  for my $h (@$hits) {
   if ($h->parts) {
     my @coords = map {$_->tstart,$_->tend} @{$h->parts};
     my ($max,$min)  = (max(@coords),min(@coords));
     $h->tstart($min) if $h->tstart < $min;
     $h->tend($max)   if $h->tend   > $max;
    }
  }
}

sub navigation_table {
  my $segment = shift;
  my $settings = shift;

  my ($table,$whole_segment);

  my $slidertable = '';
  if ($segment) {
    my $whole_segment = $CONFIG->whole_segment();
    my ($label)  = $CONFIG->tr('Scroll');
    $slidertable = $CONFIG->slidertable;
  }

  $CONFIG->section_setting(Instructions => 'open');
  $CONFIG->section_setting(Search => 'open');

  $table .= $CONFIG->toggle('Intructions',p($CONFIG->show_examples('search_src=mel')));

  $table .= $CONFIG->toggle($CONFIG->tr('Search'),
			  table({-border=>0, -width => '100%', -cellspacing=>0},
				TR({-class=>'searchtitle'},
				   td({-align=>'left', -colspan=>3},
				      html_frag('html1',$segment,$settings)||''
				      )
				   ),
				
				TR({-class=>'searchtitle'},
				   td({-align=>'left', -width=>'30%'},
				      landmark_search($settings)
				      ).
				   td({-align=>'left', colspan => 2},
				      species_search()
				      ),
				),
				TR({-class=>'searchtitle',-style=>'padding-top: 10 px', -valign => 'bottom'},
				   td({-align=>'left', -width => '30%'},
				      source_menu($settings)
				      ).
				   td({-align=>'left'},                                                                   
                                       submit(-name=>$CONFIG->tr('Search'))
                                      ).
				   td({-align => 'center'},
				      $slidertable
				      ),
				   ),
				)
			  );
  
  print $table;
}

sub source_menu {
  my $settings = shift;
  my @sources      = $CONFIG->sources;
  my $show_sources = $CONFIG->setting('show sources');
  $show_sources    = 1 unless defined $show_sources;   # default to true
  my $sources = $show_sources && @sources > 1;
  return b($CONFIG->tr('Data Source')).br.
    ( $sources ?
      popup_menu(-name   => 'source',
		 -values => \@sources,
		 -labels => { map {$_ => $CONFIG->description($_)} $CONFIG->sources},
		 -default => $CONFIG->source,
		 -onChange => 'document.mainform.submit()',
		)
	: $CONFIG->description($CONFIG->source)
      );
}

!NO!SUBS!

close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';

