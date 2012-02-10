package Bio::Graphics::Browser2::Render::HTML;

use strict;
use warnings;
use base 'Bio::Graphics::Browser2::Render';
use Bio::Graphics::Browser2::Shellwords;
use Bio::Graphics::Browser2::SubtrackTable;
use Bio::Graphics::Karyotype;
use Bio::Graphics::Browser2::Render::TrackConfig;
use Bio::Graphics::Browser2::Util qw[citation url_label segment_str];
use JSON;
use Digest::MD5 'md5_hex';
use Carp qw(croak cluck);
use CGI qw(:standard escape start_table end_table);
use Text::Tabs;
use POSIX qw(floor);

use constant JS    => '/gbrowse2/js';
use constant ANNOTATION_EDIT_ROWS => 25;
use constant ANNOTATION_EDIT_COLS => 100;
use constant MAXIMUM_EDITABLE_UPLOAD => 1_000_000; # bytes
use constant DEBUG => 0;

use constant HAVE_SVG => eval "require GD::SVG; 1";
our $CAN_PDF;

# Render HTML Start - Returns the HTML for the browser's <head> section.
sub render_html_start {
  my $self  = shift;
  my ($title,@actions) = @_;
  my $dsn   = $self->data_source;
  my $html  = $self->render_html_head($dsn,$title,@actions);
  $html    .= $self->render_js_controller_settings();
  $html    .= $self->render_balloon_settings();
  $html    .= "<div id='main'>";
  $html    .= $self->render_select_menus();
  return $html;
}

# Render Top - Returns the HTML for the top banner of the page.
sub render_top {
    my $self = shift;
    my ($title,$features) = @_;
    my $err  =  $self->render_error_div;
    my $html = '';

    $features ||= [];
    $html   .=  $self->render_title($title,$self->state->{name} 
				    && @$features == 0);
	# ***Render the snapshot title***
    $html   .=  $self->snapshot_manager->render_title;
    $html   .=  $self->html_frag('html1',$self->state);

    return  $err
	  . $self->toggle({nodiv=>1},'banner','',$html);
}

# Render Error DIV - Returns the HTML for the error display at the top of the page.
sub render_error_div {
    my $self   = shift;

    my $error   = $self->error_message;
    my $display = $error ? 'block' : 'none';

    my $button = button({-onClick=>'Controller.hide_error()',
			 -name=>'Ok'});
    return div({-class=>'errorpanel',
		-style=>"display:${display}",
		-id=>'errordiv'},
	       table(
		   TR(
		       td(span({-class=>'error',-id=>'errormsg'},$error || 'no error')),
		       td({-align=>'right'},$button)
		   ),
	       ),
	       div({-class=>'errorpanel',
		    -style=>"display:none;margin: 6px 6px 6px 6px",
		    -id   =>'errordetails'},
		   'no details'
	       )
	).br();
}

sub render_login_required {
    my $self   = shift;
    my $action = shift;
    return div(
	h1($self->translate('LOGIN_REQUIRED'),
	   button(-name    => $self->translate('LOGIN'),
		  -onClick => $action)
	));
}

# Render Tabbed Pages - Returns the HTML containing the tabs & the page DIVs to hold the content.
sub render_tabbed_pages {
    my $self = shift;
    my ($main_html,$tracks_html,$snapshot_html,$community_tracks_html,$custom_tracks_html,$settings_html) = @_;
    my $uses_database = $self->user_tracks->database;
    
    my $main_title             = $self->translate('MAIN_PAGE');
    my $tracks_title           = $self->translate('SELECT_TRACKS');
    my $snapshot_title	       = $self->translate('SNAPSHOT_SELECT');
    my $community_tracks_title = $self->translate('COMMUNITY_TRACKS_PAGE') if $uses_database;
    my $custom_tracks_title    = $self->translate('CUSTOM_TRACKS_PAGE');
    my $settings_title         = $self->translate('SETTINGS_PAGE');

    my $html = '';
	
    $html   .= div({-id=>'tabbed_section', -class=>'tabbed'},
	           div({-id=>'tabbed_menu',-class=>'tabmenu'},
		       span({id=>'main_page_select'},               $main_title),
		       span({id=>'track_page_select'},              $tracks_title),
		       span({id=>'snapshots_page_select'},           $snapshot_title),
		       $uses_database? span({id=>'community_tracks_page_select'},   $community_tracks_title) : "",
		       span({id=>'custom_tracks_page_select'},      $custom_tracks_title),,
		       span({id=>'settings_page_select'},           $settings_title)
		   ),
		   div({-id=>'main_page',            -class=>'tabbody'}, $main_html),
		   div({-id=>'track_page',           -class=>'tabbody' ,-style=>'display:none'}, $tracks_html),
		   div({-id=>'snapshots_page',       -class=>'tabbody' ,-style=>'display:none'}, $snapshot_html),
		   $uses_database?div({-id=>'community_tracks_page',-class=>'tabbody',-style=>'display:none'}, $community_tracks_html) : "",
		   div({-id=>'custom_tracks_page',   -class=>'tabbody',-style=>'display:none'}, $custom_tracks_html),
		   div({-id=>'settings_page',        -class=>'tabbody',-style=>'display:none'}, $settings_html),
	);
	
    return $html;
}

# Render User Head - Returns any HTML for the <head> section specified by the user in GBrowse.conf.
sub render_user_head {
    my $self = shift;
    my $settings = $self->state;
    return '' unless $settings->{head};
    my $a = $self->data_source->global_setting('head');
    return $a->(@_) if ref $a eq 'CODE';
    return $a || '';
}

# Render User Header - Returns any HTML for the top of the browser (the header) as specified by the user in GBrowse.conf.
sub render_user_header {
    my $self = shift;
    my $settings = $self->state;
    return '' unless $settings->{head};
    my $a = $self->data_source->global_setting('header');
    return $a->(@_) if ref $a eq 'CODE';
    return $a || '';
}

# Render Bottom - Returns any HTML included in the footer specified by the user in GBrowse.conf.
sub render_bottom {
  my $self = shift;
  my $features = shift; # not used
  my $a   = $self->data_source->global_setting('footer');
  my $value = ref $a eq 'CODE' ? $a->(@_) : $a;
  $value ||= '';
  return $value."</div>".end_html();
}

# Render Navbar - Returns the HTML for the navigation bar along the top of the main browser page (in the "Search" node).
sub render_navbar {
  my $self    = shift;
  my $segment = shift;

  warn "render_navbar()" if DEBUG;

  my $settings = $self->state;
  my $source   = '/'.$self->session->source.'/';

  my $searchform = join '',(
      start_form(
	  -name   => 'searchform',
	  -id     => 'searchform',
                    
      ),
      hidden(-name=>'force_submit',-value=>0),
      hidden(-name=>'plugin_find', -value=>0),
      div({ -id   => 'search_form_objects' },
	  $self->render_search_form_objects(),
      ),
      end_form
  );

  my $search = $self->setting('no search')
               ? '' : b($self->translate('Landmark')).':'.br().$searchform.$self->examples();

  my $plugin_form = div({-id=>'plugin_form'},$self->plugin_form());

  # *** Checks the state to see if a snapshot is active and assigns it ***
  my $source_form = div({-id=>'source_form'},$self->source_form());

  my $sliderform    = div({-id=>'slider_form'},$self->sliderform($segment));

  # *** Creates the save session button and assigns it to save_prompt ***
  my $snapshot_options     = $self->snapshot_manager->snapshot_options;
  return $self->toggle('Search',
		       div({-class=>'searchbody'},
			   table({-border=>0,-width=>'95%'},
				 TR(td({-width=>'50%'},$search),td({-width=>'45%'},$plugin_form,$snapshot_options)),
				 TR(td({-align=>'left'},
				       $source_form,
				    ),
				    td({-align=>'left'},
				       $sliderform || '&nbsp;'
				    ),
				 )
			   ),
			   $self->html_frag('html3',$self->state)
		       )
    )
      . div( { -id => "plugin_configure_div"},'');
}

# Plugin Form - Returns the HTML for the plugin form in the main navigation bar.
sub plugin_form {
    my $self     = shift;
    my $settings = $self->state;

    return $settings->{GALAXY_URL}
    ? button(-name    => $self->translate('SEND_TO_GALAXY'),
	      -onClick  => $self->galaxy_link).
       button(-name    => $self->translate('CANCEL'),
	      -onClick => $self->galaxy_clear.";Controller.update_sections(['plugin_form'])",
       )
     : join '',(
	start_form(-name=>'pluginform',
		   -id=>'pluginform',
		   -onSubmit=>'return false'),
	   $self->plugin_menu(),
	   end_form);
}

# Source Form - Returns the HTML for the source chooser in the main navigation bar.
sub source_form {
    my $self = shift;
    join '',(
	start_form(-name=>'sourceform',
		   -id=>'sourceform',
		   -onSubmit=>''),
	$self->source_menu(),
	end_form
    );
}

# *** Create the snapshot_form ***
sub snapshot_form {
    return shift->snapshot_manager->snapshot_form;
}

# Slider Form - Returns the HTML for the zooming controls with the "Flip" checkbox.
sub sliderform {
    my $self    = shift;
    my $segment = shift;
    my $settings = $self->state;
    if ($segment) {
	return
	    join '',(
		start_form(-name=>'sliderform',-id=>'sliderform',-onSubmit=>'return false'),
		b($self->translate('Scroll'). ': '),
		$self->slidertable($segment),
		b(
		    checkbox(-name=>'flip',
			     -checked=>$settings->{flip},-value=>1,
			     -label=>$self->translate('Flip'),-override=>1,
			     -onClick => 'Controller.update_coordinates(this.name + " " + this.checked)',
		    )
		),
		hidden(-name=>'navigate',-value=>1,-override=>1),
		end_form
	    );
    } 
    else  {
	return '';
    }
}

# Render Search For Objects - Returns the "Landmark or Region" search box on the browser tab.
sub render_search_form_objects {
    my $self     = shift;
    my $settings = $self->state;

    # avoid exposing the internal database ids to the public
    my $search_value = $settings->{name} =~ /^id:/ && $self->region->features 
	                ? eval{$self->region->features->[0]->display_name}
			: $settings->{name};
    my $html = textfield(
        -name    => 'name',
        -id      => 'landmark_search_field',
        -size    => 25,
        -default => $search_value,
	-override=>1,
    );
    if ($self->setting('autocomplete')) {
        my $spinner_url = $self->data_source->button_url.'/spinner.gif';
	$html .= <<END
<span id="indicator1" style="display: none">
  <img src="$spinner_url" alt="$self->translate('WORKING')" />
</span>
<div id="autocomplete_choices" class="autocomplete"></div>
END
    }
    $html .= submit( -name => $self->translate('Search') );
    return $html;
}

