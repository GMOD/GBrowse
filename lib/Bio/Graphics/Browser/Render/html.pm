package Bio::Graphics::Browser::Render::html;

# A class for rendering HTML for gbrowse
# contains non-template-specific methods

use strict;
use Carp 'croak','cluck';
use CGI ':standard';

use vars qw/$HEADER/;

use Data::Dumper;


sub new {
  my $caller  = shift;
  my $base    = shift;
  my $self    = bless {}, $caller;

  $self->base($base);
  $self->config($base->$config);
  return $self;
}

=head1 METHODS

=head2 config

Getter/setter for data source-specific configuration 
and general utilities via a Bio::Graphics::Browser object.

=cut

sub config {
  my $self   = shift;
  my $config = shift;
  return $config ? $self->{config} = $config : $self->{config};
}


=head2 base

Getter/setter for the parent rendering object.  Provides access
to configuration and shared HTML rendering methods

=cut

sub base {
  my $self = shift;
  my $base = shift;
  return $base ? $self->{base} = $base : $self->{base};
}

=head2 setting

Pass though to Render.pm setting method

=cut

sub setting {
  my $self = shift;
  return $self->base->setting(@_);
}

=head2 global_setting

Pass though to Render.pm global_setting method

=cut

sub global_setting {
  my $self = shift;
  return $self->base->global_setting(@_);
}


=head2 print_top 

prints the page header and start_html

=cut

sub print_top {
  my $self   = shift;
  my ($title, $reset_all) = @_;

  # sjm note to self: Is there a cleaner way to do this?
  local $^W = 0;  # to avoid a warning from CGI.pm                                                                                                                                                               
  my $config = $self->config;

  my $js = $self->global_setting('js');

  my @scripts = {src=>"$js/buttons.js"};
  if ($self->setting('autocomplete')) {
    push @scripts,{src=>"$js/$_"} foreach qw(yahoo.js dom.js event.js connection.js autocomplete.js);
  }

  print_header(-expires=>'+1m');
  my @args = (-title => $title,
              -style  => {src=>$self->setting('stylesheet')},
              -encoding=>$config->tr('CHARSET'),
	      );
  push @args,(-head=>$self->setting('head'))    if $self->setting('head');
  push @args,(-lang=>($config->language_code)[0]) if $config->language_code;
  push @args,(-script=>\@scripts);
  push @args,(-reset_toggle   => 1)               if $reset_all;
  print start_html(@args) unless $self->{html}++;
}


=head2 print_bottom

 usage

Description

=cut

sub print_bottom {
  my $self    = shift;
  my $version = shift;
  my $config = $self->config;

  print
    $config->footer || '',
      p(i(font({-size=>'small'},
               $config->tr('Footer_1'))),br,
        tt(font({-size=>'small'},$config->tr('Footer_2',$version)))),
      end_html;
}

=head2 slidertable

 my $navigation_bar = $browser_run->slidertable;
 
Makes the zoom menu with pan buttons

=cut

sub slidertable {
  my $self       = shift;
  my $small_pan  = shift;
  my $buttons    = $self->global_setting('buttons');
  my $segment    = $self->current_segment or fatal_error("No segment defined");
  my $span       = $small_pan ? int $segment->length/2 : $segment->length;
  my $half_title = $self->base->unit_label( int $span / 2 );
  my $full_title = $self->base->unit_label($span);
  my $half       = int $span / 2;
  my $full       = $span;
  my $fine_zoom  = $self->base->get_zoomincrement();
  Delete($_) foreach qw(ref start stop);
  my @lines;
  push @lines,
  hidden( -name => 'start', -value => $segment->start, -override => 1 );
  push @lines,
  hidden( -name => 'stop', -value => $segment->end, -override => 1 );
  push @lines,
  hidden( -name => 'ref', -value => $segment->seq_id, -override => 1 );
  push @lines, (
                image_button(
                             -src    => "$buttons/green_l2.gif",
                             -name   => "left $full",
                             -border => 0,
                             -title  => "left $full_title"
                             ),
                image_button(
                             -src    => "$buttons/green_l1.gif",
                             -name   => "left $half",
                             -border => 0,
                             -title  => "left $half_title"
                             ),
                '&nbsp;',
                image_button(
                             -src    => "$buttons/minus.gif",
                             -name   => "zoom out $fine_zoom",
                             -border => 0,
                             -title  => "zoom out $fine_zoom"
                             ),
                '&nbsp;', $self->zoomBar, '&nbsp;',
                image_button(
                             -src    => "$buttons/plus.gif",
                             -name   => "zoom in $fine_zoom",
                             -border => 0,
                             -title  => "zoom in $fine_zoom"
                             ),
                '&nbsp;',
                image_button(
                             -src    => "$buttons/green_r1.gif",
                             -name   => "right $half",
                             -border => 0,
                             -title  => "right $half_title"
                             ),
                image_button(
                             -src    => "$buttons/green_r2.gif",
                             -name   => "right $full",
                             -border => 0,
                             -title  => "right $full_title"
                             ),
                );
  return join( '', @lines );
}

