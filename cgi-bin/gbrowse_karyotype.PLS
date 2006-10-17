#!perl

use Config;
use File::Basename qw(&basename &dirname);
use File::Spec;
use FindBin '$Bin';
use Cwd;

my %OPTIONS;
if ( open F, "$Bin/../GGB.def" ) {
  while (<F>) {
    next if /^\#/;
    chomp;
    $OPTIONS{$1} = $2 if /^(\w+)\s*=\s*(.+)/;
  }
  close F;
}
$OPTIONS{CONF} ||= '/usr/local/apache/conf';

my $dir = dirname($0);
$file = shift || File::Spec->catfile( $dir, basename( $0, '.PL', '.PLS' ) );

open OUT, ">$file" or die "Can't create $file: $!";

print "Extracting $file (with variable substitutions)\n";
my $startperl =
    $Config{startperl} ne '#!perl'
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
#$Id: gbrowse_karyotype.PLS,v 1.6 2006-10-17 20:36:42 sheldon_mckay Exp $

use strict;
use CGI::Carp 'fatalsToBrowser';
use CGI qw/:standard delete/;
use CGI::Pretty 'html3';
use GD;
use GD::Image;
use Bio::DB::GFF::Feature;
use Bio::Graphics::Browser::Util;
use Bio::Graphics::Browser;
use Bio::Graphics::Panel;
use Bio::Graphics::FeatureFile;
use Text::Shellwords;
use File::Spec;
use List::Util qw/min max/;
use IO::Socket;

use vars qw($CONFIG $CONF_DIR $STANDALONE);

use constant PAD_TOP           => 10;
use constant PAD_BOT           => 20;
use constant PAD_RIGHT         => 40; # space for band labels
use constant PAD_RIGHT_NOLABEL => 10;
use constant HELP_DIR          => "$ENV{DOCUMENT_ROOT}/gbrowse";
use constant BGCOLOR           => 'gneg:white gpos25:silver gpos50:grey gpos:grey '.
                                  'gpos75:darkgray gpos100:black gvar:var stalk:#666666 tip:black';

# This may be wrong if non-standard HTDOCS config
use constant HELP_URL          => "/gbrowse/gbrowse_karyotype_help.html";


use Data::Dumper;

$| = 1;

# set the database source (OK not to have one)
my $src = param('src') || param('source') || path_info() || 'none';
$src    =~ s!^/+!!;  # get rid of leading / from path_info()
$src    =~ s!/+$!!;  # get rid of trailing / from path_info()

#if ($src eq 'none') {
$STANDALONE = 1 if $src eq 'none';
$CONF_DIR = conf_dir($CONF_DIR);
$CONFIG   = open_config($CONF_DIR);

$CONFIG->source($src eq 'none' ? 'Gbrowse_karyotype' : $src);

my $feature_text  = param('featuretext');
my @add_features  = (param('add'),   param('a')); # overlay features
my @add_style     = (param('style'), param('s')); # overlay features style
my @track_types   = (param('type'),  param('t')); # built in track types to turn on
my $labels        = \@track_types;
my $embed         = 1 if param('embed') || param('e'); # binary image or HTML output
my %configured;
my %styled;

# look for name of the cytobands track and ideogram drawing info
# CGI params take precedence over the config file

# Is there a configuration for the chromosome ideogram?
my $cytoband    = $CONFIG->karyotype_setting('cytoband_track') || 'null';

# How tall should the biggest chromosome be?
my $max_height  = param('cheight') || param('h') 
               || $CONFIG->karyotype_setting('max_height') 
               || $CONFIG->karyotype_setting('cheight') || 500;

# How many rows in the karyotype?
my $rows        = param('rows')    || param('r') 
               || $CONFIG->karyotype_setting('rows') || 'auto';

# Chromosomw width?
my $chrom_width = param('cwidth')  || param('w') 
               || $CONFIG->setting($cytoband => 'height') 
               || $CONFIG->karyotype_setting('cwidth') || 20;

# Add labels to chromosome bands?
my $band_labels = param('band_labels') || param('b') 
               || $CONFIG->karyotype_setting('band_labels');

# Make background transparent?
my $transparent = param('transparent') || param('tr')
               || $CONFIG->karyotype_setting('transparent');

# What feature types are to be considered chromosome parts?
# It must be defined somehow
my $band_feats  = lc (param('bands') || param('ba')
               || $CONFIG->karyotype_setting('bands')
               || $CONFIG->setting($cytoband => 'feature'))
               || 'chromosome_band centromere cytoband';

my $useform     = param('useform') || param('f')
               || $CONFIG->karyotype_setting('useform');


# Clear certain CGI parameters to avoid confusing deployment cases
CGI::delete('useform');
CGI::delete('f');
CGI::delete('src');
CGI::delete('source');


###################################
# Deployment
###################################

