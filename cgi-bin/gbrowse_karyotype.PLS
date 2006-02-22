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
#$Id: gbrowse_karyotype.PLS,v 1.4 2006-02-22 02:11:31 sheldon_mckay Exp $

use strict;
use CGI::Carp 'fatalsToBrowser';
use CGI ':standard';
use GD;
use GD::Image;
use Bio::DB::GFF::Feature;
use Bio::Graphics::Browser::Util;
use Bio::Graphics::Panel;
use Bio::Graphics::FeatureFile;
use Text::Shellwords;
use File::Spec;

use vars qw($CONFIG $CONF_DIR);

use constant PAD_TOP   => 10;
use constant PAD_BOT   => 20;
use constant PAD_RIGHT => 40; # space for band labels
use constant HELP      => '/gbrowse';

$CONF_DIR = conf_dir($CONF_DIR);
$CONFIG   = open_config($CONF_DIR);

# set the database source
my $src = param('src') || param('source') || path_info();
$src    =~ s!^/+!!;  # get rid of leading / from path_info()
$src    =~ s!/+$!!;  # get rid of trailing / from path_info()
$src  ||= 'human';

message("Invalid source $src; you may not have permission to access this data source.")
    unless $CONFIG->source($src);

my $feature_text  = param('featuretext');
my @add_features  = (param('add'), param('a'));    # overlay features
my @add_style     = (param('style'),  param('s')); # overlay features style
my @options       = (param('options'),param('o')); # various track options, such as bumping
my @track_types   = (param('type'),   param('t')); # built in track types to turn on
my $embed         = 1 if param('embed');

# identity and order of chromosomes to draw
my $chr_data = param('chromosome') || param('c') || $CONFIG->setting('chromosome');
my @chr = split /\s+|,/, $chr_data;
my %chr;

# look for name of the cytobands track and ideogram drawing info
my $cytoband    = $CONFIG->setting('cytoband')  || 'cytoband';
my $max_height  = param('cheight') || param('h') || $CONFIG->setting('max_height') || 500;
my $rows        = param('rows')    || param('r') || $CONFIG->setting('rows')       || 'auto';
my $chrom_width = param('cwidth')  || param('w') || $CONFIG->setting($cytoband => 'height') || 20;
my $band_labels = param('band_labels') || param('b') || $CONFIG->setting('band_labels');

# deployment
if (param('list')) {
  dump_sources() if param('list') eq 'sources';
  dump_types()   if param('list') eq 'types';
  exit 0;
}

if (param('help')) {
  my $type = param('help');
  print header(), start_html(-title => "gbrowse_karyotype $type help");
  help(param('help'),$CONFIG->setting('help') || HELP);
}

if (param('embed') || !param()) {
  print header(), start_html(-title => 'gbrowse-karyotype');
}
else {
  print header('image/png');
}

if (param('Example') || !param()) {
   front_page();
 }

# get options
my ($options,$labels) = get_options(\@options,\@track_types);

my $longest = 0;
my $master_seg;
for my $chr (@chr) {
  my $seg = get_segment($CONFIG,$chr)
      || message("Could not find chromosome $chr in the database");
  if ($seg->length > $longest) {
    $longest = $seg->length;
  }
  $chr{$chr} = $seg;
}

my (%img,$feature_file,$styles,$black,$title);
my $max_width = 0;