# Render HTML Head - Returns the HTML for the beginning of the page (for CGI's start HTML function).
sub render_html_head {
  my $self = shift;
  my ($dsn,$title,@other_initialization) = @_;
  my @plugin_list = $self->plugins->plugins;
  my $uses_database = $self->user_tracks->database;

  return if $self->{started_html}++;

  $title =~ s/<[^>]+>//g; # no markup in the head

  # pick scripts
  my $js       = $dsn->globals->js_url;
  my @scripts;
  
  # Set any onTabLoad functions
  my $main_page_onLoads = "";
  my $track_page_onLoads = '';
  my $community_track_page_onLoads = '';
  my $custom_track_page_onLoads = "";
  my $settings_page_onLoads = "";
  
  # Get plugin onTabLoad functions for each tab, if any
  my %plugin_onLoads = map ($_->onLoads, @plugin_list);
  $main_page_onLoads .= $plugin_onLoads{'main_page'} if $plugin_onLoads{'main_page'};
  $track_page_onLoads .= $plugin_onLoads{'track_page'} if $plugin_onLoads{'track_page'};
  $custom_track_page_onLoads .= $plugin_onLoads{'custom_track_page'} if $plugin_onLoads{'custom_track_page'} && $uses_database;
  $community_track_page_onLoads .= $plugin_onLoads{'community_track_page'} if $plugin_onLoads{'community_track_page'};
  $settings_page_onLoads .= $plugin_onLoads{'settings_page'} if $plugin_onLoads{'settings_page'};
  
  my $onTabScript .= "function onTabLoad(tab_id) {\n";
  $onTabScript .= "if (tab_id == 'main_page_select') {$main_page_onLoads}\n";
  $onTabScript .= "if (tab_id == 'track_page_select') {$track_page_onLoads}\n";
  $onTabScript .= "if (tab_id == 'community_track_page_select') {$community_track_page_onLoads}\n" if $uses_database;
  $onTabScript .= "if (tab_id == 'custom_track_page_select') {$custom_track_page_onLoads}\n";
  $onTabScript .= "if (tab_id == 'settings_page_select') {$settings_page_onLoads}\n";
  $onTabScript .= "};";
  push (@scripts,({type=>"text/javascript"}, $onTabScript));

  my $url = "?action=get_translation_tables" . ( $self->language_code ? ';language='.($self->language_code)[0] : '' ); #Include language as a parameter to prevent browser from using wrong cache if user changes languages
  push (@scripts,({src=>$url}));
  
  # drag-and-drop functions from scriptaculous
  push @scripts,{src=>"$js/$_"}
    foreach qw(
      prototype.js 
      scriptaculous.js 
      subtracktable.js
    );

  if ($self->setting('autocomplete')) {
    push @scripts,{src=>"$js/$_"}
      foreach qw(controls.js autocomplete.js);
  }

  if ($self->globals->user_accounts) {
    push @scripts,{src=>"$js/$_"}
      foreach qw(login.js);
  }

  # our own javascript files
  push @scripts,map { {src=>"$js/$_"} } qw(
      buttons.js
      trackFavorites.js
      karyotype.js
      rubber.js
      overviewSelect.js
      detailSelect.js
      regionSelect.js
      track.js
      balloon.js
      balloon.config.js
      GBox.js
      ajax_upload.js
      tabs.js
      track_configure.js
      track_pan.js
      ruler.js
      controller.js 
      snapshotManager.js
    );

  # add scripts needed by plugins. Looks in /js folder unless specified.
  my @plugin_scripts = map ($_->scripts, @plugin_list);
  # add a path if one isn't specified.
  foreach (@plugin_scripts) {
    if ($_ !~ /^\.{0,2}[\/\\]/) {
      $_ = "$js/$_";
    }
  };
  push @scripts,{src=>"$_"} foreach @plugin_scripts;
  
  # pick stylesheets.  Looks in /css folder unless specified.
  my @stylesheets;
  my $titlebar   = 'css/titlebar-default.css';
  my $stylesheet = $self->setting('stylesheet')||'/gbrowse2/css/gbrowse.css';
  push @stylesheets,{src => $self->globals->resolve_path('css/tracks.css','url')};
  push @stylesheets,{src => $self->globals->resolve_path('css/subtracktable.css','url')};
  push @stylesheets,{src => $self->globals->resolve_path('css/snapshots.css','url')};
  push @stylesheets,{src => $self->globals->resolve_path('css/karyotype.css','url')};
  push @stylesheets,{src => $self->globals->resolve_path('css/dropdown/dropdown.css','url')};
  push @stylesheets,{src => $self->globals->resolve_path('css/dropdown/default_theme.css','url')};
  push @stylesheets,{src => $self->globals->resolve_path($titlebar,'url')};
  
  # add stylesheets used by plugins
  my @plugin_stylesheets = map ($_->stylesheets, @plugin_list);
  # add a path if one isn't specified.
  foreach (@plugin_stylesheets) {
    if ($_ !~ /^\.{0,2}[\/\\]/) {
      $_ = $self->globals->resolve_path("css/$_",'url');
    }
  };
  push @stylesheets,{src => $_} foreach @plugin_stylesheets;

  my @theme_stylesheets = shellwords($self->setting('stylesheet') || '/gbrowse2/css/gbrowse.css');
  for my $s ( @theme_stylesheets ) {
      my ($url,$media) = $s =~ /^([^(]+)(?:\((.+)\))?/;
      $media ||= 'all';
      push @stylesheets, {
          src   => $self->globals->resolve_path($url,'url'),
          media => $media,
      };
  }

  # colors for "rubberband" selection 
  my $set_dragcolors = '';
  if (my $fill = $self->data_source->global_setting('hilite fill')) {
      $fill =~ s/^(\d+,\d+,\d+)$/rgb($1)/;
      $fill =~ s/^(#[0-9A-F]{2}[0-9A-F]{2}[0-9A-F]{2})[0-9A-F]{2}$/$1/;
      $fill =~ s/^(\w+):[\d.]+$/$1/;
      $set_dragcolors = "set_dragcolors('$fill')";
  }
  my $units   = $self->data_source->setting('units') || 'bp';
  my $divider = $self->data_source->unit_divider;
  my $set_units = "set_dragunits('$units',$divider)";

  my @extra_headers;
  push @extra_headers, $self->render_user_head;

  # put all the html head arguments together
  my @args = (-title    => $title,
              -style    => \@stylesheets,
              -encoding => $self->translate('CHARSET'),
	      -script   => \@scripts,
	      -head     => \@extra_headers,
	     );
  push @args,(-lang=>($self->language_code)[0]) if $self->language_code;
  
  # add body's onload arguments, including ones used by plugins
  my $autocomplete = '';

  my $plugin_onloads   = join ';',map {eval{$_->body_onloads}} @plugin_list;
  my $other_actions    = join ';',@other_initialization;
  push @args,(-onLoad => "initialize_page(); $set_dragcolors; $set_units; $plugin_onloads; $other_actions");
  return start_html(@args);
}

# Render JS Controller Settings - Renders a block of javascript that loads some of our global config settings into the main controller object for use in client-side code.
sub render_js_controller_settings {
    my ( $self ) = @_;
    my $globals = $self->globals;

    my @export_keys = qw(
                         buttons
                         balloons
                         openid
                         js
                         gbrowse_help
                         stylesheet
                        );

    my $controller_globals = JSON::to_json({
        map { $_ => ( $self->globals->url_path($_) || undef ) } @export_keys
					   });
    
    my $scripts = "Controller.set_globals( $controller_globals );";
    
    if ($globals->user_accounts) {
	my $userdb   = $self->userdb;
        my $openid   = ($userdb->can_openid   && $self->globals->user_accounts_allow_openid)      ||0;
        my $register = ($userdb->can_register && $self->globals->user_accounts_allow_registration)||0;
        $scripts .= "Controller.can_openid  = $openid;";
        $scripts .= "Controller.can_register = $register;";
    }
    
    return script({-type=>'text/javascript'}, $scripts);
}

# Renders the settings which control the balloon styles on the page.
sub render_balloon_settings {
    my $self   = shift;
    my $source = $self->data_source;

    my $default_style   = $source->setting('balloon style') || 'GBubble';;
    my $custom_balloons = $source->setting('custom balloons') || "";
    my %config_values   = $custom_balloons =~ /\[([^\]]+)\]([^\[]+)/g;

    # default image path is for the default balloon set
    my $balloon_images  = $self->globals->balloon_url() || '/gbrowse2/images/balloons';
    my $default_images = "$balloon_images/$default_style";
    my $balloon_settings = $self->default_balloon_settings($balloon_images);

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

sub default_balloon_settings {
    my $self = shift;
    my $balloon_images = shift;

    # These are the four configured popup tooltip styles
    # GBubble is the global default
    # each type can be called using the [name] syntax
    return <<END;
// Original GBrowse popup balloon style
var GBubble = new Balloon;
BalloonConfig(GBubble,'GBubble');
GBubble.images = "$balloon_images/GBubble";
GBubble.allowEventHandlers = true;
GBubble.opacity = 1;
GBubble.fontFamily = 'sans-serif';

// A simpler popup balloon style
var GPlain = new Balloon;
BalloonConfig(GPlain,'GPlain');
GPlain.images = "$balloon_images/GPlain";
GPlain.allowEventHandlers = true;
GPlain.opacity = 1;
GPlain.fontFamily = 'sans-serif';

// Like GBubble but fades in
var GFade = new Balloon;
BalloonConfig(GFade,'GFade');
GFade.images = "$balloon_images/GBubble";
GFade.opacity = 1;
GFade.allowEventHandlers = true;
GFade.fontFamily = 'sans-serif';

// A formatted box
// Note: Box is a subclass of Balloon
var GBox = new Box;
BalloonConfig(GBox,'GBox');
GBox.images = "$balloon_images/GBubble";
GBox.allowEventHandlers = true;
GBox.evalScripts        = true;
GBox.opacity = 1;
GBox.fontFamily = 'sans-serif';
GBox.maxWidth   = 1280;
GBox.stemHeight = 0;
END
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

# Returns the HTML for the page's title, as displayed at the top.
sub render_title {
    my $self  = shift;
    my $title = shift;
    my $error = shift;
    my $settings = $self->state;
    return $settings->{head}
        ? h1({-id=>'page_title',-class=>$error ? 'error' : 'normal'},$title)
	: '';
}

# Renders the search & navigation instructions & examples.
sub render_instructions {
  my $self     = shift;
  my $settings = $self->state;
  my $oligo    = $self->plugins->plugin('OligoFinder') ? ', oligonucleotide (15 bp minimum)' : '';

  return $settings->{head}
  ? div({-class=>'searchtitle'},
      $self->toggle('Instructions',
		    div({-style=>'margin-left:2em'},
			$self->setting('search_instructions') ||
			$self->translate('SEARCH_INSTRUCTIONS', $oligo),
			$self->setting('navigation_instructions') ||
			$self->translate('NAVIGATION_INSTRUCTIONS'),
			br(),
			$self->examples(),
			br(),$self->html_frag('html2',$self->state)
		    )
		  )
      )
  : '';
}




# Renders the HTML for the spinning "busy" signal on the top-left corner of the page.
sub render_busy_signal {
    my $self = shift;
    
    return img({
        -id    => 'busy_indicator',
        -src   => $self->data_source->button_url.'/spinner.gif',
        -style => 'position: fixed; top: 5px; left: 5px; display: none',
        -alt   => ($self->translate('WORKING')||'')
       });
}

# Renders the menu bar across the top of the browser.
sub render_actionmenu {
    my $self  = shift;
    my $settings = $self->state;

    my   @export_links=a({-href=>'#',-onclick=>'Controller.make_image_link("GD")'},      $self->translate('IMAGE_LINK'));
    push @export_links,a({-href=>'#',-onclick=>'Controller.make_image_link("GD::SVG")'}, $self->translate('SVG_LINK'))
	if HAVE_SVG;
    push @export_links,a({-href=>'#',-onclick=>'Controller.make_image_link("PDF")'},     $self->translate('PDF_LINK'))
	if HAVE_SVG && $self->can_generate_pdf;

    # Pass the gff link to a javascript function which will add the missing parameters that are determined client-side
    push @export_links,a({-href=>'#',-onclick=>"Controller.gbgff_link('". $self->gff_dump_link ."')"}, $self->translate('DUMP_GFF'));
    push @export_links,a({-href=>'#',-onclick=>"Controller.gbgff_link('". $self->dna_dump_link ."')"}, $self->translate('DUMP_SEQ'));

    push @export_links,a({-href=>'javascript:'.$self->galaxy_link},        $self->translate('SEND_TO_GALAXY'))
	if $self->data_source->global_setting('galaxy outgoing');

    my $bookmark_link = a({-href=>'#',-onclick=>'Controller.bookmark_link()'},$self->translate('BOOKMARK')),;
    my $share_link    = a({-href        => '#',
			   -onMouseDown => "GBox.showTooltip(event,'url:?action=share_track;track=all')"},
			  ($self->translate('SHARE_ALL') || "Share These Tracks" )),

    my $help_link     = a({-href=>$self->general_help(),
			   -target=>'_new'},$self->translate('HELP_WITH_BROWSER'));
    my $about_gb_link    = a({-onMouseDown => "Controller.show_info_message('about_gbrowse')",
			   -href        => 'javascript:void(0)',
			   -style       => 'cursor:pointer'
			  },
			  $self->translate('ABOUT'));
    my $about_dsn_link    = a({-onMouseDown => "Controller.show_info_message('about_dsn')",
			       -href        => 'javascript:void(0)',
			       -style       => 'cursor:pointer'
			      },
			      $self->translate('ABOUT_DSN'));
    my $about_me_link    = a({-onMouseDown => "Controller.show_info_message('about_me')",
			       -href        => 'javascript:void(0)',
			       -style       => 'cursor:pointer'
			      },
			      $self->translate('ABOUT_ME'));
    my $plugin_link      = $self->plugin_links($self->plugins);
    my $chrom_sizes_link = a({-href=>'?action=chrom_sizes'},$self->translate('CHROM_SIZES'));
    my $reset_link       = a({-href=>'?reset=1',-class=>'reset_button'},    $self->translate('RESET'));

    my $login = $self->globals->user_accounts ? $self->render_login : '';

    my $file_menu = ul({-id    => 'actionmenu',
			-class => 'dropdown downdown-horizontal'},
		       li({-class=>'dir'},$self->translate('FILE'),
			  ul(li($bookmark_link),
			     li($share_link),
			     li({-class=>'dir'},a({-href=>'#'},$self->translate('EXPORT')),
				ul(li(\@export_links))),
			     $plugin_link ? li($plugin_link) : (),
			     li($chrom_sizes_link),
			     li($reset_link),
			  )
		       ),
		       li({-class=>'dir'},$self->translate('HELP'),
			  ul({-class=>'dropdown'},
			     li($help_link),
			     li({-class=>'divider'},''),
			     li($about_gb_link),
			     li($about_dsn_link),
			     li($about_me_link),
			  )),
	);
    return div({-class=>'datatitle'},$file_menu,$login,br({-clear=>'all'}));
}

# Render Login - Returns the HTML for the login links on the top-right corner of the screen.
sub render_login {
    my $self     = shift;
    my $settings = $self->state;
    return unless $settings->{head};
    return $self->login_manager->render_login;
}

# For the subset of plugins that are named in the 'quicklink plugins' option, create quick links for them.
sub plugin_links {
  my $self    = shift;
  my $plugins = shift;

  my $quicklink_setting = $self->setting('quicklink plugins') or return '';
  my @plugins           = shellwords($quicklink_setting)      or return '';
  my $labels            = $plugins->menu_labels;

  my @result;
  for my $p (@plugins) {
    my $plugin = $plugins->plugin($p) or next;
    my $action = "?plugin=$p;plugin_do=".$self->translate('Go');
    push @result,a({-href=>$action,-target=>'_new'},"[$labels->{$p}]");
  }
  return \@result;
}

sub galaxy_form {
    my $self     = shift;
    my $segment  = shift;

    my $settings = $self->state;
    my $source   = $self->data_source;

    my $galaxy_url = $settings->{GALAXY_URL} 
                  || $source->global_setting('galaxy outgoing') ;
    return '' unless $galaxy_url;

    my $URL  = $source->global_setting('galaxy incoming');
    $URL   ||= $self->globals->gbrowse_url();

    # Make sure to include all necessary parameters in URL to ensure that gbrowse will retrieve the data
    # when Galaxy posts the URL.
    my $dbkey  = $source->global_setting('galaxy build name') || $source->name;
    my $labels = $self->join_selected_tracks;

    my $seg = $segment->seq_id.':'.$segment->start.'..'.$segment->end;
		      
    my $action = $galaxy_url =~ /\?/ ? "$galaxy_url&URL=$URL" : "$galaxy_url?URL=$URL";
    my $html = start_multipart_form(-name  => 'galaxyform',
				    -action => $action,
				    -method => 'POST');

    $html .= hidden(-name=>'dbkey',-value=>$dbkey);
    $html .= hidden(-name=>'gbgff',-value=>'save gff3');
    $html .= hidden(-name=>'id',   -value=>$settings->{userid});
    $html .= hidden(-name=>'q',-value=>$seg);
    $html .= hidden(-name=>'l',-value=>$labels);
    $html .= hidden(-name=>'s',-value=>0);
    $html .= hidden(-name=>'d',-value=>'edit');
    $html .= hidden(-name=>'m',-value=>'application/x-gff3');
    $html .= endform();

    return $html;
}

sub render_track_filter {
    my $self   = shift;
    my $plugin = shift;
    
    my $form         = $plugin->configure_form();
    my $plugin_type  = $plugin->type;
    my $action       = $self->translate('Configure_plugin');
    my $name         = $plugin->name;

    my $showfav   = $self->translate('FAVORITES');
    my $showall   = $self->translate('SHOWALL');

    return
 	div({-id=>'track select',-style=>'padding-top:8px'},
		start_form({-id      => 'track_filterform',
			    -name    => 'configure_plugin',
			    -onSubmit=> 'return false'}),
	    $form,
	    hidden(-name=>'plugin',-value=>$name),
	    button(
		-name    => 'plugin_button',
		-value   => $self->translate('search'),
		-onClick => 'doPluginUpdate()',
	    ),
	    end_form(),
	  script({-type=>'text/javascript'},
		 "function doPluginUpdate() { Controller.reconfigure_plugin('$action',null,null,'$plugin_type',\$('track_filterform'));updateTitle(\$('show_all_link'),0);}")
	);
}

# This surrounds the track table with a toggle
sub render_toggle_track_table {
  my $self     = shift;
  my $source   = $self->data_source;
  my $filter = $self->track_filter_plugin;
  my $settings = $self->state;
  # $settings->{show_favorites} =0;

  ## adding javascript array at the top so we can pass it into a js array -- ugly but it works
  my $html = '';

  $html .= div({-style=>'font-weight:bold'},
	       span({-style=>'padding-right:80px'},'<<',$self->render_select_browser_link('link')),
	       span({-id=>'showselectedtext',-style=>'padding-right:80px'},$self->render_show_active_tracks_link()),
	       span({-id => 'showfavoritestext',-style=>'padding-right:80px'},
		    $self->render_select_favorites_link('link')),
	       span({-id => 'clearfavs'},
		    $self->render_select_clear_link('link')));

  if (my $filter = $self->track_filter_plugin) {
      $html .= $self->toggle({tight=>1},'track_select',div({class=>'searchtitle',
							    style=>"text-indent:2em;padding-top:8px; display:block;"},
							   $self->render_track_filter($filter)));
  }

  $html .= $self->toggle({nodiv=>1},'Tracks',$self->render_track_table);
  $html .= div({-style=>'text-align:center'},$self->render_select_browser_link('button'));
  return $html;
}

sub render_track_table {
    my $self = shift;
    my $listing_class = $self->data_source->track_listing_class;
    eval "require $listing_class;1" or die $@ unless $listing_class->can('new');
    my $tlr = $listing_class->new($self);
    return $tlr->render_track_listing.$self->html_frag('html5',$self->state);
}

# Render Multiple Choices - 
sub render_multiple_choices {
    my $self     = shift;
    my $features = shift;
    my $terms2hilite = shift;
    my $karyotype = Bio::Graphics::Karyotype->new(source   => $self->data_source,
						  language => $self->language);
    $karyotype->add_hits($features);
    return $karyotype->to_html($terms2hilite);
}

# Render Global Config - Returns the HTML for the Preferences page.
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

    my %seen;

    my $region_size = $settings->{region_size} || 0;
    my @region_size  = shellwords($self->data_source->global_setting('region sizes'));
    my @region_sizes = grep {!$seen{$_}++} 
                          sort {$b<=>$a}
                             grep {defined $_ && $_ > 0} ($region_size,@region_size);
    my $content
        = start_form( -name => 'display_settings', -id => 'display_settings' )
        . div(
	       table ({-border => 0, -cellspacing=>0, -width=>'100%'},
		      TR(
			  
			  td( b(  checkbox(
				      
				      -name     => 'grid',
				      -label    => $self->translate('SHOW_GRID'),
				      -override => 1,
				      -checked  => $settings->{grid} || 0,
				      -onChange => 'Controller.set_display_option(this.name,this.checked ? 1 : 0)', 
				  )
			      )
			  ),
			  td( b( $self->translate('Image_width') ),
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
				  { -title => $self->translate('FEATURES_TO_HIGHLIGHT_HINT') },
				  b( $self->translate('FEATURES_TO_HIGHLIGHT') ),
				  br,
				  textfield(
				      -id       => 'h_feat',
				      -name     => 'h_feat',
				      -value    => $feature_highlights,
				      -size     => 50,
				      -override => 1,
				      -onChange => 'Controller.set_display_option(this.name,this.value)', 
				  ),
				  a({-href=>'javascript:void(0)',
				     -onClick=>'Controller.set_display_option("h_feat","_clear_");$("h_feat").value=""'},
				    $self->translate('CLEAR_HIGHLIGHTING'))
			      ),
			  ),
		      ),
		      TR(
			  td( $self->data_source->cache_time
			      ? ( b(  checkbox(
					  -name     => 'cache',
					  -label    => $self->translate('CACHE_TRACKS'),
					  -override => 1,
					  -checked  => $settings->{cache},
					  -onChange => 'Controller.set_display_option(this.name,this.checked?1:0)'
				      )
				  )
			      )
			      : ()
			  ),

			  td('&nbsp;'),
			  
			  td( span(
				  { -title => $self->translate('REGIONS_TO_HIGHLIGHT_HINT') },
				  b( $self->translate('REGIONS_TO_HIGHLIGHT') ),
				  br,
				  textfield(
				      -id       => 'h_region',
				      -name     => 'h_region',
				      -value    => $region_highlights,
				      -size     => 50,
				      -override => 1,
				      -onChange    => 'Controller.set_display_option(this.name,this.value)', 
				  ),
				  a({-href=>'javascript:void(0)',
				     -onClick=>'Controller.set_display_option("h_region","_clear_");$("h_region").value=""'
				    },
				    $self->translate('CLEAR_HIGHLIGHTING'))
			      ),
			  ),
		      ),
		      TR(
			  td( { -align => 'left' },
			      b(  checkbox(
				      -name     => 'show_tooltips',
				      -label    => $self->translate('SHOW_TOOLTIPS'),
				      -override => 1,
				      -checked  => $settings->{show_tooltips},
				      -onChange => 'Controller.set_display_option(this.name,this.checked?1:0)'
				  ),
			      )
			  ),
			  td('&nbsp;'),
			  td( $self->setting('region segment')
			      ? ( b( $self->translate('Region_size') ),
				  br,
				  popup_menu(
				      -name     => 'region_size',
				      -default  => $settings->{region_size},
				      -values   => \@region_sizes,
				      -override => 1,
				      -onChange   => 'Controller.set_display_option(this.name,this.value)',
				  ),
				  
			      )
			      : (),
			  ),
		      ),
		      TR(
			  td( {   -colspan => 3,
				  -align   => 'right'
			      },
			      b( submit( -name => $self->translate('Update_settings') ) )
			  )
		      )
	       )
	) . end_form();


    return div($content);

}

# Clear Hilights - Returns the HTML for the "Clear Highligting" link.
sub clear_highlights {
    my $self = shift;
    my $link = a({-style   => 'font-size:9pt',
		  -href    => 'javascript:void(0)',
		  -onClick => 'Controller.set_display_option("h_feat","_clear_");Controller.set_display_option("h_region","_clear_")'
		 },
		 $self->translate('CLEAR_HIGHLIGHTING'));
}
											
# Render Select Track Link - Returns the HTML for the "Select Tracks" button on the main browser page.
sub render_select_track_link {
    my $self  = shift;
    my $title = $self->translate('SELECT_TRACKS');
    return button({-name=>$title,
		    -onClick => "Controller.select_tab('track_page')",
		  
		  }
	  );
}

sub render_select_clear_link {
    my $self  = shift;

    my $title = $self->translate('CLEAR_FAV');
    my $settings = $self->state;
    my $clear = 1;

    warn "settings  $settings->{show_favorites}" if DEBUG;
    my $showicon =  img({-src   => $self->data_source->button_url."/ficon.png",-border=>0});
    return span(a({-href=>'javascript:void(0)',
		  -onClick => "clearallfav($clear);",
		 },
		 $title),$showicon);
}

sub render_show_active_tracks_link {
    my $self = shift;
    my $active = $self->state->{active_only} ? 'true' : 'false';
    return a({-href    => 'javascript:void(0)',
	      -class   => $active ? 'show_active' : 'inactive',
	      -onClick => "show_active_tracks(this,$active)"},
	     $self->translate('SHOW_ACTIVE_TRACKS'));
}

sub render_select_favorites_link {
    my $self  = shift;

    my $showfav   = $self->translate('FAVORITES');
    my $showall   = $self->translate('SHOWALL');
    my $refresh   = 'showrefresh';
    my $settings  = $self->state;
    
    my $ison      = $settings->{show_favorites}; 
    my $title     = $ison ? $showall : $showfav;
    my $showicon =  img({-src   => $self->data_source->button_url."/ficon_2.png",-border=>0});
 
    warn "settings  $settings->{show_favorites}" if DEBUG;
    warn "ison = $settings->{show_favorites}" if DEBUG;
    return span(a({-id      => 'show_all_link',
		   -class  => $settings->{show_favorites} ? 'favorites_only' : '',
		   -href    =>'javascript:void(0)',
		   -onClick => "updateTitle(this)"
		  },$title),$showicon);
}


# Render Select Browser Link - Returns the HTML for the "Back to Browser" button/link.
sub render_select_browser_link {
    my $self  = shift;
    my $style  = shift || 'button';
    my $settings = $self->state;
    my $title = $self->translate('BACK_TO_BROWSER');
    if ($style eq 'button') {
	    return button({-name=>$title,
		           -onClick => "Controller.select_tab('main_page')",
		          }
	        );
    } elsif ($style eq 'link') {
	    return a({-href=>'javascript:void(0)',
		      -onClick => "Controller.select_tab('main_page')"},
		     $title);
    }
}

# Render Community Tracks Section - Returns the content of the "Community Tracks" tab.
sub render_community_tracks_section {
    my $self = shift;
    my $userdata = $self->user_tracks;
    my $html = $self->is_admin? h2({-style=>'font-style:italic;background-color:yellow'}, $self->translate('ADMIN_MODE_WARNING')) : "";
	$html .= div({-id => "community_tracks"}, $self->render_community_track_listing);
	$html = div({-style => 'margin: 1em;'}, $html);
	return $html;
}

# Render Custom Tracks Section - Returns the content of the "Custom Tracks" tab.
sub render_custom_tracks_section {
    my $self = shift;
    my $userdata = $self->user_tracks;
    my $html = $self->is_admin? h2({-style=>'font-style:italic;background-color:yellow'}, $self->translate('ADMIN_MODE_WARNING')) : "";
	$html .= div({-id => "custom_tracks"}, $self->render_custom_track_listing);
	$html .= $self->userdata_upload;
	$html = div({-style => 'margin: 1em;'}, $html);
	return $html;
}

# Userdata Upload - Renders an "Add custom tracks" links in the Uploaded Tracks section.
sub userdata_upload {
    my $self     = shift;
    my $url      = url(-absolute=>1,-path_info=>1);

    my $html     = '';
    my $upload_label = $self->translate('UPLOAD_FILE');
	my $mirror_label = $self->translate('MIRROR_FILE');
    my $remove_label = $self->translate('REMOVE');
    my $new_label    = $self->translate('NEW_TRACK');
    my $from_text    = $self->translate('FROM_TEXT');
    my $from_file    = $self->translate('FROM_FILE');
	my $from_url     = $self->translate('FROM_URL');
    my $help_link     = $self->annotation_help;
    $html         .= p({-style=>'margin-left:10pt;font-weight:bold'},
		       $self->translate('ADD_YOUR_OWN_TRACKS') ,':',
		       a({-href=>"javascript:addAnUploadField('custom_list_start', '$url', '$new_label',    '$remove_label', 'edit','$help_link')"},
			 "[$from_text]"),
		       a({-href=>"javascript:addAnUploadField('custom_list_start', '$url', '$mirror_label', '$remove_label', 'url','$help_link')"},
			 "[$from_url]"),
		       a({-href=>"javascript:addAnUploadField('custom_list_start', '$url','$upload_label',  '$remove_label' , 'upload','$help_link')",
			  -id=>'file_adder',
			 },"[$from_file]"));
	$html       .= div({-id=>'custom_list_start'},'');
    return $html;
}

# Render Community Track Listing - Returns the HTML listing of public tracks available to a user.
sub render_community_track_listing {
	my $self = shift;
	my $globals	= $self->globals;
	my $html = h1({-style => "display: inline-block; margin-right: 1em;"}, $self->translate('COMMUNITY_TRACKS'));
	my $search = $_[0] || "";
	my $offset = $_[1] || 0;
	my $usertracks = $self->user_tracks;
	
	my @requested_tracks = $usertracks->get_public_files(@_) if @_;
	
	# Calculate the value for the next pagination
	my $max_files = $globals->public_files;
	my $total_tracks = $usertracks->public_count($search);
	my $track_limit = $search? @requested_tracks : $max_files;
	my $tracks_displayed = ($track_limit < (@requested_tracks? @requested_tracks : $total_tracks))
	                      ? $track_limit : (@requested_tracks? @requested_tracks : $total_tracks);
	my $tracks_remaining = $total_tracks - ($offset + $tracks_displayed);
	my $tracks_before = $offset;
	
	my $tracks_next = ($track_limit < $tracks_remaining)? $track_limit : $tracks_remaining;
	my $next_offset = $offset + $track_limit;
	my $tracks_previous = ($max_files < $tracks_before)? $max_files : $tracks_before;
	my $previous_offset = $offset - $globals->public_files;
	$previous_offset    = 0 if $previous_offset < 0;
	
	my $first_number = $offset + 1;
	my $last_number = $offset + $tracks_displayed;

	my $autocomplete = '';

	if ($self->setting('autocomplete')) {
	    my $spinner_url = $self->data_source->button_url.'/spinner.gif';
	    $autocomplete = <<END
<span id="indicator2" style="display: none">
  <img src="$spinner_url" />
</span>
<div id="autocomplete_upload_filter" class="autocomplete"></div>
END
	}
	
	# Create the HTML for the title & header
	$html .= span({-style => "display: inline-block;"},
		start_form({-action => "javascript:void(0);", 
                            # The return here is necessary to stop the form from ACTUALLY submitting.
			    -onsubmit => "return searchPublic(\$('public_search_keyword').value);"
			   }), 
		input({-type => "hidden", -name => "offset", 
		       -value => $offset, -id => "community_display_offset"}),
		ucfirst $self->translate('FILTER') . ":",
		input({
		    -type => "text",
		    -name => "keyword",
		    -id => "public_search_keyword",
		    -style => "width:200px",
		    -value => $search || ($self->globals->user_accounts? $self->translate('ENTER_KEYWORD') . 
					  " " . $self->translate('OR_USER') : $self->translate('ENTER_KEYWORD')),
		    -onClick => "this.value='';"
		}),
		input({-type => "submit", -value => "Search"}),
		($tracks_previous > 0)? a({-href => '#', 
					   -onClick => "return searchPublic(\"$search\", $previous_offset);"}, 
					  "[" . $self->translate('PREVIOUS_N', $tracks_previous) . "]") . "&nbsp;" : "",
		button(-label=>$self->tr('CLEAR'),
		       -onClick=>"\$('public_search_keyword').value='';searchPublic('',$previous_offset);"),
		ucfirst $self->translate('SHOWING'). " "
		. (($total_tracks > 0)? $self->translate('N_TO_N_OUT_OF', $first_number, $last_number) : "") . " " 
		. $self->translate('N_FILES', $total_tracks)
		. ($search? (" " . $self->translate("MATCHING", $search)) : "")
		. ".",
		($tracks_next > 0)? "&nbsp;" . a({-href => '#', -onClick => "return searchPublic(\"$search\", $next_offset);"}, 
						 "[" . $self->translate('NEXT_N', $tracks_next) . "]") : "",
		end_form(),
		$autocomplete
	);
	
	# Add the results
	if ($search || $offset) {
		$html .= @requested_tracks 
		    ? $self->list_tracks("public", @requested_tracks) 
		    : p($self->translate('NO_PUBLIC_RESULTS', $search));
	} else {
		$html .= $self->list_tracks("public");
	}
	return $html;
}

# Render Custom Track Listing - Returns the HTML listing of public, uploaded, imported and shared tracks added to a session, and a section to add more.
sub render_custom_track_listing {
	my $self = shift;
	my $html = h1($self->translate('UPLOADED_TRACKS'));

	$html .= a( {
	    -href => $self->annotation_help,
	    -target => '_blank'
		    },
		    i('['.$self->translate('HELP_FORMAT_UPLOAD').']')
	    );
	$html .= $self->list_tracks;
	return $html;
}

# List Tracks - Renders a visual listing of an array of tracks. No arguments creates the standard "my tracks" listing.
sub list_tracks {
    my $self = shift;
    my $userdata = $self->user_tracks;
    my $listing_type = shift || "";
    # If we've been given input, use the input. 
    # If we've been given the public type, use that, or default to all of the current user's tracks.
    my @tracks = @_? @_ 
	: (($listing_type =~ /public/)  && ($userdata->database == 1))
	? $userdata->get_public_files 
	: $userdata->tracks;
    my $track_type = $listing_type;

    $track_type .= " available" if $listing_type =~ /public/;
	
    # Main track roll code.
    if (@tracks) {
	my $count = 0;
	my @rows = map {
	    my $fileid = $_;
	    my $type = $track_type || $userdata->file_type($fileid);
	    
	    my $class         = $self->track_class($count, $type);
	    my $controls      = $self->render_track_controls($fileid, $type);
	    my $short_listing = $self->render_track_list_title($fileid, $type);
	    my $details       = $self->render_track_details($fileid, @tracks? 1 : 0);
	    my $edit_field    = div({-id => $fileid . "_editfield", -style => "display: none;"}, '');
	    $count++;
	    div({
		-id		=> "$fileid",
		-class	=> "custom_track $class",
		-style  => 'padding: 0.5em',
		 },
		 $controls,
		 $short_listing,
		 $details,
		 $edit_field
		);
	} @tracks;
	return join '', @rows;
    } else {
    	return p($self->translate(($track_type =~ /public/i ? 'THERE_ARE_NO_AVAILABLE_TRACKS':'THERE_ARE_NO_TRACKS_YET'), $track_type));
    }
}

# Track Class (Count, Type) - Returns the class for a specific custom track.
sub track_class {
    my $self = shift;
    my $count = shift;
    my $type = shift;
    $type =~ s/\s?available//;
    return $type . "_" . (($count % 2)? "even" : "odd");
}

# Render Track List Title (Track, Type) - Renders the visible HTML which is seen when the details are hidden.
sub render_track_list_title {
    my $self = shift;
    my $fileid = shift;
    my $type = shift;
    $type =~ s/\s?available//;
    my $userdata = $self->user_tracks;
    my $globals = $self->globals;
	
    my $short_name = $userdata->title($fileid);
    if ($short_name =~ /http_([^_]+).+_gbgff_.+_t_(.+)_s_/) {
	my @tracks = split /\+/, $2;
	$short_name = "Shared track from $1 (@tracks)";
    } elsif (length $short_name > 40) {
	$short_name =~ s/^(.{40}).+/$1.../;
    }

    my $is_mine = $userdata->is_mine($fileid);
    my $cursor  = $is_mine ? 'cursor:pointer' : 'cursor:auto';
    my $uploaddb  = $userdata->database;
	
    my @track_labels = $userdata->labels($fileid);
    my $track_labels = join '+', map {CGI::escape($_)} @track_labels;
    my $source_note = span({-class => "source_note"}, $type);
    my $go_there = join(' ',
			map {
			    my $label = $_;
			    my $go_there_script    = "Controller.select_tab('main_page',false);Controller.scroll_to_matching_track('$label')";
			    my $edit_label_script  = "Controller.edit_upload_track_key('$fileid', '$label', this)";
			    my $script             = $is_mine ? "if (event.shiftKey || event.ctrlKey) {$edit_label_script} else {$go_there_script}"
				                              : $go_there_script;
			    my $key   = $self->data_source->setting($label=>'key');
			    $key? (
				'['.
				span({-class => 'clickable',
				      $is_mine ? (-title => $self->tr('EDIT_LABEL')) : (),
				      -onClick         => $script,
				      -contentEditable => $is_mine ? 'true' : 'false',
				     },
				     b($key)
				).
				']'
				) : ''
			} @track_labels);
    my $stat = div(
	{
	    -id => $fileid . "_stat",
	    -style=> "display: inline;"
	},
	''
	);
    my $title = h1(
	{
	    ($is_mine ? (-title => $self->tr('ADD_TITLE')) : ()),
	    -style => "display: inline; font-size: 14pt;$cursor",
	    -onClick         => ($uploaddb && $is_mine)? "Controller.edit_upload_title('$fileid', this)" : "",
	    -contentEditable => ($uploaddb && $is_mine)? 'true' : 'false',
	},
	$short_name
	);
    my $owner;
    if ($globals->user_accounts) {
	my $owner_name = $userdata->owner_name($fileid);
	my $users      = $self->userdb;
	my ($fullname,$email)   = $users->accountinfo_from_username($owner_name);
	$email ||= '';
	my $email_link          = a({-href=>"mailto:$email"},$email);
	$fullname             ||= $owner_name;
	$owner = $self->translate("UPLOADED_BY") . " " . b($fullname).($email ? " &lt;${email_link}&gt;" : '');
    } else { 
	$owner = '';
    }
    
    return span(
	{-style => "display: inline;"},
	$stat,
	$title,
	$owner,
	br(),
	$go_there,
	) . $source_note;
}

# Render Track Controls (Track Name, Type) - Renders the HTML for the main track controls in the custom track listing.
sub render_track_controls {
	my $self = shift;
	my $fileid = shift;
	my $type = shift;
	my $userdata = $self->user_tracks;
	my $userid   = $userdata->{userid}||'';
	my @track_labels = $userdata->labels($fileid);
	my $track_labels = join '+', map {CGI::escape($_)} @track_labels;
	my $globals = $self->globals;
	
	my $buttons = $self->data_source->globals->button_url;
	
	my $controls;
	# Conditional controls, based on the type of track.
	if ($userdata->is_mine($fileid)) {
	    # The delete icon,
	    $controls .= '&nbsp;' . img(
		{
		    -src     	 => "$buttons/trash.png",
		    -style  	 => 'cursor:pointer',
		    -onMouseOver => 'GBubble.showTooltip(event,"'.$self->translate('DELETE').'",0)',
		    -onClick     => "deleteUpload('$fileid')"
		}
		);
	    # The sharing icon, if it's an upload.
	    $controls .= '&nbsp;' . img(
		{
		    -src         => "$buttons/share.png",
		    -style       => 'cursor:pointer',
		    -onMouseOver => 'GBubble.showTooltip(event,"'.$self->translate('SHARE_WITH_OTHERS').'",0)',
		    -onClick     => "Controller.get_sharing(event,'url:?action=share_track;track=$track_labels')"
		}
		) if ($type =~ /upload/ && !$userdata->database);
	}
	if ($type !~ /available/) {
	    if ($type =~ /(public|shared)/) {
		# The "remove" [x] link.
		$controls .= '&nbsp;' . a(
		    {
			-href     	 => "javascript: void(0)",
			-onMouseOver => 'GBubble.showTooltip(event,"'.$self->translate('REMOVE_FROM_MY_SESSION').'",0,200)',
			-onClick     => "unshareFile('$fileid', '$userid')"
		    },
		    "[X]"
		    );
	    }
	} else {
	    $userid ||= '';
	    $controls .= '&nbsp;' . a(
		{
		    -href	 => "javascript:void(0);",
		    -onClick => "shareFile('$fileid', '$userid')"
		},
		'['.$self->translate('SHARING_ADD_USER').']'
		);
	}
	
	return span(
		{
			-class => "controls",
			-style => "display: inline; padding: 0.3em;"
		}, $controls
	);
}

# Render Track Details (Track Name, Display?) - Renders the track listing details section.
sub render_track_details {
	my $self = shift;
	my $fileid = shift;
	my $display = shift || 0;
	my $userdata = $self->user_tracks;
	my $globals	= $self->globals;
	my $random_id = 'upload_'.int rand(9999);
	my $is_mine   = $userdata->is_mine($fileid);
	my $cursor  = $is_mine ? 'cursor:pointer' : 'cursor:auto';	
	my $description = div(
		{
		    ($is_mine ? (-title           => $self->tr('ADD_DESCRIPTION')) : ()),
		    -style           => $cursor,
		    -id              => $fileid . "_description",
		    -onClick         => $is_mine ? "Controller.edit_upload_description('$fileid', this)" : "",
		    -contentEditable => $is_mine ? 'true' : 'false',
		},
	    $userdata->description($fileid) || $self->translate($is_mine ? 'ADD_DESCRIPTION' : 'NO_DESCRIPTION')
	);
	my $source_listing = div(
		{-style => "margin-left: 2em; display: inline-block;"},
		$self->render_track_source_files($fileid)
	);
	my $sharing = ($userdata->database == 1)? div(
		{
			-style => "margin-left: 2em; display: inline;",
			-class => "sharing"
		},
		$self->render_track_sharing($fileid)
	) : "";
	
	my $status    = $userdata->status($fileid) || 'complete';
	my $status_box = div(
	    div({-id=>"${random_id}_form", -style=>"display: none;"},'&nbsp;'),
	    div({-id=>"${random_id}_status", -style=>"display: none;"},
		i($status),
		a(
		    {
			-href    =>'javascript:void(0)',
			-onClick => "Controller.monitor_upload('$random_id','$fileid')",
		    },
		    $self->translate('INTERRUPTED_RESUME')
		)
	    )
	    );
	
	return div(
		{
			-style => $display? "display: block;" : "display: none;",
			-class => "details"
		},
		i($description),
		$source_listing,
	        br(),
		$sharing,
		$status_box
	);
}

# Render Track Source Files (Track) - Renders the HTML listing of a track's source files.
sub render_track_source_files {
	my $self   = shift;
	my $fileid = shift;
	my $userdata     = $self->user_tracks();
	my @source_files = $userdata->source_files($fileid);
	my ($conf_name, $conf_modified, $conf_size) = $userdata->conf_metadata($fileid);
	$conf_modified ||= 0;
	$conf_size     ||=0;
	my $mirror_url = $userdata->is_mirrored($fileid);
	my $source_listing =
		b($self->translate('SOURCE_FILES')) .
		ul(
		    {-style => "margin: 0; padding: 0; list-style: none;"},
		    li(
			[map {
			    a( {
				-href => $mirror_url || "?userdata_download=$_->[0];track=$fileid",
				-style	=> "display: inline-block; width: 30em; overflow: hidden;"
			       },
			       $_->[0]
				).
				span({-style => "display: inline-block; width: 15em;"}, scalar localtime($_->[2])).
				span({-style => "display: inline-block; width: 10em;"}, $_->[1],'bytes').
				span(
				    ($_->[1] <= MAXIMUM_EDITABLE_UPLOAD && -T $_->[3] && $userdata->is_mine($fileid))?
				    $mirror_url?
				    a( {
					-href => "javascript:void(0)",
					-onClick => "reloadURL('$fileid','$mirror_url')"
				       },
				       $self->translate('RELOAD_FROM', $mirror_url)
				    ) : 
				    a( {
					-href    => "javascript:void(0)",
					-onClick => "editUploadData('$fileid','$_->[0]')"
				       },
				       $self->translate('EDIT_BUTTON')
				    )
				    : '&nbsp;'
				)
			 } @source_files]
		    ),
		    li(
			a( {
			    -href	=> "?userdata_download=conf;track=$fileid",
			    -style	=> "display: inline-block; width: 30em;"
			   },
			   $self->translate('CONFIGURATION')
			).
			span({-style => "display: inline-block; width: 15em;"}, scalar localtime $conf_modified).
			span({-style => "display: inline-block; width: 10em;"}, "$conf_size bytes").
			span(
			    ($userdata->is_mine($fileid))
			    ? a({
				-href    => "javascript:void(0)",
				-onClick => "editUploadConf('$fileid')"
			      }, $self->translate('EDIT_BUTTON')
			    ) 
			    : "&nbsp;"
			)
		    )
		);
	return $source_listing;
}

# Render Track Sharing (Track) - Renders the HTML listing of a track's sharing properties.
sub render_track_sharing {
    my $self = shift;
    my $fileid = shift;
    my $globals = $self->globals;
    my $userdb = $self->userdb if $globals->user_accounts;
    my $userdata = $self->user_tracks;
    
    #Building the users list.
    my $sharing_policy = $userdata->permissions($fileid);
    my @users = $userdata->shared_with($fileid);
    $_ = b(($globals->user_accounts)
	   ? $userdb->username_from_userid($_) : "an anonymous user") . 
	   "&nbsp;" . 
	   a({-href => "javascript:void(0)", -onClick => "unshareFile('$fileid', '$_')"}, "[X]") . "" foreach @users;
    my $userlist = join (", ", @users);
	
    my $sharing_content = b($self->translate('SHARING')) . br() . $self->translate('TRACK_IS') . " ";
    if ($userdata->is_mine($fileid) == 0) {
	my $count = ($sharing_policy eq "public")? $userdata->public_users($fileid) : $userdata->shared_with($fileid);
	$sharing_content .= b(($sharing_policy =~ /(casual|group)/)? lc $self->translate('SHARED_WITH_YOU') :  lc $self->translate('SHARING_PUBLIC'));
	$sharing_content .= ", " . $self->translate('USED_BY') . "&nbsp;" .  ($count? b($count) . "&nbsp;" . $self->translate('USERS') . "." : $self->translate('NO_ONE')) unless $sharing_policy =~ /casual/;
    } else {
	my %sharing_type_labels = ( private => $self->translate('SHARING_PRIVATE'),
				    casual  => $self->translate('SHARING_CASUAL') ,
				    group   => $self->translate('SHARING_GROUP')  ,
				    public  => $self->translate('SHARING_PUBLIC') );
	$sharing_content .= Select(
	    {-onChange => "changePermissions('$fileid', this.options[this.selectedIndex].value.toLowerCase())"},
	    map {
		option(
                    {
			-value => $_,
			($sharing_policy =~ /$_/i)? (-selected => "selected") : ()
		    },
		    $sharing_type_labels{$_}
		    )
	    } keys %sharing_type_labels
	    );
	
	my $sharing_help = $self->translate('SHARING_HELP');
		
	$sharing_content .= "&nbsp;" . a({-href => "javascript:void(0)", 
					  -onMouseOver => "GBubble.showTooltip(event,'$sharing_help',0,300);"}, 
					 "[?]");
	$sharing_content .= "&nbsp;" . $self->translate('SHARED_WITH') . 
	                    "&nbsp;" .  ($userlist? "$userlist" : $self->translate('NO_ONE')
			    )   if ($sharing_policy =~ /(casual|group)/);
	if ($sharing_policy =~ /public/) {
	    my $count = $userdata->public_users($fileid);
	    $sharing_content .= "&nbsp;" . 
		$self->translate('USED_BY') . 
		"&nbsp;" .  ($count? b($count) . 
			     "&nbsp;" . $self->translate('USERS') . "." : $self->translate('NO_ONE'));
	}
		
	if ($sharing_policy =~ /casual/) {
	    my $sharing_url = $userdata->sharing_link($fileid);
	    my $sharing_link = a({-href => $sharing_url}, $sharing_url);
	    $sharing_content .= br() . $self->translate('SHARE_WITH_THIS_LINK');
	    $sharing_content .= $sharing_link;
	}
		
	if ($sharing_policy =~ /group/) {
	    my $id = 'username_entry_'.int(rand(100000));
	    my $add_box = "&nbsp;" . input(
		{
		    -length => 60,
		    -style  => 'width:300px',
		    -class  => 'username_entry',
		    -id     => $id,
		    -value => $self->translate('ENTER_SOMETHING_HERE', 
					       (($globals->user_accounts)
						? $self->translate('USERNAME_OR_USER_ID') 
						: $self->translate('USER_ID'))),
		    -onFocus => "this.clear()"
		});
	    my $add_autocomplete = div({-id=>"${id}_choices",
					-class=>'autocomplete usersearch'},'') if $self->setting('autocomplete');
	    my $add_link = "&nbsp;" . a(
		{
		    -href => "javascript: void(0)",
		    -onClick => "shareFile('$fileid', this.previous('input').getValue())",
		},
		$self->translate('ADD_BUTTON') );
	    $sharing_content .= $add_box . $add_autocomplete . $add_link;
	};
    }
    return $sharing_content;
}

sub segment2link {
    my $self = shift;

    my ($segment,$label) = @_;
    
    my $source = $self->data_source;
    return  a({-href=>"?name=$segment"},$segment) unless ref $segment;

    my $ref = $segment->seq_id;
    my ($start,$stop) = ($segment->start,$segment->end);
    my $bp = $stop - $start;
    $label ||= segment_str($segment);
    $ref||='';  # get rid of uninit warnings
    return a({-href=>"?ref=$ref;start=$start;stop=$stop"},$label);
}

sub tableize {
  my $self              = shift;
  my ($array,$cols,$labelnames,$row_labels,$column_labels) = @_;
  return unless @$array;
  my $settings = $self->state;

  my $columns = $cols || 
       $self->data_source->global_setting('config table columns') || 3;
  my $rows    = int( @$array/$columns + 0.99 );

  # gets the data for the defined 'category table(s)'
  my (@column_labels,@row_labels);
  if ($row_labels && $column_labels) {
      @row_labels       = @$row_labels;
      @column_labels    = @$column_labels;
      $rows             = @row_labels;
      $columns          = @column_labels;
  }

  my $cwidth = int(100/$columns+0.5) . '%';
 
  my $html = start_table({-border=>0,-width=>'100%'});

  if (@column_labels) {
      $html.="<tr valign='top'><td></td>";
      for (my $column=0;$column<$columns;$column++) {
	  $html .= "<td><b>$column_labels[$column]</b> </td>";
      }
      $html.="</tr>";
  }

  for (my $row=0;$row<$rows;$row++) {
    # do table headers
    $html .= qq(<tr class="searchtitle" valign="top">);
    $html .= "<td><b>$row_labels[$row]</b></td>" if @row_labels;
    for (my $column=0;$column<$columns;$column++) {
	my $label    = $labelnames->[$column*$rows + $row] || '&nbsp;';
	my $checkbox = $array->[$column*$rows + $row] || '&nbsp;';
  
	# de-couple the checkbox and label click behaviors
	$checkbox =~ s/\<\/?label\>//gi;
	if ($label =~/^=/) {
          $label = '&nbsp;';
          $checkbox = '&nbsp;';
        }
	my $class = $settings->{features}{$label}{visible} ? 'activeTrack' : '';

	$html .= td({-width=>$cwidth,-style => 'visibility:visible',-class=>$class},
		    span({ -id => "notselectedcheck_${label}", 
			   -class => 'notselected_check'},$checkbox));
    }
    $html .= "</tr>\n";
  }
  $html .= end_table();
}

sub subtrack_counts {
    my $self  = shift;
    my $label = shift;
    my $stt   = $self->create_subtrack_manager($label) or return;
    return $stt->counts;
}

sub subtrack_table {
    my $self          = shift;
    my $label         = shift;
    my $stt           = $self->create_subtrack_manager($label);
    return $stt->selection_table($self);
}

#### generate the fragment of HTML for printing out the examples
sub examples {
  my $self = shift;
  my $examples = $self->setting('examples') or return;
  my @examples = shellwords($examples);
  return unless @examples;
  my @urls = map { a({-href=>"?name=".escape($_)},$_) } @examples;
  return b($self->translate('Examples')).': '.join(', ',@urls).". ";
}

######################### code for the search box and navigation bar ###################
sub plugin_menu {
  my $self = shift;
  my $settings = $self->state;
  my $plugins  = $self->plugins;

  my $labels   = $plugins->menu_labels;

  my @plugins  = grep {$plugins->plugin($_)->type ne 'trackfilter'}  # track filter gets its own special position
                 sort {$labels->{$a} cmp $labels->{$b}} keys %$labels;

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
	-id       => 'plugin',
	-values     => \@plugins,
	-labels     => $labels,
	-attributes => \%attributes,
	-default    => $settings->{plugin},
      ),
    '&nbsp;',
    button(
      -name     => 'plugin_action',
      -value    => $self->translate('Configure'),
      -onClick => 'Controller.configure_plugin("plugin_configure_div");'
    ),
    '&nbsp;',
    button(
        -name    => 'plugin_action',
        -value   => $self->translate('Go'),
        -onClick => 'var select_box = document.pluginform.plugin;'
            . q{var plugin_type = select_box.options[select_box.selectedIndex].attributes.getNamedItem('plugin_type').value;}
            . 'Controller.plugin_go('
            . 'document.pluginform.plugin.value,'
            . 'plugin_type,' . '"'
            . $self->translate('Go') . '",'
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
    my $plugin_id   = $plugin->id;

    print CGI::header(-type=>'text/html',     
		      -cache_control =>'no-cache');
    print start_form(
		  -name     => 'configure_plugin',
		  -id       => 'configure_plugin',
		  ),
	  button(-value => $self->translate('Cancel'),
 		 -onClick=>'Balloon.prototype.hideTooltip(1)'),
	  button(-value => $self->translate('Configure_plugin'),
 		 -onClick=>'Controller.reconfigure_plugin('
                 . '"'.$self->translate('Configure_plugin').'"'
                 . qq(, "plugin:$plugin_id")
                 . qq(, "plugin_configure_div")
                 . qq(, "$plugin_type")
                 . qq(, this.parentNode)
		 . ');Balloon.prototype.hideTooltip(1)'),
          $plugin->configure_form(),
          end_form();
}

# wrap arbitrary HTML in a named div
sub wrap_in_div {
    my $self   = shift;
    my $div_id = shift;
    return div({-id=>$div_id},@_);
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
        my $plugin_type        = $plugin->type;
        my $plugin_name        = $plugin->name;
        my $plugin_id          = $plugin->id;
	my @plugin_description = $plugin->description;
        my @buttons;

        # Cancel Button
        push @buttons,
            button(
            -name    => 'plugin_button',
            -value   => $self->translate('CANCEL'),
            -onClick => 'Controller.wipe_div("plugin_configure_div");'
            );

        # Configure Button

        # Supplies the track name and the track div which I'm not really
        # happy with
        push @buttons,
            button(
            -name    => 'plugin_button',
            -value   => $self->translate('Configure_plugin'),
            -onClick => 'Controller.reconfigure_plugin("'
                . $self->translate('Configure_plugin') . '", "'
                . "plugin:$plugin_id"
                . '","plugin_configure_div","'
                . $plugin_type . '");'
            );
        if ( $plugin_type eq 'finder' ) {
            push @buttons,
                button(
                -name    => 'plugin_button',
                -value   => $self->translate('Find'),
                -onClick => 'Controller.plugin_go("'
                    . $plugin_base . '","'
                    . $plugin_type . '","'
                    . $self->translate('Find') . '","'
                    . 'config' . '")',
                );
        }
        elsif ( $plugin_type eq 'dumper' ) {
            push @buttons,
                button(
                -name    => 'plugin_button',
                -value   => $self->translate('Go'),
                -onClick => 'Controller.plugin_go("'
                    . $plugin_base . '","'
                    . $plugin_type . '","'
                    . $self->translate('Go') . '","'
                    . 'config' . '")',
                );
        }

        # Start adding to the html
        $return_html .= h1(
              $plugin_type eq 'finder'
            ? $self->translate('Find')
            : $self->translate('Configure'),
            $plugin_name,
        );
	$return_html .= div({-style=>'font-size:small'},@plugin_description);

        my $button_html = join( '&nbsp;',
            @buttons[ 0 .. @buttons - 2 ],
            b( $buttons[-1] ),
        );

        $return_html .= join '', $button_html, $config_html, p(),
            $button_html,;
    }
    else {
        $return_html .= join '', p( $self->translate('Boring_plugin') ),
            b(
            button(
                -name    => 'plugin_button',
                -value   => $self->translate('CANCEL'),
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
    my $track_id      = $args{'track_id'};
    my $track_name    = $args{'track_name'};
    my $track_html    = $args{'track_html'};

    # track_type used in register_track() javascript method
    my $track_type = $args{'track_type'} || 'standard';

    my $section = $self->data_source->get_section_from_label($track_id);
    my $class   = $track_id =~ /scale/i ? 'scale' : 'track';

    return div(
        {   -id    => "track_" . $track_id,
            -class => $class,
        },
        $track_html
        )
        . qq[<script type="text/javascript" language="JavaScript">Controller.register_track("]
	. $track_id   . q[", "]
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
        -charset => $self->translate('CHARSET'),
        $attachment ? ( -attachment => $attachment ) : (),
    );
}

# Slider Table - Returns the HTML for the zooming and panning controls.
sub slidertable {
  my $self    = shift;
  my $state   = $self->state;

  # try to avoid reopening the database -- recover segment
  # and whole segment lengths from our stored state if available
  my $span  = $state->{view_stop} - $state->{view_start} + 1;
  my $max   = $self->thin_whole_segment->length;

  my $buttonsDir    = $self->data_source->button_url;

  my $half_title = $self->data_source->unit_label(int $span/2);
  my $full_title = $self->data_source->unit_label($span);
  my $half       = int $span/2;
  my $full       = $span;
  my $fine_zoom  = $self->get_zoomincrement();

  my $show   = $self->translate('Show').' ';

  my @lines =
    (image_button(-src     => "$buttonsDir/green_l2.gif",
		  -name=>"left $full",
		  -title   => "left $full_title",
		  -onClick => "Controller.scroll('left', 1)"
     ),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/green_l1.gif",-name=>"left $half",
		  -title=>"left $half_title",
		  -onClick => "Controller.scroll('left', 0.5)"
     ),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/mminus.png",
		  -name=>"zoom out $fine_zoom",
		  -style=>'background-color: transparent',
		  -title=>"zoom out $fine_zoom",
		  -onClick => "Controller.update_coordinates(this.name)"
     ),
     '&nbsp;',
     $self->zoomBar($span,$max,$show),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/mplus.png",
		  -name=>"zoom in $fine_zoom",
		  -style=>'background-color: transparent',
		  -title=>"zoom in $fine_zoom",
		  -onClick => "Controller.update_coordinates(this.name)",
     ),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/green_r1.gif",-name=>"right $half",
		  -title=>"right $half_title",
		  -onClick => "Controller.scroll('right', 0.5)"
     ),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/green_r2.gif",-name=>"right $full",
		  -title=>"right $full_title",
		  -onClick => "Controller.scroll('right', 1)"
     ),
     '&nbsp;',
    );

  my $str	= join('', @lines);
  return span({-id=>'span'},$str);
}

