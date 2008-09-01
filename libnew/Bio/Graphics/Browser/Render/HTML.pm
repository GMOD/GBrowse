package Bio::Graphics::Browser::Render::HTML;

use strict;
use warnings;
use base 'Bio::Graphics::Browser::Render';
use Bio::Graphics::Browser::Shellwords;
use Bio::Graphics::Karyotype;
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
  return $self->render_html_head($dsn,$title);
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

  my $searchform = join '',(
                start_form(
                    -name => 'searchform',
                    -id   => 'searchform',
                    
                    # Submitting through the Controller sees to have been a bad idea
                    #-onSubmit => q[ 
                    #    Controller.update_coordinates("set segment " + document.searchform.name.value); 
                    #    var return_val = (document.searchform.force_submit.value==1); 
                    #    document.searchform.force_submit.value=0;
                    #    return return_val;
                    #],
                ),
                hidden(-name=>'force_submit',-value=>0),
			    textfield(-name=> 'name',
				      -id  => 'landmark_search_field',
				      -size=> 25,
				      -default=>$settings->{name}),
			    submit(-name=>$self->tr('Search')),
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
			     start_form(-name=>'sourceform',-id=>'sourceform',
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
    foreach qw(buttons.js 
               toggle.js 
               karyotype.js
               balloon.js 
               controller.js 
               rubber.js
               overviewSelect.js
               detailSelect.js
               regionSelect.js
);

  # pick stylesheets;
  my @stylesheets;
  my $titlebar   = $self->is_safari() ? 'css/titlebar-safari.css' : 'css/titlebar-default.css';
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

sub render_title {
    my $self  = shift;
    my $title = shift;
    return h1({-id=>'page_title'},$title),
}

sub render_instructions {
  my $self = shift;
  my $settings = $self->session->page_settings;

  my $svg_link     = GD::SVG::Image->can('new') ?
    a({-href=>$self->svg_link($settings),-target=>'_blank'},'['.$self->tr('SVG_LINK').']'):'';
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
			  a({-href=>$self->bookmark_link($settings)},'['.$self->tr('BOOKMARK').']'),
			  a({-href=>$self->image_link($settings),-target=>'_blank'},'['.$self->tr('IMAGE_LINK').']'),
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
  my @sections;

  my %exclude = map {$_=>1} map {$self->tr($_)} qw(OVERVIEW REGION ANALYSIS EXTERNAL);

  my @user_keys = grep {!$exclude{$_}} sort keys %track_groups;

  my $all_on  = $self->tr('ALL_ON');
  my $all_off = $self->tr('ALL_OFF');

  my %seenit;
  foreach my $category ($self->tr('OVERVIEW'),
			$self->tr('REGION'),
			$self->tr('ANALYSIS'),
			@user_keys,
			$source->section_setting('upload_tracks') eq 'off' 
			   ? () 
			   : ($self->tr('EXTERNAL')),
		       ) {
    next if $seenit{$category}++;
    my $table;
    my $id = "${category}_section";

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
						   b(ucfirst $category),
						   div({-style=>'padding-left:1em'},
						       span({-id=>$id},$table))
						  );
      $control .= '&nbsp;'.i({-class=>'nojs'},
			     checkbox(-id=>"${id}_a",-name=>"${id}_a",
				      -label=>$all_on,-onClick=>"gbCheck(this,1)"),
			     checkbox(-id=>"${id}_n",-name=>"${id}_n",
				      -label=>$all_off,-onClick=>"gbCheck(this,0)")
			    ).br()   if exists $track_groups{$category};
      push @sections,div($control.$section);
    }

    else {
      next;
    }

  }

  autoEscape(1);
  return $self->toggle('Tracks',
		      start_form(-name=>'trackform',
				 -id=>'trackform'),
		      div({-class=>'searchbody',-style=>'padding-left:1em'},@sections),
		      table({-width=>'100%',-class=>"searchbody"},
			    TR(td{-align=>'right'},
			       submit(-name => $self->tr('Set_options')),
			       b(submit(-name => $self->tr('Update'))
				)
			      )
			   ),
		      end_form
		     );
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

  my @widths = split /\s+/,$self->setting('image widths');
  @widths = (640,800,1024) unless @widths;
  my @key_positions   = qw(between bottom);
  push @key_positions,qw(left right) if Bio::Graphics::Panel->can('auto_pad');

  my $feature_highlights = $settings->{h_feat}   ?
    join ' ',map { "$_\@$settings->{h_feat}{$_}"   } keys %{$settings->{h_feat}} : '';

  my $region_highlights  = $settings->{h_region} ?
    join ' ',@{$settings->{h_region}} : '';

  my $content =
    start_form(-name=>'display_settings',-id=>'display_settings').
    table({-class=>'searchbody',-border=>0,-width=>'100%'},
	  TR(
	     td(
		b($self->tr('Image_width')),br,
		radio_group( -name=>'width',
			     -values=>\@widths,
			     -default=>$settings->{width},
			     -override=>1,
			   ),
	       ),
	     $self->setting('region segment') ?
	     (
	      td(b($self->tr('Region_size')),br,
		 textfield(-name=>'region_size',
			   -default=>$settings->{region_size},
			   -override=>1,
			   -size=>20),
		)
	     ) : (),
             td(
                b($self->tr("TRACK_NAMES")),br,
                radio_group( -name=>"sk",
                             -values=>["sorted","unsorted"],
                             -labels=>{sorted   =>$self->tr("ALPHABETIC"),
                                       unsorted =>$self->tr("VARYING")},
                             -default=>$settings->{sk},
                             -override=>1
                           ),
               ),
	     td(
		$self->setting('drag and drop')
                ? '&nbsp;'
		: (b($self->tr('KEY_POSITION')),br,
		   radio_group( -name=>'ks',
				-values=>\@key_positions,
				-labels=>{between=>$self->tr('BETWEEN'),
					  bottom =>$self->tr('BENEATH'),
					  left   =>$self->tr('LEFT'),
					  right  =>$self->tr('RIGHT'),
					 },
				-default=>$settings->{ks},
				-override=>1
			      )
		  ),
	       ),
	    ),
	  TR(
	     td(
		span({-title=>$self->tr('FEATURES_TO_HIGHLIGHT_HINT')},
		     b(
		       $self->tr('FEATURES_TO_HIGHLIGHT')
		      ),br,
		     textfield(-name  => 'h_feat',
			       -value => $feature_highlights,
			       -size  => 50,
			       -override=>1,
			      ),
		    ),
	       ),
	     td(
		span({-title=>$self->tr('REGIONS_TO_HIGHLIGHT_HINT')},
		     b(
		       $self->tr('REGIONS_TO_HIGHLIGHT')
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
			   -label=>$self->tr('SHOW_GRID'),
			   -override=>1,
			   -checked=>$settings->{grid}||0)
		 )
	       ),
	    ),
	  TR(td({-colspan=>4,
		 -align=>'right'},
		b(submit(-name => $self->tr('Update')))))
	 )
    .end_form();
    ;
  return $self->toggle('Display_settings',$content);
}