=head2 zoomBar

 my $zoombar = $self->zoomBar;

Creates the zoom bar

=cut

sub zoomBar {
  my $self    = shift;
  my $segment = $self->base->current_segment;
  my ($show)  = $self->base->tr('Show');
  my %seen;
  my @ranges = grep { !$seen{$_}++ } sort { $b <=> $a } ($segment->length, $self->get_ranges());
  my %labels = map { $_ => $show . ' ' . $self->base->unit_label($_) } @ranges;
  return popup_menu(
    -class    => 'searchtitle',
    -name     => 'span',
    -values   => \@ranges,
    -labels   => \%labels,
    -default  => $segment->length,
    -force    => 1,
    -onChange => 'document.mainform.submit()',
		    );
}

=head2 make_overview

 my $overview = $browser_run->overview($settings,$featurefiles);

Creates an overview image as an image_button

=cut

sub make_overview {
  my ( $self, $settings, $feature_files ) = @_;
  my $segment       = $self->base->current_segment || return;
  my $whole_segment = $self->base->whole_segment;

  my $overview_ratio = $self->global_setting('OVERVIEW_RATIO');
  $self->width( $settings->{width} * $overview_ratio );

  my ( $image, $length )
      = $self->overview( $whole_segment, $segment, $settings->{features},
                         $feature_files )
      or return;

  # restore the original width!
  my $restored_width = $self->width/$overview_ratio;
  $self->width($restored_width);

  my ( $width, $height ) = $image->getBounds;
  my $url = $self->config->generate_image($image);

  return image_button(
                      -name   => 'overview',
                      -src    => $url,
                      -width  => $width,
                      -height => $height,
                      -border => 0,
                      -align  => 'middle'
                      )
      . hidden(
               -name     => 'seg_min',
               -value    => $whole_segment->start,
               -override => 1
               )
      . hidden(
               -name     => 'seg_max',
               -value    => $whole_segment->end,
               -override => 1
               );
}

=head2 overview_panel

 my $overview_panel = $render->overview_panel($settings,$featurefiles);

Creates a DHTML-toggle panel with the overview image

=cut

sub overview_panel {
  my ( $self, $page_settings, $feature_files ) = @_;
  my $segment = $self->base->current_segment || return;
  return '' if $self->config->section_setting('overview') eq 'hide';
  my $image = $self->make_overview( $page_settings, $feature_files );
  return $self->base->toggle(
                       'Overview',
                       table(
                             { -border => 0, -width => '100%', },
                             TR( { -class => 'databody' }, td( { -align => 'center' }, $image ) )
                             )
                       );
}


=head2 navigation_table

 usage

Description

=cut