# this generates the popup zoom menu with the window sizes
sub zoomBar {
  my $self = shift;
  my ($length,$max,$item_label) = @_;
  $item_label ||= '';

  my %seen;
  my @r         = sort {$a<=>$b} $self->data_source->get_ranges();
  $max         *= $self->data_source->unit_divider;

  my @ranges	= grep {!$seen{$self->data_source->unit_label($_)}++ && $_<=$max} sort {$b<=>$a} @r,$length;
  my %labels    = map {$_=>$item_label.$self->data_source->unit_label($_)} @ranges;
  return popup_menu(-class   => 'searchtitle',
		    -name    => 'span',
		    -values  => \@ranges,
		    -labels  => \%labels,
		    -default => $length,
		    -force   => 1,
		    -onChange => 'Controller.update_coordinates("set span "+this.value)',
		   );
}

sub render_ruler_div {
	my $self = shift;

	my $ruler_js = <<RULER;
<script type="text/javascript">
  // <![CDATA[
    createRuler();
  // ]]>
</script>
RULER

    my $settings   = $self->state;
    my $width      = $self->get_image_width($settings);
    my $button_url = $self->data_source->button_url;

    return div({-id => 'ruler_track',
                -style => "position:relative; z-index: 100; width:${width}px; height:0px; margin-left:auto; margin-right:auto;"},
                 div({-id => 'ruler_handle',
                      -style => "width:51px; z-index: 100;"},
                        div({-id      => 'ruler_label',
                             -onMouseUp => 'toggleRuler(false)',
                             -style   => "height:17px; cursor:pointer; text-align:center; visibility:hidden;"},'') .
                        div({-id => 'ruler_icon',
                             -onMouseOver => 'GBubble.showTooltip(event,"'.$self->translate('RULER_TOGGLE_TOOLTIP').'",0)',
                             -onMouseUp => 'toggleRuler(true)',
                             -style => "height:17px; cursor:pointer; position:absolute; top:2px; left:3px;"},
                                img({-src=>"${button_url}/ruler-icon.png",-alt=>'Ruler'}) ) .
                        div({-id => 'ruler_image',
                             -style => "background-image: url(${button_url}/ruler.png); cursor:move; background-size: 100%; display:none;"},'')
            )) . $ruler_js;
}

