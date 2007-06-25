package Bio::Graphics::Browser::RenderTracks;

use strict;
use warnings;

use Bio::Graphics;

use constant GBROWSE_RENDER => 'gbrowse_render';  # name of the CGI-based image renderer
use constant TRUE => 1;
use constant DEBUG => 1;

use constant DEFAULT_KEYSTYLE => 'between';
use constant DEFAULT_EMPTYTRACKS => 0;
use constant PAD_DETAIL_SIDES    => 10;

# when we load, we set a global indicating the LWP::Parallel::UserAgent is available
my $LPU_AVAILABLE;
my $STO_AVAILABLE;

sub new {
  my $class       = shift;
  my %options     = @_;
  my $segment       = $options{-segment};
  my $data_source   = $options{-source};
  my $page_settings = $options{-settings};

  my $self  = bless {},ref $class || $class;
  $self->segment($segment);
  $self->source($data_source);
  $self->settings($page_settings);
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
  for my $third_party (@$third_party) {   #FIX ME! (9) $third_party is a reference to a hash element, not array
    my $name = $third_party->name or next;  # every third party feature has to have a name now
    $results->{$name} = $self->render_third_party($third_party,$render_options);
  }

  # oh, ouch, we've got to do something with the plugins... or maybe they're handled by the third party hash?

  return $results;
}

sub use_renderfarm {
  my $self   = shift;

  $self->source->global_setting('renderfarm') or return;

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

  eval { require 'HTTP::Request::Common' } unless HTTP::Request::Common->can('POST');

  my $dsn      = $self->source;
  my $settings = $self->settings;

  # serialize the data source and settings
  my $s_dsn = Storable::freeze($dsn);
  my $s_set = Storable::freeze($settings);

  my $ua = LWP::Parallel::UserAgent->new;
  $ua->in_order(0);
  $ua->nonblock(1);

  for my $url (keys %$renderers) {
    my @tracks  = keys %{$renderers->{$url}};
    my $s_track  = Storable::freeze(\@tracks);
    my $request = POST($url,
		       [tracks     => $s_track,
			settings   => $s_set,
			datasource => $s_dsn]);
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
      $track_results{$track_name} = [$gd,$imagemap];
    }
  }
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

  # sort tracks by the database they come from
  my (%track2db,%db2db);

  for my $track (@$tracks) { 
    my $db = eval { $source->open_database($track)};
    unless ($db) { warn "Couldn't open database for $_: $@"; next; }
    $track2db{$db}{$track}++;
    $db2db{$db}  =  $db;  # cache database object
  }

  my %merged_results;

  for my $dbname (keys %track2db) {
    my $db        = $db2db{$dbname};              # database object
    my @tracks = keys %{$track2db{$dbname}};   # all tracks that use this database
    my $results_for_this_db = $self->image_and_map(-db      => $db,   #FIX ME! (8) Not returning a hash element, only a single GD object
						   -tracks  => \@tracks,
						   -options  => $options);
    %merged_results = (%merged_results,%$results_for_this_db);  #FIX ME! (8) Can't add to hash as it's a single GD object
  }
  return \%merged_results;
}


