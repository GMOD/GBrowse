package Bio::Graphics::Browser;

# $Id: Browser.pm,v 1.51.2.2 2003-04-07 21:34:00 pedlefsen Exp $
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
use File::Basename 'basename';
use Bio::Graphics;
use Carp qw(carp croak);
use GD 'gdMediumBoldFont','gdLargeFont';
use CGI qw(img param escape url);
use Digest::MD5 'md5_hex';
use File::Path 'mkpath';
use Text::Shellwords;

use Bio::Graphics::Browser::I18n;
use Bio::Graphics::Browser::ConfigIO;

use vars qw( $VERSION @ISA );
$VERSION = '1.15';

use constant DEFAULT_WIDTH => 800;
use constant DEFAULT_DB_ADAPTOR  => 'Bio::DB::GFF';
use constant DEFAULT_KEYSTYLE    => 'bottom';
use constant DEFAULT_EMPTYTRACKS => 'key';
use constant RULER_INTERVALS     => 20;  # fineness of the centering map on the ruler
use constant TOO_MANY_SEGMENTS   => 5_000;
use constant MAX_SEGMENT         => 1_000_000;
use constant DEFAULT_RANGES      => q(100 500 1000 5000 10000 25000 100000 200000 400000);
use constant MIN_OVERVIEW_PAD    => 25;
use constant PAD_OVERVIEW_BOTTOM => 3;

use constant DEBUG => 0;
## TODO: REMOVE
#use constant DEBUG => 1;

=head2 new()

  my $browser = Bio::Graphics::Browser->new();

Create a new Bio::Graphics::Browser object.  The object is initially
empty.  This is done automatically by gbrowse.

=cut

sub new {
  my $class    = shift;
  my $self = bless {}, ( ref( $class ) || $class );
  return $self;
} # new(..)

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

=head2 read_configuration()

  my $success = $browser->read_configuration('/path/to/gbrowse.conf');

Parse the files in the gbrowse.conf configuration directory.  This is
done automatically by gbrowse.  Returns a true status code if
successful.

=cut

sub read_configuration {
  my $self        = shift;
  my $conf_dir    = shift;
  $self->{ '_sources' } ||= {};

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
  # Build up the '_sources' hash with the source name ($basename)
  # mapped to the file name of the corresponding config file.  The
  # config file won't actually be loaded until the corresponding
  # source is used (so the initial config file will be loaded, but the
  # others won't yet).  When Config objects are instantiated they will
  # replace the file names in the '_sources' hash.
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
    $self->{ '_sources' }{ $basename } = $file;
    $basename_mtime{ $basename } = $mtimes{ $file };
    $source ||= $basename;
  }
  # This will load the Config file:
  $self->source( $source );

  return 1; # Why? I dunno.
} # read_configuration(..)

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
  my $sources = $self->{ '_sources' } or return;
  return keys %$sources;
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
  if( defined( $new_value ) ) {
    unless( $self->{ '_sources' }{ $new_value } ) {
      carp( "invalid source: $new_value" );
      return $old_value;
    }
    $self->{ '_source' } = $new_value;
    unless( ref( $self->{ '_sources' }{ $new_value } ) ) {
      # If the config hasn't yet been instantiated, do it.
      $self->{ '_sources' }{ $new_value } =
        Bio::Graphics::Browser::ConfigIO->new(
          '-file'=>$self->{ '_sources' }{ $new_value },
          '-safe'=>1
        )->read_config();
    }
    # If the new config specifies a default width, use it.
    $self->width( $self->setting( 'default_width' ) ) if
      $self->setting( 'default_width' );
    $self->width( DEFAULT_WIDTH ) unless $self->width();
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
  $self->{ '_sources' }{ $source };
} # config()

=head2 setting()

  $value = $browser->setting(general => 'stylesheet');
  $value = $browser->setting(gene => 'fgcolor');
  $value = $browser->setting('stylesheet');

The setting() method returns the value of one of the current source's
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

sub setting {
  shift->config()->get( @_ );
}

sub code_setting {
  shift->config()->get_and_eval( @_ );
}

=head2 db_settings()

  @args = $browser->db_settings;

Returns the appropriate arguments for connecting to Bio::DB::GFF.  It
can be used this way:

  $db = Bio::DB::GFF->new($browser->db_settings);

=cut

## TODO: This will go away.

# get database adaptor name and arguments
sub db_settings {
  my $self = shift;

  my $adaptor = $self->setting('db_adaptor') || DEFAULT_DB_ADAPTOR;
  eval "require $adaptor; 1" or die $@;
  my $args    = $self->config()->get_and_eval(general => 'db_args');
  my @argv = ref $args eq 'CODE'
        ? $args->()
	: shellwords($args||'');

  # for compatibility with older versions of the browser, we'll hard-code some arguments
  if (my $adaptor = $self->setting('adaptor')) {
    push @argv,(-adaptor => $adaptor);
  }

  if (my $dsn = $self->setting('database')) {
    push @argv,(-dsn => $dsn);
  }

  if (my $fasta = $self->setting('fasta_files')) {
    push @argv,(-fasta=>$fasta);
  }

  if (my $user = $self->setting('user')) {
    push @argv,(-user=>$user);
  }

  if (my $pass = $self->setting('pass')) {
    push @argv,(-pass=>$pass);
  }

  ## TODO: Here is where we should add the special aggregators for the per-section "group pattern" entries.
  if (my @aggregators = shellwords($self->setting('aggregators')||'')) {
    push @argv,(-aggregator => \@aggregators);
  }

  ($adaptor,@argv);
}

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
  my $section   = shift;
  my $language  = shift;
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
  if( ref $header eq 'CODE' ) {
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
  my $footer = $self->config()->get_and_eval('footer');
  if( ref $footer eq 'CODE' ) {
    my $f = eval { $footer->( @_ ) };
    warn $@ if $@;
    return $f;
  }
  return $footer;
} # footer()