sub source_menu {
  my $self = shift;

  my $globals  = $self->globals;
  my $username = $self->session->username if $self->session->private;
  my $p        = eval{$self->plugins->auth_plugin};

  my @sources      = $globals->data_sources;
  my $show_sources = $self->setting('show sources');
  $show_sources    = 1 unless defined $show_sources;   # default to true
  @sources         = grep {$globals->data_source_show($_,$username,$p)} @sources;
  my $sources      = $show_sources && @sources > 1;

  my %descriptions = map {$_=>$globals->data_source_description($_)} @sources;
  @sources         = sort {$descriptions{$a} cmp $descriptions{$b}} @sources;

  my %sources      = map {$_=>1} @sources;
  
  my $current_source = $self->data_source->name;
  if (!$sources{$current_source} && 
      $globals->data_source_show($current_source,$username,$p) ) { # for regexp-based sources
      $descriptions{$current_source} = $self->data_source->description;
      @sources          = sort {$descriptions{$a} cmp $descriptions{$b}} (@sources,$current_source);
  }

  return b($self->translate('DATA_SOURCE')).br.
    ( $sources ?
      popup_menu(-name     => 'source',
		 -values   => \@sources,
		 -labels   => \%descriptions,
		 -default  => $self->data_source->name,
		 -onChange => 'this.form.submit()',
		)
	: $globals->data_source_description($self->session->source)
      );
}

