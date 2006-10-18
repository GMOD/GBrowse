package Bio::Graphics::Browser::Run;
# $Id: Render.pm,v 1.4 2006-10-18 18:38:35 sheldon_mckay Exp $
#
# this library will supersedes Bio::Graphics::Browser::Util and much of
# the rendering code in the CGI scripts and Bio::Graphics::Browser

# Re: setting()
#
# Don't get confused! This object has a setting() method. There is also a
# $browser_run->config->setting() method. Thhis object's setting() method
# is used only for getting [GENERAL] information. It first queries the
# the GBrowse.conf global file, and if the setting isn't there it queries
# the current datasource-specific config object. It cannot be used to retrieve
# track-specific data.
#
# $browser_run->config->setting() returns information about the currently-active
# data source.

use strict;
use Carp 'croak','cluck';
use Bio::Graphics::Browser;

# the following are singletons which are used for web in-memory caching
my $CONFIG;
my $LANG;

# if true, turn on surrounding rectangles for debugging the image map
use constant DEBUG          => 0;
use constant DEBUG_EXTERNAL => 0;
use constant DEBUG_PLUGINS  => 0;

use constant GLOBAL_TIMEOUT => 60;  # 60 seconds to failure unless overridden in config

# probably all this stuff should go
use Bio::Graphics::Browser::PluginSet;
use Bio::Graphics::Browser::UploadSet;
use Bio::Graphics::Browser::RemoteSet;
use Bio::Graphics::Browser::PageSettings;
use Digest::MD5 'md5_hex';
use File::Path 'mkpath';
use Text::Tabs;
use Text::Shellwords;
use File::Basename 'basename','dirname';
use File::Spec;
use Carp qw(:DEFAULT croak);
use CGI qw(:standard unescape escape escapeHTML center *table *dl *TR *td);
use CGI::Toggle;
use CGI::Cookie;

use vars qw/$VERSION/;
$VERSION = 0.01;

# if you change the zoom/nav icons, you must change this as well.
use constant MAG_ICON_HEIGHT => 20;
use constant MAG_ICON_WIDTH  => 8;

# had-coded values for segment sizes
# many of these can be overridden by configuration file entries
use constant MAX_SEGMENT     => 1_000_000;
use constant MIN_SEG_SIZE         => 20;
use constant TINY_SEG_SIZE        => 2;
use constant EXPAND_SEG_SIZE      => 5000;
use constant TOO_MANY_SEGMENTS => 5_000;
use constant TOO_MANY_FEATURES => 100;
use constant TOO_MANY_REFS     => TOO_MANY_FEATURES;
use constant DEFAULT_SEGMENT => 100_000;
use constant DEFAULT_REGION_SIZE => 100_000_000;

use constant OVERVIEW_RATIO  => 1.0;    # for the time being, don't touch this -- the ratio calculation isn't working
use constant ANNOTATION_EDIT_ROWS => 25;
use constant ANNOTATION_EDIT_COLS => 100;
use constant URL_FETCH_TIMEOUT    => 5;  # five seconds max!
use constant URL_FETCH_MAX_SIZE   => 1_000_000;  # don't accept any files larger than 1 Meg
use constant MAX_KEYWORD_RESULTS  => 1_000;     # max number of results from keyword search
use constant DEFAULT_RANGES         => q(100 500 1000 5000 10000 25000 100000 200000 500000 1000000);
use constant DEFAULT_REGION_SIZES   => q(1000 5000 10000 20000);
use constant DEFAULT_FINE_ZOOM    => '10%';
use constant GBROWSE_HELP         => '/gbrowse';
use constant IMAGES               => '/gbrowse/images';
use constant JS                   => '/gbrowse/js';
use constant DEFAULT_PLUGINS      => 'FastaDumper RestrictionAnnotator SequenceDumper';
use constant BUTTONSDIR           => '/gbrowse/images/buttons';

# amount of time to remember persistent settings
use constant REMEMBER_SOURCE_TIME   => '+3M';   # 3 months
use constant REMEMBER_SETTINGS_TIME => '+1M';   # 1 month




$ENV{PATH} = '/bin:/usr/bin:/usr/local/bin';
local $CGI::USE_PARAM_SEMICOLONS = 1;
my $HAVE_SVG = eval {require GD::SVG; 1};

BEGIN {
    eval "use Apache";
    warn <<END if Apache::DBI->can('connect_on_init');
WARNING: APACHE::DBI DETECTED.
THIS WILL CAUSE THE GFF DUMP TO FAIL INTERMITTENTLY.
THIS SCRIPT DOES NOT BENEFIT FROM APACHE::DBI
END
;
};

##########################################################
# Initialization
# -- Base class for general config and rendering
# -- HTML or template specific subclasses
##########################################################

sub new {
  my $class       = shift;
  my $config_dir  = shift;
  my $html_method = shift;
  my $self       = bless {},ref $class || $class;
  $self->config_dir($self->apache_conf_dir($config_dir));
  $self->init($html_method);
  $self;
}

sub init {
  my $self = shift;
  my $method = lc shift;
  $method && $method =~ /html|template/
     or $self->fatal_error('invalid rendering method: options are HTML or template');

  $self->open_config_files;
  
  $self = "Bio::Graphics::Browser::Run::$method"->new($self);

  $self->{header}         = 0;
  $self->{html}           = 0;
  $self->{added_features} = 0;
}


##########################################################
# Session and Page Settings Management                   #
##########################################################

