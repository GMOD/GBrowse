package Bio::Graphics::Browser;

# $Id: Browser.pm,v 1.51.2.19 2003-09-02 20:06:45 ccavnor Exp $
# This package provides methods that support the Generic Genome Browser.
# Its main utility for plugin writers is to access the configuration file information

=head1 NAME

Bio::Graphics::Browser -- Utility methods for the Generic Genome Browser

=head1 SYNOPSIS

  $b = Bio::Graphics::Browser->new;
  $b->read_configuration('/path/to/conf/files');

  my @data_sources = $b->sources;
  my $current_source = $b->source;
  my $setting = $b->setting('default width');
  my $description    = $b->description;
  my @track_labels   = $b->labels;
  my @default_tracks = $b->default_labels;

=head1 DESCRIPTION

This package provides methods that support the Generic Genome Browser.
Its main utility for plugin writers is to access the configuration
file information.

Typically, the Bio::Graphics::Browser object will be created before
the plugin is invoked, and will be passed to the plugin for retrieval
by its browser_config method.  For example:

  $browser_obj = $self->browser_config;

Each browser configuration has a set of "sources" that correspond to
the individual configuration files in the gbrowse.conf directory.  At
any time there is a "current source" which indicates the source to
fetch settings from.  It is equal to the current setting of the "Data
Source" menu.

From the current source you can retrieve configuration settings
corresponding to the keys and values of the current config file.
These are fetched using the setting() method.  You can retrieve both
general settings and settings that are specific to a particular
track.

=head1 METHODS

The remainder of this document describes the methods available to the
programmer.

=cut

use strict;
use Exporter;
use Bio::LocallyIdentifiableI;
use vars qw( $VERSION $CONF_DIR @ISA @EXPORT_OK );
$VERSION = '2.00';
@ISA = qw( Exporter
           Bio::LocallyIdentifiableI );
@EXPORT_OK = qw( &configureBrowsers &retrieveBrowser $CONF_DIR );

use Bio::Graphics;
use Bio::Graphics::Util;
use Bio::Graphics::Browser::I18n;
use Bio::Graphics::Browser::ConfigIO;
use Text::Tabs;
use Text::Shellwords;
use GD qw( gdMediumBoldFont gdLargeFont );
use Digest::MD5 'md5_hex';
use File::Path 'mkpath';
use File::Basename 'basename';
#use Carp qw( :DEFAULT croak );
use CGI::Carp;
use CGI qw( :standard escape escapeHTML center expires *table *dl *TR *td );
use Cwd;
use vars qw( $SOURCES $DEFAULT_SOURCE );

## TODO: Document this.  Why?
#$ENV{ 'PATH' } = '/bin:/usr/bin:/usr/local/bin';

use constant DEBUG                => 0;
use constant DEBUG_PLUGINS        => 0;

# if true, turn on surrounding rectangles for debugging the image map
## TODO: REMOVE? This is unused.
use constant DEBUGGING_RECTANGLES => 0;

if( DEBUG ) {
  use Data::Dumper;
}

=head1 Exported functions
=cut

=head2 configureBrowsers

 Title   : configureBrowsers
 Usage   : use Bio::Graphics::Browser 'configureBrowsers';
           my $success = configureBrowsers( '/path/to/gbrowse.conf' );
 Function: Set the configuration directory for all Browser instances.
 Returns : true iff the given directory contains configuration files
 Args    : a string representing the path of the directory containing the
           gbrowse conf files.
 Status  : Public, exported function

=cut

sub configureBrowsers {
  my ( $conf_dir ) = @_;

  ## TODO: REMOVE
  warn "\$conf_dir is $conf_dir\n" if DEBUG;

  my $success = 1;
  if( $CONF_DIR ne $conf_dir ) {
    $success = Bio::Graphics::Browser->read_configuration( $conf_dir );
    if( $success ) {
      $CONF_DIR = $conf_dir;
    }
  } # End if the given $conf_dir is different from $CONF_DIR.
  return $success;
} # configureBrowsers(..)

=head2 retrieveBrowser

 Title   : retrieveBrowser
 Usage   : use Bio::Graphics::Browser 'retrieveBrowser';
           my $browser = retrieveBrowser( $browser_id );
 Function: Attempts to retrieve the instance of Bio::Graphics::Browser
           that has the given unique_id.
 Returns : a Bio::Graphics::Browser object or undef if that browser does not
           exist or has expired.
 Args    : A string unique_id value.
 Status  : Public, exported function

=cut

sub retrieveBrowser {
  my $browser_id = shift;

  ## TODO: retrieve it.  We'll somehow need to implement expiry (threads? mod-perl special treats? I dunno).

  return undef;
} # retrieveBrowser(..)

=head1 Class methods
=cut

=head2 read_configuration()

  my $success =
    Bio::Graphics::Browser->read_configuration( '/path/to/gbrowse.conf' );

Parse the files in the gbrowse.conf configuration directory.  This is
done automatically by gbrowse.  Returns a true status code if
successful.

=cut

sub read_configuration {
  my $caller      = shift;
  my $conf_dir    = shift;
  $SOURCES ||= {};

  croak( "$conf_dir: not a directory" ) unless -d $conf_dir;
  opendir( D, $conf_dir ) or croak "Couldn't open $conf_dir: $!";
  my @conf_files = map { "$conf_dir/$_" } grep { /\.conf$/ } readdir( D );
  close D;

  # try to work around a bug in Apache/mod_perl which appears when
  # running under linux/glibc 2.2.1
  unless( @conf_files ) {
    @conf_files = glob( "$conf_dir/*.conf" );
  }

  # get modification times
  my %mtimes = map { $_ => ( stat( $_ ) )[ 9 ] } @conf_files;

  # Use a string sort and use the top one as the initial source.
  # Build up the $SOURCES hash with the source name ($basename)
  # mapped to the file name of the corresponding config file.  The
  # config file won't actually be loaded until the corresponding
  # source is used (so the initial config file will be loaded, but the
  # others won't yet).  When Config objects are instantiated they will
  # replace the file names in the $SOURCES hash.
  # If multiple files have the same name then use the one most
  # recently modified.
  my ( $basename, $source, %basename_mtimes );
  for my $file ( sort { $a cmp $b } @conf_files ) {
    $basename = basename( $file, '.conf' );
    $basename =~ s/^\d+\.//;
    next if(
      defined( $basename_mtimes{ $basename } ) &&
      ( $basename_mtimes{ $basename } >= $mtimes{ $file } )
    );
    $SOURCES->{ $basename } = $file;
    $basename_mtimes{ $basename } = $mtimes{ $file };
    $source ||= $basename;
  }
  $DEFAULT_SOURCE = $source;

  return 1; # success
} # read_configuration(..)

=head2 new()

  my $browser = Bio::Graphics::Browser->new();

Create a new Bio::Graphics::Browser object.  The object is initially
empty.  This is done automatically by gbrowse.

=cut

sub new {
  my $class = shift;
  my %defaults = @_;
  my $self = bless {}, ( ref( $class ) || $class );
  $self->{ '_defaults' } = \%defaults;
  $self->_initialize_browser();
  return $self;
} # new(..)

=head1 Public object methods
=cut

=head2 unique_id

 Title   : unique_id
 Usage   : my $unique_id = $browser->unique_id( [$new_unique_id] )
 Function: This is a unique identifier that identifies this browser object.
           If not set, will return undef per L<Bio::LocallyIdentifiableI>
           If a value is given, the unique_id will be set to it, unless that
           value is the string 'undef', in which case the unique_id will
           become undefined.
 Returns : The current (or former, if used as a set method) value of unique_id
 Args    : [optional] a new string unique_id or 'undef'

=cut

sub unique_id {
  my ( $self, $value ) = @_;
  my $current_value = $self->{ '_unique_id' };
  if ( defined $value ) {
    if( !$value || ( $value eq 'undef' ) ) {
      warn "Undefining the unique_id." if DEBUG;
      $self->{ '_unique_id' } = undef;
    } else {
      warn "Setting the unique_id to $value." if DEBUG;
      $self->{ '_unique_id' } = $value;
    }
  }
  return $current_value;
} # unique_id()

=head2

Argument: the optional expiration date for this browser.
The format is as described for the B<CGI::header()> method:

	+30s                              30 seconds from now
	+10m                              ten minutes from now
	+1h                               one hour from now
	-1d                               yesterday (i.e. "ASAP!")
	now                               immediately
	+3M                               in three months
	+10y                              in ten years time
	Thursday, 25-Apr-1999 00:40:33 GMT  at the indicated time & date

=cut

sub expiration_time {
  my $self = shift;
  my ( $argument ) = @_;

  my $current_value = $self->{ '_expiration_time' };
  if( $argument ) {
    my $new_value = expires( $argument );
    $self->{ '_expiration_time' } = $new_value;
  }

  return $current_value;
} # expiration_time(..)

sub get_ranges {
  return split /\s+/, shift->setting( 'zoom levels' );
}

sub get_zoomincrement {
  return shift->setting( 'fine zoom' );
}

=head2 width()

  $width = $browser->width

=cut

sub width {
  my $self = shift;
  my $d = $self->{ '_width' };
  $self->{ '_width' } = shift if @_;
  $d;
} # width(..)

=head1 Configuration methods
=cut

=head2 sources()

  @sources = $browser->sources;

Returns the list of symbolic names for sources.  The symbolic names
are derived from the configuration file name by:

  1) stripping off the .conf extension.
  2) removing the pattern "\d+\."

This means that the configuration file "03.fly.conf" will have the
symbolic name "fly".

=cut

sub sources {
  my $self = shift;
  $SOURCES or return;
  return keys %$SOURCES;
} # sources(..)

=head2 source()

  $source = $browser->source;
  $source = $browser->source($new_source);

Sets or gets the current source.  The default source will the first
one found in the gbrowse.conf directory when sorted alphabetically.

If you attempt to set an invalid source, the module will issue a
warning but will not raise an exception.

=cut

sub source {
  my $self = shift;
  my $new_value = shift;
  my $old_value = $self->{ '_source' };
  unless( $SOURCES->{ $old_value } ) {
    ## Sometimes the last source that the user used no longer exists.
    ## This rescues them.
    $old_value = $DEFAULT_SOURCE;
    $self->{ '_source' } = $old_value;
  }
  if( defined( $new_value ) && ( $new_value ne $old_value ) ) {
    unless( $SOURCES->{ $new_value } ) {
      carp( "invalid source: $new_value" );
      return $old_value;
    }
    $self->{ '_source' } = $new_value;
    unless( ref( $SOURCES->{ $new_value } ) ) {
      # If the config hasn't yet been instantiated, do it.
      ## TODO: REMOVE
      print STDERR "Reading config for new source $new_value.." if DEBUG;
      flush STDERR;
      $SOURCES->{ $new_value } =
        Bio::Graphics::Browser::ConfigIO->new(
          '-file'=>$SOURCES->{ $new_value },
          '-safe'=>1
        )->read_config();
      ## TODO: REMOVE
      print STDERR "..done\n" if DEBUG;
    }
    # If the new config specifies a default width, use it.
    $self->width( $self->setting( 'default_width' ) ) if
      $self->setting( 'default_width' );

    # If the new config specifies a default language, use it.
    ## TODO: REMOVE
    warn "Getting language options" if DEBUG;
    my $default_language = $SOURCES->{ $new_value }->get( 'language' );
    my @languages        =
      ( http( 'Accept-language' ) =~ /([a-z]{2}-?[a-z]*)/ig );
    push( @languages, $default_language ) if $default_language;
    warn "languages = ", join( ',', @languages ) if DEBUG;
    if( @languages ) {
      $self->{ '_babelfish' }->language( @languages );
    }

    ## If the new config specifies any plugins to load, load 'em.
    $self->_initialize_plugins( $CONF_DIR );
  }
  return $old_value;
} # source(..)

=head2 config()

  $config = $browser->config;

This method returns a Bio::Graphics::Browser::Config object corresponding
to the current source.

=cut

sub config {
  my $self = shift;
  my $source = shift || $self->source();
  my $config = $SOURCES->{ $source };
  if( $config &&
      ref( $config ) ) {
    return $config;
  }
  unless( $config ) {
    carp( "invalid source: $source" );
    return;
  }
  # If the config hasn't yet been instantiated, do it.
  ## TODO: REMOVE
  print STDERR "Loading config file for source $source.." if DEBUG;
  flush STDERR;
  $config =
    Bio::Graphics::Browser::ConfigIO->new(
      '-file'=>$SOURCES->{ $source },
      '-safe'=>1
    )->read_config();
  ## TODO: REMOVE
  print STDERR "..done.\n" if DEBUG;
  $SOURCES->{ $source } = $config;
  return $config;
} # config(..)

=head2 setting()

  $value = $browser->setting(general => 'stylesheet');
  $value = $browser->setting(gene => 'fgcolor');
  $value = $browser->setting('stylesheet');

The setting() method returns the value of one of the current source\'s
configuration settings.  setting() takes two arguments.  The first
argument is the name of the stanza in which the configuration option
is located.  The second argument is the name of the setting.  Stanza
and option names are case sensitive, with the exception of the
"general" section, which is automatically folded to lowercase.

If only one argument is provided, then the "general" stanza is
assumed.

Option values are folded in such a way that newlines and tabs become
single spaces.  For example, if the "default features" option is defined like this:

 default features = Transcripts
                    Genes
	 	    Scaffolds

Then the value retrieved by 

  $browser->setting('general'=>'default features');

will be the string "Transcripts Genes Scaffolds".  Note that it is
your responsibility to split this into a list.  I suggest that you use
Text::Shellwords to split the list in such a way that quotes and
escapes are preserved.

Because of the default, you could also fetch this information without
explicitly specifying the stanza.  Combined with shellwords gives the
idiom:

 @defaults = shellwords($browser->setting('default features'));

=cut

# This is just a simple delegator (to $self->config()->get(..)) except
# that if the result value is undef, the default value (in $self->{
# '_defaults' }) will be used.
sub setting {
  my $self = shift;
  my $result = $self->config()->get( @_ );
  if( !defined( $result ) && ( scalar( @_ ) == 1 ) ) {
    return $self->{ '_defaults' }{ $_[ 0 ] };
  }
  return $result;
} # setting(..)

sub code_setting {
  shift->config()->get_and_eval( @_ );
} # code_setting(..)

=head2 description()

  $description = $browser->description( [ $source ] );

This is a shortcut method that returns the value of the "description"
option in the general section.  The value returned is a human-readable
description of the data source.

=cut

sub description {
  my $self = shift;
  return $self->config( shift )->get( 'description' );
} # description(..)

=head2 labels()

  @track_labels = $browser->labels( [\@order] );

This method returns the names of each of the track stanzas,
hereinafter called "track labels" or simply "labels".  These labels
can be used in subsequent calls as the first argument to setting() in
order to retrieve track-specific options.

=cut

sub labels {
  my $self  = shift;
  my $order = shift;
  my @labels = $self->config()->labels();
  if( $order ) { # custom order
    return @labels[ @$order ];
  } else {
    return @labels;
  }
} # labels(..)

=head2 default_labels()

  @default_labels = $browser->default_labels

This method returns the labels for each track that is turned on by
default.

=cut

sub default_labels {
  shift->config()->default_labels();
}

=head2 label2type()

  @feature_types = $browser->label2type($label,$lowres);

Given a track label, this method returns a list of the corresponding
sequence feature types in a form that can be passed to a FeatureProvider.
The optional $lowres flag can be used to tell label2type() to select a
set of features that are suitable when viewing large sections of the
sequence (it is up to the person who writes the configuration file to
specify this).

=cut

sub label2type {
  shift->config()->label2type( @_ );
}

=head2 citation()

  $citation = $browser->citation( $section [, $language ] )

This is a shortcut method that returns the citation for a given track.

=cut

sub citation {
  my $self      = shift;
  my ( $section, $language ) = @_;

  my $config = $self->config();
  my $citation;
  if( $language ) {
    for my $l ( $language->language() ) {
      $citation ||= $config->get( $section, "citation:$l" );
    }
  }
  return $citation || $config->get( $section, 'citation' );
} # citation(..)

=head2 header()

  $header = $browser->header;

This is a shortcut method that returns the header HTML for the gbrowse
page.

=cut

sub header {
  my $self = shift;
  my $header = $self->config()->get_and_eval( 'header' );
  if( ref( $header ) eq 'CODE' ) {
    my $h = eval{ $header->( @_ ) };
    warn $@ if $@;
    return $h;
  }
  return $header;
} # header()

=head2 footer()

  $footer = $browser->footer;

This is a shortcut method that returns the footer HTML for the gbrowse
page.

=cut

sub footer {
  my $self = shift;

  my $footer = $self->config()->get_and_eval( 'footer' );
  if( ref $footer eq 'CODE' ) {
    my $f = eval { $footer->( @_ ) };
    warn $@ if $@;
    return $f;
  }
  return $footer;
} # footer()

## This is the meaty deal.  The real mccoy.
sub gbrowse {
  my $self = shift;
  my ( $out_fh, $source, $old_source, $arg_page_settings ) = @_;

  unless( defined $source ) {
    $source = $DEFAULT_SOURCE;
  }
  $self->source( $source );
  my $source_changed =
    ( defined( $old_source ) && ( $source ne $old_source ) );

  ## TODO: REMOVE
  if( $source_changed ) {
    warn "source changed: $source ne $old_source" if DEBUG;
  }

  my $babelfish = $self->{ '_babelfish' };
  my $page_settings =
    $self->_get_page_settings( $source_changed, $arg_page_settings );

  warn "At the start, track order is " . Dumper( $page_settings->{ 'track_order' } ) if DEBUG;
  $page_settings->{ '_out_fh' } = $out_fh;

  ## TODO: REMOVE
  #return 0;

  ### PLUGINS #################################################################
  my $plugins = $self->_configure_plugins( $page_settings );
  my $plugin_type;
  if( param( 'plugin' ) && $plugins->{ param( 'plugin' ) } ) {
    $plugin_type =
      $plugins->{ param( 'plugin' ) }->type();
  }
  my $plugin_action = param( 'plugin_action' ) || '';
  warn "plugin_action = $plugin_action" if DEBUG_PLUGINS;
  
  ## GETTING THE SEGMENTS #####################################################
  my @segments = $self->_get_segments( $page_settings );
  if( ( $plugin_action eq $babelfish->tr( 'FIND' ) ) && param( 'plugin' ) ) {
    unless( $self->_do_plugin_find(
                     $page_settings,
                     $plugins,
                     param( 'plugin' ),
                     \@segments
                   ) ) {
      $plugin_action = 'Configure'; #reconfigure
    }
  } elsif( !@segments && $page_settings->{ 'name' } ) {
    ## TODO: Shouldn't this happen in _name2segments?
    # try again
    ## TODO: Put this back.. For now we're using the Hugo normalizer...
    #$self->_do_keyword_search( $page_settings, \@segments );
    unless( @segments ) {
      # last resort
      $self->_do_plugin_autofind( $page_settings, $plugins, \@segments );
    }
  }

  ## UPLOADED FILES #############################################################################################
  
  my ( $file_action ) = grep { /^modify\./ } param();
  my $file;
  if( $file_action ) {
    $file = $file_action;
    $file =~ s/^modify\.//;
  }

  ###############################################################################################
  ## DUMPS ######################################################################################
  ###############################################################################################

  # Check to see whether one of the plugin dumpers was invoked.  We
  # have to do this first before printing the header because the
  # plugins are responsible for generating the header.
  if( @segments &&
      ( $plugin_action eq $babelfish->tr( 'Go' ) ) &&
      ( $plugin_type eq 'dumper' ) ) {
    $self->_html_plugin_header( $page_settings, $plugins, param( 'plugin' ) );
    if( $self->_html_plugin_dump( param( 'plugin' ), $segments[ 0 ] ) ) {
      return( 0 );
    }
  }

  ###############################################################################################
  ## HANDLING FILE DOWNLOADS ######################################################################
  
  # This gets called if the user wants to download his annotation data
  if( my $to_download =
      ( param( $babelfish->tr( 'Download_file' ) ) ||
        ( $file_action &&
          ( param( $file_action ) eq $babelfish->tr( 'Download_file' ) ) &&
          $file ) ) ) {
    warn "FILE DOWNLOAD, download = $to_download" if DEBUG;
    ## Assertion: we've not yet printed the header.
    if( $page_settings->{ '_header_printed' }++ ) {
      warn "Assertion failure!  Header printed already.";
    }
    print $out_fh CGI::header( '-attachment' => $to_download,
  	                       '-type'       => 'application/octet-stream' );
    $self->_print_uploaded_file_features( $page_settings, $to_download );
    return 0;
  }
  
  ## HANDLING FILE UPLOADS ######################################################################

  # Creates local file, adds its url to page_settings.
  my ( $uploaded_file, $uploaded_file_action );
  if( param( 'Upload' ) &&
      ( my $in_file = param( 'upload_annotations' ) ) ) {
    $self->_handle_upload( $page_settings, $in_file );
  } elsif( param( 'new_upload' ) ) {
    $uploaded_file = $self->_new_upload( $page_settings );
    $uploaded_file_action = "modify.$file";
    param( '-name' => "modify.$file", '-value' => $babelfish->tr( 'Edit' ) );
  } elsif( defined( my $data = param( 'a_data' ) ) ) {
    $self->_handle_edit( $page_settings, $data );
  } elsif( my $data = ( param( 'auto' ) || param( 'add' ) ) ) {
    $self->_handle_quickie( $page_settings, $data );
  }
  
  if( $file_action && ( param( $file_action ) eq 'Delete File' ) ) {
    $self->_clear_uploaded_file( $page_settings, $uploaded_file );
  }
  
  warn "track order is " . Dumper( $page_settings->{ 'track_order' } ) if DEBUG;
  
  $self->_load_plugin_tracks( $page_settings, $plugins );
  $self->_ensure_page_settings_track_consistency( $page_settings );
  
  warn "after adjusting, track order is " . Dumper( $page_settings->{ 'track_order' } ) if DEBUG;
  
  ## UPDATING THE PERSISTENT SETTINGS##############################################################
  unless( $page_settings->{ '_header_printed' }++ ) {
    my $cookies = $self->_settings2cookies( $page_settings );
    push @$cookies, $self->_plugins2cookies( $plugins );
    print $out_fh CGI::header(
                    '-cookie'  => $cookies,
    	            '-charset' => $babelfish->tr( 'CHARSET' )
                  );
  }
  ## TODO: Wha?  Document this next line here.
  if( request_method() eq 'HEAD' ) {
    warn "Returning early because request_method is 'HEAD'" if DEBUG;
    return 0;
  }

  my $description =
    $self->setting( 'description' ) || 'Generic Genome Browser';
  
  ## STARTING THE PAGE ############################################################################
  unless( $page_settings->{ '_html_started' }++ ) {
    my $title;
    if( @segments == 1 ) {
      $title =
        ( $description.': '.
          $segments[ 0 ]->seq_id().":".
          $segments[ 0 ]->start().'..'.
          $segments[ 0 ]->end() );
    } else {
      $title = $description;
    }

    print $out_fh start_html(
                    '-title' => $title,
                    '-style' => { 'src' => $self->setting( 'stylesheet' ) }
                  );
  }
  
  ## HANDLE UPLOADED FILE EDITS ##################################################################
  if( $file_action && ( param( $file_action ) eq $babelfish->tr( 'Edit' ) ) ) {
    warn "Main: editing uploaded file" if DEBUG;
    $self->_html_edit_uploaded_file( $page_settings, $file );
  }
  
  ## HANDLE TRACK SETTINGS   #######################################################
    elsif( ( param( $babelfish->tr( 'Set_options' ) ) ||
             param( $babelfish->tr( 'Revert' ) ) ) &&
           !param(  $babelfish->tr( 'Cancel' ) ) &&
           !param(  $babelfish->tr( 'Redisplay' ) )
         ) {
    warn "Main: adjusting track options" if DEBUG;
    $self->_html_adjust_track_options( $page_settings );
  }
  
  ## HANDLE HELP PAGE   #######################################################
    elsif( param( 'help' ) ) {
    warn "Main: showing help" if DEBUG;
    $self->_html_help( $page_settings );
  }
  
  ## HANDLE PLUGIN ABOUT PAGE #####################################################
    elsif( $plugin_action eq $babelfish->tr( 'About' ) ) {
    warn "Main: showing about plugins" if DEBUG;
    $self->_html_plugin_about( $page_settings, $plugins, param( 'plugin' ) );
  }
  
  ## HANDLE PLUGIN CONFIGURATION####################################################
    elsif( ( $plugin_action eq $babelfish->tr( 'Configure' ) ) ||
           ( ( $plugin_action eq $babelfish->tr( 'Go' ) ) &&
             ( $plugin_type =~ /^(finder|annotator)$/i ) ) ) {
    warn "Main: showing plugin configurator" if DEBUG;
    $self->_html_plugin_configure( $page_settings, $plugins, param( 'plugin' ) );
  }  
  ## MAIN DISPLAY
    else {
    ## TODO: Do we ever use 'head'?  I mean, is it ever the case that we don't want the header?
    if( $page_settings->{ 'head' } ) {
      unless( $page_settings->{ '_header_printed' }++ ) {
        my $header = $self->header();
        print $out_fh ( $header ? $header : h1( $description ) );
      }
    }
    warn "Main: showing main display" if DEBUG;
    $self->_html_main_display( $page_settings, $plugins, \@segments );
  }
  
  warn "showing footer" if DEBUG;
  $self->_html_footer( $page_settings );

  return 1; # success!
} # gbrowse(..)