if (param('list')) {
  dump_sources() if param('list') eq 'sources';
  dump_types()   if param('list') eq 'types';
  exit 0;
}
elsif ($embed) {
  print header(), start_html( -title => 'gbrowse-karyotype');
}
elsif ($useform && !param()) {
  print header;
  front_page();
}
elsif ((!param() && $STANDALONE) || param('help')) {
  print header, start_html('gbrowse_karyotype');
  build_help_page();
}
else { # I guess we are drawing then
  print header('image/png');
}

# identity and order of chromosomes to draw
my $chr_data = param('chromosome') || param('c') || $CONFIG->karyotype_setting('chromosome');
#$chr_data or  die "No chromosomes specified for $src";
my ($chrom_length,@chr) = chromosome_data($chr_data);
my %chr;

my $feature_file;
if ($feature_text) {
  # no leading whitespace
  $feature_text =~ s/^\s+//gm;
  $feature_file = Bio::Graphics::FeatureFile->new( -text => $feature_text,
						   -smart_features => 1,
						   -safe => undef
						   );
}

# Last resort, see if we can find chromosomes in the external annotations
if (!@chr && defined $feature_file) {
  unless (@chr) {
    ($chrom_length,@chr) = look_for_chromosomes($feature_text);
  }
}

if (!@chr) {
  fatal_error('No chromosome data');
}


# Find the longest chromosome in the set
my $longest = 0;
my $master_seg;
for my $chr (@chr) {
  my $seg = get_segment($chr) || die "$chr not found in the database";

  if ($seg->length > $longest) {
    $longest = $seg->length;
  }
  $chr{$chr} = $seg;
}

my (%img,$styles,$black,$white,$title);
my $max_width = 0;

my $band_regex = join('|',shellwords($band_feats));
$band_regex    = qr/$band_regex/;
my $chr_regex  = join('|',@chr);

# check for unmappable features
my @bad_feats = grep { !/^$chr_regex\s+/ } @add_features;
if (@bad_feats) {
  my $bad = join "\n", @bad_feats;
  fatal_error("The following add features are improperly formatted:", pre($bad));
}

my $fw = gdMediumBoldFont->width;
my $max_string_width;
for my $chr (@chr) {
  my $seg = $chr{$chr};

  # How wide will the chromosome label be?
  my $str_width = (length $chr) * $fw;
  $max_string_width = $max_string_width 
                    ? max($str_width,$max_string_width)
                    : $str_width; 

  my $feature_list = {};
  my @local_features;
  my @band_features;
  my @styles;

  # features supplied by URL
  if (@add_features && !$feature_text) {
    # just worry about the features on this chromosome
    @local_features = grep { (split)[0] eq $chr } @add_features;

    if ($band_regex) {
      @band_features  = grep { /$band_regex/ } @local_features;
      @local_features = grep {!/$band_regex/ } @local_features;
    }

    @styles         = @add_style;
  }
  # or as a Bio::Graphics::FeatureFile
  elsif ($feature_text) {
    # just worry about the features on this chromosome
    my @this_chromosome = grep { $_->ref eq $chr } $feature_file->features;
    @local_features  = grep {$_->method !~ /$band_regex/i} @this_chromosome;
    @band_features   = grep {$_->method =~ /$band_regex/i} @this_chromosome;
    @styles          = map  { [$_, my_style($_)] } $feature_file->configured_types;
  }

  if (@local_features) {
    add_features($seg,\@local_features,\@styles,$feature_list,'add');
  }

  my $bands = [];
  if (@band_features) {
    add_features($seg,\@band_features,\@styles,$feature_list,'band');
    @$bands = map {$_->type} grep {ref $_} @band_features;
    push @$bands, grep {!ref $_} @band_features;
  }
  else {
    @$bands = shellwords($band_feats);
  }


  my ($panel, $boxes) = my_image_and_map( segment       => $seg,
					  tracks        => $labels,
					  feature_files => $feature_list,
					  bands         => $bands);

  my $gd = $panel->gd;
  $black ||= $panel->translate_color('black');
  $white ||= $panel->translate_color('white');

  # rotate the image 90 degrees clockwise
  my $img    = $gd->copyRotate90();
  my ($w,$h) = $img->getBounds();
  $max_width = $w if $w > $max_width;
  
  if ($max_width < $max_string_width + 5) {
    $max_width = $max_string_width + 5;
  }

  # reorient the boxes for image mapping by
  # flipping x + y and adjusting horizontal offsets
  for my $box (@$boxes) {
    my ($y1,$x1,$y2,$x2) = @$box[1..4];
    $x1 = $w - $x1;
    $x2 = $w - $x2;
    ($x2,$x1) = ($x1,$x2);
    @$box[1..4] = ($x1,$y1,$x2,$y2);
  }

  $img{$chr} = [$img,$boxes];
}

# dynamic row calculation if required;
$max_width += $band_labels ? PAD_RIGHT : PAD_RIGHT_NOLABEL;
$rows = int(($max_width/1024 * @chr)+1) if $rows eq 'auto';
my $new_row = int @chr/$rows;