sub restore_session {
  my $self     = shift;
  my $globals  = $self->globals or croak "no globals!";
  my $id       = param('id');
  my $page_settings = Bio::Graphics::Browser::PageSettings->new($self,$id);
  $self->page_settings($page_settings);
}

sub update_session {
  my $self     = shift;
  my $config         = $self->config;
  my $page_settings  = $self->page_settings;

  $self->set_data_source();
  $self->update_settings();

  # Make sure that we expire the data source according to the
  # policy in globals.
  $page_settings->session->expire($config->source,
				  $config->remember_settings_time);
}

sub update_settings {
  my $settings = shift;

  $settings->{grid} = 1 unless exists $settings->{grid};  # to upgrade from older settings

  if (param('width') || param('label')) { # just looking to see if the settings form was submitted
    my @selected = split_labels (param('label'));
    $settings->{features}{$_}{visible} = 0 foreach keys %{$settings->{features}};
    $settings->{features}{$_}{visible} = 1 foreach @selected;
    $settings->{flip}                  = param('flip');
    $settings->{grid}                  = param('grid');
  }

  if (my @selected = split_labels(param('enable'))) {
    $settings->{features}{$_}{visible} = 1 foreach @selected;
  }

  if (my @selected = split_labels(param('disable'))) {
    $settings->{features}{$_}{visible} = 0 foreach @selected;
  }

  $settings->{width}  = param('width')   if param('width');
  my $divider  = $CONFIG->setting('unit_divider') || 1;

  # Update coordinates.
  local $^W = 0;  # kill uninitialized variable warning
  $settings->{ref}   = param('ref');
  $settings->{start} = param('start') if defined param('start') && param('start') =~ /^[\d-]+/;
  $settings->{stop}  = param('stop')  if defined param('stop')  && param('stop')  =~ /^[\d-]+/;
  $settings->{stop}  = param('end')   if defined param('end')   && param('end')   =~ /^[\d-]+/;
  $settings->{version} ||= param('version') || '';

  if ( (request_method() eq 'GET' && param('ref'))
       ||
       (param('span') && $divider*$settings->{stop}-$divider*$settings->{start}+1 != param('span'))
       ||
       grep {/left|right|zoom|nav|regionview\.[xy]|overview\.[xy]/} param()
     )
    {
      zoomnav($settings);
      $settings->{name} = "$settings->{ref}:$settings->{start}..$settings->{stop}";
      param(name => $settings->{name});
    }

  foreach (qw(name source plugin stp ins head
	      ks sk version)) {
    $settings->{$_} = param($_) if defined param($_);
  }
  $settings->{name} =~ s/^\s+//; # strip leading
  $settings->{name} =~ s/\s+$//; # and trailing whitespace

  if (my @features = shellwords(param('h_feat'))) {
    $settings->{h_feat} = {};
    for my $hilight (@features) {
      last if $hilight eq '_clear_';
      my ($featname,$color) = split '@',$hilight;
      $settings->{h_feat}{$featname} = $color || 'yellow';
    }
  }

  if (my @regions = shellwords(param('h_region'))) {
    $settings->{h_region} = [];
    foreach (@regions) {
      last if $_ eq '_clear_';
      $_ = "$settings->{ref}:$_" unless /^[^:]+:-?\d/; # add reference if not there
      push @{$settings->{h_region}},$_;
    }
  }

  if ($CONFIG->setting('region segment')) {
    $settings->{region_size} = param('region_size')+0             if defined param('region_size');
    $settings->{region_size} = $CONFIG->setting('region segment') unless defined $settings->{region_size};
  } else {
    delete $settings->{region_size};
  }

  if (my @external = param('eurl')) {
    my %external = map {$_=>1} @external;
    foreach (@external) {
      warn "eurl = $_" if DEBUG_EXTERNAL;
      next if exists $settings->{features}{$_};
      $settings->{features}{$_} = {visible=>1,options=>0,limit=>0};
      push @{$settings->{tracks}},$_;
    }
    # remove any URLs that aren't on the list
    foreach (keys %{$settings->{features}}) {
      next unless /^(http|ftp):/;
      delete $settings->{features}{$_} unless exists $external{$_};
    }
  }

  # the "q" request overrides name, ref, and h_feat
  if (my @q = param('q')) {
    delete $settings->{$_} foreach qw(name ref h_feat h_region);
    $settings->{q} = [map {split /[+-]/} @q];
  }

  if (param('revert')) {
    warn "resetting defaults..." if DEBUG;
    set_default_tracks($settings);
  }

  elsif (param('reset')) {
    %$settings = ();
    #    Delete_all();
    default_settings($settings);
  }

  elsif (param($CONFIG->tr('Adjust_Order')) && !param($CONFIG->tr('Cancel'))) {
    adjust_track_options($settings);
    adjust_track_order($settings);
  }

  # restore the visibility of the division sections
  # using transient cookies
  for my $div (grep {/^div_visible_/} CGI::cookie()) {
    warn "div = $div";
    my ($section)   = $div =~ /^div_visible_(\w+)/ or next;
    my $visibility  = CGI::cookie($div);
    warn "$div = $visibility";
    $settings->{section_visible}{$section} = $visibility;
  }
}

sub page_settings {
  my $self = shift;
  my $d    = $self->{page_settings};
  $self->{page_settings} = shift if @_;
  $d;
}

##########################################################
# General Configuration                                  #
##########################################################