sub navigation_table {
  my $self = shift;
  my ($segment,$whole_segment,$settings) = @_;
  my $config = $self->config;
  my $buttonsDir    = $self->global_setting('buttons') || $self->global_setting('buttonsdir');
  my $table        = '';
  my $svg_link     = $HAVE_SVG? a({-href=>svg_link($settings),-target=>'_blank'},'['.$config->tr('SVG_LINK').']'):'';
  my $reset_link   = a({-href=>"?reset=1",-class=>'reset_button'},'['.$config->tr('RESET').']');
  my $help_link    =  a({-href=>general_help(),-target=>'help'},'['.$config->tr('Help').']');
  my $plugin_link  = plugin_links($PLUGINS);
  my $oligo        = $PLUGINS->plugin('OligoFinder') ? ', oligonucleotide (15 bp minimum)' : '';
  my $rand         =   substr(md5_hex(rand),0,5);

  $table .= table({-border=>0, -width=>'100%',-cellspacing=>0,-class=>'searchtitle'},
		  TR(
		     td({-align=>'left', -colspan=>2},
			toggle($settings,
			       'Instructions',
			       br(),
			       $config->setting('search_instructions') ||
			       $config->tr('SEARCH_INSTRUCTIONS',$oligo),
			       $config->setting('navigation_instructions') ||
			       $config->tr('NAVIGATION_INSTRUCTIONS'),
			       br(),
			       show_examples()
			      )
		       ),
		    ),
		  TR(
		     th({-align=>'left', -colspan=>2,-class=>'linkmenu'},
			 $settings->{name} || $settings->{ref} ?
			 (
			  a({-href=>"?rand=$rand;head=".((!$settings->{head})||0)},
			    '['.$config->tr($settings->{head} ? 'HIDE_HEADER' : 'SHOW_HEADER').']'),
			  a({-href=>bookmark_link($settings)},'['.$config->tr('BOOKMARK').']'),
			  a({-href=>image_link($settings),-target=>'_blank'},'['.$config->tr('IMAGE_LINK').']'),
			  $plugin_link,
			  $svg_link,
			 ) : (),
			$help_link,
			$reset_link
		       ),
		     )
		 );

  my $autocomplete = $config->setting('autocomplete');
  my $searchfield;
  if ($autocomplete) {
    $searchfield = div({-id=>'autocomplete'},
		       textfield(-name=>'name',
				 -size=>25,
				 -default=>$settings->{name},
				 -id=>'autoCompleteInput1',
				 -autocomplete=>'off'),
		       submit(-name=>$config->tr('Search')),
		       div({-id=>'autoCompleteContainer1',-style=>'position:relative;top:-1.5em'},''));
    $searchfield .= script({-type=>'text/javascript'},<<END);
var autoCompleteServer  = "$autocomplete";
var autoCompleteSchema  = ["\\n"];
var autoCompleteData1 = new YAHOO.widget.DS_XHR(autoCompleteServer, autoCompleteSchema); 
autoCompleteData1.responseType = autoCompleteData1.TYPE_FLAT;

var autoComplete1 = new YAHOO.widget.AutoComplete("autoCompleteInput1","autoCompleteContainer1",autoCompleteData1);
autoComplete1.allowBrowserAutocomplete = false;
autoComplete1.typeAhead = true;
autoComplete1.useShadow = true;
autoComplete1.queryDelay = 0;
autoComplete1.minQueryLength = 1;
END
  } else {
    $searchfield = textfield(-name=>'name',
			     -size=>25,
			     -default=>$settings->{name}).
	           submit(-name=>$config->tr('Search'));
  }

  my $searchbox = $config->setting('no search')
    ? '' : b($config->tr('Landmark')).':'.br().$searchfield;

  my $plugin_menu = plugin_menu($settings,$PLUGINS);
  my $plugins     = $plugin_menu ? b($config->tr('Dumps')).':'.br.$plugin_menu : '';

  my $slider = '';
  if ($segment) {
    $slider =  b($config->tr('Scroll').': ').
      slidertable($segment,$whole_segment,$buttonsDir).
	b(
	  checkbox(-name=>'flip',
		   -checked=>$settings->{flip},-value=>1,
		   -label=>$config->tr('Flip'),-override=>1)
	 );
  }


  $table .= toggle($settings,
		   'Search',
		   div({-class=>'searchbody'},
		       html_frag('html1',$segment,$settings)||'',
		       div({-style=>'float:left; width:50%'},
			   $searchbox),
		       div({-style=>'float:right; width:50%'},
			   $plugins),
		       br({-clear=>'all'}),
		       table({-class=>'searchbody'},
			     TR(td({-align=>'left'},
				   source_menu($settings)
				  ),
				td({-align=>'left'},
				   $slider || '&nbsp;'
				  )
			       )
			    )
		      )
		  );
  return $table;
}