=head2 make_link()

  $url = $browser->make_link($section,$feature,$panel)

Given a Bio::SeqFeatureI object, turn it into a URL suitable for use
in a hypertext link.  For convenience, the Bio::Graphics panel is also
provided.

=cut

sub make_link {
  my $self     = shift;
  my ( $section, $feature, $panel )  = @_;

  return $feature->make_link() if $feature->can( 'make_link' );

  my $link     = $self->code_setting( $section, 'link' );
  $link        = $self->code_setting( 'link' ) unless defined $link;
  return unless $link;
  if( ref( $link ) eq 'CODE' ) {
    my $val = eval { $link->( $feature, $panel ) };
    warn $@ if $@;
    return $val;
  }
  return $self->link_pattern( $link, $feature, $panel );
} # make_link(..)

# make the title for an object on a clickable imagemap
sub make_title {
  my $self = shift;
  my( $section, $feature, $panel ) = @_;

  return $feature->make_title() if $feature->can( 'make_title' );

  ## TODO: REMOVE?
  return unless( defined $section );

  ## TODO: REMOVE?
  local $^W = 0;  # tired of uninitialized variable warnings

  my ($title,$key) = ('','');
  $key         = $self->setting($section,'key') || $section;
  $key         =~ s/s$//;
  my $link     = $self->code_setting($section,'title')       || $self->code_setting('title');
  $link or last TRY;
  if (ref($link) eq 'CODE') {
    $title       = eval {$link->($feature,$panel)};
    warn $@ if $@;
  }
  $title     ||= $self->link_pattern($link,$feature);
  return $title if $title;

  # otherwise, try it ourselves
  $title ||= eval {
    if ($feature->can('target') &&
        (my $target = $feature->target)) {
      unless( ref( $target ) ) {
        # The target of a DAS feature is a list in list context and a
        # string in scalar context.  See Bio::Das::Feature.
        my @target_list = $feature->target;
        join (' ',
              "$key:",
              $feature->seq_id.':'.
              $feature->start."..".$feature->end,
              $target_list[0].':'.
              $target_list[1]."..".$target_list[2]);
      } else {
        join (' ',
              "$key:",
              $feature->seq_id.':'.
              $feature->start."..".$feature->end,
              $target.':'.
              $target->start."..".$target->end);
      }
    } else {
      join(' ',
	   "$key:",
	   $feature->can('display_id') ? $feature->display_id : $feature->info,
	   ($feature->can('seq_id') ? $feature->seq_id : $feature->location->seq_id)
	   .":".
	   ($feature->start||'?')."..".($feature->end||'?')
	  );
    }
  };
  warn $@ if $@;

  return $title;
}

sub make_link_target {
  my $self = shift;
  my( $section, $feature, $panel ) = @_;
  my $link_target =
    $self->code_setting( $section, 'link_target' ) ||
    $self->code_setting( 'link_target' );
  if( ref( $link_target ) eq 'CODE' ) {
    $link_target = eval { $link_target->( $feature, $panel ) } ;
    warn $@ if $@;
  }
  return $link_target;
} # make_link_target(..)

=head2

 Replace variables in a string with their values.

  Variable   Value
  --------   -----
  $ref       $feature->seq_id()
  $name      $feature->display_name()
  $class     $feature->class()  || ''
  $type      $feature->method() || $feature->primary_tag()
  $method    $feature->method() || $feature->primary_tag()
  $source    $feature->source() || $feature->primary_tag()
  $start     $feature->start()
  $end       $feature->end()
  $segstart  $panel->start()
  $segend    $panel->end()

=cut

sub link_pattern {
  my $self = shift;
  my ( $pattern, $feature, $panel ) = @_;

  $pattern =~ s/\$(\w+)/
        $1 eq 'ref'       ? $feature->seq_id()
      : $1 eq 'name'      ? $feature->display_name()
      : $1 eq 'class'     ? eval {$feature->class}  || ''
      : $1 eq 'type'      ? eval {$feature->method} || $feature->primary_tag
      : $1 eq 'method'    ? eval {$feature->method} || $feature->primary_tag
      : $1 eq 'source'    ? eval {$feature->source} || $feature->source_tag
      : $1 eq 'start'     ? $feature->start
      : $1 eq 'end'       ? $feature->end
      : $1 eq 'segstart'  ? $panel->start
      : $1 eq 'segend'    ? $panel->end
      : $1
       /exg;
  return $pattern;
} # link_pattern(..)

sub get_ranges {
  my $self        = shift;
  my $zoom_levels = $self->setting( 'zoom levels' ) || DEFAULT_RANGES;
  return split( /\s+/, $zoom_levels );
} # get_ranges(..)

=head1 Rendering methods
=cut

=head2 render_html()

  ($image,$image_map) = $browser->render_html(%args);

Render an image and an image map according to the options in %args.
Returns a two-element list.  The first element is a URL that refers to
the image which can be used as the SRC for an <IMG> tag.  The second
is a complete image map, including the <MAP> and </MAP> sections.