# set the data source
# it may come from any of several places
# - from the legacy "source" CGI parameter -- this causes a redirect to gbrowse/source/
# - from the legacy "/source" path info -- this causes a redirect to gbrowse/source/
# - from the "/source/" path info
# - from the user's saved session
# - from the default source
sub set_data_source {
  my $self = shift;
  my $config = $self->config;

  # list of all the possible sources
  my @sources = sort $config->sources;
  my %sources = map {$_=>1} @sources;

  my $source = param('source') || param('src') || path_info();
  $source    =~ s!^/+!!;  # get rid of leading & trailing / from path_info()
  $source    =~ s!/+$!!;

  # not present in the URL, or CGI parameters so get it from the session
  $source      ||=  $self->page_settings->source;
  $source      ||= $self->setting('default source');

  # not present there so get it from the first configured source
  $source      ||= $sources[0];

  # check that this is a correct source
  unless ($sources{$source}) {
    $self->warning($config->tr('INVALID_SOURCE',$source));
    $source = $self->setting('default source') || $sources[0];
  }

  # this call checks whether our path_info() is consistent with the
  # provided source. It may cause a redirect and exit!!!
  $self->redirect_legacy_url($source);

  # now set the source
  $config->source($source);                # in the current config
  $self->page_settings->source($source);   # in the page settings
}


sub config { return $CONFIG }
sub lang   { return $LANG   }

sub open_config_files {
  my $self   = shift;
  my $dir    = $self->config_dir;

  $CONFIG ||= Bio::Graphics::Browser->new;
  $LANG   ||= Bio::Graphics::Browser::I18n->new("$dir/languages");

  # don't use ugly-looking globals unless we have to
  my $conf = $self->config;
  my $lang = $self->lang;

  $conf->read_configuration($dir) or croak "Can't read configuration files: $!";
  $self->set_language;
  $conf->language($lang);
  $conf->dir($dir);
  $conf->clear_cache();  # remove cached information

  my $globals = Bio::Graphics::FeatureFile->new(-file=>"$dir/GBrowse.conf")
    or croak "no GBrowse.conf global config file found";
  $self->globals($globals);
}

sub set_language {
  my $self = shift;
  my $conf = $self->config;
  my $lang = $self->lang;
  my $default_language   = $conf->setting('language');
  my $accept             = http('Accept-language') || '';
  my @languages          = $accept =~ /([a-z]{2}-?[a-z]*)/ig;
  push @languages,$default_language if $default_language;
  return unless @languages;
  $lang->language(@languages);
}

# pass through source to the config object
sub source { shift->config->source(@_) }

# REMOVE FROM BROWSER.pm
sub remember_settings_time {
  my $self = shift;
  return $self->setting('remember settings time') || REMEMBER_SETTINGS_TIME;
}

sub config_dir {
  my $self = shift;
  my $d    = $self->{config_dir};
  $self->{config_dir} = shift if @_;
  $d;
}

sub globals {
  my $self = shift;
  my $d    = $self->{globals};
  $self->{globals} = shift if @_;
  $d;
}


# setting will search in globals first and then in currently configured source
sub setting {
  my $self   = shift;
  my $option = shift;
  my $global = $self->globals or return;
  my $result = $global->setting(general => $option);
  return $result if defined $result;
  my $conf   = $self->config or return;
  return $conf->setting(general => $option);
}

# REMOVE FROM BROWSER.pm
sub tmpdir {
  my $self = shift;
  my $path = shift || '';

  my ($tmpuri,$tmpdir) = shellwords($self->setting('tmpimages'))
    or die "no tmpimages option defined, can't generate a picture";

  $tmpuri .= "/$path" if $path;

  if ($ENV{MOD_PERL} ) {
    my $r          = $self->modperl_request();
    my $subr       = $r->lookup_uri($tmpuri);
    $tmpdir        = $subr->filename;
    my $path_info  = $subr->path_info;
    $tmpdir       .= $path_info if $path_info;
  } elsif ($tmpdir) {
    $tmpdir .= "/$path" if $path;
  }
  else {
    $tmpdir = "$ENV{DOCUMENT_ROOT}/$tmpuri";
  }

  # we need to untaint tmpdir before calling mkpath()
  return unless $tmpdir =~ /^(.+)$/;
  $path = $1;

  mkpath($path,0,0777) unless -d $path;
  return ($tmpuri,$path);
}

sub apache_conf_dir {
  my $self    = shift;
  my $default = shift;
  if (my $request = $self->modperl_request()) {
    my $conf  = $request->dir_config('GBrowseConf') or return $default;
    return $conf if $conf =~ m!^/!;                # return absolute
    return (exists $ENV{MOD_PERL_API_VERSION} &&
	    $ENV{MOD_PERL_API_VERSION} >= 2)
      ? Apache2::ServerUtil::server_root() . "/$conf"
      : Apache->server_root_relative($conf);
  }
  return $default;
}

=pod
=head2 get_source
 
 Title   : get_source 
 Usage   : my $source = $render->get_source;
           my ($new_source, $old_source) = $render->get_source;
 Function: gets the source from CGI parameters or cookie;
           sets the source value to the new source 
 Returns : a string or a list 
 Args    : none

=cut

sub get_source {
  my $self = shift;
  my $source;
  my $new_source = param('source') || param('src') || path_info();
  $new_source =~ s!^/+!!;
  $new_source =~ s!/+$!!;
  # gbrowse_syn expects a list
  if ( wantarray ) {
    my $old_source = cookie('sbrowse_source')
	unless $new_source && param('.cgifields');
    $source = $new_source || $old_source;
    $source ||= $self->source;
    
    # the default, whatever it is    $self->source($source);
    return ( $source, $old_source );
  } 
  # otherwise just the source
  else {
    $self->source($new_source) if defined $new_source;
    return $new_source;
  }
}


#################################################################
# HTTP functions                
#################################################################

