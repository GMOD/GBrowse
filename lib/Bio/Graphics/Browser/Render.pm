package Bio::Graphics::Browser::Render;
# $Id: Render.pm,v 1.5 2006-12-01 11:20:24 sheldon_mckay Exp $

#
# This library will supersedes Bio::Graphics::Browser::Util and much of
# the rendering code in the CGI scripts and Bio::Graphics::Browser

# The POD is currently just a placeholder, not complete
=pod

=head1 NAME

Bio::Graphics::Browser::Render -- HTML rendering methods for the Generic Genome Browser

=head1 SYNOPSIS

  my $render = Bio::Graphics::Browser::Render->new($CONFIG_DIR, 'HTML');

=head1 DESCRIPTION

This package provides methods that support HTML rendering for 
the Generic Genome Browser.

The new() method requires two arguments, the path to configuration files
and the renderting method ('HTML' or 'template').  The rendering method will
load methods specific to either template-driven HTML (for example, the gbrowse 
script) or CGI-based HTML (gbrowse_not).  The default method is 'HTML'.

=head1 METHODS

The remainder of this document describes the methods available to the
programmer.

=cut


use strict;
use Carp qw(croak cluck);
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Util;
use Bio::Graphics::Browser::Render::html;
use Bio::Graphics::Browser::Render::template;
use Bio::Graphics::Browser::PluginSet;
use Bio::Graphics::Browser::PageSettings;
use Carp qw(:DEFAULT croak);
use CGI qw(:standard unescape escape escapeHTML center *table *dl *TR *td);
use CGI::Toggle;
use CGI::Cookie;
use Text::Shellwords;


#################################################
# stuff that should mabye go away
use Bio::Graphics::Browser::UploadSet;
use Bio::Graphics::Browser::RemoteSet;
use Digest::MD5 'md5_hex';
use File::Path 'mkpath';
use Text::Tabs;
use File::Basename 'basename','dirname';
use File::Spec;
###################################################

use vars qw/$VERSION $CONFIG $LANG/;
$VERSION = 0.01;


$ENV{PATH} = '/bin:/usr/bin:/usr/local/bin';
local $CGI::USE_PARAM_SEMICOLONS = 1;
my $HAVE_SVG = eval {require GD::SVG; 1};

# A bunch of rendering methods will be present in either one 
# or both of the html and template subclasses.  Which subclass to
# use is specified as an argument to the new method.  Add the names
# of all html and/or template-specific methods here to autogenerate 
# pass-thru methods to be called from this object.
#
# Currently this list only contains subs from gbrowse_not

use constant PASSTHRU_METHODS => 
    (
     qw/template_error
        render 
        print_top
        print_bottom
        slidertable
        zoomBar
        overview_panel
        make_overview
        navigation_table
        tracks_table
        external_table
        settings_table
        upload_table
        das_table
        multiple_choices
        segment2link
        get_uploaded_file_info
        regionview
        edit_uploaded_file
        tableize
        # populate list...
        /
     );


BEGIN {
  
  # Alias pass-thru methods
  for my $sub_name ( PASSTHRU_METHODS ) {
    no strict 'refs';
    *{ $sub_name } = sub {
      my $self    = shift;
      return unless $self->renderer->can($sub_name);
      return $self->renderer->$sub_name(@_);
    };
  }
  
  # APACHE DBI warning
  eval "use Apache";
  warn <<'  END' if Apache::DBI->can('connect_on_init');
  WARNING: APACHE::DBI DETECTED.
  THIS WILL CAUSE THE GFF DUMP TO FAIL INTERMITTENTLY.
  THIS SCRIPT DOES NOT BENEFIT FROM APACHE::DBI
  END
};


sub new {
  my $class       = shift;
  my $config_dir  = shift;
  my $html_method = shift || 'html';
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
  
  # Create a html or template specific rendering object for internal use.
  # This is not visible to the calling script and is accessed via pass-though
  # methods
  my $renderer = "Bio::Graphics::Browser::Render::$method"->new($self);
  $self->renderer($renderer);

  $self->{header}         = 0;
  $self->{html}           = 0;
  $self->{added_features} = 0;
}

sub renderer {
  my $self = shift;
  my $pkg  = shift;
  return $pkg ? $self->{renderer} = $pkg : $self->{renderer};
}


# BEGIN SUBS


##########################################################
# Session and Page Settings Management                   #
##########################################################


=head2 restore_session

 usage

Description

=cut

sub restore_session {
  my $self     = shift;
  my $id       = param('id');
  my $page_settings = Bio::Graphics::Browser::PageSettings->new($self,$id);
  $self->page_settings($page_settings);
}


=head2 update_session

 usage

Description

=cut

sub update_session {
  my $self           = shift;
  my $config         = $self->config;
  my $page_settings  = $self->page_settings;

  $self->set_data_source();
  $self->update_settings();

  # Make sure that we expire the data source according to the
  # policy in globals.
  my $time = $self->global('remember_settings_time');
  $page_settings->session->expire($config->source, $time);
}


=head2 update_settings

 usage

Description

=cut