The arguments are a series of tag=>value pairs, where tags are:

  Argument            Value

  range               a Bio::RangeI object specifying the range to render (required)

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

sub render_html {
  my $self = shift;
  my %args = @_;

  my $range            = $args{ 'range' };
  my $do_map           = $args{ 'do_map' };
  my $do_centering_map = $args{ 'do_centering_map' };

  return unless $range;

  my( $image, $map, $panel ) = $self->image_and_map( %args );

  # Save the image to somewhere accessible and return the location.
  my $url = $self->generate_image( $image );

  # Generate the HTML image tag.
  my( $width, $height ) = $image->getBounds();
  my $img = img( {
    '-src'    => $url,
    '-align'  => 'middle',
    '-usemap' => '#hmap',
    '-width'  => $width,
    '-height' => $height,
    '-border' => 0,
    '-name'   => 'detailedView',
    '-alt'    => 'detailed view'
  });
  my $img_map = '';
  if( $do_map ) {
    $img_map = $self->make_map( $map, $do_centering_map, $panel );
  }
  return wantarray ? ( $img, $img_map ) : join( "<br>", ( $img, $img_map ) );
} # render_html(..)

# Generate the image and the box list, and return as a two-element list.
# arguments: a key=>value list
#    'range'       A Bio::SeqFeature::RangeI object. [required]
#    'options'       An hashref of options, where 0=auto, 1=force no bump, 2=force bump, 3=force label
#                       4=force fast bump, 5=force fast bump and label
#    'limit'         Place a limit on the number of features of each type to show.
#    'tracks'        List of named tracks, in the order in which they are to be shown
#    'label_scale'   If true, prints chromosome name next to scale
#    'title'         A title for the image
#    'noscale'       Suppress scale entirely
## TODO: Make changes to calls to image_and_map that reflect the change from segment to range.
sub image_and_map {
  my $self    = shift;
  my %args  = @_;

  my $range = $args{ 'range' } ||
    $self->throw( 'image_and_map(..) requires a range argument.' );

  my $conf           = $self->config;

  # Most args have defaults, either in the conf file or a magic #.
  ## TODO: Replace magic #s with CONSTANTS
  my $max_labels     = $args{ 'label density' } ||
                       $conf->get( 'label density' )  || 10; # 10 is a magic #
  my $max_bump       = $args{ 'bump density' } ||
                       $conf->get( 'bump density' )   || 50;
  my $empty_tracks   = $args{ 'empty_tracks' } =
                       $conf->get( 'empty_tracks' )   || DEFAULT_EMPTYTRACKS;
  my $key_bgcolor    = $args{ 'key bgcolor' } ||
                       $conf->get( 'key bgcolor' )    || 'moccasin';
  my $detail_bgcolor = $args{ 'detail bgcolor' } ||
                       $conf->get( 'detail bgcolor' ) || 'white';
  my $units          = $args{ 'units' } ||
                       $conf->get( 'units' )          || '';
  my $unit_divider   = $args{ 'unit_divider' } ||
                       $conf->get( 'unit_divider' )   || 1;
  my $default_track_glyph = $args{ 'track glyph' } ||
                            $conf->get( 'track glyph' ) || 'generic';

  my $tracks         = $args{ 'tracks' }              || $self->labels();
  my $options        = $args{ 'options' }             || {};
  my $limit          = $args{ 'limit' }               || {};
  my $lang           = $args{ 'lang' };
  my $keystyle       = $args{ 'keystyle' } ||
                       $conf->get( 'keystyle' )       || DEFAULT_KEYSTYLE;
  my $title          = $args{ 'title' };
  my $suppress_scale = $args{ 'noscale' };
  my $label_scale    = $args{ 'label_scale' };

  my $width          = $self->width;

  my $length         = $range->length;

  # Create the tracks that we will need
  my @argv = ( -range      => $range,
	       -width        => $width,
	       -key_color    => $key_bgcolor,
	       -bgcolor      => $detail_bgcolor,
	       -grid         => 1,
	       -key_style    => $keystyle,
	       -empty_tracks => $empty_tracks,
	       -pad_top      => $title ? gdMediumBoldFont->height : 0
	     );
  my $panel = Bio::Graphics::Panel->new( @argv );
  unless( $suppress_scale ) {
    $panel->add_track(
      $range,
      'arrow',
      -double       => 1,
      -tick         => 2,
      -label        => ( $label_scale ? $range->seq_id() : 0 ),
      -units        => $units,
      -unit_divider => $unit_divider
    );
  }

  # This is for efficiency, sort of a warning to our feature
  # provider(s) that we're going to be interested in looking at some
  # features soon, of the given types (restricted to the range of
  # the range).
  my $all_features_collection;
  if( @$tracks ) {
    ## TODO: Make Config's get_collection take the -sections argument.
    $all_features_collection =
      $config->get_collection( '-sections' => $tracks, '-range' => $range );
  }

  my ( $track, $glyph, $track_glyph, $collection, %tracks,
       $feature_count, $label, $bump, $description,
       $do_bump, $do_label, $do_description );
  foreach my $section ( @$tracks ) {
    # if the glyph is the magic "dna" glyph (for backward
    # compatibility), or if the section is marked as being a "global
    # feature", then we apply the glyph to the entire range
    $glyph = $conf->get( $section, 'glyph' );
    $track_glyph =
      $conf->get( $section, 'track glyph' ) ||
        ( ( defined( $glyph ) && ( $glyph eq 'dna' ) ) ?
          'dna' :
          $default_track_glyph );
    if(
       ( defined( $glyph ) && ( $glyph eq 'dna' ) ) ||
       $conf->get( $section, 'global feature' )
      ) {

      ## TODO: What is really going on here?
      $track = $panel->add_track(
        ( ( $track_glyph eq 'dna' ) ? $range : undef ),
        -width   => $width,
        -track_glyph => $track_glyph,
        $conf->i18n_style( $section, $lang )
      );
      unless( ( defined $glyph ) && ( $glyph eq 'dna' ) ) {
        $tracks{ $section } = $track;
      }
    } else {
      $track = $panel->add_track(
        $track_glyph,
	$conf->i18n_style( $section, $lang, $length )
      );
      $tracks{ $section } = $track;
    }
    $collection =
      $all_features_collection->get_collection(
        $conf->label2type( $section, $length )
      );
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
        $label       = $conf->get( 'label' ) || 1;
        $description = $conf->get( 'description' ) || 1;
      } elsif( $options->{ $section } == 4 ) { # TODO: Document
        $bump        = 2;
        $label       = 0;
        $description = 0;
      } elsif( $options->{ $section } == 5 ) { # TODO: Document
        $bump        = 2;
        $label       = $conf->get( 'label' ) || 1;
        $description = $conf->get( 'description' ) || 1;
      } else {                                 # Who knows?  Just force no bump
        $bump        = 0;
        $label       = 0;
        $description = 0;
      }
    } else {                                   # 'auto'
      $bump = $conf->get_and_eval( $section, 'bump' );
      if( $bump || !defined( $bump ) ) {
        $feature_count = $collection->feature_count();
        if( $limit->{ $section } && $feature_count > $limit->{ $section } ) {
          $feature_count = $limit->{ $section };
        }
        $bump = ( $feature_count <= $max_bump );
      }
      $label = $conf->get_and_eval( $section, 'label' );
      if( $label || !defined( $label ) ) {
        unless( defined $feature_count ) {
          $feature_count = $collection->feature_count();
          if( $limit->{ $section } && $feature_count > $limit->{ $section } ) {
            $feature_count = $limit->{ $section };
          }
        }
        $label = ( $feature_count <= $max_labels );
      }
      $description = $conf->get_and_eval( $section, 'description' );
      if( $description ) {
        unless( defined $feature_count ) {
          $feature_count = $collection->feature_count();
          if( $limit->{ $section } && $feature_count > $limit->{ $section } ) {
            $feature_count = $limit->{ $section };
          }
        }
        $description = ( $feature_count <= $max_labels );
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
    if( $limit->{ $section } > 0 ) {
      $tracks{ $section }->configure( '-bump_limit' => $limit->{ $section } );
    } 
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
  #   $track->add_group($_);  ## TODO: What is add_group?
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

  return $gd unless wantarray;
  my $boxes = $panel->boxes();
  return ( $gd, $boxes, $panel );
} # image_and_map(..)

=head2 generate_image

  ($url,$path) = $browser->generate_image($gd)

Given a GD::Image object, this method calls its png() or gif() methods
(depending on GD version), stores the output into the temporary
directory given by the "tmpimages" option in the configuration file,
and returns a two element list consisting of the URL to the image and
the physical path of the image.

=cut

sub generate_image {
  my $self  = shift;
  my $image = shift;

  my $extension = $image->can( 'png' ) ? 'png' : 'gif';
  my $data      = $image->can( 'png' ) ? $image->png() : $image->gif();
  my $signature = md5_hex( $data );

  # untaint signature for use in open
  $signature =~ /^([0-9A-Fa-f]+)$/g or return;
  $signature = $1;

  my ( $uri, $path ) = $self->_make_tmp_uri( $self->source() . '/img' );
  my $url       = sprintf( "%s/%s.%s", $uri, $signature, $extension );
  my $imagefile = sprintf( "%s/%s.%s", $path, $signature, $extension );

  # Write out the $data to $imagefile.
  open( F, ">$imagefile" ) ||
    die( "Can't open image file $imagefile for writing: $!\n" );
  binmode( F );
  print F $data;
  close F;

  return $url;
} # generate_image(..)

# For making a uri for the image in generate_image(..).
# ( $tmp_uri, $full_dirname ) = $browser->_make_tmp_uri( [$rel_dirname] );
sub _make_tmp_uri {
  my $self = shift;
  my $path = shift || '';

  my $tmpuri = $self->setting( 'tmpimages' ) or
    die "no tmpimages option defined, can't generate a picture";
  $tmpuri .= "/$path" if $path;
  my $tmpdir;
  if( $ENV{ MOD_PERL } ) {
    my $r          = Apache->request;
    my $subr       = $r->lookup_uri( $tmpuri );
    $tmpdir        = $subr->filename;
    my $path_info  = $subr->path_info;
    $tmpdir       .= $path_info if $path_info;
  } else {
    $tmpdir = "$ENV{DOCUMENT_ROOT}/$tmpuri";
  }
  # we need to untaint tmpdir before calling mkpath()
  return unless $tmpdir =~ /^(.+)$/;
  $path = $1;

  mkpath( $path, 0, 0777 ) unless -d $path;
  return ( $tmpuri, $path );
} # _make_tmp_uri(..)

sub make_map {
  my $self = shift;
  my ( $boxes, $do_centering_map, $panel ) = @_;
  my $map = qq(<map name="hmap" id="hmap">\n);

  # $box_ref is [ $feature, $x1, $y1, $x2, $y2 ]
  my ( $feature, $x1, $y1, $x2, $y2 );
  foreach my $box_ref ( @$boxes ) {
    ( $feature, $x1, $y1, $x2, $y2 ) = @$box_ref;
    next unless $feature->can( 'primary_tag' );
    ## TODO: What is so special about DasSegment?  This seems to
    ## indicate that the feature is a ruler/scale.
    if( $feature->primary_tag eq 'DasSegment' ) {
      $map .= $self->make_centering_map( $box_ref ) if $do_centering_map;
      next;
    }
    my $href   = $self->make_link( $section, $feature, $panel ) or next;
    my $alt    = $self->make_title( $section, $feature, $panel );
    my $target = $self->make_link_target( $section, $feature, $panel );
    my $t      = defined( $target ) ? qq(target="$target") : '';
    $map .= qq(<area shape="rect" coords="$x1,$y1,$x2,$y2" href="$href" title="$alt" alt="$alt" $t/>\n);
  }
  $map .= "</map>\n";
  return $map;
} # make_map

# this creates image map for rulers and scales, where clicking on the scale
# should center the image on the scale.
sub make_centering_map {
  my $self = shift;
  my $ruler_box_ref = shift;
  my ( $ruler, $x1, $y1, $x2, $y2 ) = @$ruler_box_ref;

  return if ( $x2 - $x1 ) == 0;

  my $length = $ruler->length();
  my $offset = $ruler->start();
  my $scale  = ( $length / ( $x2 - $x1 ) );

  # divide into RULER_INTERVAL intervals
  my $portion = ( $x2 - $x1 ) / RULER_INTERVALS;
  my $ref     = $ruler->seq_id();
  my $source  = $self->source();

  # NOTE: We use param() here from CGI to get the 'plugin' value..
  my $plugin  = escape( param( 'plugin' ) || '' );

  my @lines;
  for ( my $i = 0; $i < RULER_INTERVALS; $i++ ) {
    my $interval_x1 = int( ( $portion * $i ) + 0.5 ) );
    my $interval_x2 = int( ( $portion * ( $i + 1 ) ) + 0.5 );
    # put the middle of the sequence range into the middle of the picture
    my $middle =
      $offset + ( ( $scale * ( $interval_x1 + $interval_x2 ) ) / 2 );
    my $start  = int( $middle - ( $length / 2 ) );
    my $stop   = int( $start + $length - 1 );
    my $url    = url( '-relative' => 1, '-path_info' => 1 );
    $url .= "?ref=$ref;start=$start;stop=$stop;source=$source;nav4=1;plugin=$plugin";

    push @lines,
      qq(<area shape="rect" coords="$interval_x1,$y1,$interval_x2,$y2" href="$url" title="recenter" alt="recenter"/>\n);
  }
  return join( '', @lines );
} # make_centering_map(..)