sub redirect_legacy_url {
  my $self          = shift;
  my $source        = shift;

  if ($source && path_info() ne "/$source/") {

    my $q = new CGI '';
    if (request_method() eq 'GET') {
      foreach (param()) {
	next if $_ eq 'source';
	$q->param($_=>param($_)) if defined param($_);
      }
    }

    # This is infinitely more difficult due to horrible bug in Apache version 2
    # It is fixed in CGI.pm versions 3.11 and higher, but this version is not guaranteed
    # to be available.
    my ($script_name,$path_info) = _broken_apache_hack();
    my $query_string = $q->query_string;
    my $protocol     = $q->protocol;

    my $new_url      = $script_name;
    $new_url        .= "/$source/";
    $new_url        .= "?$query_string" if $query_string;

    print redirect(-uri=>$new_url,-status=>"301 Moved Permanently");
    exit 0;
  }
}

#################################################################
# HTML rendering -- General 
#################################################################

=pod

=head2 show_examples
 
 Title   : show_examples 
 Usage   : my $examples = $render->show_examples;
 Function: gets a formatted list of examples searches
          specific to the current data source 
 Returns : an html-formatted string 
 Args    : an optional list of '=' delimited key/value pairs for the url

=cut

# species-specific landmark examples
sub show_examples {
  my $self     = shift;
  my $params   = join ';', '', @_;
  $params ||= '';
  my $examples = $self->setting('examples') or return;
  my @examples = shellwords($examples);
  my $source   = $self->source || $self->get_source;
  my @urls = map { a( { -href => "?name=" . escape($_) . $params }, $_ ) } @examples;
  return b( $self->tr('Examples') ) . ': ' . join( ', ', @urls ) . ". ";
}

=pod

=head2 toggle
 
 Title   : toggle 
 Usage   : my $toggle_section = $self->toggle( $title, @body );
 Function: creates a show/hide section via CGI::Toggle 
 Returns : html-formatted string 
 Args    : The section title and a list of strings for section content

=cut

sub toggle {
  my $self = shift;
  my ($tconf,$id, $section_head,@body);
  if (ref $_[0] eq 'HASH') {
    ($tconf,$id, $section_head,@body) eq @_;
  }
  else {
    ($tconf,$id, $section_head,@body) eq ({},@_);
  }

  my ($label) = $self->tr($section_head) || ($section_head);
  my $state = $self->section_setting($section_head);
  my $on = $state eq 'open';

  # config as argument overrides section_setting
  $tconf->{on} ||= $on;

  return toggle_section( $tconf, $id, b($label), @body );
}

=pod

=head2 unit_label
 
 Title   : unit_label 
 Usage   : my $formatted_number = $render->unit_label(100000000);
 Function: formats a number for DNA sequence with the appropriate unit label 
 Returns : a formatted string 
 Args    : an integer

=cut

sub unit_label {
  my ( $self, $value ) = @_;
  my $unit    = $self->setting('units')        || 'bp';
  my $divider = $self->setting('unit_divider') || 1;
  $value /= $divider;
  my $abs = abs($value);
  my $label;
        $label = $abs >= 1e9 ? sprintf( "%.4g G%s", $value / 1e9, $unit )
      : $abs >= 1e6  ? sprintf( "%.4g M%s", $value / 1e6, $unit )
      : $abs >= 1e3  ? sprintf( "%.4g k%s", $value / 1e3, $unit )
      : $abs >= 1    ? sprintf( "%.4g %s",  $value,       $unit )
      : $abs >= 1e-2 ? sprintf( "%.4g c%s", $value * 100, $unit )
      : $abs >= 1e-3 ? sprintf( "%.4g m%s", $value * 1e3, $unit )
      : $abs >= 1e-6 ? sprintf( "%.4g u%s", $value * 1e6, $unit )
      : $abs >= 1e-9 ? sprintf( "%.4g n%s", $value * 1e9, $unit )
      : sprintf( "%.4g p%s", $value * 1e12, $unit );
  if (wantarray) {
    return split ' ', $label;
  }
  else {
    return $label;
  }
}

=pod

=head2 get_zoomincrement
 
 Title   : get_zoomincrement 
 Usage   : my $zoom_inc = $render->get_zoomincrement;
 Function: get the zoom increment for the pan buttons 
 Returns : a percent value 
 Args    : none

=cut

sub get_zoomincrement {
  my $self = shift;
  my $zoom = $self->setting('fine zoom') || DEFAULT_FINE_ZOOM;
  $zoom;
}

=pod

=head2 split_labels
 
 Title   : split_labels 
 Usage   : my @labels = $render->split_labels(param('label'));
 Function: splits urls into a list 
 Returns : a list 
 Args    : a scalar or list

=cut

sub split_labels {
  my $self = shift;
  map { /^(http|ftp|das)/ ? $_ : split /[+-]/ } @_;
}

=pod

=head2 bookmark_link
 
 Title   : bookmark_link 
 Usage   : my $query_url = $render->bookmark_link($settings);
 Function: create a URL for bookmarking this saved session 
 Returns : a formatted URL 
 Args    : a hashref containing page settings

=cut

