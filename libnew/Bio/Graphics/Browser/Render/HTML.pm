package Bio::Graphics::Browser::Render::HTML;

use strict;
use warnings;
use base 'Bio::Graphics::Browser::Render';
use Digest::MD5 'md5_hex';
use Carp 'croak';
use CGI qw(:standard escape);
eval { use GD::SVG };

use constant JS    => '/gbrowse/js';

sub render_top {
  my $self = shift;
  my $features = shift;

  my $dsn = $self->data_source;

  my $description = $dsn->description;
  my $feature     = $features->[0] if $features && @$features == 1;
  my $title;

  $title = $features ? "$description: ".$feature->seq_id.":".$feature->start.'..'.$feature->end
    : $description;


  $self->render_html_head($dsn,$title);
  print h1($title);
  $self->render_instructions();
}

sub render_bottom {
  my $self = shift;
  my $features = shift; # not used
  print hr(),
    end_html();
}

sub render_navbar {
  my $self    = shift;
  my $segment = shift;

  my $settings = $self->state;

  my $searchform = join '',(
			    start_form(-name=>'searchform'),
			    textfield(-name=>'name',
				      -size=>25,
				      -default=>$settings->{name}),
			    submit(-name=>$self->tr('Search')),
			    end_form
			    );

  my $search = $self->setting('no search')
    ? '' : b($self->tr('Landmark')).':'.br().$searchform;

  my $plugin_form = join '',(
			     start_form(-name=>'pluginform'),
			     $self->plugin_menu(),
			     end_form);

  my $source_form = join '',(
			     start_form(-name=>'sourceform'),
			     $self->source_menu(),
			     end_form
			    );

  my $sliderform = '';
  if ($segment) {
    $sliderform =
      join '',(
	       start_form(-name=>'sliderform'),
	       b($self->tr('Scroll').': '),
	       $self->slidertable($segment),
	       b(
		 checkbox(-name=>'flip',
			  -checked=>$settings->{flip},-value=>1,
			  -label=>$self->tr('Flip'),-override=>1)
		),
	       hidden(-name=>'navigate',-value=>1,-override=>1),
	       end_form
	      );
  }

  print $self->toggle('Search',
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
		     ).br({-clear=>'all'});
}

sub render_html_head {
  my $self = shift;
  my ($dsn,$title) = @_;

  my $js = $dsn->globals->js_url;
  my @scripts;

  # drag-and-drop functions from scriptaculous
  push @scripts,{src=>"$js/$_"}
    foreach qw(prototype.js scriptaculous.js);

  # our own javascript
  push @scripts,{src=>"$js/$_"}
    foreach qw(buttons.js toggle.js);

 if ($self->setting('autocomplete')) {
    push @scripts,{src=>"$js/$_"}
      foreach qw(yahoo.js dom.js event.js connection.js autocomplete.js);
  }

  my @args;
  push @args,(-title => $title,
              -style  => {src=>$dsn->globals->stylesheet_url},
              -encoding=>$self->tr('CHARSET'),
	      );
  push @args,(-head=>$self->setting('head'))    if $self->setting('head');
  push @args,(-lang=>($self->language_code)[0]) if $self->language_code;
  push @args,(-script=>\@scripts);
  push @args,(-gbrowse_images => $dsn->globals->button_url);
  push @args,(-gbrowse_js     => $dsn->globals->js_url);
  print start_html(@args) unless $self->{started_html}++;
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

  my $html = table({-border=>0, -width=>'100%',-cellspacing=>0,-class=>'searchtitle'},
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
  print $html;
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

  my @plugins = $self->shellwords($self->setting('quicklink plugins')) or return '';
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
  my $examples = $self->setting('examples') or return;;
  my @examples = $self->shellwords($examples);
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
  return unless @plugins;
  return join('',
	      popup_menu(-name=>'plugin',
			 -values=>\@plugins,
			 -labels=> $labels,
			 -default => $settings->{plugin},
			),'&nbsp;',
	      submit(-name=>'plugin_action',-value=>$self->tr('Configure')),'&nbsp;',
	      b(submit(-name=>'plugin_action',-value=>$self->tr('Go')))
	     );
}

sub slidertable {
  my $self = shift;
  my $segment = shift;

  my $whole_segment = $self->whole_seg;
  my $buttonsDir    = $self->globals->button_url;

  my $span       = $segment->length;
  my $half_title = $self->unit_label(int $span/2);
  my $full_title = $self->unit_label($span);
  my $half      = int $span/2;
  my $full      = $span;
  my $fine_zoom = $self->get_zoomincrement();

  my @lines = 
    (image_button(-src=>"$buttonsDir/green_l2.gif",-name=>"left $full",
		  -title=>"left $full_title"),
     image_button(-src=>"$buttonsDir/green_l1.gif",-name=>"left $half",
		  -title=>"left $half_title"),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/minus.gif",-name=>"zoom out $fine_zoom",
		  -title=>"zoom out $fine_zoom"),
     '&nbsp;',
     $self->zoomBar($segment,$whole_segment,$buttonsDir),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/plus.gif",-name=>"zoom in $fine_zoom",
		  -title=>"zoom in $fine_zoom"),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/green_r1.gif",-name=>"right $half",
		  -title=>"right $half_title"),
     image_button(-src=>"$buttonsDir/green_r2.gif",-name=>"right $full",
		  -title=>"right $full_title"),
    );

  my $str	= join('', @lines);
  return $str;
}

# this generates the popup zoom menu with the window sizes
sub zoomBar {
  my $self = shift;

  my ($segment,$whole_segment,$buttonsDir) = @_;

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
		    -onChange => 'this.form.submit()',
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
	: $self->data_source_description($self->session->source)
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
  my $title         = shift;
  my @body           = @_;

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

  my $buttons = $self->data_source->globals->button_url;
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