# This is the content of the popup balloon that describes the track and gives configuration settings

# This is currently somewhat hacky, hard to extend and needs to be generalized.
# NOTE: to add new configuration rows, the name of the form element must begin with "conf_" and
# the rest must correspond to a valid glyph option.
sub track_config {
    my $self        = shift;
    my $label              = shift;
    my $revert_to_defaults = shift;

    eval 'require Bio::Graphics::Browser2::TrackConfig'
	unless Bio::Graphics::Browser2::Render::TrackConfig->can('new');
    my $c           = Bio::Graphics::Browser2::Render::TrackConfig->new($self);
    return $c->config_dialog($label,$revert_to_defaults);
}

sub cit_link {
    my $self        = shift;
    my $label       = shift;
    return "?display_citation=$label";
}

sub track_citation {
    my $self        = shift;
    my $label       = shift;

    my $state       = $self->state();
    my $data_source = $self->data_source();

    my $length      = $self->thin_segment->length;
    my $slabel      = $data_source->semantic_label($label,$length);
    my $key         = $self->label2key($slabel);

    # citation info:
    my $cit_txt = citation( $data_source, $label, $self->language ) 
	|| $self->tr('NO_TRACK_CITATION');
    my $cit_html;
    my $cit_link = '';
     
    # For verbose citations, add a link to a new window
    if (length $cit_txt > 512) {
       $cit_link = "?display_citation=$label";
       $cit_link =~ s!gbrowse\?!gbrowse/$state->{source}/\?!;
       $cit_link = a(
    	    {
    	      -href    => $cit_link, 
    	      -target  => "citation", #'_NEW',
    	      -onclick => 'GBox.hideTooltip(1)'
    		},
    	    'Click here to display in new window...');    
       $cit_link = p($cit_link);
    }
    $cit_html = p($cit_link||br,$cit_txt);
    my $title    = div({-style => 'background:gainsboro;padding:5px;font-weight:bold'},$key);
    my $download = a({-href=>"?l=$label;f=save+datafile"},$self->tr('DOWNLOAD_ALL'));
    my $id       = $self->tr('TRACK_ID',$label);
    return  p(div({-style=>'text-align:center;font-size:small'},$title,$id,"[$download]"),$cit_html);
}