sub bookmark_link {
  my ( $self, $settings ) = @_;
  my $q    = new CGI('');
  my @keys = qw(start stop ref width version flip);
  foreach (@keys) {
    $q->param( -name => $_, -value => $settings->{$_} );
  }    # handle selected features slightly differently
  my @selected = grep {
    $settings->{features}{$_}{visible} && !/^(file|ftp|http):/;
  }
  @{ $settings->{tracks} };
  $q->param( -name => 'label', -value => join( '-', @selected ) );
  
  # handle external urls
  my @url = grep {/^(ftp|http):/} @{$settings->{tracks}};
  $q->param( -name => 'eurl',     -value => \@url );
  $q->param( -name => 'h_region', -value => $settings->{h_region} )
      if $settings->{h_region};
  my @h_feat
      = map {"$_\@$settings->{h_feat}{$_}"} keys %{ $settings->{h_feat} };
  $q->param( -name => 'h_feat', -value => \@h_feat ) if @h_feat;
  $q->param( -name => 'id',   -value => $settings->{id} );
  $q->param( -name => 'grid', -value => $settings->{grid} );
  return "?" . $q->query_string();
}

=pod

=head2 zoomnav
 
 Title   : zoomnav 
 Usage   : $render->zoomnav($settings);
 Function: responds to zoom/pan requests 
 Returns : nothing 
 Args    : a hashref containing page settings

=cut

sub zoomnav {
  my ( $self, $settings ) = @_;
  return unless $settings->{ref};
  my $start   = $settings->{start};
  my $stop    = $settings->{stop};
  my $span    = $stop - $start + 1;
  my $divisor = $self->setting( general => 'unit_divider' ) || 1;
  warn "before adjusting, start = $start, stop = $stop, span=$span" if DEBUG;
  my $flip = $settings->{flip} ? -1 : 1;

  # get zoom parameters
  my $selected_span  = param('span');
  my ($zoom) = grep {/^zoom (out|in) \S+/} param();
  my ($nav)  = grep {/^(left|right) \S+/} param();
  my $overview_x      = param('overview.x');
  my $regionview_x    = param('regionview.x');
  my $regionview_size = $settings->{region_size};
  my $seg_min         = param('seg_min');
  my $seg_max         = param('seg_max');
  my $segment_length  = $seg_max - $seg_min + 1
      if defined $seg_min && defined $seg_max;
  my $zoomlevel = $self->unit_to_value($1)
      if $zoom && $zoom =~ /((?:out|in) .+)\.[xy]/;
  my $navlevel = $self->unit_to_value($1)
      if $nav && $nav =~ /((?:left|right) .+)/;

  if ( defined $zoomlevel ) {
    warn "zoom = $zoom, zoomlevel = $zoomlevel" if DEBUG;
    my $center = int( $span / 2 ) + $start;
    my $range = int( $span * ( 1 - $zoomlevel ) / 2 );
    $range = 1 if $range < 1;
    ( $start, $stop ) = ( $center - $range, $center + $range - 1 );
  }
  elsif ( defined $navlevel ) {
    $start += $flip * $navlevel;
    $stop  += $flip * $navlevel;
  }
  elsif ( defined $overview_x && defined $segment_length ) {
    my @overview_tracks = grep { $settings->{features}{$_}{visible} }
        $self->config->overview_tracks;
    my ( $padl, $padr ) = $self->overview_pad( \@overview_tracks );
    $settings->{width} ||= 800;
    my $overview_width = ( $settings->{width} * OVERVIEW_RATIO );

    # adjust for padding in pre 1.6 versions of bioperl
    $overview_width -= ($padl+$padr) unless Bio::Graphics::Panel->can('auto_pad');
    my $click_position = $seg_min + $segment_length * ( $overview_x - $padl )
        / $overview_width;
    $span = $self->setting('DEFAULT_SEGMENT')
        if $span > $self->setting('MAX_SEGMENT');
    $start = int( $click_position - $span / 2 );
    $stop  = $start + $span - 1;
  }
  elsif ( defined $regionview_x ) {
    my ( $regionview_start, $regionview_end )
        = get_regionview_seg( $settings, $start, $stop );
    my @regionview_tracks = grep { $settings->{features}{$_}{visible} }
        $self->self->regionview_tracks;
    my ( $padl, $padr ) = $self->overview_pad( \@regionview_tracks );
    my $regionview_width
        = ( $settings->{width} * OVERVIEW_RATIO );

    # adjust for padding in pre 1.6 versions of bioperl
    $regionview_width -= ($padl+$padr) unless Bio::Graphics::Panel->can('auto_pad');
    my $click_position
        = $regionview_size * ( $regionview_x - $padl ) / $regionview_width;
    $span = $self->setting('DEFAULT_SEGMENT')
        if $span > $self->setting('MAX_SEGMENT');
    $start = int( $click_position - $span / 2 + $regionview_start );
    $stop  = $start + $span - 1;
  }
  elsif ($selected_span) {
    warn "selected_span = $selected_span" if DEBUG;
    my $center = int( ( $span / 2 ) ) + $start;
    my $range  = int( ($selected_span) / 2 );
    $start = $center - $range;
    $stop  = $start + $selected_span - 1;
  }
  warn
      "after adjusting for navlevel, start = $start, stop = $stop, span=$span"
      if DEBUG;

  # to prevent from going off left end
  if (defined $seg_min && $start < $seg_min) {
    warn "adjusting left because $start < $seg_min" if DEBUG;
    ( $start, $stop ) = ( $seg_min, $seg_min + $stop - $start );
  } 
  # to prevent from going off right end
  if (defined $seg_max && $stop > $seg_max) {
    warn "adjusting right because $stop > $seg_max" if DEBUG;
    ( $start, $stop ) = ( $seg_max - ( $stop - $start ), $seg_max );
  } 
  # to prevent divide-by-zero errors when zoomed down to a region < 2 bp  
  $stop  = $start + ($span > 4 ? $span - 1 : 4) if $stop <= $start+2;
  warn "start = $start, stop = $stop\n" if DEBUG;
  $divisor = 1 if $divisor =~ /[^0-9]/;;
  $settings->{start} = $start / $divisor;
  $settings->{stop}  = $stop / $divisor;
}

