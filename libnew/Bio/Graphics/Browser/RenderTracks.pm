package Bio::Graphics::Browser::RenderTracks;

use strict;
use warnings;

use Bio::Graphics;
use CGI qw(param escape unescape);

use constant GBROWSE_RENDER => 'gbrowse_render';  # name of the CGI-based image renderer
use constant TRUE => 1;
use constant DEBUG => 0;

use constant DEFAULT_KEYSTYLE => 'between';
use constant DEFAULT_EMPTYTRACKS => 0;
use constant PAD_DETAIL_SIDES    => 10;
use constant RULER_INTERVALS     => 20;

# when we load, we set a global indicating the LWP::Parallel::UserAgent is available
my $LPU_AVAILABLE;
my $STO_AVAILABLE;

sub new {
  my $class       = shift;
  my %options     = @_;
  my $segment       = $options{-segment};
  my $data_source   = $options{-source};
  my $page_settings = $options{-settings};
  my $renderer      = $options{-renderer};

  my $self  = bless {},ref $class || $class;
  $self->segment($segment);
  $self->source($data_source);
  $self->settings($page_settings);
  $self->page_renderer($renderer);
  return $self;
}

sub segment {
  my $self = shift;
  my $d = $self->{segment};
  $self->{segment} = shift if @_;
  return $d;
}

sub source {
  my $self = shift;
  my $d = $self->{source};
  $self->{source} = shift if @_;
  return $d;
}

sub page_renderer {
  my $self = shift;
  my $d    =$self->{renderer};
  $self->{renderer} = shift if @_;
  return $self->{renderer};
}

sub settings {
  my $self = shift;
  my $d = $self->{settings};
  $self->{settings} = shift if @_;
  return $d;
}


# This renders the named tracks and returns the images and image maps
# input args:
#           (-tracks         => [array of track names],
#            -third_party    => [third party annotations (Bio::DasI objects)],
#           );
# output:
# a hash of 
# { $track_name => { gd   => $gd_object,
#                   map  => $image_map }
# }
#
sub render_tracks {
  my $self    = shift;
  my %args    = @_;

  my $source   = $self->source;
  my $settings = $self->settings;

  my $tracks              = $args{-tracks};
  my $third_party         = $args{-third_party};
  my $render_options      = $args{-options};

  my $results = {};

  # if the "renderfarm" option is set, then we scatter the requests across multiple remote URLs
  if ($self->use_renderfarm($source)) {
    $results = $self->render_remotely($tracks,$render_options);
  }

  else {
    $results = $self->render_locally($tracks,$render_options);
  }

  # add third-party data (currently always handled locally and serialized)
  my $segment  = $self->segment;
  for my $sourcename ($third_party->sources) {
    my $ff = $third_party->feature_file($sourcename,$segment);
    my $name = $ff->name or next;  # every third party feature has to have a name now
    $results->{$name} = $self->render_third_party($ff,$render_options);
  }

  # oh, ouch, we've got to do something with the plugins... or maybe they're handled by the third party hash?

  return $results;
}

sub use_renderfarm {
  my $self   = shift;

  $self->source->global_setting('renderfarm') or return;	#comment out to force remote rendering (kludge)

  $LPU_AVAILABLE = eval { require LWP::Parallel::UserAgent; } unless defined $LPU_AVAILABLE;
  $STO_AVAILABLE = eval { require Storable; 1; }              unless defined $STO_AVAILABLE;
  return 1 if $LPU_AVAILABLE && $STO_AVAILABLE;
  warn "The renderfarm setting requires the LWP::Parallel::UserAgent and Storable modules, but one or both are missing. Reverting to local rendering.\n";
  return;
}


sub render_remotely {
  my $self    = shift;
  my $tracks  = shift;
  my $options = shift;

  my $source = $self->source;

  my %remote;
  for my $track (@$tracks) {
    my $host  = $source->semantic_setting($track => 'remote renderer');
    $host   ||= $self->local_renderer_url;
    $remote{$host}{$track}++;
  }

  return $self->call_remote_renderers(\%remote);
}


