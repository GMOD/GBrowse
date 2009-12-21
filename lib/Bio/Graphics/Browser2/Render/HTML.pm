package Bio::Graphics::Browser2::Render::HTML;

use strict;
use warnings;
use base 'Bio::Graphics::Browser2::Render';
use Bio::Graphics::Browser2::Shellwords;
use Bio::Graphics::Karyotype;
use Bio::Graphics::Browser2::Util qw[citation url_label];
use JSON;
use Digest::MD5 'md5_hex';
use Carp 'croak';
use CGI qw(:standard escape start_table end_table);
use Text::Tabs;

use constant JS    => '/gbrowse/js';
use constant ANNOTATION_EDIT_ROWS => 25;
use constant ANNOTATION_EDIT_COLS => 100;
use constant DEBUG => 0;

use constant HAVE_SVG => eval "require GD::SVG; 1";
our $CAN_PDF;

sub render_html_start {
  my $self  = shift;
  my $title = shift;
  my $dsn   = $self->data_source;
  my $html  = $self->render_html_head($dsn,$title);
  $html    .= $self->render_balloon_settings();
  $html    .= $self->render_select_menus();
  return $html;
}

sub render_top {
    my $self = shift;
    my ($title,$features) = @_;
    my $err  =  $self->render_error_div;
    my $html = '';

    $html   .=  $self->render_title($title,$self->state->{name} 
				    && @$features == 0);
    $html   .=  $self->html_frag('html1',$self->state);
    return  $err
	  . $self->toggle({nodiv=>1},'banner','',$html);
}

sub render_error_div {
    my $self   = shift;
    my $button = button({-onClick=>'Controller.hide_error()',
			 -name=>'Ok'});
    return div({-class=>'errorpanel',
		-style=>'display:none',
		-id=>'errordiv'},
	       table(
		   TR(
		       td(span({-id=>'errormsg'},'no error')),
		       td({-align=>'right'},$button)
		   ),
	       ),
	       div({-class=>'errorpanel',
		    -style=>'display:none;margin: 6px 6px 6px 6px',
		    -id   =>'errordetails'},
		   'no details'
	       )
	);
}

sub render_tabbed_pages {
    my $self = shift;
    my ($main_html,$custom_tracks_html,$settings_html) = @_;
    my $main_title          = $self->tr('MAIN_PAGE');
    my $custom_tracks_title = $self->tr('CUSTOM_TRACKS_PAGE');
    my $settings_title      = $self->tr('SETTINGS_PAGE');

    my $html = '';
    $html   .= div({-id=>'tabbed_section',-class=>'tabbed'},
		   div({-id=>'tabbed_menu',-class=>'tabmenu'},
		       span({id=>'main_page_select'},    $main_title),
		       span({id=>'custom_tracks_page_select'},$custom_tracks_title),
		       span({id=>'settings_page_select'},$settings_title)
		   ),
		   div({-id=>'main_page'},         $main_html),
		   div({-id=>'custom_tracks_page'},$custom_tracks_html),
		   div({-id=>'settings_page'},     $settings_html)
	);
    return $html;
}

sub render_user_head {
    my $self = shift;
    my $settings = $self->state;
    return '' unless $settings->{head};
    my $a = $self->data_source->global_setting('head');
    return $a->(@_) if ref $a eq 'CODE';
    return $a || '';
}

sub render_user_header {
    my $self = shift;
    my $settings = $self->state;
    return '' unless $settings->{head};
    my $a = $self->data_source->global_setting('header');
    return $a->(@_) if ref $a eq 'CODE';
    return $a || '';
}

sub render_bottom {
  my $self = shift;
  my $features = shift; # not used
  my $a   = $self->data_source->global_setting('footer');
  my $value = ref $a eq 'CODE' ? $a->(@_) : $a;
  $value ||= '';
  return $value.end_html();
}

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
      div({ -id   => 'search_form_objects' },
	  $self->render_search_form_objects(),
      ),
      end_form
  );

  my $search = $self->setting('no search')
               ? '' : b($self->tr('Landmark')).':'.br().$searchform.$self->examples();

  my $plugin_form = div({-id=>'plugin_form'},$self->plugin_form());

  my $source_form = div({-id=>'source_form'},$self->source_form());

  my $sliderform  = div({-id=>'slider_form'},$self->sliderform($segment));

  return $self->toggle('Search',
		       div({-class=>'searchbody'},
			   table({-border=>0},
				 TR(td($search),td($plugin_form)),
				 TR(td({-align=>'left'},
				       $source_form,
				    ),
				    td({-align=>'left'},
				       $sliderform || '&nbsp;'
				    )
				 )
			   ),
			   $self->html_frag('html3',$self->state)
		       )
    )
      . div( { -id => "plugin_configure_div"},'');
}