sub update_settings {
  my $self     = shift;
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
  my $divider  = $self->global_setting('unit_divider') || 1;

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

  if ($self->config->setting('region segment')) {
    $settings->{region_size} = param('region_size')+0             if defined param('region_size');
    $settings->{region_size} = $self->config->setting('region segment') unless defined $settings->{region_size};
  } else {
    delete $settings->{region_size};
  }

  if (my @external = param('eurl')) {
    my %external = map {$_=>1} @external;
    foreach (@external) {
      warn "eurl = $_" if $self->global('DEBUG_EXTERNAL');
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
    warn "resetting defaults..." if $self->global('DEBUG');
    set_default_tracks($settings);
  }

  elsif (param('reset')) {
    %$settings = ();
    #    Delete_all();
    default_settings($settings);
  }

  elsif (param($self->config->tr('Adjust_Order')) && !param($self->config->tr('Cancel'))) {
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


=head2 page_settings

 usage

Description

=cut

sub page_settings {
  my $self = shift;
  my $d    = $self->{page_settings};
  $self->{page_settings} = shift if @_;
  if (wantarray) {
    return ($d->page_settings,$d);
  }
  return $d;
}


=head2 finish

 usage

Description

=cut

sub finish {
  my $self   = shift;
  $self->page_settings->flush;
}



##########################################################
# General Configuration                                  #
##########################################################

# replace global $PLUGINS

=head2 plugins

 usage

Description

=cut

sub plugins {
  my $self = shift;

  return $self->{plugins}{$self->source} if $self->{plugins}{$self->source};

  my ($page_settings,$session)  = $self->page_settings;
  my $conf = $self->config;
  my @plugin_path = $self->config_dir . "/plugins";

  unshift @plugin_path, shellwords($self->global_setting('plugin_path'))
      if $self->global_setting('plugin_path');

  my $plugins = $self->{plugins}{$self->source};
  $self->{plugins}{$self->source} ||= Bio::Graphics::Browser::PluginSet->new($conf,$page_settings,@plugin_path); 
  $plugins->configure(open_database(),$page_settings,$session);
  $plugins;
}

# set the data source
# it may come from any of several places
# - from the legacy "source" CGI parameter -- this causes a redirect to gbrowse/source/
# - from the legacy "/source" path info -- this causes a redirect to gbrowse/source/
# - from the "/source/" path info
# - from the user's saved session
# - from the default source

=head2 set_data_source

 usage

Description

=cut

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
  $source      ||= $self->global_setting('default source');

  # not present there so get it from the first configured source
  $source      ||= $sources[0];

  # check that this is a correct source
  unless ($sources{$source}) {
    $self->warning($self->tr('INVALID_SOURCE',$source));
    $source = $self->setting('default source') || $sources[0];
  }

  # this call checks whether our path_info() is consistent with the
  # provided source. It may cause a redirect and exit!!!
  $self->redirect_legacy_url($source);

  # now set the source
  $config->source($source);                # in the current config
  $self->page_settings->source($source);   # in the page settings
}


=head2 open_config_files

 usage

Description

=cut

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

  # Gbrowse.conf is the base configuration file that contains global config
  # options and all of the foemr constants
  my $globals = Bio::Graphics::FeatureFile->new(-file=>"$dir/GBrowse.conf")
    or croak "no GBrowse.conf global config file found";
  $self->global_config($globals);
}


=head2 set_language

 usage

Description

=cut

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


# pass through methods to the config object

=head2 remember_settings_time

 usage

Description

=cut

sub source { shift->config->source(@_) }
sub tr     { shift->config->tr(@_) }

# REMOVE FROM BROWSER.pm
sub remember_settings_time {
  shift->global_setting('remember settings time');
}


=head2 config_dir

 usage

Description

=cut

sub config_dir {
  my $self = shift;
  my $d    = $self->{config_dir};
  $self->{config_dir} = shift if @_;
  $d;
}

#####################################################################################
# Configuration settings
#
# This object has two settings methods.
#
# The global_setting() method is used only for getting [GENERAL] information.
# Global configuration options have precedence over options for the current data source.
# It first queries the the GBrowse.conf global file.  If the setting isn't there,
# it queries the current data source-specific config object. It cannot be used to
# retrieve track-specific data.  Missing config settings cause a fatal exception
#
# The setting() method is used for getting [GENERAL] or track specific
# configuration from the currently active data source or, if none is found,
# the global configuration file.


=head2 setting

 usage

Description

=cut

sub setting {
  my $self   = shift;
  return $self->config->setting(@_) || $self->global($_[-1]);
}


=head2 global_setting

 usage

Description

=cut

sub global_setting {
  my $self   = shift;
  my $option = shift;
  my $retval = $self->global($option) || $self->config->setting($option);
  $retval ? return $retval : $self->fatal_error("Option $option is not configured");
}

#####################################################################################


=head2 global_config

 usage

Description

=cut

sub global_config {
  my $self    = shift;
  my $globals = shift;
  return $globals ? $self->{globals} = $globals : $self->{globals};
}

# replacement for all constants as well as access to global settings

=head2 global

 usage

Description

=cut

sub global {
  my $self     = lc shift;
  my $option   = shift;
  return $self->global_config->setting(general => $option);
}

# REMOVE FROM BROWSER.pm

=head2 tmpdir

 usage

Description

=cut

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


=head2 apache_conf_dir

 usage

Description

=cut

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

=head2 get_source
 
 my $source = $render->get_source;
 my ($new_source, $old_source) = $render->get_source;
 

Gets the source from CGI parameters or cookie and (optionally) sets 
the source value to the new source. 

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
    
    # the default, whatever it is    
    $self->source($source);
    return ( $source, $old_source );
  } 
  # otherwise just the source
  else {
    $self->source($new_source) if defined $new_source;
    return $new_source;
  }
}