=head2 tracks_table

 usage

Description

=cut

sub tracks_table {
  my $self     = shift;
  my $settings = shift;
  my $additional_features = shift;

  # set up the dumps line.
  my($ref,$start,$stop) = @{$settings}{qw(ref start stop)};
  my $source   = $self->config->source;
  my $self_url = "?help=citations";

  my @labels     = @{$settings->{tracks}};
  my %labels     = map {$_ => make_citation_link($_,$self_url) } @labels;
  my %label_keys = map {$_ => label2key($_)}                     @labels;
  my @defaults   = grep {$settings->{features}{$_}{visible}  }   @labels;

  # Sort the tracks into categories:
  # Overview tracks
  # Region tracks
  # Regular tracks (which may be further categorized by user)
  # Plugin tracks
  # External tracks
  my %track_groups;
  foreach (@labels) {
    my $category = categorize_track($_);
    push @{$track_groups{$category}},$_;
  }

  autoEscape(0);
  my @sections;

  my %exclude = map {$_=>1} map {$self->config->tr($_)} qw(OVERVIEW REGION ANALYSIS EXTERNAL);

  my @user_keys = grep {!$exclude{$_}} sort keys %track_groups;
  # my $id = "c00000";

  my $all_on  = $self->config->tr('ALL_ON');
  my $all_off = $self->config->tr('ALL_OFF');

  my %seenit;
  foreach my $category ($self->config->tr('OVERVIEW'),
			$self->config->tr('REGION'),
			$self->config->tr('ANALYSIS'),
			@user_keys,
			$self->config->section_setting('upload_tracks') eq 'off' ? () : ($self->config->tr('EXTERNAL')),
		       ) {
    next if $seenit{$category}++;
    my $table;
    my $id = "${category}_section";

    if ($category eq $self->config->tr('REGION') && !$self->config->setting('region segment')) {
     next;
    }
    elsif  (exists $track_groups{$category}) {
      my @track_labels = @{$track_groups{$category}};
      @track_labels = sort {lc $label_keys{$a} cmp lc $label_keys{$b}} @track_labels
        if ($settings->{sk} eq "sorted");
      my @checkboxes = checkbox_group(-name       => 'label',
				      -values     => \@track_labels,
				      -labels     => \%labels,
				      -defaults   => \@defaults,
				      -onClick    => "gbTurnOff('$id')",
				      -override   => 1,
				     );
      $table = tableize(\@checkboxes);
      $table =~ s/<tr>/<tr class="searchtitle">/g;

      my $visible = exists $page_settings->{section_visible}{$id} ? $page_settings->{section_visible}{$id} : 1;

      my ($control,$section)=toggle_section({on=>$visible,nodiv=>1},
					    $id,
					    b(ucfirst $category),div({-style=>'padding-left:1em'},span({-id=>$id},$table)));
      $control .= '&nbsp;'.i({-class=>'nojs'},
			     checkbox(-id=>"${id}_a",-name=>"${id}_a",
				      -label=>$all_on,-onClick=>"gbCheck(this,1)"),
			     checkbox(-id=>"${id}_n",-name=>"${id}_n",
				      -label=>$all_off,-onClick=>"gbCheck(this,0)")
			    ).br()   if exists $track_groups{$category};
      push @sections,div($control.$section);
      $id++;
    }

    else {
      #$table = table(TR({-class=>'searchtitle',-width=>'100%'},td($self->config->tr('NO_TRACKS'))));
      next;
    }

  }

  autoEscape(1);
  return toggle($settings,
		'Tracks',
		div({-class=>'searchbody',-style=>'padding-left:1em'},@sections),
		table({-width=>'100%',-class=>"searchbody"},
		      TR(td{-align=>'right'},
			 submit(-name => $self->config->tr('Set_options')),
			 b(submit(-name => $self->config->tr('Update'))
			  )
			)
		     ));
}