# This routine is called to hand off the rendering to a remote renderer. The remote processor does not have to
# have a copy of the config file installed; the entire DataSource object is sent to it in serialized form via
# POST. It returns a serialized hash consisting of the GD object and the imagemap.
# INPUT $renderers_hashref
#    $renderers_hashref->{$remote_url}{$track}
#
# RETURN
#    hash of { $track_label => { gd => $gd object, map => $imagemap } }
#
#
# POST outgoing arguments:
#    datasource => serialized Bio::Graphics::Browser::DataSource
#    settings   => serialized state hash (from the session)
#    tracks     => serialized list of track names to render
#
# POST incoming arguments
#    [[$track,$gd,$imagemap],[$track,$gd,$imagemap],...]
#
# reminder: segment can be found in the settings as $settings->{ref,start,stop,flip}
sub call_remote_renderers {
  my $self    = shift;
  my $renderers = shift;
  
  #eval { require 'HTTP::Request::Common' } unless HTTP::Request::Common->can('POST');
  eval { use HTTP::Request::Common; } unless HTTP::Request::Common->can('POST');

  my $dsn      = $self->source;
  my $settings = $self->settings;
  my $lang     = $self->page_renderer->language->{lang};
  my $session  = $self->page_renderer->session;
  my $paramargs= {};
  $paramargs->{'plugin_do'} 	= param('plugin_do')	if param('plugin_do'); 
  $paramargs->{'plugin_action'}	= param('plugin_action')if param('plugin_action'); 
  $paramargs->{'plugin'}	= param('plugin')	if param('plugin'); 
  $paramargs->{'.source'}	= param('.source')	if param('.source'); 
  $paramargs->{'render'}	= param('render')	if param('render'); 

  # serialize the data source and settings
  my $s_dsn	= Storable::freeze($dsn);
  my $s_set	= Storable::freeze($settings);
  my $s_lang	= Storable::freeze($lang);
  my $s_sess	= Storable::freeze($session);
  my $s_p_args	= Storable::freeze($paramargs);

  my $ua = LWP::Parallel::UserAgent->new;
  $ua->in_order(0);
  $ua->nonblock(1);

  for my $url (keys %$renderers) {
    my @tracks  = keys %{$renderers->{$url}};
    $url = "http://localhost" . $url . ".pl/";				#fix absolute path later
    my $s_track  = Storable::freeze(\@tracks);
    my $request = POST ($url,
    		       [tracks     => $s_track,
			settings   => $s_set,
			datasource => $s_dsn,
			language   => $s_lang,
			session    => $s_sess,
			paramargs  => $s_p_args]);
    my $error = $ua->register($request);
    if ($error) { warn "Could not send request to $url: ",$error->as_string }
  }

  my $timeout = $dsn->global_setting('timeout') || 20;
  my $results = $ua->wait($timeout);

  my %track_results;
  foreach (keys %$results) {
    my $response = $results->{$_}->response;
    unless ($response->is_success) {
      warn $results->request->uri,"; fetch failed: ",$response->status_line;
      next;
    }
    my $content = $response->content;
    my $tracks = Storable::thaw($content);
    for my $track_tuple (@$tracks) {
      my ($track_name,$gd,$imagemap) = @$track_tuple;
      $track_results{$track_name}{gd} = $gd;
      $track_results{$track_name}{map} = $imagemap;
    }
  }
  #warn"track results are:".Dumper(%track_results);
  return \%track_results;
}

sub local_renderer_url {
  my $self     = shift;
  my $self_uri = CGI::url(-absolute=>1);
  my $render   = GBROWSE_RENDER;
  $self_uri    =~ s/[^\/]+$/$render/;
  return $self_uri;
}