# This needs to be fleshed out.
sub render_uploads {
    my $self = shift;
    
    my $feature_files = shift;
    my $state = $self->state;
    my $content
        = start_form( -name => 'externalform', -id => 'externalform' )
        . $self->upload_table
        . $self->das_table
        . end_form();
    return $self->toggle( 'UPLOAD_TRACKS', $content );
}

sub upload_table {
  my $self      = shift;
  my $settings  = $self->state;

  # start the table.
  my $cTable = start_table({-border=>0,-width=>'100%'})
    . TR(
	 th({-class=>'uploadtitle', -colspan=>4, -align=>'left'},
	    $self->tr('Upload_title').':',
	    a({-href=>annotation_help(),-target=>'help'},'['.$self->tr('HELP').']'))
	);
  my $uploaded_sources = $self->uploaded_sources();

  # now add existing files
  for my $file ($uploaded_sources->files) {

    (my $name = $file) =~ s/^file://;
    $name = escape($name);

    my $download = escape($self->tr('Download_file'));
    my $link = a({-href=>"?$download=$file"},"[$name]");

    my @info =  $self->get_uploaded_file_info(
	$self->track_visible($file) && $uploaded_sources->feature_file($file));

    my $escaped_file = CGI::escape($file);
    $cTable .=  TR({-class=>'uploadbody'},
		   th({-width=>'20%',-align=>'right'},$link),
		   td({-colspan=>3},
		      submit(-name=>"modify.$escaped_file",-value=>$self->tr('Edit')).'&nbsp;'.
		      submit(-name=>"modify.$escaped_file",-value=>$self->tr('Download_file')).'&nbsp;'.
		      submit(-name=>"modify.$escaped_file",-value=>$self->tr('Delete'))));
    $cTable .= TR({-class=>'uploadbody'},td('&nbsp;'),td({-colspan=>3},@info));
  }

  # end the table.
  $cTable .= TR({-class=>'uploadbody'},
		th({-width=>'20%',-align=>'right'},$self->tr('Upload_File')),
		td({-colspan=>3},
		   filefield(-size=>80,-name=>'upload_annotations'),
		   '&nbsp;',
		   submit(-name=>$self->tr('Upload')),
		   '&nbsp;',
		   submit(-name=>'new_upload',-value=>$self->tr('New')),
		  )
	       );
  $cTable .= end_table;
  return a({-name=>"upload"},$cTable);
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

  my (@rows,$count);

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
	  push @rows,th({-align=>'right',-width=>'20%'},"URL",++$count).
	      td(textfield(-name=>'eurl',-size=>80,-value=>$url,-override=>1),
		 submit(-name=>"modify.$escaped_url",-value=>$self->tr('Delete')),
		 br,
		 a({-href=>$f,-target=>'help'},'['.$self->tr('Download').']'),
		 $self->get_uploaded_file_info($self->track_visible($url) && $feature_files->{$url})
	      );
      }
  }

  push @rows,th({-align=>'right',-width=>'20%'},
		$self->tr('Remote_url')).
		    td(textfield(-name=>'eurl',-size=>80,-value=>'',-override=>1),
		       $presets,
		       submit($self->tr('Update_urls')));

  return table({-border=>0,-width=>'100%'},
	       TR(
		  th({-class=>'uploadtitle',-align=>'left',-colspan=>2},
		     $self->tr('Remote_title').':',
		     a({-href=>annotation_help().'#remote',-target=>'help'},'['.$self->tr('Help').']'))),
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

    print header( -charset => $self->tr('CHARSET') );
    $self->render_top("Editing $file");
    print start_form();
    my $data;
    my $fh = $self->uploaded_sources->open_file($file) or return;
    $data = join '', expand(<$fh>);
    print table(
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
        TR( { -class => 'searchtitle' },
            th( reset( $self->tr('Undo') ) 
                    . '&nbsp;'
                    . submit('Cancel')
                    . '&nbsp;'
                    . b( submit('Submit Changes...') )
            )
        )
    );
    print hidden( -name => 'edited file', -value => $file );
    print end_form();
    $self->render_bottom();
}