=head2 overview()

  ($gd,$length) = $browser->overview($segment);

This method generates a GD::Image object containing the image data for
the overview panel.  Its argument is a Bio::RangeI object.  It returns
a two element list consisting of the image data and the length of the
segment (in bp).

In the configuration file, any section labeled "[something:overview]"
will be added to the overview panel.

=cut

# generate the overview, if requested, and return it as a GD
sub overview {
  my $self = shift;
  my ( $range ) = @_;

  my $conf    = $self->config();
  ## TODO: Why is class used at all?  Why do we expect the range's
  ## seq_id to have it?
  my $class   = eval { $range->seq_id()->class() };
  my $segment =
    $conf->segment( '-class' => $class, '-name' => $range->seq_id() );

  my $width          = $self->width();
  my @tracks         = $conf->overview_tracks();
  my( $padl, $padr ) = $self->overview_pad( \@tracks );

  ## TODO: Magic #s
  my $bgcolor        = $conf->get( 'overview bgcolor' ) || 'wheat';
  ## TODO: There seems to be some confusion about which units setting to use.
  #my $units         = $conf->get( 'overview units' );
  my $units          = $conf->get( 'units' )            || '';
  my $unit_divider   = $conf->get( 'unit_divider' )     || 1;

  my $panel =
    Bio::Graphics::Panel->new(
      '-segment'    => $segment,
      '-width'      => $width,
      '-bgcolor'    => $bgcolor,
      '-key_style'  => 'left',
      '-pad_left'   => $padl,
      '-pad_right'  => $padr,
      '-pad_bottom' => PAD_OVERVIEW_BOTTOM
    );

  $panel->add_track(
    $segment,
    '-glyph'        => 'arrow',
    '-double'       => 1,
    '-label'        => "Overview of " . $segment->seq_id(),
    '-labelfont'    => gdMediumBoldFont,
    '-tick'         => 2,
    '-units'        => $units,
    '-unit_divider' => $unit_divider
  );

  $self->add_overview_landmarks( $panel, $segment, \@tracks, $padl );

  my $gd = $panel->gd();

  # Paint a red border.
  my $red = $gd->colorClosest( 255, 0, 0 );
  my ( $x1, $x2 ) =
    $panel->map_pt( $range->start(), $range->end() );
  my ( $y1, $y2 ) = ( 0, $panel->height() - 1 );
  if( $x2 >= $panel->right() ) {
    $x2 = $panel->right() - 1;
  }
  $gd->rectangle( $x1, $y1, $x2, $y2, $red );

  return ( $gd, $segment->length() );
} # overview(..)