# This is entry point for rendering a series of tracks given their labels
# input is (\@track_names_to_render)
#
# output is $results hashref:
#   $results->{$track_label}{gd} = $gd_object
#   $results->{$track_label{map} = $imagemap
#
sub render_locally {
  my $self    = shift;
  my $tracks  = shift;
  my $options = shift;

  my $source = $self->source;

  my $lang    = $self->page_renderer->language;
  warn "language = $lang";

  # sort tracks by the database they come from
  my (%track2db,%db2db);

  for my $track (@$tracks) { 
    my $db = eval { $source->open_database($track)};
    unless ($db) { warn "Couldn't open database for $_: $@"; next; }
    $track2db{$db}{$track}++;
    $db2db{$db}  =  $db;  # cache database object
  }

  my %merge;

  for my $dbname (keys %track2db) {
    my $db        = $db2db{$dbname};              # database object
    my @tracks = keys %{$track2db{$dbname}};   # all tracks that use this database
    my $results_for_this_db = $self->generate_panels(-db      => $db,
						     -tracks  => \@tracks,
						     -options  => $options);
    %merge = (%merge,%$results_for_this_db);
  }

  my %results;
  for my $label (keys %merge) {
    my $panel    = $merge{$label} or next;
    my $gd       = $panel->gd;
    my $imagemap = $label eq '__scale__' ? $self->make_centering_map($panel) 
    	: $self->make_map($panel,$label,$lang);
    $results{$label}{gd} = $gd;
    $results{$label}{map} = $imagemap;
#use Storable;store([$label,$gd,$imagemap],'/Users/mokada/development/testing/temp/triplets.dat');return\%results;
  }

  return \%results;
}

sub make_map {
  my $self  = shift;
  my ($panel,$label) = @_;

  my $boxes = $panel->boxes;

  my $map = qq(<map name="${label}_map" id="${label}_map">\n);
  my $flip = $panel->flip;

  my $did_map;

  local $^W = 0; # avoid uninit variable warnings due to poor coderefs

  foreach (@$boxes){
    next unless $_->[0]->can('primary_tag');
    my $href   = $self->make_link($_->[0],$panel,$label,$_->[5]) or next;
    my $alt    = unescape($self->make_title($_->[0],$panel,$label,$_->[5]));
    my $target = $self->make_link_target($_->[0],$panel,$label,$_->[5]);
    my $t      = defined($target) ? qq(target="$target") : '';
    $map .= qq(<area shape="rect" coords="$_->[1],$_->[2],$_->[3],$_->[4]" href="$href" title="$alt" alt="$alt" $t/>\n);
  }

  # now add links for the track labels
  if ($panel->can('key_boxes') && (my $keys = $panel->key_boxes)) {
    for my $key (@$keys) {
      my ($key_text,$x1,$y1,$x2,$y2,$track) = @$key;
      my $link;
      if ($label =~ /^file:/) {
	$link = "?Download%20File=$key_text";
      }
      elsif ($label =~ /^w+:/) {
	next;
      }
      else {
	$link = "?help=citations#$label";
      }
      my $citation = $self->citation($label,$self->page_renderer->language);
      my $cite     = defined $citation ? qq(title="$citation") : '';
      $map .= qq(<area shape="rect" coords="$x1,$y1,$x2,$y2" href="$link" target="citation" $cite alt="$label"/>\n);
    }
  }

  $map .= "</map>\n";
  $map;
}

# this creates image map for rulers and scales, where clicking on the scale
# should center the image on the scale.
sub make_centering_map {
  my $self   = shift;
  my $panel  = shift;
  my $ruler  = $panel->boxes->[0];
  

  my $flip   = $panel->flip;

  return if $ruler->[3]-$ruler->[1] == 0;

  my $length = $ruler->[0]->length;
  my $offset = $ruler->[0]->start;
  my $end    = $ruler->[0]->end;
  my $scale  = $length/($ruler->[3]-$ruler->[1]);
  my $pl     = $ruler->[-1]->panel->pad_left;

  # divide into RULER_INTERVAL intervals
  my $portion = ($ruler->[3]-$ruler->[1])/RULER_INTERVALS;
  my $ref    = $ruler->[0]->seq_id;
  my $source = $self->source;
  my $plugin = escape(param('plugin')||'');

  my @lines;
  for my $i (0..RULER_INTERVALS-1) {
    my $x1 = int($portion * $i+0.5);
    my $x2 = int($portion * ($i+1)+0.5);

    # put the middle of the sequence range into the middle of the picture
    my $middle = $flip ? $end - $scale * ($x1+$x2)/2 : $offset + $scale * ($x1+$x2)/2;
    my $start  = int($middle - $length/2);
    my $stop   = int($start  + $length - 1);

    $x1 += $pl;
    $x2 += $pl;

    my $url = "?ref=$ref;start=$start;stop=$stop;nav4=1;plugin=$plugin";
    $url .= ";flip=1" if $flip;
    push @lines,
      qq(<area shape="rect" coords="$x1,$ruler->[2],$x2,$ruler->[4]" href="$url" title="recenter" alt="recenter" />\n);
  }
  return join '',qq(<map name="__scale___map" id="__scale___map">\n),@lines,"</map>";
}