###################### help ##############3
sub annotation_help {
  return "?help=annotation";
}

sub general_help {
  return "?help=general";
}

sub bookmark_link {
  my $self     = shift;
  my $settings = shift;

  my $q = new CGI('');
  my @keys = qw(start stop ref width version flip);
  foreach (@keys) {
    $q->param(-name=>$_,-value=>$settings->{$_});
  }

  # handle selected features slightly differently
  my @selected = grep {$settings->{features}{$_}{visible} && !/^(file|ftp|http):/} @{$settings->{tracks}};
  $q->param(-name=>'label',-value=>join('-',@selected));

  # handle external urls
  my @url = grep {/^(ftp|http):/} @{$settings->{tracks}};
  $q->param(-name=>'eurl',-value=>\@url);
  $q->param(-name=>'h_region',-value=>$settings->{h_region}) if $settings->{h_region};
  my @h_feat= map {"$_\@$settings->{h_feat}{$_}"} keys %{$settings->{h_feat}};
  $q->param(-name=>'h_feat',-value=>\@h_feat) if @h_feat;
  $q->param(-name=>'id',-value=>$settings->{id});
  $q->param(-name=>'grid',-value=>$settings->{grid});

  return "?".$q->query_string();
}

# for the subset of plugins that are named in the 'quicklink plugins' option, create
# quick links for them.
sub plugin_links {
  my $self    = shift;
  my $plugins = shift;

  my $quicklink_setting = $self->setting('quicklink plugins') or return '';
  my @plugins           = shellwords($quicklink_setting)      or return '';
  my @result;
  for my $p (@plugins) {
    my $plugin = $plugins->plugin($p) or next;
    my $name   = $plugin->name;
    my $action = "?plugin=$p;plugin_do=".$self->tr('Go');
    push @result,a({-href=>$action},"[$name]");
  }
  return join ' ',@result;
}

sub image_link {
  my $settings = shift;
  return "?help=link_image;flip=".($settings->{flip}||0);
}

sub svg_link {
  my $settings = shift;
  return "?help=svg_image;flip=".($settings->{flip}||0);
}

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

# Wrap the plugin configuration html into a form and tie it into the controller 
sub wrap_plugin_configuration {
    my $self        = shift;
    my $plugin_base = shift or return '';
    my $plugin      = shift or return '';
    my $config_html = $plugin->configure_form();

    my $return_html = start_form(
        -name     => 'configure_plugin',
        -id       => 'configure_plugin',
        -onSubmit => 'alert("here3");return false;',
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
                . "plugin:$plugin_name" . '", "'
                . "track_plugin:$plugin_name"
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
     span({-id=>'span_menu'},$self->zoomBar($segment,$whole_segment,$buttonsDir)),
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
  return $str;
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
		    -id      => 'span',
		    -values  => \@ranges,
		    -labels  => \%labels,
		    -default => $length,
		    -force   => 1,
		    -onChange => 'Controller.update_coordinates("set span "+this.value)',
		   );
}

sub source_menu {
  my $self = shift;
  my $settings = $self->state;

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