=head1 Protected object methods
=cut

sub _initialize_browser {
  my $self = shift;

  # Create the babelfish.
  ## TODO: REMOVE
  warn "Creating babelfish.." if DEBUG;
  $self->{ '_babelfish' } =
    Bio::Graphics::Browser::I18n->new( "$CONF_DIR/languages" );
  # Note that the babelfish will get some languages when the source is set.

  # Give it a unique name..
  # The basetime modulo 100 times the pid should do the trick.
  $self->unique_id( $^T % ( $$ * 100 ) );
} # _initialize_browser()

sub _get_page_settings {
  my $self = shift;
  my ( $source_changed, $arg_page_settings ) = @_;

  # Read from cookie, if there is one.
  my $page_settings = $self->_cookie_page_settings();

  if( defined $page_settings && %$page_settings ) {
    $self->_ensure_page_settings_track_consistency( $page_settings );
  } else {
    %$page_settings = ();
    $self->_default_page_settings( $page_settings );
  }

  if( !$source_changed ||
      ( request_method() eq 'GET' ) ) {
    if( !$source_changed ) {
      warn "Source did not change, so we're using the CGI settings." if DEBUG;
    } else {
      warn "Using GET mode, so we're using the CGI settings." if DEBUG;
    }
    $self->_CGI_page_settings( $page_settings );
  } else {
    ## TODO: REMOVE
    warn "Source did change, so we're NOT using the CGI settings." if DEBUG;
  }

  # Now incorporate the incoming page_settings, if there are any.
  if( defined( $arg_page_settings ) && %$arg_page_settings ) {
    unless( defined( $page_settings ) && %$page_settings ) {
      $self->_default_page_settings( $page_settings );
    }
    foreach my $key ( keys %$arg_page_settings ) {
      $page_settings->{ $key } = $arg_page_settings->{ $key };
    }
  }

  if( $source_changed ) {
    # Restore old reference point.
    param( 'name' => $page_settings->{ 'name' } );
    ## If there's a reference in the [GENERAL] section, use it.
    ## TODO: REMOVE?
    if( defined $self->setting( 'reference' ) ) {
      $page_settings->{ 'seq_id' } = $self->setting( 'reference' );
    }
  }
  return $page_settings;
} # _get_page_settings(..)

# Returns a new page_settings hash
sub _cookie_page_settings {
  my $self = shift;

  my $source = $self->source();

  my %settings = cookie( "gbrowse_$source" );

  warn "cookie settings for gbrowse_$source are " . Dumper( \%settings ) if DEBUG;

  my $settings_are_valid = 1;
  if( %settings ) {  # if cookie is there, then validate it
    $settings_are_valid = ( $settings{ 'v' } == $VERSION );
    warn "settings_are_valid (version) = $settings_are_valid" if DEBUG;
  
    if( $settings_are_valid ) {
      $settings_are_valid =
        ( ( defined $settings{ 'width' } ) &&
          ( $settings{ 'width' } > 100 ) &&
          ( $settings{ 'width' } < 5000 ) );
      warn "settings_are_valid (width) = $settings_are_valid" if DEBUG;
    }
  
    # Make sure the source is valid.
    if( $settings_are_valid ) {
      my %sources_present = map { $_ => 1 } $self->sources();
      $settings_are_valid = $sources_present{ $settings{ 'source' } };
      warn "settings_are_valid (source) = $settings_are_valid" if DEBUG;
    }
  
    # the single 'tracks' value of the cookie gets parsed to become the
    # 'track_order' and 'track_options' keys of the page settings
    my @tracks;
    if( $settings_are_valid && ( defined $settings{ 'tracks' } ) ) {
      @tracks = split( $;, $settings{ 'tracks' } );
      $settings{ 'track_order' }    = [];  # make sure these are clean
      $settings{ 'track_options' }  = {};
      foreach my $track ( @tracks ) {
        warn "track = $track" if DEBUG;
        my ( $label, $visible, $option, $limit ) =
          ( $track =~ m!^(.+)/(\d+)/(\d+)/(\d+)$! );
        warn "label = $label, visible = $visible, option = $option, limit = $limit" if DEBUG;
    
        if( $label ) {
          push @{ $settings{ 'track_order' } }, $label;
          $settings{ 'track_options' }{ $label } = 
            { 'visible' => $visible,
              'options' => $option,
              'limit'   => $limit };
        } else { # No $label: corrupt cookie; purge it.
          undef $settings_are_valid;
        }
      }
      warn "settings_are_valid (label) = $settings_are_valid" if DEBUG;
  
      if( $settings_are_valid ) {
        $settings_are_valid =
          ( ref( $settings{ 'track_order' } ) &&
            ( @{ $settings{ 'track_order' } } > 0 ) );
        warn "settings_are_valid (track_order) = $settings_are_valid" if DEBUG;
      }
    } # End if there's anything in $settings{ 'tracks' }, parse it.
  } # End if %settings, validate cookie settings.

  if( $settings_are_valid && %settings ) {
    return \%settings;
  } else {
    return {};
  }
} # _cookie_page_settings()

# Takes and modifies a page_settings hash
sub _CGI_page_settings {
  my $self = shift;
  my ( $settings ) = @_;

  my $babelfish = $self->{ '_babelfish' };

  $settings->{ 'width' } = param( 'width' ) if param( 'width' );

  if( ( param( 'seq_id' ) || param( 'ref' ) ) &&
      ( ( request_method() eq 'GET' ) ||
	( param( 'name' ) eq param( 'prevname' ) ) ||
	( grep { /zoom|nav|overview/ } param() ) )
  ) {
    ## TODO: REMOVE.  Testing.
    if( request_method() eq 'GET' ) {
      warn "Okay we're zoomnaving because request_method is GET" if DEBUG;
    } elsif( param( 'name' ) eq param( 'prevname' ) ) {
      warn "Okay we're zoomnaving because ( param( 'name' ) eq param( 'prevname' ) )" if DEBUG;
    } elsif( grep { /zoom/ } param() ) {
      warn "Okay we're zoomnaving because grep /zoom/ param()" if DEBUG;
    } elsif( grep { /nav/ } param() ) {
      warn "Okay we're zoomnaving because grep /nav/ param()" if DEBUG;
    } elsif( grep { /overview/ } param() ) {
      warn "Okay we're zoomnaving because grep /overview/ param()" if DEBUG;
    } else {
      warn "Okay we're zoomnaving, but I can't figure out why." if DEBUG;
    }
    $settings->{ 'seq_id' } =
      ( param( 'seq_id' ) || param( 'ref' ) || $self->setting( 'reference' ) );
    if( param( 'start' ) =~ /^[\d-]+/ ) {
      $settings->{ 'start' } = param( 'start' );
    }
    if( param( 'stop' ) =~ /^[\d-]+/ ) {
      $settings->{ 'end' } = param( 'stop' );
    } elsif( param( 'end' ) =~ /^[\d-]+/ ) {
      $settings->{ 'end' } = param( 'end' );
    }
    $self->_zoomnav( $settings );
    $settings->{ 'name' } =
      "$settings->{seq_id}:$settings->{start}..$settings->{end}";
    param( 'name' => $settings->{ 'name' } );
  }

  # Set all the rest of the params.
  foreach ( qw( name source plugin show_tracks_table ins head keystyle ) ) {
    $settings->{ $_ } = param( $_ ) if defined param( $_ );
  }

  ## TODO: Note that this here code is probably scrappable, when external tracks are all handled via the nice Config chaining dealy.
  ## TODO: This is assuming that the eurl entries will all begin with
  ## http or ftp, and that's not actually tested.
  if( my @external = param( 'eurl' ) ) {
    my %external_tracks = map { $_ => 1 } @external;
    foreach my $external_track ( @external ) {
      next if exists $settings->{ 'track_options' }{ $external_track };
      $settings->{ 'track_options' }{ $external_track } =
        { 'visible' => 1,
          'options' => 0,
          'limit'   => 0 };
      push( @{ $settings->{ 'track_order' } }, $external_track );
    }
    # remove any URLs that aren't on the list
    foreach my $track ( keys %{ $settings->{ 'track_options' } } ) {
      next unless /^(http|ftp):/;
      next if exists $external_tracks{ $track };
      delete $settings->{ 'track_options' }{ $track };
    }
  }

  # Do any requested actions.  Note the elsifs.
  if( param( $babelfish->tr( 'Revert' ) ) ||
      param( $babelfish->tr( 'RevertQuick' ) ) ) {
    warn "resetting defaults..." if DEBUG;
    $self->_default_page_settings_tracks( $settings );
  } elsif( param( $babelfish->tr( 'Reset' ) ) ) {
    %$settings = ();
    Delete_all(); # Clear CGI params (&Delete_all() is from CGI.pm)
  } elsif( param( $babelfish->tr( 'Adjust_Order' ) ) &&
           !param( $babelfish->tr( 'Cancel' ) ) ) {
    # Adjust track options:
    warn "adjusting track options" if DEBUG;
    foreach ( grep {/^option\./} param() ) {
      my ( $track ) = /(\d+)/;
      my $label     = $settings->{ 'track_order' }[ $track ];
      my $option    = param( $_ );
      $settings->{ 'track_options' }{ $label }{ 'options' } = $option;
    }
    foreach ( grep {/^limit\./} param() ) {
      my ( $track ) = /(\d+)/;
      my $feature   = $settings->{ 'track_order' }[ $track ];
      my $option    = param( $_ );
      $settings->{ 'track_options' }{ $feature }{ 'limit' } = $option;
    }

    # Adjust track order:
    my @labels = @{ $settings->{ 'track_order' } };
    warn "adjusting track order: labels = @labels" if DEBUG;
    my %seen_it_already;
    foreach ( grep {/^track\./} param() ) {
      warn "$_ => ", param( $_ ) if DEBUG;
      next unless /^track\.(\d+)/;
      my $track = $1;
      my $label = param( $_ );
      next unless ( length $label > 0 );
      next if $seen_it_already{ $label }++;
      warn "$label => track $track" if DEBUG;
  
      # figure out where features currently are
      my $i = 0;
      my %order = map { $_ => $i++ } @labels;
  
      # remove feature from wherever it is now
      my $current_position = $order{ $label };
      warn "current position of $label = $current_position" if DEBUG;
      splice( @labels, $current_position, 1 );
  
      warn "new position of $label = $track" if DEBUG;
      # insert feature into desired position
      splice( @labels, $track, 0, $label );
    }
    $settings->{ 'track_order' } = \@labels;
  } # End if there's an action to do.

  ## Make only the 'track.label' and/or 'label' tracks visible.
  if( param( 'track.label' ) || param( 'label' ) ) {
    # Start by clearing all visibility...
    foreach ( @{ $settings->{ 'track_order' } } ) {
      $settings->{ 'track_options' }{ $_ }{ 'visible' } = 0;
    }
    # From the main page we use the 'label' all-in-one param; from the
    # track options page we use the 'track.label' checkbox param.
    foreach ( param( 'track.label' ), map { split /[+-]/ } param( 'label' ) ) {
      $settings->{ 'track_options' }{ $_ }{ 'visible' } = 1;
    }
  }

} # _CGI_page_settings(..)

# Takes and modifies a page_settings hash.
sub _default_page_settings {
  my $self = shift;
  my ( $settings ) = @_;

  warn "Setting default settings" if DEBUG;
  $settings->{ 'name' }   = '';
  $settings->{ 'seq_id' } = '';
  $settings->{ 'start' }  = '';
  $settings->{ 'end' }    = '';
  $settings->{ 'width' }  = $self->setting( 'default width' );
  $settings->{ 'source' } = $self->source();
  $settings->{ 'id' }     = md5_hex( rand );  # new identity
  $settings->{ 'v' }      = $VERSION;
  $settings->{ 'show_tracks_table' }    = 1;
  $settings->{ 'ins' }    = 1;
  $settings->{ 'head' }   = 1;
  $settings->{ 'keystyle' }     = 'between';

  $self->_default_page_settings_tracks( $settings );
} # _default_page_settings(..)

sub _default_page_settings_tracks {
  my $self = shift;
  my ( $settings ) = @_;

  my @labels = $self->labels();
  $settings->{ 'track_order' } = \@labels;
  warn "default order = " . Dumper( \@labels ) if DEBUG;

  # Just use the default labels.
  foreach my $label ( @labels ) {
    $settings->{ 'track_options' }{ $label } =
      { 'visible' => 0,
        'options' => 0,
        'limit'   => 0 };
  }
  foreach my $default_label ( $self->default_labels() ) {
    $settings->{ 'track_options' }{ $default_label }{ 'visible' } = 1;
  }
} # _default_page_settings_track_order(..)

# This is called to check that the list of feature types given
# in the configuration file are consistent with the features
# given in the user's cookie.  If not, the settings are adjusted
# as best we can. The attempt here is to allow
# the administrator to add new feature stanzas
# without invalidating users' old settings.
sub _ensure_page_settings_track_consistency {
  my $self = shift;
  my ( $settings ) = shift;
  my %configured_labels = map { $_ => 1 } $self->labels();

  ## Add to the settings any tracks in the config file that
  ## weren't in the cookie.
  foreach my $track_label (
    grep { !exists( $settings->{ 'track_options' }{ $_ } ) }
         keys %configured_labels
  ) {
    $settings->{ 'track_options' }{ $track_label }{ 'visible' } = 0;# invisible
    $settings->{ 'track_options' }{ $track_label }{ 'options' } = 0;# autobump
    push @{ $settings->{ 'track_order' } }, $track_label;
  }
  # Remove from the settings any track  that are not mentioned in the
  # config file, excepting Uploaded and remote URL features.
  # This may happen if a stanza is removed from the config file.
  my %extra = map { $_ => 1 }
               grep { !/^(http|ftp|das|file|plugin):/ &&
                      !$configured_labels{ $_ } }
                    keys %{ $settings->{ 'track_options' } };
  # remove extra from tracks && options
  if( %extra ) {
    delete $settings->{ 'track_options' }{ $_ } foreach keys %extra;
  }

  # make sure that tracks are completely consistent with options
  $settings->{ 'track_order' } =
    [ grep { exists $settings->{ 'track_options' }{ $_ } }
           @{ $settings->{ 'track_order' } } ];
} # _ensure_page_settings_track_consistency(..)

sub _html_main_display {
  my $self = shift;
  my ( $settings, $plugins, $segments ) = @_;

  #warn "_html_main_display: \$segments are " . Dumper( $segments ) if DEBUG;
  ## TODO: REMOVE
  warn "_html_main_display 1" if DEBUG;

  my $babelfish = $self->{ '_babelfish' };
  my $out_fh = $settings->{ '_out_fh' };

  my $segment;
  # It's bad if we don't have any segments, but only if they asked for one.
  if( ( @$segments == 0 ) &&
      ( my $name = $settings->{ 'name' } ) ) {
    unless( $settings->{ '__already_printed_not_found' } ) {
      $self->_html_error( $settings, $babelfish->tr( 'NOT_FOUND', $name ) );
    }
  } elsif( @$segments == 1 ) {
    $segment = $segments->[ 0 ];
    ## TODO: Didn't we already handle this one (segment length short), in gbrowse?
    if( $segment->length() < 4 ) { # TODO: Magic #
      $segment = $self->_truncated_segment( $segment );
    }
    my $divider = $self->setting( 'unit_divider' ) || 1;
      } # End if size of @segments is 0 or 1.

  ## TODO: REMOVE
  warn "_html_main_display 2" if DEBUG;

  # print the top of the form, with navigation bar, etc
  print $out_fh
    start_multipart_form(
      '-name'   => 'mainform',
      '-action' => url( '-relative' => 1, '-path_info' => 1 )
    );
  ## TODO: RENAME.  _html should be reserved for those that print to screen.
  print $out_fh $self->_html_navigation_table( $settings, $plugins, $segment );

  ## TODO: REMOVE
  warn "_html_main_display 2 A" if DEBUG;

  ## TODO: RENAME.  _html should be reserved for those that print to screen.
  print $out_fh $self->_html_frag( 'html2' );

  ## TODO: REMOVE
  warn "_html_main_display 2 B" if DEBUG;

  # if more than one segment, then list them all
  my $external_configs;
  if( @$segments > 1 ) {
    warn "Multiple segments" if DEBUG;
    $self->_html_multiple_choices( $settings, $segments );
  } elsif( @$segments == 1 ) {
    my $segment = $segments->[ 0 ];

    warn "Using segment $segment" if DEBUG;

    ## TODO: This will go away when we implement 'config chaining'
    $external_configs = $self->_load_external_sources( $settings );
    print $out_fh $self->_get_overview_panel_html(
                    $settings,
                    $segment,
                  );
    print $out_fh
      $self->_get_detail_panel_html(
        $settings,
        $plugins,
        $segment,
        $external_configs
      );
  }

  ## TODO: REMOVE
  warn "_html_main_display 3" if DEBUG;

  # print the bottom of the form, with plugins, tracks, settings, etc.
  print $out_fh $self->_html_frag( 'html3' );
  print $out_fh $self->_get_plugins_table_html( $settings, $plugins );
  print $out_fh $self->_html_frag( 'html4' );
  print $out_fh $self->_get_tracks_table_html( $settings );
  print $out_fh $self->_html_frag( 'html5' );
  print $out_fh $self->_get_settings_table_html( $settings );
  print $out_fh $self->_html_frag( 'html6' );
  print $out_fh p(),
                $self->_get_upload_table_html( $settings, $external_configs );
  print $out_fh p(),
                $self->_get_external_table_html( $settings, $external_configs );
  print $out_fh end_form();

  ## TODO: REMOVE
  warn "_html_main_display 4" if DEBUG;

  # clean us up
  ## TODO: Is this necessary to do this here?  Won't it be collected with the Config, later?
  foreach my $config ( keys %$external_configs ) {
    next unless( $config && ref( $config ) );
    $self->config()->remove_config( $config );
    $config->destroy();
  }
} # _html_main_display(..)

sub _get_detail_panel_html {
  my $self = shift;
  my ( $settings, $plugins, $segment, $external_configs ) = @_;

  ## TODO: REMOVE
  warn "_get_detail_panel_html 1" if DEBUG;

  ## TODO: REMOVE.  This is for testing just the overview panel..
  #return;

  my $babelfish = $self->{ '_babelfish' };

  my ( $img, $map );
  my $cell = '';

  my $max_segment = $self->setting( 'max_segment' );
  if( $segment->length() <= $max_segment ) {

    ## TODO: REMOVE
    warn "_get_detail_panel_html 2" if DEBUG;

    $self->_load_plugin_annotations(
      $settings,
      $plugins,
      $segment,
      $external_configs
    );

    $self->width( $settings->{ 'width' } );
    my @tracks_to_show =
      grep { $settings->{ 'track_options' }{ $_ }{ 'visible' } }
           @{ $settings->{ 'track_order' } };
    my %options =
      map { $_ => $settings->{ 'track_options' }{ $_ }{ 'options' } }
          @tracks_to_show;
    my %limit   =
      map { $_ => $settings->{ 'track_options' }{ $_ }{ 'limit' } }
          @tracks_to_show;

    ( $img, $map ) =
      $self->_get_detail_image_html(
        $settings,
        'segment'          => $segment,
        'external_configs' => $external_configs,
	'tracks'           => \@tracks_to_show,
        'options'          => \%options,
        'limit'            => \%limit,
        'do_map'           => 1,
        'do_centering_map' => 1,
        'lang'             => $babelfish,
        ## AHA! 'ks' means 'keystyle'.  Now we know.
	'keystyle'         => $settings->{ 'keystyle' },
      );
    $cell .= $img;
  } else { # the segment is greater than max_segment.
    my $default_segment = $self->setting( 'default_segment' );

    ## TODO: REMOVE
    warn "_get_detail_panel_html 2: The segment is too big." if DEBUG;

    $cell .=
      i(
        $babelfish->tr(
          'TOO_BIG',
          commas( $max_segment ),
          commas( $default_segment )
        )
      );
  } # End if the length of $segment is less than $max_segment .. else ..

  $cell .= "\n";

  my $table =
    table(
      { '-border'  => 0,
        '-width'   => '100%' },
      TR(
        { '-class' => 'databody' },
        td(
          { '-align' =>'center' },
          $cell
        )
      )
    ) . "\n";
  if( $map ) {
    $table .= $map;
  }
  $table .=
    hidden( '-name'     => 'session_id',
            '-value'    => $self->unique_id(),
            '-override' => 1 );
  return $table;
} # _get_detail_panel_html(..)

###############################################################################################

# this is called to flatten the settings into an HTTP cookie
sub _settings2cookies {
  my $self = shift;
  my ( $settings ) = @_;

  my %cookie_settings;

  for my $key ( keys %$settings ) {
    next if $key =~ /^(track_order|track_options)$/;  # handled specially
    next if $key =~ /^\_/;  # private data, not to be saved
    if( ref( $settings->{ $key } ) eq 'ARRAY' ) {
      $cookie_settings{ $key } = join( $;, @{ $settings->{ $key } } );
    } else {
      $cookie_settings{ $key } = $settings->{ $key };
    }
  } # End foreach settings key, if it's an array ref, join the values.

  # the "track_options" and "track_order" keys map to a single array
  # contained in the "tracks" key of the cookie
  my @array = map { join( "/",
			  $_,
			  $settings->{ 'track_options' }{ $_ }{ 'visible' },
			  $settings->{ 'track_options' }{ $_ }{ 'options' },
			  $settings->{ 'track_options' }{ $_ }{ 'limit' }
                        ) } @{ $settings->{ 'track_order' } };
  $cookie_settings{ 'tracks' } = join( $;, @array );

  warn "[outgoing] cookie settings are " . Dumper( \%cookie_settings ) if DEBUG;

  my @cookies;
  my $source = $self->source();
  push( @cookies, cookie(
                    '-name'    => "gbrowse_$source",
		    '-value'   => \%cookie_settings,
		    '-expires' => '+3M'
                  ) );
  push( @cookies, cookie(
                    '-name'    => 'gbrowse_source',
		    '-value'   => $source,
		    '-expires' => '+3M'
                  ) );
  # Also add the session_id cookie for Browser object persistence.
  push( @cookies, cookie(
                    '-name'    => 'gbrowse_session_id',
		    '-value'   => $self->unique_id(),
                    '-expires' => $self->setting( 'browser_ttl' )
                  ) );
  # And use this opportunity to reestablish our own expiry.
  $self->expiration_time( $self->setting( 'browser_ttl' ) );
  warn "cookies = ( " . join( ', ', @cookies ) . " )" if DEBUG;
  return \@cookies;
} # _settings2cookies(..)

