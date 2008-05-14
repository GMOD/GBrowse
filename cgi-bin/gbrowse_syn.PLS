#!perl
use Config;
use File::Basename qw(&basename &dirname);
use File::Spec;
use FindBin '$Bin';
use Cwd;

my %OPTIONS;
if (open F,"$Bin/../GGB.def") {
  while (<F>) {
    next if /^\#/;
    chomp;
    $OPTIONS{$1} = $2 if /^(\w+)\s*=\s*(.+)/;
  }
  close F;
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
#
###################################################################
\$VERSION   = 0.01;
\$BIOGRAPHICS_VERSION   = $OPTIONS{BIOGRAPHICS_VERSION};


!GROK!THIS!

print OUT "use lib '$OPTIONS{LIB}';\n" if defined $OPTIONS{LIB};

# In the following, perl variables are not expanded during extraction.

print OUT <<'!NO!SUBS!';
#$Id: gbrowse_syn.PLS,v 1.9.2.5 2008-05-14 20:47:05 sheldon_mckay Exp $

use strict;

use CGI qw(:standard Map Area delete_all);
use CGI::Carp 'fatalsToBrowser';
use CGI::Toggle;
use CGI::Pretty 'html3';
use Bio::Graphics;
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Util;
use Bio::Graphics::Browser::Synteny;
use Bio::Graphics::Browser::PageSettings;
use Bio::DB::GFF::SyntenyIO;
use Bio::DB::GFF::SyntenyBlock;
use Text::Shellwords;
use List::Util qw/min max sum/;
use Digest::MD5 'md5_hex';
use List::Util 'max';
use Math::Round 'nearest';
use Data::Dumper;


use constant OVERVIEW_RATIO     => 0.9;
use constant OVERVIEW_BGCOLOR   => 'gainsboro';
use constant INTERIMAGE_PAD     => 5;
use constant VERTICAL_PAD       => 40;
use constant IMAGE_PAD          => 10;
use constant ALIGN_HEIGHT       => 6;
use constant MAX_GAP            => 0.3;
use constant MAX_SEGMENT        => 400_001;
use constant DEBUG              => 0;

# Display options -- using a hash here so that
# $page_settings can be updated without using hard-coded
# keys (not counting this constant).
use constant DEFAULT_SETTINGS => 
    ( 
      aggregate  => 'off', # chain alignments
      pgrid      => 'on',  # gridlines
      shading    => 'on',  # shaded polygons
      tiny       => 'off', # ignore small alignments
      pflip      => 'on',  # flip (-) strand panels
      edge       => 'on',  # outline polygons
      imagewidth => 1024,  # width of the image
      );

use vars qw/$CONF_DIR $SCONF $CONF $VERSION $MAP $SYNTENY_IO/;

# initialization
$CONF_DIR   = conf_dir($CONF_DIR);
$SCONF      = open_config($CONF_DIR,'syn');           # species-specific configuration
$CONF       = Bio::Graphics::Browser::Synteny->new(); # general configuration
$CONF->read_configuration($CONF_DIR,'synconf');
$SYNTENY_IO = Bio::DB::GFF::SyntenyIO->new($CONF->setting('join'));

END {
  $CONF->flush_settings();
}

my ($source, $old_source) = $CONF->get_source();
$MAP = db_map();
my ($page_settings,$session) = page_settings();
$CONF->page_settings($page_settings);
$CONF->search_src($CONF->page_settings("search_src"));

my $segment = landmark2segment() if $CONF->page_settings("name");

if ($segment) {
  $segment    = feature2segment($segment) if ref $segment ne 'Bio::DB::GFF::RelSegment';
  $CONF->current_segment($segment);
}

my $cookie  = CGI::Cookie->new(-name    => $CGI::Session::NAME,
			       -value   => $session->id,
			       -path    => url(-absolute=>1),
			       -expires => '+1d');

print_header(-cookie => [$cookie], -expires => 'now');

print start_html( -title => $CONF->setting('description'),
		  -style => $CONF->setting('stylesheet'));

my $header = $CONF->setting('header');
$header = &$header if ref $header;
print $header || h1($CONF->setting('description'));
search_form($segment);
print overview_panel($CONF->whole_segment($segment),$segment) if $segment;
draw_image();
options_table();
print $CONF->footer || end_html();

exit 0;

sub source_popup {
  my @sources = $CONF->sources;
  if (@sources > 1) {
    return popup_menu(-name=>'source',
		      -values=>\@sources,
		      -labels => { map {$_ => $CONF->description($_)} $CONF->sources},
		      -default => $CONF->source,
		      -override=>1,
		      -onChange => 'document.mainform.submit()'
		     );
  } else {
    return $CONF->description($CONF->source);
  }
}

sub landmark_search {
  my $segment = shift;
  my $default = $segment->name if $segment;
  return $CONF->setting('no search')
      ? '' : b($CONF->tr('Landmark')).':'.br.
      textfield(-name=>'name',-size=>25,-default=>$default);
}

sub species_search {
  my $default = $CONF->page_settings("search_src");

  # This is not implemented/working yet
  if (my @species = param('species')) {
    my %species = map {$_=>1} @species;
    for my $s (keys %$MAP) {
      delete $MAP->{$s} unless $species{$s};
    }
  }

  my %labels = map {$_=>$MAP->{$_}{desc}} keys %$MAP;
  return b($CONF->tr('Reference Species')).':'.br.
      popup_menu(-name=>'search_src',
		 -values=>[sort {$MAP->{$a}{desc} cmp $MAP->{$b}{desc}} keys %labels],
		 -labels=>\%labels,
		 -default=>$default,
		 -override=>1
		 );
}

sub search_form {
  my $segment = shift;
  print start_form(-name=>'mainform',-method => 'post');
  navigation_table($segment);
}

sub db_map {
  my %map;
  my @map = shellwords($CONF->setting('source_map'));
  while (my($symbol,$db,$desc) = splice(@map,0,3)) {
    $map{$symbol}{db}   = $db;
    $map{$symbol}{desc} = $desc;
  }
  \%map;
}

sub _type_from_box {
  my $box = shift;
  my @type = split ':', $box->[0];
  my ($feature,$fname) = @type[0,-1];
  return ($feature,$fname);
}

sub draw_image {
  my $src     = $CONF->page_settings("search_src");
  my $segment = $CONF->current_segment or return;
  my $max_segment = MAX_SEGMENT;

  if ( $segment->length > $max_segment) {
    my $units = $CONF->unit_label($max_segment);
    print h2("Sorry: the size of region $segment exceeds the maximum ($units)");
    exit;
  }

  my $max_gap = $segment->length * MAX_GAP;

  my @hits = $SYNTENY_IO->get_synteny_by_range(-src   => $src,
				       -ref   => $segment->abs_ref,
				       -start => $segment->abs_start,
				       -end   => $segment->abs_end);
  

  # dynamically create synteny blocks
  @hits = aggregate(\@hits) if $CONF->page_settings("aggregate") eq 'on';
  
  # save the hits by name so we can access them from the name alone
  for (@hits) {
    $CONF->name2hit( $_->name => $_ );
  }

  # relate hits into "spans" sorted by target contig/chromosomes
  # %span = ( target_database,target_contig => { target, contig, start, end } } )
  my (%span,%hit2span,%instance);
  for my $h (sort {$a->tstart <=> $b->tstart} @hits) {
    # re-map target coordinates if the hit spans a ref. segment end
    remap_coordinates($h,$segment);

    my $src    = $h->src2;
    my $contig = $h->target;
    $instance{$src,$contig} ||= 0;
    my $key = join $;,$src,$contig,$instance{$src,$contig};

    # start a new span if the gap is too large 
    if ($span{$key} && ($h->tstart >= $span{$key}{end}+$max_gap)) {
      $key = join $;,$src,$contig,++$instance{$src,$contig};
    }

    # Tally the plus and minus strand total.  We will flip the panel
    # if more aligned sequence is on the minus strand than the plus strand.
    # only count actual alignmnts (not aggregates).
    my $panel_flip = $CONF->panel_flip($key);
    if ($h->parts) {
      for my $p (@{$h->parts}) {
	$panel_flip->{$key}{yes} += ($p->tend - $p->tstart) if $p->tstrand eq '-';
	$panel_flip->{$key}{no}  += ($p->tend - $p->tstart) if $p->tstrand eq '+';
      }
    }
    else {
      $panel_flip->{$key}{yes} += ($h->tend - $h->tstart) if $h->tstrand eq '-';
      $panel_flip->{$key}{no}  += ($h->tend - $h->tstart) if $h->tstrand eq '+';
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
    $hit2span{$h->name} = $key;
  }

  # get rid of tiny spans
  my $src_fraction = $segment->length/40;
  my @unused_hits;
  unless ($CONF->page_settings("tiny") eq 'on') {
    for my $key (keys %span) {
      my $too_short = ($span{$key}{end} - $span{$key}{start}) < $src_fraction
	  && ($span{$key}{tend} - $span{$key}{tstart}) < $src_fraction;
      if ($too_short) {
	delete $span{$key};
	push @unused_hits, grep { $hit2span{$_} eq $key } @hits;
	@hits = grep { $hit2span{$_} ne $key } @hits;
      }
    }
  }

  #print pre(Dumper \%alignment);

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
  # on third through, let's try sorting by species
  
  my $num_species = keys %$MAP;
  my $pos_by_src = $num_species == 1 || $num_species % 2;
  for my $h (sort {($b->end-$b->start)<=>($a->end-$a->start)} @hits) {
    my $src = $h->src2;
    if ($pos_by_src) {
      $position{$src} ||= $position++;
    }
    else {
      $position{$src} = $position++;
    }
    my $span_key = $hit2span{$h};
    $span{$span_key}{position} = $position{$src};
    $hit_positions{$h} ||= $span{$span_key}{position};
  }

  
  # we now create feature files for the reference
  my %source_colors;
  for my $key (keys %span) {
    $source_colors{$span{$key}{src}} ||= $CONF->setting($MAP->{$span{$key}{src}}{db}=>'color');
  }
  my $setcolor = sub {
    my $feature = shift;
    $source_colors{$feature->source};
  };

  # Create the middle (reference) panel
  my ($upper_ff,$lower_ff,%is_upper);
  
  # restrict segment to aligned sequence
  my $only_aligned = 0;
  if ($only_aligned && @hits) {
    my @coords = map {$_->start, $_->end} @hits;
    my $new_name = $segment->ref .':'.(min @coords).'..'.(max @coords);
    $segment = landmark2segment($new_name,$CONF->page_settings('search_src'));
  }

  for my $h (@hits) {
    my $src = $h->src2;

    # keep track of the hits for mapping purposes
    $is_upper{$src} ||= $hit_positions{$h} % 2;
    my $ff       = $is_upper{$src} ? \$upper_ff : \$lower_ff;
    unless ($$ff) {
      $$ff = Bio::Graphics::FeatureFile->new;
      $$ff->add_type(BLOCK => {bgcolor   => $setcolor,
			       fgcolor   => $setcolor,
			       height    => ALIGN_HEIGHT,
			       glyph     => 'segments', 
			       label     => 0, 
			       box_subparts => 1,
			       connector => 'dashed'});
    }
    add_hit_to_ff($segment,$$ff,$h);
  }

  my $orphan_hit = 0;
  for my $h (@unused_hits) {
    warn "I am an orphan! ".$h->start."..".$h->end."\n" if DEBUG;
    my $is_upper = ++$orphan_hit % 2;
    my $ff       = $is_upper ? \$upper_ff : \$lower_ff;
    unless ($$ff) {
      $$ff = Bio::Graphics::FeatureFile->new;
      $$ff->add_type(BLOCK => {bgcolor   => $setcolor,
                               fgcolor   => $setcolor,
                               height    => ALIGN_HEIGHT,
                               glyph     => 'segments',
                               label     => 0,
			       box_subparts => 1,
                               connector => 'dashed'});
    }
    add_hit_to_ff($segment,$$ff,$h) if $ff;
  }

  my $width = $CONF->page_settings('imagewidth');

  my ($ref_img,$ref_boxes) = segment2image($segment,
					   $src,
					   { width           => $width,
					     features_top    => $upper_ff,
					     features_bottom => $lower_ff,
					     background      => 'white',
					   }
					   ) or die("no image");
  
  my $ref_title = $MAP->{$src}{desc} . ' ' . format_segment($segment);

  # pad all of the span coordinates for a bit of regional context 
  for my $key (keys %span) {
    my $width = $span{$key}{end} - $span{$key}{start};
    $span{$key}{start} -= int $width/20;
    $span{$key}{end  } += int $width/20;
  }


  # we now create panels and corresponding hit feature files for each of the small
  # panels
  my $refwidth     = $width;# - INTERIMAGE_PAD;
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
    my $panels           = $is_above ? $panels_above : $panels_below;
    my $total_width      = $refwidth + INTERIMAGE_PAD;
    $total_width         -= $panels > 1 ? 1.5*$panels*INTERIMAGE_PAD + $panels*INTERIMAGE_PAD
	                                : 2*INTERIMAGE_PAD;
    $total_width         += INTERIMAGE_PAD if $panels < 4;

    my $src              = $span{$key}{src};
    my $contig           = $span{$key}{contig};
    my $end              = $span{$key}{end};
    my $start            = $span{$key}{start};
    my $bases            = $end - $start;
    my $name             = "$contig:$start..$end";
    my $segment          = landmark2segment($name,$src);
    my @relevant_hits    = grep {$hit2span{$_} eq $key} @hits;

    my $rsegment = landmark2segment("$contig:$start..$end",$src);

    # width of inset panels scaled by size of target sequence
    $bases or next;
    my $scale = $bases/$total_bases;
    my $width = $total_width;
    
    if  ($panels > 1) {
      $width *= $scale;
    }

    my $ff    = Bio::Graphics::FeatureFile->new;
    $ff->add_type(BLOCK => {
			    bgcolor   => $setcolor,
			    fgcolor   => $setcolor,
			    height    => ALIGN_HEIGHT,
			    glyph     => 'segments',
			    label     => 0,
			    box_subparts => 1,
			    connector => 'dashed'},
		  );

    add_hit_to_ff($rsegment,$ff,$_,'invert') foreach @relevant_hits;

    my $segment_args = {width => $width};
    if ($is_above) {
      $segment_args->{features_bottom} = $ff;
      $segment_args->{noscale} = 1;
    }
    else {
      $segment_args->{features_top} = $ff;
    }

    $segment_args->{flip}++ if panel_is_flipped($key,1);

    ($img,$boxes)     = segment2image($segment, $src, $segment_args);

    $img or next;
    $span{$key}{image} = $img;
    $span{$key}{boxes} = $boxes;
    $span{$key}{title} = $MAP->{$src}{desc};
    $span{$key}{title} .= ' (reverse)' if panel_is_flipped($key);

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
    my $color            = $CONF->setting($MAP->{$span{$key}{src}}{db}=>'color');
    $span{$key}{tcolor}  = $gd->colorAllocateAlpha(Bio::Graphics::Panel->color_name_to_rgb($color),95);
    $span{$key}{bgcolor} = $gd->colorAllocateAlpha(Bio::Graphics::Panel->color_name_to_rgb($color),115);
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

  my $max_height_above = max( map {eval{$span{$_}{image}->height}} grep {$span{$_}{position} % 2} @sorted_spans);
  my $max_height_below = max( map {eval{$span{$_}{image}->height}} grep {! ($span{$_}{position} % 2)} @sorted_spans);

  for my $key (@sorted_spans) {
    my $is_above = $span{$key}{position} % 2;
    my $img = $span{$key}{image} or next;
    my $xi = $is_above ? 'above' : 'below';
    my $max_height = $is_above ? $max_height_above : $max_height_below;
    
    my $img_y = $is_above ? $ref_top-VERTICAL_PAD()-$img->height : $ref_bottom+VERTICAL_PAD;
    my $msk_y  = $is_above ? $ref_top-VERTICAL_PAD()-$max_height : $img_y;
    $span{$key}{offsets} = [$x{$xi},$img_y];
    my @rect = ($x{$xi},$msk_y,$x{$xi}+$img->width,$msk_y+$max_height);
    $gd->copy($img,$x{$xi},$img_y,0,0,$img->width,$img->height);

    $gd->filledRectangle(@rect,$span{$key}{bgcolor});
    $gd->rectangle(@rect,$span{$key}{border});
    $gd->string(GD::gdSmallFont,$x{$xi}+5,$msk_y,$span{$key}{title},$black)
	if $img->width > 75;
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
  my $color   = $CONF->setting($MAP->{$src}{db}=>'color');
  $color ||= 'blue';
  my $bgcolor = $gd->colorAllocateAlpha(Bio::Graphics::Panel->color_name_to_rgb($color),110);
  my $border  = $gd->colorResolve(Bio::Graphics::Panel->color_name_to_rgb($color));
  $gd->filledRectangle(@rect,$bgcolor);
  $gd->rectangle(@rect,$border);
  my $title = $MAP->{$src}{desc};
  $gd->string(GD::gdSmallFont,$rect[0]+5,$rect[1],$MAP->{$src}{desc},$black);
  push @map_items,Area({shape=>'rect',
			coords=>join(',',@rect),
			title=>$ref_title});

  # sort out the coordinates of all the hits so that we can join them
  # first the hits in the reference panel
  my (%ref_boxes,%panel_boxes);
  for my $box (@$ref_boxes) {
    ref $box or next;
    my ($feature,$fname) = _type_from_box($box);
    next unless $feature eq 'BLOCK';
    my $hit = $CONF->name2hit($fname);
    next if $hit && @{$hit->parts} > 1;
    $ref_boxes{$fname} = 
      [INTERIMAGE_PAD+$box->[1],$ref_top+$box->[2],INTERIMAGE_PAD+$box->[3],$ref_top+$box->[4]];
    # for debugging
    #$gd->rectangle(INTERIMAGE_PAD+$box->[1],$ref_top+$box->[2],INTERIMAGE_PAD+$box->[3],$ref_top+$box->[4],$black);
  }

  # now for the hits in each individual panel
  my %tcolors;
  for my $key (keys %span) {
    defined $span{$key}{offsets} or next;
    my ($left,$top) = @{$span{$key}{offsets}};
    my $boxes  = $span{$key}{boxes};
    for my $box (@$boxes) {
      ref $box or next;
      my ($feature,$fname) = _type_from_box($box);
      next unless $feature eq 'BLOCK';
      my $hit = $CONF->name2hit($fname);
      next if $hit && @{$hit->parts} > 1;
      $panel_boxes{$fname} = [$left+$box->[1],$top+$box->[2],$left+$box->[3],$top+$box->[4]];
      $tcolors{$fname} = $span{$key}{tcolor};
      # for debugging
      #$gd->rectangle($left+$box->[1],$top+$box->[2],$left+$box->[3],$top+$box->[4],$black);
    }
  }
  
  my %grid_line;
  my %gc;
  $gc{1} = $CONF->page_settings("pgrid") eq 'on' ? $gd->colorResolveAlpha(10,10,10,100) : $gd->colorResolveAlpha(10,10,10,70);
  $gc{3} = $gd->colorResolveAlpha(10,10,255,100);
  my $thickness = 3;

  for my $feature (keys %ref_boxes) { 
    next unless defined $ref_boxes{$feature} && defined $panel_boxes{$feature};
    my $real_name = $CONF->part2name($feature) || $feature;
    next unless defined $CONF->name2hit($real_name);

    my $span = $hit2span{$real_name};
    my $flip =  !panel_is_flipped($span) && $CONF->flip($feature)
             ||  panel_is_flipped($span) && !$CONF->flip($feature);

    my ($rx1,$ry1,$rx2,$ry2) = @{$ref_boxes{$feature}};
    my ($px1,$py1,$px2,$py2) = @{$panel_boxes{$feature}};
    my $upper = $py2 < $ry1;    

    if ($CONF->page_settings("shading") eq 'on') {
      my $poly = GD::Polygon->new();
      $upper = $py2 < $ry1;
      ($rx1,$rx2) = ($rx2,$rx1) if $flip;

      if ($upper) { 
	$poly->addPt($px1,$py2);
	$poly->addPt($px2,$py2);
	$poly->addPt($rx2,$ry1);
	$poly->addPt($rx1,$ry1);
      } 
      else {
	$poly->addPt($px1,$py1);
	$poly->addPt($px2,$py1);
	$poly->addPt($rx2,$ry2);
	$poly->addPt($rx1,$ry2);
      }
      
      $gd->filledPolygon($poly,$tcolors{$feature});
    }
  }

  # reloop to avoid mysterious alpha-channel interaction
  # between shading and grid-lines
  for my $feature (keys %ref_boxes) {
    next unless defined $ref_boxes{$feature} && defined $panel_boxes{$feature};
    my $real_name = $CONF->part2name($feature) || $feature;

    next unless my $hit = $CONF->name2hit($real_name);

    my $span = $hit2span{$feature};
    my $flip =  !panel_is_flipped($span) && $CONF->flip($feature)
             ||  panel_is_flipped($span) && !$CONF->flip($feature);

    my ($rx1,$ry1,$rx2,$ry2) = @{$ref_boxes{$feature}};
    my ($px1,$py1,$px2,$py2) = @{$panel_boxes{$feature}};
    my $upper = $py2 < $ry1;

    my @grid_coords = $CONF->page_settings("pgrid") eq 'on' 
	? grid_coords( $hit,
		       $ref_boxes{$feature},
		       $panel_boxes{$feature},
		       panel_is_flipped($span),
		       $segment) : ();

    # add edges
    if ($CONF->page_settings("edge") eq 'on') {
      unshift @grid_coords, $flip ? [$rx1,$px2] :  [$rx1,$px1];
      push @grid_coords, $flip ? [$rx2,$px1] :  [$rx2,$px2];
    }

    my $tidx = 0;
    for my $pair (@grid_coords) {
      my ($x1,$x2) = @$pair;
      unless ($grid_line{$x1}{thickness}) {
	$thickness = ++$tidx == 5 ? 3 : 1;
	$tidx = 0 if $tidx == 5;
      }
      else {
	$thickness = $grid_line{$x1}{thickness};
      }
      $gd->setThickness($thickness);
      if ($upper) {
	$gd->line($x1,$ry1,$x2,$py2,$gc{$thickness});
	$gd->line($x2,$py2,$x2,0,$gc{$thickness});
	$grid_line{$x1}{top} ||= $ry2;
      }
      else {
	$gd->line($x1,$ry2,$x2,$py1,$gc{$thickness});
	$gd->line($x2,$py1,$x2,$gd->height,$gc{$thickness});
	$grid_line{$x1}{bottom} ||= $ry1;
      }
      $grid_line{$x1}{thickness} ||= $thickness;
    }
  }
  
  
  for my $g (keys %grid_line) {
    my $thickness = $grid_line{$g}{thickness};
    $gd->setThickness($thickness);
    $grid_line{$g}{top}    ||= $ref_top;
    $grid_line{$g}{bottom} ||= $ref_bottom;
    $gd->line($g,$grid_line{$g}{top},$g,$grid_line{$g}{bottom},$gc{$thickness});
  }

  
  my $url = $SCONF->generate_image($gd);
  
  print $CONF->toggle( 1, 'Details',
			 table( {-width=>'100%'},
				Tr( td( {-align=>'center', -class => 'databody'},
					img({-src=>$url,-border=>0,-usemap=>'#mymap'} )))
				),
			 );


  print Map({-name=>'mymap'},@map_items);
}

sub segment2image {
  my ($segment,$src,$options) = @_;
  $segment or return;

  my $width       = $options->{width};
  my $hits_top    = $options->{features_top};
  my $hits_bottom = $options->{features_bottom};
  my $background  = $options->{background} || 'white';
  my $flip        = $options->{flip};

  my $dsn = $MAP->{$src}{db} or return;

  my @tracks    = shellwords($CONF->setting($dsn => 'tracks'));
  my $ff_scale  = Bio::Graphics::FeatureFile->new;
  $ff_scale->add_type( SCALE => { fgcolor => 'black', 
				  glyph   => 'arrow',
				  tick    => 2,
				  double  => 0,
				  description => 0} );


  $ff_scale->add_feature(segment2feature($segment));
  
  my @labels;
  if ($hits_top && $hits_bottom) {
    @labels = ('ff_top','ff_scale',@tracks,'ff_bottom');
  }
  elsif ($hits_top) {
    @labels = ('ff_top','zz_scale',@tracks);
  }
  elsif ($hits_bottom) {
    @labels = (@tracks,'ff_scale','ff_bottom');
  }
  else {
    @labels = ('ff_scale',@tracks);
  }

  my %ff_hash;
  $ff_hash{ff_top}    = $hits_top    if $hits_top;
  $ff_hash{ff_bottom} = $hits_bottom if $hits_bottom;

  # coerce correct track order in bottom panel
  my $scale_label = $hits_bottom && !$hits_bottom ? 'zz_scale' : 'ff_scale';
  $ff_hash{$scale_label}  = $ff_scale;

  $SCONF->width($width) if defined $width;
  $SCONF->setting('general','image_padding' => INTERIMAGE_PAD);
  $SCONF->setting('general','detail bgcolor'=> $background);

  my $title = $MAP->{$src}{desc};

  # cache no panels if some params change
  my $no_cache = [md5_hex(url(-query_string=>1))];
  
  my ($img,$boxes) = $SCONF->render_panels( 
					    {
					      drag_n_drop => 0,
					      image_and_map => 1,
					      keystyle  => 'none',
					      segment   => $segment,
					      labels    => \@labels,
					      title     => $title,
					      -grid     => 0,
					      do_map    => 1,
					      noscale   => 1,
					      feature_files=>\%ff_hash,
					      -flip     => $flip,
					      cache_extra => $no_cache, 
					    }
					    );
  
  return ($img,$boxes,$segment);
}

sub format_segment {
  my $seg = shift;
  return $seg->ref.':'.$seg->start.'..'.$seg->end;
}

sub landmark2segment {
  my ($name,$source);
  if (@_ == 2) {
    ($name,$source) = @_;
  }
  else {
    $name   = $CONF->page_settings("name");
    $source = $CONF->page_settings("search_src");
  }
  my $segment  = _do_search($name,$source);
  return $segment if defined $segment;
 
  # Maybe the landmark is in another species?
  #for my $src (keys %$MAP) {
  #  $segment = _do_search($name,$src);
  #  return $segment if defined $segment;
  #}
    
  print header, warning("Error: $name was not found in the database");
  exit 0;
}

sub _do_search {
  my ($landmark,$src) = @_;

  my $dsn = $MAP->{$src}{db} or die "no database\n";
  $SCONF->source($dsn);
  my $db = open_database();
  my ($segment) = grep {$_} $SCONF->name2segments($landmark,$db);
  return $segment;
}

sub warning {
  h2({-style=>'color:red'},@_);
}

sub add_hit_to_ff {
  my ($segment,$ff,$hit,$invert) = @_;
  my $feature;
  my $flip_hit = $hit->tstrand eq '-';
  $CONF->flip($hit->name => 1) if $flip_hit;
  my @attributes = $flip_hit ? (-attributes => {flip=>1}) : ();

  if ($invert) { # construct the feature from the target coordinates
    $feature = Bio::DB::GFF::Feature->new_from_parent( $segment,
                                                       $hit->tstart,
                                                       $hit->tend,
                                                       'BLOCK',
                                                       $hit->src2,
                                                       undef,
                                                       $hit->tstrand eq '-' ? -1 : 1,
                                                       '.',
						       Bio::DB::GFF::Featname->new(Hit => $hit->name)
						       );
    my $p = $hit->parts;
    if (@$p > 1) {
      for my $part (@$p) {
        my $pfeat = Bio::DB::GFF::Feature->new_from_parent( $segment,
                                                            $part->tstart,
                                                            $part->tend,
							    'BLOCK',
							    $part->src2,
                                                            undef,
                                                            $part->tstrand eq '-' ? -1 : 1,
							    '.',
							    Bio::DB::GFF::Featname->new(Hit => $part->name)
                                                            );
	$feature->add_subfeature($pfeat);
      }
    }
  } 
  else { # construct the feature from the src coordinates
    $feature = Bio::DB::GFF::Feature->new_from_parent( $segment,
						       $hit->start,
						       $hit->end,
						       'BLOCK',
						       $hit->src2,
						       undef,
						       $hit->strand eq '-' ? -1 : 1,
						       '.',
						       Bio::DB::GFF::Featname->new(Hit => $hit->name)
						       );
    my $p = $hit->parts;
    if (@$p > 1) {
      for my $part (@$p) {
	my $pfeat = Bio::DB::GFF::Feature->new_from_parent( $segment,
							    $part->start,
							    $part->end,
							   'BLOCK',
							    $part->src2,
							    undef,
							    $part->strand eq '-' ? -1 : 1,
							    '.',
							    Bio::DB::GFF::Featname->new(Hit => $part->name)
							    );
	$feature->add_subfeature($pfeat);
      }
    }
  }
  $ff->add_feature($feature);
}

sub adjust_container {
  my $h = shift;

  if ($h->parts) {
    my @coords = map {$_->tstart,$_->tend} @{$h->parts};
    my ($max,$min)  = (max(@coords),min(@coords));
    $h->tstart($min) if $h->tstart != $min;
    $h->tend($max)   if $h->tend   != $max;
    @coords = map {$_->start,$_->end} @{$h->parts};
    ($max,$min)  = (max(@coords),min(@coords));
    $h->start($min) if $h->start != $min;
    $h->end($max)   if $h->end   != $max;
   }

  return $h;
}

sub navigation_table {
  my $segment = shift;

  my ($table,$whole_segment);

  my $slidertable = '';
  if ($segment) {
    my $whole_segment = $CONF->whole_segment();
    my ($label)  = $CONF->tr('Scroll');
    $slidertable = $CONF->slidertable;
  }

  $CONF->section_setting(Instructions => 'open');
  $CONF->section_setting(Search => 'open');

 		   
  $table .= $CONF->toggle(2, 'Intructions',
				   div({-class=>'searchtitle'},
				       br.'Select a Region to Browse and a Reference species:',
				       p($CONF->show_examples())));

  $table .= $CONF->toggle(1, $CONF->tr('Search'),
			  table({-border=>0, -width => '100%', -cellspacing=>0},
				TR({-class=>'searchtitle'},
				   td({-align=>'left', -colspan=>3},
				      html_frag('html1',$segment,$CONF->page_settings)||''
				      )
				   ),
				
				TR({-class=>'searchtitle'},
				   td({-align=>'left', -width=>'30%'},
				      landmark_search($segment)
				      ).
				   td({-align=>'left', colspan => 2},
				      species_search()
				      ),
				),
				TR({-class=>'searchtitle',-style=>'padding-top: 10 px', -valign => 'bottom'},
				   td({-align=>'left', -width => '30%'},
				      source_menu()
				      ).
				   td({-align=>'left'},                                                                   
                                       submit(-name=>$CONF->tr('Search')). '&nbsp;&nbsp;'.
				       submit(-name=>$CONF->tr('Reset'))
                                      ).
				   td({-align => 'center'},
				      $slidertable
				      ),
				   ),
				) );

  print $table;
}

sub options_table {
  my @onclick = ();#(-onclick => "document.mainform.submit()");
  my $radio_style = {-style=>"background:lightyellow;border:5px solid lightyellow", @onclick};
  my $space = '&nbsp;&nbsp';

  print $CONF->toggle(1,  $CONF->tr('Display_settings'), 
			table({-cellpadding => 5, -width => '100%', -border => 0, -class => 'searchtitle'},
			      TR(
				 td(
				     b($CONF->tr('Image widths'), ': '),
				      span( $radio_style, radio_group( -name   => 'imagewidth',
						   -values => [640,768,800,1024,1280],
						   -default=>$CONF->page_settings('imagewidth'),
						   @onclick ))
				    ),
				 td(
				    submit(-name => 'Update Image')
				    )
				 ),
			      TR(
				 td( {-colspan => 2},
				    b($CONF->tr('Image options'), ': '),
				    div(
					span($radio_style, 'Flip minus strand panels ', option_check('pflip')),$space,
					span($radio_style, 'Display tiny alignments ', option_check('tiny')),$space,
					span($radio_style, 'Grid lines ', option_check('pgrid')),$space,
					span($radio_style, 'Edges ', option_check('edge')), $space,
					span($radio_style, 'Shading ', option_check('shading')),
                                    ))
				 ),
			      )
			);
}

sub option_check {
  my $name = shift;
  my $checked = $CONF->page_settings("$name") eq 'on' ? 'on' : 'off';
  return radio_group(-name => $name, -values => [qw/on off/], -default =>$checked);
}

sub source_menu {
  my $settings = shift;
  my @sources      = $CONF->sources;
  my $show_sources = $CONF->setting('show sources');
  $show_sources    = 1 unless defined $show_sources;   # default to true
  my $sources = $show_sources && @sources > 1;
  return b($CONF->tr('Data Source')).br.
    ( $sources ?
      popup_menu(-name   => 'source',
		 -values => \@sources,
		 -labels => { map {$_ => $CONF->description($_)} $CONF->sources},
		 -default => $CONF->setting('search_src'),
		 -onChange => 'document.mainform.submit()',
		)
	: $CONF->description($CONF->source)
      );
}


sub aggregate {
  my $hits = shift;

  my @sorted_hits = sort { $a->target cmp $b->target || $a->tstart <=> $b->tstart} @$hits;

  my (%group,$last_hit);

  for my $hit (@sorted_hits) {
    if ($last_hit && belong_together($last_hit,$hit)) {
      push @{$group{$last_hit}}, $hit;
      $group{$hit} = $group{$last_hit};
    }
    else {
      push @{$group{$hit}}, $hit;
    }

    $last_hit = $hit;
  }

  $hits = [];
  my %seen;
  for my $grp (grep {++$seen{$_} == 1} values %group) {
    if (@$grp == 1) {
      push @$hits, $grp->[0];
    }
    else {
      my $hit = Bio::DB::GFF::SyntenyBlock->new($grp->[0]->name);
      $hit->add_part($grp->[0]->src,$grp->[0]->tgt);
      $CONF->part2name($hit->name, $grp->[0]->name);
      for my $part (@$grp) {
	my $old_name = $part->name;
        my $new_name = $hit->add_part($part->src,$part->tgt);
	$CONF->part2name($new_name,$old_name);
      }
      push @$hits, $hit;
    }
  }


  return map {adjust_container($_)} @$hits;

}

sub belong_together { 
  my ($feat1,$feat2) = @_;
  return unless $feat1->target  eq $feat2->target;       # same chromosome
  return unless $feat1->seqid   eq $feat2->seqid;
  return unless $feat1->tstrand eq $feat2->tstrand;    # same strand                                                                                            
  if ($feat1->tstrand eq '+') {
    return unless $feat1->end < $feat2->end;   # '+' strand monotonically increasing                                                                            
  } else {
    return unless $feat1->end > $feat2->end;   # '-' strand monotonically decreasing                                                                            
  }
  my $dist1 = abs($feat2->end - $feat1->start);
  my $dist2 = abs($feat2->tend - $feat1->tstart);
  return unless $dist2 < 200000 && $dist1 < 200000;
  return $dist2;
}


sub overview_panel {
  my ($whole_segment,$segment) = @_;
  return '' if $SCONF->section_setting('overview') eq 'hide';
  my $image = overview($whole_segment,$segment);
  return toggle($CONF->page_settings,
                'Overview',
                table({-border=>0,-width=>'100%'},
                      TR({-class=>'databody'},
                         td({-align=>'center'},$image)
                        )
                     )
		);
}

sub overview {
  my ($region_segment,$segment) = @_;
  return unless $segment;
  my $width = $CONF->page_settings('imagewidth');
  $width *= OVERVIEW_RATIO;
  $CONF->width($width);
  
  # the postgrid will be invoked to hilite the currently selected region
  my $postgrid = hilite_regions_closure([$segment->start,$segment->end,'yellow']);

  # reference genome
  my $ref = $MAP->{$CONF->page_settings("search_src")}->{desc};

  my ($overview)   = $CONF->render_panels(
						  {
						    length         => $segment->length,
						    section        => 'overview',
						    segment        => $region_segment,
						    postgrid       => $postgrid,
						    label_scale    => 2,
						    lang           => $SCONF->language,
						    keystyle       => 'left',
						    settings       => $CONF->page_settings(),
						    scale_map_type => 'centering_map',
						    cache_extra    => [$segment->start,$segment->end],
						    do_map         => 1,
						    drag_n_drop    => 0,
						    image_button   => 0,
						    -grid          => 0,
						    -pad_top       => 5,
						    -bgcolor       => OVERVIEW_BGCOLOR,
						  }
						  );

  return div({-id=>'overview',-class=>'track'},'Reference genome: ',i($ref),$overview);
}

sub toggle {
  my $title         = shift;
  my @body           = @_;

  my $id    = "\L${title}_panel\E";
  my ($label) = $CONF->tr($title)               or return '';
  my $state = $CONF->section_setting($title)    or return '';
  return '' if $state eq 'off';
  my $settings = $CONF->page_settings;
  my $visible = exists $settings->{section_visible}{$id} ? $settings->{section_visible}{$id} : $state eq 'open';

  return toggle_section({on=>$visible},
			$id,
			b($label),
			@body);
}

sub get_options {
  my $tracks_to_show = shift;
  my $settings = $CONF->page_settings;
  my %options    = map {$_=>$settings->{features}{$_}{options}} @$tracks_to_show;
  my %limits     = map {$_=>$settings->{features}{$_}{limit}}   @$tracks_to_show;
  return (\%options,\%limits);
}

sub hilite_regions_closure {
  my @h_regions = @_;

  return sub {
    my $gd     = shift;
    my $panel  = shift;
    my $left   = $panel->pad_left;
    my $top    = $panel->top;
    my $bottom = $panel->bottom;
    for my $r (@h_regions) {
      my ($h_start,$h_end,$h_color) = @$r;
      my ($start,$end) = $panel->location2pixel($h_start,$h_end);
      if ($end-$start <= 1) { $end++; $start-- } # so that we always see something

      # assuming top is 0 so as to ignore top padding
      $gd->filledRectangle($left+$start,0,$left+$end,$bottom,
			   $panel->translate_color($h_color));
    }
  };
}

sub feature2segment {
  my $feature = shift;
  return $feature if ref $feature eq 'Bio::DB::GFF::RelSegment';
  my $refclass = $CONF->setting('reference class') || 'Sequence';
  my $db = open_database();
  my $version = eval {$_->isa('Bio::SeqFeatureI') ? undef : $_->version};
  return $db->segment(-class => $refclass,
		      -name  => $feature->ref,
		      -start => ($feature->start - int($feature->length/20)),
		      -stop  => ($feature->end + int($feature->length/20)),
		      -absolute => 1,
		      defined $version ? (-version => $version) : ());
}

sub segment2feature {
  my $segment = shift;
  my $start = $segment->start;
  my $end   = $segment->end;
  my $type  = 'SCALE';
  my $src   = 'segment';
  my $strand = $segment->strand;
  my $group  = Bio::DB::GFF::Featname->new(Scale => $segment->ref);
  return Bio::DB::GFF::Feature->new_from_parent($segment,$start,$end,$type,$src,undef,$strand,'.',$group);
}


sub expand {
  my $seq = shift;
  $seq =~ s/(\S)(\d+)/($1 x $2)/eg;
  return $seq;
}

sub remap_coordinates {
  my $hit     = shift;
  my $segment = shift;
  my $flip    = $hit->tstrand eq '-';

  return unless $hit->start < $segment->start || $hit->end > $segment->end;

  if ($hit->start < $segment->start) {
    my ($new_start,$new_tstart) = $SYNTENY_IO->get_nearest_position_match($hit,$hit->src1,$segment->start);
    if ($new_start) {
      my $hsp = $hit->parts->[0];
      $hsp->start($new_start);
      $flip ? $hsp->tend($new_tstart) : $hsp->tstart($new_tstart);
    }
  }
  if ($hit->end > $segment->end) {
    my ($new_end,$new_tend) = $SYNTENY_IO->get_nearest_position_match($hit,$hit->src1,$segment->end);
    if ($new_end) {
      my $hsp = $hit->parts->[-1];
      $hsp->end($new_end);
      $flip ? $hsp->tstart($new_tend) : $hsp->tend($new_tend);
    }
  }
  $hit = adjust_container($hit);
}

# take a vote to flip the panel: the majority strand wins
sub panel_is_flipped { 
  my $key = shift;
  return 0 if $CONF->page_settings('pflip') eq 'off';
  my $panel_flip = $CONF->panel_flip($key);
  my $yes = $panel_flip->{$key}{yes} || 0;
  my $no  = $panel_flip->{$key}{no}  || 0;
  return $yes > $no;
}

# map the reference and target coordinates to pixel locations
# to draw gridlines
sub locations2pixels {
  my ($loc,$hit,$refbox,$hitbox,$flip) = @_;

  my $reversed = $hit->start ne $hit->tstrand;

  # round to the nearest 100
  $loc = nearest(100,$loc);

  my ($ref_location,$hit_location) = $SYNTENY_IO->get_nearest_position_match($hit,$hit->src1,$loc);

  $ref_location -= $hit->start if $ref_location;
  $hit_location -= $hit->tstart if $hit_location;
  my $ref_length = $hit->end - $hit->start;
  my $hit_length = $hit->tend - $hit->tstart;
  my $ref_pixels = $refbox->[2] - $refbox->[0];
  my $hit_pixels = $hitbox->[2] - $hitbox->[0];
  my $ref_conversion = $ref_length/$ref_pixels;
  my $hit_conversion = $hit_length/$hit_pixels;
  my $ref_pixel = $refbox->[0] + int($ref_location/$ref_conversion + 0.5);
  my $hit_pixel;

  if ($flip && $reversed) {
    $hit_pixel = $hitbox->[2] - int($hit_location/$hit_conversion + 0.5);
  }
  else {
    $hit_pixel = $hitbox->[0] + int($hit_location/$hit_conversion + 0.5);
  }

  $ref_pixel = 0 if $ref_pixel < 0;
  $hit_pixel = 0 if $hit_pixel < 0;
  $hit_pixel = $hitbox->[0] if $hit_pixel < $hitbox->[0];
  $hit_pixel = $hitbox->[2] if $hit_pixel > $hitbox->[2];
  return [$ref_pixel,$hit_pixel];
}

sub grid_coords {
  my ($hit,$refbox,$hitbox,$flip,$segment) = @_;
  my $step = grid_step($segment) or return;
  my $start = nearest(100,$hit->start);
  $start += $CONF->page_settings("edge") eq 'on' ? $step : 100;

  my @pairs;
  my $offset = $start;
  until ($offset > $hit->end) {
    my $pair = locations2pixels($offset,$hit,$refbox,$hitbox,$flip);
    push @pairs, $pair;
    $offset += $step;
  }

  return @pairs;
}

# will become more sophisticated ?
sub grid_step {
  my $segment = shift;
  return nearest(100,int($segment->length/75)) || 100;
}

sub page_settings {
  my $source = $CONF->get_source;
  my $session
      = Bio::Graphics::Browser::PageSettings->new( $CONF, param('id') );
  $source ||= $session->source;
  redirect_legacy_url($source);
  my $old_source    = $session->source($source);
  $CONF->source($source);

  my $settings = get_settings($session);
  return ($settings,$session);
}

sub get_settings {
  my $session = shift;
  my $hash = $session->page_settings;
  default_settings($hash) if param('reset') or !%$hash;
  adjust_settings($hash);
  $hash->{id} = $session->id;
  return $hash;
}

sub default_settings {
  my $settings = shift;
  $settings ||= {};
  %$settings = ();
  @$settings{ 'name', 'ref', 'start', 'stop', 'version' } = ( '', '', '', '', 100 );
  $settings->{width}       = $CONF->setting('default width') || $CONF->width;
  $settings->{source}      = $CONF->source;
  $settings->{v}           = $VERSION;
  $settings->{grid}        = 1;

  my %default = DEFAULT_SETTINGS;
  foreach (keys %default) {
    $settings->{$_} = $default{$_};  
  }
  set_default_tracks($settings);
}

sub set_default_tracks {
  my $settings = shift;
  my @labels = $CONF->labels;
  $settings->{tracks} = \@labels;
  foreach (@labels) {
    $settings->{features}{$_} = { visible => 0, options => 0, limit => 0 };
  }
  foreach ( $CONF->default_labels ) {
    $settings->{features}{$_}{visible} = 1;
  }
}

sub adjust_settings {
  my $settings = shift;

  $settings->{width} = param('width') if param('width');
  my $divider = $CONF->setting('unit_divider') || 1;

  # Update coordinates. 
  local $^W = 0; # kill uninitialized variable warning
  $settings->{ref}   = param('ref');
  $settings->{start} = param('start')
      if defined param('start') && param('start') =~ /^[\d-]+/;
  $settings->{stop} = param('stop')
      if defined param('stop') && param('stop') =~ /^[\d-]+/;
  $settings->{stop} = param('end')
      if defined param('end') && param('end') =~ /^[\d-]+/;
  $settings->{version}    ||= param('version') || '0.1';
  $settings->{search_src} = param('search_src');
  $settings->{name}       = param('name');
  $settings->{name}       ||= "$settings->{ref}:$settings->{start}..$settings->{stop}"
      if defined $settings->{ref};

  param( name => $settings->{name} );

  if ( (request_method() eq 'GET' && param('ref'))
       ||
       (param('span') && $divider*$settings->{stop}-$divider*$settings->{start}+1 != param('span'))
       ||
       grep {/left|right|zoom|nav|regionview\.[xy]|overview\.[xy]/} param()
     ) {
    $CONF->zoomnav($settings);
    $settings->{name} = "$settings->{ref}:$settings->{start}..$settings->{stop}";
    param(name => $settings->{name});
  }

  my %default = DEFAULT_SETTINGS;
  foreach (keys %default) {
    if (defined param($_)) {
      $settings->{$_} = param($_);
    }
    else {
      $settings->{$_} ||= $default{$_};
    }
  }

  $settings->{name} =~ s/^\s+//; # strip leading
  $settings->{name} =~ s/\s+$//; # and trailing whitespace
  
  if ( param('reset') ) {
    %$settings = ();
     default_settings($settings);
  }
}


!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';