=head2 external_table

 usage

Description

=cut

sub external_table {
  my $self     = shift;
  my ($settings,$feature_files) = @_;
  my $upload_table = upload_table($settings,$feature_files);
  my $das_table    = das_table($settings,$feature_files);
  toggle($settings,
	 'Upload_tracks',
	 table({-width=>'100%',-class=>'searchbody'},
	       TR(td($upload_table,$das_table))));
}



=head2 settings_table

 usage

Description

=cut

sub settings_table {
  my $self     = shift;
  my $settings = shift;

  my @widths = split /\s+/,$self->config->setting('image widths');
  @widths = (640,800,1024) unless @widths;
  my @key_positions   = qw(between bottom);
  push @key_positions,qw(left right) if Bio::Graphics::Panel->can('auto_pad');

  my $feature_highlights = $settings->{h_feat}   ?
    join ' ',map { "$_\@$settings->{h_feat}{$_}"   } keys %{$settings->{h_feat}} : '';

  my $region_highlights  = $settings->{h_region} ?
    join ' ',@{$settings->{h_region}} : '';

  my @region_sizes = split /\s+/,$self->config->setting('region sizes') || DEFAULT_REGION_SIZES;
  unshift @region_sizes,0;

  my $content =
    table({-class=>'searchbody',-border=>0,-width=>'100%'},
	  TR(
	     td(
		b($self->config->tr('Image_width')),br,
		radio_group( -name=>'width',
			     -values=>\@widths,
			     -default=>$settings->{width},
			     -override=>1,
			   ),
	       ),
	     td(
		b($self->config->tr('KEY_POSITION')),br,
		radio_group( -name=>'ks',
			     -values=>\@key_positions,
			     -labels=>{between=>$self->config->tr('BETWEEN'),
				       bottom =>$self->config->tr('BENEATH'),
				       left   =>$self->config->tr('LEFT'),
				       right  =>$self->config->tr('RIGHT'),
				      },
			     -default=>$settings->{ks},
			     -override=>1
			   ),
	       ),
             td(
                b($self->config->tr("TRACK_NAMES")),br,
                radio_group( -name=>"sk",
                             -values=>["sorted","unsorted"],
                             -labels=>{sorted   =>$self->config->tr("ALPHABETIC"),
                                       unsorted =>$self->config->tr("VARYING")},
                             -default=>$settings->{sk},
                             -override=>1
                           ),
               ),
	    ),
	  TR(
	     td(
		span({-title=>$self->config->tr('FEATURES_TO_HIGHLIGHT_HINT')},
		     b(
		       $self->config->tr('FEATURES_TO_HIGHLIGHT')
		      ),br,
		     textfield(-name  => 'h_feat',
			       -value => $feature_highlights,
			       -size  => 50,
			       -override=>1,
			      ),
		    ),
	       ),
	     td(
		span({-title=>$self->config->tr('REGIONS_TO_HIGHLIGHT_HINT')},
		     b(
		       $self->config->tr('REGIONS_TO_HIGHLIGHT')
		      ),br,
		     textfield(-name=>'h_region',
			       -value=>$region_highlights,
			       -size=>50,
			       -override=>1,
			      ),
		    ),
	       ),
	     td(
		b(
		  checkbox(-name=>'grid',
			   -label=>$self->config->tr('SHOW_GRID'),
			   -override=>1,
			   -checked=>$settings->{grid}||0)
		 )
	       ),
	    ),
	  $self->config->setting('region segment') ?
	     (
	      TR(
		 td({-colspan=>3},
		    b($self->config->tr('Region_size')),
		    popup_menu(-name=>'region_size',
			       -default =>$settings->{region_size},
			       -override=> 1,
			       -values  => \@region_sizes),
		   )
		)
	     ) : (),
	  TR(td({-colspan=>4,
		 -align=>'right'},
		b(submit(-name => $self->config->tr('Update')))))
	 );
  return toggle($settings,
		'Display_settings',$content);
}