# adjust image  widths for even chromosome 
# spacing and labels
for my $chr (@chr) {
  my ($gd,$boxes) = @{$img{$chr}};
  my ($w,$h)  = $gd->getBounds();
  my $offset = $max_width - $w;
  $offset -= $band_labels ? PAD_RIGHT : PAD_RIGHT_NOLABEL;
  my $img = GD::Image->new($max_width,$h);
  $img->copy($gd,$offset,0,0,0,$w,$h);

  my $where_was_i = 0;
  my $chr_offset;
  for my $box (@$boxes) {
    $box->[1] += $offset;
    $box->[3] += $offset;

    if ($box->[0]->method =~ /$band_regex|synthetic_chromosome/) {
      $chr_offset = $box->[1];
    }

    if ($band_labels) {
      my $feature = $box->[0];
      next unless $feature->method =~ /$band_regex/i;
      next if $feature->method =~ /centromere/i;

      my $x = $box->[3] + 2;
      my $y = $box->[2];
      
      # skip very narrow bands
      my $band_width = $box->[4] - $box->[2];
      next if $band_width < $max_height/200;
      
      # adjust vertical label placement
      if ($band_width < $max_height/50) {
	$y -= 2;
      }
      elsif ($band_width > $max_height/40) {
	$y = $y + $band_width/2 - 4; # 4 is 1/2 the font height                                                                                                       
      }
    
      # only add a label if there is room
      next if ($y - $where_was_i) <= 8;
      $where_was_i = $y;
      my ($band_name) = $feature->attributes('Name');

      $img->string(gdTinyFont,$x,$y,"-$band_name",$black) if $band_name;
    }

  } 

  # There is something wrong if we have no chromosome offset
  fatal_error('No chromosome offset') unless $chr_offset;

  # chromosome label
  my $string_width = $fw * (length $chr);
  my $mid  = $chr_offset + int($chrom_width/2);
  my $x    = $mid - int($string_width/2 + 0.5);
  my $y    = $h - 12;
  $img->string(gdMediumBoldFont,$x,$y,$chr,$black);

  if ($transparent) {
    my $almost_white = $img->colorResolve(255,255,254);
    $img->fill(0,0,$almost_white);
    $img->transparent($almost_white);
    $img->interlaced('true');
  }

  $img{$chr} = [$img,$boxes];
}

# now consolidate all of the images
my ($new_img,$new_boxes) = consolidate_images(\%img,$rows,$max_width,$transparent);
my $map = my_make_map($new_boxes,$feature_file);

if ($embed) {
  #print h2({-align => 'center'}, ucfirst $src);
  print img( 
	     { -src => $CONFIG->generate_image($new_img), 
	       -usemap => '#hmap', 
	       -border => 0 }
	     ), $map;
}
else {
  print $new_img->png;
}


## Subroutines ##
## several were borrowed and modified from gbrowse and gbrowse_img ##

# avoid multiple segment hangups, just return the first

sub get_segment {
  my $name = shift;
  
  unless ($STANDALONE) {
    my $db = open_database($CONFIG);
    my @segments;
    my @matches = $CONFIG->name2segments($name,$db);
    push @matches, $CONFIG->name2segments(ucfirst $name,$db);
    push @segments,@matches;
    $_->absolute(1) foreach @matches;
    my ($segment_to_return) = grep {defined $_} @segments;
    return $segment_to_return;
  }
  else {
    my $end = $chrom_length->{$name};
    $end or die "No length information for chromosome $name";
    return Bio::Graphics::Feature->new( -start  => 1, 
					-stop   => $end,
					-type   => 'chromosome',
					-seq_id => $name);
  }

}

sub message {
  my @msg = @_;
  print header();
  print start_html,
        h1('Error'),
        p(@msg),
  end_html;
  exit 0;
}

# put all of the chromosomes into one image and
# adjust the image maps accordingly
sub consolidate_images {
  my ($images,$rows,$max_width,$trans) = @_;

  # maximum chromosome height for each row
  my $new_row = int @chr/$rows;
  my @row_heights;
  my ($row_height,$idx,$row) = (0,0,0);
  for my $ref (@chr) {
    my $gd = $images->{$ref}->[0];
    my $h = $gd->height;
    $row_height = $h if $h > $row_height;
    if (++$idx >= $new_row) {
      push @row_heights, $row_height;
      ($row_height,$idx) = (0,0);
    }
  }
  push @row_heights, $row_height if $row_height;

  # overall consolidated image size
  my $overall_height;
  map {$overall_height += $_} @row_heights;
  my $overall_width = $max_width * @chr;
  $overall_width = $overall_width/$rows;

  my $composite = GD::Image->new($overall_width,$overall_height);
  my $almost_white = $composite->colorResolve(255,255,254);
  $composite->fill(0,0,$almost_white);
  $composite->transparent($almost_white) if $trans;
  $composite->interlaced('true');

  my @boxes;

  ($row,$idx) = (0,0);
  for my $ref (@chr) {
    my ($gd,$boxes) = @{$images->{$ref}};
    my ($w,$h) = $gd->getBounds;

    if (++$idx > $new_row) {
      $row++;
      $idx = 1;
    }

    my $xoffset = ($idx-1) * $w;
    my $yoffset = $row_heights[$row] - $h;
    for (0..($row-1)) {
      $yoffset += $row_heights[$_];
    }

    $composite->copy($gd,$xoffset,$yoffset,0,0,$w,$h);
    
    # re-fit boxes
    for my $box (@$boxes) {
      $box->[1] += $xoffset;
      $box->[2] += $yoffset;
      $box->[3] += $xoffset;
      $box->[4] += $yoffset;
      push @boxes,$box;
    }
  }

  return ($composite,\@boxes);
}