sub download_track_menu {
    my $self  = shift;
    my $track = shift;
    my $view_start = shift;
    my $view_stop  = shift;

    my $state       = $self->state();
    my $data_source = $self->data_source();

    my $segment;
    if ($track =~ /:overview$/) {
        $segment = $self->thin_whole_segment;
    } elsif ($track =~ /:region$/) {
        $segment = $self->thin_region_segment;
    } else {
        $segment = $self->thin_segment;
        $segment->{start} = $view_start || $segment->{start};
        $segment->{stop}  = $view_stop  || $segment->{stop};
        $segment->{end}   = $view_stop  || $segment->{end};
    }

    my $seqid       = $segment->seq_id;
    my $start       = $segment->start;
    my $end         = $segment->end;
    my $key         = $self->label2key($track);

    my $unload      = 'window.onbeforeunload=void(0)';
    my $byebye      = 'Balloon.prototype.hideTooltip(1)';

    my $segment_str = segment_str($segment);
    my $glyph       = $data_source->setting($track=>'glyph') || 'generic';
    
    my @format_options = Bio::Graphics::Browser2::TrackDumper->available_formats($data_source,$track);
    my %foptions       = map {$_=>1} @format_options;
    my $default     = $foptions{$state->{preferred_dump_format}||''} ? $state->{preferred_dump_format}
                                                                     : $glyph =~ /vista/ && $foptions{vista} ? 'vista'
                                                                     : $foptions{gff3}   ? 'gff3'
								     : $foptions{bed}    ? 'bed'
								     : $foptions{sam}    ? 'sam'
								     : $foptions{vista}  ? 'vista'
								     : 'fasta';
    my @radios      = radio_group(-name   => 'format',
				  -values => \@format_options,
				  -default => $default,
				  -labels => {fasta => 'FASTA',
					      gff3  => 'GFF3',
					      genbank => 'Genbank',
					      vista        => 'WIG (peaks+signal)',
					      vista_wiggle => 'WIG (signal)',
					      vista_peaks  => 'WIG (peaks)',
					      bed   => 'WIG',
					      sam   => 'SAM alignment format'});
    my $options = "gbgff=1;l=$track;s=0;f=save+gff3;'+\$('dump_form').serialize()";
    my $html = '';
    $html   .= div({-align=>'center'},
		   div({-style => 'background:gainsboro;padding:5px;font-weight:bold'},$key).
		   hr().
		   start_form({-id=>'dump_form'}).
		   div($self->tableize(\@radios,3)).
		   end_form().
		   hr().
		   button(-value   => $self->translate('DOWNLOAD_TRACK_DATA_REGION',$segment_str),
			  -onClick => "$unload;window.location='?q=$seqid:$start..$end;$options;$byebye",
		   ),br(),

		   button(-value   => $self->translate('DOWNLOAD_TRACK_DATA_CHROM',$seqid),
			  -onClick => "$unload;window.location='?q=$seqid;$options;$byebye",
		   ),br(),

		   button(-value=> $self->translate('DOWNLOAD_TRACK_DATA_ALL'),
			  -onClick => "$unload;location.href='?$options;$byebye",
		   )).
		   button(-style=>"background:pink;float:right",-onClick=>"$byebye",-name=>$self->translate('CANCEL'));
    return $html;
}