for my $chr (@chr) {
  my $seg = $chr{$chr};

  my $feature_list = {};
  
  # features supplied by URL
  if (@add_features && !$feature_text) {

    # just worry about the features on this chromosome
    my @local_features = grep { (split)[0] eq $chr } @add_features;
    if (@local_features) {
      add_features($seg,\@local_features,\@add_style,$feature_list);
    }
  }
  # or as a Bio::Graphics::FeatureFile
  elsif ($feature_text) {
    $feature_file ||= Bio::Graphics::FeatureFile->new( -text => $feature_text,
						       -smart_features => 1,
						       -safe => undef
						       );

    # just worry about the features on this chromosome
    my @local_features = grep { $_->ref eq $chr } $feature_file->features;
    if (@local_features) {
      my @styles  = map  { [$_, my_style($_)] } $feature_file->configured_types;
      add_features($seg,\@local_features,\@styles,$feature_list);
    }
  }

  my ($panel, $boxes) = my_image_and_map( segment       => $seg,
					  tracks        => $labels,
					  feature_files => $feature_list );

  my $gd = $panel->gd;

  # rotate the image 90 degrees clockwise
  my $img    = $gd->copyRotate90();
  my ($w,$h) = $img->getBounds();
  $max_width = $w if $w > $max_width;

  # chromosome label
  $black ||= $panel->translate_color('black');  
  my $mid  = $w - $chrom_width/2;
  my $x    = $mid - 5;
  my $y    = $h - 15;
  $img->string(gdMediumBoldFont,$x,$y,$chr,$black);

  # reorient the boxes for image mapping by
  # flipping x + y and adjusting horizontal offsets
  for my $box (@$boxes) {
    my ($y1,$x1,$y2,$x2) = @$box[1,2,3,4];
    $x1 = $w - $x1;
    $x2 = $w - $x2;
    @$box[1..4] = ($x1,$y1,$x2,$y2);
  }

  $img{$chr} = [$img,$boxes];
}

# dynamic row calculation if required;
$max_width += PAD_RIGHT if $band_labels;
$rows = int(($max_width/1024 * @chr)+1) if $rows eq 'auto';
my $new_row = int @chr/$rows;

# adjust image  widths for even chromosome 
# spacing and labels
for my $chr (@chr) {
  my ($gd,$boxes) = @{$img{$chr}};
  my ($w,$h)  = $gd->getBounds();
  my $offset = $max_width - $w;
  $offset -= PAD_RIGHT if $band_labels;

  my $img = GD::Image->new($max_width,$h);
  $img->copy($gd,$offset,0,0,0,$w,$h);

  my $where_was_i = 0;
  for my $box (@$boxes) {
    $box->[1] += $offset;
    $box->[3] += $offset;

    if ($band_labels) {
      my $feature = $box->[0];
      next unless $feature->method =~ /cyto\S*band|chromosome\S+/i;

      my $x = $box->[1] + 1;
      my $y = $box->[2];

      # skip very narrow bands
      my $band_width = $box->[4] - $box->[2];
      next if $band_width < $max_height/100;

      # adjust vertical label placement
      if ($band_width < $max_height/50) {
	$y -= 2;
      }
      elsif ($band_width > $max_height/40) {
        $y = $y + $band_width/2 - 4; # 4 is 1/2 the font height                                                                                                       
      }

      # only add a label if there is room
      next if ($y - $where_was_i) <= 10;
      $where_was_i = $y;

      my $band_name = $feature->attributes('Name');
      $img->string(gdTinyFont,$x,$y,"-$band_name",$black) if $band_name;
    }
  } 

  $img{$chr} = [$img,$boxes];
}

# now consolidate all of the images
my ($new_img,$new_boxes) = consolidate_images(\%img,$rows,$max_width);
my $map = my_make_map($new_boxes,$feature_file);

if ($embed) {
  print h2({-align => 'center'}, ucfirst $src);
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
  my ($CONFIG,$name) = @_;
  my $db = open_database($CONFIG);
  my @segments;
  my @matches = $CONFIG->name2segments($name,$db);
  push @segments,@matches;
  $_->absolute(1) foreach @matches;
  return $segments[0];
}