=pod

=head2 unit_to_value
 
 Title   : unit_to_value 
 Usage   : my $value = $render->unit_to_value($number);
 Function: converts formatted numbers to the appropriate
           absolute number (e.g. 1 kbp -> 1000) 
 Returns : a number 
 Args    : a formatted number

=cut

sub unit_to_value {
  my ( $self, $string ) = @_;
  my $sign = $string =~ /out|left/ ? '-' : '+';
  my ( $value, $units ) = $string =~ /([\d.]+) ?(\S+)/;

  return unless defined $value;

  $value /= 100 if $units eq '%';

  # percentage;
  $value *= 1000 if $units =~ /kb/i;
  $value *= 1e6  if $units =~ /mb/i;
  $value *= 1e9  if $units =~ /gb/i;
  return "$sign$value";
}

#################################################################
# HTML rendering -- HTML/template specific methods
# Must be in a subclass so that template
# and non-template versions coexist
# template methods are in Bio::Graphics::Run::template
# non-template methods are in Bio::Graphics::Run::html
#################################################################

sub template_error {shift->fatal_error('Not implemented')}
sub render {shift->fatal_error('Not implemented')}
sub finish {shift->fatal_error('Not implemented')}
sub print_top {shift->fatal_error('Not implemented')}
sub print_bottom {shift->fatal_error('Not implemented')}
sub source_menu {shift->fatal_error('Not implemented')}
sub slidertable {shift->fatal_error('Not implemented')}
sub zoomBar {shift->fatal_error('Not implemented')}
sub make_overview {shift->fatal_error('Not implemented')}
sub overview_panel {shift->fatal_error('Not implemented')}

##################################################################
# Bio::DB::GFF Utilities
##################################################################

=pod

=head2 current_segment
 
 Title   : current_segment 
 Usage   : my $segment = $render->current_segment;
           $render->current_segment($my_segment);
 Function: setter/getter for the current segment 
 Returns : a Bio::DB::GFF::RelSegment object, if one exists 
 Args    : a Bio::DB::GFF::RelSegment object 
 Note    : the alias 'segment' also works

=cut

*segment = \&current_segment;

sub current_segment {
  my ( $self, $segment ) = @_;
  $self->{current_segment} = $segment if $segment;
  $self->{current_segment} ||= $self->{segment};
  return $self->{current_segment};
}

=pod

=head2 whole_segment
 
 Title   : whole_segment 
 Usage   : my $whole_segment = $render->whole_segment;
 Function: returns a segment object for the entire reference sequence 
 Returns : a Bio::DB::GFF::RelSegment object 
 Args    : none

=cut

sub whole_segment {
  my $self = shift;
  return $self->{whole_segment} if $self->{whole_segment};
  my $segment = $self->current_segment;
  my $factory = $segment->factory;

  # the segment class has been deprecated, but we still must support it
  my $class   = eval {$segment->seq_id->class} || eval{$factory->refclass};
  ( $self->{whole_segment} ) = $factory->segment(
						 -class => $class,
						 -name  => $segment->seq_id
						 );
  $self->{whole_segment} ||= $segment;
  
  # just paranoia
  return $self->{whole_segment};
}

=pod

=head2 resize
 
 Title   : resize 
 Usage   : $render->resize;
 Function: truncate the segment to fit within min and max segment boundaries 
 Returns : nothing 
 Args    : none

=cut

sub resize {
  my $self          = shift;
  my $segment       = $self->current_segment;
  my $whole_segment = $self->whole_segment;
  my $divider       = $self->setting('unit_divider') || 1;
  my $min_seg_size  = $self->setting('min segment')  || MIN_SEG_SIZE;
  $min_seg_size /= $divider;

  my ( $new_start, $new_stop, $fix ) = ( $segment->start, $segment->end, 0 );

  if ( $segment->length < $min_seg_size ) {
    my $resize = $min_seg_size;
    my $middle = int( ( $segment->start + $segment->end ) / 2 );
    $new_start = $middle - int( $resize / 2 );
    $new_stop  = $middle + int( $resize / 2 );
    $fix++;
  }

  if ( $segment->start < $whole_segment->start ) {
    $new_start = $whole_segment->start;
    $fix++;
  }
  elsif ( $segment->start > $whole_segment->end ) {
    $new_start = $whole_segment->end - $min_seg_size;
    $fix++;
  }

  if ( $segment->end > $whole_segment->end ) {
    $new_stop = $whole_segment->end;
    $fix++;
  }
  elsif ( $segment->end < $whole_segment->start ) {
    $new_stop = $whole_segment->start + $min_seg_size;
    $fix++;
  }    
  
  $new_start = $whole_segment->start if $new_start < $whole_segment->start;
  $new_stop  = $whole_segment->end   if $new_stop > $whole_segment->end;
  my $new_seg = $segment->factory->segment(
    -name     => $segment->seq_id,
    -start    => $new_start,
    -end      => $new_stop,
    -absolute => 1
  );
  $self->current_segment($new_seg);
}

=pod

=head2 is_search
 
 Title   : is_search 
 Usage   : my $is_search = 1 if $render_is_search;
 Function: returns true if this is an active search 
 Returns : 
 Args    :

=cut

sub is_search {
  my ( $self, $page_settings ) = @_;
  return 1 if param();
  return 1 if $self->setting('initial landmark') && !$page_settings->{name};
  return 1 unless $self->setting('no autosearch');
  return undef;
}

