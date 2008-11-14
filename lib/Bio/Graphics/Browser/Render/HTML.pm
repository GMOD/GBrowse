package Bio::Graphics::Browser::Render::HTML;

use strict;
use warnings;
use base 'Bio::Graphics::Browser::Render';
use Bio::Graphics::Browser::Shellwords;
use Bio::Graphics::Karyotype;
use Bio::Graphics::Browser::Util qw[citation get_section_from_label url_label];
use Digest::MD5 'md5_hex';
use Carp 'croak';
use CGI qw(:standard escape start_table end_table);
use Text::Tabs;
eval "use GD::SVG";

use constant JS    => '/gbrowse/js';
use constant ANNOTATION_EDIT_ROWS => 25;
use constant ANNOTATION_EDIT_COLS => 100;
use constant DEBUG => 0;

sub render_top {
  my $self  = shift;
  my $title = shift;
  my $dsn   = $self->data_source;
  my $html  = $self->render_html_head($dsn,$title);
  $html    .= $self->render_balloon_settings();
  $html    .= $self->render_select_menus();
  return $html;
}

sub render_bottom {
  my $self = shift;
  my $features = shift; # not used
  return $self->data_source->global_setting('footer').end_html();
}

sub render_navbar {
  my $self    = shift;
  my $segment = shift;

  my $settings = $self->state;
  my $source   = '/'.$self->session->source.'/';

  my $searchform = join '',(
                start_form(
                    -name   => 'searchform',
                    -id     => 'searchform',
                    
                    # Submitting through the Controller seems to have been a bad idea
                    #-onSubmit => q[ 
                    #    Controller.update_coordinates("set segment " + document.searchform.name.value); 
                    #    var return_val = (document.searchform.force_submit.value==1); 
                    #    document.searchform.force_submit.value=0;
                    #    return return_val;
                    #],
                ),
                hidden(-name=>'force_submit',-value=>0),
                div({ -id => 'search_form_objects' },
                  $self->render_search_form_objects(),
                ),
			    end_form
			    );

  my $search = $self->setting('no search')
    ? '' : b($self->tr('Landmark')).':'.br().$searchform;

  my $plugin_form = join '',(
			     start_form(-name=>'pluginform',-id=>'pluginform',
					-onSubmit=>'return false'),
			     $self->plugin_menu(),
			     end_form);

  my $source_form = join '',(
			     start_form(-name=>'sourceform',
					-id=>'sourceform',
					-onSubmit=>''),
			     $self->source_menu(),
			     end_form
			    );

  my $sliderform = '';
  if ($segment) {
    $sliderform =
      join '',(
	       start_form(-name=>'sliderform',-id=>'sliderform',-onSubmit=>'return false'),
	       b($self->tr('Scroll').': '),
	       $self->slidertable($segment),
	       b(
		 checkbox(-name=>'flip',
			  -checked=>$settings->{flip},-value=>1,
			  -label=>$self->tr('Flip'),-override=>1,
              -onClick => 'Controller.update_coordinates(this.name + " " + this.checked)',
                )
		),
	       hidden(-name=>'navigate',-value=>1,-override=>1),
	       end_form
	      );
  }

  return $self->toggle('Search',
		       div({-class=>'searchbody'},
			   $self->html_frag('html1',$segment,$settings)||'',
			   table({-border=>0,-class=>'searchbody'},
				 TR(td($search),td($plugin_form)),
				 TR(td({-align=>'left'},
				       $source_form,
				    ),
				    td({-align=>'left'},
				       $sliderform || '&nbsp;'
				    )
				 )
			   )
		       )
    )
    . div( { -id => "plugin_configure_div"},'&nbsp;'  )
    . br({-clear=>'all'})
;
}

sub render_search_form_objects {
    my $self     = shift;
    my $settings = $self->state;

    return textfield(
        -name    => 'name',
        -id      => 'landmark_search_field',
        -size    => 25,
        -default => $settings->{name}
    ) . submit( -name => $self->tr('Search') );
}

sub render_html_head {
  my $self = shift;
  my ($dsn,$title) = @_;

  return if $self->{started_html}++;

  # pick scripts
  my $js       = $dsn->globals->js_url;
  my @scripts;

  # drag-and-drop functions from scriptaculous
  push @scripts,{src=>"$js/$_"}
    foreach qw(
        prototype.js 
        scriptaculous.js 
        yahoo-dom-event.js 
    );

 if ($self->setting('autocomplete')) {
    push @scripts,{src=>"$js/$_"}
      foreach qw(connection.js autocomplete.js);
  }

  # our own javascript
  push @scripts,{src=>"$js/$_"}
    foreach qw(
               buttons.js 
               toggle.js 
               karyotype.js
               rubber.js
               overviewSelect.js
               detailSelect.js
               regionSelect.js
               track.js
               balloon.js
               balloon.config.js
	       GBox.js
               controller.js
);

  # pick stylesheets;
  my @stylesheets;
#  my $titlebar   = $self->is_safari() ? 'css/titlebar-safari.css' : 'css/titlebar-default.css';
  my $titlebar   = 'css/titlebar-default.css';
  my $stylesheet = $self->setting('stylesheet')||'/gbrowse/gbrowse';
  push @stylesheets,{src => $self->globals->resolve_path($stylesheet,'url')};
  push @stylesheets,{src => $self->globals->resolve_path('css/tracks.css','url')};
  push @stylesheets,{src => $self->globals->resolve_path('css/karyotype.css','url')};
  push @stylesheets,{src => $self->globals->resolve_path($titlebar,'url')};

  # put them all together
  my @args = (-title    => $title,
              -style    => \@stylesheets,
              -encoding => $self->tr('CHARSET'),
	      -script   => \@scripts,
	     );
  push @args,(-head=>$self->setting('head'))    if $self->setting('head');
  push @args,(-lang=>($self->language_code)[0]) if $self->language_code;
  push @args,(-onLoad=>'initialize_page()');

  return start_html(@args);
}