=head2 upload_table

 usage

Description

=cut

sub upload_table {
  my $self          = shift;
  my $settings      = shift;
  my $feature_files = shift;

  # start the table.
  my $cTable = start_table({-border=>0,-width=>'100%'})
    . TR(
	 th({-class=>'uploadtitle', -colspan=>4, -align=>'left'},
	    $self->config->tr('Upload_title').':',
	    a({-href=>annotation_help(),-target=>'help'},'['.$self->config->tr('HELP').']'))
	);

  # now add existing files
  for my $file ($UPLOADED_SOURCES->files) {
    (my $name = $file) =~ s/^file://;
    $name = escape($name);
    my $download = escape($self->config->tr('Download_file'));
    my $link = a({-href=>"?$download=$file"},"[$name]");
    my @info =  get_uploaded_file_info($settings->{features}{$file}{visible}
				       && $feature_files->{$file});
    $cTable .=  TR({-class=>'uploadbody'},
		   th($link),
		   td({-colspan=>3},
		      submit(-name=>"modify.$file",-value=>$self->config->tr('Edit')).'&nbsp;'.
		      submit(-name=>"modify.$file",-value=>$self->config->tr('Download_file')).'&nbsp;'.
		      submit(-name=>"modify.$file",-value=>$self->config->tr('Delete'))));
    $cTable .= TR({-class=>'uploadbody'},td('&nbsp;'),td({-colspan=>3},@info));
  }

  # end the table.
  $cTable .= TR({-class=>'uploadbody'},
		th({-align=>'right'},$self->config->tr('Upload_File')),
		td({-colspan=>3},
		   filefield(-size=>40,-name=>'upload_annotations'),
		   '&nbsp;',
		   submit(-name=>$self->config->tr('Upload')),
		   '&nbsp;',
		   submit(-name=>'new_upload',-value=>$self->config->tr('New')),
		  )
	       );
  $cTable .= end_table;
  $cTable;
}


=head2 das_table

 usage

Description

=cut

sub das_table {
  my $self          = shift;
  my $settings      = shift;
  my $feature_files = shift;
  my (@rows,$count);

  my ($preset_labels,$preset_urls) = get_external_presets($settings);  # (arrayref,arrayref)
  my $presets = '&nbsp;';
  if ($preset_labels && @$preset_labels) {  # defined AND non-empty
    my %presets;
    @presets{@$preset_urls} = @$preset_labels;
    unshift @$preset_urls,'';
    $presets{''} = $self->config->tr('PRESETS');
    $presets = popup_menu(-name   => 'eurl',
			  -values => $preset_urls,
			  -labels => \%presets,
			  -override => 1,
			  -default  => '',
			  -onChange => 'document.externalform.submit()'
			 );
  }

  local $^W = 0;
  if (defined $settings->{ref}) {
    my $segment = "$settings->{ref}:$settings->{start},$settings->{stop}";
    for my $url ($REMOTE_SOURCES->sources) {

      (my $f = $url) =~ s!(http:.+/das/\w+)(?:\?(.+))?$!$1/features?segment=$segment;$2!;
      warn "url = $url" if DEBUG_EXTERNAL;
      next unless $url =~ /^(ftp|http):/ && $feature_files->{$url};
      warn "external_table(): url = $url" if DEBUG;
      push @rows,th({-align=>'right',-valign=>'TOP'},"URL",++$count).
	td(textfield(-name=>'eurl',-size=>50,-value=>$url,-override=>1),br,
	   a({-href=>$f,-target=>'help'},'['.$self->config->tr('Download').']'),
	   get_uploaded_file_info($settings->{features}{$url}{visible} && $feature_files->{$url})
	  );
    }
    push @rows,th({-align=>'right'},
		  $self->config->tr('Remote_url')).
		    td(textfield(-name=>'eurl',-size=>40,-value=>'',-override=>1),
		       $presets);
  }

  return table({-border=>0,-width=>'100%'},
	       TR(
		  th({-class=>'uploadtitle',-align=>'left',-colspan=>2},
		     $self->config->tr('Remote_title').':',
		     a({-href=>annotation_help().'#remote',-target=>'help'},'['.$self->config->tr('Help').']'))),
	       TR({-class=>'uploadbody'},\@rows),
	       TR({-class=>'uploadbody'},
		  th('&nbsp;'),
		  th({-align=>'left'},submit($self->config->tr('Update_urls'))))
	      );
}