=pod

=head2 features2segments
 
 Title   : features2segments 
 Usage   : my $segments = $render->features2segments(\@features,$database)
 Function: converts a list of feature objects to segment objects 
 Returns : an array ref of segment opjects 
 Args    : an array ref of feature objects and a database_handle;

=cut

sub features2segments {
  my ( $self, $features, $db ) = @_;
  my $refclass = $self->setting('reference class') || 'Sequence';
  $db ||= open_database();
  my @segments = map {
    my $version = eval { $_->isa('Bio::SeqFeatureI') ? undef: $_->version };
    $db->segment(
      -class    => $refclass,
      -name     => $_->ref,
      -start    => $_->start,
      -stop     => $_->end,
      -absolute => 1,
      defined $version ? ( -version => $version ) : ()
        )
  } @$features;
  warn "segments = @segments\n" if DEBUG;
  \@segments;
}

=pod

=head2 get_features
 
 Title   : get_features 
 Usage   : Function: 
 Returns : an array ref of feature objects 
 Args    : config hashref, database handle

=cut

sub get_features {
  my ( $self, $settings, $db ) = @_;
  $db ||= open_database();
  unless ($db) {
    $self->fatal_error(
      "ERROR: Unable to open database",
      $self->setting('description'),
      pre($@)
    );
  }
  eval { $db->biosql->version( $settings->{version} ) };

  # if no name is specified but there is a "initial landmark" defined in the
  # config file, then we default to that.  
  $settings->{name} ||= $self->setting('initial landmark')
      if defined $self->setting('initial landmark') && !defined $settings->{q};

  my @features = $self->lookup_features_from_db( $db, $settings );

  # sort of hacky way to force keyword search on wildcards  
  if (defined $settings->{name} && $settings->{name} =~ /[*?]/ ){ 
    my $searchterm = $settings->{name};
        push @features, do_keyword_search($searchterm)
        if length $searchterm > 0;
    } 
   
  # h'mmm.  Couldn't find the feature.  See if it is in an uploaded file.
  @features    = $self->lookup_features_from_external_sources($settings,$settings->{name}, undef ) 
      unless @features;

  return \@features;
}


=pod

=head2 lookup_features_from_db
 
 Title   : lookup_features_from_db 
 Usage   : my $segment = $render->lookup_features_from_db($database,$settings);
 Function: looks up segments in the database 
 Returns : a segment object 
 Args    : a database handle, a config hashref

=cut

sub lookup_features_from_db {
  my ( $self, $db, $settings ) = @_;
  my @segments;
  warn
      "name = $settings->{name}, ref = $settings->{ref}, start = $settings->{start}, "
      . "stop = $settings->{stop}, version = $settings->{version}"
      if DEBUG;

  my $divisor  = $self->setting( general => 'unit_divider' )     || 1;
  my $padding  = $self->setting( general => 'landmark_padding' ) || 0;
  my $too_many = $self->setting('TOO_MANY_SEGMENTS');

  if ( my $name = $settings->{name} ) {
    warn "looking up by name: name = $name" if DEBUG;
    @segments = $self->name2segments( $name, $db, $too_many );
  }
  elsif ( ( my $names = $settings->{q} ) && ref $settings->{q} ) {
    warn "looking up by query: q = $names" if DEBUG;
    my $max = $too_many / @$names;
    @segments = map { $self->name2segments( $_, $db, $max ) } @$names;
  }
  elsif ( my $ref = $settings->{ref} ) {
    my @argv = ( -name => $ref );
    push @argv, ( -start => $settings->{start} * $divisor )
        if defined $settings->{start};
    push @argv, ( -end => $settings->{stop} * $divisor )
        if defined $settings->{stop};
    warn "looking up by @argv" if DEBUG;
    @segments = $db->segment(@argv);
  } 
  # expand by a bit if padding is requested
  # THIS CURRENTLY ISN'T WORKING PROPERLY
  if (@segments == 1 && $padding > 0 && !$settings->{name} ){ 
    $segments[0] = $segments[0]->subseq( -$padding, $segments[0]->length + $padding );
  } 
  # some segments are not going to support the absolute() method
  # if they come out of BioPerl  
  eval {$_->absolute(1)} foreach @segments;
  return unless @segments;

  # Filter out redundant segments; this can happen when the same basic feature
  # ia present under several names, such as "genes" and "frameworks"
  my %seenit;
  my $version = eval { $_->isa('Bio::SeqFeatureI') ? undef: $_->version };
  $version ||= 0;
  @segments = grep { !$seenit{ $_->seq_id, $_->start, $_->end, $version }++ }
  @segments;
  return @segments if @segments > 1;

  # this prevents any confusion over (ref,start,stop) and (name) addressing.  $settings->{ref}   = $segments[0]->seq_id;
  $settings->{start} = $segments[0]->start / $divisor;
  $settings->{stop}  = $segments[0]->end / $divisor;
 
  return $segments[0];
}

=pod

=head2 lookup_features_from_external_sources
 
 Title   : lookup_features_from_external_sources 
 Usage   : my @feats = $render->lookup_features_from_external_sources($settings,$searchterm);
 Function: get a list of external features matching a search term 
 Returns : a list of feature objects 
 Args    : a settings hashref, a string

=cut