sub render_balloon_settings {
    my $self   = shift;
    my $source = $self->data_source;

    my $default_style   = $source->setting('balloon style') || 'GBubble';;
    my $custom_balloons = $source->setting('custom balloons') || "";
    my $balloon_images  = $self->globals->balloon_url() || '/gbrowse/images/balloons';
    my %config_values   = $custom_balloons =~ /\[([^\]]+)\]([^\[]+)/g;

    # default image path is for the default balloon set
    my $default_images = "$balloon_images/$default_style";

    # These are the four configured popup tooltip styles
    # GBubble is the global default
    # each type can be called using the [name] syntax
    my $balloon_settings .= <<END;
// Original GBrowse popup balloon style
var GBubble = new Balloon;
BalloonConfig(GBubble,'GBubble');
GBubble.images = "$balloon_images/GBubble";

// A simpler popup balloon style
var GPlain = new Balloon;
BalloonConfig(GPlain,'GPlain');
GPlain.images = "$balloon_images/GPlain";

// Like GBubble but fades in
var GFade = new Balloon;
BalloonConfig(GFade,'GFade');
GFade.images = "$balloon_images/GBubble";

// A formatted box
// Note: Box is a subclass of Balloon
var GBox = new Box;
BalloonConfig(GBox,'GBox');
GBox.images = "$balloon_images/GBox";
END
;
    							   
    # handle any custom balloons/config sets
    # two args that are interpreted here and not passed
    # to the JavaScript:
    #
    # class = Balloon (could also be Box)
    # config set = GPlain (GBubble is the default)
    for my $balloon ( keys %config_values ) {
        my %config = $config_values{$balloon} =~ /(\w+)\s*=\s*(\S+)/g;
        
        # which balloon configuration set to use?
	my $bstyle = $config{'config set'} || $default_style;
	delete $config{'config set'};

        # which class to use (may be Box or Balloon)
        my $bclass = $config{'class'}      || 'Balloon';
	delete $config{'class'};
   
        # This creates a Ballon (or Box) object and loads the
        # specified configuration set.
        $balloon_settings .= "\nvar $balloon = new $bclass;\nBalloonConfig($balloon,'$bstyle')\n";

	# Image path must be specified
	$config{images} ||= $default_images;

        for my $option ( keys %config ) {
            my $value
                = $config{$option} =~ /^[\d.-]+$/
                ? $config{$option}
                : "'$config{$option}'";
            $balloon_settings .= "$balloon.$option = $value;\n";
        }
    }

    $balloon_settings =~ s/^/  /gm;
    return "\n<script type=\"text/javascript\">\n$balloon_settings\n</script>\n";
}

sub render_select_menus {  # for popup balloons
    my $self = shift;
    my $html = '';
    $html .= $self->_render_select_menu($_)
	foreach (qw(DETAIL OVERVIEW REGION));
    return $html;
}

sub _render_select_menu {
    my $self = shift;
    my $view = shift || 'DETAIL';
    my $config_label = uc($view).' SELECT MENU';

    # HTML for the custom menu is required
    my $menu_html =  $self->setting($config_label => 'HTML') 
	          || $self->setting($config_label => 'html') 
                  || return '';

    # should not be visible
    my %style = (display => 'none');

    # optional style attributes
    for my $att (qw/width font background background-color border/) {
	my $val = $self->setting($config_label => $att) || next;
	$style{$att} = $val;
    } 
    $style{width} .= 'px';
    my $style = join('; ', map {"$_:$style{$_}"} keys %style);

    # clean up the HTML just a bit
    $menu_html =~ s/\</\n\</g;

    return div( { -style => $style, 
		  -id    => lc($view).'SelectMenu' }, 
		$menu_html );
}

sub render_title {
    my $self  = shift;
    my $title = shift;
    return h1({-id=>'page_title'},$title),
}

sub render_instructions {
  my $self = shift;
  my $settings = $self->session->page_settings;

  my $svg_link     = GD::SVG::Image->can('new') ?
    a({-href=>'?make_image=GD::SVG',-target=>'_blank'},'['.$self->tr('SVG_LINK').']'):'';
  my $reset_link   = a({-href=>"?reset=1",-class=>'reset_button'},'['.$self->tr('RESET').']');
  my $help_link    = a({-href=>$self->general_help(),-target=>'help'},'['.$self->tr('Help').']');
  my $plugin_link  = $self->plugin_links($self->plugins);
  my $oligo        = $self->plugins->plugin('OligoFinder') ? ', oligonucleotide (15 bp minimum)' : '';
  my $rand         = substr(md5_hex(rand),0,5);

  # standard status bar
  my $html =  ''; 

  $html .= table({-border=>0, -width=>'100%',-cellspacing=>0,-class=>'searchtitle'},
		   TR(
		      td({-align=>'left', -colspan=>2},
			 $self->toggle('Instructions',
				       br(),
				       $self->setting('search_instructions') ||
				       $self->tr('SEARCH_INSTRUCTIONS',$oligo),
				       $self->setting('navigation_instructions') ||
				       $self->tr('NAVIGATION_INSTRUCTIONS'),
				       br(),
				       $self->examples()
				      )
			),
		     ),
		   TR(
		      th({-align=>'left', -colspan=>2,-class=>'linkmenu'},
			 $settings->{name} || $settings->{ref} ?
			 (
			  a({-href=>"?rand=$rand;head=".((!$settings->{head})||0)},
			    '['.$self->tr($settings->{head} ? 'HIDE_HEADER' : 'SHOW_HEADER').']'),
			  a({-href=>'?bookmark=1'},'['.$self->tr('BOOKMARK').']'),
              a({-href        => '#',
                 -onMouseDown => "GPlain.showTooltip(event,'url:?share_track=all')"},
                '[' . ($self->tr('SHARE_ALL') || "Share These Tracks" ) .']'),
			  a({-href=>'?make_image=GD',-target=>'_blank'},'['.$self->tr('IMAGE_LINK').']'),
			  $plugin_link,
			  $svg_link,
			 ) : (),
			 $help_link,
			 $reset_link
			),
		     )
		  );
  return $html;
}

# This surrounds the track table with a toggle
sub render_toggle_track_table {
  my $self     = shift;
  return $self->toggle('Tracks', $self->render_track_table());
}

# this draws the various config options
  # This subroutine is invoked to draw the checkbox group underneath the main display.