sub add_overview_landmarks {
  my $self = shift;
  my ( $panel, $segment, $tracks, $pad ) = @_;

  return {} unless @$tracks;

  my $conf = $self->config();
  my $default_track_glyph = $conf->get( 'track glyph' )   || 'generic';
  my $max_label           = $conf->get( 'label density' ) || 10;
  my $max_bump            = $conf->get( 'bump density' )  || 50;

  # This is for efficiency, sort of a warning to our feature
  # provider(s) that we're going to be interested in looking at some
  # features soon, of the given types (restricted to the range of
  # the range).
  my $all_features_collection =
    $config->get_collection(
      '-sections' => $tracks,
      '-range' => $range,
      '-rare' => 1 ## TODO: Document the '-rare' use here
    );

  my ( $collection, %tracks, $track, $feature_count, $bump, $label );
  foreach my $section ( @$tracks ) {
    $tracks{ $overview_track } = $track =
      $panel->add_track(
        '-glyph'   => $default_track_glyph,
        '-height'  => 3,
        '-fgcolor' => 'black',
        '-bgcolor' => 'black',
        $conf->style( $overview_track )
      );
    $collection =
      $all_features_collection->get_collection(
        $conf->label2type( $section, $length )
      );
    $track->set_feature_collection( $collection );

    # Now calculate the bump and label options.  We might need feature
    # counts for this, but we'll defer because it can be expensive and
    # we might not need it.
    undef( $feature_count );
    $bump = $conf->get_and_eval( $section, 'bump' );
    unless( defined $bump ) {
      $feature_count = $collection->feature_count();
      $bump = ( $feature_count <= $max_bump );
    }
    $label = $conf->get_and_eval( $section, 'label' );
    unless( defined $label ) {
      unless( defined $feature_count ) {
        $feature_count = $collection->feature_count();
      }
      $label = ( $feature_count <= $max_label );
    }
    $track->configure( '-bump' => $bump, '-label' => $label );
  } # End foreach $section in @$tracks, build the corresponding overview track.
  return \%tracks;
} # add_overview_landmarks(..)