# finally....
# this is the routine that actually does the work!!!!
sub generate_panels {
  my $self    = shift;
  my %args    = @_;

  my $db      = $args{-db};
  my $tracks  = $args{-tracks};
  my $options = $args{-options};

  my $source         = $self->source;
  my $settings       = $self->settings;
  my $f_options      = $settings->{features};  # feature options, such as "visible" and "bump"
  my $lang           = $settings->{lang};

  my $keystyle        = $options->{keystyle};
  my $flip            = $options->{flip};
  my $suppress_scale  = $options->{noscale};
  my $hilite_callback = $options->{hilite_callback};
  my $image_class     = $options->{image_class} || 'GD';
  my $postgrid        = $options->{postgrid} || '';
  my $background      = $options->{background} || '';
  my $title           = $options->{title} || '';
  my $limit           = $options->{limit}         || {};

  my $feature_files   = $options->{feature_files} || {};

  my $segment  = $self->segment;

  $segment->factory->debug(1) if DEBUG;

  # Bring in the appropriate package - just for the fonts. Ugh.
  eval "use $image_class";

  my $width          = $settings->{width};

  my $max_labels     = $source->setting('label density');
  my $max_bump       = $source->setting('bump density');
  my $length         = $segment->length;

  my @feature_types = map { $source->label2type($_,$length) } @$tracks;
  my %filters = map { my %conf =  $source->style($_); 
		      $conf{'-filter'} ? ($_ => $conf{'-filter'})
			               : ()
		      } @$tracks;

  # Create the tracks that we will need
  my ($seg_start,$seg_stop ) = ($segment->start,$segment->end);

  # BUG: This looks like a bug; is it?
  if ($seg_stop < $seg_start) {
    ($seg_start,$seg_stop)     = ($seg_stop,$seg_start);
    $flip = 1;
  }

  my @pass_thru_args = map {/^-/ ? ($_=>$options->{$_}) : ()} keys %$options;
  my @argv = (
	      -grid      => 1,
	      @pass_thru_args,
	      -start     => $seg_start,
	      -end       => $seg_stop,
	      -stop      => $seg_stop,  #backward compatibility with old bioperl
	      -key_color => $source->setting('key bgcolor')     || 'moccasin',   #FIX ME! (3) Suggestion: $source->setting ...
	      -bgcolor   => $source->setting('detail bgcolor')  || 'white',      #FIX ME! (3) Suggestion: $source->setting ...
	      -width     => $width,
	      -key_style    => $keystyle || $source->setting(general=>'keystyle') || DEFAULT_KEYSTYLE,
#	      -key_style    => 'none',
	      -empty_tracks => $source->setting(general=>'empty_tracks') 	  || DEFAULT_EMPTYTRACKS,
	      -pad_top      => $title ? $image_class->gdMediumBoldFont->height : 0,
#	      -pad_top      => 5,
	      -image_class  => $image_class,
	      -postgrid     => $postgrid,
	      -background   => $background,
	      -truecolor    => $source->setting(general=>'truecolor') || 0,
	     );

  push @argv, -flip => 1 if $flip;
  my $p = defined $source->setting(general=>'image_padding') ? $source->setting(general=>'image_padding')
                                                           : PAD_DETAIL_SIDES;
  my $pl = $source->setting(general=>'pad_left');
  my $pr = $source->setting(general=>'pad_right');
  $pl    = $p unless defined $pl;
  $pr    = $p unless defined $pr;

  push @argv,(-pad_left =>$pl, -pad_right=>$pr) if $p;

  # here is where we begin to build the results up
  my @results;

  my $panel = Bio::Graphics::Panel->new(@argv);

  $panel->add_track($segment      => 'arrow',
		    -double       => 1,
		    -tick         => 2,
		    -label        => $options->{label_scale} ? $segment->seq_id : 0,
		    -units        => $source->setting(general=>'units') || '',
		    -unit_divider => $source->setting(general=>'unit_divider') || 1,
		   ) unless $suppress_scale;

  #---------------------------------------------------------------------------------
  # Track and panel creation

  # we create two hashes:
  #        the %panels hash maps label names to panels
  #        the %tracks hash maps label names to tracks within the panels

  my %panels;
  $panels{__scale__} = $panel;
  my %tracks;

  for my $label (@$tracks) {
    next if $panels{$label};  # already created for some reason

    # if "hide" is set to true, then skip panel
    next if $source->semantic_setting($label=>'hide',$length);

    $panels{$label} = Bio::Graphics::Panel->new(@argv,-pad_top=>16,-extend_grid=>1);
    if ($source->semantic_setting($label=>'global feature',$length)) {
      $tracks{$label} = $panels{$label}->add_track($segment,
						   $source->default_style,
						   $source->i18n_style($label,$lang)
						  );
    } else {
      my @settings = ($source->default_style,$source->i18n_style($label,$lang,$length));
      push @settings,(-hilite => $hilite_callback) if $hilite_callback;
      $tracks{$label} = $panels{$label}->add_track(-glyph => 'generic',@settings);
    }
  }
  #---------------------------------------------------------------------------------

  #---------------------------------------------------------------------------------
  # Adding features from the database

  my (%groups,%feature_count,%group_pattern,%group_field);
  if (@feature_types) {
    my $iterator = $segment->get_feature_stream(-type=>\@feature_types);

    while (my $feature = $iterator->next_seq) {
      my @labels = $source->feature2label($feature,$length);

      for my $label (@labels) {

	my $track = $tracks{$label}  or next;
	$filters{$label}->($feature) or next if $filters{$label};
	$feature_count{$label}++;


	# ------------------------------------------------------------------------------------------
	# GROUP CODE
	# Handle name-based groupings.
	unless (exists $group_pattern{$label}) {
	  $group_pattern{$label} = $source->code_setting($label => 'group_pattern');
	  $group_pattern{$label} =~ s!^/(.+)/$!$1! if $group_pattern{$label}; # clean up regexp delimiters
	}

	# Handle generic grouping (needed for GFF3 database)
	$group_field{$label} = $source->code_setting($label => 'group_on') unless exists $group_field{$label};
	
	if (my $pattern = $group_pattern{$label}) {
	  my $name = $feature->name or next;
	  (my $base = $name) =~ s/$pattern//i;
	  $groups{$label}{$base} ||= Bio::Graphics::Feature->new(-type   => 'group');
	  $groups{$label}{$base}->add_segment($feature);
	  next;
	}
	
	if (my $field = $group_field{$label}) {
	  my $base = eval{$feature->$field};
	  if (defined $base) {
	    $groups{$label}{$base} ||= Bio::Graphics::Feature->new(-start  =>$feature->start,
								   -end    =>$feature->end,
								   -strand => $feature->strand,
								   -type   =>$feature->primary_tag);
	    $groups{$label}{$base}->add_SeqFeature($feature);
	    next;
	  }
	}
	# ------------------------------------------------------------------------------------------

	$track->add_feature($feature);
      }
    }

    # ------------------------------------------------------------------------------------------
    # fixups

    # fix up %group features
    # the former creates composite features based on an arbitrary method call
    # the latter is traditional name-based grouping based on a common prefix/suffix

    for my $label (keys %groups) {
      my $track  = $tracks{$label};
      my $g      = $groups{$label} or next;
      $track->add_feature($_) foreach values %$g;
      $feature_count{$label} += keys %$g;
    }

    # configure the tracks based on their counts
    for my $label (keys %tracks) {
      next unless $feature_count{$label};

      $options->{$label} ||= 0;

      my $count = $feature_count{$label};
      $count    = $limit->{$label} if $limit->{$label} && $limit->{$label} < $count;

      my $do_bump  = $self->do_bump($label, $options->{$label},$count,$max_bump,$length);
      my $do_label = $self->do_label($label,$options->{$label},$count,$max_labels,$length);
      my $do_description = $self->do_description($label,$options->{$label},$count,$max_labels,$length);

      $tracks{$label}->configure(-bump  => $do_bump,
				 -label => $do_label,
				 -description => $do_description,
				);
      $tracks{$label}->configure(-connector  => 'none') if !$do_bump;
      $tracks{$label}->configure(-bump_limit => $limit->{$label}) 
	if $limit->{$label} && $limit->{$label} > 0;
    }
  }
  # ------------------------------------------------------------------------------------------

  # add additional features, if any
  my $offset = 0;
  my $select = sub {
    my $file  = shift;
    my $type  = shift;
    my $section = $file->setting($type=>'section') || $file->setting(general=>'section');
    return 1 unless defined $section;
    return $section =~ /detail/;
  };

  my $extra_tracks = $options->{noscale} ? 0 : 1;

  # ---------------------------------------------------------------------------------------
  # feature files

  for my $label (keys %$feature_files) {
    my $file = $feature_files->{$label} or next;
    ref $file or next;
    my $name = $file->name || '';
    $options->{$name}      ||= 0;
    eval {$file->render($panels{$label},0,$options->{$name},$max_bump,$max_labels,$select)};
    $self->error("$name: $@") if $@;
  }

  return \%panels;
}