##################################################################
# Bio::DB::GFF Utilities
##################################################################

=head2 current_segment
 
 my $segment = $render->current_segment;
 $render->current_segment($my_segment);

Getter/setter for the current segment object
Note : the alias 'segment' also works

=cut

*segment = \&current_segment;

sub current_segment {
  my ( $self, $segment ) = @_;
  $self->{current_segment} = $segment if $segment;
  $self->{current_segment} ||= $self->{segment};
  return $self->{current_segment};
}

=head2 whole_segment
 
 my $whole_segment = $render->whole_segment;
 
Returns a segment object for the entire reference sequence. 

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

=head2 resize
 
 $render->resize;
 
Truncate the segment to fit within min and max segment boundaries 

=cut

sub resize {
  my $self          = shift;
  my $segment       = $self->current_segment;
  my $whole_segment = $self->whole_segment;
  my $divider       = $self->setting('unit_divider') || 1;
  my $min_seg_size  = $self->setting('min segment')  || $self->global('MIN_SEG_SIZE');
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

=head2 is_search
 
 my $is_search = 1 if $render->is_search;
 
Returns true if this is an active search 

=cut

sub is_search {
  my ( $self, $page_settings ) = @_;
  return 1 if param();
  return 1 if $self->setting('initial landmark') && !$page_settings->{name};
  return 1 unless $self->setting('no autosearch');
  return undef;
}

=head2 features2segments
 
 my $segments = $render->features2segments(\@features,$database)

Converts a list of feature objects to segment objects 

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
  warn "segments = @segments\n" if $self->global('DEBUG');
  \@segments;
}

=head2 get_features
 
 my @features = @{$self->get_features($settings,$db)};

Returns an array ref containing feature objects.
 
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

=head2 lookup_features_from_db
 
 my $segment = $render->lookup_features_from_db($database,$settings);
 
=cut