=head2 hits_on_overview()

  $hashref = $browser->hits_on_overview($db,@hits);

This method is used to render a series of genomic positions ("hits")
into a graphical summary of where they hit on the genome in a
segment-by-segment (e.g. chromosome) manner.

The first argument is a Bio::DB::GFF (or Bio::DasI) database.  The
second and subsequent arguments are one of:

  1) a set of array refs in the form [ref,start,stop,name], where
     name is optional.

  2) a Bio::DB::GFF::Feature object

  3) a Bio::SeqFeatureI object.

The returned HTML is stored in a hashref, where the keys are the
reference sequence names and the values are HTML to be emitted.

=cut

# Return an HTML showing where multiple hits fall on the genome.
# Can either provide a list of objects that provide the ref() method call, or
# a list of arrayrefs in the form [ref,start,stop,[name]]
sub hits_on_overview {
  my $self = shift;
  my ($db,$hits) = @_;

  my %html; # results are a hashref sorted by chromosome

  my $conf  = $self->config;
  my $width = $self->width;
  my $units = $self->setting('overview units');
  my $max_label  = $conf->setting(general=>'label density') || 10;
  my $max_bump   = $conf->setting(general=>'bump density') || 50;
  my $class      = $hits->[0]->can('factory') ? $hits->[0]->factory->refclass : 'Sequence';
  my ($padl,$padr)  = $self->overview_pad([$self->config()->overview_tracks],'Matches');

  # sort hits out by reference
  my (%refs);
  for my $hit (@$hits) {
    if (ref($hit) eq 'ARRAY') {
      my ($ref,$start,$stop,$name) = @$hit;
      push @{$refs{$ref}},Bio::Graphics::Feature->new(-start=>$start,
						      -end=>$stop,
						      -name=>$name||'');
    } elsif (UNIVERSAL::can($hit,'ref')) {
      my $ref  = $hit->seq_id;
      my $name = $hit->can('seq_name') ? $hit->seq_name : $hit->name;
      my($start,$end) = ($hit->start,$hit->end);
      $name =~ s/\:\d+,\d+$//;  # remove coordinates if they're there
      $name = substr($name,0,7).'...' if length $name > 10;
      push @{$refs{$ref}},Bio::Graphics::Feature->new(-start=>$start,
						      -end=>$end,
						      -name=>$name);
    } elsif (UNIVERSAL::can($hit,'location')) {
      my $location = $hit->location;
      my ($ref,$start,$stop,$name) = ($location->seq_id,$location->start,
				      $location->end,$location->primary_tag);
      push @{$refs{$ref}},Bio::Graphics::Feature->new(-start=>$start,
						      -end=>$stop,
						      -name=>$name||'');
    }
  }

  for my $ref (sort keys %refs) {
    my $segment = ($db->segment(-class=>$class,-name=>$ref))[0];
    my $panel = Bio::Graphics::Panel->new(-segment => $segment,
					  -width   => $width,
					  -bgcolor => $self->setting('overview bgcolor') || 'wheat',
					  -pad_left  => $padl,
					  -pad_right => $padr,
					  -pad_bottom => PAD_OVERVIEW_BOTTOM,
					  -key_style => 'left',
					 );

    # add the arrow
    $panel->add_track($segment,
		      -glyph     => 'arrow',
		      -double    => 1,
		      -label     => 0, #"Overview of ".$segment->seq_id,
		      -labelfont => gdMediumBoldFont,
		      -tick      => 2,
		      $units ? (-units => $units) : (),
		     );

    # add the landmarks
    $self->add_overview_landmarks($panel,$segment,[$self->config()->overview_tracks]);

    # add the hits
    $panel->add_track($refs{$ref},
		      -glyph     => 'diamond',
		      -height    => 8,
		      -fgcolor   => 'red',
		      -bgcolor   => 'red',
		      -fallback_to_rectangle => 1,
		      -key       => 'Matches',
		      -bump      => @{$refs{$ref}} <= $max_bump,
		      -label     => @{$refs{$ref}} <= $max_bump,  # deliberate
		     );

    my $gd    = $panel->gd;
    my $boxes = $panel->boxes;
    $html{$ref} = $self->_hits_to_html($ref,$gd,$boxes);
  }
  return \%html;
}