# It creates a hyperlinked set of feature names.
sub render_track_table {
  my $self     = shift;
  my $settings = $self->state;
  my $source   = $self->data_source;

  # tracks beginning with "_" are special, and should not appear in the
  # track table.
  my @labels     = grep {!/^_/} ($source->detail_tracks,
				 $source->overview_tracks,
				 $source->plugin_tracks,
				 $source->regionview_tracks,
				 $self->uploaded_sources->files,
				 $self->remote_sources->sources,
  );
  my %labels     = map {$_ => $self->label2key($_)}              @labels;
  my @defaults   = grep {$settings->{features}{$_}{visible}  }   @labels;

  # Sort the tracks into categories:
  # Overview tracks
  # Region tracks
  # Regular tracks (which may be further categorized by user)
  # Plugin tracks
  # External tracks
  my %track_groups;
  foreach (@labels) {
    my $category = $self->categorize_track($_);
    push @{$track_groups{$category}},$_;
  }

  autoEscape(0);

  my %exclude = map {$_=>1} map {$self->tr($_)} qw(OVERVIEW REGION ANALYSIS EXTERNAL);

  my @user_keys = grep {!$exclude{$_}} sort keys %track_groups;

  my $all_on  = $self->tr('ALL_ON');
  my $all_off = $self->tr('ALL_OFF');

  my (%seenit,%section_contents);

  my @categories = ($self->tr('OVERVIEW'),
		    $self->tr('REGION'),
		    @user_keys,
		    $self->tr('ANALYSIS'),
		    $source->section_setting('upload_tracks') eq 'off' 
		    ? () : ($self->tr('EXTERNAL')),
      );


  my @titles; # for sorting

  foreach my $category (@categories) {
    next if $seenit{$category}++;
    my $table;
    my $id = "${category}_section";
    my $category_title   = (split m/:/,$category)[-1];

    if ($category eq $self->tr('REGION') 
	&& !$self->setting('region segment')) {
     next;
    }

    elsif  (exists $track_groups{$category}) {
      my @track_labels = @{$track_groups{$category}};

      $settings->{sk} ||= 'sorted'; # get rid of annoying warning

      @track_labels = sort {lc ($labels{$a}) cmp lc ($labels{$b})} @track_labels
        if ($settings->{sk} eq "sorted");

      my @checkboxes = checkbox_group(-name       => 'label',
				      -values     => \@track_labels,
				      -labels     => \%labels,
				      -defaults   => \@defaults,
				      -onClick    => "gbTurnOff('$id');gbToggleTrack(this)",
				      -override   => 1,
				     );
      $table = $self->tableize(\@checkboxes);
      my $visible = exists $settings->{section_visible}{$id} ? $settings->{section_visible}{$id} : 1;

      my ($control,$section)=$self->toggle_section({on=>$visible,nodiv => 1},
						   $id,
						   b(ucfirst $category_title),
						   div({-style=>'padding-left:1em'},
						       span({-id=>$id},$table))
						  );
      $control .= '&nbsp;'.i({-class=>'nojs'},
			     checkbox(-id=>"${id}_a",-name=>"${id}_a",
				      -label=>$all_on,-onClick=>"gbCheck(this,1)"),
			     checkbox(-id=>"${id}_n",-name=>"${id}_n",
				      -label=>$all_off,-onClick=>"gbCheck(this,0)")
			    ).br()   if exists $track_groups{$category};
      $section_contents{$category} = div($control.$section);
    }

    else {
      next;
    }

  }

  autoEscape(1);
  my $slice_and_dice = $self->indent_categories(\%section_contents,\@categories);
  return join( "\n",
		      start_form(-name=>'trackform',
				 -id=>'trackform'),
		      div({-class=>'searchbody',-style=>'padding-left:1em'},$slice_and_dice),
		      end_form
		     );
}

sub indent_categories {
    my $self = shift;
    my ($contents,$categories) = @_;

    my $category_hash = {};

    for my $category (@$categories) {
	my $cont   = $contents->{$category} || '';
	my @parts  = split m/:/,$category;

	my $i      = $category_hash;

	# we need to add phony __next__ and __contents__ keys to avoid
	# the case in which the track sections are placed at different
	# levels of the tree, for instance 
	# "category=level1:level2" and "category=level1"
	for my $index (0..$#parts) {
	    $i = $i->{__next__}{$parts[$index]} ||= {};
	    $i->{__contents__}                    = $cont 
		                                    if $index == $#parts;
	}
    }
    my $i               = 1;
    my %sort_order      = map {$_=>$i++} map {split m/:/} @$categories;
    my $nested_sections =  $self->nest_toggles($category_hash,\%sort_order);
}

# this turns the nested category/subcategory hashes into a prettily indented
# tracks table
sub nest_toggles {
    my $self         = shift;
    my ($hash,$sort) = @_;
    my $settings = $self->state;

    my $result = '';
    for my $key (sort { 
	           $sort->{$a}<=>$sort->{$b} || $a cmp $b
		      }  keys %$hash) {
	if ($key eq '__contents__') {
	    $result .= $hash->{$key}."\n";
	} elsif ($key eq '__next__') {
	    $result .= $self->nest_toggles($hash->{$key},$sort);
	} elsif ($hash->{$key}{__next__}) {
	    my $id =  "category-${key}";
	    $settings->{section_visible}{$id} = 1 unless exists $settings->{section_visible}{$id};
 	    $result .= $self->toggle_section({on=>$settings->{section_visible}{$id}},
					     $id,
					     b($key),
					     div({-style=>'margin-left:1.5em;margin-right:1em'},
						 $self->nest_toggles($hash->{$key},$sort)));
	} else {
	    $result .= $self->nest_toggles($hash->{$key},$sort);
	}
    }
    return $result;
}

sub render_multiple_choices {
    my $self     = shift;
    my $features = shift;
    my $terms2hilite = shift;

    my $karyotype = Bio::Graphics::Karyotype->new(source   => $self->data_source,
						  language => $self->language);
    $karyotype->add_hits($features);
    return $karyotype->to_html($terms2hilite);
}

