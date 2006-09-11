package Bio::Graphics::Browser::Run;

# this supersedes Bio::Graphics::Browser::Util and much of the rendering code in
# the CGI scripts and Bio::Graphics::Browser

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
use CGI qw(:standard);

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

sub new {
  my $class      = shift;
  my $config_dir = shift;
  my $self       = bless {},ref $class || $class;
  $self->config_dir($self->apache_conf_dir($config_dir));
  $self->init;
  $self;
}

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

sub init {
  my $self = shift;
  $self->open_config_files;

  # initialize some variables
  $self->{header}         = 0;
  $self->{html}           = 0;
  $self->{added_features} = 0;
}

######################################################################
# settings
######################################################################

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

sub page_settings {
  my $self = shift;
  my $d    = $self->{page_settings};
  $self->{page_settings} = shift if @_;
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
# HTML rendering -- move into a subclass so that template
# and non-template versions coexist
# these versions are for the non-template version
#################################################################
sub render {
  my $self   = shift;
}

sub finish {
  my $self   = shift;
  $self->$page_settings->flush;
}

sub print_top {
  my $self   = shift;
  my ($title,$reset_all) = @_;

  local $^W = 0;  # to avoid a warning from CGI.pm

  my $config = $self->config;

  my $js = $config->setting('js')||JS;
  my @scripts = {src=>"$js/buttons.js"};
  if ($config->setting('autocomplete')) {
    push @scripts,{src=>"$js/$_"} foreach qw(yahoo.js dom.js event.js connection.js autocomplete.js);
  }

  print_header(-expires=>'+1m');
  my @args = (-title => $title,
	      -style  => {src=>$config->setting('stylesheet')},
	      -encoding=>$config->tr('CHARSET'),
	     );
  push @args,(-head=>$config->setting('head'))    if $config->setting('head');
  push @args,(-lang=>($config->language_code)[0]) if $config->language_code;
  push @args,(-script=>\@scripts);
  push @args,(-reset_toggle   => 1)               if $reset_all;
  print start_html(@args) unless $self->{html}++;
}

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

sub warning {
  my $self = shift;
  my @msg  = @_;
  cluck "@_" if DEBUG;
  $self->print_top();
  print h2({-class=>'error'},@msg);
}

sub template_error {
  my $self = shift;
  my @msg = @_;

  my $config = $self->config;
  print_header( -expires => '+1m' );
  $config->template->process(
			     'error.tt2',
			     {   server_admin  => $ENV{SERVER_ADMIN},
				 error_message => join( "\n", @msg ),
			     }
			    )
    or warn $config->template->error();
  exit 0;
}

#########################################
# Things that might be utils
#########################################
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
  $path_info_search    =~ s/([^a-zA-Z0-9$()':_.,+*\/;?=&-])/uc sprintf("%%%02x",ord($1))/eg;
  $path_info_search    = quotemeta($path_info_search);
  $path_info_search    =~ s!/!/+!g;
  if ($uri =~ m/^(.+)($path_info_search)/) {
    return ($1,$2);
  } else {
    return ($raw_script_name,$raw_path_info);
  }
}
1;