#FIX ME! (6,7)  I've copied and modified the following 3 methods from the original Browser to fit
#with the current implementation. (June24)
#
#copied from Bio::Graphics::Browser (lib)
sub do_bump {
  my $self = shift;
  my ($track_name,$option,$count,$max,$length) = @_;

  my $conf              = $self->source;
  my $maxb              = $conf->code_setting($track_name => 'bump density')
                       || $conf->code_setting("TRACK DEFAULTS"=> 'bump density');#warn"maxb is $maxb";
  $maxb                 = $max unless defined $maxb;

  $count ||= 0;
  $maxb  ||= 0;

  my $maxed_out = $count <= $maxb;
  my $conf_bump = $conf->semantic_setting($track_name => 'bump',$length);
  $option ||= 0;
  return defined $conf_bump ? $conf_bump
      :  $option == 0 ? $maxed_out
      :  $option == 1 ? 0
      :  $option == 2 ? 1
      :  $option == 3 ? 1
      :  $option == 4 ? 2
      :  $option == 5 ? 2
      :  0;
}

#copied from Bio::Graphics::Browser (lib)
sub do_label {
  my $self = shift;
  my ($track_name,$option,$count,$max_labels,$length) = @_;

  my $conf = $self->source;

  my $maxl              = $conf->code_setting($track_name => 'label density')
                       || $conf->code_setting("TRACK DEFAULTS" => 'label density');
  $maxl                 = $max_labels unless defined $maxl;
  my $maxed_out         = $count <= $maxl;

  my $conf_label        = $conf->semantic_setting($track_name => 'label',$length);
  $conf_label           = 1 unless defined $conf_label;

  $option ||= 0;
  return  $option == 0 ? $maxed_out && $conf_label
        : $option == 3 ? $conf_label || 1
	: $option == 5 ? $conf_label || 1
        : 0;
}