sub render_global_config {
    my $self     = shift;
    my $settings = $self->state;

    my @widths = split /\s+/, $self->setting('image widths');
    @widths = ( 640, 800, 1024 ) unless @widths;
    my @key_positions = qw(between bottom);
    push @key_positions, qw(left right)
        if Bio::Graphics::Panel->can('auto_pad');

    my $feature_highlights = $settings->{h_feat}
        ? join ' ',
        map {"$_\@$settings->{h_feat}{$_}"} keys %{ $settings->{h_feat} }
        : '';

    my $region_highlights = $settings->{h_region}
        ? join ' ', @{ $settings->{h_region} }
        : '';

    my $content
        = start_form( -name => 'display_settings', -id => 'display_settings' )
        . table(
        { -class => 'searchbody', -border => 0, -width => '100%' },
        TR( { -class => 'searchtitle' },
            td( b(  checkbox(
                        -name     => 'grid',
                        -label    => $self->tr('SHOW_GRID'),
                        -override => 1,
                        -checked  => $settings->{grid} || 0,
			-onChange => 'Controller.set_display_option(this.name,this.checked ? 1 : 0)', 
                    )
                )
            ),
            td( b( $self->tr('Image_width') ),
                br,
                radio_group(
                    -name     => 'width',
                    -values   => \@widths,
                    -default  => $settings->{width},
                    -override => 1,
		    -onChange => 'Controller.set_display_option(this.name,this.value)', 
                ),
            ),
            td( span(
                    { -title => $self->tr('FEATURES_TO_HIGHLIGHT_HINT') },
                    b( $self->tr('FEATURES_TO_HIGHLIGHT') ),
                    br,
                    textfield(
                        -name     => 'h_feat',
                        -value    => $feature_highlights,
                        -size     => 50,
                        -override => 1,
		        -onChange => 'Controller.set_display_option(this.name,this.value)', 
                    ),
                ),
            ),
        ),
        TR( { -class => 'searchtitle' },
            td( $self->data_source->cache_time
                ? ( b(  checkbox(
                            -name     => 'cache',
                            -label    => $self->tr('CACHE_TRACKS'),
                            -override => 1,
                            -checked  => $settings->{cache},
                            -onChange => 'Controller.set_display_option(this.name,this.checked?1:0)'
                        )
                    )
                    )
                : ()
            ),
            td( b( $self->tr("TRACK_NAMES") ),
                br,
                radio_group(
                    -name   => "sk",
                    -values => [ "sorted", "unsorted" ],
                    -labels => {
                        sorted   => $self->tr("ALPHABETIC"),
                        unsorted => $self->tr("VARYING")
                    },
                    -default  => $settings->{sk},
                    -override => 1
                ),
            ),

            td( span(
                    { -title => $self->tr('REGIONS_TO_HIGHLIGHT_HINT') },
                    b( $self->tr('REGIONS_TO_HIGHLIGHT') ),
                    br,
                    textfield(
                        -name     => 'h_region',
                        -value    => $region_highlights,
                        -size     => 50,
                        -override => 1,
		        -onChange    => 'Controller.set_display_option(this.name,this.value)', 
                    ),
                ),
            ),
        ),
        TR( { -class => 'searchtitle' },
            td( { -align => 'left' },
                b(  checkbox(
                        -name     => 'show_tooltips',
                        -label    => $self->tr('SHOW_TOOLTIPS'),
                        -override => 1,
                        -checked  => $settings->{show_tooltips},
                        -onChange => 'Controller.set_display_option(this.name,this.checked?1:0)'
                    ),
                )
            ),
            td( { -id => 'ks_label', },
                b( $self->tr('KEY_POSITION') ),
                br,
                radio_group(
                    -name   => 'ks',
                    -values => \@key_positions,
                    -labels => {
                        between => $self->tr('BETWEEN'),
                        bottom  => $self->tr('BENEATH'),
                        left    => $self->tr('LEFT'),
                        right   => $self->tr('RIGHT'),
                    },
                    -default  => $settings->{ks},
                    -override => 1,
                    -id       => 'key positions',
                )
            ),
            td( $self->setting('region segment')
                ? ( b( $self->tr('Region_size') ),
                    br,
                    textfield(
                        -name     => 'region_size',
                        -default  => $settings->{region_size},
                        -override => 1,
                        -size     => 20,
                        -onChange   => 'Controller.set_display_option(this.name,this.value)',
                    ),

                    )
                : (),
            ),
        ),
        TR( { -class => 'searchtitle' },
            td( {   -colspan => 3,
                    -align   => 'right'
                },
                b( submit( -name => $self->tr('Update_settings') ) )
            )
        )
        ) . end_form();

    return $self->toggle( 'Display_settings', $content );
}

# This surrounds the external table with a toggle
sub render_toggle_external_table {
  my $self     = shift;
  return $self->toggle('UPLOAD_TRACKS', $self->render_external_table());
}

sub render_external_table {
    my $self = shift;
    my $feature_files = shift;

    my $state = $self->state;
    my $content 
        = div( { -id => "external_utility_div" }, '' )
        . start_form( -name => 'externalform', -id => 'externalform' )
        . $self->upload_table
        . $self->das_table
        . end_form();
    return $content;
}

sub upload_table {
  my $self      = shift;
  my $settings  = $self->state;

  # start the table.
  my $cTable = start_table({-border=>0,-width=>'100%',-id=>'upload_table',})
    . TR(
	 th({-class=>'uploadtitle', -colspan=>4, -align=>'left'},
	    $self->tr('Upload_title').':',
	    a({-href=>$self->annotation_help(),-target=>'_new'},'['.$self->tr('HELP').']'))
	);

  $cTable .= TR({-class=>'uploadbody', -name=>'something', -id=>'something'},
		th({-width=>'20%',-align=>'right'},$self->tr('Upload_File')),
		td({-colspan=>3},
		   filefield(-size=>80,-name=>'upload_annotations'),
		   '&nbsp;',
		   submit(-name=>$self->tr('Upload')),
		   '&nbsp;',
            button(
              -value   => $self->tr('New'),
              -onClick => 'Controller.edit_new_file();'
            ),
		  )
	       );

  # now add existing files
  my $uploaded_sources = $self->uploaded_sources();
  for my $file ($uploaded_sources->files) {
    $cTable .=  $self->upload_file_rows($file);
  }

  # end the table.
  $cTable .= end_table;
  return a({-name=>"upload"},$cTable);
}

sub upload_file_rows {
    my $self             = shift;
    my $file             = shift;

    my $uploaded_sources = $self->uploaded_sources();
    ( my $name = $file ) =~ s/^file://;
    $name = escape($name);

    my $return_html = '';
    my $download    = escape( $self->tr('Download_file') );
    my $link        = a( { -href => "?$download=$file" }, "[$name]" );

    my @info = $self->get_uploaded_file_info( $self->track_visible($file)
            && $uploaded_sources->feature_file($file) );

    my $escaped_file = CGI::escape($file);
    $return_html .= TR(
        { -class => 'uploadbody' },
        th( { -width => '20%', -align => 'right' }, $link ),
        td( { -colspan => 3 },
            button(
                -value   => $self->tr('edit'),
                -onClick => 'Controller.edit_upload("' . $escaped_file . '");'
                )
                . '&nbsp;'
                . submit(
                -name  => "modify.$escaped_file",
                -value => $self->tr('Download_file')
                )
                . '&nbsp;'
                . button(
                -name    => 'delete_button',
                -value   => $self->tr('Delete'),
                -onClick => 'Controller.delete_upload_file("' . $file . '");'
                )),
    );
    $return_html .= TR( { -class => 'uploadbody' },
        td('&nbsp;'), td( { -colspan => 3 }, @info ) );
    return $return_html;
}

sub get_uploaded_file_info {
    my $self         = shift;
    my $feature_file = shift or return i("Display off");

    warn "get_uploaded_file_info(): feature_file = $feature_file" if DEBUG;

    my $modified  = localtime($feature_file->mtime);
    my @refs      = sort($feature_file->features)
	unless $feature_file->name =~ m!/das/!;

    my ($landmarks,@landmarks,@links);

    if (@refs > $self->data_source->too_many_landmarks) {
	$landmarks = b($self->tr('Too_many_landmarks',scalar @refs));
    } else {
	@links = map {$self->segment2link($_,$_->display_name)} @refs;
	$landmarks = $self->tableize(\@links);
    }
    warn "get_uploaded_file_info(): modified = $modified, landmarks = $landmarks" if DEBUG;
    return i($self->tr('File_info',$modified),$landmarks||'');
}