sub plugin_form {
    my $self     = shift;
    my $settings = $self->state;

    return $settings->{GALAXY_URL}
    ? button(-name    => $self->tr('SEND_TO_GALAXY'),
	      -onClick  => $self->galaxy_link).
       button(-name    => $self->tr('CANCEL'),
	      -onClick => $self->galaxy_clear.";Controller.update_sections(['plugin_form'])",
       )
     : join '',(
	start_form(-name=>'pluginform',
		   -id=>'pluginform',
		   -onSubmit=>'return false'),
	   $self->plugin_menu(),
	   end_form);
}


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

sub sliderform {
    my $self    = shift;
    my $segment = shift;
    my $settings = $self->state;
    if ($segment) {
	return
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
    else  {
	return '';
    }
}

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
	$html .= <<END
<span id="indicator1" style="display: none">
  <img src="/gbrowse2/images/spinner.gif" alt="Working..." />
</span>
<div id="autocomplete_choices" class="autocomplete"></div>
END
    }
    $html .= submit( -name => $self->tr('Search') );
    return $html;
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
      foreach qw(controls.js autocomplete.js);
  }

  if ($self->setting('login script')) {
    push @scripts,{src=>"$js/$_"}
      foreach qw(login.js);
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
               ajax_upload.js
               tabs.js
               controller.js
    );

  # pick stylesheets;
  my @extra_headers;
  my @style = shellwords($self->setting('stylesheet') || '/gbrowse/gbrowse.css');
  for my $s (@style) {
      my ($url,$media) = $s =~ /^([^(]+)(?:\((.+)\))?/;
      $media ||= 'all';
      push @extra_headers,CGI::Link({-rel=>'stylesheet',
				     -type=>'text/css',
				     -href=>$self->globals->resolve_path($url,'url'),
				     -media=>$media});
  }


  my @stylesheets;
  my $titlebar   = 'css/titlebar-default.css';
  my $stylesheet = $self->setting('stylesheet')||'/gbrowse/gbrowse.css';
  push @stylesheets,{src => $self->globals->resolve_path('css/tracks.css','url')};
  push @stylesheets,{src => $self->globals->resolve_path('css/karyotype.css','url')};
  push @stylesheets,{src => $self->globals->resolve_path('css/dropdown/dropdown.css','url')};
  push @stylesheets,{src => $self->globals->resolve_path('css/dropdown/default_theme.css','url')};
  push @stylesheets,{src => $self->globals->resolve_path($titlebar,'url')};

  # colors for "rubberband" selection 
  my $set_dragcolors = '';
  if (my $fill = $self->data_source->global_setting('hilite fill')) {
      $fill =~ s/^(\d+,\d+,\d+)$/rgb($1)/;
      $fill =~ s/^(#[0-9A-F]{2}[0-9A-F]{2}[0-9A-F]{2})[0-9A-F]{2}$/$1/;
      $fill =~ s/^(\w+):[\d.]+$/$1/;
      $set_dragcolors = "set_dragcolors('$fill')";
  }

  push @extra_headers,$self->setting('head')  if $self->setting('head');

  # put them all together
  my @args = (-title    => $title,
              -style    => \@stylesheets,
              -encoding => $self->tr('CHARSET'),
	      -script   => \@scripts,
	      -head     => \@extra_headers,
	     );
  push @args,(-lang=>($self->language_code)[0]) if $self->language_code;
  my $autocomplete = '';
  push @args,(-onLoad=>"initialize_page();$set_dragcolors;$autocomplete");

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
GBox.opacity = 1;
GBox.fontFamily = 'sans-serif';
GBox.stemHeight = 0;
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

sub render_login {
    my $self     = shift;
    my $images   = $self->globals->openid_url;
    my $appname  = $self->globals->application_name;
    my $appnamel = $self->globals->application_name_long;
    my $settings = $self->state;
    my $session  = $self->session;
    my $style    = 'float:right;font-weight:bold;color:blue;cursor:pointer;';
    my ($html,$title,$text,$click);
    $click = 'load_login_globals(\''.$images.'\',\''.$appname.'\',\''.$appnamel.'\');';
    $html  = '';

    if ($session->private) {
        $html .= span({-style=>'float:right;font-weight:bold;color:black;'},
                      'Welcome, '.$session->username.'.') . br() .
                 span({-style       => $style,
		       -title       => 'Click here to log out from '.$session->username.'',
		       -onMouseDown => 'location.href=\'?id=logout\';',
		       -onMouseOver => 'this.style.textDecoration=\'underline\'',
		       -onMouseOut  => 'this.style.textDecoration=\'none\''}, 'Log Out') .
		       span({-style=>'float:right;font-weight:bold;color:black;'}, '&nbsp; &nbsp;');

        $title  = 'Click here to change your account settings';
        $text   = 'My Account';
        $click .= 'load_login_balloon(event,\''.$session->id.'\',\'';
        $click .= $session->username.'\','.$session->using_openid.');';
    } else {
        $title  = 'Click here to log in or create a new gbrowse account';
        $text   = 'Log in / create account';
        $click .= 'load_login_balloon(event,\''.$session->id.'\',false,false);';
    }

    $html .= span({-style => $style, -title => $title, -onMouseDown => $click,
                  -onMouseOver => 'this.style.textDecoration=\'underline\'',
                  -onMouseOut  => 'this.style.textDecoration=\'none\''}, $text);

    return $settings->{head} ? $html : '';

    my $container = span({-style=>'float:right;'},$html);

    return $settings->{head} ? $container : '';
}

sub render_login_account_confirm {
    my $self     = shift;
    my $confirm  = shift;
    my $images   = $self->globals->openid_url;
    my $appname  = $self->globals->application_name;
    my $appnamel = $self->globals->application_name_long;
    my $settings = $self->state;

    return $settings->{head} ?
        iframe({-style  => 'display:none;',
                -onLoad => 'load_login_globals(\''.$images.'\',\''.$appname.'\',\''.$appnamel.'\');
                 confirm_screen(\''.$confirm.'\')'})
        : "";
}

sub render_login_openid_confirm {
    my $self            = shift;
    my $images          = $self->globals->openid_url;
    my $appname         = $self->globals->application_name;
    my $appnamel        = $self->globals->application_name_long;
    my $settings        = $self->state;
    my $this_session    = $self->session;
    my ($page,$session) = @_;

    my $logged_in = 'false';
       $logged_in = 'true'  if $this_session->private;

    return $settings->{head} ?
        iframe({-style  => 'display:none;',
                -onLoad => 'load_login_globals(\''.$images.'\',\''.$appname.'\',\''.$appnamel.'\');
                 login_blackout(true,\'\');confirm_openid(\''.$session.'\',\''.$page.'\','.$logged_in.');'})
        : "";
}

sub render_title {
    my $self  = shift;
    my $title = shift;
    my $error = shift;
    my $settings = $self->state;
    return $settings->{head}
        ? h1({-id=>'page_title',-class=>$error ? 'error' : 'normal'},$title)
	: '';
}

sub render_instructions {
  my $self     = shift;
  my $settings = $self->state;
  my $oligo    = $self->plugins->plugin('OligoFinder') ? ', oligonucleotide (15 bp minimum)' : '';

  return $settings->{head}
  ? div({-class=>'searchtitle'},
      $self->toggle('Instructions',
		    div({-style=>'margin-left:2em'},
			$self->setting('search_instructions') ||
			$self->tr('SEARCH_INSTRUCTIONS',$oligo),
			$self->setting('navigation_instructions') ||
			$self->tr('NAVIGATION_INSTRUCTIONS'),
			br(),
			$self->examples(),
			br(),$self->html_frag('html2',$self->state)
		    )
		  )
      )
  : '';
}

sub render_actionmenu {
    my $self  = shift;
    my $settings = $self->state;

    my   @export_links=a({-href=>'?make_image=GD', -target=>'_blank'},     $self->tr('IMAGE_LINK'));
    push @export_links,a({-href=>'?make_image=GD::SVG',-target=>'_blank'}, $self->tr('SVG_LINK'))
	if HAVE_SVG;
    push @export_links,a({-href=>'?make_image=GD::SVG',-target=>'_blank'}, $self->tr('PDF_LINK'))
	if HAVE_SVG && $self->can_generate_pdf;

    push @export_links,a({-href=>$self->gff_dump_link},                    $self->tr('DUMP_GFF'));
    push @export_links,a({-href=>$self->dna_dump_link},                           $self->tr('DUMP_SEQ'));
    push @export_links,a({-href=>'javascript:'.$self->galaxy_link},        $self->tr('SEND_TO_GALAXY'));

    my $bookmark_link = a({-href=>'?action=bookmark'},$self->tr('BOOKMARK')),;
    my $share_link    = a({-href        => '#',
			   -onMouseDown => "GBox.showTooltip(event,'url:?action=share_track;track=all')"},
			  ($self->tr('SHARE_ALL') || "Share These Tracks" )),

    my $help_link     = a({-href=>$self->general_help(),-target=>'help'},$self->tr('Help'));
    my $plugin_link   = $self->plugin_links($self->plugins);
    my $reset_link    = a({-href=>'?reset=1',-class=>'reset_button'},    $self->tr('RESET'));

    my $login = $self->setting('login script') ? $self->render_login : '';

    my $file_menu = ul({-id    => 'actionmenu',
			-class => 'dropdown downdown-horizontal'},
		       li({-class=>'dir'},'File',
			  ul(li($bookmark_link),
			     li($share_link),
			     li({-class=>'dir'},a({-href=>'#'},$self->tr('EXPORT')),
				ul(li(\@export_links))),
			     $plugin_link ? li($plugin_link) : (),
			     li($reset_link)
			  )
		       ),
		       li({-class=>'dir'},'About',
			  ul(li($help_link))),
	);
    return div({-class=>'datatitle'},$file_menu.$login.br({-clear=>'all'}));
}

# for the subset of plugins that are named in the 'quicklink plugins' option, create
# quick links for them.
sub plugin_links {
  my $self    = shift;
  my $plugins = shift;

  my $quicklink_setting = $self->setting('quicklink plugins') or return '';
  my @plugins           = shellwords($quicklink_setting)      or return '';
  my $labels            = $plugins->menu_labels;

  my @result;
  for my $p (@plugins) {
    my $plugin = $plugins->plugin($p) or next;
    my $action = "?plugin=$p;plugin_do=".$self->tr('Go');
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
    if (!$URL) {
	$URL = url(-full=>1,-path_info=>1);
    } else {
      $URL .= "/".$source->name;
    }

    my $action = $galaxy_url =~ /\?/ ? "$galaxy_url&URL=$URL" : "$galaxy_url?URL=$URL";

    my $html = start_multipart_form(-name  => 'galaxyform',
				    -action => $action,
				    -method => 'POST');

    # Make sure to include all necessary parameters in URL to ensure that gbrowse will retrieve the data
    # when Galaxy posts the URL.
    my $dbkey  = $source->global_setting('galaxy build name') || $source->name;
    my $labels = join('+',map {escape($_)} $self->detail_tracks);

    my $seg = $segment->seq_id.':'.$segment->start.'..'.$segment->end;
		      
    $html .= hidden(-name=>'dbkey',-value=>$dbkey);
    $html .= hidden(-name=>'gbgff',-value=>1);
    $html .= hidden(-name=>'id',   -value=>$settings->{userid});
    $html .= hidden(-name=>'q',-value=>$seg);
    $html .= hidden(-name=>'t',-value=>$labels);
    $html .= hidden(-name=>'s',-value=>'off');
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
    my $action       = $self->tr('Configure_plugin');
    my $name         = 'plugin:'.$plugin->name;

    return
 	p({-id=>'track select'},
	  start_form({-id      => 'track_filterform',
		      -name    => 'configure_plugin',
		      -onSubmit=> 'return false'}),
	  $form,
	  button(
	      -name    => 'plugin_button',
	      -value   => $self->tr('Configure_plugin'),
	      -onClick => 'doPluginUpdate()',
	  ),
	  end_form(),
	  script({-type=>'text/javascript'},
		 "function doPluginUpdate() { Controller.reconfigure_plugin('$action',null,null,'$plugin_type',\$('track_filterform')) }")
	);
}

# This surrounds the track table with a toggle
sub render_toggle_track_table {
  my $self     = shift;
  my $html;

  if (my $filter = $self->track_filter_plugin) {
      $html .= $self->toggle({tight=>1},'track_select',div({class=>'searchtitle',
							    style=>"text-indent:2em"},$self->render_track_filter($filter)));
  }
  $html .= $self->toggle('Tracks',$self->render_track_table);

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
  my @labels     = $self->potential_tracks;

  warn "potential tracks = @labels" if DEBUG;
  my %labels     = map {$_ => $self->label2key($_)}              @labels;
  my @defaults   = grep {$settings->{features}{$_}{visible}  }   @labels;

  if (my $filter = $self->track_filter_plugin) {
      eval {@labels    = $filter->filter_tracks(\@labels,$source)};
      warn $@ if $@;
  }

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
    my $category_title   = (split m/(?<!\\):/,$category)[-1];
    $category_title      =~ s/\\//g;

    if ($category eq $self->tr('REGION') 
	&& !$self->setting('region segment')) {
     next;
    }

    elsif  (exists $track_groups{$category}) {
      my @track_labels = @{$track_groups{$category}};

      $settings->{sk} ||= 'sorted'; # get rid of annoying warning

      @track_labels = sort {lc ($labels{$a}) cmp lc ($labels{$b})} @track_labels
        if ($settings->{sk} eq "sorted");

      my %ids        = map {$_=>{id=>"${_}_check"}} @track_labels;

      my @checkboxes = checkbox_group(-name       => 'label',
				      -values     => \@track_labels,
				      -labels     => \%labels,
				      -defaults   => \@defaults,
				      -onClick    => "gbTurnOff('$id');gbToggleTrack(this)",
				      -attributes => \%ids,
				      -override   => 1,
				     );
      $table = $self->tableize(\@checkboxes);
      my $visible = exists $settings->{section_visible}{$id} 
                    ? $settings->{section_visible}{$id} : 1;

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
	       end_form,
	       $self->html_frag('html5',$settings),
	       );
}

sub indent_categories {
    my $self = shift;
    my ($contents,$categories) = @_;

    my $category_hash = {};
    my %sort_order;
    my $sort_index = 0;

    for my $category (@$categories) {
	my $cont   = $contents->{$category} || '';

	my @parts  = map {s/\\//g; $_} split m/(?<!\\):/,$category;
	$sort_order{$_} = $sort_index++ foreach @parts;

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
	           ($sort->{$a}||0)<=>($sort->{$b}||0) || $a cmp $b
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

    my %seen;

    my $region_size = $settings->{region_size} || 0;
    my @region_size  = shellwords($self->data_source->global_setting('region sizes'));
    my @region_sizes = grep {!$seen{$_}++} 
                          sort {$b<=>$a}
                             grep {defined $_ && $_ > 0} ($region_size,@region_size);
    my $content
        = start_form( -name => 'display_settings', -id => 'display_settings' )
        . div( {-class=>'searchbody'},
	       table ({-border => 0, -cellspacing=>0, -width=>'100%'},
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
				      -id       => 'h_feat',
				      -name     => 'h_feat',
				      -value    => $feature_highlights,
				      -size     => 50,
				      -override => 1,
				      -onChange => 'Controller.set_display_option(this.name,this.value)', 
				  ),
				  a({-href=>'javascript:void(0)',
				     -onClick=>'Controller.set_display_option("h_feat","_clear_");$("h_feat").value=""'},
				    $self->tr('CLEAR_HIGHLIGHTING'))
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

			  td('&nbsp;'),
			  
			  td( span(
				  { -title => $self->tr('REGIONS_TO_HIGHLIGHT_HINT') },
				  b( $self->tr('REGIONS_TO_HIGHLIGHT') ),
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
				    $self->tr('CLEAR_HIGHLIGHTING'))
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
			  td('&nbsp;'),
			  td( $self->setting('region segment')
			      ? ( b( $self->tr('Region_size') ),
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
		      TR( { -class => 'searchtitle' },
			  td( {   -colspan => 3,
				  -align   => 'right'
			      },
			      b( submit( -name => $self->tr('Update_settings') ) )
			  )
		      )
	       )
	) . end_form();
    return div($content);
}

sub render_toggle_userdata_table {
    my $self = shift;
    return h2('Uploaded Tracks').
	div($self->render_userdata_table(),
	    $self->userdata_upload()
	);
}

sub render_toggle_import_table {
    my $self = shift;
    return h2('Imported Tracks').
	div($self->render_userimport_table(),
	    $self->userdata_import()
	);
}

sub render_userdata_table {
    my $self = shift;
    my $html = div( {-id=>'userdata_table_div',-class=>'uploadbody'},
		    scalar $self->list_userdata('uploaded'));
    return $html;
}

sub render_userimport_table {
    my $self = shift;
    my $html = div( { -id => 'userimport_table_div',-class=>'uploadbody' },
		    $self->list_userdata('imported'),
	);
    return $html;
}

sub list_userdata {
    my $self = shift;
    my $type = shift;

    my $userdata = Bio::Graphics::Browser2::UserTracks->new($self->data_source,
							   $self->state,
							   $self->language);

    my $imported = $type eq 'imported' ? 1 : 0;
    my @tracks   = $userdata->tracks($imported);
    my %modified = map {$_ => $userdata->modified($_) } @tracks;
    @tracks      = sort {$modified{$a}<=>$modified{$b}} @tracks;

    my $buttons = $self->data_source->globals->button_url;
    my $share   = "$buttons/share.png";
    my $delete  = "$buttons/trash.png";

    my $count = 0;
    my @rows = map {
	my $name          = $_;
	my $description   = div(
	    {
		-id              => "${name}_description",
		-onClick         => "Controller.edit_upload_description('$name',this)",
		-contentEditable => 'true',
	    },
	    $userdata->description($_) || 'Click to add a description'
	    );

	my $status    = $userdata->status($name) || 'complete';
	my $random_id = 'upload_'.int rand(9999);

	my ($conf_name,$conf_modified,$conf_size) = $userdata->conf_metadata($name);

	my @source_files  = $userdata->source_files($name);
	my $download_data = 
	    table({-class=>'padded-table'},
		  TR(th({-align=>'left'},
			(a({-href=>"?userdata_download=conf;track=$name"},'Configuration'))),
		     td(scalar localtime $conf_modified),
		     td("$conf_size bytes"),
		     td(a({-href    => "javascript:void(0)",
			   -onClick => "editUploadConf('$name')"},'[edit]'))
		  ),
		  TR([map { th({-align=>'left'},
			       a({-href=>"?userdata_download=$_->[0];track=$name"},$_->[0])).
				td(scalar localtime($_->[2])).
				td($_->[1],'bytes').
				td(a({-href    => "javascript:void(0)",
				      -onClick => "editUploadData('$name','$_->[0]')"},'[edit]'))
				,
		      } @source_files]));
		  
	my $go_there      = a({-href    => 'javascript:void(0)',
			       -onClick => 
				   qq(Controller.select_tab('main_page');Controller.scroll_to_matching_track("$name"))},
			      '[View track]');
	
	my $color         = $count++%2 ? 'paleturquoise': 'lightblue';

	div({-style=>"background-color:$color"},
	    div({-id=>"${name}_stat"},''),
#	    img({-src=>$share,
#		 -onMouseOver => 'GBubble.showTooltip(event,"Share with other users",0)',
#		 -onClick     => 'GBubble.showTooltip(event,"Sorry, not yet implemented",0)',
#		}),
	    img({-src     => $delete,
		 -style   => 'cursor:pointer',
		 -onMouseOver => 'GBubble.showTooltip(event,"Delete",0,100)',
		 -onClick     => "deleteUploadTrack('$name')"
		}
	    ),'&nbsp;',b($name),$go_there,br(), 
	    i($description),
	    div({-style=>'padding-left:10em'},
		b('Source files:'),
		$download_data),
	    div({-id=>"${name}_editfield"},''),
	    ($status !~ /complete/) 
	      ? div(
		div({-id=>"${random_id}_form"},'&nbsp;'),
		div({-id=>"${random_id}_status"},i($status),
		           a({-href    =>'javascript:void(0)',
			      -onClick => 
				  "Controller.monitor_upload('$random_id','$name')",
			     },'Interrupted [Resume]')
		)
	      )
	      : '',
	    )
    } @tracks;
    return join '',@rows;
}

sub userdata_import {
    my $self     = shift;
    my $html     = '';

    my $url      = url(-absolute=>1,-path_info=>1);
    $html   .= div({-id=>'import_list_start'},'');

    my $import_label  = $self->tr('IMPORT_TRACK');
    my $import_prompt = $self->tr('REMOTE_URL');
    my $remove_label  = $self->tr('REMOVE');
    my $help_link     = $self->annotation_help;
    $html            .= div({-style=>'margin-left:10pt'},
			   a({-href => "javascript:addAnUploadField('import_list_start','$url','$import_prompt','$remove_label','import','$help_link')",
			      -id   => 'import_adder',
			     },b("[$import_label]")));
    return $html;
}

sub userdata_upload {
    my $self     = shift;
    my $url      = url(-absolute=>1,-path_info=>1);

    my $html     = '';
    $html       .= div({-id=>'upload_list_start'},'');

    my $upload_label = $self->tr('UPLOAD_FILE');
    my $remove_label = $self->tr('REMOVE');
    my $new_label    = $self->tr('NEW_TRACK');
    my $from_text    = $self->tr('FROM_TEXT');
    my $from_file    = $self->tr('FROM_FILE');
    my $help_link     = $self->annotation_help;
    $html         .= p({-style=>'margin-left:10pt;font-weight:bold'},
		       'Add custom track(s):',
		       a({-href=>"javascript:addAnUploadField('upload_list_start', '$url', '$new_label',   '$remove_label', 'edit','$help_link')"},
			 "[$from_text]"),
		       a({-href=>"javascript:addAnUploadField('upload_list_start', '$url','$upload_label','$remove_label' , 'upload','$help_link')",
			  -id=>'file_adder',
			 },"[$from_file]"));
		       

    return $html;
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

sub tableize {
  my $self  = shift;
  my $array = shift;
  return unless @$array;

  my $columns = $self->data_source->global_setting('config table columns') || 3;
  my $rows    = int( @$array/$columns + 0.99 );

  my $cwidth = int(100/$columns+0.5) . '%';

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

    print CGI::header(-type=>'text/html',     
		      -cache_control =>'no-cache');
    print start_form(
		  -name     => 'configure_plugin',
		  -id       => 'configure_plugin',
		  ),
	  button(-value => $self->tr('Cancel'),
 		 -onClick=>'Balloon.prototype.hideTooltip(1)'),
	  button(-value => $self->tr('Configure_plugin'),
 		 -onClick=>'Controller.reconfigure_plugin('
                 . '"'.$self->tr('Configure_plugin').'"'
                 . qq(, "plugin:$plugin_name")
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
	my @plugin_description = $plugin->description;
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
    my $track_id      = $args{'track_id'};
    my $track_name    = $args{'track_name'};
    my $track_html    = $args{'track_html'};

    # track_type used in register_track() javascript method
    my $track_type = $args{'track_type'} || 'standard';

    my $section = $self->get_section_from_label($track_id);
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
        -charset => $self->tr('CHARSET'),
        $attachment ? ( -attachment => $attachment ) : (),
    );
}

sub slidertable {
  my $self    = shift;
  my $state   = $self->state;

  # try to avoid reopening the database -- recover segment
  # and whole segment lengths from our stored state if available
  my $span  = $self->thin_segment->length;
  my $max   = $self->thin_whole_segment->length;

  my $buttonsDir    = $self->globals->button_url;

  my $half_title = $self->unit_label(int $span/2);
  my $full_title = $self->unit_label($span);
  my $half       = int $span/2;
  my $full       = $span;
  my $fine_zoom  = $self->get_zoomincrement();

  my @lines =
    (image_button(-src     => "$buttonsDir/green_l2.gif",
		  -name=>"left $full",
		  -title   => "left $full_title",
		  -onClick => "Controller.update_coordinates(this.name)"
     ),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/green_l1.gif",-name=>"left $half",
		  -title=>"left $half_title",
		  -onClick => "Controller.update_coordinates(this.name)"
     ),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/mminus.png",
		  -name=>"zoom out $fine_zoom",
		  -style=>'background-color: transparent',
		  -title=>"zoom out $fine_zoom",
		  -onClick => "Controller.update_coordinates(this.name)"
     ),
     '&nbsp;',
     $self->zoomBar($span,$max),
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

  my ($length,$max) = @_;

  my $show   = $self->tr('Show');

  my %seen;
  my @r         = sort {$a<=>$b} $self->data_source->get_ranges();
  my @ranges	= grep {!$seen{$_}++ && $_<=$max} sort {$b<=>$a} @r,$length;

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
  @sources         = grep {$globals->data_source_show($_)} @sources;
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
    my $revert_to_defaults = shift;

    my $state       = $self->state();
    my $data_source = $self->data_source();

    my $length      = $self->thin_segment->length;
    my $slabel      = $data_source->semantic_label($label,$length);

    eval 'require Bio::Graphics::Browser2::OptionPick; 1'
        unless Bio::Graphics::Browser2::OptionPick->can('new');

    my $picker = Bio::Graphics::Browser2::OptionPick->new($self);

    my $key = $self->label2key($slabel);

    if ( $revert_to_defaults ) {
        $state->{features}{$slabel}{override_settings} = {};
    }

    my $override = $state->{features}{$slabel}{override_settings}||{};
    my $return_html = start_html();

    # truncate too-long citations
    my $cit_txt = citation( $data_source, $slabel, $self->language ) || ''; #$self->tr('NO_CITATION');

    if (my ($lim) = $slabel =~ /\:(\d+)$/) {
	$key .= " (at >$lim bp)";
    }

    $cit_txt =~ s/(.{512}).+/$1\.\.\./;
    my $citation = h4($key) . p($cit_txt);

    my $height   = $data_source->semantic_fallback_setting( $label => 'height' ,        $length)    || 5;
    my $width    = $data_source->semantic_fallback_setting( $label => 'linewidth',      $length )   || 1;
    my $glyph    = $data_source->semantic_fallback_setting( $label => 'glyph',          $length )   || 'box';
    my $stranded = $data_source->semantic_fallback_setting( $label => 'stranded',       $length);
    my $limit    = $data_source->semantic_fallback_setting( $label => 'feature_limit' , $length)    || 0;
    my $dynamic = $self->tr('DYNAMIC_VALUE');

    my @glyph_select = shellwords(
        $data_source->semantic_fallback_setting( $label => 'glyph select', $length )
	);

    @glyph_select = $glyph =~ /wiggle/ ? qw(wiggle_xyplot wiggle_density wiggle_box)
                                       : qw(arrow anchored_arrow box crossbox dashed_line diamond 
                                         dna dot dumbbell ellipse
                                         ex line primers saw_teeth segments span splice_site translation triangle
                                         two_bolts wave) unless @glyph_select;
    unshift @glyph_select,$dynamic if ref $data_source->fallback_setting($label=>'glyph') eq 'CODE';

    my %glyphs       = map { $_ => 1 } ( $glyph, @glyph_select );
    my @all_glyphs   = sort keys %glyphs;

    my $url = url( -absolute => 1, -path => 1 );
    my $reset_js = <<END;
new Ajax.Request('$url',
                  { method: 'get',
                    asynchronous: false,
                    parameters: 'action=configure_track&track=$label&track_defaults=1',
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
                    -values  => \@all_glyphs,
                    -default => ref $glyph eq 'CODE' ? $dynamic : $glyph,
                    -current => $override->{'glyph'},
                )
            )
        ),
        TR( th( { -align => 'right' }, $self->tr('BACKGROUND_COLOR') ),
            td( $picker->color_pick(
                    'bgcolor',
                    $data_source->semantic_fallback_setting( $slabel => 'bgcolor', $length ),
                    $override->{'bgcolor'}
                )
            )
        ),
        TR( th( { -align => 'right' }, $self->tr('FG_COLOR') ),
            td( $picker->color_pick(
                    'fgcolor',
                    $data_source->semantic_fallback_setting( $label => 'fgcolor', $length ),
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
            td( $picker->popup_menu(
                    -name     => 'feature_limit',
                    -values   => [ 0, 5, 10, 25, 50, 100, 200, 500, 1000 ],
                    -labels   => { 0 => $self->tr('NO_LIMIT') },
		    -current  => $override->{feature_limit},
                    -override => 1,
                    -default  => $limit,
                )
            )
        ),
        TR( th( { -align => 'right' }, $self->tr('STRANDED') ),
            td(checkbox(
                    -name    => 'stranded',
		    -override=> 1,
		    -value   => 1,
                    -checked => defined $override->{'stranded'} 
		                  ? $override->{'stranded'} 
                                  : $stranded,
		    -label   => '',
                )
            )
        ),
        TR(td({-colspan=>2},
	      button(
                    -style   => 'background:pink',
                    -name    => $self->tr('Revert'),
                    -onClick => $reset_js
	      ), br, 
	      button(
		  -name    => $self->tr('Cancel'),
		  -onClick => 'Balloon.prototype.hideTooltip(1)'
	      ),
	      button(
		  -name => $self->tr('Change'),
		  -onClick =><<END
	    Element.extend(this);
	    var ancestors    = this.ancestors();
	    var form_element = ancestors.find(function(el) {return el.nodeName=='FORM'; });
	    Controller.reconfigure_track('$label',form_element,'$slabel')
END
	      )
	   )
	)
    );
    $form .= end_form();

    $return_html
        .= table( TR( td( { -valign => 'top' }, [ $citation, $form ] ) ) );
    $return_html .= end_html();
    return $return_html;
}

# this is the content of the popup balloon that allows the user to select
# individual features by source or name
sub select_subtracks {
    my $self  = shift;
    my $label = shift;

    my $state       = $self->state();
    my $data_source = $self->data_source();

    my $select_options = $data_source->setting($label=>'select');
    my ($method,@values) = shellwords($select_options);

    my $filter = $state->{features}{$label}{filter};

    unless (exists $filter->{method} && $filter->{method} eq $method) {
	$filter->{method} = $method;
	$filter->{values} = { map {$_=>1} @values }; # all on
    }

    my @turned_on = grep {$filter->{values}{$_}} @values;

    my $return_html = start_html();
    $return_html   .= start_form(-name => 'subtrack_select_form',
				 -id   => 'subtrack_select_form');
    $return_html   .= p($self->language->tr('SHOW_SUBTRACKS')
			||'Show subtracks');
    $return_html   .= checkbox_group(-name      => "select",
				     -values    => \@values,
				     -linebreak => 1,
				     -defaults  => \@turned_on);
    $return_html .= button(-name    => 
			      $self->tr('Change'),
			   -onClick => 
			      "Controller.filter_subtrack('$label',\$('subtrack_select_form'))"
	);
    $return_html .= end_form();
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
    my $segment = $label =~  /:region$/   ? '$region'
                 :$label =~  /:overview$/ ? '$overview'
                 :'$segment';
    my $upload_id = $state->{uploadid} || $state->{userid};
    if ( $label =~ /^(http|ftp):/ ) {    # reexporting and imported track!
        $gbgff = $label;
    }
    else {
        $gbgff = url( -full => 1, -path_info => 1 );
        $gbgff .= "?gbgff=1;q=$segment;t=$labels;s=1";
        $gbgff .= ";id=$upload_id" if $labels =~ /file(:|%3A)/;
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
  my $label = $self->tr($title) || '';
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

  # IE hack -- no longer needed?
  # my $agent      = CGI->user_agent || '';
  # my $ie         = $agent =~ /MSIE/;
  # $config{tight} = undef if $ie;

  my $buttons = $self->globals->button_url;
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
  my @result =  $config{nodiv} ? (div({-style=>'float:left'},
				      $show_ctl.$hide_ctl),$content)
                :$config{tight}? (div({-style=>'float:left;position:absolute;z-index:10'},
				      $show_ctl.$hide_ctl).$break,$content)
                : div($show_ctl.$hide_ctl,$content);
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
    my $inkscape_dir = File::Spec->catfile($home,'.inkscape');
    my $gnome2_dir   = File::Spec->catfile($home,'.gnome2');
    if (-e $inkscape_dir && -w $inkscape_dir
	&&  -e $gnome2_dir   && -w $gnome2_dir) {
	return $CAN_PDF=1;
    } else {
	print STDERR
	    join(' ',
		 qq(GBROWSE NOTICE: To enable PDF generation, please enter the directory "$home"),
		 qq(and run the commands:),
		 qq("sudo mkdir .inkscape .gnome2"),
		 qq(and "sudo chown $user .inkscape .gnome2". ),
		 qq(To turn off this message add "generate pdf = 0"),
		 qq(to the [GENERAL] section of your GBrowse.conf configuration file.)
	    );
	return $CAN_PDF=0;
    }
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

1;