#copied from Bio::Graphics::Browser (lib)
sub do_description {
  my $self = shift;
  my ($track_name,$option,$count,$max_labels,$length) = @_;

  my $conf              = $self->source;

  my $maxl              = $conf->code_setting($track_name => 'label density')
                       || $conf->code_setting("TRACK DEFAULTS" => 'label density');
  $maxl                 = $max_labels unless defined $maxl;
  my $maxed_out = $count <= $maxl;

  my $conf_description  = $conf->semantic_setting($track_name => 'description',$length);
  $conf_description     = 0 unless defined $conf_description;
  $option ||= 0;
  return  $option == 0 ? $maxed_out && $conf_description
        : $option == 3 ? $conf_description || 1
        : $option == 5 ? $conf_description || 1
        : 0;
}


# override make_link to allow for code references
sub make_link {
  my $self     = shift;
  my ($feature,$panel,$label,$track)  = @_;

  my $data_source = $self->source;
  my $ds_name     = $data_source->name;

  if ($feature->can('url')) {
    my $link = $feature->url;
    return $link if defined $link;
  }
  return $label->make_link($feature) if $label && $label->isa('Bio::Graphics::FeatureFile');

  $panel ||= 'Bio::Graphics::Panel';
  $label ||= $data_source->feature2label($feature);

  # most specific -- a configuration line
  my $link     = $data_source->code_setting($label,'link');

  # less specific - a smart feature
  $link        = $feature->make_link if $feature->can('make_link') && !defined $link;

  # general defaults
  $link        = $data_source->code_setting('TRACK DEFAULTS'=>'link') unless defined $link;
  $link        = $data_source->code_setting(general=>'link')          unless defined $link;

  return unless $link;

  if (ref($link) eq 'CODE') {
    my $val = eval {$link->($feature,$panel,$track)};
    $data_source->_callback_complain($label=>'link') if $@;
    return $val;
  }
  elsif (!$link || $link eq 'AUTO') {
    my $n     = $feature->display_name;
    my $c     = $feature->seq_id;
    my $name  = CGI::escape("$n");  # workaround CGI.pm bug
    my $class = eval {CGI::escape($feature->class)}||'';
    my $ref   = CGI::escape("$c");  # workaround again
    my $start = CGI::escape($feature->start);
    my $end   = CGI::escape($feature->end);
    my $src   = CGI::escape(eval{$feature->source} || '');
    my $url   = CGI->request_uri || '../..';
    $url      =~ s!/gbrowse.*!!;
    $url      .= "/gbrowse_details/$ds_name?name=$name;class=$class;ref=$ref;start=$start;end=$end";
    return $url;
  }
  return $data_source->link_pattern($link,$feature,$panel);
}