# this is the content of the popup balloon that describes how to share a track
sub share_track {
    my $self  = shift;
    my $label = shift;

    my $state = $self->state();
    my $source = $self->data_source;
    my $name   = $source->name;

    (my $lbase = $label) =~ s/:\w+$//;

    my $description;
    my $labels;
    my $usertracks_present;

    my @visible
        = grep { $state->{features}{$_}{visible} && !/:(overview|region)$/ }
        @{ $state->{tracks} };

    if ( $label eq 'all' ) {
	    for my $l (@visible) {
	        $usertracks_present ||= $source->is_usertrack($l);
	    }
            $labels = join '+', map { CGI::escape($_) } @visible;
            $description = 'all selected tracks';
    } else {
        $description = $self->setting( $label => 'key' ) 
	    || $self->setting( $lbase => 'key')
	    || $label;
	    $usertracks_present ||= $source->is_usertrack($label);
        $labels = $label;
    }

    my $base = url(-full=>1,-path_info=>1);

    my $gbgff;
    my $segment = $label =~  /:region$/   ? '$region'
                 :$label =~  /:overview$/ ? '$overview'
                 :'$segment';
    my $session = $self->session;
    my $upload_id = $session->uploadsid;
    if ( $label =~ /^(http|ftp)/ ) {    # reexporting an imported track!
        $gbgff   = $source->setting($label=>'remote feature');
        $gbgff ||= $source->setting($lbase=>'remote feature');
    } else {
        $gbgff  = $base;
        $gbgff .= "?gbgff=1;q=$segment;t=$labels;s=1;format=gff3";
        $gbgff .= ";uuid=$upload_id" if $usertracks_present;
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
    $das =~ s/$name/$name|$label/ if $label ne 'all';
    $das .= "features";
    $das .= "?$das_types";

    my $return_html = start_html();
    $return_html .= h1( $self->translate('SHARE', $description));

    my $tsize = 72;
    
    if ($source->is_usertrack($label)) {
        my $usertracks = $self->user_tracks;
        my $file = $usertracks->get_track_upload_id($label);
        my $permissions = $usertracks->permissions($file);
        my $is_mine = $usertracks->is_mine($file);
        if ($is_mine || $permissions eq "public" || $permissions eq "casual") {
            my $permissions_changed;
            if ($permissions !~ /(casual|public)/) {
                $usertracks->permissions($file, "casual");
                $permissions_changed = 1;
            }
            if ($is_mine) {
                $return_html .= p(($permissions_changed? 
				   $self->translate('SHARE_CUSTOM_TRACK_CHANGED', "casual") 
				   : $self->translate('SHARE_CUSTOM_TRACK_NO_CHANGE', $permissions)) 
				   . $self->translate('SHARE_INSTRUCTIONS_BOOKMARK'));
                $return_html .= p($self->translate('OTHER_SHARE_METHODS'));
            } elsif ($permissions =~ /(casual|public)/) {
                $return_html .= p($self->translate('SHARE_SHARED_TRACK', $permissions) 
				  . $self->translate('SHARE_INSTRUCTIONS_BOOKMARK'));
            }
            
            $return_html .= textfield(
	            -style    => 'background-color: wheat',
	            -readonly => 1,
	            -size     => $tsize,
	            -value    => $usertracks->sharing_link($file),
	            -onClick  => 'this.select()',
	        ).br();
        } else {
            $return_html .= p($self->translate('CANT_SHARE'));
        }
    } else {
        if ($label ne 'all' && $label !~ /^(http|ftp)/) {
            my $shared = "$base?label=$label";

	        $return_html .= p(
	            $self->translate('SHARE_INSTRUCTIONS_BOOKMARK'),br(),
	            textfield(
		            -style    => 'background-color: wheat',
		            -readonly => 1,
		            -size     => $tsize,
		            -value    => $shared,
		            -onClick  => 'this.select()'
	            )
	        )
        }

        $return_html .=
	    p(
	        $self->translate(
		    $label eq 'all'
		    ? 'SHARE_INSTRUCTIONS_ALL_TRACKS'
		    : 'SHARE_INSTRUCTIONS_ONE_TRACK'
	        ).br().
	        textfield(
		    -style    => 'background-color: wheat',
		    -readonly => 1,
		    -size     => $tsize,
		    -value    => $gbgff,
		    -onClick  => 'this.select()'));

        if ($das_types) {
            $return_html .= p(
                $self->translate(
                    $label eq 'all'
                    ? 'SHARE_DAS_INSTRUCTIONS_ALL_TRACKS'
                    : 'SHARE_DAS_INSTRUCTIONS_ONE_TRACK'
                )
                )
	        . p( textfield(
                    -style    => 'background-color: wheat',
                    -readonly => 1,
		    -size     => $tsize,
                    -value    => $das,
                    -onFocus  => 'this.select()',
                    -onSelect => 'this.select()')
                 );
        }
    }
    
    $return_html .= 
    button(
	     -name    => $self->translate('OK'),
	     -onClick => 'Balloon.prototype.hideTooltip(1)'
	     );

    $return_html .= end_html();
    return div({-style=>'width:600px'},$return_html);
}

################### various utilities ###################

sub html_frag {
  my $self     = shift;
  my $fragname = shift;
  my $a = $self->data_source->global_setting($fragname);
  return $a->(@_) if ref $a eq 'CODE';
  return $a || '';
}


############################## toggle code ########################
sub toggle {
  my $self = shift;

  my %args = ();
  if (ref $_[0]) {
      %args = %{shift()};
  }
  
  my $title = shift;
  my @body  = @_;

  my $page_settings = $self->state;

  my $id    = "\L${title}_panel\E";
  my $label = $self->translate($title) || '';
  my $state = $self->data_source->section_setting($title)    or return '';
  return '' if $state eq 'off';
  my $visible = exists $page_settings->{section_visible}{$id} ? 
    $page_settings->{section_visible}{$id} : $state eq 'open';

  return $self->toggle_section({on=>$visible,%args},
			       $id,
			       b($label),
			       @body);
}

sub toggle_section {
  my $self = shift;
  my %config = ref $_[0] eq 'HASH' ? %{shift()} : ();
  my ($name,$section_title,@section_body) = @_;

  my $visible = $config{on};

  my $buttons = $self->data_source->button_url;
  my $plus  = "$buttons/plus.png";
  my $minus = "$buttons/minus.png";
  my $break = div({-id=>"${name}_break",
		   -style=>$visible ? 'display:none' : 'display:block'
		  },'&nbsp;');

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
		     img({-src=>$minus,-alt=>'-'}).'&nbsp;'.span({-class=>'tctl',-id=>"${name}_title"},$section_title));
  my $content  = div({-id    => $name,
		      -style=>$visible ? 'display:inline' : 'display:none',
		      -class => 'el_visible'},
		     @section_body);
  my @class  = (-class=>'toggleable');
  my @result =  $config{nodiv} ? (div({-style=>'float:left',@class},
				      $show_ctl.$hide_ctl),$content)
                :$config{tight}? (div({-style=>'float:left;position:absolute;z-index:10',@class},
				      $show_ctl.$hide_ctl).$break,$content)
                : div({@class},$show_ctl.$hide_ctl,$content);
  return wantarray ? @result : "@result";
}