sub segment2link {
    my $self = shift;

    my ($segment,$label) = @_;
    
    my $source = $self->data_source;
    return  a({-href=>"?name=$segment"},$segment) unless ref $segment;

    my ($start,$stop) = ($segment->start,$segment->end);
    my $ref = $segment->seq_id;
    my $bp = $stop - $start;
    my $s  = $self->commas($start) || '';
    my $e  = $self->commas($stop)  || '';
    $label ||= "$ref:$s..$e";
    $ref||='';  # get rid of uninit warnings
    return a({-href=>"?ref=$ref;start=$start;stop=$stop"},$label);
}

# URLs for external annotations
sub das_table {
  my $self          = shift;

  my $settings      = $self->state;
  my $feature_files = $self->external_data;

  my (@rows);

  my ($preset_labels,$preset_urls) = $self->get_external_presets($settings);  # (arrayref,arrayref)
  my $presets = '&nbsp;';
  if ($preset_labels && @$preset_labels) {  # defined AND non-empty
    my %presets;
    @presets{@$preset_urls} = @$preset_labels;
    unshift @$preset_urls,'';
    $presets{''} = $self->tr('PRESETS');
    $presets = popup_menu(-name   => 'eurl',
			  -values => $preset_urls,
			  -labels => \%presets,
			  -override => 1,
			  -default  => '',
			  -onChange => 'document.externalform.submit()'
			 );
  }

  local $^W = 0;
  if (my $segment = $self->segment) {

      my $remote_sources = $self->remote_sources();
      for my $url ($remote_sources->sources) {

	  my $f = $remote_sources->transform_url($url,$segment);

	  next unless $url =~ /^(ftp|http):/ && $feature_files->{$url};
	  my $escaped_url = CGI::escape($url);
          my $ulabel = url_label($url);
          $ulabel = '' unless $ulabel ne $url;
          push @rows,th({-align=>'right',-valign=>'top',-width=>'20%'},"$ulabel&nbsp;&nbsp;").
	      td(textfield(-name=>'eurl',-size=>80,-value=>$url,-override=>1),
         button(
            -name    => 'delete_button',
            -value   => $self->tr('Delete'),
            -onClick => 'Controller.delete_upload_file("' . $url . '");'
         ),
		 br,
		 a({-href=>$f,-target=>'help'},'['.$self->tr('Download').']'),
		 $self->get_uploaded_file_info($self->track_visible($url) && $feature_files->{$url})
	      );
      }
  }

  push @rows,
    th({-align=>'right',-width=>'20%'},
		$self->tr('Remote_url')).
    td(textfield(-name=>'eurl',-id=>'eurl',-size=>80,-value=>'',-override=>1),
       $presets,
       button(
         -name    => 'update_url_button',
         -value   => $self->tr('Update_urls'),
         -onClick => 'Controller.new_remote_track($("eurl").value);',
       ),
    );

  return table({-border=>0,-width=>'100%'},
	       TR(
		  th({-class=>'uploadtitle',-align=>'left',-colspan=>2},
		     $self->tr('Remote_title').':',
		     a({-href=>$self->annotation_help().'#remote',-target=>'help'},'['.$self->tr('Help').']'))),
	       TR({-class=>'uploadbody'},\@rows),
	      );
}

sub tableize {
  my $self  = shift;
  my $array = shift;
  return unless @$array;

  my $columns = $self->data_source->global_setting('config table columns') || 3;
  my $rows    = int( @$array/$columns + 0.99 );

  my $cwidth = 100/$columns . '%';

  my $html = start_table({-border=>0,-width=>'100%'});
  for (my $row=0;$row<$rows;$row++) {
    # do table headers
    $html .= qq(<tr class="searchtitle">);
    for (my $column=0;$column<$columns;$column++) {
      $html .= td({-width=>$cwidth},$array->[$column*$rows + $row] || '&nbsp;');
    }
    $html .= "</tr>\n";
  }
  $html .= end_table();
}

sub edit_uploaded_file {
    my $self = shift;
    my ($file) = @_;

    my $uploaded_sources = $self->uploaded_sources();

    my $return_str = '';
    $return_str .= h1( { -align => 'center' }, "Editing $file" );
    $return_str .= start_form(
        -name => 'edit_upload_form',
        -id   => 'edit_upload_form',
    );

    my $data = '';
    if ( $uploaded_sources->url2path($file) ) {
        my $fh = $uploaded_sources->open_file($file) or return;
        $data = join '', expand(<$fh>);
    }

    my $buttons_str = reset( $self->tr('Undo') ) 
        . '&nbsp;'
        . button(
        -name    => 'cancel_button',
        -value   => $self->tr('CANCEL'),
        -onClick => 'Controller.wipe_div("external_utility_div");'
        )
        . '&nbsp;'
        . button(
        -name    => 'accept_button',
        -value   => $self->tr('ACCEPT_RETURN'),
        -onClick => 'Controller.commit_file_edit("' . $file . '");'
        );

    $return_str .= table(
        { -width => '100%' },
        TR( { -class => 'searchbody' },
            td( $self->tr('Edit_instructions') ),
        ),
        TR( { -class => 'searchbody' },
            td( a(  { -href => "?help=annotation#format", -target => 'help' },
                    b( '[' . $self->tr('Help_format') . ']' )
                )
            ),
        ),
        TR( { -class => 'searchtitle' }, th( $self->tr('Edit_title') ) ),
        TR( th($buttons_str) ),
        TR( { -class => 'searchbody' },
            td( { -align => 'center' },
                pre(textarea(
                        -name  => 'a_data',
                        -value => $data,
                        -rows  => ANNOTATION_EDIT_ROWS,
                        -cols  => ANNOTATION_EDIT_COLS,
                        -wrap  => 'off',
                        -style => "white-space : pre"
                    )
                )
            )
        ),
        TR( { -class => 'searchtitle' }, th($buttons_str) )
    );
    $return_str .= hidden( -name => 'edited file', -value => $file );
    $return_str .= end_form();
    $return_str .= $self->render_bottom();
    return $return_str;
}

#### generate the fragment of HTML for printing out the examples
sub examples {
  my $self = shift;
  my $examples = $self->setting('examples') or return;
  my @examples = shellwords($examples);
  return unless @examples;
  my @urls = map { a({-href=>"?name=".escape($_)},$_) } @examples;
  return b($self->tr('Examples')).': '.join(', ',@urls).". ";
}