# make the title for an object on a clickable imagemap
sub make_title {
  my $self = shift;
  my ($feature,$panel,$label,$track) = @_;
  local $^W = 0;  # tired of uninitialized variable warnings
  my $data_source = $self->source;

  my ($title,$key) = ('','');

 TRY: {
    if ($label && $label->isa('Bio::Graphics::FeatureFile')) {
      $key = $label->name;
      $title = $label->make_title($feature) or last TRY;
      return $title;
    }

    else {
      $label     ||= $data_source->feature2label($feature) or last TRY;
      $key       ||= $data_source->setting($label,'key') || $label;
      $key         =~ s/s$//;
      $key         = $feature->segment->dsn if $feature->isa('Bio::Das::Feature');  # for DAS sources

      my $link     = $data_source->code_setting($label,'title')
	|| $data_source->code_setting('TRACK DEFAULTS'=>'title')
	  || $data_source->code_setting(general=>'title');
      if (defined $link && ref($link) eq 'CODE') {
	$title       = eval {$link->($feature,$panel,$track)};
	$self->_callback_complain($label=>'title') if $@;
	return $title if defined $title;
      }
      return $data_source->link_pattern($link,$feature) if $link && $link ne 'AUTO';
    }
  }

  # otherwise, try it ourselves
  $title = eval {
    if ($feature->can('target') && (my $target = $feature->target)) {
      join (' ',
	    "$key:",
	    $feature->seq_id.':'.
	    $feature->start."..".$feature->end,
	    $feature->target->seq_id.':'.
	    $feature->target->start."..".$feature->target->end);
    } else {
      my ($start,$end) = ($feature->start,$feature->end);
      ($start,$end)    = ($end,$start) if $feature->strand < 0;
      join(' ',
	   "$key:",
	   $feature->can('display_name') ? $feature->display_name : $feature->info,
	   ($feature->can('seq_id')      ? $feature->seq_id : $feature->location->seq_id)
	   .":".
	   (defined $start ? $start : '?')."..".(defined $end ? $end : '?')
	  );
    }
  };
  warn $@ if $@;

  return $title;
}

sub make_link_target {
  my $self = shift;
  my ($feature,$panel,$label,$track) = @_;
  my $data_source = $self->source;

  if ($feature->isa('Bio::Das::Feature')) { # new window
    my $dsn = $feature->segment->dsn;
    $dsn =~ s/^.+\///;
    return $dsn;
  }

  $label    ||= $data_source->feature2label($feature) or return;
  my $link_target = $data_source->code_setting($label,'link_target')
    || $data_source->code_setting('LINK DEFAULTS' => 'link_target')
    || $data_source->code_setting(general => 'link_target');
  $link_target = eval {$link_target->($feature,$panel,$track)} if ref($link_target) eq 'CODE';
  $data_source->_callback_complain($label=>'link_target') if $@;
  return $link_target;
}

# FIXME - belongs in Render.pm, not here
sub citation {
  my $self = shift;
  my $label     = shift;
  my $language  = shift;
  my $config = $self->source;
  my $c;
  if ($language) {
    for my $l ($language->language) {
      $c ||= $config->setting($label=>"citation:$l");
    }
  }
  $c ||= $config->setting($label=>'citation');
  $c;
}
1;