sub my_make_map {
  my ($boxes,$ff) = @_;
  my $html = qq(<map name="hmap" alt="imagemap" />\n);

  my $last_y = 0;
  for (@$boxes){
    my $f = $_->[0];
   
    # skip the whole-chromosome box
    next if $f->method eq 'synthetic_chromosome';
    next if $f->method eq 'Component';

    my $w = $_->[5]->option('height');    

    # repair zero-height boxes ?!
    my $h = $_->[4] - $_->[2];
    if ($h == 0) {
      $_->[4] = int($_->[2] + $w/2 + 0.5);
      $_->[2] = int($_->[2] - $w/2 + 0.5);
    }

    $_->[2]++ if $_->[2] == $last_y;
    $last_y = $_->[4];

    my %att = $f->attributes;
    my $title  = $att{Name} ||$att{Alias} || $f->desc || $f->name || $f->display_id;
    #Bio::Graphics::Featurefile returns array refs
    $title = $title->[0] if ref $title;

    if ($title =~ /(\S+)_cent/) {
      $title = "centromere:$1";
    }
    $title = $title ? qq(title="$title") : '';

    my $url = eval{$f->url} || $att{url} || $att{link};
    $url = $url->[0] if ref $url; 
    my $href = $url ? qq(href="$url" target="_parent") : q{};

    
    my ($start,$stop) = ($f->start,$f->end);
    my $coords = join(',',map {int($_+0.5)} @{$_}[1..4]);
    $html .= qq{<area $href $title shape="rect" coords="$coords"/>\n}
        if $title || $href;
  }
  $html .= "</map>\n";

  return $html;
}

sub add_features {
  my ($segment,$features,$styles,$feature_hash,$category) = @_;
  my @features = @$features;
  my @styles   = @$styles;

  my $feature_list = Bio::Graphics::FeatureFile->new(
						     -smart_features  => 1,
						     -safe => undef 
						     );

  # we need some style info for bands
  my @band_styles;
  OUTER: for my $t (shellwords($band_feats)) {
    my $have_style;
    INNER: for my $s (@styles) {
      if (ref $s) {
	next INNER if $s->[0] ne $t;
	next OUTER if $s->[1]->{bgcolor};
	$s->[1]->{bgcolor} = BGCOLOR;
	$have_style++;
      }
      else {
	my ($type,@options) = shellwords($s);
	next INNER unless $type eq $t;
	my %options ={ map {split /=/} @options };
	next OUTER if $options{bgcolor};
	$options{bgcolor} = BGCOLOR;
	$s = [$type,\%options];
	$have_style++;
      }
      
      unless ($have_style) {
	push @styles, [$t,{bgcolor=>BGCOLOR}];
      }
    }
  }

 my %add_style; 
 for my $s (@styles) {
    my ($type, $options);
    if (ref $s) { # already parsed
      ($type,$options) = @$s;
    }
    else {
      ($type,my @options) = shellwords($s);
      $options ={ map {split /=/} @options };
      $s = [$type,$options];
    }
    $add_style{$type} = $options;
  }
    
  my $td = 'TRACK DEFAULT';
  my %default_style = ( 
			label       => $CONFIG->setting($td => 'label') || 0,
			description => $CONFIG->setting($td => 'description') || 0,
			bgcolor     => $CONFIG->setting($td => 'bgcolor') || 'black',
			glyph       => $CONFIG->setting($td => 'glyph') || 'triangle',
			fgcolor     => $CONFIG->setting($td => 'fgcolor') || 'black',
			height      => $CONFIG->setting($td => 'height') ||10,
			linewidth   => $CONFIG->setting($td => 'linewidth') || 1,
			orient      => $CONFIG->setting($td => 'orient') || 'E',
			point       => $CONFIG->setting($td => 'point') || 1,
			link        => $CONFIG->setting($td => 'link') || 0
		       );

  for my $f (@features) {
    my $type;
    # feature objects
    if (ref $f) {
      $feature_list->add_feature($f);
      # remove attribute=value pairs from description
      my $desc = $f->desc || '';
      $desc =~ s/\w+=\S+(;|\s+)?//g;
      $desc =~ s/^\s+|\s+$//g;
      $f->desc($desc);
      $type = $f->type;
    }
    # or add string
    else {
      my ($ref,$t,$name,$segments,$tag) = my_parse_feature_str($f);

      $type = $t;

      my @parts = @$segments;  

      my @other_args = ();
      
      if ($tag && ref $tag) {
	if (my ($d) = grep {/desc/} keys %$tag) {
	  push @other_args, (-desc => $tag->{$d});
	}
	if (my ($url) = grep {/url|link/} keys %$tag) {
	  push @other_args, (-url => $tag->{$url});
	  delete $tag->{$url};
	}
	if (%$tag) {
	  push @other_args, (-attributes => $tag);
	} 
      }

      my $strand = $parts[0][0]<=$parts[0][1] ? +1 : -1;
      push @other_args, (-strand => $strand);

      if (@parts == 1) {
	push @other_args, ( -start => min(@{$parts[0]}),
			    -end  => max(@{$parts[0]}) );
      }
      else {
	push @other_args, ( -segments => \@parts );
      }

      $type = 'chromosome_band' if $category eq 'band' && $type ne 'centromere';       
      my $feature = Bio::Graphics::Feature->new(
						-ref      => $ref||'',
						-type     => $type||'',
						-name     => $name||'',
						@other_args
						);
      $feature_list->add_feature($feature);
    }

    
   unless ( defined $styled{$segment}{$type} ) { 
      my ($type_style) = grep {$_->[0] eq $type} @styles;
      $type_style ||= [$type,{}];
      my $options = $type_style->[1];
      for my $k (keys %default_style) {
	$options->{$k} = $add_style{$type}{$k} || $default_style{$k};
      }
      push @styles, $type_style;
      $styled{$segment}{$type}++;
    }
  }
  
  
  for my $s (@styles) {
    my ($type,$options) = @$s;

    for my $option (keys %default_style) {
      $options->{$option}  ||= $add_style{$type}{$option} || $default_style{$option};
    }

    # adjust pointy glyph orientation to allow for
    # horizontal to vertical rotation.
    #$options->{orient} = adjust_compass($options->{orient});

    if ($options->{glyph} eq 'xyplot') {
      $options->{label} = 1;
      $options->{description} = 1;
    }

    # add some mix and match capability
    add_callbacks($type,$segment,$options);

    $feature_list->add_type($type => $options);

  }

  push @$labels, 'add' unless grep { $_ eq 'add' } @$labels;

  $feature_hash->{$category} = $feature_list;
}