sub lookup_features_from_external_sources {
  my ( $self, $settings, $searchterm ) = @_;
  return unless my $uploads = $self->setting('UPLOADED_SOURCES');
 
 my @uploaded_files = map { $uploads->feature_file($_) }
  grep { $settings->{features}{$_}{visible} } $uploads->files;

  for my $file (@uploaded_files) {
    next unless $file->can('get_feature_by_name');
    my @features = $file->get_feature_by_name($searchterm);
    return @features if @features;
  } 
  # No exact match.  Try inexact match.
  my $max_keywords = $self->setting('keyword search max')|| $self->setting('MAX_KEYWORD_RESULTS');

  for my $file (@uploaded_files) {
    next unless $file->can('search_notes');
    my @matches = $file->search_notes( $searchterm, $max_keywords );
    return map {
      my ( $feature, $description, $score ) = @$_;
      Bio::Graphics::Feature->new(
				  -name  => $feature->display_name,
				  -type  => $description,
				  -score => $score,
				  -ref   => $feature->ref,
				  -start => $feature->start,
				  -end   => $feature->end
				  )
	} @matches if @matches;
  }
  return;
}

=pod

=head2 do_keyword_search
 
 Title   : do_keyword_search 
 Usage   : my @feats = $render->do_keyword_search($searchterm,$database);
 Function: lookup up features in the database that match the search term 
 Returns : a list of features 
 Args    : a keyword, a database handle

=cut

sub do_keyword_search {
  my ( $self, $searchterm, $db ) = @_;
  $db ||= open_database();

  # if they wanted something specific, don't give them non-specific results.
  return if $searchterm =~ /^[\w._-]+:/;

  # Need to untaint the searchterm.  We are very lenient about
  # what is accepted here because we wil be quote-metaing it later.
  $searchterm =~ /([\w .,~!@\#$%^&*()-+=<>?\/]+)/;
  $searchterm = $1;
  my $max_keywords = $self->setting('keyword search max')
      || $self->setting('MAX_KEYWORD_RESULTS');
  my @matches = $db->search_notes( $searchterm, $max_keywords );
  my @results;

  for my $r (@matches) {
    my ( $name, $description, $score ) = @$r;
    my ($seg) = $db->segment($name) or next;
    push @results,
    Bio::Graphics::Feature->new(
				-name    => $name,
				-class   => eval { $name->class } || undef,
				-type    => $description,
				-score   => $score,
				-ref     => $seg->abs_ref,
				-start   => $seg->abs_start,
				-end     => $seg->abs_end,
				-factory => $db
				);
  }

  return @results;
}

=pod

=head2 make_cookie
 
 Title   : make_cookie 
 Usage   : my $cookie = $render->make_cookie($key => $value);
 Function: bake a fresh cookie 
 Returns : a cookie 
 Args    : key, value

=cut


########################################################
# Things that might be utils and/or
# things migrated from Bio::Graphics::Browser::Util
########################################################

sub modperl_request {
  my $self = shift;
  return unless $ENV{MOD_PERL};
  (exists $ENV{MOD_PERL_API_VERSION} &&
   $ENV{MOD_PERL_API_VERSION} >= 2 ) ? Apache2::RequestUtil->request
                                     : Apache->request;
}

# workaround for broken Apache 2 and CGI.pm <= 3.10
sub _broken_apache_hack {
  my $raw_script_name = $ENV{SCRIPT_NAME} || '';
  my $raw_path_info   = $ENV{PATH_INFO}   || '';
  my $uri             = $ENV{REQUEST_URI} || '';

   ## dgg patch; need for what versions? apache 1.x; 
  if ($raw_script_name =~ m/$raw_path_info$/) {
    $raw_script_name =~ s/$raw_path_info$//;
  }

  my @uri_double_slashes  = $uri =~ m^(/{2,}?)^g;
  my @path_double_slashes = "$raw_script_name $raw_path_info" =~ m^(/{2,}?)^g;

  my $apache_bug      = @uri_double_slashes != @path_double_slashes;
  return ($raw_script_name,$raw_path_info) unless $apache_bug;

  my $path_info_search = $raw_path_info;
  # these characters will not (necessarily) be escaped
  $path_info_search    =~ s/([^a-zA-Z0-9$()\':_.,+*\/;?=&-])/uc sprintf("%%%02x",ord($1))/eg;
  $path_info_search    = quotemeta($path_info_search);
  $path_info_search    =~ s!/!/+!g;
  if ($uri =~ m/^(.+)($path_info_search)/) {
    return ($1,$2);
  } else {
    return ($raw_script_name,$raw_path_info);
  }
}

sub make_cookie {
  my $self = shift;
  my ( $name, $val ) = @_;
  my $cookie = cookie(
    -name  => $name,
    -value => $val
  );
  return $cookie;
}

sub error {
  my $self = shift;
  my @msg = @_;
  cluck "@_" if DEBUG;
  print_top();
  print h2({-class=>'error'},@msg);
}

sub fatal_error {
  my $self = shift;
  my @msg = @_;
  print_header( -expires => '+1m' );
    $CONFIG->template->process(
        'error.tt2',
			       {   server_admin  => $ENV{SERVER_ADMIN},
            error_message => join( "\n", @msg ),
				 }
        )
        or warn $CONFIG->template->error();
  exit 0;
}

sub early_error {
  my $self = shift;
  my $lang = shift;
  my $msg  = shift;
  $msg     = $lang->tr($msg);
  warn "@_" if DEBUG;
  local $^W = 0;  # to avoid a warning from CGI.pm                                                                                                                                                               
  print_header(-expires=>'+1m');
  my @args = (-title  => 'GBrowse Error');
  push @args,(-lang=>$lang->language);
  print start_html();
  print b($msg);
  print end_html;
  exit 0;
}

1;