sub can_generate_pdf {
    my $self   = shift;
    my $source = $self->data_source;

    return $CAN_PDF if defined $CAN_PDF;
    return $CAN_PDF = $source->global_setting('generate pdf') 
	if defined $source->global_setting('generate pdf');

    return $CAN_PDF=0 unless `which inkscape`;
    # see whether we have the needed .inkscape and .gnome2 directories
    my $home = (getpwuid($<))[7];
    my $user = (getpwuid($<))[0];
    my $inkscape_dir = File::Spec->catfile($home,'.config','inkscape');
    my $gnome2_dir   = File::Spec->catfile($home,'.gnome2');
    if (-e $inkscape_dir && -w $inkscape_dir
	&&  -e $gnome2_dir   && -w $gnome2_dir) {
	return $CAN_PDF=1;
    } else {
	print STDERR
	    join(' ',
		 qq(GBROWSE NOTICE: To enable PDF generation, please enter the directory "$home"),
		 qq(and run the commands:),
		 qq("sudo mkdir -p .config/inkscape .gnome2"),
		 qq(and "sudo chown $user .config/inkscape .gnome2". ),
		 qq(To turn off this message add "generate pdf = 0"),
		 qq(to the [GENERAL] section of your GBrowse.conf configuration file.)
	    );
	return $CAN_PDF=0;
    }
}

# Truncated version (of track_config) for displaying citation only:
sub display_citation {
    my $self        = shift;
    my $label       = shift;
    my $state       = $self->state();
    my $data_source = $self->data_source();
    my $segment     = $self->thin_segment;
    my $length      = $segment ? $segment->length : 0;
    my $slabel      = $data_source->semantic_label($label,$length);
 
    my $key = $self->label2key($slabel);
 
    my @stylesheets;
    my @style = shellwords($self->setting('stylesheet') || '/gbrowse2/gbrowse.css');
     for my $s (@style) {
      my ($url,$media) = $s =~ /^([^\(]+)(?:\((.+)\))?/;
      $media ||= 'all';
      push @stylesheets, CGI::Link({-rel=>'stylesheet',
 				    -type=>'text/css',
 				    -href=>$self->globals->resolve_path($url,'url'),
 				    -media=>$media});
     }
 				
   my $return_html = start_html(-title => $key, -head => \@stylesheets);
   my $cit_txt = citation( $data_source, $label, $self->language ) || $self->translate('NO_CITATION');
     
   if (my ($lim) = $slabel =~ /\:(\d+)$/) {
        $key .= " (at >$lim bp)";
   }

   my $citation = div({-class => 'searchbody', -style => 'padding:10px;width:70%'}, h4($key), $cit_txt);
     
 
   $return_html
           .= table( TR( td( { -valign => 'top' }, $citation ) ) );
   $return_html .= end_html();
   return $return_html;
}

sub format_autocomplete {
    my $self     = shift;
    my $features = shift;
    my $partial  = shift;
    my %names;
    for my $f (@$features) {
	my ($name) = grep {/$partial/i} ($f->display_name,eval{$f->aliases});
	$names{$name}++;
    }
    my $html = "<ul>\n";
    for my $n (sort keys %names) {
	$n =~ s/($partial)/<b>$1<\/b>/i;
	$html .= "<li>$n</li>\n";
    }
    $html .= "</ul>\n";
    return $html;
}

sub format_upload_autocomplete {
    my $self     = shift;
    my $matches  = shift;
    my $partial  = shift;
    my %names;
    for my $f (@$matches) {
	my ($name) = grep {/$partial/i} $f;
	$names{$name}++;
    }
    my $html = "<ul>\n";
    for my $n (sort keys %names) {
	$n =~ s/($partial)/<b>$1<\/b>/i;
	$html .= "<li>$n</li>\n";
    }
    $html .= "</ul>\n";
    return $html;
}
1;