sub get_options {
  my ($options,$track_types) = @_;

  # get the options
  my %options = shellwords(@$options);

  # set the track types to display.
  my @labels  = shellwords(@$track_types);

  @labels     = $CONFIG->default_labels unless @labels;

  return (\%options,\@labels);
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
  my ($images,$rows,$max_width) = @_;

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
  $composite->colorAllocate(255,255,255);
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

  for (@$boxes){
    my $f = $_->[0];
    my $w = $_->[5]->option('height');    

    # repair zero-height boxes ?!
    my $h = $_->[4] - $_->[2];
    if ($h == 0) {
      $_->[4] = $_->[2] + $w/2;
      $_->[2] = $_->[2] - $w/2;
    }

    my $title; 
    if ($f->method ne 'centromere') {
      my $att = $f->attributes;
      $title  = eval{$att->{Name}->[0] || $att->{Alias}->[0]};
    }
    else {
      $title = $f->desc || $f->name || $f->display_id || q{};
    }

    my ($start,$stop) = ($f->start,$f->end);
    my $coords = join(',',@$_[1..4]);
    $html .= qq{<area shape="rect" coords="$coords" title="$title"/>\n}
        if $title;
  }
  $html .= "</map>\n";

  return $html;
}

sub add_features {
  my ($segment,$features,$styles,$feature_hash) = @_;
  my @features = @$features;
  my @styles   = @$styles;

  my $feature_list = Bio::Graphics::FeatureFile->new(
						     -smart_features  => 1,
						     -safe => undef 
						     );

  for my $f (@features) {
    # feature objects
    if (ref $f) {
      $feature_list->add_feature($f);

      # remove attribute=value pairs from description
      my $desc = $f->desc || '';
      $desc =~ s/\w+=\S+(;|\s+)?//g;
      $desc =~ s/^\s+|\s+$//g;
      $f->desc($desc);
    }
    # or add string
    else {
      my ($reference,$type,$name,@segments) = parse_feature_str($f);
      my $mapper = coordinate_mapper($segment);
      my ($ref,@parts) = $mapper->($reference,@segments);
      next unless $ref;
      
      my $feature = Bio::Graphics::Feature->new(
						-ref      => $ref||'',
						-type     => $type||'',
						-name     => $name||'',
						-strand   => $parts[0][0]<=$parts[0][1] ? +1 : -1,
						-segments => \@parts
						);
      $feature_list->add_feature($feature);
    }
  }

  push @$labels, 'add' unless grep { $_ eq 'add' } @$labels;

  for my $s (@styles) {
    my ($type, $options);
    if (ref $s) { # already parsed
      ($type,$options) = @$s;
    }
    else {
      ($type,my @options) = shellwords($s);
      $options ={ map {split /=/} @options };
    }
    
    # adjust pointy glyph orientation to allow for 
    # horizontal to vertical rotation.  The default is to
    # point toward the chromosome.
    $options->{orient} = adjust_compass($options->{orient});

    # Most features are very small relative to whole
    # chromosomes.  Glyphs should not be scaled by default
    $options->{point} = 1 unless exists $options->{point};

    # Suppress feature labels and descriptions (for now).
    # They don't work well for vertical rendering
    unless ($options->{glyph} eq 'xyplot') {
      $options->{label} = 0;
      $options->{description} = 0;
    }
    
    # add some mix and match magic
    add_callbacks($options);

    $feature_list->add_type($type => $options);
  }
  
  $feature_hash->{add} = $feature_list;
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
  my $options_ref = shift;
  my @attributes = qw( bgcolor glyph fgcolor height linewidth orient );
  for my $att (@attributes) {
    # only do this for configured options
    my $default_value = $options_ref->{$att} || next;

    # Intercept suspicious attribute values; 
    # only pass letters, numbers or hexadecimal color codes
    if ( $default_value =~ /^sub|[^\#\w]/) {
      message( 
	       h1( "$att $default_value for attribute $att contains invalid characters. ",
		   " Please consult the documentation.")
	       );
      
    }

    # create a coderef 
    # the attribute:value pairs are alreadt parsed
    # by Bio::Graphics::FeatureFile
    $options_ref->{$att} = sub {
      my $f = shift;
      my $desc = $f->desc;
      my $atts = $f->attributes;
      my $override = $atts->{$att}->[0] if defined $atts->{$att};

      # no illegal characters 
      return $default_value unless $override && $override !~ /[^\#\w]/; 

      if ($override) {
	return $att eq 'orient' ? adjust_compass(uc $override) : $override;
      }
      return $default_value;
    }
  }
}

sub coordinate_mapper {
  my $current_segment = shift;
  my $db              = open_database();

  my ($ref,$start,$stop) = ($current_segment->seq_id,
                            $current_segment->start,$current_segment->end);
  my %segments;

  my $closure = sub {
    my ($refname,@ranges) = @_;

    unless (exists $segments{$refname}) {
      my @segments = map {
        eval{$_->absolute(0)}; $_  # so that rel2abs works properly later
	  }
      $CONFIG->name2segments($refname,$db,undef,1);
      $segments{$refname} = $segments[0];
      return unless @segments;
    }

    my $mapper   = $segments{$refname} || return;
    my $absref   = $mapper->abs_ref;
    my $cur_ref  = eval {$current_segment->abs_ref}
    || eval{$current_segment->ref};  # account for api changes in Bio::SeqI
    return unless $absref eq $cur_ref;

    my @abs_segs;
    if ($absref eq $refname) {  # doesn't need remapping
      @abs_segs = @ranges;
    } else {
      @abs_segs = map {[$mapper->rel2abs($_->[0],$_->[1])]} @ranges;
    }
    
    return ($absref,@abs_segs);
  };
 
  return $closure;
}

# Can't use Bio::Graphics::Browser image_and_map method
# due to gbrowse display-specific defaults/assumptions
sub my_image_and_map {
  my %config  = @_;

  my $segment       = $config{segment};
  my $feature_files = $config{feature_files} || {};
  my $tracks        = $config{tracks}        || [];
  my $options       = $config{options}       || {};
  my $length        = $segment->length;
  my $conf          = $CONFIG->config;

  my @feature_types = map { $CONFIG->label2type($_,$length) } @$tracks;

  # scale horizontal panel width by chromosome size
  my $width = int(($segment->length/$longest)*$max_height);

  my @argv = (
              -grid      => 0,
              -start     => 1,
              -end       => $segment->length,
              -bgcolor   => 'white',
              -width     => $width,
              -pad_left  => PAD_TOP,
	      -pad_right => PAD_BOT,
	      -key_style => 'none'
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

  if (@feature_types) {  # don't do anything unless we have features to fetch!
      
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

  my $factory    = $segment->clone->factory;
  my $aggregator = $CONFIG->setting($cytoband => 'aggregator');

  my @features;

  if ($aggregator) {
    $factory->aggregators($aggregator) if $aggregator;
    if ($aggregator =~ /^(\S+)\{/) {
      $aggregator = $1;
    }
    elsif ($aggregator =~ /\/(\S+)\}/) {
      $aggregator = $1;
    }
  }
  else {
    my $features = $CONFIG->setting($cytoband => 'feature');
    @features    = split /\s+/, $features;
  }

  push @features, $aggregator;
  my @bands = $segment->features( -type => \@features );

 # Make a blank chromosome if there are no cytoband data
  unless (@bands > 1) {
    push @bands, Bio::Graphics::Feature->new ( -start  => $segment->start,
                                               -stop   => $segment->end,
                                               -type   => 'chromosome' );
  }

  # -invisible hides unaggregated bands but retains their coordinates
  # for image mapping
  $panel->unshift_track(\@bands,
                        -bump      => 0,
                        -glyph     => $CONFIG->setting($cytoband => 'glyph')     || 'ideogram',
                        -height    => $chrom_width,
                        -arcradius => $CONFIG->setting($cytoband => 'arcradius') || $max_height/100,
                        -bgcolor   => $CONFIG->setting($cytoband => 'bgcolor'),
                        -fgcolor   => $CONFIG->setting($cytoband => 'fgcolor'),
                        -invisible => $aggregator ? 1 : 0,
                        # if we are drawing a heat-map
                        -start_color => $CONFIG->setting($cytoband => 'start_color') || 'white',
                        -end_color   => $CONFIG->setting($cytoband => 'end_color')   || 'red',
                        -min_score   => $CONFIG->setting($cytoband => 'min_score')   || 0,
                        -max_score   => $CONFIG->setting($cytoband => 'max_score')   || 100,
                        );

  # for image mapping, don't save whole chromosome box
  # if we have aggregated
  my @boxes;
  if ($aggregator) {
    @boxes = grep {$$_[0]->method ne $aggregator} $panel->boxes;
  }
  else {
    @boxes = $panel->boxes;
  }

  return ($panel, \@boxes);
}

sub front_page {
  my $page_header = html_frag('header')     || page_header();
  my $page_footer = html_frag('footer')     || page_footer(); 
  my $input_form  = html_frag('input_form') || input_form();
  my $html1       = html_frag('html1')      || help_line();
  my $html2       = html_frag('html2')      || q{};

  print <<END;
  <html>
  <head>
  <title>gbrowse-karyotype</title>
  </head>
  <html>
  <body>
  $page_header
  <p>
  $html1
  <p>
  $input_form
  </p>
  $html2
  <p>
  $page_footer
  </p> 
  </body>
  </html> 
END
;
  exit 0;
}

sub input_form {
  my $sample_text = param('Example') ? sample_text() : q{};
  my $source_menu = source_menu();
  my $cytoband    = $CONFIG->setting('cytoband');
  my $height      = $CONFIG->setting($cytoband => 'max_height') || 500;
  my $width       = $CONFIG->setting($cytoband => 'cwidth')     || 20; 
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
  $sample_text
  </textarea>
  </p>
  <input type="submit" name="Draw" value="Draw"/>&nbsp;&nbsp;
  <input type="submit" name="Example" value="Example"/>&nbsp;&nbsp;
  <input type="button" name="Erase" value="Erase" onclick="document.f1.featuretext.value=&#39;&#39;" />
    &nbsp;&nbsp;
  <input type="reset" name="Reset" value="Reset" />
  </form>
END
}

sub page_header {
  return <<END;
  <h2>gbrowse_karyotype</h2>
  <h4>Draw karyotypes and map feature data via the Generic Genome Browser</h3>
END
}

sub page_footer {
  return <<END;
  <hr>
  <p>Data and configuration help: &nbsp;&nbsp;
  <a href="/cgi-bin/gbrowse_karyotype?help=configuration" target="_blank">[Browser configuration]</a>
  &nbsp;&nbsp;
  <a href="/cgi-bin/gbrowse_karyotype?help=ideogram" target="_blank">[Chromosomes and banding data]</a>.
  </p>
  <p>
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
  
  my $onchange = qq{"location = '$url/'+this.options[this.selectedIndex].value;"};
  $html .= "<select name=src onchange=$onchange>";
  for my $source ($CONFIG->sources) {
    $CONFIG->source($source);
    next unless $CONFIG->setting('cytoband') || $CONFIG->setting('chromosome');
    my $selected = " selected=selected" if $source eq $src;
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
mutation allele2 30006001..30009000 "cosmic radiation damage"
END

}

sub dump_sources {
  print header('text/plain');
  print "## Sources\n";
  for my $source ($CONFIG->sources) {
    $CONFIG->source($source);
    next unless $CONFIG->setting('cytoband') || $CONFIG->setting('chromosome');
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

sub help {
  my ($help_type,$conf_dir) = @_;

  my $ref = referer();
  my $do_close = join('',
		      start_form(-action=>$ref),
		      button(-onClick=>'window.close()',-label=>$CONFIG->tr('Close_Window')),
		      end_form());
  
  if ($help_type eq 'configuration') {
    print dump_configuration_help($do_close);
    exit 0;
  }
  elsif ($help_type eq 'ideogram') {
    print dump_ideogram_help($do_close);
    exit 0;
  }
  else {
    my @components = File::Spec->splitdir($help_type);
    my $updir      = File::Spec->updir;
    
    # don't let evil people get into root directory
    my $evil       = grep { /^$updir$/o } @components;
    return         if $evil;
    
    print div({-align=>'left'},$do_close);
    build_help_page("$conf_dir/gbrowse_karyotype_${help_type}_help.html");
    print div({-align=>'left'},$do_close), end_html;
  } 

  exit 0;
}
  
sub build_help_page {
  my $helpfile = shift or return;
  my $file = url2file($helpfile) or return;
  my $root = $CONFIG->setting('help') || HELP;
  open(F,$file) or return;
  print while (<F>);
  close F;
}

sub dump_configuration_help {
  my $close = div(shift);
  return <<END;
  $close
  <h2> gbrowse_karyotype browser customization and configuration </h2>
  <p>
   Below is a sample configuration file (see the main Generic Genome Browser
   documentation for more information on configuration files).  The format
   is standard except for the following gbrowse_karyotype information:
  <p>
  <ul>
    <li> The front page for the interactive browser can be almost entirely
         customized with the following keys.
          <ul>
             <li> <pre> header     = ... </pre>Page header biolerplate (Visible title, etc.)
             <li> <pre> html1      = ... </pre>Miscellaneous HTML to insert after header
             <li> <pre> input_form = ... </pre>HTML to replace eveything between the header
                  and footer
             <li> <pre> html2      = ... </pre>Miscellaneous HTML to insert befor footer
             <li> <pre> footer     = ... </pre>Page footer
          </ul>
	  <p>
 	  The above fields are optional; reasonable, albeit plain, defaults will be
          used unless otherwise specified. 
	  </p>
     <li> <pre>chromosome = chr1 chr2 chr3</pre>
          This entry is required to specify which chromosomes to display 
          and in which order.  The space delimited list should contain 
          reference sequences that exist in your database or GFF flat file.
     <li> <pre>cytoband = CYT</pre>
          This specifies which built-in feature corresponds to the chromosome
          band data.  If there are no band data, black chromosomes will be
          drawn.  However, a confuguration stanza is still necessary to specify
          default chromosome attributes.
     <li> <pre>feature = cytoband centromere\nOR\naggregator = chromosome</pre>
          In the feature configuration for the cytoband data, either a
          list of feature types or an aggregator can be specified. 
          Either a built-in aggregator such as 'chromosome' or a custom 
          aggregator, such as
          <pre> aggregator = my_chr{cytoband,centromere} </pre>  
	  can be used.  The feature and aggregator keys
          are mutually exclusive and the latter is preferred. Note that
          the aggregator key must be used in the cytoband track configuration, 
          not the 'general' section.
     <li> <pre> glyph = ideogram </pre>
          The ideogram glyph would be most commonly used in combination
	  with cytoband data.  An alternative for scored, non cytoband
          features (for example local gene densites, recombination rates,
          etc) is the heat_map_ideogram glyph, which can be used to draw
          chromosomes with color-coded bands representing scores, frequencies
          etc. The chromosome-like look can be enhanced by including
          the centromere amongst the scored "bands".  
  </ul>

<pre>
# This is a basic configuration to draw chromosome ideograms for the 
# human genome.  It is a standalone file but could could also be part
# of a normal gbrowse configuration file. 
[GENERAL]
description   = human
db_adaptor    = Bio::DB::GFF
# this configuration just uses a simple flatfile 
db_args       = -adaptor memory
                -gff    'usr/local/apache/htdocs/gbrowse/databases/ideograms/human_cytobands.gff'


# Where temporary images are stored
tmpimages   = /gbrowse/tmp

# chromosome dimensions (in pixels)
max_height  = 400
cwidth      = 15

# number of rows to draw
rows        = auto

# chromosomes names and order
chromosome  = 1 2 3 4 5 6 7 8 9 10 11 12 13
              14 15 16 17 18 19 20 21 22 X Y

# which track contains the cytoband configuration
cytoband  = CYT

[CYT]
aggregator    = chromosome
# could also use    
# feature      = cytoband centromere 
glyph         = ideogram
fgcolor       = black
bgcolor       = gneg:white gpos25:silver gpos50:gray gpos:gray 
                gpos75:darkgray gpos100:black gvar:var stalk:#666666
arcradius     = 7
height        = 21

# Other built-in feature configuration, if any,  would be added here
</pre>
$close
END

}

sub dump_ideogram_help {
  my $close = div(shift);
  my $script = join q{}, (<DATA>);

  return <<END;
  $close
  <h2>How to get cytoband data</h2>
  <p>
  The starting point for drawing chromosome ideograms is the cytoband data.
  These data can be obtained from the UCSG genome browser, from NCBI and
  from EnsEMBL.  Once obtained, the cytobands are converted to GFF to be
  loaded into a Bio::DB::GFF database or saved as a flatfile.
  </p>

  <p>
  Below is an example of GFF3-format cytoband data.  Note that the 
  Parent= tag is used to facilitate aggregation of bands into their parent 
  chromosomes.  Preprocessed GFF files for mouse, human and rat can be found
  in the html (or htdocs) directory at gbrowse/databases/ideogram
  </p>
  <pre>
  ##gff-version 3
  ##sequence-region 1 1 245522847
  1       ensembl chromosome_band        1       2300000 .       .       .       Parent=1;Name=p36.33;Alias=1p36.33;Stain=gneg
  1       ensembl chromosome_band        2300001 5300000 .       .       .       Parent=1;Name=p36.32;Alias=1p36.32;Stain=gpos25
  1       ensembl chromosome_band        15600001        20200000        .       .       .       Parent=1;Name=p36.13;Alias=1p36.13;Stain=gneg
  1       ensembl centromere      121000001       127900000       .       .       .       Parent=1;Name=1_cent;Alias=11_cent
  </pre>
  
  <p>
  Ensembl has cytoband data for human, mouse and rat.  Below is an example of a 
  script that retrieves cytoband features from the public mysql database 
  and converts them to GFF.  
  </p>
  
  <table>
  <tr>
  <td width=50></td>
  <td bgcolor="silver">
  <pre>
  $script
  </pre>
  </td>
  </tr>
  </table>
  
  <h2>SEE ALSO: Bio::Graphics::Glyph::ideogram</h2>
  $close
  </html>
END
  
}

sub my_html_frag {
  my $frag = shift;
  my $html = $CONFIG->setting($frag);
  return $html;
}


__DATA__

#!/usr/bin/perl -w
use strict;
use DBI;

my $database = shift;
my $host     = 'ensembldb.ensembl.org';
my $query    = 
'SELECT name,seq_region_start,seq_region_end,band,stain
 FROM seq_region,karyotype
 WHERE seq_region.seq_region_id = karyotype.seq_region_id;';


my $dbh = DBI->connect( "dbi:mysql:$database:$host", 'anonymous' )
    or die DBI->errstr;

my $sth = $dbh->prepare($query) or die $dbh->errstr;
$sth->execute or die $sth->errstr;

my ($cent_start,$prev_chr,$chr_end,$segments,$gff);
my $chr_start = 1;
while (my @band = $sth->fetchrow_array ) {
  my ($chr,$start,$end,$band,$stain) = @band;
  my $class = 'Chromosome';
  my $method;

  $chr =~ s/chr//;
  if ($stain eq 'acen' && !$cent_start) {
    $cent_start = $start;
    next;
  }
  elsif ($cent_start) {
    $method = 'centromere';
    $band   = "$chr\_cent";
    $start  = $cent_start;
    $stain  = '';
    $cent_start = 0;
  }
  else {
    $method = 'chromosome_band'; # SO term
  }

  $gff .= join("\t", $chr, 'ensembl', lc $method, $start, $end,
	       qw/. . ./,qq{Parent=$chr;Name=$band;Alias=$chr$band});
  $gff .= $stain ? ";Stain=$stain\n" : "\n";

  if ($prev_chr && $prev_chr !~ /$chr/) {
    $segments .= "\#\#sequence-region $prev_chr $chr_start $chr_end\n";
    $chr_start = 1;
  }

  $prev_chr = $chr;
  $chr_end  = $end;
}

$segments .= "\#\#sequence-region $prev_chr $chr_start $chr_end\n";
print "##gff-version 3\n";
print $segments,$gff;

__END__
# Currently ideograms for human, rat and mouse are available
# To see the current database list, try the command:

mysql -uanonymous -hensembldb.ensembl.org -e 'show databases' \ 
| grep core | grep 'sapiens\|rattus\|mus' | grep -v 'expression'


!NO!SUBS!

close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