=head2 multiple_choices

 usage

Description

=cut

sub multiple_choices {
  my $self = shift;
  my ($settings,$results) = @_;

  my $db   = open_database();
  my $name = $settings->{name};
  my $regexp = join '|',($name =~ /(\w+)/g);

  # sort into bins by reference and version
  my %refs;
  foreach (@$results) {
    my $version = eval {$_->isa('Bio::SeqFeatureI') ? undef : $_->version};
    my $ref = $_->seq_id;
    $ref .= " version $version" if defined $version;    
    push @{$refs{$ref}},$_;
  }

  $self->config->width($settings->{width}*$self->config->overview_ratio);
  my $overviews = $self->config->hits_on_overview($db,$results,$settings->{features});
  my $count = @$results;

  print start_table();
  print TR({-class=>'datatitle'},
	   th({-colspan=>4},
	      $self->config->tr('Hit_count',$count)));
  print TR({-class=>'datatitle'},
	   th({-colspan=>4},
	      $self->config->tr('Possible_truncation',MAX_KEYWORD_RESULTS)))
    if $count >= MAX_KEYWORD_RESULTS;

  local $^W = 0;  # get rid of non-numeric warnings coming out of by_score_and_position
  for my $ref(sort keys %refs) {
    my ($id) = split /\s/, $ref; 
    my @results = @{$refs{$ref}};
    print TR(th({-class=>'databody',-colspan=>4,-align=>'center'},$self->config->tr('Matches_on_ref',$ref),br,
		$overviews->{$ref}));

    my $padding = $self->setting(general=>'landmark_padding') || 0;
    my $units    = $self->setting(general=>'units') || $self->config->tr('bp');
    my $divisor  = $self->setting(general=>'unit_divider') || 1;

    for my $r (sort by_score_and_position @results) {
      my $version = eval {$r->isa('Bio::SeqFeatureI') ? undef : $r->version};
      my $name        = eval {$r->name}  || $r->primary_tag;

      my $class       = eval {$r->class} || $CONFIG->tr('Sequence');
      my $score       = eval {$r->score} || $CONFIG->tr('NOT_APPLICABLE');
      my ($start,$stop) = ($r->start,$r->end);
      my $padstart = $start - $padding;
      my $padstop  = $stop  + $padding;
      my $description = escapeHTML(eval{join ' ',$r->attributes('Note')}
				   ||eval{$r->method}||eval{$r->source_tag}||$r->{ref});
      if (my @aliases = grep {$_ ne ''} eval{$r->attributes('Alias')}) {
	$description .= escapeHTML(" [@aliases]");
      }
      my $n           = escape("$name");
      my $c           = escape($class);
      $description =~ s/($regexp)/<b class="keyword">$1<\/b>/ig;
      $description =~ s/(\S{60})/$1 /g;  # wrap way long lines

      my $objref     = $class ? "?name=$c:$n" : "?name=$n";
      my $posref     = "?ref=$id;start=$padstart;stop=$padstop;version=$version";
      my $position = format_segment($r);
      my $length   = unit_label($stop-$start+1);
      print TR({-class=>'databody',-valign=>'TOP'},
	       th({-align=>'right'},ref($name) ? a({-href=>$objref},$name):tt($name)),
	       td($description),
	       td(a({-href=>$posref},$position . " ($length)")),
	       td($CONFIG->tr('SCORE',$score)));
    }
  }
  print end_table;

}



=head2 segment2link

 usage

Description

=cut