# prints the zooming and navigation bar
sub _html_navigation_table {
  my $self = shift;
  my ( $settings, $plugins, $segment ) = @_;

  my $babelfish = $self->{ '_babelfish' };

  my $buttons_dir = $self->setting( 'buttons' );
  my $self_url    = url( '-relative' => 1, '-path_info' => 1 );

  # Shoot.  There has to be a more OO way to do this:
  my $oligo =
    ( $plugins->{ 'OligoFinder' } ?
      ', oligonucleotide (15 bp minimum)' :
      '' );
  my $help  =
    a( { '-href'   => ( url( '-relative' => 1, '-path_info' => 1 ) .
                        "?help=general" ),
         '-target' => 'help' },
       '[' . $babelfish->tr( 'Help' ) . ']' );
  my $rand  = substr( md5_hex( rand ), 0, 5 );

  ## TODO: REMOVE
  warn "_html_navigation_table" if DEBUG;

  return
    table(
      { '-border'      => 0,
        '-width'       => '100%',
        '-cellspacing' => 0,
        '-class'       => 'searchtitle' },
      ( $settings->{ 'ins' } ?
        (
         TR(
            td(
              { '-align' => 'left', '-colspan' => 3 },
              b( $babelfish->tr( 'INSTRUCTIONS' ) . ': ' ),
              $babelfish->tr( 'SEARCH_INSTRUCTIONS', $oligo ),
              $babelfish->tr( 'NAVIGATION_INSTRUCTIONS' )
            )
         ),
         TR(
           td(
             { '-align'   => 'left',
               '-colspan' => 3 },
              $self->_get_examples_html(),
              p(),
           )
         ),
        ) : ()
      ),
      TR(
        th( { '-align'   => 'left',
              '-colspan' => 3 },
          a(
            { '-href' => ( "$self_url?rand=$rand;head=" .
                           ( ( !$settings->{ 'head' } ) || 0 ) ) },
            ( '[' .
              $babelfish->tr(
                 $settings->{ 'head' } ?
                 'HIDE_HEADER' :
                 'SHOW_HEADER'
              ) .
              ']'
            )
          ),
          a(
            { '-href' => ( "$self_url?rand=$rand;ins=" .
                           ( ( !$settings->{ 'ins' } ) || 0 ) ) },
            ( '[' .
              $babelfish->tr(
                $settings->{ 'ins' } ?
                'HIDE_INSTRUCTIONS'  :
                'SHOW_INSTRUCTIONS'
              ) .
              ']'
            )
          ),
          ( $settings->{ 'name' } ||
            ( $settings->{ 'seq_id' } ?
              (
               a(
                 { '-href' =>
                     $self->_get_bookmark_link_html( $settings ) },
                 '[' . $babelfish->tr( 'BOOKMARK' ) . ']'
               ),
               a(
                 { '-href'   =>
                     $self->_get_image_link_html( $settings ),
                   '-target' => '_blank' },
                 '[' . $babelfish->tr( 'IMAGE_LINK' ) . ']'
               ),
              ) : (),
              $help
            )
          )
        )
      ),
      TR(
        { '-class' => 'searchbody' },
        td( { '-align'   => 'left',
              '-colspan' => 3 },
            ( $self->setting( 'html1' ) || '' )
        )
      ),
      TR(
        { '-class' => 'searchbody',
          '-align' => 'left' },
        td(
          { '-align' => 'left' },
          b( $babelfish->tr( 'Landmark' ) ),
          br(),
          textfield( '-name' => 'name', '-size' => 40 ),
          ( submit( '-name' => $babelfish->tr( 'Search' ) ) .
            '&nbsp;' .
            submit( '-name'  => $babelfish->tr( 'Reset' ),
                    '-class' => 'reset_button' ) )
        ),
        td(
           { '-class' => 'searchbody',
             '-align' => 'left' },
           ( $segment ?
             ( b( $babelfish->tr( 'Scroll' ) . ': ' ),
               br(),
               $self->_get_navbar_html( $segment, $buttons_dir )
             ) : ''
           )
        )
      )
    );
} # _html_navigation_table(..)

sub _get_examples_html {
  my $self = shift;

  ## TODO: REMOVE
  warn "_get_examples_html" if DEBUG;

  my $examples = $self->setting( 'examples' ) or return;;
  my @examples = split( /\s+/, $examples );
  return unless @examples;

  my $babelfish = $self->{ '_babelfish' };

  my $url    = url( '-relative' => 1, '-path_info' => 1 );
  my $source = $self->source();
  my @urls   =
    map { a( { '-href' => "$url?source=$source;name=" . escape( $_ ) }, $_ ) }
        @examples;
  return b( $babelfish->tr( 'Examples' ) ) . ': ' . join( ', ', @urls ) . ". ";
} # _get_examples_html(..)

sub _get_bookmark_link_html {
  my $self = shift;
  my ( $settings ) = @_;

  ## TODO: REMOVE
  warn "_get_bookmark_link_html" if DEBUG;

  my $q = new CGI( '' );
  my @keys = ( $settings->{ 'name' }   ?
               qw( name source width ) :
               qw( start end seq_id source width ) );
  foreach my $key ( @keys ) {
    $q->param( '-name' => $key, '-value' => $settings->{ $key } );
  }

  # handle selected features slightly differently
  my @selected =
    grep { $settings->{ 'track_options' }{ $_ }{ 'visible' } &&
           !/^(file|ftp|http):/ }
         @{ $settings->{ 'track_order' } };
  $q->param( '-name' => 'label', '-value' => join( '-', @selected ) );

  # handle external urls
  my @url = grep { /^(ftp|http):/ } @{ $settings->{ 'track_order' } };
  $q->param( '-name' => 'eurl', '-value' => \@url );

  return $q->url( '-relative' => 1, '-path_info' => 1, '-query' => 1 );
} # _get_bookmark_link_html(..)

sub _get_image_link_html {
  my $self = shift;
  my ( $settings ) = @_;
  my $rand = md5_hex( rand );

  ## TODO: REMOVE
  warn "_get_image_link_html" if DEBUG;

  return ( url( '-relative' => 1, '-path_info' => 1 ) .
           "?help=link_image;rand=$rand" );
} # _get_image_link_html(..)

# This generates the navigation bar with the arrows
sub _get_navbar_html {
  my $self = shift;
  my ( $segment, $buttons_dir ) = @_;

  ## TODO: REMOVE
  warn "_get_navbar_html" if DEBUG;

  my $span      = $segment->length();
  my $half      = $self->_unit_label( int( $span ) / 2 );
  my $full      = $self->_unit_label( $span );
  my $fine_zoom = $self->get_zoomincrement();

  ## TODO: REMOVE
  warn "_get_navbar_html B" if DEBUG;

  my @lines;
  push( @lines,
        hidden( '-name'     => 'last_source',
                '-value'    => $self->source(),
                '-override' => 1 )
      );
  push( @lines,
        hidden( '-name'     => 'start',
                '-value'    => $segment->abs_start(),
                '-override' => 1 )
      );
  push( @lines,
        hidden( '-name'     => 'end',
                '-value'    => $segment->abs_end(),
                '-override' => 1 )
      );
  push( @lines,
        hidden( '-name'     => 'seq_id',
                '-value'    => ( '' . $segment->abs_seq_id() ),
                '-override' => 1 )
      );
  push( @lines,
        hidden( '-name'     => 'prevname',
                '-value'    => scalar( param( 'name' ) ),
                '-override' => 1 )
      );

  ## TODO: REMOVE
  warn "_get_navbar_html C" if DEBUG;

  push( @lines,
        ( image_button( '-src'    => "$buttons_dir/green_l2.gif",
                        '-name'   => "left $full",
                        '-border' => 0,
                        '-title'  => "left $full" ),
          image_button( '-src'    => "$buttons_dir/green_l1.gif",
                        '-name'   => "left $half",
                        '-border' => 0,
                        '-title'  => "left $half" ),
          '&nbsp;',
          image_button( '-src'    => "$buttons_dir/minus.gif",
                        '-name'   => "zoom out $fine_zoom",
                        '-border' => 0,
                        '-title'  => "zoom out $fine_zoom" ),
          '&nbsp;',
          $self->_get_zoombar_html( $segment, $buttons_dir ),
          '&nbsp;',
          image_button(
            '-src'    => "$buttons_dir/plus.gif",
            '-name'   => "zoom in $fine_zoom",
            '-border' => 0,
            '-title'  => "zoom in $fine_zoom"
          ),
          '&nbsp;',
          image_button(
            '-src'    => "$buttons_dir/green_r1.gif",
            '-name'   => "right $half",
            '-border' => 0,
            '-title'  => "right $half"
          ),
          image_button(
            '-src'    => "$buttons_dir/green_r2.gif",
            '-name'   => "right $full",
            '-border' => 0,
            '-title'  => "right $full"
          )
        )
    );

  return join( '', @lines );
} # _get_navbar_html(..)

# this generates the popup zoom menu with the window sizes
sub _get_zoombar_html {
  my $self = shift;
  my ( $segment, $buttons_dir ) = @_;

  ## TODO: REMOVE
  warn "_get_zoombar_html" if DEBUG;

  my $babelfish = $self->{ '_babelfish' };

  my $show = $babelfish->tr( 'Show' );

  my %seen;
  my @ranges	= grep { !$seen{ $_ }++ }
                       sort { $b <=> $a}
                       ( $segment->length(), $self->get_ranges() );
  my %labels    = map { $_ => $show . ' ' . $self->_unit_label( $_ ) } @ranges;
  return popup_menu(
           '-class'    => 'searchtitle',
           '-name'     => 'span',
           '-values'   => \@ranges,
           '-labels'   => \%labels,
           '-default'  => $segment->length(),
           '-force'    => 1,
           '-onChange' => 'document.mainform.submit()',
	 );
} # _get_zoombar_html(..)

# convert bp into nice Mb/Kb units
sub _unit_label {
  my $self = shift;
  my ( $value ) = @_;

  my $unit     = $self->setting( 'units' )        || 'bp';
  my $divider  = $self->setting( 'unit_divider' ) || 1;
  $value /= $divider;

  return   $value >= 1e9  ? sprintf( "%.4g G%s", ( $value / 1e9 ), $unit )
         : $value >= 1e6  ? sprintf( "%.4g M%s", ( $value / 1e6 ), $unit )
         : $value >= 1e3  ? sprintf( "%.4g k%s", ( $value / 1e3 ), $unit )
	 : $value >= 1    ? $value." $unit"
	 : $value >= 1e-2 ? sprintf( "%.4g c%s", ( $value * 100 ), $unit )
	 : $value >= 1e-3 ? sprintf( "%.4g m%s", ( $value * 1e3 ), $unit )
	 : $value >= 1e-6 ? sprintf( "%.4g u%s", ( $value * 1e6 ), $unit )
	 : $value >= 1e-9 ? sprintf( "%.4g n%s", ( $value * 1e9 ), $unit )
         :                  sprintf( "%.4g p%s", ( $value * 1e12 ), $unit );
} # _unit_label(..)

# convert Mb/Kb back into bp... or a ratio
sub _unit_to_value {
  my $self = shift;
  my ( $string ) = @_;

  my $sign              = ( ( $string =~ /out|left/ ) ? '-' : '+' );
  my ( $value, $units ) = ( $string =~ /([\d.]+) ?(\S+)/ );

  return unless defined( $value );
  if( $units eq '%' ) { # percentage;
    $value /= 100;
  } elsif( $units =~ /kb/i ) {
    $value *= 1000;
  } elsif( $units =~ /mb/i ) {
    $value *= 1e6;
  } elsif( $units =~ /gb/i ) {
    $value *= 1e9;
  }
  return "$sign$value";
} # _unit_to_value(..)

sub _get_plugins_table_html {
  my $self = shift;
  my ( $settings, $plugins ) = @_;

  my $source_menu_html = $self->_get_source_menu_html( $settings );
  my $plugin_menu_html = $self->_get_plugin_menu_html( $settings, $plugins );

  unless( $source_menu_html ) {
    ## We have to say something about the source or else nobody will
    ## ever know and the next time the user refreshes they'll be
    ## sorry, and then we'll be sorry, and then sorryness will reign
    ## supreme.  We don't want that.
    $source_menu_html =
      hidden(
        '-name'     => 'source',
        '-value'    => $self->source(),
        '-override' => 1
      );
    unless( $plugin_menu_html ) {
      return $source_menu_html;
    }
  }
  return
    table(
      { '-border'      => 0,
        '-width'       => '100%',
        '-cellspacing' => 0 },
      TR(
        { '-class' => 'settingsbody',
          '-align' => 'left' },
        td(
          { '-align' => 'left' },
          $source_menu_html
        ),
        td(
          { '-align' => 'left' },
          $plugin_menu_html
        )
      )
    );
} # _get_plugins_table_html(..)

# This subroutine is invoked to draw the checkbox group underneath the
# main display.  It creates a hyperlinked set of track names.
sub _get_tracks_table_html {
  my $self = shift;
  my ( $settings ) = @_;

  my $babelfish = $self->{ '_babelfish' };

  warn "_get_tracks_table_html(..)" if DEBUG;

  # set up the dumps line.
  my $seq_id        = $settings->{ 'seq_id' };
  my $start         = $settings->{ 'start' };
  my $end           = $settings->{ 'end' };
  my $source        = $self->source();
  my $self_url      = url( '-relative' => 1, '-path_info' => 1 );

  my @labels = @{ $settings->{ 'track_order' } };
  if( $self->setting( 'sort tracks' ) ) {
    ## TODO: REMOVE
    #warn "Sorting tracks";
    @labels = sort { lc( $self->setting( $a, 'key' ) ) cmp lc( $self->setting( $b, 'key' ) ) } @labels;
  } else {
    ## TODO: REMOVE
    #warn "NOT sorting tracks";
  }
  my %labels =
    map { $_ =>
            $self->_get_citation_html(
              $settings,
              $_,
              ( $self_url . '?help=citations' )
            )
        }
        @labels;
  my @visibility =
    grep { $settings->{ 'track_options' }{ $_ }{ 'visible' } } @labels;

  ## TODO: REMOVE
  if( DEBUG ) {
    my %visibility = map { $_ => $settings->{ 'track_options' }{ $_ }{ 'visible' } } @labels;
    warn "_get_tracks_table_html(..): \%visibility is ".Dumper( \%visibility ).".";
  }

  autoEscape( 0 );
  my $s_table =
    table(
      { '-border' => 0,
        '-width'  => '100%' },
      ( $settings->{ 'show_tracks_table' } ?
        (
         TR(
           td(
             { '-class'    => 'searchbody',
               '-valign'   => 'top',
               '-align'    => 'right' },
             b( $babelfish->tr( 'tracks' ) ),
             a(
               { '-href'   => "$self_url?show_tracks_table=0" },
               '[' . $babelfish->tr( 'HIDE' ) . ']'
             ),
             p( i( $babelfish->tr( 'External_tracks' ) ) )
           ),
           td(
             { '-class'    => 'searchbody',
               '-colspan'  => 3,
               '-width'    => '85%' },
             checkbox_group(
               '-name'     => 'label',
               # use the track ordering to adjust the order of the checkboxes
               # this is an array slice
               '-values'   => \@labels,
               '-labels'   => \%labels,
               '-defaults' => \@visibility,
               '-cols'     => 3,
               '-override' => 1
             )
           )
         )
        ) :
        TR(
          td(
            { '-class'     => 'searchbody',
              '-colspan'   => 3 },
            b( $babelfish->tr( 'tracks' ) ),
            a(
              { '-href'    => "$self_url?show_tracks_table=1" },
              '[' . $babelfish->tr( 'SHOW' ) . ']'
            )
          )
        )
      ) # End (?:).
    );
  autoEscape( 1 );
  return $s_table;
} # _get_tracks_table_html(..)

sub _get_settings_table_html {
  my $self         = shift;
  my ( $settings ) = @_;

  my $babelfish = $self->{ '_babelfish' };

  my @widths = split( /\s+/, $self->setting( 'image widths' ) );
  @widths = ( 640, 800, 1024 ) unless @widths;

  return
    table(
      { '-border' => 0,
        '-width'  => '100%',
        '-class'  => 'settingsbody'
      },
      TR(
        td(
          b( $babelfish->tr( 'Image_width' ) ),
          br(),
          radio_group(
            '-name'     => 'width',
            '-values'   => \@widths,
            '-default'  => $settings->{width},
            '-override' => 1
          )
        ),
        td(
          b( $babelfish->tr( 'KEY_POSITION' ) ),
          br(),
          radio_group(
            '-name'     => 'keystyle',
            '-values'   => [ 'between', 'bottom' ],
            '-labels'   => { 'between' => $babelfish->tr( 'BETWEEN' ),
                             'bottom'  => $babelfish->tr( 'BENEATH' ) },
            '-default'  => $settings->{ 'keystyle' },
            '-override' => 1
	  )
        ),
        td(
          { '-align'    => 'right' },
	  (
           submit(    '-name' => $babelfish->tr( 'Set_options' ) ) .
           '&nbsp;' .
	   b( submit( '-name' => $babelfish->tr( 'Update' ) ) )
          )
        )
      )
    );
} # _get_settings_table_html(..)

sub _get_upload_table_html {
  my $self = shift;
  my ( $settings, $external_configs ) = @_;

  my $babelfish = $self->{ '_babelfish' };

  my $self_url = url( '-relative' => 1, '-path_info' => 1 );

  # start the table.
  my $c_table =
    (
     start_table( { '-border' => 0, '-width' => '100%' } ) .
     TR(
       th(
         { '-class'    => 'uploadtitle',
           '-colspan'  => 3,
           '-align'    => 'left' },
         $babelfish->tr( 'Upload_title' ) . ':',
         a(
           { '-href'   => ( $self_url . '?help=annotation' ),
             '-target' => 'help' },
           '[' . $babelfish->tr( 'HELP' ) . ']'
         )
       )
     )
    );

  # now add existing files
  my ( $file, $name, $download, $link, @info );
  for my $filename ( @{ $settings->{ 'track_order' } } ) {
    next unless( ( $filename =~ /^file:/ ) &&
                 ( $external_configs->{ $filename } ) );
    $file = $filename;
    $file =~ s/^file://;

    $name     = escape( $file );
    $download = escape( $babelfish->tr( 'Download_file' ) );
    $link     = a(
                  { '-href' => $self_url . '?$download=$name' },
                  "[$name]"
                );
    my @info  = $self->_get_uploaded_file_info_html(
                  $settings->{ 'track_options' }{ $filename }{ 'visible' } &&
                  $external_configs->{ $filename }
                );
    $c_table .=
      (
       TR(
         { '-class'     => 'uploadbody' },
         th( $link ),
         td(
           { '-colspan' => 2 },
           (
            submit(
              '-name'    => "modify.$file",
              '-value'   => $babelfish->tr( 'Edit' )
            ) .
            '&nbsp;' .
            submit(
              '-name'    => "modify.$file",
              '-value'   => $babelfish->tr( 'Download_file' )
            ) .
            '&nbsp;' .
            submit(
              '-name'    => "modify.$file",
              '-value'   => $babelfish->tr( 'Delete' )
            )
           )
         )
       ) .
       TR(
         { '-class' => 'uploadbody' },
         td( '&nbsp;' ),
         td( { '-colspan' => 2 }, @info )
       )
      );
  } # End foreach $filename in the tracks in 'track_order'.

  # end the table.
  $c_table .=
    (
     TR(
       { '-class'   => 'uploadbody' },
       th(
         { '-align' => 'right' },
         $babelfish->tr( 'Upload_File' )
       ),
       td(
         { '-colspan' => 3 },
         filefield(
           '-size'    => 40,
           '-name'    => 'upload_annotations'
         ),
         '&nbsp;',
         submit(
           '-name'    => $babelfish->tr( 'Upload' )
         ),
         '&nbsp;',
         submit(
           '-name'    => 'new_upload',
           '-value'   => $babelfish->tr( 'New' )
         )
       )
     ) .
     end_table()
    );
  return $c_table;
} # _get_upload_table_html(..)

# URLs for external annotations
sub _get_external_table_html {
  my $self = shift;
  my ( $settings, $external_configs ) = @_;

  my $babelfish = $self->{ '_babelfish' };
  my $self_url = url( '-relative' => 1, '-path_info' => 1 );

  my ( $preset_labels, $preset_urls ) =   # (arrayref,arrayref)
    $self->_get_external_presets( $settings );

  my $presets_html;
  if( $preset_labels && @$preset_labels ) {  # defined AND non-empty
    my %presets;
    @presets{ @$preset_urls } = @$preset_labels;
    unshift( @$preset_urls, '' );
    $presets{ '' } = $babelfish->tr( 'choose_preset' );
    $presets_html =
      popup_menu(
        '-name'     => 'eurl',
        '-values'   => $preset_urls,
        '-labels'   => \%presets,
        '-override' => 1,
        '-default'  => '',
        '-onChange' => 'document.mainform.submit()'
      );
  } else {
    $presets_html = '&nbsp;';
  }

  my ( @rows, $count );
  for my $filename ( @{ $settings->{ 'track_order' } } ) {
    next unless( ( $filename =~ /^(ftp|http):/ ) &&
                 ( $external_configs->{ $filename } ) );
    warn "_get_external_table_html(): filename = $filename" if DEBUG;

    push( @rows,
          (
           th(
             { '-align' => 'right', '-valign' => 'TOP' },
             'URL',
             ++$count
           ) .
           td(
             textfield(
               '-name'     => 'eurl',
               '-size'     => 50,
               '-value'    => $filename,
               '-override' => 1
             ),
             br(),
             a(
               { '-href'   => $filename,
                 '-target' => 'help' },
               '[' . $babelfish->tr( 'Download' ) . ']'
             ),
             $self->_get_uploaded_file_info_html(
               $settings->{ 'track_options' }{ $filename }{ 'visible' } &&
               $external_configs->{ $filename }
             )
           )
          )
	);
  } # End foreach $filename that's an external url in the track_options hash.

  push( @rows,
        (
         th(
           { '-align'    => 'right' },
           $babelfish->tr( 'Remote_url' )
         ) .
         td(
           textfield(
             '-name'     => 'eurl',
             '-size'     => 40,
             '-value'    => '',
             '-override' => 1
           ),
           $presets_html
         )
        )
      );

  return
    table(
      { '-border' => 0,
        '-width'  => '100%' },
      TR(
        { '-class' => 'uploadtitle' },
        th(
          { '-align'   => 'left',
            '-colspan' => 2 },
          $babelfish->tr( 'Remote_title' ) . ':',
          a(
            { '-href'   => $self_url . '?help=annotation#remote',
              '-target' => 'help' },
            '[' . $babelfish->tr( 'Help' ) . ']'
          )
        )
      ),
      TR( { '-class' => 'uploadbody' }, \@rows ),
      TR(
        { '-class' => 'uploadbody' },
        th( '&nbsp;' ),
        th(
          { '-align' => 'left' },
          submit( $babelfish->tr( 'Update_urls' ) )
        )
      )
    );
} # _get_external_table_html(..)