######################### code for the search box and navigation bar ###################
sub plugin_menu {
  my $self = shift;
  my $settings = $self->state;
  my $plugins  = $self->plugins;

  my $labels = $plugins->menu_labels;

  my @plugins = sort {$labels->{$a} cmp $labels->{$b}} keys %$labels;

  # Add plugin types as attribute so the javascript controller knows what to do
  # with each plug-in
  my %attributes = map {
    $_ => {
      'plugin_type' => $plugins->plugin($_)->type(),
      'track_name'  => "plugin:".$plugins->plugin($_)->name(),
      }
    }
    keys %$labels;

  return unless @plugins;

  return join(
    '',
    popup_menu(
      -name       => 'plugin',
      -values     => \@plugins,
      -labels     => $labels,
      -attributes => \%attributes,
      -default    => $settings->{plugin},
    ),
    '&nbsp;',
    button(
      -name     => 'plugin_action',
      -value    => $self->tr('Configure'),
      -onClick => 'Controller.configure_plugin("plugin_configure_div");'
    ),
    '&nbsp;',
    button(
        -name    => 'plugin_action',
        -value   => $self->tr('Go'),
        -onClick => 'var select_box = document.pluginform.plugin;'
            . q{var plugin_type = select_box.options[select_box.selectedIndex].attributes.getNamedItem('plugin_type').value;}
            . 'Controller.plugin_go('
            . 'document.pluginform.plugin.value,'
            . 'plugin_type,' . '"'
            . $self->tr('Go') . '",'
            . '"form"' . ');',
        ),
  );
}


# plugin configuration form for balloon content
sub plugin_configuration_form {
    my $self = shift;
    my $plugin = shift;

    my $plugin_type = $plugin->type;
    my $plugin_name = $plugin->name;

    print CGI::header('text/html');
    print start_html(),
              start_form(
		  -name     => 'configure_plugin',
		  -id       => 'configure_plugin',
		  ),
	  submit(
            -name    => 'plugin_button',
            -value   => $self->tr('Configure_plugin'),
          ),
          $plugin->configure_form(),
	  submit(
            -name    => 'plugin_button',
            -value   => $self->tr('Configure_plugin'),
          ),
          end_form(),
          end_html();
}

# Wrap the plugin configuration html into a form and tie it into the controller 
sub wrap_plugin_configuration {
    my $self        = shift;
    my $plugin_base = shift or return '';
    my $plugin      = shift or return '';
    my $config_html = $plugin->configure_form();

    my $return_html = start_form(
        -name     => 'configure_plugin',
        -id       => 'configure_plugin',
        -onSubmit => 'return false;',
    );
    if ($config_html) {
        my $plugin_type = $plugin->type;
        my $plugin_name = $plugin->name;
        my @buttons;

        # Cancel Button
        push @buttons,
            button(
            -name    => 'plugin_button',
            -value   => $self->tr('CANCEL'),
            -onClick => 'Controller.wipe_div("plugin_configure_div");'
            );

        # Configure Button

        # Supplies the track name and the track div which I'm not really
        # happy with
        push @buttons,
            button(
            -name    => 'plugin_button',
            -value   => $self->tr('Configure_plugin'),
            -onClick => 'Controller.reconfigure_plugin("'
                . $self->tr('Configure_plugin') . '", "'
                . "plugin:$plugin_name"
                . '","plugin_configure_div","'
                . $plugin_type . '");'
            );
        if ( $plugin_type eq 'finder' ) {
            push @buttons,
                button(
                -name    => 'plugin_button',
                -value   => $self->tr('Find'),
                -onClick => 'alert("Find not yet implemented")',
                );
        }
        elsif ( $plugin_type eq 'dumper' ) {
            push @buttons,
                button(
                -name    => 'plugin_button',
                -value   => $self->tr('Go'),
                -onClick => 'Controller.plugin_go("'
                    . $plugin_base . '","'
                    . $plugin_type . '","'
                    . $self->tr('Go') . '","'
                    . 'config' . '")',
                );
        }

        # Start adding to the html
        $return_html .= h1(
              $plugin_type eq 'finder'
            ? $self->tr('Find')
            : $self->tr('Configure'),
            $plugin_name
        );
        my $button_html = join( '&nbsp;',
            @buttons[ 0 .. @buttons - 2 ],
            b( $buttons[-1] ),
        );

        $return_html .= join '', $button_html, $config_html, p(),
            $button_html,;
    }
    else {
        $return_html .= join '', p( $self->tr('Boring_plugin') ),
            b(
            button(
                -name    => 'plugin_button',
                -value   => $self->tr('CANCEL'),
                -onClick => 'Controller.wipe_div("plugin_configure_div");'
            )
            );
    }
    $return_html .= end_form();

    return $return_html;

}

sub wrap_track_in_track_div {
    my $self       = shift;
    my %args       = @_;
    my $track_name = $args{'track_name'};
    my $track_html = $args{'track_html'};

    # track_type Used in register_track() javascript method
    my $track_type = $args{'track_type'} || 'standard';

    my $section = get_section_from_label($track_name);
    my $class = $track_name =~ /scale/i ? 'scale' : 'track';

    return div(
        {   -id    => "track_" . $track_name,
            -class => $class,
        },
        $track_html
        )
        . qq[<script type="text/javascript" language="JavaScript">Controller.register_track("]
        . $track_name . q[", "]
        . $track_type . q[", "]
        . $section
        . q[");</script>];
}

sub do_plugin_header {
    my $self   = shift;
    my $plugin = shift;
    my $cookie = shift;
    my ( $mime_type, $attachment ) = $plugin->mime_type;
    print header(
        -cookie  => $cookie,
        -type    => $mime_type,
        -charset => $self->tr('CHARSET'),
        $attachment ? ( -attachment => $attachment ) : (),
    );
}

sub slidertable {
  my $self = shift;
  my $segment = shift;

  my $whole_segment = $self->whole_segment;
  my $buttonsDir    = $self->globals->button_url;

  my $span       = $segment->length;
  my $half_title = $self->unit_label(int $span/2);
  my $full_title = $self->unit_label($span);
  my $half       = int $span/2;
  my $full       = $span;
  my $fine_zoom  = $self->get_zoomincrement();

  my @lines =
    (image_button(-src     => "$buttonsDir/green_l2.gif",-name=>"left $full",
		  -title   => "left $full_title",
		  -onClick => "Controller.update_coordinates(this.name)"
     ),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/green_l1.gif",-name=>"left $half",
		  -title=>"left $half_title",
		  -onClick => "Controller.update_coordinates(this.name)"
     ),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/minus.gif",-name=>"zoom out $fine_zoom",
		  -title=>"zoom out $fine_zoom",
		  -onClick => "Controller.update_coordinates(this.name)"
     ),
     '&nbsp;',
     $self->zoomBar($segment,$whole_segment,$buttonsDir),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/plus.gif",-name=>"zoom in $fine_zoom",
		  -title=>"zoom in $fine_zoom",
		  -onClick => "Controller.update_coordinates(this.name)",
     ),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/green_r1.gif",-name=>"right $half",
		  -title=>"right $half_title",
		  -onClick => "Controller.update_coordinates(this.name)"
     ),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/green_r2.gif",-name=>"right $full",
		  -title=>"right $full_title",
		  -onClick => "Controller.update_coordinates(this.name)"
     ),
     '&nbsp;',
    );

  my $str	= join('', @lines);
  return span({-id=>'span'},$str);
}