# adjust perspective for a 90 degree clockwise rotation
sub adjust_compass {
  my $dir = shift || 'E';
  return 'E' if $dir eq 'S';
  return 'W' if $dir eq 'N';
  return 'N' if $dir eq 'E';
  return 'S' if $dir eq 'W';
}

# Use the description field to supply certain
# feature-specific attributes to allow mixing
# of colors, glyphs, etc, within a single track
sub add_callbacks {
  my $type = shift;
  my $segment = shift;
  return 0 if ++$configured{$type}{$segment} > 1;
  my $options_ref = shift;

  my @attributes = qw( point label bgcolor glyph fgcolor height linewidth orient );

  for my $att (@attributes) {
    my $default_value = $options_ref->{$att} || 0;

    $default_value = adjust_compass($default_value) if $att eq 'orient';

    # Intercept suspicious attribute values; 
    # only pass letters, numbers or hexadecimal color codes
    if ( $default_value =~ /^sub|[^ \#\w\:]/ ) {
      fatal_error(
	       h1( "$att $default_value for attribute $att contains invalid characters. ",
		   " Please consult the documentation.")
	       );
      
    }

    # The callback
    $options_ref->{$att} = sub { 
      my $f = shift;
      my ($override) = $f->attributes("$att");
      # careful about shell characters
      undef $override if $override && $override =~ /^sub|[^\#\w]/; 
      return $override || $default_value;
    }
  }

  $options_ref->{url} = sub {
    my $f = shift;
    my @url = ($f->attributes('url'),f->attributes('link'));
    return $f->url || $url[0];
  };

}


# give the URL a onceover
sub check_url {
  my $url = shift;
  return 1 if $url =~ m|(https?://)?([-\w\.]+)+(:\d+)?(/([\w/_\.]*(\?[^ \w\#\.;~&]+)?)?)?|;
  die "invalid URL: $url";
}

sub my_image_and_map {
  my %config  = @_;

  my $segment       = $config{segment};
  my $feature_files = $config{feature_files} || {};
  my $tracks        = $config{tracks}        || [];
  my $options       = $config{options}       || {};
  my $length        = $segment->length;
  my $conf          = $CONFIG->config;
  my $band_feats    = $config{bands}         || [];

  my @feature_types = $STANDALONE ? @$tracks : map { $CONFIG->label2type($_,$length) } @$tracks;

  # scale horizontal panel width by chromosome size
  my $width = int(($segment->length/$longest)*$max_height);

  my @argv = (
              -grid      => 0,
              -start     => 1,
              -end       => $segment->length,
              -bgcolor   => '#FFFFFE',
              -width     => $width,
              -pad_left  => PAD_TOP,
	      -pad_right => PAD_BOT,
	      -key_style => 'none',
	      );

  my $panel = Bio::Graphics::Panel->new(@argv);

  my (%track2label,%tracks,@blank_tracks);

  my $max_bump = $CONFIG->bump_density;

  for (my $i= 0; $i < @$tracks; $i++) {

    my $label = $tracks->[$i];

    # if we don't have a built-in label, then this is a third party annotation
    if (my $ff = $feature_files->{$label}) {
      push @blank_tracks,$i;
      next;
    }

    my $lang = $CONFIG->language;
    my @settings = ($conf->default_style,$conf->i18n_style($label,$lang,$length));
    my $track = $panel->add_track(-glyph => 'generic',@settings);
    $track2label{$track} = $label;
    $tracks{$label}      = $track;
  }

  if (@feature_types && !$STANDALONE) {  # don't do anything unless we have features to fetch!
      
    my $iterator = $segment->get_feature_stream(-type=>\@feature_types);
    my (%groups,%feature_count,%group_pattern);
    
    while (my $feature = $iterator->next_seq) {
      
      # allow a single feature to live in multiple tracks
      for my $label ($CONFIG->feature2label($feature,$length)) {
	my $track = $tracks{$label}  or next;
	
	$feature_count{$label}++;
	
	# Handle name-based groupings.  Since this occurs for every feature
	# we cache the pattern data.
	exists $group_pattern{$label} or $group_pattern{$label} = $conf->code_setting($label => 'group_pattern');
	
	if (defined $group_pattern{$label}) {
	  push @{$groups{$label}},$feature;
	  next;
	}
	
	$track->add_feature($feature);
      }
    }
    
    # handle pattern-based group matches
    for my $label (keys %groups) {
      my $set     = $groups{$label};
      my $pattern = $group_pattern{$label} or next;
      $pattern =~ s!^/(.+)/$!$1!;  # clean up regexp delimiters
      my %pairs;
      for my $a (@$set) {
	(my $base = $a->name) =~ s/$pattern//i;
	push @{$pairs{$base}},$a;
      }
      my $track = $tracks{$label};
      foreach (values %pairs) {
	$track->add_group($_);
      }
    }
    
    # configure the tracks based on their counts
    for my $label (keys %tracks) {
      next unless $feature_count{$label};
      
      $options->{$label} ||= 0;
      
      my $count = $feature_count{$label};
      
      my $do_bump  = $CONFIG->do_bump($label, $options->{$label},$count,$max_bump,$length);
      
      $tracks{$label}->configure( -bump  => $do_bump );
      $tracks{$label}->configure( -connector  => 'none') if !$do_bump;
    }
  }
  
  # add additional features, if any
  my $offset = 0;
  my $select = sub {
    my $file  = shift;
    my $type  = shift;
    my $section = $file->setting($type=>'section');
    return 1 unless defined $section;
    return $section =~ /detail/;
  };

  for my $track (@blank_tracks) {
    my $file = $feature_files->{$tracks->[$track]} or next;
    ref $file or next;
    $track += $offset;
    my $name = $file->name || '';
    $options->{$name} ||= 0;
    my ($inserted,undef,$new_tracks)
	= eval { $file->render($panel,$track,$options->{$name},
			       $max_bump,undef,
			       $select
			       )
		   };
    $CONFIG->error($@) if $@;
    foreach (@$new_tracks) {
      $track2label{$_} = $file;
    }
    $offset += $inserted-1; # adjust for feature files that insert multiple tracks
  }
  
  # Be agnostic about aggregation
  my @bands;
  if (defined $feature_files->{band}) {
    for my $f ($feature_files->{band}->features) {
      if (my @sf = $f->segments) {
        push @bands, @sf;
      }
      else {
        push @bands, $f;
      }
    }
  }
  if ($segment->can('features')) {
    for my $f ($segment->features(-type => $band_feats)) {
      if (my @sf = $f->segments) {
	push @bands, @sf;
      }
      else {
	push @bands, $f;
      }
    }
  }

  # Add a whole chromosome in case there are no bands or the band coverage
  # is not complete.  The bands are subfeats
  my   $chrom = Bio::Graphics::Feature->new ( -start  => $segment->start,
					      -stop   => $segment->end,
					      -type   => 'synthetic_chromosome',
					      -segments => (@bands ? \@bands : []));


  # need to pass along the subfeatures for band-labelling/image mapping
  my $bands = $band_labels ? [$chrom,@bands] : [$chrom];

  $panel->unshift_track(\@bands,
                        -bump        => 0,
                        -glyph       => $CONFIG->setting($cytoband => 'glyph')     || 'ideogram',
                        -height      => $chrom_width,
                        -arcradius   => $CONFIG->setting($cytoband => 'arcradius') || $max_height/100,
                        -bgcolor     => $CONFIG->setting($cytoband => 'bgcolor')   || BGCOLOR,
                        -fgcolor     => $CONFIG->setting($cytoband => 'fgcolor')   || 'black',
                        -invisible   => ($band_labels ? 1 : 0),
			# These options only apply to a heat_map_ideogram
                        -start_color => $CONFIG->setting($cytoband => 'start_color') || 'white',
                        -end_color   => $CONFIG->setting($cytoband => 'end_color')   || 'red',
                        -min_score   => $CONFIG->setting($cytoband => 'min_score')   || 0,
                        -max_score   => $CONFIG->setting($cytoband => 'max_score')   || 100,
                        );

  return ($panel, [$panel->boxes]);
}

sub front_page {
  my $page_header = my_html_frag('header')     || page_header();
  my $page_footer = my_html_frag('footer')     || page_footer(); 
  my $input_form  = my_html_frag('input_form') || input_form();
  my $html_header = '';
  my $script      = example_script();

  $page_header = start_html(-titel => 'gbrowse_karyotype', -script => $script) . $page_header 
      unless $page_header =~ /<html/i;
  $page_footer = end_html . $page_footer 
      unless $page_footer =~ /<\/html/i;

  print join("\n",$page_header,$input_form,$page_footer);
  exit 0;
}

sub input_form {
  my $source_menu = source_menu();
  my $cytoband    = $CONFIG->karyotype_setting('cytoband');
  my $height      = $CONFIG->setting($cytoband => 'max_height') 
                 || $CONFIG->karyotype_setting('max_height') || 500;

  return <<END;
  <form method="post" enctype="multipart/form-data" name="f1">
  <p>
  $source_menu
  </p>
  <p>Maximum chromosome height (pixels)&nbsp;
  <input name=cheight value=$max_height size=5></p>
  <p>Chromosome width&nbsp;
  <input name=cwidth value=$chrom_width size=5>
  &nbsp;&nbsp;Number of rows&nbsp;
  <select name=rows>
    <option value=auto>auto</option>
    <option value=1>1</option>
    <option value=2>2</option>
    <option value=3>3</option>
    <option value=4>4</option>
  </select>
  </p>
  <p>
  Label chromosome bands <input type=checkbox name=band_labels value=1 checked>
  &nbsp;&nbsp;&nbsp;
  Add mousover labels to image <input type=checkbox name=embed value=1 checked>
  </p>
  <p>
  Paste your feature data below (optional)
  <br>
  <textarea name="featuretext" rows="15" cols="60">
  </textarea>
  </p>
  <input type="submit" name="Draw" value="Draw"/>&nbsp;&nbsp;
  <input type="button" value="Example" onclick="showExample()"/>&nbsp;&nbsp;
  <input type="button" value="Erase"   onclick="hideExample()"/>&nbsp;&nbsp;
  <input type="reset" name="Reset" value="Reset" />
  </form>
END
}

sub page_header {
  my $text = sample_text();
  my $helpfile = HELP_URL;

  return <<END;
  <div id="exampleText" style="display:none">
  $text
  </div>
  <h2>gbrowse_karyotype</h2>
  <h3>Draw karyotypes and map feature data via the Generic Genome Browser</h3>
  <a style="cursor:help" title="help and program description" href=$helpfile>help and program description</a>
END
}

sub page_footer {
  return <<END;
  <hr>
  For the source code for this browser, see the <a href="http://www.gmod.org"> Generic Model Organism Database Project.</a>  
  <br>
  For other questions, send mail to <a href="mailto:mckays\@cshl.edu">mckays\@cshl.edu</a>.
  </p>
END

}

sub help_line {
  return <<END;
  Adding your own data: &nbsp;&nbsp;
  <a href="/cgi-bin/gbrowse_karyotype?help=URL" target="_blank">[image generator]</a>
  &nbsp;&nbsp;&nbsp;
  <a href="/cgi-bin/gbrowse_karyotype?help=annotation" target="_blank">[interactive browser]</a>
END
}

sub source_menu {
  my $html = "<p>Species\&nbsp;\n";
  my $url = self_url;
  $url =~ s/karyotype.+/karyotype/;
  $html .= "<select name=src>";
  for my $source ($CONFIG->sources) {
    $CONFIG->source($source);
    next unless $CONFIG->karyotype_setting('cytoband_track')
	     || $CONFIG->karyotype_setting('chromosome');
    my $selected = $source eq $src ? " selected=selected" : '';
    $html .= "<option value=$source$selected>$source</option>\n</p>";
  }
  $html .= "</select>\n";
  return $html;
}


# remove '-' from option keys
sub my_style {
  my $type = shift;
  my %options = $feature_file->style($type);
  my $options = {};

  while (my ($k,$v) = each %options) {
    $k =~ s/^-//;
    $options->{$k} = $v;
  }
  
  return $options;
}

sub sample_text {

  return <<END;

##########################################
##  Hit 'Erase' to clear this example   ##
##########################################

## Default display options for gene ##
[gene]
glyph   = triangle
bgcolor = red
fgcolor = red
height  = 7
bump    = 1

[mutation]
glyph   = lightning
bgcolor = yellow
fgcolor = black
height  = 15

# chromosome 1
reference=1
gene gene1 20000001..20006000 "Carbonic Anhydrase gene" 
gene gene2 20066001..20069000 "ADH gene"
gene gene3 50000001..50006000 bgcolor=blue;fgcolor=blue;glyph=dot;description="Unknown gene"

# chromosome 5
reference=5
gene gene4 20000001..20006000 bgcolor=white
gene gene5 30006001..30009000
gene gene6 80000001..80006000
mutation allele2 30006001..30009000 link=http://www.nasa.gov;description="cosmic radiation damage"
END

}

sub dump_sources {
  print header('text/plain');
  print "## Sources\n";
  for my $source ($CONFIG->sources) {
    $CONFIG->source($source);
    next unless $CONFIG->setting('karyotype' => 'cytoband_track') 
             || $CONFIG->setting('karyotype' => 'chromosome');
    print "$source\n";
  }
}

sub dump_types {
  print header('text/plain');
  print "## Built-in feature types for source ",$CONFIG->source,"\n";
  my @labels  = $CONFIG->labels;
  my %default = map {$_=>1} $CONFIG->default_labels;
  for my $l (@labels) {
    next if $l eq $cytoband;
    my $d = $default{$l} ? 'default' : '';
    my $key = $CONFIG->setting($l=>'key')||'';
    print join("\t",$l,$key,$d),"\n";
  }
}

sub build_help_page {
  my $helpfile = shift || "gbrowse_karyotype_help.html";
  my $file = HELP_DIR . "/$helpfile";
  open(F,$file) or return;
  print while (<F>);
  close F;
  print end_html;
  exit 0;
}

sub my_html_frag {
  my $frag = shift;
  my $html = $CONFIG->karyotype_setting($frag);
  return $html;
}


sub my_parse_feature_str {
  my $f      = shift;

  # less flexible than gbrowse_img, but we need to have some structure
  # to be analogous to Bio::Graphics::Featurefile
  my ($reference,$type,$name,$position,@desc) = shellwords($f);

  return unless $reference && $type && $name && $position;

  my @segments = map { [/(-?\d+)(?:-|\.\.)(-?\d+)/]} map {split /,/} $position;

  my %tag;

  if ( grep /\w+=\S+/, @desc ) { 

    my @attributes = map {split /,\s*/} @desc;
    
    for (@attributes) {
      my ($k,$v) = grep {s/^\s*|\s*$//g} /(.+?)=(.+)/;
      $v =~ s/[\'\"]//g;
      next if $k =~ /url|link/ && !check_url($v);
      $tag{$k}   = $v if $v;
      $tag{desc} = $k if !$v;
    }

  }

  my $tag = \%tag if %tag;

  ($reference,$type,$name,\@segments,$tag);
}


sub example_script {

 return <<END;
function hideExample() {
  document.f1.featuretext.value = '';
}

function showExample() {
  var text = xInnerHtml('exampleText');
  document.f1.featuretext.value = text;
}


// xGetElementById, Copyright 2001-2006 Michael Foster (Cross-Browser.com)
// Part of X, a Cross-Browser Javascript Library, Distributed under the terms of the GNU LGPL

function xGetElementById(e)
{
  if(typeof(e)=='string') {
    if(document.getElementById) e=document.getElementById(e);
    else if(document.all) e=document.all[e];
    else e=null;
  }
  return e;
}
  
// xInnerHtml, Copyright 2001-2006 Michael Foster (Cross-Browser.com)
// Part of X, a Cross-Browser Javascript Library, Distributed under the terms of the GNU LGPL

function xInnerHtml(e,h)
{
  if(!(e=xGetElementById(e)) || !xStr(e.innerHTML)) return null;
  var s = e.innerHTML;
  if (xStr(h)) {e.innerHTML = h;}
  return s;
}

// xStr, Copyright 2001-2006 Michael Foster (Cross-Browser.com)
// Part of X, a Cross-Browser Javascript Library, Distributed under the terms of the GNU LGPL

function xStr(s)
{
  for(var i=0; i<arguments.length; ++i){if(typeof(arguments[i])!='string') return false;}
  return true;
}

END
}

sub chromosome_data {
  my $d = shift or return ();
  $d =~ s/,/ /g;
  my @chr = shellwords($d);
  my $len = {};
  for (@chr) {
    ($_,my $length) = split ':';
    $len->{$_} = $length if $length;
  }
  return $len,@chr;
}

sub look_for_chromosomes {
  my $str = shift or return ();
  my @chr;
  my $clen = {};
  my @lines = grep {/\#\#sequence-region/} split "\n", $str;
  for (@lines) {
    my ($chr,$len) = /region\s+(\S+)\s+\d+\s+(\d+)/;
    if ($chr && $len) {
      push @chr, $chr;
      $clen->{$chr} = $len;
    }
  }

  return $clen, @chr if @chr;
  return 0;
}

!NO!SUBS!

close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';

