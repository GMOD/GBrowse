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
#
###################################################################
\$VERSION   = $OPTIONS{VERSION};

!GROK!THIS!

print OUT "use lib '$OPTIONS{LIB}';\n" if defined $OPTIONS{LIB};

# In the following, perl variables are not expanded during extraction.

print OUT <<'!NO!SUBS!';
use strict;
use CGI qw(:standard Map Area);
use Bio::Graphics;
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Util;
use Bio::DB::GFF::SyntenyIO;
use Text::Shellwords;

use constant IMAGEWIDTH    => 800;
use constant INTERIMAGE_PAD => 4;
use constant VERTICAL_PAD => 40;
use constant IMAGE_PAD     =>  15;
use constant MAX_REGION    => 100_000;
use constant BUTTONSDIR    => '/gbrowse/images/buttons/';
use constant FINEZOOM      => '20%';
use constant ALIGN_HEIGHT  => 6;

use constant DEBUG => 1;

use vars qw($CONF_DIR $CONF $SCONF $VERSION $MAP);

# initialization
$CONF_DIR  = conf_dir($CONF_DIR);    # conf_dir() is exported from Util.pm

# open_config() is exported from Util.pm
$CONF   = open_config($CONF_DIR,'conf');
$SCONF  = Bio::Graphics::Browser->new;
$SCONF->read_configuration($CONF_DIR,'syn');

my ($source,$old_source) = get_source($SCONF);
redirect_legacy_url($source);
$SCONF->source($source);

$MAP = db_map();

print header(-cookie=>[make_cookie()],);

print start_html($SCONF->setting('description'));
print h1($SCONF->setting('description'));
mainform();
draw_image();
print hr();
print end_html();

exit 0;

sub get_source {
  my $new_source = param('source') || param('src') || path_info();
  $new_source    =~ s!^/+!!;  # get rid of leading & trailing / from path_info()
  $new_source    =~ s!/+$!!;
  my $old_source = cookie('sbrowse_source') unless $new_source && param('.cgifields');
  my $source   = $new_source || $old_source;
  $source    ||= $SCONF->source;  # the default, whatever it is
  return ($source,$old_source);
}

sub make_cookie {
  my $cookie = cookie(-name  => 'gbrowse_syn_src',
		      -value => $SCONF->source);
  return $cookie;
}

sub source_popup {
  my @sources = $SCONF->sources;
  if (@sources > 1) {
    return popup_menu(-name=>'source',
		      -values=>\@sources,
		      -labels => { map {$_ => $SCONF->description($_)} $SCONF->sources},
		      -default => $SCONF->source,
		      -override=>1,
		      -onChange => 'document.mainform.submit()'
		     );
  } else {
    return $SCONF->description($SCONF->source);
  }
}

sub search {
  my %labels = map {$_=>$MAP->{$_}{desc}} keys %$MAP;
  return p('Search',
	   popup_menu(-name=>'search_src',
		      -values=>[sort {$MAP->{$a}{desc} cmp $MAP->{$b}{desc}} keys %labels],
		      -labels=>\%labels,
		     ),
	   'with',
	   textfield(-name=>'name'),
	  );
}

sub mainform {
  my $sources = shift;
  print
    start_multipart_form(-name=>'mainform'),
    search(),
    source_popup(),
    end_form();
}

sub db_map {
  my %map;
  my @map = shellwords($SCONF->setting('source_map'));
  while (my($symbol,$db,$desc) = splice(@map,0,3)) {
    $map{$symbol}{db}   = $db;
    $map{$symbol}{desc} = $desc;
  }
  \%map;
}