# this generates the popup zoom menu with the window sizes
sub zoomBar {
  my $self = shift;

  my ($segment,$whole_segment) = @_;

  my $show   = $self->tr('Show');
  my $length = $segment->length;
  my $max    = $whole_segment->length;

  my %seen;
  my @r         = sort {$a<=>$b} $self->data_source->get_ranges();
  my @ranges	= grep {!$seen{$_}++ && $_<=$max} sort {$b<=>$a} $segment->length,@r;

  my %labels    = map {$_=>$show.' '.$self->unit_label($_)} @ranges;
  return popup_menu(-class   => 'searchtitle',
		    -name    => 'span',
		    -values  => \@ranges,
		    -labels  => \%labels,
		    -default => $length,
		    -force   => 1,
		    -onChange => 'Controller.update_coordinates("set span "+this.value)',
		   );
}

sub source_menu {
  my $self = shift;

  my $globals = $self->globals;

  my @sources      = $globals->data_sources;
  my $show_sources = $self->setting('show sources');
  $show_sources    = 1 unless defined $show_sources;   # default to true
  my $sources = $show_sources && @sources > 1;
  return b($self->tr('DATA_SOURCE')).br.
    ( $sources ?
      popup_menu(-name   => 'source',
		 -values => \@sources,
		 -labels => { map {$_ => $globals->data_source_description($_)} @sources},
		 -default => $self->session->source,
		 -onChange => 'this.form.submit()',
		)
	: $globals->data_source_description($self->session->source)
      );
}

# this is the content of the popup balloon that describes the track and gives configuration settings
sub track_config {
    my $self        = shift;
    my $label       = shift;
    my $state       = $self->state();
    my $data_source = $self->data_source();

    eval 'require Bio::Graphics::Browser::OptionPick; 1'
        unless Bio::Graphics::Browser::OptionPick->can('new');

    my $picker = Bio::Graphics::Browser::OptionPick->new($self);

    my $key = $self->label2key($label);

    if ( param('track_defaults') ) {
        $state->{features}{$label}{override_settings} = {};
    }

    my $override = $state->{features}{$label}{override_settings};

    my $return_html = start_html();

    # truncate too-long citations
    my $cit_txt = citation( $data_source, $label, $self->language )
        || $self->tr('NO_CITATION');

    $cit_txt =~ s/(.{512}).+/$1\.\.\./;
    my $citation = h4($key) . p($cit_txt);
    my $height = $data_source->fallback_setting( $label => 'height' ) || 5;
    my $width = $data_source->fallback_setting( $label => 'linewidth' ) || 1;
    my $glyph = $data_source->fallback_setting( $label => 'glyph' ) || 'box';
    my @glyph_select = shellwords(
        $data_source->fallback_setting( $label => 'glyph select' ) );
    @glyph_select
        = qw(arrow anchored_arrow box crossbox dashed_line diamond dna dot dumbbell ellipse
        ex line primers saw_teeth segments span splice_site translation triangle
        two_bolts wave) unless @glyph_select;
    my %glyphs = map { $_ => 1 } ( $glyph, @glyph_select );

    my $url = url( -absolute => 1, -path => 1 );
    my $reset_js = <<END;
new Ajax.Request('$url',
                  { method: 'get',
                    asynchronous: false,
                    parameters: 'configure_track=$label&track_defaults=1',
                    onSuccess: function(t) { document.getElementById('contents').innerHTML=t.responseText },
                    onFailure: function(t) { alert('AJAX Failure! '+t.statusText)}
                  }
                );
END

    my $self_url  = url( -absolute => 1, -path => 1 );
    my $form_name = 'track_config_form';
    my $form      = start_form(
        -name => $form_name,
        -id   => $form_name,
    );

    ### Create the javascript that will serialize the form.
    # I'm not happy about this but the prototype method only seems to be
    # reporting the default values when the form is inside a balloon.
    my $form_serialized_js = join q[+'&'+], map {qq['$_='+escape($_.value)]} (
        "format_option", "glyph",  "bgcolor", "fgcolor",
        "linewidth",     "height", "limit",
    );

    # "show_track" is a special case since it's a checkbox
    # :( This is so ugly.
    my $preserialize_js = "var show_track_checked = 0;"
        . "if(show_track.checked){show_track_checked =1;}";
    $form_serialized_js .= q[+'&'+] . "'show_track='+show_track_checked";

    $form .= table(
        { -border => 0 },
        TR( th( { -align => 'right' }, $self->tr('Show') ),
            td( checkbox(
                    -name     => 'show_track',
                    -value    => $label,
                    -override => 1,
                    -checked  => $state->{features}{$label}{visible},
                    -label    => ''
                )
            ),
        ),
        TR( th( { -align => 'right' }, $self->tr('Packing') ),
            td( popup_menu(
                    -name     => 'format_option',
                    -values   => [ 0 .. 3 ],
                    -override => 1,
                    -default  => $state->{features}{$label}{options},
                    -labels   => {
                        0 => $self->tr('Auto'),
                        1 => $self->tr('Compact'),
                        2 => $self->tr('Expand'),
                        3 => $self->tr('Expand_Label'),
                    }
                )
            )
        ),
        TR( th( { -align => 'right' }, $self->tr('GLYPH') ),
            td( $picker->popup_menu(
                    -name    => 'glyph',
                    -values  => [ sort keys %glyphs ],
                    -default => $glyph,
                    -current => $override->{'glyph'},
                )
            )
        ),
        TR( th( { -align => 'right' }, $self->tr('BACKGROUND_COLOR') ),
            td( $picker->color_pick(
                    'bgcolor',
                    $data_source->fallback_setting( $label => 'bgcolor' ),
                    $override->{'bgcolor'}
                )
            )
        ),
        TR( th( { -align => 'right' }, $self->tr('FG_COLOR') ),
            td( $picker->color_pick(
                    'fgcolor',
                    $data_source->fallback_setting( $label => 'fgcolor' ),
                    $override->{'fgcolor'}
                )
            )
        ),
        TR( th( { -align => 'right' }, $self->tr('LINEWIDTH') ),
            td( $picker->popup_menu(
                    -name    => 'linewidth',
                    -current => $override->{'linewidth'},
                    -default => $width || 1,
                    -values  => [ sort { $a <=> $b } ( $width, 1 .. 5 ) ]
                )
            )
        ),
        TR( th( { -align => 'right' }, $self->tr('HEIGHT') ),
            td( $picker->popup_menu(
                    -name    => 'height',
                    -current => $override->{'height'},
                    -default => $height,
                    -values  => [
                        sort { $a <=> $b }
                            ( $height, map { $_ * 5 } ( 1 .. 20 ) )
                    ],
                )
            )
        ),
        TR( th( { -align => 'right' }, $self->tr('Limit') ),
            td( popup_menu(
                    -name   => 'limit',
                    -values => [ 0, 5, 10, 25, 100 ],
                    -labels   => { 0 => $self->tr('No_limit') },
                    -override => 1,
                    -default => $state->{features}{$label}{limit}
                )
            )
        ),
        TR( td(),
            td( button(
                    -style   => 'background:pink',
                    -name    => $self->tr('Revert'),
                    -onClick => $reset_js
                )
            )
        ),
        TR( td(),
            td( button(
                    -name    => $self->tr('Cancel'),
                    -onClick => 'Balloon.prototype.hideTooltip(1)'
                    )
                    . '&nbsp;'
                    . button(
                    -name => $self->tr('Change'),
                    -onClick =>
                        "$preserialize_js;Controller.reconfigure_track('$label',$form_serialized_js, show_track.checked);",
                    )
            )
        ),
    );
    $form .= end_form();

    $return_html
        .= table( TR( td( { -valign => 'top', -width => '50%' }, [ $citation, $form ] ) ) );
    $return_html .= end_html();
    return $return_html;
}