# utility called by hits_on_overview
sub _hits_to_html {
  my $self = shift;
  my ($ref,$gd,$boxes) = @_;
  my $source   = $self->source;
  my $self_url = url(-relative=>1);
  $self_url   .= "?source=$source";

  my $signature = md5_hex(rand().rand()); # just a big random number
  my ($width,$height) = $gd->getBounds;
  my $url       = $self->generate_image($gd,$signature);
  my $img       = img({-src=>$url,
		       -align=>'middle',
		       -usemap=>"#$ref",
		       -width => $width,
		       -height => $height,
		       -border=>0});
  my $html = "\n";
  $html   .= $img;
  $html   .= qq(<br /><map name="$ref" alt="imagemap" />\n);

  # use the scale as a centering mechanism
  my $ruler   = shift @$boxes;
  return unless $ruler;  # don't know why....
  my $length  = $ruler->length/RULER_INTERVALS;
  $width   = ($x2-$x1)/RULER_INTERVALS;
  for my $i (0..RULER_INTERVALS-1) {
    my $x = $x1 + $i * $width;
    my $y = $x + $width;
    my $start = int($length * $i);
    my $stop  = int($start + $length);
    my $href      = $self_url . ";ref=$ref;start=$start;stop=$stop";
    $html .= qq(<area shape="rect" coords="$x,$y1,$y,$y2" href="$href" alt="ruler" />\n);
  }

  foreach (@$boxes){
    my ($start,$stop) = ($_->[0]->start,$_->[0]->end);
    my $href      = $self_url . ";ref=$ref;start=$start;stop=$stop";
    $html .= qq(<area shape="rect" coords="$_->[1],$_->[2],$_->[3],$_->[4]" href="$href" alt="ruler" />\n);
  }
  $html .= "</map>\n";
  $html;
}

# return ( max, min ) pixels required to pad the overview panel for
# including the given tracks' key strings.  Tracks are given as an
# array ref.  Other strings may be given as extra args.
sub overview_pad {
  my $self   = shift;
  my $tracks = shift;
  my @more_strings = @_;

  my $conf = $self->config();
  $tracks ||= [ $conf->overview_tracks() ];
  my $max = 0;
  foreach my $section ( @$tracks ) {
    my $key = $conf->get( $section, 'key' );
    next unless defined $key;
    $max = length $key if length $key > $max;
  }
  foreach my $str ( @more_strings ) {  #extra
    $max = length $str if length $str > $max;
  }
  if( $max ) {
    return ( ( $max * gdMediumBoldFont->width() ) + 3, MIN_OVERVIEW_PAD );
  } else {
    return ( MIN_OVERVIEW_PAD, MIN_OVERVIEW_PAD );
  }
} # overview_pad(..)

=head1 Utility methods
=cut

sub merge {
  my $self = shift;
  my ($db,$features,$max_range) = @_;
  $max_range ||= 100_000;

  my (%segs,@merged_segs);
  push @{$segs{$_->seq_id}},$_ foreach @$features;
  foreach (keys %segs) {
    push @merged_segs,_low_merge($db,$segs{$_},$max_range);
  }
  return @merged_segs;
}

sub _low_merge {
  my ($db,$features,$max_range) = @_;

  my ($previous_start,$previous_stop,$statistical_cutoff,@spans);

  my @features = sort {$a->low<=>$b->low} @$features;

  # run through the segments, and find the mean and stdev gap length
  # need at least 10 features before this becomes reliable
  if (@features >= 10) {
    my ($total,$gap_length,@gaps);
    for (my $i=0; $i<@$features-1; $i++) {
      my $gap = $features[$i+1]->low - $features[$i]->high;
      $total++;
      $gap_length += $gap;
      push @gaps,$gap;
    }
    my $mean = $gap_length/$total;
    my $variance;
    $variance += ($_-$mean)**2 foreach @gaps;
    my $stdev = sqrt($variance/$total);
    $statistical_cutoff = $stdev * 2;
  } else {
    $statistical_cutoff = $max_range;
  }

  my $ref = $features[0]->seq_id;

  for my $f (@features) {
    my $start = $f->low;
    my $stop  = $f->high;

    if (defined($previous_stop) &&
	( $start-$previous_stop >= $max_range ||
	  $previous_stop-$previous_start >= $max_range ||
	  $start-$previous_stop >= $statistical_cutoff)) {
      push @spans,$db->segment($ref,$previous_start,$previous_stop);
      $previous_start = $start;
      $previous_stop  = $stop;
    }

    else {
      $previous_start = $start unless defined $previous_start;
      $previous_stop  = $stop;
    }

  }
  my $class = eval { $features[0]->factory->refclass };
  my @args  = (-name=>$ref,-start=>$previous_start,-end=>$previous_stop);
  push @args,(-class=>$class) if defined $class;
  push @spans,$db ? $db->segment(@args)
                  : Bio::Graphics::Feature->new(-start=>$previous_start,-end=>$previous_stop,-ref=>$ref);
  return @spans;
}