sub draw_image {
  my $src = param('search_src');
  my $landmark = param('name');
  return unless defined $src && defined $landmark;

  my $segment = landmark2segment($src,$landmark) or return;

  my $io = Bio::DB::GFF::SyntenyIO->new($SCONF->setting('join')) or die;
  my @hits = $io->get_synteny_by_range(-src=>$src,
				       -ref=>$segment->abs_ref,
				       -start=>$segment->abs_start,
				       -end => $segment->abs_end);
  return unless @hits;

  # relate hits into "spans" sorted by target contig/chromosomes
  # %span = ( target_database,target_contig => { target, contig, start, end } } )
  my (%span,%hit2span);
  for my $h (@hits) {
    my $src    = $h->src2;
    my $contig = $h->target;
    my $key = join $;,$src,$contig;

    $span{$key}{start} = $h->tstart
      if !defined $span{$key}{start} or $span{$key}{start} > $h->tstart;

    $span{$key}{end}   = $h->tend
      if !defined $span{$key}{end}   or $span{$key}{end}   < $h->tend;

    $span{$key}{src}    ||= $src;
    $span{$key}{contig} ||= $contig;

    $hit2span{$h} = $key;
  }

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
  for my $h (sort {$a->start<=>$b->start} @hits) {
    my $span_key = $hit2span{$h};
    $hit_positions{$h} = ($span{$span_key}{position} ||= $position++);
  }


  # we now create feature files for the reference
  my %source_colors;
  for my $key (keys %span) {
    $source_colors{$span{$key}{src}} ||= $SCONF->setting($MAP->{$span{$key}{src}}{db}=>'color');
  }
  my $setcolor = sub {
    my $feature = shift;
    $source_colors{$feature->source};
  };

  # Create the middle (reference) panel

  my ($upper_ff,$lower_ff);
  for my $h (@hits) {
    my $is_upper = $hit_positions{$h} % 2;
    my $ff       = $is_upper ? \$upper_ff : \$lower_ff;
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

  my($ref_img,$ref_boxes) = segment2image($segment,$src,{
							 features_top    => $upper_ff,
							 features_bottom => $lower_ff,
							 background => 'peachpuff',
							}
					 ) or return;
  my $ref_title = $MAP->{$src}{desc} . ' '.format_segment($segment);

  # we now create panels and corresponding hit feature files for each of the small
  # panels
  my $refwidth     = $CONF->width;
  my $panel_count  = keys %span;
  my $panels_above = grep { $span{$_}{position} % 2 } keys %span;
  my $panels_below = $panel_count - $panels_above;
  my ($pad_top,$pad_bottom) = (0,0);
  my ($img,$boxes);

  for my $key (keys %span) {
    my $panel_position   = $span{$key}{position};
    my $is_above         = $panel_position % 2;
    my $panels_here      = $is_above ? $panels_above : $panels_below;
    my $width            = ($refwidth-($panels_here-1)*INTERIMAGE_PAD-($panels_here-1)*IMAGE_PAD*2)/$panels_here;

    my $src              = $span{$key}{src};
    my $contig           = $span{$key}{contig};
    my $start            = $span{$key}{start};
    my $end              = $span{$key}{end};
    my $name             = "${contig}:$start..$end";

    my $ff    = Bio::Graphics::FeatureFile->new;
    $ff->add_type(BLOCK => {
			    bgcolor=>$setcolor,
			    fgcolor=>$setcolor,
			    height=>ALIGN_HEIGHT,
			    glyph=>'segments',
			    label=>0,
			    box_subparts=>1});
    my @relevant_hits    = grep {$_->src2 eq $src && $_->target eq $contig} @hits;
    add_hit_to_ff($ff,$_,'invert') foreach @relevant_hits;

    my $segment          = landmark2segment($src,$name);
    my ($img,$boxes)        = segment2image($segment,
					    $src,
					    {
					     width=>$width,
					     $is_above ? (features_bottom=>$ff) : (features_top=>$ff)
					    }) or next;
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

  # total width is width of reference + INTERIMAGE_PAD pixels of padding on each side
  my $total_width = $ref_img->width + INTERIMAGE_PAD*2;

  my $gd = GD::Image->new($total_width+INTERIMAGE_PAD+1,$total_height+1,1) or return;
  $gd->saveAlpha(0);
  $gd->alphaBlending(1);
  my $white       = $gd->colorAllocate(255,255,255);
  my $black       = $gd->colorAllocate(0,0,0);
  my $cyan        = $gd->colorAllocate(0,255,255);
  $gd->filledRectangle(0,0,$gd->width,$gd->height,$white);
  my $translucent = $gd->colorAllocateAlpha(0,0,255,90);


  for my $key (keys %span) {
    my $color            = $SCONF->setting($MAP->{$span{$key}{src}}{db}=>'color');
    my $tcolor           = $gd->colorAllocateAlpha(Bio::Graphics::Panel->color_name_to_rgb($color),90);
    $span{$key}{tcolor}  = $tcolor;
  }

  my $ref_top    = $panels_above ? $pad_top + VERTICAL_PAD : INTERIMAGE_PAD;
  my $ref_bottom = $ref_top + $ref_img->height;

  # paste the individual panels into the picture
  my @map_items;
  my %x = (above=>INTERIMAGE_PAD,below=>INTERIMAGE_PAD);
  for my $key (sort {$span{$a}{position} <=> $span{$b}{position}} keys %span) {
    my $is_above = $span{$key}{position} % 2;
    my $img = $span{$key}{image};
    my $xi = $is_above ? 'above' : 'below';
    my $y  = $is_above ? $ref_top-VERTICAL_PAD()-$img->height : $ref_bottom+VERTICAL_PAD;
    $span{$key}{offsets} = [$x{$xi},$y];
    my @rect = ($x{$xi},$y,$x{$xi}+$img->width,$y+$img->height);
    $gd->copy($img,$x{$xi},$y,0,0,$img->width,$img->height);
    $gd->rectangle(@rect,$cyan);
    $x{$xi} += $img->width + INTERIMAGE_PAD;
    push @map_items,Area({shape=>'rect',
			  coords=>join(',',@rect),
			  title=>$span{$key}{title}});
  }

  # middle row (reference)
  my @rect = (INTERIMAGE_PAD,$ref_top,INTERIMAGE_PAD+$ref_img->width,$ref_top+$ref_img->height);
  $gd->copy($ref_img,INTERIMAGE_PAD,$ref_top,0,0,$ref_img->width,$ref_img->height);
  $gd->rectangle(@rect,$cyan);
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
    my ($rx1,$ry1,$rx2,$ry2) = @{$ref_boxes{$feature}};
    my ($px1,$py1,$px2,$py2) = @{$panel_boxes{$feature}};
    my $poly = GD::Polygon->new();
    my $upper = $py2 < $ry1;
    if ($upper) { # an upper panel          # This works - but can be simplified!
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
  print img({-src=>$url,-border=>0,-usemap=>'#mymap'});
  print Map({-name=>'mymap'},@map_items);
}

sub segment2image {
  my ($segment,$src,$options) = @_;
  return unless $segment;

  my $width           = $options->{width};
  my $features_top    = $options->{features_top};
  my $features_bottom = $options->{features_bottom};
  my $background      = $options->{background} || 'white';

  my $dsn = $MAP->{$src}{db} or return;
  my @tracks    = shellwords($SCONF->setting($dsn => 'tracks'));
  my $ff_scale  = Bio::Graphics::FeatureFile->new;
  $ff_scale->add_type(SCALE=>{fgcolor=>'black',glyph=>'arrow',tick=>2,double=>1,description=>0});
  $ff_scale->add_feature($segment=>'SCALE');

  my @labels;
  if ($features_top && $features_bottom) {
    @labels = ('ff_top','ff_scale',@tracks,'ff_bottom');
  } elsif ($features_top) {
    @labels = ('ff_top',@tracks,'ff_scale');
  } elsif ($features_bottom) {
    @labels = ('ff_scale',@tracks,'ff_bottom');
  } else {
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
  $CONF->width($width) if defined $width;
  $CONF->setting('general','image_padding' => IMAGE_PAD);
  $CONF->setting('general','detail bgcolor'=> $background);

  my ($img,$boxes) = $CONF->image_and_map(
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
  my $dsn = $MAP->{$src}{db} or return;
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
    if (my $p = $hit->parts) {
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
    } else {
      $feature = Bio::Graphics::Feature->new(-type => 'BLOCK',
					     -name => $hit->name,
					     -seqid=> $hit->target,
					     -start=> $hit->tstart,
					     -source  => $hit->src2,
					     -end  => $hit->tend,
					     @attributes,
					    );
    }

  } else { # construct the feature from the src coordinates
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
    } else {
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
!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