# finally....
# this is the routine that actually does the work!!!!
sub image_and_map {
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

  # Bring in the appropriate package - just for the fonts. Ugh.
  eval "use $image_class";

  my $width          = $settings->{width};

  my $max_labels     = $source->setting('label density');
  my $max_bump       = $source->setting('bump density');
  my $length         = $segment->length;

  my @feature_types  = map { $source->label2type($_,$length) } @$tracks;
  my %filters = map { my %conf =  $source->style($_); 
		      $conf{'-filter'} ? ($_ => $conf{'-filter'})
			               : ($_ => \&TRUE)
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
	      -key_color => $self->setting('key bgcolor')     || 'moccasin',   #FIX ME! (3) Suggestion: $source->setting ...
	      -bgcolor   => $self->setting('detail bgcolor')  || 'white',      #FIX ME! (3) Suggestion: $source->setting ...
	      -width     => $width,
	      -key_style    => $keystyle || $source->setting(general=>'keystyle') || DEFAULT_KEYSTYLE,
	      -empty_tracks => $source->setting(general=>'empty_tracks') 	  || DEFAULT_EMPTYTRACKS,
	      -pad_top      => $title ? $image_class->gdMediumBoldFont->height : 0,
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

  my $panel = Bio::Graphics::Panel->new(@argv);

  $panel->add_track($segment      => 'arrow',
		    -double       => 1,
		    -tick         => 2,
		    -label        => $options->{label_scale} ? $segment->seq_id : 0,
		    -units        => $source->setting(general=>'units') || '',
		    -unit_divider => $source->setting(general=>'unit_divider') || 1,
		   ) unless $suppress_scale;

  my (%track2label,%tracks,@blank_tracks);

  for (my $i= 0; $i < @$tracks; $i++) {

    my $label = $tracks->[$i];

    # if "hide" is set to true, then track goes away
    next if $source->semantic_setting($label=>'hide',$length);

    my $track;

    # if the section is marked as being a "global feature", then we apply the glyph to the entire segment
    if ($source->semantic_setting($label=>'global feature',$length)) {
      $track = $panel->add_track($segment,
				 $source->default_style,
				 $source->i18n_style($label,$lang),
				);
    }

    else {
      my @settings = ($source->default_style,$source->i18n_style($label,$lang,$length));
      push @settings,(-hilite => $hilite_callback) if $hilite_callback;
      $track = $panel->add_track(-glyph => 'generic',@settings);
    }

    $track2label{$track} = $label;
    $tracks{$label}      = $track;
  }

  if (@feature_types) {  # don't do anything unless we have features to fetch!

    my $iterator = $segment->get_feature_stream(-type=>\@feature_types);
    warn "feature types = @feature_types\n" if DEBUG;
    my (%groups,%feature_count,%group_pattern,%group_on,%group_on_field);

    while (my $feature = $iterator->next_seq) {

      warn "next feature = $feature, type = ",$feature->type,' method = ',$feature->method,
	' start = ',$feature->start,' end = ',$feature->end,"\n" if DEBUG;

      # allow a single feature to live in multiple tracks
      for my $label ($self->feature2label($feature,$length)) {    #FIX ME! (5) Suggestion: $source->feature2label ...
	my $track = $tracks{$label}  or next;
	$filters{$label}->($feature) or next;

	warn "feature = $feature, label = $label, track = $track\n" if DEBUG;

	$feature_count{$label}++;

	# Handle name-based groupings.  Since this occurs for every feature
	# we cache the pattern data.
	warn "$track group pattern => ",$source->code_setting($label => 'group_pattern') if DEBUG;
	exists $group_pattern{$label} or $group_pattern{$label} = $source->code_setting($label => 'group_pattern');
	
	if (defined $group_pattern{$label}) {
	  push @{$groups{$label}},$feature;
	  next;
	}

	# Handle generic grouping (needed for GFF3 database)
	warn "$track group_on => ",$source->code_setting($label => 'group_on') if DEBUG;
	exists $group_on_field{$label} or $group_on_field{$label} = $source->code_setting($label => 'group_on');
	
	if (my $field = $group_on_field{$label}) {
	  my $base = eval{$feature->$field};
	  if (defined $base) {
	    my $group_on_object = $group_on{$label}{$base} ||= Bio::Graphics::Feature->new(-start=>$feature->start,
											      -end  =>$feature->end,
											      -strand => $feature->strand,
											      -type =>$feature->primary_tag);
	    $group_on_object->add_SeqFeature($feature);
	    next;
	  }
	}

	$track->add_feature($feature);
      }
    }

    # fix up groups and group_on
    # the former is traditional name-based grouping based on a common prefix/suffix
    # the latter creates composite features based on an arbitrary method call

    for my $label (keys %group_on) {
      my $track = $tracks{$label};
      my $group_on = $group_on{$label} or next;
      $track->add_feature($_) foreach values %$group_on;
    }

    # handle pattern-based group matches
    for my $label (keys %groups) {
      my $track = $tracks{$label};
      # fix up groups
      my $set     = $groups{$label};
      my $pattern = $group_pattern{$label} or next;
      $pattern =~ s!^/(.+)/$!$1!;  # clean up regexp delimiters

      my $count    = $feature_count{$label};
      $count       = $limit->{$label} if $limit->{$label} && $limit->{$label} < $count;
      my $do_bump  = $self->do_bump($label, $options->{$label},$count,$max_bump,$length);

      if (!$do_bump) {  # don't bother grouping if we aren't bumping - no one will see anyway
	$track->add_feature($_) foreach @$set;
	next;
      }

      my %pairs;
      for my $a (@$set) {
	my $name = $a->name or next;
	(my $base = $name) =~ s/$pattern//i;
 	push @{$pairs{$base}},$a;
      }
      foreach (values %pairs) {
	$track->add_group($_);
      }
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

  for my $track (@blank_tracks) {
    my $file = $feature_files->{$tracks->[$track]} or next;
    ref $file or next;
    $track += $offset + $extra_tracks;
    my $name = $file->name || '';
    $options->{$name} ||= 0;
    my ($inserted,undef,$new_tracks)
      = eval { $file->render($panel,$track,$options->{$name},
			     $max_bump,$max_labels,
			     $select
			    )
	     };
    $self->error("$name: $@") if $@;
    foreach (@$new_tracks) {
      $track2label{$_} = $file;
    }
    $offset += $inserted-1; # adjust for feature files that insert multiple tracks
  }

  my $gd = $panel->gd;

  if ($title) {
    my $x = ($width - length($title) * $image_class->gdMediumBoldFont->width)/2;
    $gd->string($image_class->gdMediumBoldFont,$x,0,$title,$panel->translate_color('black'));
  }
  return $gd   unless wantarray;

  my $boxes    = $panel->boxes;

  return ($gd,$boxes,$panel,\%track2label);

  
}


#FIX ME! (6,7)  I've copied and modified the following 3 methods from the original Browser to fit
#with the current implementation. (June24)
#
#copied from Bio::Graphics::Browser (lib)
sub do_bump {
  my $self = shift;
  my ($track_name,$option,$count,$max,$length) = @_;

  my $conf              = $self->source;
  my $maxb              = $conf->code_setting($track_name => 'bump density');# ||
#  				$conf->code_setting("TRACK DEFAULTS"=> 'bump density');#warn"maxb is $maxb"; 
  $maxb                 = $max unless defined $maxb;

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

  my $maxl              = $conf->code_setting($track_name => 'label density');
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

  my $maxl              = $conf->code_setting($track_name => 'label density');
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






1;