# fetch a list of Segment objects given a name or range
# (this used to be in gbrowse executable itself)
sub name2segments {
  my $self = shift;
  my ($name,$db,$toomany) = @_;

  ## TODO: REMOVE
  print STDERR "\$db is $db, a ", ref( $db ), "\n";

  $toomany ||= TOO_MANY_SEGMENTS;
  my $max_segment = $self->setting('max_segment') || MAX_SEGMENT;

  my (@segments,$class,$start,$stop);
  if ($name =~ /([\w._-]+):(-?[\d.]+),(-?[\d.]+)$/ or
      $name =~ /([\w._-]+):(-?[\d,.]+)(?:-|\.\.)(-?[\d,.]+)$/) {
    $name  = $1;
    $start = $2;
    $stop  = $3;
    $start =~ s/,//g; # get rid of commas
    $stop  =~ s/,//g;
  }

  elsif ($name =~ /^(\w+):(.+)$/) {
    $class = $1;
    $name  = $2;
  }

  my $divisor = $self->setting(general=>'unit_divider') || 1;
  $start *= $divisor if defined $start;
  $stop  *= $divisor if defined $stop;

  my @argv = (-name  => $name);
  push @argv,(-class => $class) if defined $class;
  push @argv,(-start => $start) if defined $start;
  push @argv,(-end   => $stop)  if defined $stop;
  @segments = $name =~ /[*?]/ ? $db->get_feature_by_name(@argv) 
                              : $db->segment(@argv);

  ## TODO: REMOVE
  if( @segments ) {
    print STDERR "( 1 ) Got segments ( ", join( ", ", @segments ), " ).  \$name is $name.\n";
  }

  # Here starts the heuristic part.  Try various abbreviations that
  # people tend to use for chromosomal addressing.
  if (!@segments && $name =~ /^([\dIVXA-F]+)$/) {
    my $id = $1;
    foreach (qw(CHROMOSOME_ Chr chr)) {
      my $n = "${_}${id}";
      my @argv = (-name  => $n);
      push @argv,(-class => $class) if defined $class;
      push @argv,(-start => $start) if defined $start;
      push @argv,(-end   => $stop)  if defined $stop;
      @segments = $name =~ /\*/ ? $db->get_feature_by_name(@argv) 
                                : $db->segment(@argv);
      ## TODO: REMOVE
      if( @segments ) {
        print STDERR "( 2 ) Got segments ( ", join( ", ", @segments ), " ).  \$name is $name.\n";
      }
      last if @segments;
    }
  }

  # try to remove the chr CHROMOSOME_I
  if (!@segments && $name =~ /^(chromosome_?|chr)/i) {
    (my $chr = $name) =~ s/^(chromosome_?|chr)//i;
    @segments = $db->segment($chr);
  }

  # try the wildcard  version, but only if the name is of significant length
  if (!@segments && length $name > 3) {
    @argv = (-name => "$name*");
    push @argv,(-start => $start) if defined $start;
    push @argv,(-end   => $stop)  if defined $stop;
    @segments = $name =~ /\*/ ? $db->get_feature_by_name(@argv)
                              : $db->segment(@argv);
    ## TODO: REMOVE
    if( @segments ) {
      print STDERR "( 3 ) Got segments ( ", join( ", ", @segments ), " ).  \$name is $name.\n";
    }
  }

  # try any "automatic" classes that have been defined in the config file
  if (!@segments && !$class &&
      (my @automatic = split /\s+/,$self->setting('automatic classes') || '')) {
    my @names = length($name) > 3 && 
      $name !~ /\*/ ? ($name,"$name*") : $name;  # possibly add a wildcard
  NAME:
      foreach $class (@automatic) {
	for my $n (@names) {
	  @argv = (-name=>$n);
	  push @argv,(-start => $start) if defined $start;
	  push @argv,(-end   => $stop)  if defined $stop;
	  # we are deliberately doing something different in the case that the user
	  # typed in a wildcard vs an automatic wildcard being added
	  @segments = $name =~ /\*/ ? $db->get_feature_by_name(-class=>$class,@argv)
	                            : $db->segment(-class=>$class,@argv);
          ## TODO: REMOVE
          if( @segments ) {
            print STDERR "( 4 ) Got segments ( ", join( ", ", @segments ), " ).  \$name is $name.\n";
          }
	  last NAME if @segments;
	}
      }
  }

  # user wanted multiple locations, so user gets them
  return @segments if $name =~ /\*/;

  # Otherwise we try to merge segments that are adjacent if we can!

  # This tricky bit is called when we retrieve multiple segments or when
  # there is an unusually large feature to display.  In this case, we attempt
  # to split the feature into its components and offer the user different
  # portions to look at, invoking merge() to select the regions.
  my $max_length = 0;
  foreach (@segments) {
    $max_length = $_->length if $_->length > $max_length;
  }
  if (@segments > 1 || $max_length > $max_segment) {
    my @s     = $db->fetch_feature_by_name(-class => $segments[0]->class,
					   -name  => $segments[0]->seq_id,
					   -automerge=>0);
    @segments     = $self->merge($db,\@s,($self->get_ranges())[-1])
      if @s > 1 && @s < TOO_MANY_SEGMENTS;
  }
  @segments;
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