sub segment2link {
  my $self = shift;
  my ($segment,$label) = @_;

  my $source = $CONFIG->source;
  return  a({-href=>"?name=$segment"},$segment) unless ref $segment;

  my ($start,$stop) = ($segment->start,$segment->end);
  my $ref = $segment->seq_id;
  my $bp = $stop - $start;
  my $s  = commas($start) || '';
  my $e  = commas($stop)  || '';
  $label ||= "$ref:$s..$e";
  return a({-href=>"?ref=$ref;start=$start;stop=$stop"},$label);
}


=head2 get_uploaded_file_info

 usage

Description

=cut

sub get_uploaded_file_info {
  my $self         = shift;
  my $feature_file = shift or return i("Display off");
  warn "get_uploaded_file_info(): feature_file = $feature_file" if DEBUG;

  my $modified = localtime($feature_file->mtime);
  my @refs      = sort($feature_file->features)
    unless $feature_file->name =~ m!/das/!;

  my $db        = open_database();

  my ($landmarks,@landmarks,@links);

  if (@refs > TOO_MANY_REFS) {
    $landmarks = b($CONFIG->tr('Too_many_landmarks',scalar @refs));
  } else {
    @links = map {segment2link($_,$_->display_name)} @refs;
    $landmarks = tableize(\@links);
  }
  warn "get_uploaded_file_info(): modified = $modified, landmarks = $landmarks" if DEBUG;
  return i($CONFIG->tr('File_info',$modified,$landmarks||''));
}

=head2 regionview

 usage

Description

=cut

sub regionview {
  my ($region_segment,$segment,$settings,$feature_files) = @_;
  return unless $region_segment;

  my ($image,$length) = $CONFIG->regionview($region_segment,$segment,$settings->{features},$feature_files) or return;
  my ($width,$height) = $image->getBounds;
  my $url             = $CONFIG->generate_image($image);
  return image_button(-name=>'regionview',
 		      -src=>$url,
 		      -align=>'middle');
}


=head2 edit_uploaded_file

 usage

Description

=cut

sub edit_uploaded_file {
  my $self = shift;
  my ($settings,$file) = @_;
  warn "edit_uploaded_file(): file = $file" if DEBUG;
  print_top("Editing $file");
  print start_form();
  my $data;
  my $fh = $UPLOADED_SOURCES->open_file($file) or return;
  $data = join '',expand(<$fh>);
  print table({-width=>'100%'},
	      TR({-class=>'searchbody'},
		 td($CONFIG->tr('Edit_instructions')),
		),
	      TR({-class=>'searchbody'},
		 td(
		    a({-href=>"?help=annotation#format",-target=>'help'},
		      b('['.$CONFIG->tr('Help_format').']'))
		   ),
		),
	      TR({-class=>'searchtitle'},
		 th($CONFIG->tr('Edit_title'))),
	      TR({-class=>'searchbody'},
		 td({-align=>'center'},
		    pre(
			textarea(-name    => 'a_data',
				 -value   => $data,
				 -rows    => ANNOTATION_EDIT_ROWS,
				 -cols    => ANNOTATION_EDIT_COLS,
				 -wrap    => 'off',
				 -style   => "white-space : pre"
				))
		   )
		),
	      TR({-class=>'searchtitle'},
		 th(reset($CONFIG->tr('Undo')).'&nbsp;'.
		    submit('Cancel').'&nbsp;'.
		    b(submit('Submit Changes...'))))
	     );
  print hidden(-name=>'edited file',-value=>$file);
  print end_form();
  print_bottom($VERSION);
}


=head2 tableize

 usage

Description

=cut

sub tableize {
  my $self  = shift;
  my $array = shift;
  return unless @$array;
  my $rows    = int(sqrt(@$array));
  my $columns = int(0.99+@$array/$rows);
  my $html = qq(<table border="0">);
  for (my $row=0;$row<$rows;$row++) {
    $html .= "<tr>";
    for (my $column=0;$column<$columns;$column++) {
      if (defined($array->[$column*$rows + $row])) {
	$html .= "<td>" . $array->[$column*$rows + $row] . "</td>"
      } else {
	$html .= "<td>&nbsp;</td>";
      }
    }
    $html .= "</tr>\n";
  }
  $html .= "</table>\n";
}