# this is the content of the popup balloon that describes how to share a track
sub share_track {
    my $self  = shift;
    my $label = shift;

    my $state = $self->state();

    my $description;
    my $labels;
    my @visible
        = grep { $state->{features}{$_}{visible} && !/:(overview|region)$/ }
        @{ $state->{tracks} };

    if ( $label eq 'all' ) {
        $labels = join '+', map { CGI::escape($_) } @visible;
        $description = 'all selected tracks';
    }
    else {
        $description = $self->setting( $label => 'key' ) || $label;
        $labels = $label;
    }

    my $gbgff;
    if ( $label =~ /^(http|ftp):/ ) {    # reexporting and imported track!
        $gbgff = $label;
    }
    else {
        $gbgff = url( -full => 1, -path_info => 1 );
        $gbgff .= "?gbgff=1;q=\$segment;t=$labels";
        $gbgff .= ";id=" . $state->{id} if $labels =~ /file:/;
    }

    my $das_types = join( ';',
        map      { "type=" . CGI::escape($_) }
            grep { length $_ > 0 }
            map  { shellwords( $self->setting( $_ => 'feature' ) ) }
            grep { $self->setting( $_ => 'das category' ) }
            $label eq 'all'
        ? @visible
        : $label );
    my $das = url( -full => 1, -path_info => 1 );
    $das =~ s/gbrowse/das/;
    $das .= "features";
    $das .= "?$das_types";

    my $return_html = start_html();
    $return_html .= h1( $self->tr( 'SHARE', $description ) )
        . p(
        $self->tr(
            $label eq 'all'
            ? 'SHARE_INSTRUCTIONS_ALL_TRACKS'
            : 'SHARE_INSTRUCTIONS_ONE_TRACK'
        )
        )
        . br()
	. b('GBrowse URL: ') 
	. br()
	. p( textfield(
            -style    => 'background-color: wheat',
            -readonly => 1,
            -value    => $gbgff,
            -size     => 56,
            -onFocus  => 'this.select()',
            -onSelect => 'this.select()' )
	);

    if ($das_types) {
        $return_html .= p(
            $self->tr(
                $label eq 'all'
                ? 'SHARE_DAS_INSTRUCTIONS_ALL_TRACKS'
                : 'SHARE_DAS_INSTRUCTIONS_ONE_TRACK'
            )
            )
            . br()
            .b('DAS URL: ') 
	    . br()
	    . p( textfield(
                -style    => 'background-color: wheat',
                -readonly => 1,
                -value    => $das,
                -size     => 56,
                -onFocus  => 'this.select()',
                -onSelect => 'this.select()')
             );
    }
    $return_html .= 
	button(
		 -name    => $self->tr('OK'),
		 -onClick => 'Balloon.prototype.hideTooltip(1)'
		 );

    $return_html .= end_html();
    return $return_html;
}



################### various utilities ###################

sub html_frag {
  my $self = shift;
  my $fragname = shift;
  my $a = $self->data_source->code_setting(general => $fragname);
  return $a->(@_) if ref $a eq 'CODE';
  return $a || '';
}


############################## toggle code ########################
sub toggle {
  my $self = shift;
  my $title = shift;
  my @body  = @_;

  my $page_settings = $self->state;

  my $id    = "\L${title}_panel\E";
  my $label = $self->tr($title)                              or return '';
  my $state = $self->data_source->section_setting($title)    or return '';
  return '' if $state eq 'off';
  my $visible = exists $page_settings->{section_visible}{$id} ? 
    $page_settings->{section_visible}{$id} : $state eq 'open';

  return $self->toggle_section({on=>$visible},
			       $id,
			       b($label),
			       @body);
}

sub toggle_section {
  my $self = shift;
  my %config = ref $_[0] eq 'HASH' ? %{shift()} : ();
  my ($name,$section_title,@section_body) = @_;

  my $visible = $config{on};

  my $buttons = $self->globals->button_url;
  my $plus  = "$buttons/plus.png";
  my $minus = "$buttons/minus.png";

  my $show_ctl = div({-id=>"${name}_show",
		       -class=>'ctl_hidden',
		       -style=>$visible ? 'display:none' : 'display:inline',
		       -onClick=>"visibility('$name',1)"
                     },
		     img({-src=>$plus,-alt=>'+'}).'&nbsp;'.span({-class=>'tctl'},$section_title));
  my $hide_ctl = div({-id=>"${name}_hide",
		       -class=>'ctl_visible',
		       -style=>$visible ? 'display:inline' : 'display:none',
		       -onClick=>"visibility('$name',0)"
                     },
		     img({-src=>$minus,-alt=>'-'}).'&nbsp;'.span({-class=>'tctl'},$section_title));
  my $content  = div({-id    => $name,
		      -style=>$visible ? 'display:inline' : 'display:none',
		      -class => 'el_visible'},
		     @section_body);
  my @result = $config{nodiv} ? ($show_ctl.$hide_ctl,$content) : div(($show_ctl.$hide_ctl,$content));
  return wantarray ? @result : "@result";
}

1;