sub lookup_features_from_db {
  my ( $self, $db, $settings ) = @_;
  my @segments;
  warn
      "name = $settings->{name}, ref = $settings->{ref}, start = $settings->{start}, "
      . "stop = $settings->{stop}, version = $settings->{version}"
      if $self->global('DEBUG');

  my $divisor  = $self->setting( general => 'unit_divider' )     || 1;
  my $padding  = $self->setting( general => 'landmark_padding' ) || 0;
  my $too_many = $self->setting('TOO_MANY_SEGMENTS');

  if ( my $name = $settings->{name} ) {
    warn "looking up by name: name = $name" if $self->global('DEBUG');
    @segments = $self->name2segments( $name, $db, $too_many );
  }
  elsif ( ( my $names = $settings->{q} ) && ref $settings->{q} ) {
    warn "looking up by query: q = $names" if $self->global('DEBUG');
    my $max = $too_many / @$names;
    @segments = map { $self->name2segments( $_, $db, $max ) } @$names;
  }
  elsif ( my $ref = $settings->{ref} ) {
    my @argv = ( -name => $ref );
    push @argv, ( -start => $settings->{start} * $divisor )
        if defined $settings->{start};
    push @argv, ( -end => $settings->{stop} * $divisor )
        if defined $settings->{stop};
    warn "looking up by @argv" if $self->global('DEBUG');
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

=head2 lookup_features_from_external_sources
 
 my @feats = $render->lookup_features_from_external_sources($settings,$searchterm);

Gets a list of external features matching a search term

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

=head2 do_keyword_search
 
 my @feats = $render->do_keyword_search($searchterm,$database);

 Lookup up features in the database that match the search term 

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

=head2 make_cookie
 
 my $cookie = $render->make_cookie($key => $value);
 
Creats a new cookie.

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

=head2 _broken_apache_hack

 usage

Description

=cut

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


=head2 error

 usage

Description

=cut

sub error {
  my $self = shift;
  my @msg = @_;
  cluck "@_" if $self->global('DEBUG');
  print_top();
  print h2({-class=>'error'},@msg);
}


=head2 fatal_error

 usage

Description

=cut

sub fatal_error {
  my $self = shift;
  my @msg = @_;
  print_header( -expires => '+1m' );
    $self->config->template->process(
        'error.tt2',
			       {   server_admin  => $ENV{SERVER_ADMIN},
            error_message => join( "\n", @msg ),
				 }
        )
        or warn $self->config->template->error();
  exit 0;
}


=head2 early_error

 usage

Description

=cut

sub early_error {
  my $self = shift;
  my $lang = shift;
  my $msg  = shift;
  $msg     = $lang->tr($msg);
  warn "@_" if $self->global('DEBUG');
  local $^W = 0;  # to avoid a warning from CGI.pm                                                                                                                                                               
  print_header(-expires=>'+1m');
  my @args = (-title  => 'GBrowse Error');
  push @args,(-lang=>$lang->language);
  print start_html();
  print b($msg);
  print end_html;
  exit 0;
}

#################################################################
# HTTP functions                
#################################################################


=head2 redirect_legacy_url

 usage

Description

=cut

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
# General HTML rendering and associated utilities                        
#
# Methods with the same behavior for the template and
# non-template rendering should go here.  HTML or template
# specific methods should go in the appropriate subclass
#
#################################################################

=head2 show_examples
 
 my $examples = $render->show_examples;

Gets a formatted list of examples searches specific to the current data source 

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
  return b( $self->config->tr('Examples') ) . ': ' . join( ', ', @urls ) . ". ";
}

=head2 toggle

 my $toggle_section = $self->toggle( $title, @body );
 
Creates a show/hide section via CGI::Toggle 

=cut

sub toggle {
  my $self = shift;
  my ($tconf,$id, $section_head,@body);
  if (ref $_[0] eq 'HASH') {
    ($tconf,$id, $section_head,@body) = @_;
  }
  else {
    ($tconf,$id, $section_head,@body) = ({},@_);
  }

  my ($label) = $self->tr($section_head) || ($section_head);
  my $state = $self->config->section_setting($section_head);
  my $on = $state eq 'open';

  # config as argument overrides section_setting
  $tconf->{on} ||= $on;

  return toggle_section( $tconf, $id, b($label), @body );
}

=head2 unit_label
 
 my $formatted_number = $render->unit_label(100000000);

Formats a number for DNA sequence with the appropriate unit label 

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

=head2 get_zoomincrement
 
 my $zoom_inc = $render->get_zoomincrement;

Get the zoom increment for the pan buttons 

=cut

sub get_zoomincrement {
  my $self = shift;
  my $zoom = $self->setting('fine zoom') 
      || $self->global('DEFAULT_FINE_ZOOM');
  $zoom;
}

=head2 split_labels
 
 my @labels = $render->split_labels(param('label'));

Splits urls into a list 

=cut

sub split_labels {
  my $self = shift;
  map { /^(http|ftp|das)/ ? $_ : split /[+-]/ } @_;
}

=head2 bookmark_link
 
 my $query_url = $render->bookmark_link($settings);

Create a URL for bookmarking this saved session 

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

=head2 zoomnav
 
 $render->zoomnav($settings);

Responds to zoom/pan requests 

=cut

sub zoomnav {
  my ( $self, $settings ) = @_;
  return unless $settings->{ref};
  my $start   = $settings->{start};
  my $stop    = $settings->{stop};
  my $span    = $stop - $start + 1;
  my $divisor = $self->setting( general => 'unit_divider' ) || 1;
  warn "before adjusting, start = $start, stop = $stop, span=$span" if $self->global('DEBUG');
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
  my $overview_ratio = $self->global('OVERVIEW_RATIO');

  if ( defined $zoomlevel ) {
    warn "zoom = $zoom, zoomlevel = $zoomlevel" if $self->global('DEBUG');
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
    my $overview_width = ( $settings->{width} * $overview_ratio );

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
        = ( $settings->{width} * $overview_ratio );

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
    warn "selected_span = $selected_span" if $self->global('DEBUG');
    my $center = int( ( $span / 2 ) ) + $start;
    my $range  = int( ($selected_span) / 2 );
    $start = $center - $range;
    $stop  = $start + $selected_span - 1;
  }
  warn
      "after adjusting for navlevel, start = $start, stop = $stop, span=$span"
      if $self->global('DEBUG');

  # to prevent from going off left end
  if (defined $seg_min && $start < $seg_min) {
    warn "adjusting left because $start < $seg_min" if $self->global('DEBUG');
    ( $start, $stop ) = ( $seg_min, $seg_min + $stop - $start );
  } 
  # to prevent from going off right end
  if (defined $seg_max && $stop > $seg_max) {
    warn "adjusting right because $stop > $seg_max" if $self->global('DEBUG');
    ( $start, $stop ) = ( $seg_max - ( $stop - $start ), $seg_max );
  } 
  # to prevent divide-by-zero errors when zoomed down to a region < 2 bp  
  $stop  = $start + ($span > 4 ? $span - 1 : 4) if $stop <= $start+2;
  warn "start = $start, stop = $stop\n" if $self->global('DEBUG');
  $divisor = 1 if $divisor =~ /[^0-9]/;;
  $settings->{start} = $start / $divisor;
  $settings->{stop}  = $stop / $divisor;
}

=head2 unit_to_value
 
 my $value = $render->unit_to_value($number);

Converts formatted numbers to the appropriate absolute number (e.g. 1 kbp -> 1000) 

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


=head2 make_hilite_callback
 
 my $hcallback = $render->make_hilite_callback($page_settings);

This method creates a coderef to handle feature highlighting
(if highlighter plugins are installed).

=cut


sub make_hilite_callback {
  my $self     = shift;
  my $settings = shift;
  my @hiliters = grep {$_->type eq 'highlighter'} $PLUGINS->plugins;
  return unless @hiliters or ($settings->{h_feat} && %{$settings->{h_feat}});
  return sub {
    my $feature = shift;
    my $color;

    # run through the set of hilite plugins and give each one
    # a chance to choose the highlighting for its feature
    foreach (@hiliters) {
      $color ||= $_->highlight($feature);
    }
    return $color if $color;

    # if we get here, we select the search term for highlighting
    return unless $feature->display_name;
    return $settings->{h_feat}{$feature->display_name};
  }
}




=head2 make_postgrid_callback

 usage

Description

=cut

sub make_postgrid_callback {
  my $self     = shift;
  my $settings = shift;
  my @h_regions;
  return unless ref $settings->{h_region};
  for my $r (@{$settings->{h_region}}) {
    my ($h_ref,$h_start,$h_end,$h_color) = $r =~ /^(.+):(\d+)\.\.(\d+)(?:@(\S+))?/ or next;
    next unless $h_ref eq $settings->{ref};
    push @h_regions,[$h_start,$h_end,$h_color||'lightgrey'];
  }
  @h_regions or return;

  return sub {
    my $gd     = shift;
    my $panel  = shift;
    my $left   = $panel->pad_left;
    my $top    = $panel->top;
    my $bottom = $panel->bottom;
    for my $r (@h_regions) {
      my ($h_start,$h_end,$h_color) = @$r;
      my ($start,$end) = $panel->location2pixel($h_start,$h_end);
      $gd->filledRectangle($left+$start,$top,$left+$end,$bottom,
			   $panel->translate_color($h_color));
    }
  }
}


=head2 categorize_track

 usage

Description

=cut

sub categorize_track {
  my $self     = shift;
  my $label = shift;
  return $self->tr('OVERVIEW') if $label =~ /:overview$/;
  return $self->tr('REGION')   if $label =~ /:region$/;
  return $self->tr('EXTERNAL') if $label =~ /^(http|ftp|file):/;
  return $self->tr('ANALYSIS') if $label =~ /^plugin:/;

  my $category;
  for my $l ($self->config->language->language) {
    $category      ||= $self->setting($label=>"category:$l");
  }
  $category        ||= $self->setting($label => 'category');
  $category        ||= '';  # prevent uninit variable warnings
  $category         =~ s/^[\"\']//;  # get rid of leading quotes
  $category         =~ s/[\"\']$//;  # get rid of trailing quotes
  return $category ||= $self->tr('GENERAL');
}


=head2 annotation_help

 usage

Description

=cut

sub annotation_help {
  return "?help=annotation";
}


=head2 general_help

 usage

Description

=cut

sub general_help {
  return "?help=general";
}


=head2 format_segment

 usage

Description

=cut

sub format_segment {
  my $self  = shift;
  my $s = shift or return $self->tr('Not_applicable');
  my $ref = $s->seq_id;
  my ($start,$s_units) = unit_label($s->start);
  my ($end,$e_units)   = unit_label($s->end);
  $start  = commas($start);
  $end    = commas($end);
  my $pos = $s_units eq $e_units ? "$start..$end $s_units" : "$start $s_units..$end $e_units";
  return "<b>$ref</b>:$pos";
}


=head2 line_end

 usage

Description

=cut

sub line_end {
  my $self    = shift;
  my $agent  = CGI->user_agent();
  return "\r"   if $agent =~ /Mac/;
  return "\r\n" if $agent =~ /Win/;
  return "\n";
}


=head2 print_uploaded_file_features

 usage

Description

=cut

sub print_uploaded_file_features {
  my ($self,$settings,$file) = @_;
  my $line_end = line_end();
  if (my $fh = $UPLOADED_SOURCES->open_file($file)) {
    while (<$fh>) {
      chomp;
      print $_,$line_end;
    }
  }
}

=head2 image_link

 usage

Description

=cut

sub image_link {
  my $self     = shift;
  my $settings = shift;
  return "?help=link_image;flip=".($settings->{flip}||0);
}

=head2 svg_link

 usage

Description

=cut

sub svg_link {
  my $self     = shift;
  my $settings = shift;
  return "?help=svg_image;flip=".($settings->{flip}||0);
}

=head2 help

 usage

Description

=cut

sub help {
  my ($self,$help_type,$conf_dir,$settings) = @_;

  my $ref = referer();
  my $do_close = join('',
		      start_form(-action=>$ref),
		      button(-onClick=>'window.close()',-label=>$self->tr('Close_Window')),
		      end_form());
  print div({-align=>'right'},$do_close);
  if ($help_type eq 'citations') {
    build_citation_page($settings);
  }

  elsif ($help_type eq 'link_image') {
    build_link_image_page($settings);
  } elsif ($help_type eq 'svg_image') {
    build_svg_image_page($settings);
  }

  else {
    my @components = File::Spec->splitdir($help_type);
    my $updir      = File::Spec->updir;
    # don't let evil people get into root directory
    my $evil       = grep { /^$updir$/o } @components;
    return         if $evil;
    build_help_page("$conf_dir/${help_type}_help.html");
  }
  print div({-align=>'right'},$do_close);
}

=head2 make_citation

 usage

Description

=cut

sub make_citation {
  my $self    = shift;
  my $config  = shift;
  my $feature = shift;
  my $citation = eval {$config->citation($feature,$self->config->language)};
  if (ref $citation && ref $citation eq 'CODE') {
    $citation = $citation->();
  }
  # BUG: here's where we should remove "bad" HTML, but we don't!
  # should remove active content and other nasties
  (my $link     = $feature) =~ tr/ /-/;
  my $text      = label2key($feature);
  return join ('',
	       dt(a({-name=>$link},b($text))),
	       dd($citation||$self->tr('NO_CITATION')),
	       p());
}


=head2 build_citation_page

 usage

Description

=cut

sub build_citation_page {
  my $self     = shift;
  my $settings = shift;

  my @features = $self->config->labels;
  my $external_features = load_external_sources(undef,$settings);
  $external_features ||= {};

  my (@citations);
  print h2($self->tr('Track_descriptions'));

  # build native features
  print h3($self->tr('Built_in'));
  for my $feature (@features) {
    push @citations,make_citation($self->config,$feature);
  }

  print blockquote(dl(@citations));

  # build external features
  if (%$external_features) {
    print hr,h3($self->tr('External'));
    for my $file (keys %$external_features) {
      my @citations = ();
      my $f = escape($file);
      my $name   = $file;
      my $is_url = $name =~ m!^(http|ftp)://!;
      my $download = escape($self->tr('Download_data'));
      my $link   = $is_url  ? $name  : "?$download=1;file=$f";
      my $anchor = $name;
      $anchor =~ tr/ /-/;

      unless (ref $external_features->{$file}) {
	print h3(a{-name=>$anchor,-href=>$link},$name);
	print blockquote($self->tr('Activate'));
	next;
      }

      my $obj = eval{$external_features->{$file}->factory} || $external_features->{$file};

      $link =~ s!(/das/[^/?]+)!$1/types! 
	if $obj->isa('Bio::Das');

      print h4(a{-name=>$anchor,-href=>$link},$name);
      for my $feature ($obj->types) {
	push @citations,make_citation($external_features->{$file},$feature);
      }
      print blockquote(dl(@citations));
    }
    print p($self->tr('No_external')) unless @citations;
  }

}


=head2 build_citation_page

 usage

Description

=cut

sub build_citation_page {
  my $self     = shift;
  my $settings = shift;

  my @features = $self->config->labels;
  my $external_features = load_external_sources(undef,$settings);
  $external_features ||= {};

  my (@citations);
  print h2($self->tr('Track_descriptions'));

  # build native features
  print h3($self->tr('Built_in'));
  for my $feature (@features) {
    push @citations,make_citation($self->config,$feature);
  }

  print blockquote(dl(@citations));

  # build external features
  if (%$external_features) {
    print hr,h3($self->tr('External'));
    for my $file (keys %$external_features) {
      my @citations = ();
      my $f = escape($file);
      my $name   = $file;
      my $is_url = $name =~ m!^(http|ftp)://!;
      my $download = escape($self->tr('Download_data'));
      my $link   = $is_url  ? $name  : "?$download=1;file=$f";
      my $anchor = $name;
      $anchor =~ tr/ /-/;

      unless (ref $external_features->{$file}) {
	print h3(a{-name=>$anchor,-href=>$link},$name);
	print blockquote($self->tr('Activate'));
	next;
      }

      my $obj = eval{$external_features->{$file}->factory} || $external_features->{$file};

      $link =~ s!(/das/[^/?]+)!$1/types! 
	if $obj->isa('Bio::Das');

      print h4(a{-name=>$anchor,-href=>$link},$name);
      for my $feature ($obj->types) {
	push @citations,make_citation($external_features->{$file},$feature);
      }
      print blockquote(dl(@citations));
    }
    print p($self->tr('No_external')) unless @citations;
  }

}


=head2 build_help_page

 usage

Description

=cut

sub build_help_page {
  my $self     = shift;
  my $helpfile = shift or return;
  my $file = url2file($helpfile) or return;
  my $root = $self->global_setting('help') || GBROWSE_HELP;
  my $url  = url(-abs=>1,-path=>1);
  open(F,$file) or return;
  while (<F>) { # fix up relative addressing of images
    s/\$GBROWSE\b/$url/g
      or
    s/(href|src)=\"([^\"\#\$]+)\"/$1=\"$root\/$2\"/g;
    s/<!--\s*\#include-classes\s*-->/object_classes_for_help()/e;
    print;
  }
  close F;
}


=head2 build_link_image_page

 usage

Description

=cut

sub build_link_image_page {
  _build_image_page(@_,'IMAGE_DESCRIPTION');
}


=head2 build_svg_image_page

 usage

Description

=cut

sub build_svg_image_page {
  _build_image_page(@_,'SVG_DESCRIPTION','GD::SVG');
}


=head2 _build_image_page

 usage

Description

=cut

sub _build_image_page {
  my $self     = shift;
  my $settings = shift;
  my $help     = shift;
  my $format   = shift;

  my $source = $self->config->source;
  my $id     = $settings->{id};
  my $flip   = $settings->{flip} || param('flip') || 0;
  my $keystyle = $settings->{ks};
  my $grid     = $settings->{grid} || 0;
  my $url = url(-base=>1);
  $url   .= url(-absolute=>1);
  $url    = dirname($url) . "/gbrowse_img/".escape($source);
  my $tracks = $settings->{tracks};
  my $width  = $self->config->width;
  my $name   = $settings->{name} || "$settings->{ref}:$settings->{start}..$settings->{stop}";
  my $type    = join '+',map{escape($_)} map {/\s/?qq("$_"):$_} grep {$settings->{features}{$_}{visible}} @$tracks;
  my $options = join '+',map { join '+', escape($_),$settings->{features}{$_}{options}
			     } map {/\s/?"$_":$_}
			       grep {
				 $settings->{features}{$_}{options}
			       } @$tracks;
  my $img_url = "$url/?name=$name;type=$type;width=$width;id=$id";
  $img_url   .= ";flip=$flip"         if $flip;
  $img_url   .= ";options=$options"   if $options;
  $img_url   .= ";format=$format"     if $format;
  $img_url   .= ";keystyle=$keystyle" if $keystyle;
  $img_url   .= ";grid=$grid";
  add_hilites($settings,\$img_url);
  print $self->tr($help,$img_url,$img_url);
}


=head2 add_hilites

 usage

Description

=cut

sub add_hilites {
  my $self     = shift;
  my $settings = shift;
  my $img_url  = shift;

  # add feature hilighting
  if ($settings->{h_feat} && ref $settings->{h_feat} eq 'HASH') {
    for my $h (keys %{$settings->{h_feat}}) {
      $$img_url .= ";h_feat=$h\@$settings->{h_feat}{$h}";
    }
  }
  # add region hilighting
  if ($settings->{h_region} && ref $settings->{h_region} eq 'ARRAY') {
    for my $h (@{$settings->{h_region}}) {
      $$img_url .= ";h_region=$h";
    }
  }

}


=head2 object_classes_for_help

 usage

Description

=cut

sub object_classes_for_help {
  return $OBJECT_CLASSES{$self->config->source} if exists $OBJECT_CLASSES{$self->config->source};
  my $db = open_database();
  my @classes = eval {$db->classes};
  return $OBJECT_CLASSES{$self->config->source} = '' unless @classes;
  return $OBJECT_CLASSES{$self->config->source} = ul(li(\@classes));
}


=head2 make_citation_link

 usage

Description

=cut

sub make_citation_link {
  my ($self,$label,$self_url)   = @_;
  my ($link,$key);
  if ($label =~ /^plugin:/) {
    $key = $label || '';
    $key =~ s/^plugin://;
    my $about = escape($self->tr('About')) || '';
    my $plugin = $PLUGIN_NAME2LABEL{$label} ? ";plugin=$PLUGIN_NAME2LABEL{$label}" : '';
    $link = "?plugin_action=${about}${plugin}";
  }

  elsif ($label =~ /^file:/){
    $key  = label2key($label);
    $link = "?Download%20File=$key";
  }

  else {
    $key = label2key($label);
    (my $anchor  = $label) =~ tr/ /-/;
    $link = $self_url.'#'.escapeHTML($anchor);
  }
  my $citation = $self->config->citation($label,$self->config->language);
  my $overview_color = $self->setting('overview bgcolor') || DEFAULT_OVERVIEW_BGCOLOR();
  my @args = (-href=>$link,-target=>'citation');
  push @args,-style=>'Font-style: italic' if $label =~ /^(http|ftp|file):/;
  # push @args,-style=>"background: $overview_color" if $label =~ /:overview$/;
  return a({@args},$key);
}


=head2 label2key

 usage

Description

=cut

sub label2key {
  my $self  = shift;
  my $label = shift;
  my $key;
  $PRESETS ||= get_external_presets || {};
  for my $l ($self->config->language->language) {
    $key     ||= $self->config->setting($label=>"key:$l");
  }
  $key     ||= $self->config->setting($label => 'key');
  $key     ||= $PRESETS->{$key} if defined $key;
  $key     ||= $label;
  # $key     .= '*' if $label =~ /:overview$/;
  $key;
}


=head2 plugin_links

 usage

Description

=cut

sub plugin_links {
  my $self    = shift;
  my $plugins = shift;
  my @plugins = shellwords($self->setting('quicklink plugins')) or return '';
  my @result;
  for my $p (@plugins) {
    my $plugin = $plugins->plugin($p) or next;
    my $name   = $plugin->name;
    my $action = "?plugin=$p;plugin_do=".$self->tr('Go');
    push @result,a({-href=>$action},"[$name]");
  }
  return join ' ',@result;
}


=head2 plugin_menu

 usage

Description

=cut

sub plugin_menu {
  my ($self,$settings,$plugins) = @_;

  my $labels = $plugins->menu_labels;

  my @plugins = sort {$labels->{$a} cmp $labels->{$b}} keys %$labels;
  return unless @plugins;
  return join('',
	      popup_menu(-name=>'plugin',
			 -values=>\@plugins,
			 -labels=> $labels,
			 -default => $settings->{plugin},
			),'&nbsp;',
	      # submit(-name=>'plugin_action',-value=>$self->tr('About')),'&nbsp;',
	      submit(-name=>'plugin_action',-value=>$self->tr('Configure')),'&nbsp;',
	      b(submit(-name=>'plugin_action',-value=>$self->tr('Go')))
	      );
}


=head2 do_plugin_about

 usage

Description

=cut

sub do_plugin_about {
  my $self   = shift;
  my $plugin = shift;
  my $p = $PLUGINS->plugin($plugin) or return;
  my $type  = ( split ( /::/, ref($p) ) )[-1];
  my $labels = $PLUGINS->menu_labels;
  print h1($self->tr('About_plugin',$labels->{$type}));
  print $p->description;
  print start_form(),submit(-name=>$self->tr('Back_to_Browser'),
			    -onClick=>'window.close()')
    ,hidden('plugin'),end_form();
}


=head2 do_plugin_autofind

 usage

Description

=cut

sub do_plugin_autofind {
  my ($self,$settings,$searchterm) = @_;
  my $segments = [];

  for my $p ($PLUGINS->plugins) {
    next unless $p->type eq 'finder' && $p->can('auto_find');
    do_plugin_find($settings,$p,$segments,$searchterm);
    last if @$segments;
  }
  return @$segments;
}


=head2 do_plugin_configure

 usage

Description

=cut

sub do_plugin_configure {
  my $self     = shift;
  my $plugin   = shift;
  my $p = $PLUGINS->plugin($plugin) or return;
  my $type = $p->type;
  my @action_labels = ($self->tr('Cancel'),$self->tr('Configure_plugin'));
  push @action_labels,$self->tr('Find') if $type eq 'finder';
  push @action_labels,$self->tr('Go')   if ($type eq 'dumper' or $type eq 'filter');
  my @buttons = map {submit(-name=>'plugin_action',-value=>$_)} @action_labels;

  # turn this off if requested by the plugin
  unless ($p->suppress_title) {
    print h1($p->type eq 'finder' ? $self->tr('Find') : $self->tr('Configure'),$p->name);
  }

  my $config_html = $p->configure_form;

  print start_multipart_form(),
    $config_html ? (
		    $config_html,p(),
		    join ('&nbsp;',
			  @buttons[0..@buttons-2],
			  b($buttons[-1]),
			  ),
		    # This is an insurance policy in case user hits return in text field
		    # in which case the plugin_action is not going to be defined
		    hidden(-name=>'plugin_action',-value=>$action_labels[-1],-override=>1),
		   )
                 : ( p($self->tr('Boring_plugin')),
		     b(submit($self->tr('Back_to_Browser')))
		   ),
     hidden(-name=>'plugin_config',-value=>1,-override=>1),
     hidden('plugin'),
     end_form();
}


=head2 do_plugin_dump

 usage

Description

=cut

sub do_plugin_dump {
  my $self     = shift;
  my $plugin   = shift;
  my $segment  = shift;
  my $settings = shift;
  my $p        = $PLUGINS->plugin($plugin) or return;
  my @additional_feature_sets;
  if ($segment && $settings && $segment->length <= $MAX_SEGMENT) {
     my $feature_files = load_external_sources($segment,$settings);
     @additional_feature_sets = values %{$feature_files};
  }
  $p->dump($segment,@additional_feature_sets);
  return 1;
}


=head2 do_plugin_find

 usage

Description

=cut

sub do_plugin_find {
  my $self = shift;
  my ($settings,$plugin,$features,$search_string) = @_;

  # to simplify life, this subroutine takes either the plugin name
  # or a plugin reference.
  my $p = ref $plugin ? $plugin : $PLUGINS->plugin($plugin);
  $p or return;

  my $plugin_name = $p->name;

  my $results = $p->can('auto_find') && defined $search_string
              ? $p->auto_find($search_string) 
              : $p->find($features);
  return unless $results;  # reconfigure message
  return unless @$results;

  @$features = @$results;
  $settings->{name} = defined($search_string) ? $self->tr('Plugin_search_1',$search_string,$plugin_name)
                                              : $self->tr('Plugin_search_2',$plugin_name);
  # remember the search
  write_auto($settings,$results);
  1; # return a true result to indicate that we don't need further configuration
}


=head2 do_plugin_header

 usage

Description

=cut

sub do_plugin_header {
  my $self          = shift;
  my $plugin        = shift;
  my $page_settings = shift;
  my $cookie        = shift;
  my ($mime_type,$attachment)     = $PLUGINS->plugin($plugin)->mime_type;
  print_header(-cookie => $cookie,
	       -type=>$mime_type,
	       $attachment ? (-attachment=>$attachment) : (),
	      );
}


=head2 get_regionview_seg

 usage

Description

=cut

sub get_regionview_seg {
  my $self = shift;
  my ($settings,$detail_start, $detail_end, $whole_start, $whole_end) = @_;
  my $regionview_length = $settings->{region_size};
  if ($detail_end - $detail_start + 1 > $regionview_length) { # region can't be smaller than detail
    $regionview_length = $detail_end - $detail_start + 1;
  }
  my $midpoint = ($detail_end + $detail_start) / 2;
  my $regionview_start = int($midpoint - $regionview_length/2 + 1);
  my $regionview_end = int($midpoint + $regionview_length/2);
  if ($regionview_start < $whole_start) {
    $regionview_start = 1;
    $regionview_end   = $regionview_length;
  }
  if ($regionview_end > $whole_end) {
    $regionview_start = $whole_end - $regionview_length + 1;
    $regionview_end   = $whole_end;
  }
  return ($regionview_start, $regionview_end);
}


=head2 version_warning

 usage

Description

=cut

sub version_warning {
  return if Bio::Graphics::Panel->can('api_version') &&
	  Bio::Graphics::Panel->api_version >= $BIOGRAPHICS_VERSION;

    warn <<END;
GBROWSE VERSION MISMATCH:
GBrowse version $VERSION requires a compatible version of the Bio::Graphics library.
You should either install BioPerl (the CVS live version) or reinstall GBrowse,
which will patch Bio::Graphics to the latest version.
END
}


=head2 warning

 usage

Description

=cut

sub warning {
  my $self = shift;
  my @msg  = @_;
  cluck "@_" if $self->global('DEBUG');
  $self->print_top();
  print h2({-class=>'error'},@msg);
}

=head2  source_menu

 my $source_menu = $browser_run->source_menu;

Creates a popup menu of available data sources

=cut

sub source_menu {
  my $self         = shift;
  my @sources      = $self->config->sources;
  my $show_sources = $self->setting('show sources') || 1;
  my $sources = $show_sources && @sources > 1;

  my $popup = popup_menu(
                         -name     => 'source',
                         -values   => \@sources,
                         -labels   => { map { $_ => $self->description($_) } $self->sources },
                         -default  => $self->source,
                         -onChange => 'document.mainform.submit()'
                         );

  return b( $self->tr('DATA_SOURCE') ) . br
      . ( $sources ? $popup : $self->description( $self->source ) );
}


=head2 footer()

    $footer = $browser->footer;

This is a shortcut method that returns the footer HTML for the gbrowse
page.

Left in for backwards compatibility.

=cut

sub footer {
  my $self = shift;
  my $footer = $self->config->code_setting(general => 'footer');
  if (ref $footer eq 'CODE') {
    my $f = eval {$footer->(@_)};
    $self->_callback_complain(general=>'footer') if @_;
    return $f;
  }
  return $footer;
}

1;