# In list context, returns a pair of array refs ( $labels, $urls ).
# In scalar context, returns a hash ref $presets->{ $url } == $label.
sub _get_external_presets {
  my $self = shift;
  my ( $settings ) = @_;

  my $presets  = $self->setting( 'remote sources' ) or return;
  my @presets  = shellwords( $presets );

  my ( @labels, @urls );

  while ( @presets ) {
    my ( $label, $url ) = splice( @presets, 0, 2 );
    next unless( $url && ( $url =~ /^(http|ftp)/ ) );
    push( @labels, $label );
    push( @urls, $url );
  }
  return unless @labels;

  return ( \@labels, \@urls ) if wantarray;

  my %presets;
  @presets{ @urls } = @labels;
  return \%presets;
} # _get_external_presets(..)

# computes the new values for start and end when the user made use of
# the zooming bar or navigation bar
sub _zoomnav {
  my $self = shift;
  my ( $settings ) = @_;

  return unless( $settings->{ 'seq_id' } );
  my $start = $settings->{ 'start' };
  my $end  = $settings->{ 'end' };
  my $span  = ( ( $end - $start ) + 1 );

  # get zoom parameters
  my $selected_span  = param( 'span' );
  my ( $zoom )       = grep { /^zoom (out|in) \S+/ } param();
  my ( $nav )        = grep { /^(left|right) \S+/ }  param();
  my $overview_x     = param( 'overview.x' );
  my $segment_length = param( 'seg_length' );

  my ( $zoomlevel, $navlevel );
  if( $zoom && ( $zoom =~ /((?:out|in) .+)\.[xy]/ ) ) {
    $zoomlevel = $self->_unit_to_value( $1 );
    ## TODO: REMOVE
    #warn "zoomlevel is $zoomlevel";
  } elsif( $nav && ( $nav  =~ /((?:left|right) .+)/ ) ) {
    $navlevel  = $self->_unit_to_value( $1 );
    ## TODO: REMOVE
    #warn "navlevel is $navlevel";
    ## TODO: REMOVE
    #warn "start is $start, end is $end, span is $span, segment length is $segment_length";
  }

  if( defined $zoomlevel ) {
    warn "zoom = $zoom, zoomlevel = $zoomlevel" if DEBUG;
    my $center	    = int( $span / 2 ) + $start;
    my $range	    = int( $span * ( 1 - $zoomlevel ) / 2 );
    if( $range < 2 ) {
      $range        = 2;
    }
    $start = ( $center - $range );
    $end  = ( ( $center + $range ) - 1 );
  } elsif( defined $navlevel ){
    $start += $navlevel;
    $end  += $navlevel;
  } elsif( defined( $overview_x ) && defined( $segment_length ) ) {
    my ( $padl, $padr ) = $self->_overview_pad();
    my $overview_width  =
      ( ( $settings->{ 'width' } * $self->setting( 'overview_ratio' ) ) -
        ( $padl + $padr ) );
    my $click_position  =
      ( $segment_length * ( ( $overview_x - $padl ) / $overview_width ) );
    my $max_segment     = $self->setting( 'max_segment' );
    my $default_segment = $self->setting( 'default_segment' );

    if( $span > $max_segment ) {
      $span = $default_segment;
    }
    $start = int( $click_position - ( $span / 2 ) );
    $end   = ( ( $start + $span ) - 1 );
  } elsif( $selected_span ) {
    my $center	    = ( ( $span / 2 ) + $start );
    my $range	    = ( ( $selected_span ) / 2 );
    $start          = int( $center - $range );
    $end            = ( ( $start + $selected_span ) - 1 );
  }

  # Prevent it from being larger than the segment's length
  $span  = ( ( $end - $start ) + 1 );
  if( defined( $segment_length ) && ( $span > $segment_length ) ) {
    $span = $segment_length;
    $end = $start + ( $span - 1 );
  }

  # to prevent from going off left end
  if( $start < 1 ) {
    warn "adjusting right because $start < 1" if DEBUG;
    ( $start, $end ) = ( 1, ( ( $end - $start ) + 1 ) );
  }

  # to prevent from going off right end
  if( defined( $segment_length ) && ( $end > $segment_length ) ) {
    warn "adjusting left because $end > $segment_length" if DEBUG;
    $start = ( $segment_length - ( $end - $start ) );
    $end   = $segment_length;
  }

  # to prevent divide-by-zero errors when zoomed down to a region < 2 bp
  if( $end <= ( $start + 2 ) ) {
    $end = ( $start + ( ( $span > 4 ) ? ( $span - 1 ) : 4 ) );
  }
  warn "start = $start, end = $end" if DEBUG;

  my $divisor = $self->setting( 'unit_divider' ) || 1;
  $settings->{ 'start' } = ( $start / $divisor );
  $settings->{ 'end' }   = ( $end / $divisor );
} # _zoomnav(..)

# The _get_segments() call fetches the genome segments specified in the
# current settings.  It is really just a front end to _lookup_segments()
# which does the real work.  The main work in _get_segments() is to
# identify any segments that are below 'min_seg_size' in length, and to
# recenter on a window 'min_seg_size' wide.  This prevents the browser
# from getting brain damaged when fetching 1bp features like SNPs.
sub _get_segments {
  my $self = shift;
  my ( $settings ) = @_;

  my @segments = $self->_lookup_segments( $settings );

  my $babelfish = $self->{ '_babelfish' };
  my $min_seg_size = $self->setting( 'min_seg_size' );
  my $tiny_seg_size = $self->setting( 'tiny_seg_size' );
  my $expand_seg_size = $self->setting( 'expand_seg_size' );
  my $divisor = $self->setting( 'unit_divider' ) || 1;
  # resize any segments that are below $min_seg_size
  for my $segment ( @segments ) {
    next unless( $segment->length() < $min_seg_size );
    my $original_start = $segment->start();
    my $original_end = $segment->end();
    my $max_length = $segment->abs_range()->length();
    # First just try adjusting the bounds...
    $segment->adjust_bounds();
    my $resize =
      ( ( $segment->length() <= $tiny_seg_size ) ?
        $expand_seg_size :
        $min_seg_size );
    if( $resize > $max_length ) {
      $resize = $max_length;
    }
    my $middle = int( ( $original_start + $original_end ) / 2 );
    my $new_start = ( $middle - int( $resize / 2 ) );
    my $new_end = ( $middle + int( $resize / 2 ) - 1 );
    ## TODO: REMOVE
    warn "Resizing $segment to $resize bases centered at $middle." if DEBUG;
    # to prevent from going off left end
    if( $new_start < 1 ) {
      warn "adjusting left because $new_start < 1" if DEBUG;
      ( $new_start, $new_end ) = ( 1, ( ( $new_end - $new_start ) + 1 ) );
    }
  
    # to prevent from going off right end
    my $abs_end = $segment->abs_range()->end();
    if( $new_end > $abs_end ) {
      warn "adjusting right because $new_end > $abs_end" if DEBUG;
      $new_start = ( $abs_end - ( $new_end - $new_start ) );
      $new_end   = $abs_end;
    }
  
    # to prevent divide-by-zero errors when resizing to a region < 2 bp
    if( $new_end <= ( $new_start + 2 ) ) {
      $new_end = ( $new_start + ( ( $resize > 4 ) ? ( $resize - 1 ) : 4 ) );
    }

    $self->_html_error(
      $settings,
      $babelfish->tr( 'Small_interval', $resize ),
      "for segment $segment"
    );
    $segment =
      $segment->factory()->segment(
        '-range' =>
          Bio::RelRange->new(
            '-seq_id'  => ( '' . $segment->seq_id() ),
            '-start' => $new_start,
            '-end'   => $new_end
          )
      );
    $settings->{ 'start' } = ( $new_start / $divisor );
    $settings->{ 'end' }   = ( $new_end / $divisor );

  } # End foreach $segment, resize if below $min_seg_size.

  return @segments;
} # _get_segments(..)

# interesting heuristic way of fetching sequence segments based on
# educated guesses
sub _lookup_segments {
  my $self = shift;
  my ( $settings ) = @_;

  my @segments;

  # TODO: ? $self->config()->debug( 0 );

  my $divisor = $self->setting( 'unit_divider' ) || 1;

  ## TODO: Dude.  Why is it sometimes in 'name', sometimes in 'seq_id'?
  ##  .. it must be that when zoomnaving we don't have name, we have seq_id.
  ## TODO: Doublecheck this hypothesis!
  if( my $name = $settings->{ 'name' } ) {
    warn "name = $name" if DEBUG;
    @segments = $self->_name2segments( $settings, $name );
  } elsif( my $seq_id = $settings->{ 'seq_id' } ) {
    my @argv = ( '-seq_id' => $seq_id );
    if( defined $settings->{ 'start' } ) {
      push( @argv, ( '-start' => ( $settings->{ 'start' } * $divisor ) ) );
    }
    if( defined $settings->{ 'end' } ) {
      push( @argv, ( '-end'   => ( $settings->{ 'end' } * $divisor ) ) );
    }
    warn "looking up @argv" if DEBUG;
    @segments =
      $self->config()->get_collection(
        '-range' => Bio::RelRange->new( @argv )
      );
  }

  return unless @segments;

  # Absolutify them.
  $_->absolute( 1 ) foreach @segments;

  ## TODO: REMOVE.  This doesn't make sense because all returned segments are on independent sequences, by definition.
  ## Filter out redundant segments; this can happen when the same basic
  ## feature is present under several names, such as "genes" and
  ## "frameworks"
  #my %seenit;
  #@segments =
  #  grep { !$seenit{ ( '' . $_->seq_id() ), $_->start(), $_->end() }++ }
  #       @segments;
  #return @segments if ( @segments > 1 );

  ## TODO: Understand this.  Wha?
  # this prevents any confusion over (seq_id,start,end) and (name) addressing.
  $settings->{ 'seq_id' } = ( '' . $segments[ 0 ]->seq_id() );
  $settings->{ 'start' }  = ( $segments[ 0 ]->start() / $divisor );
  $settings->{ 'end' }    = ( $segments[ 0 ]->end() / $divisor );

  ## TODO: REMOVE
  warn "_lookup_segments(..) is returning ".$segments[ 0 ]."." if DEBUG;

  return $segments[ 0 ];
} # _lookup_segments(..)

# this gets called when -- for whatever reason -- we got a truncated segment
sub _truncated_segment {
  my $self = shift;
  my ( $segment ) = @_;

  my ( $trunc_left, $trunc_right );
  if( $segment->can( 'truncated' ) && $segment->truncated() ) {
    ( $trunc_left, $trunc_right ) = @{ $segment->truncated() };
  } else { ## TODO: ?
    return $segment;
  }
  my $seq_id = ( '' . $segment->seq_id() );
  my $whole  = $self->config()->segment( '-unique_id' => $seq_id );
  if( $trunc_right ) {
    return $self->config()->segment(
             '-range' =>
               Bio::RelRange->new(
                 '-seq_id' => $seq_id,
                 '-start'  => ( $whole->end() - 4 ),
                 '-end'    => ( $whole->end() )
               )
           );
  } elsif( $trunc_left ) {
    return $self->config()->segment(
             '-range' =>
               Bio::RelRange->new(
                 '-seq_id'  => $seq_id,
                 '-start'   => 1,
                 '-end'     => 4
               )
             );
  } else {
    return $segment; ## TODO: What should we return here?
  }
} # _truncated_segment(..)

################ perform keyword search ###############
sub _do_keyword_search {
  my $self = shift;
  my ( $settings, $segments ) = @_;

  my $searchterm = $settings->{ 'name' };

  # if they wanted something specific, don't give them non-specific results.
  return if $searchterm =~ /^[\w._-]+:/;

  # Need to untaint the searchterm.  We are very lenient about
  # what is accepted here because we wil be quote-metaing it later.
  $searchterm = ( $searchterm =~ /([\w .,~!@\#$%^&*()-+=<>?\/]+)/ );

  my $match_sub = 'sub {';
  foreach ( split /\s+/, $searchterm ) {
    $match_sub .= "return unless \$_[ 0 ] =~ /\Q$_\E/i; ";
  }
  $match_sub .= "};";
  ## TODO: REMOVE
  warn "eval: match_sub" if DEBUG;
  my $match = eval $match_sub;

  my $max_keywords = $self->setting( 'keyword search max' );
  my @matches = grep { $match->( $_->[ 1 ] ) }
    $self->config()->search_notes( $searchterm, $max_keywords );
  ## TODO: What is the $name field (the first field of each entry in
  ## @matches), and why is it safe to do $name->class(), below?
  my ( $name, $description, $score, $seg, @results );
  for my $match ( @matches ) {
    ( $name, $description, $score ) = @$match;
    ( $seg ) = $self->config()->segment( '-unique_id' => $name ) or next;
    push( @results,
          Bio::Graphics::Feature->new(
            '-name'   => $name,
            '-class'  => $name->class(),
            '-type'   => $description,
            '-score'  => $score,
            '-seq_id' => ( '' . $seg->abs_seq_id() ),
            '-start'  => $seg->abs_start(),
            '-end'    => $seg->abs_end()
          )
        );

  }
  @$segments = @results;
  return 1; # success.
} # _do_keyword_search(..)

################ format keyword search ###################
sub _html_multiple_choices {
  my $self = shift;
  my ( $settings, $segments ) = @_;

  my $babelfish = $self->{ '_babelfish' };
  my $out_fh    = $settings->{ '_out_fh' };

  my $name = $settings->{ 'name' };
  my $regexp = join( '|', ( $name =~ /(\w+)/g ) );

  # sort into bins by seq_id
  my %seq_ids;
  foreach my $segment ( @$segments ) {
    push(  @{ $seq_ids{ $segment->seq_id() } } , $segment );
  }

  ## TODO: Document this.
  $self->width( $settings->{ 'width' } * $self->setting( 'overview_ratio' ) );

  my $overviews = $self->_hits_on_overview( $segments );

  my $count = @$segments;
  my $keyword_search_max = $settings->{ 'keyword search max' };

  print $out_fh start_table();
  print $out_fh
    TR(
      { '-class' => 'datatitle' },
      th(
         { '-colspan' => 4 },
         $babelfish->tr( 'Hit_count', $count )
      )
    );
  if( $count >= $keyword_search_max ) {
    print $out_fh
      TR(
        { '-class' => 'datatitle' },
        th(
          { '-colspan' => 4 },
          $babelfish->tr( 'Possible_truncation', $keyword_search_max )
        )
      );
  }
  my $url = url( '-relative' => 1, '-path_info' => 1 );

  # get rid of non-numeric warnings coming out of by_score_and_position
  local $^W = 0;

  my ( @segments, $name, $class, $score, $start, $end, %attributes,
       $description, $escaped_name, $escaped_class, $objref, $posref,
       $position, @aliases );
  for my $seq_id ( sort keys %seq_ids ) {
    @segments = @{ $seq_ids{ $seq_id } };
    print $out_fh
      TR(
        th(
          { '-class'   => 'databody',
            '-colspan' => 4,
            '-align'   => 'center' },
           $babelfish->tr( 'Matches_on_ref', $seq_id ),
           br(),
           $overviews->{ $seq_id }
        )
      );

    for my $segment ( sort __sort_by_score_and_position @segments ) {
      $name        = "$segment";
      $class       = $segment->class() ||
                     $babelfish->tr( 'Sequence' );
      $score       = eval{ $segment->score() } ||
                     $babelfish->tr( 'NOT_APPLICABLE');
      $start       = $segment->start();
      $end         = $segment->end();

      %attributes = ();
      $description =
        escapeHTML(
                   eval { join( ' ', $segment->attributes( 'Note' ) ) } ||
                   eval { $segment->method() }     ||
                   eval { $segment->source_tag() } ||
                   ( '' . $segment->seq_id() )
                  );
      @aliases = eval { $segment->attributes( 'Alias' ) };
      if( @aliases ) {
	$description .= escapeHTML( " [@aliases]" );
      }
      $escaped_name  = escape( $name );
      $escaped_class = escape( $class );
      $description =~ s/($regexp)/<b class="keyword">$1<\/b>/ig;

      my $objref     =
        ( $class ?
          "$url?name=$escaped_class:$escaped_name" :
          "$url?name=$escaped_name" );
      my $posref     = "$url?seq_id=$seq_id;start=$start;end=$end";
      my $position   =
        ( $segment ?
          ( '<b>' . $segment->seq_id() . '</b>:' .
            commas( $segment->start() ) . '..' .
            commas( $segment->end() ) ) :
          $babelfish->tr( 'Not_applicable' ) );

      print $out_fh
        TR(
          { '-class'   => 'databody',
            '-valign'  => 'TOP' },
          th(
            { '-align' => 'right' },
            ( ref( $name ) ?
              a( { '-href' => $objref }, $name ) :
              tt( $name ) )
          ),
          td( $description ),
          td(
            a(
              { '-href' => $posref },
              ( $position . ' (' . ( $end - $start + 1 ) .
                ' ' . $babelfish->tr( 'bp' ) . ')' )
            )
          ),
          td( $babelfish->tr( 'SCORE', $score ) )
        );
    } # End foreach $segment with this $seq_id
  } # End foreach $seq_id

  print $out_fh end_table();
} # _html_multiple_choices(..)

# This is a function not a method!  Meant for passing to sort(..).
sub __sort_by_score_and_position {
  my $result = eval{ $b->score() <=> $a->score() };
  if( $result == 0 ) {
    $result = (
               ( $a->seq_id() cmp $b->seq_id() ) ||
               ( $a->start()  <=> $b->start() ) ||
               ( $a->end()    <=> $b->end() )
              );
  }
  return $result;
} # __sort_by_score_and_position(..)

sub _get_overview_panel_html {
  my $self = shift;
  my ( $settings, $segment ) = @_;

  my $image_html;
  if( defined $segment ) {
    $self->width( $settings->{ 'width' } * $self->setting( 'overview_ratio' ) );
    
    my $image              = $self->_get_overview_image( $segment );
    unless( $image ) {
      warn "Returning early from _get_overview_panel_html because there's no overview image to show." if DEBUG;
      return;
    }
    my ( $width, $height ) = $image->getBounds();
    my $url                = $self->_generate_image_url( $image );
    $image_html =
      image_button(
        '-name'     => 'overview',
        '-src'      => $url,
        '-width'    => $width,
        '-height'   => $height,
        '-border'   => 0,
        '-align'    => 'middle'
      ) .

      ## There's a problem here with using just the abs_range length
      ## if the abs_seq_id isn't a true sequence (so the abs_range is
      ## really just $segment, and its abs_high() value is greater
      ## than its length().  We temporarily, hackily solve it by
      ## taking the max of the two.  This value is used on the next
      ## call to gbrowse to determine the sequence's length, so this
      ## may still cause problems if, for instance, the user pans
      ## right.
      hidden(
        '-name'     => 'seg_length',
        '-value'    => max( $segment->abs_range()->length(), $segment->abs_high() ),#$segment->length(),
        '-override' => 1
      );
  } # End if( $segment )
  return
    table(
      { '-border' => 0,
        '-width'  => '100%' },
      TR(
        { '-class' => 'databody' },
        td(
          { '-align' => 'center' },
          $image_html . br()
        )
      )
    );
} # _get_overview_panel_html(..)

sub _get_segment_link_html {
  my $self = shift;
  my ( $base_url, $segment, $label ) = @_;

  my $source = $self->source();

  unless( ref $segment ) {
    return a(
             { '-href' => "$base_url?source=$source;name=$segment" },
             $segment
           );
  }

  my $start  = $segment->start();
  my $end    = $segment->end();
  my $seq_id = ( '' . $segment->seq_id() );
  my $bp = ( $end - $start );
  my $s = commas( $start );
  my $e = commas( $end );
  $label ||= "$seq_id:$s..$e";
  return
    a(
      { '-href' =>
          "$base_url?source=$source;seq_id=$seq_id;start=$start;end=$end" },
      $label
    );
} # _get_segment_link_html(..)

########## upload stuff ########
sub _new_upload {
  my $self = shift;
  my ( $settings ) = @_;

  # Eeeek!  This seems bug-prone (albeit infrequently) to me, Paul E.
  my $rand = int( 1000 * rand );

  my $filename = "upload.$rand";
  my $local_fh = $self->_open_uploaded_file( $settings, $filename, '>' );
  close $local_fh;
  my ( undef, $url ) = $self->_name_uploaded_file( $settings, $filename );
  warn "url = $url" if DEBUG;
  push( @{ $settings->{ 'track_order' } }, $url );
  $settings->{ 'track_options' }{ $url } =
    { 'visible' => 1,
      'options' => 0,
      'limit'   => 0 };
  return $filename;
} # _new_upload(..)

sub _handle_upload {
  my $self = shift;
  my ( $settings, $in_fh ) = @_;
  warn "handle_upload( $settings, $in_fh )" if DEBUG;
  # $in_fh is either a CGI string or a filehandle object, so be careful
  my ( $filename ) = "$in_fh" =~ /([^\/\\:]+)$/;

  # Copy the file to $filename, which is local.
  my $local_fh =
    $self->_open_uploaded_file( $settings, $filename, '>' ) or return;
  my $buffer;
  while( read( $in_fh, $buffer, 1024 ) ) {
    $buffer =~ s/\r\n?/\n/g;
    print $local_fh $buffer;
  }
  close $local_fh;

  # Now get a url for it.
  my ( undef, $url ) = $self->_name_uploaded_file( $settings, $filename );
  warn "url = $url" if DEBUG;
  push( @{ $settings->{ 'track_order' } }, $url );
  $settings->{ 'track_options' }{ $url } =
    { 'visible' => 1,
      'options' => 0,
      'limit'   => 0 };
} # _handle_upload(..)

sub _handle_edit {
  my $self = shift;
  my ( $settings, $data ) = @_;
  my $filename = param( 'edited file' ) or return;

  # Fix the data
  my @lines = unexpand( split( /\r?\n|\r\n?/, $data ) );
  $data = join( "\n", @lines ) . "\n";

  # Write it back out to that file
  my $local_fh = $self->_open_uploaded_file( $settings, $filename, '>' );
  print $local_fh $data;
  close $local_fh;

} # _handle_edit(..)

# format of quickie data is reference+type+name+start-end,start-end,start-end
sub _handle_quickie {
  my $self = shift;
  my ( $settings, $data ) = @_;
  return unless $data;

  # format of quickie data is reference+type+name+start-end,start-end,start-end
  my ( $reference, $type, $name, @position ) = shellwords( $data || '' );
  my @segments = map { [/(-?\d+)(?:-|\.\.)(-?\d+)/]} map {split /,/} @position;
  my $feature = Bio::Graphics::Feature->new(
                  '-seq_id'   => ( $reference || '' ),
                  '-type'     => ( $type || '' ),
                  '-name'     => ( $name || '' ),
                  '-segments' => \@segments
                );
  $self->_write_search_results( $settings, [ $feature ] );
} # _handle_quickie(..)

sub _write_search_results {
  my $self = shift;
  my ( $settings, $segments ) = @_;

  # Clear previous search results even if there's no new ones.
  my $file = 'search_results'; ## TODO: Magic #
  $self->_clear_uploaded_file( $settings, $file );
  return unless @$segments;

  my %seenit;

  warn "opening $file...\n" if DEBUG;
  my $local_fh = $self->_open_uploaded_file( $settings, $file, ">>" );
  return unless( $local_fh );

  warn "writing $file...\n" if DEBUG;
  my ( $seq_id, $type, $name, @features, $position );
  for my $segment ( @$segments ) {
    $seq_id    = ( '' . $segment->seq_id() );
    $type      = $segment->primary_tag();
    $name      = $segment->display_name();
    @features  = $segment->features();
    $position  = ( @features ?
                   join( ',', map { $_->start().'..'.$_->end() } @features ) :
                   $segment->start().'..'.$segment->end() );
    $name .= "($seenit{$name})" if $seenit{ $name }++;
    print $local_fh "\nreference=$seq_id\n";
    print $local_fh join ("\t",qq("$type"),qq("$name"),$position),"\n";
  }
  close $local_fh;
  my ( undef, $url ) = $self->_name_uploaded_file( $settings, $file );
  unshift( @{ $settings->{ 'track_order' } }, $url );
  $settings->{ 'track_options' }{ $url } =
    { 'visible' => 1,
      'options' => 0,
      'limit'   => 0 };
} # _write_search_results(..)

sub _name_uploaded_file {
  my $self = shift;
  my ( $settings, $filename ) = @_;

  warn "name_uploaded_file(): filename = $filename" if DEBUG;
  # keep last non-[/\:] part of name
  my ( $name ) = ( $filename =~ /([^:\\\/]+)$/ );
  my $id = $settings->{ 'id' } or return;
  my ( undef, $tmpdir ) =
    $self->_make_tmp_uri( $self->source()."/uploaded_file/$id" );
  my $physical = "$tmpdir/$filename";
  my $url      = "file:$filename";
  return ( wantarray ? ( $physical, $url ) : $physical );
} # _name_uploaded_file(..)

sub _open_uploaded_file {
  my $self = shift;
  my ( $settings, $filename, $mode ) = @_;

  # Strip protocol
  $filename =~ s/^file://;

  my $babelfish = $self->{ '_babelfish' };
  my $file = $self->_name_uploaded_file( $settings, $filename );
  warn "file = $file" if DEBUG;
  unless( $file ) {
    $self->_html_error( $settings, $babelfish->tr( 'Purged', $filename ) );
    $self->_clear_uploaded_file( $settings, $filename );
    return;
  }

  my $local_fh;
  my $result = open( $local_fh, "${mode}${file}" );

  unless( $result ) {
    warn "Can't open the file named $filename.  Perhaps it has been purged? (error: $!)";
    $self->_clear_uploaded_file( $settings, $filename );
    return;
  }

  return $local_fh;
} # _open_uploaded_file(..)

sub _load_external_sources {
  my $self = shift;
  my ( $settings, $segment ) = @_;

  my @new_configs = $self->_load_uploaded_files( $settings, $segment );
  warn "uploaded feature files = @new_configs" if DEBUG;

  my @external = $self->_load_remote_sources( $settings, $segment );
  warn "remove sources = @external" if DEBUG;
  push( @new_configs, @external ) if @external;

  ## TODO: ERE I AM.  I got this message:
  #[Fri Apr 18 16:25:47 2003] [error] [client 127.0.0.1] Warning: something's wrong at /local/lib/perl5/site_perl/5.8.0/Bio/Graphics/Browser.pm line 2757., referer: http://localhost/cgi-bin/gbrowse

  ## TODO: Put back
  #my %new_configs_hash =
  #  map { ( ref( $_ ) ? $_->unique_id() : $_ ) => $_ } @new_configs;
  ## TODO: REMOVE
  my %new_configs_hash;
  foreach my $config ( @new_configs ) {
    $new_configs_hash{ $config->unique_id() } = $config;
  }
  warn "new_configs_hash is " . Dumper( \%new_configs_hash ) if DEBUG;

  return \%new_configs_hash;
} # _load_external_sources(..)

# Opens config files and attatches them to our Config object
# ($self->source()).  Also returns them in a list.  Actually, the
# returned list will contain either a Config object or a filename,
# depending on whether or not the track containing that file has its
# 'visible' property set to true in the 'track_options' hash.  If
# 'visible' is true it will be a Config object.  Otherwise it will be
# the file name.
sub _load_uploaded_files {
  my $self = shift;
  my ( $settings, $segment ) = @_;

  my $width = $settings->{ 'width' } or return;

  my @files;

  my @uploads = grep {/^file:/} @{ $settings->{ 'track_order' } };
  my @result;
  for my $file ( @uploads ) {
    warn "loading $file" if DEBUG;
    if( !$settings->{ 'track_options' }{ $file }{ 'visible' } ) { # turned off
      push( @result, $file );
      next;
    }

    my $local_fh = $self->_open_uploaded_file( $settings, $file, "<" );
    return unless( $local_fh );

    # Make a new config object 
    my $new_config =
      Bio::Graphics::Browser::ConfigIO->new(
        '-fh'   => $local_fh,
        '-safe' => 1
      )->read_config();
    ## TODO: Note the old parameters.  rel2abs was from:
    ## my $rel2abs = $self->_coordinate_mapper( $settings, $segment ) if $segment;
    ## and who knows about smart_features...
    # my $feature_file = Bio::Graphics::FeatureFile->new(-file           => $local_fh,
    #                                                    -map_coords     => $rel2abs,
    #                                                    -smart_features =>1);
    close $local_fh;
    next unless $new_config;
    # And add it to our current one
    $self->source()->add_config( $new_config );
    $new_config->unique_id( $file );
    push( @result, $new_config );
  }
  return @result;
} # _load_uploaded_files(..)

# Opens config files and attatches them to our Config object
# ($self->source()).  Also returns them in a list.  Actually, the
# returned list will contain either a Config object or a filename,
# depending on whether or not the track containing that file has its
# 'visible' property set to true in the 'track_options' hash.  If
# 'visible' is true it will be a Config object.  Otherwise it will be
# the file name.
sub _load_remote_sources {
  my $self = shift;
  my ( $settings, $segment ) = @_;

  my $babelfish = $self->{ '_babelfish' };

  # Make sure that we have a user agent
  unless( $settings->{ '_user_agent' } ) {
    unless( eval "require LWP" ) {
      error( $babelfish->tr( 'NO_LWP' ) );
      return;
    }
    $settings->{ '_user_agent' } =
      LWP::UserAgent->new(
        'agent'    => "Generic-Genome-Browser/$VERSION",
        'timeout'  => $settings->{ 'url_fetch_timeout' },
        'max_size' => $settings->{ 'url_fetch_max_size' },
      );
  }

  my @uploads = grep { /^(http|ftp):/ } @{ $settings->{ 'track_order' } };
  my ( @result, $file );
  for my $url ( @uploads ) {
    warn "load_remote_sources(): loading $url" if DEBUG;
    if( !$settings->{ 'track_options' }{ $url }{ 'visible' } ) { # turned off
      push( @result, $url );
      next;
    }
    $file = md5_hex( $url );      # turn into a filename
    $file =~ /^([0-9a-fA-F]+)$/;  # untaint operation
    $file = $1;

    my ( undef, $tmpdir ) =
      $self->_make_tmp_uri( $self->source() . '/external' );
    my $response = $settings->{ '_user_agent' }->mirror( $url, "$tmpdir/$file" );
    if( $response->is_error() ) {
      $self->_html_error(
        $settings,
        $babelfish->tr(
          'Fetch_failed',
          $url,
          $response->message()
        )
      );
      next;
    }

    my $local_fh;
    open( $local_fh, "<$tmpdir/$file" ) or next;

    ## NOTE: This used to have -smart_features=>1, back when it was
    ## instantiating a FeatureFile.
    my $new_config =
      Bio::Graphics::Browser::ConfigIO->new(
        '-fh'   => $local_fh,
        '-safe' => 1
      )->read_config();
    close $local_fh;
    next unless $new_config;

    # And add it to our current one
    $self->source()->add_config( $new_config );
    $new_config->unique_id( $url );
    warn "get_remote_feature_data(): got $new_config" if DEBUG;

    push( @result, $new_config );
  }
  return @result;
} # _load_remote_sources(..)

sub _load_plugin_annotations {
  my $self = shift;
  my ( $settings, $plugins, $segment, $external_configs ) = @_;

  for my $plugin ( keys %$plugins ) {
    next unless( $plugins->{ $plugin }->type() eq 'annotator' );
    my $name = "plugin:" . $plugins->{ $plugin }->name();
    next unless $settings->{ 'track_options' }{ $name }{ 'visible' };
    my $new_config =
      $plugins->{ $plugin }->annotate( $segment ) or next;
    # And add it to our current one
    $self->source()->add_config( $new_config );
    $new_config->unique_id( $name );
    $external_configs->{ $name } = $new_config;
  } # End foreach $plugin, if it's an annotator, use it to generate a new Config.
} # _load_plugin_annotations(..)

sub _load_plugin_tracks {
  my $self = shift;
  my ( $settings, $plugins ) = @_;
  my $plugin_name;
  for my $plugin_class ( keys %$plugins ) {
    next unless( $plugins->{ $plugin_class }->type() eq 'annotator' );
    $plugin_name = 'plugin:'.$plugins->{ $plugin_class }->name();
    $settings->{ '_plugin_name2class' }{ $plugin_name } = $plugin_class;
    unless( $settings->{ 'track_options' }{ $plugin_name } ) {
      push( @{ $settings->{ 'track_order' } }, $plugin_name );
      $settings->{ 'track_options' }{ $plugin_name } =
        { 'visible' => 0,
          'options' => 0,
          'limit'   => 0 };
    }
  } # End foreach $plugin_class, add an invisible track for it and
    # remember the track name->plugin mapping.
} # _load_plugin_tracks(..)

sub _print_uploaded_file_features {
  my $self = shift;
  my ( $settings, $file ) = @_;

  my $out_fh = $settings->{ '_out_fh' };

  my $line_end = $self->_line_end();
  if( my $local_fh = $self->_open_uploaded_file( $settings, $file ) ) {
    while( <$local_fh> ) {
      chomp;
      print $out_fh $_, $line_end;
    }
  }
} # _print_uploaded_file_features(..)

sub _line_end {
  my $self = shift;

  my $agent  = CGI->user_agent();
  return "\r"   if $agent =~ /Mac/;
  return "\r\n" if $agent =~ /Win/;
  return "\n";
} # _line_end(..)

sub _get_uploaded_file_info_html {
  my $self = shift;
  my ( $config ) = @_;
  unless( $config ) {
    return i( 'Display off' );
  }
  warn "_get_uploaded_file_info_html(): config = $config" if DEBUG;

  my $babelfish = $self->{ '_babelfish' };

  my $modified = localtime( $config->mtime() );
  my @seq_ids  = sort $config->seq_ids();

  my ( $landmarks, @landmarks, @links );
  my $self_url = url( '-relative' => 1, '-path_info' => 1 );

  if( @seq_ids > $self->setting( 'too_many_refs' ) ) {
    $landmarks = b( $babelfish->tr( 'Too_many_landmarks', scalar @seq_ids ) );
  } else {
    @links = map { $self->_get_segment_link_html( $self_url, $_ ) } @seq_ids;
    if( @links ) {
      my $rows    = int( sqrt( @links ) );
      my $columns = int( 0.99 + ( @links / $rows ) );
      my $cell;
      $landmarks = qq(<table border="1">);
      for( my $row_i = 0; $row_i < $rows; $row_i++ ) {
        $landmarks .= '<tr>';
        for( my $col_i = 0; $col_i < $columns; $col_i++ ) {
          $cell = $links[ ( $col_i * $rows ) + $row_i ];
          if( defined $cell ) {
            $landmarks .= "<td>$cell</td>";
          }
        } # End foreach $col_i
        $landmarks .= "</tr>\n";
      } # End foreach $row_i
      $landmarks .= "</table>\n";
    } # End if @links
  }

  warn "_get_uploaded_file_info_html(): modified = $modified, landmarks = $landmarks" if DEBUG;
  return i( $babelfish->tr( 'File_info', $modified, $landmarks ) );
} # _get_uploaded_file_info_html(..)

sub _clear_uploaded_file {
  my $self = shift;
  my ( $settings, $file ) = @_;
  warn "clear_uploaded_file(): file = $file" if DEBUG;
  my $path = $self->_name_uploaded_file( $settings, $file ) or return;
  unlink $path;
  delete $settings->{ 'track_options' }{ "file:$file" };
  warn "clear_uploaded_file(): deleting file = file:$file" if DEBUG;
  $settings->{ 'track_order' } =
    [ grep { $_ ne "file:$file" } @{ $settings->{ 'track_order' } } ];
} # _clear_uploaded_file(..)

sub _html_edit_uploaded_file {
  my $self = shift;
  my ( $settings, $file ) = @_;
  warn "edit_uploaded_file(): file = $file" if DEBUG;

  my $out_fh = $settings->{ '_out_fh' };
  my $babelfish = $self->{ '_babelfish' };

  print $out_fh start_form();
  my $data;
  my $local_fh = $self->_open_uploaded_file( $settings, $file ) or return;

  $data = join( '', expand( <$local_fh> ) );
  print $out_fh
    table(
      { '-width' => '100%' },
      TR(
        { '-class' => 'searchbody' },
        td( $babelfish->tr( 'Edit_instructions' ) ),
      ),
      TR(
        { '-class' => 'searchbody' },
        td(
          a(
            { '-href' =>
                url( '-relative'  => 1,
                     '-path_info' => 1 ).
                "?help=annotation#format",
              '-target' => 'help'
            },
            b( '[' . $babelfish->tr( 'Help_format' ) . ']' )
          )
        ),
      ),
      TR(
        { '-class' => 'searchtitle' },
        th( $babelfish->tr( 'Edit_title' ) )
      ),
      TR(
        { '-class' => 'searchbody' },
        td(
          { '-align' => 'center' },
          pre(
            textarea(
              '-name'  => 'a_data',
              '-value' => $data,
              '-rows'  => $settings->{ 'annotation_edit_rows' },
              '-cols'  => $settings->{ 'annotation_edit_cols' },
              '-wrap'  => 'off',
              '-style' => "white-space : pre"
	    )
          )
        )
      ),
      TR(
        { '-class' => 'searchtitle' },
        th(
          reset( $babelfish->tr( 'Undo' ) ) . '&nbsp;' .
          submit( 'Cancel' ) . '&nbsp;' .
          b( submit( 'Submit Changes...' ) )
        )
      )
    );
  print $out_fh hidden( '-name' => 'edited file', '-value' => $file );
  print $out_fh end_form();
} # _html_edit_uploaded_file(..)

sub _coordinate_mapper {
  my $self = shift;
  my ( $settings, $segment ) = @_;

  my $seq_id = $segment->seq_id();
  my $start  = $segment->start();
  my $end    = $segment->end();

  my %segments;
  return
    sub {
      my( $refname, @ranges ) = @_;

      unless( $segments{ $refname } ) {
        my @segments =
          grep {
            ( $_->abs_seq_id() eq $seq_id ) &&
            ( $_->abs_start() <= $end ) &&
            ( $_->abs_end()  >= $start )
          } $self->_name2segments( $settings, $refname );
        return unless @segments;
        $segments{ $refname } = $segments[ 0 ];
      }
      my $mapper     = $segments{ $refname };
      my $abs_seq_id = $mapper->abs_seq_id();
      my @abs_segs   =
        map { [ $mapper->rel2abs( $_->[ 0 ], $_->[ 1 ] ) ] } @ranges;

      # this inhibits mapping outside the displayed region
      foreach ( @abs_segs ) {
        if( ( $_->[ 0 ] <= $end ) && ( $_->[ 1 ] >= $start ) ) {
          return ( $abs_seq_id, @abs_segs );
        }
      }
      return;
    };
} # _coordinate_mapper(..)

sub _maybe_print_top {
  my $self = shift;
  my ( $settings ) = @_;

  my $out_fh = $settings->{ '_out_fh' };
  my $babelfish = $self->{ '_babelfish' };

  print $out_fh CGI::header() unless $settings->{ '_header_printed' }++;
  print $out_fh start_html(
                  '-title' => $babelfish->tr( 'Page_title' ),
                  '-style'  => { 'src' => $self->setting( 'stylesheet' ) }
                ) unless $settings->{ '_html_started' }++;
} # _maybe_print_top(..)

# this controls the "adjust track options" screen
sub _html_adjust_track_options {
  my $self = shift;
  my ( $settings ) = @_;

  my @labels = @{ $settings->{ 'track_order' } };
  my $babelfish = $self->{ '_babelfish' };
  my $out_fh = $settings->{ '_out_fh' };

  my %keys = map { $_ => $self->setting( $_ => 'key' ) || $_ } @labels;
  my @sorted_labels = ( '',
                        sort { lc( $keys{ $a } ) cmp lc( $keys{ $b } ) } 
                             @labels
                      );

  my @rows;
  for( my $track_i = 0; $track_i < @labels; $track_i++ ) {
    my $label = $labels[ $track_i ];
    push( @rows,
      (
       th(
         { '-align' => 'left',
           '-class' => 'searchtitle' },
         $babelfish->tr( 'Track' ),
         ( $track_i + 1 )
       ) .
       th(
         { '-align' => 'left',
           '-class' => 'searchbody' },
         $keys{ $label }
       ) .
       td(
         { '-align' => 'center',
           '-class' => 'searchbody' },
         checkbox(
           '-name'     => 'track.label',
           '-value'    => $label,
           '-override' => 1,
           '-checked'  => $settings->{ 'track_options' }{ $label }{ 'visible' },
           '-label'    => ''
         )
       ) .
       td(
         { '-align' => 'center',
           '-class' => 'searchbody' },
         popup_menu(
           '-name'     => "option.$track_i",
           '-values'   => [0..3],
           '-override' => 1,
           '-default'  => $settings->{ 'track_options' }{ $label }{ 'options' },
           '-labels'   =>
             { '0' => $babelfish->tr( 'Auto' ),
               '1' => $babelfish->tr( 'Compact' ),
               '2' => $babelfish->tr( 'Expand' ),
               '3' => $babelfish->tr( 'Expand_Label' ),
             }
         )
       ) .
       td(
         { '-align' => 'center',
           '-class' => 'searchbody' },
         popup_menu(
           '-name'     => "limit.$track_i",
           '-values'   => [ 0, 5, 10, 25, 100 ],
           '-labels'   => { '0' => $babelfish->tr( 'No_limit' ) },
           '-override' => 1,
           '-default'  => $settings->{ 'track_options' }{ $label }{ 'limit' }
         )
       ) .
       td(
         { '-align' => 'center',
           '-class' => 'searchbody' },
         popup_menu(
           '-name'     => "track.$track_i",
           '-values'   => \@sorted_labels,
           '-labels'   => \%keys,
           '-override' => 1,
           '-onChange' => 'document.settings.submit()',
           '-default'  => ''
         )
       )
      )
    );
  } # End foreach $track_i from 1..$#labels.
  my $controls =
    TR(
      { '-class' => 'searchtitle' },
      td(
        { '-colspan' => 3,
          '-align'   => 'center' },
        (
         reset(  $babelfish->tr( 'Undo' ) ) .    '&nbsp;' .
         submit( $babelfish->tr( 'Revert' ) ) .  '&nbsp;' .
         submit( $babelfish->tr( 'Refresh' ) ) . '&nbsp;'
	)
      ),
      td(
        { '-align'   => 'center',
          '-colspan' => 3 },
        (
         submit(
           '-name'  => $babelfish->tr( 'Cancel' ),
           '-value' => $babelfish->tr( 'Cancel_Return' )
         ) . '&nbsp;'.
         b(
           submit(
             '-name'  => $babelfish->tr( 'Redisplay' ),
             '-value' => $babelfish->tr( 'Accept_Return' )
           )
         )
        )
      )
    );

  print $out_fh
    h1(
       { '-align' => 'center' },
       $babelfish->tr( 'Settings', $self->setting( 'description' ) )
    );
  print $out_fh start_form( '-name' => 'settings' );
  print $out_fh
    table(
      { '-width'  => '100%',
        '-border' => 0 },
      $controls,
      TR(
        { '-class' => 'searchtitle' },
        th( { '-colspan' => 6 }, $babelfish->tr( 'Options_title' ) )
      ),
      TR(
        { '-class' => 'searchbody' },
        td( { '-colspan' => 6 }, $babelfish->tr( 'Settings_instructions' ) )
      ),
      TR(
        { '-class' => 'searchtitle' },
        th( $babelfish->tr( 'Track' ) ),
        th( $babelfish->tr( 'Track Type' ) ),
        th( $babelfish->tr( 'Show' ) ),
        th( $babelfish->tr( 'Format' ) ),
        th( $babelfish->tr( 'Limit' ) ),
        th( $babelfish->tr( 'Change_Order' ) ),
      ),
      TR( \@rows ),
      $controls,
      hidden(
        '-name'     => $babelfish->tr( 'Set_options' ),
        '-value'    => 1,
        '-override' => 1
      ),
      hidden(
        '-name'     => $babelfish->tr( 'Adjust_order' ),
        '-value'    => 1,
        '-override' => 1
      )
    );
  print $out_fh end_form();
} # _html_adjust_track_options(..)

sub _html_help {
  my $self = shift;
  my ( $settings ) = @_;

  my $help_type = param( 'help' );
  my $conf_dir  = $self->setting( 'help' );
  my $babelfish = $self->{ '_babelfish' };
  my $out_fh    = $settings->{ '_out_fh' };

  # We'll use this twice:
  my $do_close =
    (
     start_form( '-action' => referer() ) .
     button( '-onClick' => 'window.close()',
             '-label'   => $babelfish->tr( 'Close_Window' ) ) .
     end_form()
    );

  print $out_fh div( { '-align' => 'right' }, $do_close );
  if( $help_type eq 'citations' ) {
    $self->_html_citation( $settings );
  } elsif( $help_type eq 'link_image' ) {
    $self->_html_link_image( $settings );
  } else {
    my $helpfile = "$conf_dir/${help_type}_help.html";
    my $file = $self->_url2file( $helpfile );
    if( $file ) {
      my $root = $self->setting( 'help' );
      my $url  = url( '-relative' => 1 );
      my $local_fh;
      open( $local_fh, $file );
      if( $local_fh ) {
        while( <$local_fh> ) { # fix up relative addressing of images
          s/(href|src)=\"([^\"\#\$]+)\"/$1=\"$root\/$2\"/g;
          s/<!--\s*\#include-classes\s*-->/$self->_get_object_types_help_html( $settings )/e;
          print $out_fh $_;
        }
        close $local_fh;
      }
    }
  }
  print $out_fh div( { '-align' => 'right' }, $do_close );
} # _html_help(..)

sub _make_citation {
  my $self = shift;
  my ( $settings, $label ) = @_;

  my $babelfish = $self->{ '_babelfish' };
  my $citation = $self->citation( $label, $babelfish );

  # BUG: here's where we should remove "bad" HTML, but we don't!
  # We should remove active content and other nasties
  my $link = $label;
  $link =~ tr/ /-/;
  my $text = $self->_label2key( $settings, $label );
  return join(
    '',
    ( dt( a( { '-name' => $link }, b( $text ) ) ),
      dd( $citation || $babelfish->tr( 'No_citation' ) ),
      p() )
  );
} # _make_citation(..)

# build a citation page
sub _html_citation {
  my $self = shift;
  my ( $settings ) = @_;

  my @labels = $self->labels();
  my $external_configs = $self->_load_external_sources( $settings );
  my $babelfish = $self->{ '_babelfish' };
  my $out_fh = $settings->{ '_out_fh' };

  my @citations;
  print $out_fh h2( $babelfish->tr( 'Track_descriptions' ) );

  # build native labels
  print $out_fh h3( $babelfish->tr( 'Built_in' ) );
  for my $label ( @labels ) {
    push( @citations, $self->_make_citation( $settings, $label ) );
  }
  print $out_fh blockquote( dl( @citations ) );

  # build external citations
  if( %$external_configs ) {
    print $out_fh hr(), h3( $babelfish->tr( 'External' ) );
    @citations = ();
    my ( $f, $name, $is_url, $download, $link, $anchor );
    for my $file ( keys %$external_configs ) {
      $f = escape( $file );
      $name     = $file;
      $is_url   = ( $name =~ m!^(http|ftp)://! );
      $download = escape( $babelfish->tr( 'Download_data' ) );
      $link     = ( $is_url ?
                    $name   :
                    url( '-relative' => 1, '-path_info' => 1 ) .
                      "?$download=1;file=$f" );
      $anchor = $name;
      $anchor =~ tr/ /-/;
      unless( ref $external_configs->{ $file } ) {
	print $out_fh h3( a{ '-name' => $anchor, '-href' => $link }, $name );
	print $out_fh blockquote( $babelfish->tr( 'Activate' ) );
	next;
      }
      print $out_fh h4( a{ '-name' => $anchor, '-href' => $link }, $name );
      for my $label ( $external_configs->{ $file }->labels() ) {
        # TODO: It's technically conceivable that the label will exist
        # in multiple configs, in which case we would have to qualify
        # the label somehow as coming from $external_configs->{ $file
        # }, but for now we're not doing that.
	push(
          @citations,
          $self->_make_citation(
            $settings,
            $label
          )
        );
      } # End foreach $label in this external config..
      print $out_fh blockquote( dl( @citations ) );
    } # End foreach external config..
    unless( @citations ) {
      print $out_fh p( $babelfish->tr( 'No_external' ) );
    }
  } # End if there's any external configs.
} # _html_citation(..)

sub _html_link_image {
  my $self = shift;
  my ( $settings, $segment ) = @_;

  my $babelfish = $self->{ '_babelfish' };
  my $out_fh = $settings->{ '_out_fh' };

  # Get the url of the invocation of this Browser.
  my $url = url( '-base' => 1 ) . url( '-absolute' => 1 );
  ## TODO: Does this break if we don't have a base with 'gbrowse' in it?
  $url =~ s/gbrowse/gbrowse_img/;

  my $source = $self->source();
  my $width  = $self->width();

  my $name   = $settings->{ 'name' } ||
               "$settings->{seq_id}:$settings->{start}..$settings->{end}";
  my $type   =
    join( '+',
          map { escape( $_ ) }
              grep { $settings->{ 'track_options' }{ $_ }{ 'visible' } }
                   @{ $settings->{ 'track_order' } } );
  my $img_url = "$url?source=$source;name=$name;type=$type;width=$width";
  print $out_fh $babelfish->tr( 'IMAGE_DESCRIPTION', $img_url, $img_url );
} # _html_link_image(..)

sub _url2file {
  my $self = shift;
  my ( $url ) = @_;

  my $babelfish = $self->{ '_babelfish' };

  for my $lang ( ( map { "$url.$_" } $babelfish->language() ), $url ) {
    my $file =
      ( $ENV{ 'MOD_PERL' } ?
        Apache->request()->lookup_uri( $lang )->filename() :
        "$ENV{DOCUMENT_ROOT}/$lang" );
    return $file if -e $file;
  }
  return;
} # _url2file(..)

# get list of object types for help pages
sub _get_object_types_help_html {
  my $self = shift;
  my ( $settings ) = @_;

  my $source = $self->source();

  if( exists $settings->{ '_object_types' }{ $source } ) {
    return $settings->{ '_object_types' }{ $source };
  }

  my @types = $self->config()->types();
  if( @types ) {
    return
      ( $settings->{ '_object_types' }{ $source } = ul( li( \@types ) ) );
  } else {
    return ( $settings->{ '_object_types' }{ $source } = undef );
  }
} # _get_object_types_help_html(..)

# Create a link to a citation.  It will point to an external URL if the
# citation looks like a URL (starts with http: or ftp:).  It will be
# self-referential otherwise.

# The persistent problem here is that the regular features are cited on a
# feature-by-feature basis, while the uploaded/external ones are cited as
# a group.  This makes for ugly logic branches.
sub _get_citation_html {
  my $self = shift;
  my ( $settings, $label, $self_url )   = @_;

  my $babelfish = $self->{ '_babelfish' };

  my ( $link, $key );

  if( $label =~ /^plugin:/ ) {
    $key = $label;
    my $about = escape( $babelfish->tr( 'About' ) );
    my $class =
      $settings->{ '_plugin_name2class' }{ $label };
    $link =
      ( url( '-relative' => 1 ) .
        "?plugin_action=$about;plugin=$class" );
  } else {
    $key = $self->_label2key( $settings, $label );
    my $anchor = $label;
    $anchor =~ tr/ /-/;
    $link = $self_url . '#' . escapeHTML( $anchor );
  }
  my @args = ( '-href' => $link, '-target' => 'citation' );
  if( $label =~ /^(http|ftp|file):/ ) {
    push( @args, '-style' => 'Font-style: italic' );
  }
  return a( { @args }, $key );
} # _get_citation_html(..)

sub _label2key {
  my $self = shift;
  my ( $settings, $label ) = @_;

  my $babelfish = $self->{ '_babelfish' };

  my $key;
  $settings->{ '_presets' } ||=
    $self->_get_external_presets( $settings ) || {};

  for my $lang ( $babelfish->language() ) {
    $key ||= $self->setting( $label, "key:$lang" );
  }

  $key   ||= $self->setting( $label, 'key');
  $key   ||= $settings->{ '_presets' }->{ $key } || $label;
  return $key;
} # _label2key(..)

### PLUGINS ###################################################################################
###############################################################################################
sub _initialize_plugins {
  my $self = shift;
  my $path = shift;

  my $plugin_dir = "$path/plugins";
  warn "initializing plugins..." if DEBUG;
  my @plugin_classes = shellwords( $self->setting( 'plugins' ) );

  my %plugins = ();
  for my $plugin_class ( @plugin_classes ) {
    my $class_path = "$plugin_dir/$plugin_class.pm";
    if( eval { require $class_path } ) {
      warn "plugin $plugin_class loaded successfully" if DEBUG_PLUGINS;
      $plugins{ $plugin_class } = $class_path;
    } else {
      warn $@ if $@;
    }
  }
  $self->{ 'plugin_classes' } = \%plugins;
} # _initialize_plugins(..)

# Instantiates and initializes the plugins.  Stores them in settings under 'configure_plugins' and also returns them (a hash ref).
sub _configure_plugins {
  my $self = shift;
  my( $settings ) = @_;

  my $babelfish = $self->{ '_babelfish' };

  my ( $plugin, %plugins );
  foreach my $plugin_class ( keys %{ $self->{ 'plugin_classes' } } ) {
    $plugin = "Bio\:\:Graphics\:\:Browser\:\:Plugin\:\:$plugin_class"->new();
    warn "plugin name = ", $plugin->name()," base = $plugin_class" if DEBUG_PLUGINS;
    $plugins{ $plugin_class } = $plugin;
    $plugin->browser_config( $self->source() );
    $plugin->page_settings( $settings );
    $plugin->init();  # other initialization

    # retrieve persistent configuration
    my $config = $self->_retrieve_plugin_config_from_cookie( $plugin );
    # and tell the plugin about it
    $plugin->configuration( $config );

    # if there are any CGI parameters from the
    # plugin's configuration screen, set it here
    my @params = grep {/^$plugin_class\./} param();
    next unless @params;
    unless( param( 'plugin_action' ) eq $babelfish->tr( 'Cancel' ) ) {
      $plugin->reconfigure();
    }

    # Remember it
    $plugins{ $plugin_class } = $plugin;

    # turn the plugin on
    $settings->{ 'track_options' }{ 'plugin:'.$plugin->name() }{ 'visible' } = 1;
  } # End foreach $plugin_class, make the plugin.
  # Store it in settings
  ## TODO: We never use this, so I've removed it.
  #$settings->{ '_configured_plugins' } = \%plugins;
  # And also return it.
  return \%plugins;
} # _configure_plugins(..)

sub _get_plugin_menu_html {
  my $self = shift;
  my ( $settings, $plugins ) = @_;

  my $babelfish = $self->{ '_babelfish' };

  warn "_get_plugin_menu_html(..)" if DEBUG;

  my %verbs = ( 'dumper'    => $babelfish->tr( 'Dump' ),
	        'finder'    => $babelfish->tr( 'Find' ),
	        'annotator' => $babelfish->tr( 'Annotate' ) );
  my %labels =
    map { $_ =>
               (
                ( $verbs{ $plugins->{ $_ }->type() } ||
                  $plugins->{ $_ }->type() ) .
                ' ' .
                $plugins->{ $_ }->name()
               )
        }
        keys %$plugins;

  my @plugins = sort { $labels{ $a } cmp $labels{ $b } } keys %labels;
  return unless @plugins;
  return
    (
     b( $babelfish->tr( 'Dumps' ) . ':' ) .
     br() .
     popup_menu(
       '-name'    => 'plugin',
       '-values'  => \@plugins,
       '-labels'  => \%labels,
       '-default' => $settings->{ 'plugin' },
     ) .
     '&nbsp;' .
     submit(
       '-name'    => 'plugin_action',
       '-value'   => $babelfish->tr( 'About' )
     ) .          
     '&nbsp;' .   
     submit(      
       '-name'    => 'plugin_action',
       '-value'   => $babelfish->tr( 'Configure' )
     ) .          
     '&nbsp;' .   
     submit(      
       '-name'    => 'plugin_action',
       '-value'   => $babelfish->tr( 'Go' )
     )
    );
} # _get_plugin_menu_html(..)

sub _get_source_menu_html {
  my $self = shift;
  my ( $settings ) = @_;

  my $babelfish = $self->{ '_babelfish' };

  warn "_get_source_menu_html(..) A" if DEBUG;

  my @sources = sort $self->sources();
  return unless scalar( @sources > 1 );

  warn "_get_source_menu_html(..) B" if DEBUG;

  return
    (
     b( $babelfish->tr( 'DATA_SOURCE' ) ) .
     br() .
     ( ( @sources > 1 ) ?
       popup_menu(
         '-name'     => 'source',
         '-values'   => [ @sources ],
         # TODO: Put back? description(..) loads the named conf file.  If we can avoid that, let's.
         #'-labels'   => { map { $_ => $self->description( $_ ) } @sources },
         '-default'  => $self->source(),
         '-onChange' => 'document.mainform.submit()',
       ) :
       $self->source()
     )
    );
} # _get_source_menu_html(..)

sub _html_plugin_header {
  my $self = shift;
  my ( $settings, $plugins, $plugin_class ) = @_;

  # You can only print the header once, alas.
  return if $settings->{ '_header_printed' }++;

  my $out_fh    = $settings->{ '_out_fh' };
  my $mime_type = $plugins->{ $plugin_class }->mime_type();
  my @cookies   = $self->_plugins2cookies(
                    { $plugin_class => $plugins->{ $plugin_class } }
                  );
  # Also add the session_id cookie for Browser object persistence.
  push( @cookies, cookie(
                    '-name'    => 'gbrowse_session_id',
		    '-value'   => $self->unique_id(),
                    '-expires' => $self->setting( 'browser_ttl' )
                  ) );
  # And use this opportunity to reestablish our own expiry.
  $self->expiration_time( $self->setting( 'browser_ttl' ) );

  print $out_fh CGI::header( '-cookie' => \@cookies, '-type' => $mime_type );
} # _html_plugin_header(..)

sub _html_plugin_dump {
  my $self = shift;
  my ( $plugins, $plugin_class, $segment ) = @_;
  my $plugin = $plugins->{ $plugin_class } or return;
  $plugin->dump( $segment );
  return 1;
} # _html_plugin_dump(..)

sub _html_plugin_about {
  my $self = shift;
  my ( $settings, $plugins, $plugin_label ) = @_;

  ## Warn even if we're not in DEBUG mode.
  warn "plugin = $plugin_label, but PLUGINS = ", join( ' ', keys( %$plugins ) );

  my $babelfish = $self->{ '_babelfish' };
  my $out_fh = $settings->{ '_out_fh' };

  my $plugin = $plugins->{ $plugin_label };
  print $out_fh h1( $babelfish->tr( 'About_plugin', $plugin->name() ) );
  print $out_fh $plugin->description();
  print $out_fh start_form(),
                submit( $babelfish->tr( 'Back_to_Browser' ) ),
                hidden( 'plugin' ),
                end_form();
} # _html_plugin_about(..)

# Fill the segments array ref with the result of the plugin's find()
# or autofind() method.
sub _do_plugin_find {
  my $self = shift;
  my ( $settings, $plugins, $plugin_class, $segments, $search_string ) = @_;

  my $plugin = $plugins->{ $plugin_class } or return;
  my $plugin_name = $plugin->name();

  my $results =
    ( ( $plugin->can( 'auto_find' ) && defined( $search_string ) ) ?
      $plugin->auto_find( $search_string ) :
      $plugin->find( $segments ) );
  return unless $results;  # reconfigure message

  @$segments = @$results;

  my $babelfish = $self->{ '_babelfish' };
  $settings->{ 'name' } =
    ( defined( $search_string ) ?
      $babelfish->tr( 'Plugin_search_1', $search_string, $plugin_name ) :
      $babelfish->tr( 'Plugin_search_2', $plugin_name )
    );

  # remember the search
  $self->_write_search_results( $settings, $segments );
  # return a true result to indicate that we don't need further configuration
  return 1;
} # _do_plugin_find(..)

# invoke any finder plugins that define the auto_find() method
sub _do_plugin_autofind {
  my $self = shift;
  my ( $settings, $plugins, $segments ) = @_;

  for my $plugin_class ( keys %$plugins ) {
    next unless( ( $plugins->{ $plugin_class }->type() eq 'finder' ) &&
                 $plugins->{ $plugin_class }->can( 'auto_find' ) );
    $self->_do_plugin_find(
      $settings,
      $plugins,
      $plugin_class,
      $segments,
      $settings->{ 'name' }
    );
    last if @$segments;
  }
} # _do_plugin_autofind(..)

sub _html_plugin_configure {
  my $self = shift;
  my ( $settings, $plugins, $plugin_label ) = @_;

  my $plugin = $plugins->{ $plugin_label } or return;
  my $type = $plugin->type();

  my $babelfish = $self->{ '_babelfish' };
  my $out_fh = $settings->{ '_out_fh' };

  my @action_labels =
    ( $babelfish->tr( 'Cancel' ), $babelfish->tr( 'Configure_plugin' ) );
  if( $type eq 'finder' ) {
    push( @action_labels, $babelfish->tr( 'Find' ) );
  } elsif( $type eq 'dumper' ) {
    push( @action_labels, $babelfish->tr( 'Go' ) );
  }
  my @buttons =
    map { submit( '-name' => 'plugin_action', '-value' => $_ ) }
        @action_labels;

  print $out_fh
    h1(
       ( ( $type eq 'finder' ) ?
         $babelfish->tr( 'Find' ) :
         $babelfish->tr( 'Configure' ) ),
       $plugin->name()
    );
  my $config_html = $plugin->configure_form();

  print $out_fh
    start_form(),
    ( $config_html ?
      (
       $config_html,
       p(),
       join( '&nbsp;',
             (
              @buttons[ 0..( @buttons - 2 ) ],
              b( $buttons[ -1 ] ),
             )
       ),
       # This is an insurance policy in case user hits return in text field
       # in which case the plugin_action is not going to be defined
       hidden(
         '-name'     => 'plugin_action',
         '-value'    => $action_labels[ -1 ],
         '-override' => 1
       ),
      ) :
      (
       p( $babelfish->tr( 'Boring_plugin' ) ),
       b( submit( $babelfish->tr( 'Back_to_Browser' ) ) )
      )
    ),
    hidden( 'plugin' ),
    end_form();
} # _html_plugin_configure(..)

sub _retrieve_plugin_config_from_cookie {
  my $self = shift;
  my ( $plugin ) = @_;

  my $name   = $plugin->name();
  my %settings = cookie( "${name}_config" );
  unless( %settings ) {
    return $plugin->config_defaults();
  }

  foreach my $key ( keys %settings ) {
    # TODO: need better serialization than this...
    if( $settings{ $key } =~ /$;/ ) { # If it contains the separator char...
      my @settings = split( $;, $settings{ $key } );
      pop @settings unless defined $settings[ -1 ]; # rm undef at the end
      $settings{ $key } = \@settings;
    }
  }
  return \%settings;
} # _retrieve_plugin_config_from_cookie(..)

sub _plugins2cookies {
  my $self = shift;
  my ( $plugins ) = @_;

  my ( $name, $conf, %conf, @cookies );
  for my $plugin ( values %$plugins ) {
    $name = $plugin->name();
    warn "plugins2cookies for $plugin\n" if DEBUG_PLUGINS;
    $conf = $plugin->configuration() or next;
    %conf = %$conf;

    # TODO: we need a better serialization than this...
    for my $key ( keys %conf ) {
      if( ref( $conf{ $key } ) eq 'ARRAY' ) {
        $conf{ $key } = join( $;, @{ $conf{ $key } } );
        unless( $conf{ $key } =~ /$;/ ) {
          $conf{ $key } .= $;;
        }
      }
    }
    push( @cookies,
          cookie( '-name'    => "${name}_config",
                  '-value'   => \%conf,
                  '-expires' => '+3M' ) );
  }
  warn "plugin cookies = ( " . join( ', ', @cookies ) . " ) " if DEBUG_PLUGINS;
  return @cookies;
} # _plugins2cookies(..)

sub _html_frag {
  my $self = shift;
  my ( $fragname ) = @_;

  my $a = $self->code_setting( $fragname );
  if( ref( $a ) eq 'CODE' ) {
    return $a->( @_ );
  } else {
    return $a;
  }
} # _html_frag(..)

sub _html_footer {
  my $self = shift;
  my ( $settings ) = @_;

  my $babelfish = $self->{ '_babelfish' };
  my $out_fh = $settings->{ '_out_fh' };

  print $out_fh
    $self->footer() || '',
    p(
      i(
        font(
          { '-size' => 'small' },
          $babelfish->tr( 'Footer_1' )
        )
      ),
      br(),
      tt(
        font(
          { '-size' => 'small' },
          $babelfish->tr( 'Footer_2', $VERSION )
        )
      )
    ),
    end_html();
} # _html_footer(..)

=head2 _get_link()

  $url = $browser->_get_link( $section, $feature, $panel )

Given a Bio::SeqFeatureI object, turn it into a URL suitable for use
in a hypertext link.  For convenience, the Bio::Graphics panel is also
provided.

=cut

sub _get_link {
  my $self     = shift;
  my ( $section, $feature, $panel )  = @_;

  ## TODO: REMOVE
  #warn "doing _get_link for feature $feature.";

  my $link;
  if( !$self->setting( $section, 'always use config link' ) &&
      $feature->can( 'make_link' ) ) {
    $link = $feature->make_link();
  }
  unless( defined $link ) {
    $link = $self->code_setting( $section, 'link' );
  }
  unless( defined $link ) {
    $link = $self->code_setting( 'link' );
  }
  if( !defined( $link ) &&
      $self->setting( $section, 'always use config link' ) &&
      $feature->can( 'make_link' ) ) {
    $link = $feature->make_link();
  }
  unless( defined $link ) {
    # Give up.
    return;
  }
  if( ref( $link ) eq 'CODE' ) {
    $link = eval { $link->( $feature, $panel ) };
    warn $@ if $@;
  }
  return $self->_replace_vars_with_vals( $link, $feature, $panel );
} # _get_link(..)

sub _get_link_target {
  my $self = shift;
  my( $section, $feature, $panel ) = @_;

  my $link_target = $self->code_setting( $section, 'link_target' );
  unless( defined $link_target ) {
    $link_target  = $self->code_setting( 'link_target' );
  }
  unless( defined $link_target ) {
    # Give up.
    return;
  }
  if( ref( $link_target ) eq 'CODE' ) {
    $link_target = eval { $link_target->( $feature, $panel ) } ;
    warn $@ if $@;
  }
  return $self->_replace_vars_with_vals( $link_target, $feature, $panel );
} # _get_link_target(..)

# get the title for a feature on a clickable imagemap
sub _get_map_title {
  my $self = shift;
  my( $section, $feature, $panel ) = @_;

  ## TODO: What feature class can make_title()?  What about toString()?
  #return $feature->make_title() if $feature->can( 'make_title' );

  if( $feature->has_tag( 'description' ) ) {
    return join( "; ", $feature->get_tag_values( 'description' ) );
  }

  ## TODO: REMOVE?
  return unless( defined $section );

  ## TODO: REMOVE?
  #local $^W = 0;  # tired of uninitialized variable warnings

  my $key      = $self->setting( $section, 'key' )        || $section;
  $key =~ s/s$//; # depluralize ('singularize'?)

  my $title    = $self->code_setting( $section, 'title' );
  unless( defined $title ) {
    $title     = $self->code_setting( 'title' );
  }

  if( $title ) {
    if( ref( $title ) eq 'CODE' ) {
      $title   = eval { $title->( $feature, $panel ) };
      warn $@ if $@;
    }
    $title     = $self->_replace_vars_with_vals( $title, $feature, $panel );
    return $title if $title;
  }

  # otherwise, try it ourselves
  unless( $title ) {
    if( $feature->can( 'target' ) &&
        ( my $target = $feature->target() ) ) {
      unless( ref( $target ) ) {
        # The target of a DAS feature is a list in list context and a
        # string in scalar context.  See Bio::Das::Feature.
        my @target_list = $feature->target();

        $title =
          (
           "$key: " .
           $feature->seq_id() . ':' .
           $feature->start() . '..' . $feature->end() . ' ' .
           $target_list[ 0 ] . ':' .
           $target_list[ 1 ] . '..' . $target_list[ 2 ]
          );
      } else {
        $title =
          (
           "$key: " .
           $feature->seq_id() . ':' .
           $feature->start() . '..' . $feature->end() . ' ' .
           $target . ':' .
           $target->start() . '..' . $target->end()
          );
      }
    } else {
      $title =
        (
         "$key: " .
         $feature->display_name() . ' ' .
         $feature->seq_id() . ':' .
         ( $feature->start() || '?' ) . '..' . ( $feature->end() || '?' )
        );
    }
  } # End if $title hasn't been made yet.

  return $title;
} # _get_map_title(..)

=head2 _replace_vars_with_vals

  my $after_string = $browser->_replace_vars_with_vals(
                       $before_string,
                       $feature,
                       $panel
                     );

 Replace variables in a string with their values.

  The $feature argument may be any Bio::SeqFeature::SegmentI object
  (Bio::SeqFeatureI objects are Bio::SeqFeature::SegmentI objects).

  Variable   Value
  --------   -----
  $seq_id    $feature->seq_id()
  $ref       $feature->seq_id()
  $name      $feature->display_name()
  $class     $feature->class()  || ''
  $type      $feature->method() || $feature->primary_tag()
  $method    $feature->method() || $feature->primary_tag()
  $source    $feature->source() || $feature->primary_tag()
  $alias     shift @{ $feature->get_tag_values( 'alias' ) } || $feature->display_name()
  $start     $feature->start()
  $end       $feature->end()
  $segstart  $panel->start()
  $segend    $panel->end()

=cut

sub _replace_vars_with_vals {
  my $self = shift;
  my ( $pattern, $feature, $panel ) = @_;

  $pattern =~ s/\$(\w+)/
        $1 eq 'seq_id'    ? ( '' . $feature->seq_id() )
      : $1 eq 'ref'       ? ( '' . $feature->seq_id() )
      : $1 eq 'name'      ? $feature->display_name()
      : $1 eq 'class'     ? ( eval { $feature->class() }  || '' )
      : $1 eq 'type'      ? ( eval { $feature->method() } ||
                              $feature->primary_tag() )
      : $1 eq 'method'    ? ( eval { $feature->method() } ||
                              $feature->primary_tag() )
      : $1 eq 'source'    ? ( eval { $feature->source() } ||
                              $feature->source_tag() )
      : $1 eq 'start'     ? $feature->start()
      : $1 eq 'end'       ? $feature->end()
      : $1 eq 'segstart'  ? $panel->start()
      : $1 eq 'segend'    ? $panel->end()
      : $1 eq 'alias'     ? ( ( $feature->has_tag( 'alias' ) ? $feature->get_tag_values( 'alias' ) : undef ) ||
                              $feature->display_name() )
      : $1
       /exg;
  return $pattern;
} # _replace_vars_with_vals(..)

=head1 Rendering methods
=cut

=head2 _get_detail_image_html()

  ( $gd_image, $image_map ) = $browser->_get_detail_image_html( %args );

Render an image and an image map according to the options in %args.
Returns a two-element list.  The first element is a URL that refers to
the image which can be used as the SRC for an <IMG> tag.  The second
is a complete image map, including the <MAP> and </MAP> sections.

The arguments are a series of tag=>value pairs, where tags are:

  Argument            Value

  segment             a Bio::SeqFeature::SegmentI object to render (required)

  tracks              An arrayref containing a series of track
                        labels to render (required).  The order of the labels
                        determines the order of the tracks.

  options             A hashref containing options to apply to
                        each track (optional).  Keys are the track labels
                        and the values are 0=auto, 1=force no bump,
                        2=force bump, 3=force label, 4=expanded bump.

  do_map              This argument is a flag that controls whether or not
                        to generate the image map.  It defaults to false.

  do_centering_map    This argument is a flag that controls whether or not
                        to add elements to the image map so that the user can
                        center the image by clicking on the scale.  It defaults
                        to false, and has no effect unless do_map is also true.

  title               Add specified title to the top of the image.

  noscale             Suppress the scale

=cut

sub _get_detail_image_html {
  my $self = shift;
  my $settings = shift;
  my %args = @_;

  ## TODO: REMOVE
  warn "_get_detail_image_html" if DEBUG;

  my $segment = $args{ 'segment' } ||
    $self->throw( '_get_detail_image_html(..) requires a segment argument.' );

  my $do_map           = $args{ 'do_map' };
  my $do_centering_map = $args{ 'do_centering_map' };

  my ( $image, $map, $panel ) = $self->_get_detail_image( %args );

  # Save the image to somewhere accessible and return the location.
  my $url = $self->_generate_image_url( $image );

  # Generate the HTML image tag.
  my( $width, $height ) = $image->getBounds();
  my $img =
    img(
      { '-src'    => $url,
        '-align'  => 'middle',
        '-usemap' => '#hmap',
        '-width'  => $width,
        '-height' => $height,
        '-border' => 0,
        '-name'   => 'detailedView',
        '-alt'    => 'detailed view' }
    );
  my $img_map = '';
  if( $do_map ) {
    $img_map =
      $self->_get_map_html( $settings, $map, $do_centering_map, $panel );
  }
  return wantarray ? ( $img, $img_map ) : join( "<br>", ( $img, $img_map ) );
} # _get_detail_image_html(..)

# Generate the image and the box list, and return as a two-element list.
# arguments: a key=>value list
#    'segment'       A Bio::SeqFeature::SegmentI object. [required]
#    'options'       An hashref of options, where 0=auto, 1=force no bump, 2=force bump, 3=force label
#                       4=force fast bump, 5=force fast bump and label
#    'limit'         Place a limit on the number of features of each type to show.
#    'tracks'        List of named tracks, in the order in which they are to be shown
#    'label_scale'   If true, prints chromosome name next to scale
#    'title'         A title for the image
#    'noscale'       Suppress scale entirely
sub _get_detail_image {
  my $self    = shift;
  my %args  = @_;

  ## TODO: REMOVE
  warn "_get_detail_image" if DEBUG;

  my $segment = $args{ 'segment' } ||
    $self->throw( '_get_detail_image(..) requires a segment argument.' );

  ## TODO: REMOVE
  warn "_get_detail_image: segment is $segment.  It has " . $segment->feature_count() . " features." if DEBUG;

  my $conf           = $self->config();

  # Most args have defaults, either in the conf file or a magic #.
  ## TODO: Replace magic #s with CONSTANTS
  my $max_labels     = $args{ 'label density' }             ||
                       $self->setting( 'label density' )    || 10;
  my $max_bump       = $args{ 'bump density' }              ||
                       $self->setting( 'bump density' )     || 50;
  my $empty_tracks   = $args{ 'empty_tracks' }              ||
                       $self->setting( 'empty_tracks' );
  my $key_bgcolor    = $args{ 'key bgcolor' }               ||
                       $self->setting( 'key bgcolor' )      || 'moccasin';
  my $detail_bgcolor = $args{ 'detail bgcolor' }            ||
                       $self->setting( 'detail bgcolor' )   || 'white';
  my $units          = $args{ 'units' }                     ||
                       $self->setting( 'units' )            || '';
  my $unit_divider   = $args{ 'unit_divider' }              ||
                       $self->setting( 'unit_divider' )     || 1;
  my $default_track_glyph = $args{ 'track glyph' }          ||
                            $self->setting( 'track glyph' ) || 'generic';

  my $tracks         = $args{ 'tracks' };
  unless( defined( $tracks ) ) {
    @$tracks = $self->labels();
  }
  my $options        = $args{ 'options' }                   || {};
  my $limit          = $args{ 'limit' }                     || {};
  my $lang           = $args{ 'lang' }                      ||
                       $self->{ '_babelfish' };
  my $keystyle       = $args{ 'keystyle' }                  ||
                       $self->setting( 'keystyle' );
  my $title          = $args{ 'title' };
  my $suppress_scale = $args{ 'noscale' };
  my $label_scale    = $args{ 'label_scale' };

  my $width          = $self->width();
  my $length         = $segment->length();

  # Create the tracks that we will need
  my @argv = ( '-segment'      => $segment,
	       '-width'        => $width,
	       '-key_color'    => $key_bgcolor,
	       '-bgcolor'      => $detail_bgcolor,
	       '-grid'         => 1,
	       '-key_style'    => $keystyle,
	       '-empty_tracks' => $empty_tracks,
	       '-pad_top'      => ( $title ? gdMediumBoldFont->height() : 0 )
	     );
  my $panel = Bio::Graphics::Panel->new( @argv );
  unless( $suppress_scale ) {
    $panel->add_track(
      $segment,
      '-glyph'        => 'arrow',
      '-shallow'      => 1,
      '-double'       => 1,
      '-tick'         => 2,
      '-label'        => ( $label_scale ? "$segment" : 0 ),
      '-units'        => $units,
      '-unit_divider' => $unit_divider
    );
  }

  my ( $track, $glyph, $track_glyph, $collection, %tracks,
       $feature_count, $label, $bump, $description,
       $do_bump, $do_label, $do_description );
  foreach my $section ( @$tracks ) {

    ## TODO: REMOVE
    warn "_get_detail_image: adding glyph for track '$section'" if DEBUG;

    # if the glyph is the magic "dna" glyph (for backward
    # compatibility), or if the section is marked as being a "global
    # feature", then we apply the glyph to the entire range
    $glyph = $self->setting( $section, 'glyph' );
    $track_glyph =
      $self->setting( $section, 'track glyph' ) ||
        ( ( defined( $glyph ) && ( $glyph eq 'dna' ) ) ?
          'dna' :
          $default_track_glyph );
    if(
       ( defined( $glyph ) && ( $glyph eq 'dna' ) ) ||
       $self->setting( $section, 'global feature' )
      ) {

      ## TODO: What is really going on here?
      $track = $panel->add_track(
        ( ( $track_glyph eq 'dna' ) ? $segment : undef ),
        '-width'          => $width,
        '-track_glyph'    => $track_glyph,
        '-config_section' => $section,
        $conf->i18n_style( $section, $lang )
      );
      #unless( ( defined $glyph ) && ( $glyph eq 'dna' ) ) {
        $tracks{ $section } = $track;
      #}
    } else {
      $track = $panel->add_track(
        $track_glyph,
        '-config_section' => $section,
	$conf->i18n_style( $section, $lang, $length )
      );
      $tracks{ $section } = $track;
    }
    ## TODO: Put back
    #$collection =
    #  $segment->get_collection(
    #    $conf->label2type( $section, $length )
    #  );

    my @types = $conf->label2type( $section, $length );
    ## TODO: REMOVE
    warn "_get_detail_image: types for $section ( length $length ) are ( ", join( ', ', @types ) . " )" if DEBUG;

    $collection =
      $segment->get_collection(
        '-types' => \@types
      );

    # Don't bother if there's no features to display.
    #next unless defined $collection;
    unless( defined $collection ) {
      warn "Skipping $section glyph because there's no features of types ( ".join( ', ', @types ). " )" if DEBUG;
      next;
    }
    
    ## TODO: REMOVE
    warn "_get_detail_image: calling Glyph's set_feature_collection( $collection )" if DEBUG;

    ## TODO: Implement set_feature_collection in Glyph.pm
    $track->set_feature_collection( $collection );

    # We might need the feature_count to calculate the bump, label,
    # and description options, but we'll defer it until we know it's
    # necessary because it can be expensive to calculate.
    undef( $feature_count );

    if( $options->{ $section } ) {
      # We don't have to calculate feature counts if the options value isn't 0.
      if( $options->{ $section } == 1 ) {      # 'force no bump'
        $bump        = 0;
        $label       = 0;
        $description = 0;
      } elsif( $options->{ $section } == 2 ) { # 'force bump'
        $bump        = 1;
        $label       = 0;
        $description = 0;
      } elsif( $options->{ $section } == 3 ) { # 'force label'
        $bump        = 1;
        $label       = $self->setting( 'label' ) || 1;
        $description = $self->setting( 'description' ) || 1;
      } elsif( $options->{ $section } == 4 ) { # TODO: Document
        $bump        = 2;
        $label       = 0;
        $description = 0;
      } elsif( $options->{ $section } == 5 ) { # TODO: Document
        $bump        = 2;
        $label       = $self->setting( 'label' ) || 1;
        $description = $self->setting( 'description' ) || 1;
      } else {                                 # Who knows?  Just force no bump
        $bump        = 0;
        $label       = 0;
        $description = 0;
      }
    } else {                                   # 'auto'
      $bump = $conf->get_and_eval( $section, 'bump' );

      ## TODO: Put back.  This is a temporary hack; never look at the
      ## bump limits for now..

      #if( $bump || !defined( $bump ) ) {
      #  $feature_count = $collection->feature_count();
      #  if( $limit->{ $section } && $feature_count > $limit->{ $section } ) {
      #    $feature_count = $limit->{ $section };
      #  }
      #  $bump = ( $feature_count <= $max_bump );
      #}
      unless( defined $bump ) { $bump = 1; }
      $label = $conf->get_and_eval( $section, 'label' );
      if( $label || !defined( $label ) ) {

        ## TODO: Put back.  This is a temporary hack; never look at the
        ## label limits for now..

        #unless( defined $feature_count ) {
        #  $feature_count = $collection->feature_count();
        #  if( $limit->{ $section } && $feature_count > $limit->{ $section } ) {
        #    $feature_count = $limit->{ $section };
        #  }
        #}
        #$label = ( $feature_count <= $max_labels );
        unless( defined $label ) { $label = 1; }
      }
      $description = $conf->get_and_eval( $section, 'description' );
      if( $description ) {

        ## TODO: Put back.  This is a temporary hack; never look at the
        ## description limits for now..

        #unless( defined $feature_count ) {
        #  $feature_count = $collection->feature_count();
        #  if( $limit->{ $section } && $feature_count > $limit->{ $section } ) {
        #    $feature_count = $limit->{ $section };
        #  }
        #}
        #$description = ( $feature_count <= $max_labels );
        $description = 1;
      }
    }
    $tracks{ $section }->configure(
      '-bump'        => $bump,
      '-label'       => $label,
      '-description' => $description
    );
    unless( $bump ) {
      $tracks{ $section }->configure( '-connector' => 'none' );
    }
    #if( $limit->{ $section } > 0 ) {
    #  $tracks{ $section }->configure( '-bump_limit' => $limit->{ $section } );
    #} 
  } # End foreach $section in @$tracks, build the corresponding track.

  ## This was removed, but for the TODO I'm keeping it here.. #################
  # # Handle name-based groupings.  Since this occurs for every feature
  # # we cache the pattern data.
  # warn "$track group pattern => ",$conf->get_and_eval($label => 'group_pattern') if DEBUG;
  # unless( exists $group_pattern{ $label } ) {
  #   $group_pattern{ $label } =
  #     $conf->get_and_eval( $label => 'group_pattern' );
  # }
  # 
  # if (defined $group_pattern{$label}) {
  #   push @{$groups{$label}},$feature;
  #   next;
  # }
  ### TODO: ERE I AM.  This should be handled by attatching special aggregators.
  # handle pattern-based group matches
  #for my $label (keys %groups) {
  #  my $set     = $groups{$label};
  #  my $pattern = $group_pattern{$label} or next;
  #  $pattern =~ s!^/(.+)/$!$1!;  # clean up regexp delimiters
  #  my %pairs;
  #  for my $a (@$set) {
  #    (my $base = $a->name) =~ s/$pattern//i;
  #   push @{$pairs{$base}},$a;
  #  }
  #  my $track = $tracks{$label};
  #  foreach (values %pairs) {
  #   $track->add_group($_);
  #  }
  #}

  my $gd = $panel->gd();

  # Nice day for a black title.
  if( $title ) {
    $gd->string(
      gdMediumBoldFont,
      ( ( $width - ( length( $title ) * gdMediumBoldFont->width() ) ) / 2 ),
      0,
      $title,
      $panel->translate_color( 'black' )
    );
  }

  if( wantarray ) {
    # We need to do this in scalar context to get the ref to the boxes array.
    my $boxes = $panel->boxes();
    return ( $gd, $boxes, $panel );
  } else {
    return $gd;
  }
} # _get_detail_image(..)

=head2 _generate_image_url

  my $url = $browser->_generate_image_url( $gd_image )

Given a GD::Image object, this method calls its png() or gif() methods
(depending on GD version), stores the output into the temporary
directory given by the "tmpimages" option in the configuration file,
and returns a two element list consisting of the URL to the image and
the physical path of the image.

=cut

sub _generate_image_url {
  my $self      = shift;
  my ( $image ) = @_;

  my $extension = ( $image->can( 'png' ) ? 'png' : 'gif' );
  my $data      = ( $image->can( 'png' ) ? $image->png() : $image->gif() );
  my $signature = md5_hex( $data );

  # untaint signature for use in open
  $signature =~ /^([0-9A-Fa-f]+)$/g or return;
  $signature = $1;

  my ( $uri, $path ) = $self->_make_tmp_uri( $self->source() . '/img' );
  my $url       = sprintf( "%s/%s.%s", $uri, $signature, $extension );
  my $imagefile = sprintf( "%s/%s.%s", $path, $signature, $extension );

  # Write out the $data to $imagefile.
  my $image_fh;
  open( $image_fh, ">$imagefile" ) ||
    die( "Can't open image file $imagefile for writing: $!\n" );
  binmode( $image_fh );
  print $image_fh $data;
  close $image_fh;

  return $url;
} # _generate_image_url(..)

# ( $tmp_uri, $full_dirname ) = $browser->_make_tmp_uri( [$rel_dirname] );
sub _make_tmp_uri {
  my $self = shift;
  my $path = shift || '';

  my $tmpuri = $self->setting( 'tmpimages' ) or
    die "no tmpimages option defined, can't generate a picture";
  $tmpuri .= "/$path" if $path;
  my $tmpdir;
  if( $ENV{ 'MOD_PERL' } ) {
    my $r          = Apache->request;
    my $subr       = $r->lookup_uri( $tmpuri );
    $tmpdir        = $subr->filename;
    my $path_info  = $subr->path_info;
    $tmpdir       .= $path_info if $path_info;
  } else {
    my $document_root = $ENV{ 'DOCUMENT_ROOT' } || cwd();
    $tmpdir = "$document_root/$tmpuri";
  }
  # we need to untaint tmpdir before calling mkpath()
  return unless $tmpdir =~ /^(.+)$/;
  $path = $1;

  eval{ mkpath( $path, 0, 0777 ) unless -d $path; };
  warn $@ if $@;

  ## TODO: REMOVE
  $self->throw( $@ ) if $@;
  return ( $tmpuri, $path );
} # _make_tmp_uri(..)

sub _get_map_html {
  my $self = shift;
  my ( $settings, $boxes, $do_centering_map, $panel ) = @_;
  my $map = qq(<map name="hmap" id="hmap">\n);

  # $box_ref is [ $feature, $x1, $y1, $x2, $y2, $section ]
  my ( $feature, $x1, $y1, $x2, $y2, $section );
  foreach my $box_ref ( @$boxes ) {
    ( $feature, $x1, $y1, $x2, $y2, $section ) = @$box_ref;
    ## TODO: REMOVE?  What feature can't do primary_tag?
    unless( $feature->can( 'primary_tag' ) ) {
      warn "Unexpected: The feature $feature, a ".ref( $feature )." can't do primary_tag()." if DEBUG;
      next;
    }
    ## TODO: What is so special about DasSegment?  This seems to
    ## indicate that the segment is a ruler/scale.
    if( $feature->primary_tag() eq 'DasSegment' ) {
      if( $do_centering_map ) {
        $map .= $self->_get_centering_map_html( $settings, $box_ref );
      }
      next;
    }
    my $href   = $self->_get_link( $section, $feature, $panel ) or next;
    my $target = $self->_get_link_target( $section, $feature, $panel );
    my $alt    = $self->_get_map_title( $section, $feature, $panel );
    my $t      = ( defined( $target ) ? qq(target="$target") : '' );
    $map .= qq(<area shape="rect" coords="$x1,$y1,$x2,$y2" href="$href" title="$alt" alt="$alt" $t/>\n);
  }
  $map .= "</map>\n";
  return $map;
} # _get_map_html(..)

# this creates image map for rulers and scales, where clicking on the scale
# should center the image on the scale.
sub _get_centering_map_html {
  my $self = shift;
  my ( $settings, $ruler_box_ref ) = shift;

  my ( $ruler, $x1, $y1, $x2, $y2 ) = @$ruler_box_ref;

  return if ( $x2 - $x1 ) == 0;

  my $length = $ruler->length();
  my $offset = $ruler->start();
  my $scale  = ( $length / ( $x2 - $x1 ) );

  my $ruler_intervals = $settings->{ 'ruler_intervals' };
  # divide into 'ruler_interval' intervals
  my $portion = ( $x2 - $x1 ) / $ruler_intervals;
  my $seq_id  = ( '' . $ruler->seq_id() );
  my $source  = $self->source();

  my $plugin  = escape( param( 'plugin' ) || '' );

  my @lines;
  for ( my $i = 0; $i < $ruler_intervals; $i++ ) {
    my $interval_x1 = int( ( $portion * $i ) + 0.5 );
    my $interval_x2 = int( ( $portion * ( $i + 1 ) ) + 0.5 );
    # put the middle of the sequence range into the middle of the picture
    my $middle =
      $offset + ( ( $scale * ( $interval_x1 + $interval_x2 ) ) / 2 );
    my $start  = int( $middle - ( $length / 2 ) );
    my $end   = int( $start + $length - 1 );
    my $url    = url( '-relative' => 1, '-path_info' => 1 );
    $url .= "?seq_id=$seq_id;start=$start;end=$end;source=$source;nav4=1;plugin=$plugin";

    push @lines,
      qq(<area shape="rect" coords="$interval_x1,$y1,$interval_x2,$y2" href="$url" title="recenter" alt="recenter"/>\n);
  }
  return join( '', @lines );
} # _get_centering_map_html(..)

=head2 _get_overview_image()

  $gd_image = $browser->_get_overview_image( $segment );

This method generates a GD::Image object containing the image data for
the overview panel.  Its argument is a Bio::SeqFeature::SegmentI
object.  It returns the GD image.

In the configuration file, any section labeled "[something:overview]"
will be added to the overview panel.

=cut

sub _get_overview_image {
  my $self = shift;
  my ( $segment ) = @_;

  my $conf           = $self->config();

  my $width          = $self->width();
  my @tracks         = $conf->overview_tracks();
  my( $padl, $padr ) = $self->_overview_pad( \@tracks );

  ## TODO: Magic #s
  my $bgcolor        = $self->setting( 'overview bgcolor' ) || 'wheat';
  ## TODO: There seems to be some confusion about which units setting to use.
  #my $units         = $self->setting( 'overview units' );
  my $units          = $self->setting( 'units' )            || '';
  my $unit_divider   = $self->setting( 'unit_divider' )     || 1;

  ## TODO: REMOVE
  warn "_get_overview_image A" if DEBUG;

  my $panel =
    Bio::Graphics::Panel->new(
      '-segment'    => $segment->abs_range(),#$segment,
      '-width'      => $width,
      '-bgcolor'    => $bgcolor,
      '-key_style'  => 'left',
      '-pad_left'   => $padl,
      '-pad_right'  => $padr,
      '-pad_bottom' => $self->setting( 'pad_overview_bottom' )
    );

  ## TODO: REMOVE
  warn "_get_overview_image B" if DEBUG;

  ## TODO: Change the label to use display_name, or to_string?
  $panel->add_track(
    $segment->abs_range(),#$segment,
    #$segment,
    #'-track_glyph'  => 'arrow',
    '-glyph'        => 'arrow',
    '-shallow'      => 1,
    '-double'       => 1,
    '-label'        => 'Overview of ' . $segment->seq_id(),
    '-labelfont'    => gdMediumBoldFont,
    '-tick'         => 2,
    ( $units ? ( '-units' => $units ) : () ),
    '-unit_divider' => $unit_divider
  );

  ## TODO: REMOVE
  warn "_get_overview_image C" if DEBUG;

  $self->_add_overview_tracks( $panel, $segment, \@tracks, $padl );

  ## TODO: REMOVE
  warn "_get_overview_image D" if DEBUG;

  my $gd = $panel->gd();

  # Paint a red border.
  my $red = $gd->colorClosest( 255, 0, 0 );
  my ( $x1, $x2 ) =
    $panel->map_pt( $segment->start(), $segment->end() );
  my ( $y1, $y2 ) = ( 0, $panel->height() - 1 );
  if( $x2 >= $panel->right() ) {
    $x2 = $panel->right() - 1;
  }
  $gd->rectangle( $x1, $y1, $x2, $y2, $red );

  ## TODO: REMOVE
  warn "_get_overview_image E" if DEBUG;

  return $gd;
} # _get_overview_image(..)

sub _add_overview_tracks {
  my $self = shift;
  my ( $panel, $segment, $tracks, $pad ) = @_;

  return {} unless @$tracks;

  my $conf = $self->config();
  my $default_track_glyph = $self->setting( 'track glyph' )   || 'generic';
  my $max_label           = $self->setting( 'label density' ) || 10;
  my $max_bump            = $self->setting( 'bump density' )  || 50;
  my $length              = $segment->length();

  ## TODO: REMOVE
  warn "_add_overview_tracks 1" if DEBUG;

  my ( $collection, %tracks, $track, $feature_count, $bump, $label );
  foreach my $section ( @$tracks ) {
    ## TODO: REMOVE
    warn "_add_overview_tracks 1: Adding track for $section." if DEBUG;

    $tracks{ $section } = $track =
      $panel->add_track(
        '-glyph'   => $default_track_glyph,
        '-height'  => 3,
        '-fgcolor' => 'black',
        '-bgcolor' => 'black',
        '-config_section' => $section,
        $conf->style( $section )
      );
    my @types = $conf->label2type( $section, $length );
    ## TODO: REMOVE
    warn "_add_overview_tracks 1: section $section corresponds to types ( ".join( ', ', @types )." )." if DEBUG;
    if( @types ) {
      $collection =
        $segment->get_collection(
          @types
        );
    } else {
      undef $collection;
    }
    # Don't bother if there's no features to display.
    #next unless $collection;
    unless( defined $collection ) {
      warn "Skipping $section glyph because there's no features of types ( ".join( ', ', @types ). " )" if DEBUG;
      next;
    }
    
    ## TODO: REMOVE.
    warn "_add_overview_tracks 1: got the collection: $collection." if DEBUG;
    $track->set_feature_collection( $collection );

    # Now calculate the bump and label options.  We might need feature
    # counts for this, but we'll defer because it can be expensive and
    # we might not need it.
    undef( $feature_count );
    $bump = $conf->get_and_eval( $section, 'bump' );
    unless( defined $bump ) {

      ## TODO: Put back.  This is a temporary hack; never look at the
      ## bump limits for now..

      #$feature_count = $collection->feature_count();
      #$bump = ( $feature_count <= $max_bump );
      $bump = 1;
    }
    $label = $conf->get_and_eval( $section, 'label' );
    unless( defined $label ) {

      ## TODO: Put back.  This is a temporary hack; never look at the
      ## label limits for now..

      #unless( defined $feature_count ) {
      #  $feature_count = $collection->feature_count();
      #}
      #$label = ( $feature_count <= $max_label );
      $label = 1;
    }
    $track->configure( '-bump' => $bump, '-label' => $label );
  } # End foreach $section in @$tracks, build the corresponding overview track.
  ## TODO: REMOVE
  warn "_add_overview_tracks 2" if DEBUG;
  return \%tracks;
} # _add_overview_tracks(..)

=head2 _hits_on_overview()

  $hashref = $browser->_hits_on_overview(@hits);

This method is used to render a series of genomic positions ("hits")
into a graphical summary of where they hit on the genome in a
segment-by-segment (e.g. chromosome) manner.

The arguments are one of:

  1) a set of array refs in the form [seq_id,start,end,name], where
     name is optional.

  2) a Bio::SeqFeatureI object.

The returned HTML is stored in a hashref, where the keys are the
reference sequence names and the values are HTML to be emitted.

=cut

# Return an HTML showing where multiple hits fall on the genome.
# Can either provide a list of Bio::SeqFeature::SegmentI objects, or
# a list of arrayrefs in the form [seq_id,start,end,[name]]
sub _hits_on_overview {
  my $self = shift;
  my ( $hits ) = @_;

  my %html; # results are a hashref sorted by chromosome

  my $conf  = $self->config();
  my $width = $self->width();
  my $units = $self->setting( 'overview units' );
  my $max_label  = $self->setting( 'label density' ) || 10;
  my $max_bump   = $self->setting( 'bump density' ) || 50;
  my $class      =
    ( $hits->[ 0 ]->can( 'class' ) ?
      $hits->[ 0 ]->class() :
      'Sequence' );
  my @overview_tracks = $conf->overview_tracks();
  my ( $padl, $padr ) =
    $self->_overview_pad( \@overview_tracks, 'Matches' );

  # Make Bio::Graphics::Feature objects for every hit and store them
  # binned by shared seq_id.
  ## TODO: Why do we have to make SeqFeatureI objects into
  ## Bio::Graphics::Feature objects?
  my ( %seq_ids );
  for my $hit ( @$hits ) {
    if( ref( $hit ) eq 'ARRAY' ) {
      my ( $seq_id, $start, $end, $name ) = @$hit;
      push( @{ $seq_ids{ $seq_id } },
            Bio::Graphics::Feature->new(
              '-start' => $start,
              '-end'   => $end,
              '-name'  => ( $name || '' )
            )
          );
    } elsif( $hit->isa( 'Bio::SeqFeatureI' ) ) {
      my $seq_id  = $hit->seq_id();
      my $name    = ( $hit->can( 'seq_name' ) ?
                      $hit->seq_name() :
                      ( $hit->display_name() || $hit->primary_tag() ) );
      my( $start, $end ) = ( $hit->start(), $hit->end() );
      $name =~ s/\:\d+,\d+$//;  # remove coordinates if they're there
      if( length( $name ) > 10 ) {
        $name = substr( $name, 0, 7 ) . '...';
      }
      push( @{ $seq_ids{ $seq_id } },
            Bio::Graphics::Feature->new(
              '-start' => $start,
              '-end'   => $end,
              '-name'  => $name
            )
          );
    }
  } # End foreach $hit, create a Bio::Graphics::Feature & bin by seq_id.

  for my $seq_id ( sort keys %seq_ids ) {
    my ( $segment ) =
      $conf->segment( '-class' => $class, '-name' => $seq_id );
    my $panel =
      Bio::Graphics::Panel->new(
        '-segment'    => $segment,
        '-width'      => $width,
        '-bgcolor'    => ( $self->setting( 'overview bgcolor' ) || 'wheat' ),
        '-pad_left'   => $padl,
        '-pad_right'  => $padr,
        '-pad_bottom' => $self->setting( 'pad_overview_bottom' ),
        '-key_style'  => 'left'
      );

    # add the arrow
    $panel->add_track(
      $segment,
      '-glyph'     => 'arrow',
      '-shallow'   => 1,
      '-double'    => 1,
      '-label'     => 0, #"Overview of ".$segment->seq_id(),
      '-labelfont' => gdMediumBoldFont,
      '-tick'      => 2,
      ( $units ? ( '-units' => $units ) : () )
    );

    # add the landmarks
    $self->_add_overview_tracks(
      $panel,
      $segment,
      \@overview_tracks
    );

    # add the hits
    $panel->add_track(
      $seq_ids{ $seq_id },
      '-glyph'    => 'diamond',
      '-height'   => 8,
      '-fgcolor'  => 'red',
      '-bgcolor'  => 'red',
      '-fallback_to_rectangle' => 1,
      '-key'      => 'Matches',
      '-bump'     => ( @{ $seq_ids{ $seq_id } } <= $max_bump ),
      '-label'    => ( @{ $seq_ids{ $seq_id } } <= $max_bump )  # deliberate
     );

    my $gd    = $panel->gd();
    my $boxes = $panel->boxes();
    $html{ $seq_id } = $self->_hits_to_html( $seq_id, $gd, $boxes );
  }
  return \%html;
} # _hits_on_overview(..)

# utility called by _hits_on_overview
sub _hits_to_html {
  my $self = shift;
  my ( $seq_id, $gd, $boxes ) = @_;

  my $source   = $self->source();
  my $self_url = url( '-relative' => 1 );
  $self_url   .= "?source=$source";

  my ( $width, $height ) = $gd->getBounds();
  my $url       = $self->_generate_image( $gd );
  my $img =
    img(
        { '-src'    => $url,
          '-align'  => 'middle',
          '-usemap' => "#$seq_id",
          '-width'  => $width,
          '-height' => $height,
          '-border' => 0 }
       );
  my $html = "\n";
  $html   .= $img;
  $html   .= qq(<br /><map name="$seq_id" alt="imagemap" />\n);

  # use the scale as a centering mechanism
  my $ruler_box_ref = shift @$boxes;
  return unless $ruler_box_ref;  # don't know why....
  my ( $ruler, $x1, $y1, $x2, $y2 ) = @$ruler_box_ref;
  my $ruler_intervals = $self->setting( 'ruler_intervals' );
  my $length  = ( $ruler->length() / $ruler_intervals );
  $width      = ( ( $x2 - $x1 ) / $ruler_intervals );
  my ( $x, $y, $start, $end, $href );
  for my $i ( 0..$ruler_intervals - 1 ) {
    $x = ( $x1 + ( $i * $width ) );
    $y = ( $x + $width );
    $start = int( $length * $i );
    $end  = int( $start + $length );
    $href  = ( $self_url . ";seq_id=$seq_id;start=$start;end=$end" );
    $html .= qq(<area shape="rect" coords="$x,$y1,$y,$y2" href="$href" alt="ruler" />\n);
  }

  foreach ( @$boxes ){
    ( $start, $end ) = ( $_->[ 0 ]->start(), $_->[ 0 ]->end() );
    $href = ( $self_url . ";seq_id=$seq_id;start=$start;end=$end" );
    $html .= qq(<area shape="rect" coords="$_->[1],$_->[2],$_->[3],$_->[4]" href="$href" alt="ruler" />\n);
  }
  $html .= "</map>\n";
  return $html;
} # _hits_to_html(..)

# return ( max, min ) pixels required to pad the overview panel for
# including the given tracks' key strings.  Tracks are given as an
# array ref.  Other strings may be given as extra args.
sub _overview_pad {
  my $self   = shift;
  my ( $tracks, @more_strings ) = @_;

  my $conf = $self->config();
  $tracks ||= [ $conf->overview_tracks() ];
  my $max = 0;
  foreach my $section ( @$tracks ) {
    my $key = $self->setting( $section, 'key' );
    next unless defined $key;
    $max = length $key if length $key > $max;
  }
  foreach my $str ( @more_strings ) {  #extra
    $max = length $str if length $str > $max;
  }
  if( $max ) {
    return ( ( $max * gdMediumBoldFont->width() ) + 3,
             $self->setting( 'min_overview_pad' ) );
  } else {
    return ( $self->setting( 'min_overview_pad' ),
             $self->setting( 'min_overview_pad' ) );
  }
} # _overview_pad(..)

sub _name2segments {
  my $self = shift;
  my ( $settings, $name ) = @_;

  my $toomany = $self->setting( 'too_many_segments' );
  my $max_segment = $self->setting( 'max_segment' );

  my ( @segments, $class, $start, $end );
  if( $name =~ /([\w._-]+):(-?[\dkKmM.]+),(-?[\dkKmM.]+)$/ or
      $name =~ /([\w._-]+):(-?[\dkKmM,.]+)(?:-|\.\.)(-?[\dkKmM,.]+)$/ ) {
    $name  = $1;
    $start = $2;
    $end  = $3;
    $start =~ s/,\.//g; # get rid of commas
    $end  =~ s/,\.//g;
    if( $start =~ /[kKmM]/ ) {
      my ( $millions, $rest ) = ( $start =~ /^(\d+)[Mm](.*)$/ );
      unless( defined $millions ) {
        $rest = $start;
      }
      my ( $thousands, $ones ) = ( $rest =~ /^(\d+)[Kk](\d*)$/ );
      $start = ( $millions * 1000000 ) + ( $thousands * 1000 ) + $ones;
    }
    ## Hey, you.  Pssst.  C'mere.  Yeah, you!
    ## The above code and the below should be exactly the same except
    ## s/start/end/g;
    if( $end =~ /[kKmM]/ ) {
      my ( $millions, $rest ) = ( $end =~ /^(\d+)[Mm](.*)$/ );
      unless( defined $millions ) {
        $rest = $end;
      }
      my ( $thousands, $ones ) = ( $rest =~ /^(\d+)[Kk](\d*)$/ );
      $end = ( $millions * 1000000 ) + ( $thousands * 1000 ) + $ones;
    }
  } elsif( $name =~ /^(\w+):(.+)$/ ) {
    ## TODO: Note that this is for namespace qualifiers on the feature or sequence name, but if that's the case, shouldn't it also be done in the above regexp?
    $class = $1;
    $name  = $2;
  }

  my $divisor = $self->setting( 'unit_divider' ) || 1;
  $start *= $divisor if defined $start;
  $end   *= $divisor if defined $end;

  ## TODO: We often pass in -start and -end instead of -range, but we don't have a seq_id to build a range from.  Should we use name as seq_id?
  my @argv = ( '-name'  => $name );
  push( @argv, ( '-class' => $class ) ) if defined $class;
  if( defined( $start ) || defined( $end ) ) {
    push( @argv,
          ( '-range' => Bio::RelRange->new(
                          '-start' => $start,
                          '-end' => $end
                        ) ) );
  }

  ## TODO: REMOVE
  warn "_name2segments: \@argv is " . Dumper( \@argv ) if DEBUG;

  ## TODO: Why do we interchange 'get_collection' and 'segment'?
  @segments = $self->config()->segment( @argv );

  ## TODO: REMOVE
  warn "_name2segments: First attempt got " . scalar( @segments ) . " segments." if DEBUG;
  if( @segments ) {
    warn "_name2segments: The first segment, ".$segments[ 0 ].", has " . $segments[ 0 ]->feature_count() . " features." if DEBUG;
  } else {
    warn "_name2segments: Didn't find it as-is.." if DEBUG;
  }

  # Here starts the heuristic part.  Try various abbreviations that
  # people tend to use for chromosomal addressing.
  if( !@segments && ( $name =~ /^([\dIVXA-F]+)$/ ) ) {
    my $id = $1;
    foreach ( qw( CHROMOSOME_ Chr chr ) ) {
      ## TODO: REMOVE
      warn "Trying with a leading string of $_" if DEBUG;
      my $n = "${_}${id}";
      @argv = ( '-name'  => $n );
      push( @argv, ( '-class' => $class ) ) if defined $class;
      if( defined( $start ) || defined( $end ) ) {
        push( @argv,
              ( '-range' => Bio::RelRange->new(
                              '-start' => $start,
                              '-end' => $end
                            ) ) );
      }
      @segments = $self->config()->segment( @argv );
      last if @segments;
    }
    if( @segments ) {
      ## TODO: REMOVE
      warn "_name2segments: Got " . scalar( @segments ) . " segments." if DEBUG;
      warn "_name2segments: The first segment, ".$segments[ 0 ].", has " . $segments[ 0 ]->feature_count() . " features." if DEBUG;
    } else {
      warn "_name2segments: Didn't find it that way.." if DEBUG;
    }
  }

  # try to remove the chr CHROMOSOME_I
  if( !@segments && ( $name =~ /^(chromosome_?|chr)/i ) ) {
    ## TODO: REMOVE
    warn "Trying without the leading string" if DEBUG;
      ( my $chr = $name ) =~ s/^(chromosome_?|chr)//i;
      @argv = ( '-name'  => $chr );
      push( @argv, ( '-class' => $class ) ) if defined $class;
      if( defined( $start ) || defined( $end ) ) {
        push( @argv,
              ( '-range' => Bio::RelRange->new(
                              '-start' => $start,
                              '-end' => $end
                            ) ) );
      }
    @segments = $self->config()->segment( @argv );
    if( @segments ) {
      ## TODO: REMOVE
      warn "_name2segments: Got " . scalar( @segments ) . " segments." if DEBUG;
      warn "_name2segments: The first segment, ".$segments[ 0 ].", has " . $segments[ 0 ]->feature_count() . " features." if DEBUG;
    } else {
      warn "_name2segments: Didn't find it that way either.." if DEBUG;
    }
  }

  # try the wildcard version, but only if the name is of significant length
  if( !@segments && ( length( $name ) > 3 ) ) {
    @argv =    ( '-name'  => "$name*" );
    if( defined( $start ) || defined( $end ) ) {
      push( @argv,
            ( '-range' => Bio::RelRange->new(
                            '-start' => $start,
                            '-end' => $end
                          ) ) );
    }
    @segments = $self->config()->segment( @argv );
  }

  # try any "automatic" classes that have been defined in the config file
  if( !@segments &&
      !$class &&
      ( my @automatic = split( /\s+/, $self->setting( 'automatic classes' ) ||
                                      '' ) )
    ) {
    my @names =
      ( ( ( length( $name ) > 3 ) && 
          ( $name !~ /\*/ ) ) ?
        ( $name, "$name*" ) :
        $name );  # possibly add a wildcard
  NAME:
    foreach $class ( @automatic ) {
      for my $n ( @names ) {
        @argv =      ( '-name'  => $n );
        push( @argv, ( '-class' => $class ) );
        if( defined( $start ) || defined( $end ) ) {
          push( @argv,
                ( '-range' => Bio::RelRange->new(
                                '-start' => $start,
                                '-end' => $end
                              ) ) );
        }
        # we are deliberately doing something different in the case
        # that the user typed in a wildcard vs an automatic wildcard
        # being added
        @segments = $self->config()->segment( @argv );
        last NAME if @segments;
      } # End foreach $n in @names
    } # End foreach $class (This is the loop called NAME)
  } # End if still no @segments, try automatic classes.

  # user wanted multiple locations, so user gets them
  return @segments if ( $name =~ /\*/ );

  # Otherwise we try to merge segments that are adjacent if we can!
  ## TODO: REMOVE.  This bit here is now unnecessary because the segments are necessarily on different sequences, so they're already merged if they need to be.

  ## This tricky bit is called when we retrieve multiple segments or when
  ## there is an unusually large feature to display.  In this case, we attempt
  ## to split the feature into its components and offer the user different
  ## portions to look at, invoking _merge_segments() to select the regions.
  #my $max_length = 0;
  #foreach my $segment ( @segments ) {
  #  if( $segment->length() > $max_length ) {
  #    $max_length = $segment->length();
  #  }
  #}
  #if( ( @segments > 1 ) || ( $max_length > $max_segment ) ) {
  #  my @s =
  #    $self->config()->segment(
  #      '-class'     => $segments[ 0 ]->class(),
  #      '-unique_id' => ( '' . $segments[ 0 ]->seq_id() ),
  #      '-automerge' => 0
  #    );
  #  if( ( @s > 1 ) && ( @s < $toomany ) ) {
  #    @segments = $self->_merge_segments( \@s, ( $self->get_ranges() )[ -1 ] );
  #  }
  #}
  ## TODO: REMOVE
  warn "_name2segments: returning \@segments ( " . join( ', ', @segments ) . " )" if DEBUG;

  return @segments;
} # _name2segments(..)

# auxiliary to _name2segments(..)
sub _merge_segments {
  my $self = shift;
  my ( $segments, $max_range ) = @_;
  $max_range ||= 100_000; ## TODO: Magic #

  my ( %segs, @merged_segs );
  push( @{ $segs{ $_->seq_id() } }, $_ ) foreach @$segments;
  foreach my $seq_id ( keys %segs ) {
    push( @merged_segs,
          $self->_merge_segments_low( $segs{ $seq_id }, $max_range ) );
  }
  return @merged_segs;
} # _merge_segments(..)

# auxiliary to _merge_segments(..)
# Merge segments when the gap between them is less than two standard
# deviations from the mean gap.
sub _merge_segments_low {
  my $self = shift;
  my ( $segments, $max_range ) = @_;

  my ( $previous_start, $previous_end, $statistical_cutoff, @spans );

  my @segments = sort { $a->low() <=> $b->low() } @$segments;

  # run through the segments, and find the mean and stdev gap length
  # need at least 10 segments before this becomes reliable
  if( @segments >= 10 ) {
    my ( $total, $gap_length, @gaps, $gap );
    for( my $seg_i = 0; $seg_i < ( @$segments - 1 ); $seg_i++ ) {
      $gap = $segments[ $seg_i + 1 ]->low() - $segments[ $seg_i ]->high();
      $total++;
      $gap_length += $gap;
      push( @gaps, $gap );
    }
    my $mean = ( $gap_length / $total );
    my $variance;
    ( $variance += ( ( $_ - $mean ) ** 2 ) ) foreach @gaps;
    my $stdev = sqrt( $variance / $total );
    $statistical_cutoff = ( $stdev * 2 );
  } else {
    $statistical_cutoff = $max_range;
  }

  my $seq_id = $segments[ 0 ]->seq_id();

  for my $segment ( @segments ) {
    my $start = $segment->low();
    my $end  = $segment->high();

    if( defined( $previous_end ) &&
	( ( ( $start - $previous_end ) >= $max_range ) ||
	  ( ( $previous_end - $previous_start ) >= $max_range ) ||
	  ( ( $start - $previous_end ) >= $statistical_cutoff ) ) ) {
      push( @spans,
            $self->config()->segment(
              '-range' => Bio::RelRange->new(
                            '-seq_id' => $seq_id,
                            '-start'  => $previous_start,
                            '-end'    => $previous_end
                          ) ) );
      $previous_start = $start;
      $previous_end  = $end;
    } else {
      $previous_start = $start unless defined $previous_start;
      $previous_end  = $end;
    }
  } # end foreach $segment

  ## TODO: Note that it used to be segments[ 0
  ## ]->factory()->refclass().  Dunno if changing it to ->class() was
  ## the right thing to do.
  my $class = $segments[ 0 ]->class();
  my @args  =
    ( '-range' => Bio::RelRange->new(
                    '-seq_id' => $seq_id,
                    '-start'  => $previous_start,
                    '-end'    => $previous_end
                  ) );
  push @args, ( '-class' => $class ) if defined $class;
  push( @spans,
        ( $self->config()->segment( @args ) ||
          Bio::Graphics::Feature->new(
            '-seq_id' => $seq_id,
            '-start'  => $previous_start,
            '-end'    => $previous_end
        ) ) );
  return @spans;
} # _merge_segments_low(..)

sub _html_error {
  my $self = shift;
  my $settings = shift;
  my @msg = @_;

  warn "@msg" if DEBUG;

  my $out_fh = $settings->{ '_out_fh' };

  $self->_maybe_print_top( $settings );
  print $out_fh h2( { '-class' => 'error' }, @msg );
} # _html_error(..)

## TODO: REMOVE?  This is unused.
sub fatal_error {
  my $self = shift;
  my @msg = @_;
  warn "@_" if DEBUG;
  maybe_print_top();
  print h2('An internal error has occurred');
  print p({-class=>'error'},@msg);
  my $webmaster = $ENV{SERVER_ADMIN} ?
   "maintainer (".a({-href=>"mailto:$ENV{SERVER_ADMIN}"},$ENV{SERVER_ADMIN}).')'
     : 'maintainer';
  print p("Please contact this site's $webmaster for assistance.");
  print $self->footer();
  exit 0;
} # fatal_error(..)

## TODO: REMOVE?  This is unused
sub debugging_rectangles {
  my ($image,$boxes) = @_;
  my $black = $image->colorClosest(0,0,0);
  foreach (@$boxes) {
    my @rect = @{$_}[1,2,3,4];
    $image->rectangle(@{$_}[1,2,3,4],$black);
  }
} # debugging_rectangles(..)

## TODO: REMOVE.  This is being kept around for my own notes only.
=head2 db_settings()

  @args = $browser->db_settings;

Returns the appropriate arguments for connecting to Bio::DB::GFF.  It
can be used this way:

  $db = Bio::DB::GFF->new($browser->db_settings);

=cut

# get database adaptor name and arguments
#sub db_settings {
#  my $self = shift;
#
#  my $adaptor = $self->setting('db_adaptor') || DEFAULT_DB_ADAPTOR;
#  eval "require $adaptor; 1" or die $@;
#  my $args    = $self->config()->get_and_eval(general => 'db_args');
#  my @argv = ref $args eq 'CODE'
#        ? $args->()
#	: shellwords($args||'');
#
#  # for compatibility with older versions of the browser, we'll hard-code some arguments
#  if (my $adaptor = $self->setting('adaptor')) {
#    push @argv,(-adaptor => $adaptor);
#  }
#
#  if (my $dsn = $self->setting('database')) {
#    push @argv,(-dsn => $dsn);
#  }
#
#  if (my $fasta = $self->setting('fasta_files')) {
#    push @argv,(-fasta=>$fasta);
#  }
#
#  if (my $user = $self->setting('user')) {
#    push @argv,(-user=>$user);
#  }
#
#  if (my $pass = $self->setting('pass')) {
#    push @argv,(-pass=>$pass);
#  }
#
#  ## TODO: Here is where we should add the special aggregators for the per-section "group pattern" entries.
#  if (my @aggregators = shellwords($self->setting('aggregators')||'')) {
#    push @argv,(-aggregator => \@aggregators);
#  }
#
#  ($adaptor,@argv);
#} # db_settings(..)

sub max {
  my ( $a, $b ) = @_;
  return ( $a > $b ) ? $a : $b;
}

1;

__END__


=head1 SEE ALSO

L<Bio::Graphics::Panel>,
L<Bio::Graphics::Glyph>,
L<Bio::Graphics::Feature>,
L<Bio::Graphics::FeatureFile>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2001 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut
