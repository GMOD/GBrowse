package Bio::Graphics::Browser;
# $Id: Browser.pm,v 1.167.4.34.2.32.2.126 2009-09-03 17:08:10 lstein Exp $

# GLOBALS for the Browser
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
  my $track_label    = $b->feature2label;

  # warning: commas() and DEFAULT_OVERVIEW_BGCOLOR is exported
  my $big_number_with_commas = commas($big_number_without_commas);

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
use Carp qw(carp croak cluck);
use CGI qw(img param escape unescape url div span image_button);
use CGI::Toggle 'toggle_section';
use Digest::MD5 'md5_hex';
use File::Path 'mkpath';
use IO::File;
use Bio::Graphics::Browser::I18n;
use Bio::Graphics::Browser::Util qw(modperl_request is_safari shellwords);

require Exporter;

use vars '$VERSION','@ISA','@EXPORT';
$VERSION = '1.17';

@ISA    = 'Exporter';
@EXPORT = ('commas','DEFAULT_OVERVIEW_BGCOLOR');

use constant DEFAULT_WIDTH => 800;
use constant DEFAULT_DB_ADAPTOR  => 'Bio::DB::GFF';
use constant DEFAULT_KEYSTYLE    => 'bottom';
use constant DEFAULT_EMPTYTRACKS => 'key';
use constant RULER_INTERVALS     => 20;  # fineness of the centering map on the ruler
use constant TOO_MANY_SEGMENTS   => 5_000;
use constant MAX_SEGMENT         => 1_000_000;
use constant DEFAULT_SEGMENT     => 100_000;
use constant DEFAULT_RANGES      => q(100 500 1000 5000 10000 25000 100000 200000 400000);
use constant MIN_OVERVIEW_PAD    => 25;
use constant PAD_OVERVIEW_BOTTOM => 5;
use constant PAD_DETAIL_SIDES    => 25;
use constant DEFAULT_OVERVIEW_BGCOLOR => 'wheat';

# amount of time to remember persistent settings
use constant REMEMBER_SOURCE_TIME   => '+12M';   # 12 months
use constant REMEMBER_SETTINGS_TIME => '+1M';    # 1 month

use constant DEBUG => 0;

if( $ENV{MOD_PERL} &&
    exists $ENV{MOD_PERL_API_VERSION} &&
    $ENV{MOD_PERL_API_VERSION} >= 2) {
    require Apache2::SubRequest;
    require Apache2::RequestUtil;
    require Apache2::ServerUtil;
}

=head2 new()

  my $browser = Bio::Graphics::Browser->new();

Create a new Bio::Graphics::Browser object.  The object is initially
empty.  This is done automatically by gbrowse.

=cut

sub new {
  my $class    = shift;
  my $self = bless { },ref($class) || $class;
  $self;
}


=head2 url_label()

    my $url_label = $browser->url_label($yucky_url);

Creates a label.alias for URL strings starting with 'http' or 'ftp'.
The last word (following a '/') in the url is used for the label.
Returns a string "url:label".

=cut

sub url_label {
  my ($self,$label) = @_;
  my $key;
  if ($label =~ /^http|^ftp/) {
    my $l = $label;
    $l =~ s!^\W+//!!;
    my (undef,$type) = $l =~ /\S+t(ype)?=([^;\&]+)/;
    $l =~ s/\?.+//;
    ($key) = grep /$_/, reverse split('/',$l);
    $key = "url:$key" if $key;
    $key .= ":$type"  if $type; 
  }
  return $key || $label;
}



=head2 read_configuration()

  my $success = $browser->read_configuration('/path/to/gbrowse.conf');

Parse the files in the gbrowse.conf configuration directory.  This is
done automatically by gbrowse.  Returns a true status code if
successful.

=cut

sub read_configuration {
  my $self        = shift;
  my $conf_dir    = shift;
  my $suffix      = shift || 'conf';

  $self->{conf} ||= {};

  croak("$conf_dir: not a directory") unless -d $conf_dir;
  opendir(D,$conf_dir) or croak "Couldn't open $conf_dir: $!";
  my @conf_files = map { "$conf_dir/$_" } grep {/\.$suffix$/} grep {!/^\.|^#|log4perl/} readdir(D);
  close D;

  # try to work around a bug in Apache/mod_perl which appears when
  # running under linux/glibc 2.2.1
  unless (@conf_files) {
    @conf_files = glob("$conf_dir/*.$suffix");
  }

  # get modification times
  my %mtimes     = map { $_ => (stat($_))[9] } @conf_files;

  for my $file (@conf_files) {
    my $basename = basename($file,".$suffix");
    next if $basename eq 'GBrowse';  # global settings -- used in main branch
    $basename =~ s/^\d+\.//;
    next if defined($self->{conf}{$basename}{mtime})
      && ($self->{conf}{$basename}{mtime} >= $mtimes{$file});
    my $config = Bio::Graphics::BrowserConfig->new(-file => $file,
						   -safe => 1) or next;
    $self->{conf}{$basename}{data}  = $config;
    $self->{conf}{$basename}{mtime} = $mtimes{$file};
    $self->{conf}{$basename}{path}  = $file;
  }

 my $default_source;
  for my $basename (sort keys %{$self->{conf}}) {
    my $config = $self->{conf}{$basename}{data};
    $default_source  ||= $basename if $config->authorized('general');
  }


  $self->{source} = $default_source;
  $self->{width}  = DEFAULT_WIDTH;
  $self->{dir}    = $conf_dir;
  1;
}

=head2 $conf_dir = dir()

Returns the directory path that this config is attached to.

=cut

sub dir {
  my $self = shift;
  my $d    = $self->{dir};
  $self->{dir} = shift if @_;
  $d;
}

=head2 sources()

  @sources = $browser->sources;

Returns the list of symbolic names for sources.  The symbolic names
are derived from the configuration file name by:

  1) stripping off the .conf extension.
  2) removing the pattern "^\d+\."

This means that the configuration file "03.fly.conf" will have the
symbolic name "fly".

=cut

sub sources {
  my $self = shift;
  my $conf        = $self->{conf} or return;
  my @sources = keys %$conf;

  # don't let unauthorized individuals see the source at all
  my @authorized = grep {exists $conf->{$_}{data} && $conf->{$_}{data}->authorized('general')} @sources;

  # alternative: sort by the config file name
  # return sort {$conf->{$a}{path} cmp $conf->{$b}{path}} @authorized;

  # alternative: sort by description
  return sort {lc $self->description($a) cmp lc $self->description($b)} @authorized;

  # alternative: sort by base name
  # return sort {$a cmp $b} @authorized;
}

=head2 source()

  $source = $browser->source;
  $source = $browser->source($new_source);

Sets or gets the current source.  The default source will the first
one found in the gbrowse.conf directory when sorted alphabetically.

If you attempt to set an invalid source, the module will issue a
warning and will return undef.

=cut

# get/set current source
sub source {
  my $self = shift;
  my $d    = $self->{source};
  if (@_) {
    my $source = shift;
    unless ($self->{conf}{$source}) {
      carp("invalid source: $source");
      return;
    }
    unless ($self->{conf}{$source}{data}->authorized('general')) {
      carp ("Unauthorized source: $source");
      return;
    }
    $self->{source} = $source;
  }
  $d;
}

=head2 setting()

  $value = $browser->setting(general => 'stylesheet');
  $value = $browser->setting(gene => 'fgcolor');
  $value = $browser->setting('stylesheet');

The setting() method returns the value of one of the current source
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
  my $self = shift;
  my @args = @_;
  if (@args == 1) {
    unshift @args,'general';
  } else {
    $args[0] = 'general'
      if !ref $args[0]
      && 
      $args[0] ne 'general' 
      && lc($args[0]) eq 'general';  # buglet
  }
  my $config = $self->config or return;
  $config->setting(@args);
}

# to return the list of configuration options
sub _setting {
    shift->config->_setting(@_);
}

=head2 fallback_setting()

  $value = $browser->setting(gene => 'fgcolor');

Tries to find the setting for designated label (e.g. "gene") first. If
this fails, looks in [TRACK DEFAULTS]. If this fails, looks in [GENERAL].

=cut

sub fallback_setting {
  my $self = shift;
  my ($label,$option) = @_;
  for my $key ($label,'TRACK DEFAULTS','GENERAL') {
    my $value = $self->setting($key,$option);
    return $value if defined $value;
  }
  return;
}

=head2 plugin_setting()

   $value = = $browser->plugin_setting("option_name");

When called in the context of a plugin, returns the setting for the
requested option.  The option must be placed in a [PluginName:plugin]
configuration file section:

  [MyPlugin:plugin]
  foo = bar

Now within the MyPlugin.pm plugin, you may call
$browser->plugin_setting('foo') to return value "bar".

=cut

sub plugin_setting {
  my $self           = shift;
  my $caller_package = caller();
  my ($last_name)    = $caller_package =~ /(\w+)$/;
  my $option_name    = "${last_name}:plugin";
  $self->setting($option_name => @_);
}

=head2 db_settings()

  @args = $browser->db_settings;

Returns the appropriate arguments for connecting to Bio::DB::GFF.  It
can be used this way:

  $db = Bio::DB::GFF->new($browser->dbgff_settings);

=cut

# get database adaptor name and arguments
sub db_settings {
  my $self = shift;

  my $adaptor = $self->setting('db_adaptor') || DEFAULT_DB_ADAPTOR;
  eval "require $adaptor; 1" or die $@;

  my $args    = $self->config->setting(general => 'db_args');
  my @argv = ref $args eq 'CODE'
        ? $args->()
	: Bio::Graphics::Browser::Util::shellwords($args||'');

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

  if (defined (my $a = $self->setting('aggregators'))) {
    my @aggregators = Bio::Graphics::Browser::Util::shellwords($a||'');
    push @argv,(-aggregator => \@aggregators);
  }

  ($adaptor,@argv);
}

=head2 gbrowse_root()

  $root = $browser->gbrowse_root()

Return the setting of "gbrowse root"

=cut

sub gbrowse_root {
  my $self = shift;
  my $root = $self->setting('general' => 'gbrowse root') || '/gbrowse';
  $root    = "/$root" unless $root =~ /^\//;
  $root;
}

=head2 relative_path()

  $relative_path = $browser->relative_path('gbrowse.css');

Add the setting of "gbrowse root" to the indicated path, if
relative. Otherwise pass through unchanged.

=cut

sub relative_path {
  my $self = shift;
  my $path = shift;
  return $path if $path =~ /^\//;             # already absolute
  return $path if $path =~ /^(?:http|ftp)+:/; # a URL
  my $root = $self->gbrowse_root;
  return "$root/$path";
}

=head2 relative_path_setting()

  $relative_path = $browser->relative_path_setting('stylesheet');

Like relative_path(), but works on a named setting rather than an
actual path or directory.

=cut

sub relative_path_setting {
  my $self    = shift;
  my $setting = shift;
  my $path    = $self->setting('general' => $setting);
  return unless $path;
  return $self->relative_path($path);
}

=head2 version()

  $version = $browser->version

This is a shortcut method that returns the value of the "version"
option in the general section.  The value returned is the version
of the data source.

=cut

sub version {
  my $self = shift;
  my $source = shift;
  my $c = $self->{conf}{$source}{data} or return;
  return $c->setting('general','version');
}

=head2 description()

  $description = $browser->description

This is a shortcut method that returns the value of the "description"
option in the general section.  The value returned is a human-readable
description of the data source.

=cut

sub description {
  my $self = shift;
  my $source = shift;
  my $c = $self->{conf}{$source}{data} or return;
  return $c->setting('general','description');
}

=head2 $time = $browser->remember_settings_time

Return the relative time (in CGI "expires" format) to maintain
information about the current page settings, including plugin
configuration.

=cut

sub remember_settings_time {
  my $self = shift;
  return $self->setting('remember settings time') || REMEMBER_SETTINGS_TIME;
}


=head2 $time = $browser->remember_source_time

Return the relative time (in CGI "expires" format) to maintain information
on which source the user is viewing.

=cut

sub remember_source_time {
  my $self = shift;
  return $self->setting('remember cookie time') || $self->setting('remember source time') || REMEMBER_SOURCE_TIME;
}

=head2 $language = $browser->language([$new_language])

Get/set an associated Bio::Graphics::Browser::I18n language translation object.

=cut

sub language {
  my $self = shift;
  my $d    = $self->{language};
  $self->{language} = shift if @_;
  $d;
}


=head2 $french = $browser->tr($english)

Translate message into currently-set language, with fallback to POSIX,
via associated Bio::Graphics::Browser::I18n language translation object.

=cut

sub tr {
  my $self = shift;
  my $lang = $self->language or return @_;
  $lang->tr(@_);
}

=head2 $section_setting = $browser->section_setting($section_name)

Returns "open" "closed" or "off" for the named section. Named sections are:

 instructions
 search
 overview
 details
 tracks
 display
 add tracks

=cut

sub section_setting {
  my $self = shift;
  my $section = shift;
  my $config_setting = "\L$section\E section";
  my $s = $self->setting($config_setting);
  return 'open' unless defined $s;
  return $s;
}

=head2 labels()

  @track_labels = $browser->labels

This method returns the names of each of the track stanzas,
hereinafter called "track labels" or simply "labels".  These labels
can be used in subsequent calls as the first argument to setting() in
order to retrieve track-specific options.

=cut

sub labels {
  my $self  = shift;
  my $order = shift;
  my @labels = $self->config->labels;
  if ($order) { # custom order
    return @labels[@$order];
  } else {
    return @labels;
  }
}

=head2 default_labels()

  @default_labels = $browser->default_labels

This method returns the labels for each track that is turned on by
default.

=cut

sub default_labels {
  my $self = shift;
  $self->config->default_labels;
}

=head2 label2type()

  @feature_types = $browser->label2type($label,$lowres);

Given a track label, this method returns a list of the corresponding
sequence feature types in a form that can be passed to Bio::DB::GFF.
The optional $lowres flag can be used to tell label2type() to select a
set of features that are suitable when viewing large sections of the
sequence (it is up to the person who writes the configuration file to
specify this).

=cut

sub label2type {
  my $self = shift;
  $self->config->label2type(@_);
}

=head2 type2label()

  $label = $browser->type2label($type);

Given a feature type, this method translates it into a track label.

=cut

sub type2label {
  my $self = shift;
  $self->config->type2label(@_);
}

=head2 feature2label()

  $label = $browser->feature2label($feature [,$length]);

Given a Bio::DB::GFF::Feature (or anything that implements a type()
method), this method returns the corresponding label.  If an optional
length is provided, the method takes semantic zooming into account.

=cut

sub feature2label {
  my $self = shift;
  my ($feature,$length) = @_;
  return $self->config->feature2label($feature,$length);
}

=head2 citation()

  $citation = $browser->citation($label)

This is a shortcut method that returns the citation for a given track
label.  It simply calls $browser->setting($label=>'citation');

=cut

sub citation {
  my $self = shift;
  my $label     = shift;
  my $language  = shift;
  my $config = $self->config;
  my $c;
  if ($language) {
    for my $l ($language->language) {
      $c ||= $config->setting($label=>"citation:$l");
      $c = &$c if ref $c eq 'CODE';
    }
  }
  $c ||= $config->setting($label=>'citation');
  $c = &$c if ref $c eq 'CODE';
  $c;
}

=head2 width()

  $width = $browser->width

This is a shortcut method that returns the width of the display in
pixels.

=cut

sub width {
  my $self = shift;
  my $d = $self->{width};
  $self->{width} = shift if @_;
  $d;
}

=head2 header()

  $header = $browser->header;

This is a shortcut method that returns the header HTML for the gbrowse
page.

=cut

sub header {
  my $self = shift;
  my $header = $self->config->setting(general => 'header');
  if (ref $header eq 'CODE') {
    my $h = eval{$header->(@_)};
    $self->_callback_complain(general=>'header') if @_;
    return $h;
  }
  return $header;
}

=head2 footer()

  $footer = $browser->footer;

This is a shortcut method that returns the footer HTML for the gbrowse
page.

=cut

sub footer {
  my $self = shift;
  my $footer = $self->config->setting(general => 'footer');
  if (ref $footer eq 'CODE') {
    my $f = eval {$footer->(@_)};
    $self->_callback_complain(general=>'footer') if @_;
    return $f;
  }
  return $footer;
}

=head2 config()

  $config = $browser->config;

This method returns a Bio::Graphics::FeatureFile object corresponding
to the current source.

=cut

sub config {
  my $self = shift;
  my $source = $self->source or return;
  $self->{conf}{$source}{data};
}

=head2 mtime()

  $time = $browser->mtime()

This method returns the modification time of the config file for the
current source.

=cut

sub mtime {
  my $self = shift;
  my $source = $self->source;
  $self->{conf}{$source}{mtime};
}

=head2 path()

  $path = $browser->path()

This method returns the file path of the config file for the
current source.

=cut

sub path {
  my $self = shift;
  my $source = $self->source;
  $self->{conf}{$source}{path};
}

sub default_label_indexes {
  my $self = shift;
  $self->config->default_label_indexes;
}

=head2 make_link()

  $url = $browser->make_link($feature,$panel,$label)

Given a Bio::SeqFeatureI object, turn it into a URL suitable for use
in a hypertext link.  For convenience, the Bio::Graphics panel is also
provided.  If $label is provided, then its link overrides the type of
the feature.

=cut

sub make_link {
  my $self = shift;
  my ($feature,$panel,$label,$src) = @_;
  my @results = $self->config->make_link($feature,$panel,$label,$self->source);
  return wantarray ? @results : $results[0];
}

=head2 render_panels()

  $panels = $browser->render_panels(%args);

Render an image and an image map according to the options in %args.
In a
Returns a two-element list.  The first element is a URL that refers to
the image which can be used as the SRC for an <IMG> tag.  The second
is a complete image map, including the <MAP> and </MAP> sections.

The arguments are a series of tag=>value pairs, where tags are:

  Argument            Value

  segment             A Bio::DB::GFF::Segment or
                      Bio::Das::SegmentI object (required).

  tracks              An arrayref containing a series of track
                        labels to render (required).  The order of the labels
                        determines the order of the tracks.

  options             A hashref containing options to apply to
                        each track (optional).  Keys are the track labels
                        and the values are 0=auto, 1=force no bump,
                        2=force bump, 3=force label, 4=expanded bump.

  feature_files       A hashref containing a series of
                        Bio::Graphics::FeatureFile objects to be
                        rendered onto the display (optional).  The keys
                        are labels assigned to the 3d party
                        features.  These labels must appear in the
                        tracks arrayref in order for render_panels() to
                        determine the order in which to render them.

  do_map              This argument is a flag that controls whether or not
                        to generate the image map.  It defaults to false.

  do_centering_map    This argument is a flag that controls whether or not
                        to add elements to the image map so that the user can
                        center the image by clicking on the scale.  It defaults
                        to false, and has no effect unless do_map is also true.

  title               Add specified title to the top of the image.

  noscale             Suppress the scale

  flip                Flip coordinates left to right

  hilite_callback     Callback for performing hilighting

  image_and_map       This argument will cause render_panels to emulate 
                        the legacy method image_and_map() and return a 
                        GD::Image object and a 'boxes' array reference rather
                        than rendered html.  This argument applies only to composite
                        (non-draggable) panel images.  

Any arguments names that begin with an initial - (hyphen) are passed
through to Bio::Graphics::Panel->new() directly

Any arguments names that begin with an initial - (hyphen) are passed
through to Bio::Graphics::Panel->new() directly

=cut

sub render_panels {
  my $self = shift;
  my $args = shift;

  my $segment         = $args->{segment};
  my $do_map          = $args->{do_map};
  my $drag_n_drop     = $self->drag_and_drop($args->{drag_n_drop});

  return unless $segment;

  $self->_load_aggregator_types($segment) if $do_map;
  my $panels = $self->generate_panels($args);

  return $drag_n_drop ? $self->render_draggable_tracks($args,$panels)
                      : $self->render_composite_track($args,$panels->{'__all__'});
}

=head2 drag_and_drop()

Return true if drag_and_drop tracks should be enabled on this
datasource. Looks at the "drag and drop" option and also consults a
series of user agents known to support drag_and_drop.

=cut

sub drag_and_drop {
  my $self          = shift;
  my $override      = shift;
  return if defined $override && !$override;
  my $dnd           = $self->setting(general => 'drag and drop'); # explicit drag-and-drop setting
  $dnd              = 1 unless defined $dnd;
  my $pg            = $self->setting(general => 'postgrid');      # postgrid forces drag and drop off
  return $dnd && !$pg;
}

sub cache_time {
  my $self = shift;
  my $override = shift;
  return $override if defined $override;
  my $ct = $self->setting(general => 'cache time');
  return $ct if defined $ct;  # may return zero
  return 1; # 1 hour default
}

sub render_draggable_tracks {
  my $self = shift;
  my ($args,$panels) = @_;

  my $images   = $self->relative_path_setting('buttons');
  my $do_map   = $args->{do_map};
  my $tmpdir   = $args->{tmpdir};
  my $settings = $args->{settings};
  my $do_drag  = $args->{do_drag};
  my $button   = $args->{image_button};
  my $section  = $args->{section};
  $section    =~ s/^\?//;

  my $plus   = "$images/plus.png";
  my $minus  = "$images/minus.png";
  my $share  = "$images/share.png";
  my $help   = "$images/query.png";

  # get the pad image, which we use to fill up space between collapsed tracks
  my $pad_url  = $panels->{__pad__}{image};
  my ($pw,$ph) = @{$panels->{__pad__}}{'width','height'};


  my @result;
  for my $label ('__scale__',@{$args->{labels}}) {

    next unless $panels->{$label};
    my ($url,$img_map,$width,$height) = @{$panels->{$label}}{qw(image map width height)};

    # this complication is due to the fact that a plugin or uploaded file can be
    # in several sections at the same time
    my $element_id    = $label =~ /^(file|plugin):/ ? "${section}_${label}" : $label;

    my $collapsed     =  $settings->{track_collapsed}{$element_id};
    my $img_style     = $collapsed ? "display:none" : "display:inline";

    # The javascript functions for rubber-band selection
    # need this ID as a hook, please do not change it
    my $id = $label eq '__scale__' 
	? "${section}_image" 
	: "${element_id}_image";

    # we don't want overview and regionview tracks to be clickable image buttons
#     my @disabled = ();
#     if ($id =~ /^[^\:]+\:(overview|region)/ && !$img_map) {
# 	@disabled = (-disabled => 1);
# 	$img_style .= ';cursor:default';
#     }
#     if ($img_map) {
# 	$button = 0;
#     }

    $img_style .= '; cursor:pointer' if $label eq '__scale__';

    my @map = $button 
	? () 
	: (-usemap=>"#${element_id}_map");
    my $img = img({-src=>$url,
		   -width => $width,
		   -id    => "$id",
		   -height=> $height,
		   -border=> 0,
		   -name  => "${section}_${label}",
		   -alt   => "${label} $section",
		   -style => $img_style,
		   @map,
		  });

    my $class     = $label eq '__scale__' ? 'scale' : 'track';
    my $icon      = $collapsed ? $plus : $minus;

    my $config_click;
    if ($label =~ /^plugin:/) {
	my $help_url = "url:?plugin=".CGI::escape($label).';plugin_do=Configure';
	$config_click = "balloon.showTooltip(event,'$help_url',1)";
    }

    elsif ($label =~ /^file:/) {
	my $url  = "?modify.${label}=".$self->tr('Edit');
	$config_click = "window.location='$url'";
    }

    else {
	my $help_url = "url:?configure_track=".CGI::escape($label);
	$help_url   .= ";rand=".rand(); # work around caching bugs... # if CGI->user_agent =~ /MSIE/;
	$config_click = "balloon.showTooltip(event,'$help_url',1)";
    }

    my $title;
    if ($label =~ /\w+:(.+)/ && $label !~ /:overview|:region/) {
      $title = $label =~ /^http|^ftp/ ? $self->url_label($label) : $1;
    }
    else {
      $title = $self->config->setting($label=>'key') || $label;
    }

    if ($self->setting(general=>'show track categories')) {
	my $cat = $self->config->setting($label=>'category');
	$title .= " ($cat)" if $cat;
    }
    my $show_or_hide     = $self->tr('SHOW_OR_HIDE_TRACK');
    my $share_this_track = $self->tr('SHARE_THIS_TRACK');
    my $citation         = $self->plain_citation($label,512);
    #$citation            =~ s/"/&quot;/g;
    #$citation            =~ s/'/&#39;/g;

    my $configure_this_track = $citation || '';
    $configure_this_track   .= '<br>' if $citation;
    $configure_this_track   .= $self->tr('CONFIGURE_THIS_TRACK');
    my $escaped_label        = CGI::escape($label);
	   
    my $titlebar    = $label eq '__scale__' || $label eq '__all__'
	? ''
	: span({-class=>$collapsed ? 'titlebar_inactive' : 'titlebar',-id=>"${element_id}_title"},
	       img({-src         =>$icon,
		    -id          => "${element_id}_icon",
		    -onMouseOver => "balloon.showTooltip(event,'$show_or_hide')",
		    -onClick     => "collapse('$element_id')",
		    -style       => 'cursor:pointer',
		   }),
	       img({-src         => $share,
		    -style       => 'cursor:pointer',
		    -onMouseOver => "balloon.showTooltip(event,'$share_this_track')",
		    -onMousedown => "balloon.showTooltip(event,'url:?share_track=$escaped_label')",
		   }),
	       $label !~ /^(http|ftp|das):/ 
	         ? img({-src         => $help,
			-style       => 'cursor:pointer',
			-onMouseOver => "balloon.showTooltip(event,'$configure_this_track')",
			-onmousedown => $config_click
		       })
	         : (),
	       span({-class=>'draghandle'},$title)
	);
    
    my $pad_img  = img({-src   => $pad_url,
			-width => $pw,
			-height=> $ph,
			-border=> 0,
			-id    => "${element_id}_pad",
			-style => $collapsed ? "display:inline" : "display:none",
		       });

    (my $munge_label = $label) =~ s/_/%5F/g;  # freakin' scriptaculous uses _ as a delimiter!!!
    $img_map = qq(<map name="${element_id}_map" id="${element_id}_map">$img_map</map>\n) if $img_map;

    push @result, (is_safari()
		   ?
		   "\n".div({-id=>"${section}_track_${munge_label}",-class=>$class},
			    $titlebar,
			    div({-align=>'center',
				 -style=>'margin-top: -18px; margin-bottom: 3px'},
				$img.$pad_img),
			    $img_map||'')
		   :
		   "\n".div({-id=>"${section}_track_${munge_label}",-class=>$class},
			    div({-align=>'center'},$titlebar.$img.$pad_img),
			    $img_map||'')
    );

  }

  return wantarray ? @result : join '',@result;
}

sub render_composite_track {
  my $self   = shift;
  my ($args,$panel) = @_;

  my $section = $args->{section} || '?detail';
  $section    =~ s/^\?//;
  my $button  = $args->{image_button};

  my ($width,$height,$url,$map,$gd,$boxes) = @{$panel}{qw/width height image map gd boxes/};

  # doesn't work
  #   my $css_map = $self->map_css($boxes,$section) if $section eq 'detail';

  if ($args->{image_and_map}) {
    return $gd, $boxes;
  }

  $map ||= '';
  my $map_name = param('hmap') || "${section}_map";

  # The javascript functions for rubber-band selection
  # need this ID as a hook, please do not change it

  # rubberbanding doesn't work with composite track
  my $id = $section eq 'detail' ? 'composite_track' : "${section}_image";

  my $img = $button
      ? image_button(-src   => $url,
		     -name  => $section,
		     -id    => $id
		    )
      : img({-src=>$url,
	     -usemap=>'#'.$map_name,
	     -width => $width,
	     -id    => $id,
	     -height=> $height,
	     -border=> 0,
	     -name  => $section,
	     -alt   => $section,
	     -style => 'position:relative'});


  my $html    = div({-align=>'center'},
		    $img,
#		    $css_map,
		    qq(<map name="$map_name">$map</map>)
      );

  return $html;
}

=head2 generate_panels()

Generate the GD object and the imagemap and returns a hashref in the format

  $results->{track_label} = {image=>$uri, map=>$map_data, width=>$w, height=>$h, file=>$img_path)

If the "drag_n_drop" argument is false, then returns a single track named "__all__".

Arguments: a key=>value list
   'section'       Section type to draw; one of "overview", "region" or "detail"
   'segment'       A feature iterator that responds to next_seq() methods
   'feature_files' A hash of Bio::Graphics::FeatureFile objects containing 3d party features
   'options'       An hashref of options, where 0=auto, 1=force no bump, 2=force bump, 3=force label
                      4=force fast bump, 5=force fast bump and label
   'drag_n_drop'   Force drag-and-drop behavior on or off
   'limit'         Place a limit on the number of features of each type to show.
   'labels'        List of named tracks, in the order in which they are to be shown
   'tracks'        List of named tracks, in the order in which they are to be shown (deprecated)
   'label_scale'   If true, prints chromosome name next to scale
   'title'         A title for the image
   'noscale'       Suppress scale entirely
   'image_class'   Optional image class for generating SVG output (by passing GD::SVG)
   'cache_extra'   Extra cache args needed to make this image unique
   'scale_map_type' If equal to "centering_map" adds an imagemap to the ruler that recenters.
                    If equal to "interval_map" creates an imagemap that jumps to a small interval in map
   'featurefile_select' callback for selecting features to be rendered from a featurefile onto a panel
any arguments that begin with an initial - (hyphen) are passed through to Panel->new
directly

=cut

sub generate_panels {
  my $self  = shift;
  my $args  = shift;

  my $segment       = $args->{segment};
  my ($seg_start,$seg_stop,$flip) = $self->segment_coordinates($segment,
							       $args->{flip});
  my $feature_files = $args->{feature_files} || {};
  my $labels        = $args->{labels} || $args->{tracks} || []; # legacy
  my $options       = $args->{options}       || {};

  my $limits        = $args->{limit}         || {};
  my $lang          = $args->{lang} || $self->language;
  my $suppress_scale= $args->{noscale};
  my $hilite_callback = $args->{hilite_callback};
  my $drag_n_drop   = $self->drag_and_drop($args->{drag_n_drop});
  my $do_map        = $args->{do_map};
  my $cache_extra   = $args->{cache_extra} || [];
  my $cache         = $args->{cache};
  my $settings      = $args->{settings};
  my $section       = $args->{section}     || '?detail';

  # hack to turn caching off in a one-shot fashion...
  $cache = 0 if param('redisplay');

  my @panel_args    = $self->create_panel_args($section,$args);

  $segment->factory->debug(1) if DEBUG;
  #$self->error('');

  my $conf     = $self->config;
  my $length   = $segment->length;

  #---------------------------------------------------------------------------------
  # Track and panel creation

  # we create two hashes:
  #        the %panels hash maps label names to panels
  #        the %tracks hash maps label names to tracks within the panels
  # in the case of no drag_n_drop, then %panels will contain a single key named "__scale__"
  my %panels;           # map label names to Bio::Graphics::Panel objects
  my %tracks;           # map label names to Bio::Graphics::Track objects
  my %track_args;       # map label names to track-specificic arguments (for caching)
  my %seenit;           # used to avoid possible upstream error of putting track on list multiple times
  my %results;          # hash of {$label}{gd} and {$label}{map}
  my %cached;           # list of labels that have cached data on disk
  my %cache_key;        # list that maps labels to cache keys

  my $panel_key = $drag_n_drop ? '__scale__' : '__all__';

  # When running in monolithic mode, we need to be very careful about the cache key. This key
  # is the combination of the panel type, the panel args, and all the individual track args!
  my @cache_args          = ($section,$panel_key,@panel_args,
			     @$cache_extra,$do_map);
  if ($panel_key eq '__all__') {
    $track_args{$_} ||= [$self->create_track_args($_,$args)] foreach @$labels;
    push @cache_args,map {@$_} values %track_args;
  }

  $cache_key{$panel_key}  = $self->create_cache_key(@cache_args);
  $cached{$panel_key}     = $cache && $self->panel_is_cached($cache_key{$panel_key});

  unless ($cached{$panel_key}) {
    $panels{$panel_key}      = Bio::Graphics::Panel->new(@panel_args);

    $panels{$panel_key}->add_track($segment      => 'arrow',
				   -double       => 1,
				   -tick         => 2,
				   -label        => $args->{label_scale} ? $segment->seq_id : 0,
				   -units        => $conf->setting(general=>'units') || '',
				   -unit_divider => $conf->setting(general=>'unit_divider') || 1,
				  ) unless $suppress_scale;
  }

  # create another special track for padding to be used when we "collapse" a track, but only
  # if $drag_n_drop is false.
  if ($drag_n_drop) {
    $panel_key = '__pad__';
    my @cache_args           = ($section,$panel_key,@panel_args,
				@$cache_extra,$drag_n_drop);
    $cache_key{$panel_key}   = $self->create_cache_key(@cache_args);
    unless ($cached{$panel_key} =
	    $cache && $self->panel_is_cached($cache_key{$panel_key})
	   ) {
      $panels{$panel_key} = Bio::Graphics::Panel->new(@panel_args);
    }
  }

  # this will keep track of numbering of the tracks; only used when inserting
  # feature files into one big panel.
  my $trackno = $suppress_scale ? 0 : 1;
  my %feature_file_offsets;

  for my $label (@$labels) {

    # das tracks only go into details panel for now.
    next if $feature_files->{$label} && 
	$label =~ m!/das/! && 
	$section !~ /detail/; 

    next if $seenit{$label}++; # this shouldn't happen, but let's be paranoid

    # if "hide" is set to true, then skip panel
    next if $conf->semantic_setting($label=>'hide',$length);

    $track_args{$label} ||= [$self->create_track_args($label,$args)];

    # create a new panel if we are in drag_n_drop mode
    if ($drag_n_drop) {
      $panel_key = $label;

      # get config data from the feature files
      my @extra_args          = eval {
	$feature_files->{$label}->types,
        $feature_files->{$label}->mtime,
	} if $feature_files->{$label};

      my @args = (
		  @panel_args,
		  @{$track_args{$label}},
		  @extra_args,
		  @$cache_extra,
		  $drag_n_drop,
		  $options->{$label},
	          $label,
	  );

      $cache_key{$label}      = $self->create_cache_key(@args);
      next if $cached{$label} = $cache && $self->panel_is_cached($cache_key{$label});

      my @keystyle = (-key_style=>'between') 
	if $label =~ /^\w+:/ && $label !~ /:(overview|region)/;  # a plugin

      $panels{$panel_key}         = Bio::Graphics::Panel->new(@panel_args,@keystyle);
    }

    # case of a third-party feature or plugin, in which case we defer creation of a track
    # but record where we would place it
    elsif ($feature_files->{$label}) {
      $feature_file_offsets{$label} = $trackno;
      next;
    }

    $tracks{$label} = $panels{$panel_key}->add_track(@{$track_args{$label}})
      unless $cached{$panel_key} || $feature_files->{$label};
  }
  continue {
    $trackno++;
  }

  #---------------------------------------------------------------------------------
  # Add features to the database
  my @feature_types = map { $conf->label2type($_,$length) } grep {!$cached{$_}} @$labels;
  my %filters = map { my %conf =  $conf->style($_); 
		      $conf{'-filter'} ? ($_ => $conf{'-filter'})
			               : ()
		      } @$labels;
  $self->add_features_to_track(-types   => \@feature_types,
			       -tracks  => \%tracks,
			       -filters => \%filters,
			       -segment => $segment,
			       -options => $options,
			       -limits  => $limits,
			      ) if @feature_types;

  # ------------------------------------------------------------------------------------------
  # Add feature files, including remote annotations

  # Start by removing uploaded files mentioned in the list of labels, but
  # not in the feature_files list. This is a workaround for an upstream bug.
  for my $l (grep {/^(file|http|ftp):/} @$labels) {
    next if $feature_files->{$l};
    next unless $drag_n_drop;
    eval {$panels{$l}->finished};
    delete $panels{$l};
    delete $cached{$l};
  }

  my $featurefile_select = $args->{featurefile_select} 
                           || $self->feature_file_select($section);
  my $feature_file_extra_offset = 0;

  my %trackmap;

  for my $l (sort
	     { 
		 ($feature_file_offsets{$a}||1) <=> ($feature_file_offsets{$b}||1) 
	     } keys %$feature_files) {


    next if $cached{$l};
    my $file = $feature_files->{$l} or next;

    ref $file or next;
    $panel_key = $l if $drag_n_drop;

    next unless $panels{$panel_key};

    my $ff_offset = defined $feature_file_offsets{$l} ? $feature_file_offsets{$l} : 1;

    my $override_args  = $settings->{features}{$l}{override_settings} || {};
    my @override       = map {'-'.$_ => $override_args->{$_}} keys %$override_args;

    my ($nr_tracks_added,$tracks) =
      $self->add_feature_file(
			      file     => $file,
			      panel    => $panels{$panel_key},
			      position => $ff_offset + $feature_file_extra_offset,
			      options  => $options,
			      select   => $featurefile_select,
			      segment  => $segment,
	                      override_settings => \@override,
			     );

    do { eval {$panels{$panel_key}->finished};
	 delete $panels{$panel_key};
	 delete $cached{$panel_key};
       }
      if $drag_n_drop && $nr_tracks_added==0;  # suppress display of empty uploaded file tracks
    $trackmap{$_} = $file foreach @$tracks;

    $feature_file_extra_offset += $nr_tracks_added-1;
  }

  # map tracks (stringified track objects) to corresponding labels
  for my $label (keys %tracks) { $trackmap{$tracks{$label}} = $label }

  # uncached panels need to be generated and cached
  $args->{scale_map_type} ||= 'centering_map' unless $suppress_scale;
  (my $map_name = $section) =~ s/^\?//;

  for my $l (keys %panels) {
    my $gd    = $panels{$l}->gd;
    my $boxes = $panels{$l}->boxes;
    $self->debugging_rectangles($gd,$boxes) if DEBUG;
    my $map  = !$do_map          ? (undef,undef)
	     : $l eq '__pad__'   ? (undef,undef)
	     : $l eq '__scale__' ? $self->make_centering_map(shift @{$boxes},
							     $args->{flip},
							     $l,
							     $args->{scale_map_type}
							     )
	     : $l eq '__all__'   ? $self->make_map($boxes,
						   $panels{$l},
						   $map_name,
						   \%trackmap,
						   $args->{scale_map_type})
	     : $self->make_map($boxes,
			       $panels{$l},
			       $l,
			       \%trackmap,
			       0);
    my $key = $drag_n_drop ? $cache_key{$l} : $cache_key{'__all__'};
    $self->set_cached_panel($key,$gd,$map);
    eval {$panels{$l}->finished};
  }

  # cached panels need to be retrieved
  for my $l (keys %cached) {
    @{$results{$l}}{qw(image map width height file gd boxes)} = $self->get_cached_panel($cache_key{$l});
    # for apps that rely on the image_and_maps syntax, format the boxes
    $results{$l}{boxes} = $self->map_array($results{$l}{boxes});
  }

  return \%results;
}

sub add_features_to_track {
  my $self = shift;
  my %args = @_;

  my $segment         = $args{-segment} or die "programming error";
  my $feature_types   = $args{-types}   or die "programming error";
  my $tracks          = $args{-tracks}  or die "programming error";
  my $filters         = $args{-filters} or die "programming error";
  my $options         = $args{-options} or die "programming error";
  my $limits          = $args{-limits}  or die "programming error";

  my $max_labels      = $self->label_density;
  my $max_bump        = $self->bump_density;

  my $length  = $segment->length;
  my $conf    = $self->config;

  my (%groups,%feature_count,%group_pattern,%group_field);
  my $iterator = $segment->get_feature_stream(-type=>$feature_types);

  while (my $feature = $iterator->next_seq) {

    my @labels = $self->feature2label($feature,$length);

    for my $l (@labels) {

      my $track = $tracks->{$l}  or next;
      $filters->{$l}->($feature) or next if $filters->{$l};
      $feature_count{$l}++;


      # ------------------------------------------------------------------------------------------
      # GROUP CODE
      # Handle name-based groupings.
      unless (exists $group_pattern{$l}) {
	$group_pattern{$l} =  $conf->setting($l => 'group_pattern');
	$group_pattern{$l} =~ s!^/(.+)/$!$1! 
	                       if $group_pattern{$l}; # clean up regexp delimiters
	}

      # Handle generic grouping (needed for GFF3 database)
      $group_field{$l} = $conf->setting($l => 'group_on') unless exists $group_field{$l};
	
      if (my $pattern = $group_pattern{$l}) {
	my $name = $feature->name or next;
	(my $base = $name) =~ s/$pattern//i;
	$groups{$l}{$base} ||= Bio::Graphics::Feature->new(-type   => 'group');
	$groups{$l}{$base}->add_segment($feature);
	$feature_count{$l}--;
	next;
      }
	
      if (my $field = $group_field{$l}) {
	my $base = eval{$feature->$field};
	if (defined $base) {
	  $groups{$l}{$base} ||= $self->clone_feature($feature);
	  $groups{$l}{$base}->add_SeqFeature($feature);
	  $feature_count{$l}--;
	  next;
	}
      }

      $track->add_feature($feature);
    }
  }

  # ------------------------------------------------------------------------------------------
  # fixups

  # fix up %group features
  # the former creates composite features based on an arbitrary method call
  # the latter is traditional name-based grouping based on a common prefix/suffix

  for my $l (keys %groups) {
    my $track  = $tracks->{$l};
    my $g      = $groups{$l} or next;
    $track->add_feature($_) foreach values %$g;
    $feature_count{$l} += keys %$g;
  }

  # now reconfigure the tracks based on their counts
  for my $l (keys %$tracks) {
    next unless $feature_count{$l};

    $options->{$l} ||= 0;

    my $count = $feature_count{$l};
    $count    = $limits->{$l}
      if $limits->{$l} &&
	$limits->{$l} < $count;

    my $do_bump  = $self->do_bump($l,
				  $options->{$l},
				  $count,
				  $max_bump,
				  $length);

    my $do_label = $self->do_label($l,
				   $options->{$l},
				   $count,
				   $max_labels,
				   $length);

    my $do_description = $self->do_description($l,
					       $options->{$l},
					       $count,
					       $max_labels,
					       $length);

    $tracks->{$l}->configure(-bump  => $do_bump,
			     -label => $do_label,
			     -description => $do_description,
			      );
    $tracks->{$l}->configure(-connector  => 'none') if !$do_bump;
    $tracks->{$l}->configure(-bump_limit => $limits->{$l}) 
      if $limits->{$l} && $limits->{$l} > 0;
  }
}

=head2 add_feature_file

Internal use: render a feature file into a panel

=cut

sub add_feature_file {
  my $self = shift;
  my %args = @_;

  my $file    = $args{file}    or return;
  my $options = $args{options} or return;

  my $select  = $args{select}  or return;

  my $name = $file->name || '';
  $options->{$name}      ||= 0;

  my $override_settings = $args{override_settings};

  my ($nr_tracks_added,$panel,$tracklist) =
    eval {
      $file->render(
	  $args{panel},
	  $args{position},
	  $options->{$name},
	  $self->bump_density,
	  $self->label_density,
	  $select,
	  $args{segment},
	  $override_settings,
	  );
      };

  $self->error("error while rendering ",$args{file}->name,": $@") if $@;
  return ($nr_tracks_added,$tracklist);
}

# this returns a coderef that will indicate whether an added (external) feature is placed
# in the overview, region or detailed panel. If the section name begins with a "?", then
# if not otherwise stated, the feature will be placed in this section.
sub feature_file_select {
  my $self             = shift;
  my $required_section = shift;

  my $undef_defaults_to_true;
  if ($required_section =~ /^\?(.+)/) {
    $undef_defaults_to_true++;
    $required_section = $1;
  }

  return sub {
    my $file  = shift;
    my $type  = shift;
    my $section = $file->setting($type=>'section') || $file->setting(general=>'section');
    return $undef_defaults_to_true if !defined$section;
    return $section =~ /$required_section/;
  };
}

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
  my ($extension,$data);

  if (!ref $image) { # possibly raw SVG data -- this is a workaround
    $extension = 'svg';
    $data      = $image;
  } else {
    $extension = $image->can('png') ? 'png' : 'gif';
    $data      = $image->can('png') ? $image->png : $image->gif;
  }

  my $signature = md5_hex($data);

  warn ((CGI::param('ref')||'')   . ':' .
	(CGI::param('start')||'') . '..'.
	(CGI::param('stop')||'')
	,
	" sig $signature\n") if DEBUG;

  # untaint signature for use in open
  $signature =~ /^([0-9A-Fa-f]+)$/g or return;
  $signature = $1;

  my ($uri,$path) = $self->tmpdir($self->source.'/img');
  my $url         = sprintf("%s/%s.%s",$uri,$signature,$extension);
  my $imagefile   = sprintf("%s/%s.%s",$path,$signature,$extension);
  open (F,">$imagefile") || die("Can't open image file $imagefile for writing: $!\n");
  binmode(F);
  print F $data;
  close F;
  return wantarray ? ($url,$imagefile) : $url;
}

sub tmpdir {
  my $self = shift;
  my $path = shift || '';

  # Original code; retain while testing new "callback_setting" method below
  #  my ($tmpuri,$tmpdir) = shellwords($self->setting('tmpimages'))
  #   or die "no tmpimages option defined, can't generate a picture";

  my ($tmpuri,$tmpdir) = Bio::Graphics::Browser::Util::shellwords($self->callback_setting('tmpimages'))
    or die "no tmpimages option defined, can't generate a picture";

  $tmpuri  = $self->relative_path($tmpuri);
  $tmpuri .= "/$path" if $path;

  if ($ENV{MOD_PERL} ) {
    my $r          = modperl_request();
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

# Check if a configuration setting is a coderef or simple variable
sub callback_setting {
    my $self = shift;
    my $val  = $self->setting(@_);
    return ref $val eq 'CODE' ? $val->() : $val;
}

sub make_map {
  my $self = shift;
  my ($boxes,$panel,$map_name,$trackmap,$first_box_is_scale) = @_;
  my @map = ($map_name);

  my $flip      = $panel->flip;
  my $tips      = $self->setting('balloon tips');
  my $use_titles_for_balloons = $self->setting('titles are balloons');

  my $did_map;

  local $^W = 0; # avoid uninit variable warnings due to poor coderefs

  if ($first_box_is_scale) {
    push @map, $self->make_centering_map(shift @$boxes,$flip,0,$first_box_is_scale);
  }

  foreach (@$boxes){
    next unless $_->[0]->can('primary_tag');

    my $label  = $_->[5] ? $trackmap->{$_->[5]} : '';

    my $href   = $self->make_href($_->[0],$panel,$label,$_->[5]);
    my $title  = unescape($self->make_title($_->[0],$panel,$label,$_->[5]));
    my $target = $self->config->make_link_target($_->[0],$panel,$label,$_->[5]);

    my ($mouseover,$mousedown,$style);
    if ($tips) {

      #retrieve the content of the balloon from configuration files
      # if it looks like a URL, we treat it as a URL.
      my ($balloon_ht,$balloonhover)     = 
	  $self->config->balloon_tip_setting('balloon hover',$label,
					     $_->[0],$panel,$_->[5]);

      my ($balloon_ct,$balloonclick)     = 
	  $self->config->balloon_tip_setting('balloon click',$label,
					     $_->[0],$panel,$_->[5]);

      # balloon_ht = type of balloon to use for hovering -- usually "balloon"
      # balloon_ct = type of balloon to use for clicking -- usually "balloon"
      my $sticky             = $self->setting($label,'balloon sticky');
      my $height             = $self->setting($label,'balloon height') || 300;
      my $width              = $self->setting($label,'balloon width')  || 0;
      my $hover_width        = $self->setting($label,'balloon hover width')  || $width;
      my $click_width        = $self->setting($label,'balloon click width')  || $width;

      if ($use_titles_for_balloons) {
	$balloonhover ||= $title;
	$balloonhover  =~ s/\'/\&\#39;/g;
	$balloonhover  =~ s/\"/\&\#34;/g;
      }

      $balloon_ht ||= 'balloon';
      $balloon_ct ||= 'balloon';

      if ($balloonhover) {
        my $iframe_width = $hover_width || "'+parseInt($balloon_ct.maxWidth)+'";
        my $stick = defined $sticky ? $sticky : 0;
        $mouseover = $balloonhover =~ /^(https?|ftp):/
            ? "$balloon_ht.showTooltip(event,'<iframe width=$iframe_width height=$height frameborder=0 " .
              "src=$balloonhover scrolling=no></iframe>',$stick)"
	      : "$balloon_ht.showTooltip(event,'$balloonhover',$stick,$hover_width)";
        undef $title;
      }
      if ($balloonclick) {
        my $iframe_width = $click_width || "'+parseInt($balloon_ct.maxWidth)+'";
        my $iframe_style = "style=padding-right:16px";
        $style = "cursor:pointer";
        $mousedown = $balloonclick =~ /^(http|ftp):/
            ? "$balloon_ct.showTooltip(event,'<iframe width=$iframe_width height=$height " .
              "frameborder=0 src=$balloonclick $iframe_style></iframe>')"
	      : "$balloon_ct.showTooltip(event,'$balloonclick',1,$click_width)";
        undef $href;
      }
    }

    my %attributes = (
		      title       => $title,
		      href        => $href,
		      target      => $target,
		      onmouseover => $mouseover,
		      onmousedown => $mousedown,
		      style       => $style
		      );

    my $ftype = $_->[0]->primary_tag || 'feature';
    my $fname = $_->[0]->display_name if $_->[0]->can('display_name');
    $fname  ||= $_->[0]->name if $_->[0]->can('name');
    $fname  ||= 'unnamed';
    $ftype = "$ftype:$fname";
    my $line = join("\t",$ftype,@{$_}[1..4]);
    for my $att (keys %attributes) {
      next unless defined $attributes{$att} && length $attributes{$att};
      $line .= "\t$att\t$attributes{$att}";
    }
    push @map, $line;
  }

  return \@map;

}

# this creates image map for rulers and scales, where clicking on the scale
# should center the image on the scale.
sub make_centering_map {
  my $self   = shift;
  my ($ruler,$flip,$label,$scale_map_type)  = @_;
  my @map = $label ? ($label) : ();

  my $title = $self->tr('Recenter');

  return if $ruler->[3]-$ruler->[1] == 0;

  my $length = $ruler->[0]->length;
  my $offset = $ruler->[0]->start;
  my $end    = $ruler->[0]->end;
  my $scale  = $length/($ruler->[3]-$ruler->[1]);
  my $pl     = $ruler->[-1]->panel->pad_left;

  my $ruler_intervals = RULER_INTERVALS;

  if ($scale_map_type eq 'interval_map' && $length/RULER_INTERVALS > $self->get_max_segment) {
    my $max = $self->get_max_segment/5;  # usually a safe guess
    $ruler_intervals = int($length/$max);
  }

  # divide into RULER_INTERVAL intervals
  my $portion = ($ruler->[3]-$ruler->[1])/$ruler_intervals;
  my $ref    = $ruler->[0]->seq_id;
  my $source = $self->source;

  for my $i (0..$ruler_intervals-1) {
    my $x1 = int($portion * $i+0.5);
    my $x2 = int($portion * ($i+1)+0.5);

    my ($start,$stop);
    if ($scale_map_type eq 'centering_map') {
      # put the middle of the sequence range into the middle of the picture
      my $middle = $flip ? $end - $scale * ($x1+$x2)/2 : $offset + $scale * ($x1+$x2)/2;
      $start  = int($middle - $length/2);
      $stop   = int($start  + $length - 1);
    }
    elsif ($scale_map_type eq 'interval_map') {
      # center on the interval
      $start = int($flip ? $end - $scale * $x1 : $offset + $scale * $x1);
      $stop  = int($start + $portion * $scale);
    }

    $x1 += $pl;
    $x2 += $pl;

    my $url = "?ref=$ref;start=$start;stop=$stop";
    $url .= ";flip=1" if $flip;
    
    push @map, join("\t",'ruler',$x1, $ruler->[2], $x2, $ruler->[4], 
		    href  => $url, title => $title||'', alt   => $title||'');
  }
  
  return $label ? \@map : @map;
}

sub make_href {
  my $self = shift;
  my ($feature,$panel,$label,$track)   = @_;
  return $self->make_link($feature,$panel,$label,$self->source,$track);
}

sub make_title {
  my $self             = shift;
  my ($feature,$panel,$label) = @_;
  return $feature->make_title if $feature->can('make_title');
  return $self->config->make_title($feature,$panel,$label);
}


###### attempted substitution; unfortunately runs slower than original!! #######
=head2 new_hits_on_overview()

  $hashref = $browser->hits_on_overview($db,$hits,$options,$keyname);

This method is used to render a series of genomic positions ("hits")
into a graphical summary of where they hit on the genome in a
segment-by-segment (e.g. chromosome) manner.

The first argument is a Bio::DB::GFF (or Bio::DasI) database.  

The second argument is an array ref containing one of:

  1) a set of array refs in the form [ref,start,stop,name], where
     name is optional.

  2) a Bio::DB::GFF::Feature object

  3) a Bio::SeqFeatureI object.

The third argument is the page settings hash from gbrowse.

The fourth option is the key to use for the "hits" track.

The returned HTML is stored in a hashref, where the keys are the
reference sequence names and the values are HTML to be emitted.

=cut

sub new_hits_on_overview {
  my $self = shift;
  my ($db,$hits,$page_settings,$keyname) = @_;


  my %overviews; # results are a hashref sorted by chromosome

  $keyname ||= 'Matches';

  my $class         = eval{$hits->[0]->factory->default_class} || 'Sequence';
  my ($padl,$padr)  = $self->overview_pad([grep { $page_settings->{$_}{visible}}
					   $self->config->overview_tracks],
					  'Matches');

  # sort hits out by reference and version
  my (%featurefiles);

  for my $hit (@$hits) {
    if (ref($hit) eq 'ARRAY') {
      my ($ref,$start,$stop,$name) = @$hit;
      $featurefiles{$ref} ||= Bio::Graphics::FeatureFile->new(-smart_features  => 1);
      $featurefiles{$ref}->add_feature(Bio::Graphics::Feature->new(-seq_id=>$ref,
								   -start=>$start,
								   -end=>$stop,
								   -name=>$name||'',
								   -type=>'hit',
								  )
				      );
    }
    elsif (UNIVERSAL::can($hit,'seq_id')) {
      my $name        = $hit->can('seq_name') ? $hit->seq_name : $hit->name;
      eval {$hit->absolute(1)};
      my $ref         = my $id = $hit->seq_id;
      my $version     = eval {$hit->isa('Bio::SeqFeatureI') ? undef : $hit->version};
      $ref           .= " version $version" if defined $version;
      my($start,$end) = ($hit->start,$hit->end);
      $name           =~ s/\:\d+,\d+$//;  # remove coordinates if they're there
      $name           = substr($name,0,7).'...' if length $name > 10;
      $featurefiles{$ref} ||= Bio::Graphics::FeatureFile->new(-smart_features  => 1);
      my $f =Bio::Graphics::Feature->new(-seq_id=>$ref,
					 -start=>$start,
					 -end=>$end,
					 -name=>$name,
					 -type=>'hit',
					);
      $featurefiles{$ref}->add_feature($f);
    } elsif (UNIVERSAL::can($hit,'location')) {
      my $location                 = $hit->location;
      my ($ref,$start,$stop,$name) = ($location->seq_id,$location->start,
				      $location->end,$location->primary_tag);
      $featurefiles{$ref} ||= Bio::Graphics::FeatureFile->new(-smart_features  => 1);
      $featurefiles{$ref}->add_feature(Bio::Graphics::Feature->new(-seq_id=>$ref,
								   -start=>$start,
								   -end=>$stop,
								   -name=>$name||'',
								   -type=>'hit')
				      );
    }
  }

  # We now have a feature list. Create an overview for each unique ref
  my @refs = sort keys %featurefiles;

  my @tracks_to_show = grep {$page_settings->{features}{$_}{visible} && /:overview$/ }
    @{$page_settings->{tracks}};
  push @tracks_to_show,'my_data';

  for my $ref (@refs) {
    my ($name, $version) = split /\sversion\s/i, $ref;
    my $segment = ($db->segment(-class=>$class,-name=>$name,
				defined $version ? (-version => $version):()))[0] or next;

    my @cache_extra = (time);  # this will never cache
    my $count = scalar (my @h = $featurefiles{$ref}->features);
    $featurefiles{$ref}->add_type(hit => {
					  glyph  => 'diamond',
					  bgcolor=> 'red',
					  fgcolor=> 'red',
					  key    => $keyname,
					  fallback_to_rectangle => 1,
					  no_subparts    => 1,
					  bump      => $count <= $self->bump_density,
					  label     => $count <= $self->bump_density,  # deliberate
					  link   => sub {my $f = shift; 
							 return "?name=".$f->display_name}
					  }
				  );
    my $html = $self->render_panels({
				     section       => "overview_${ref}",
				     segment       => $segment,
				     labels        => \@tracks_to_show,
				     feature_files => {my_data => $featurefiles{$ref}},
				     drag_n_drop   => 0,
				     do_map        => 1,
				     scale_map_type=> 'interval_map',
				     keystyle      => 'left',
				     label_scale   => 1,
				     cache_extra   => \@cache_extra,
				     image_class   => 'GD',
				     featurefile_select => sub { 1 } ,
				     -grid         => 0,
				     -pad_left     => $padl,
				     -pad_right    => $padr,
				     -bgcolor      => $self->setting("overview bgcolor") || DEFAULT_OVERVIEW_BGCOLOR,
					 }
					);
    $overviews{$ref} = $html;
  }

  return \%overviews;
}

sub bump_density {
  my $self = shift;
  my $conf = $self->config;
  return $conf->setting(general=>'bump density')
      || $conf->setting('TRACK DEFAULTS' =>'bump density')
      || 50;
}

sub label_density {
  my $self = shift;
  my $conf = $self->config;
  return $conf->setting(general=>'label density')
      || $conf->setting('TRACK DEFAULTS' =>'label density')
      || 10;
}

sub do_bump {
  my $self = shift;
  my ($track_name,$option,$count,$max,$length) = @_;

  my $conf              = $self->config;
  my $maxb              = $conf->setting($track_name => 'bump density');
  $maxb                 = $max unless defined $maxb;

  my $maxed_out = $count <= $maxb;
  my $conf_bump = $conf->semantic_setting($track_name => 'bump',$length);
  $option ||= 0;
  return defined $conf_bump ? $conf_bump
      :  $option == 0 ? $maxed_out
      :  $option == 1 ? 0
      :  $option == 2 ? 1
      :  $option == 3 ? 1
      :  $option == 4 ? 2
      :  $option == 5 ? 2
      :  0;
}

sub do_label {
  my $self = shift;
  my ($track_name,$option,$count,$max_labels,$length) = @_;

  my $conf = $self->config;

  my $maxl              = $conf->setting($track_name => 'label density');
  $maxl                 = $max_labels unless defined $maxl;
  my $maxed_out         = $count <= $maxl;

  my $conf_label        = $conf->semantic_setting($track_name => 'label',$length);
  $conf_label           = 1 unless defined $conf_label;

  $option ||= 0;
  return  $option == 0 ? $maxed_out && $conf_label
        : $option == 3 ? $conf_label || 1
	: $option == 5 ? $conf_label || 1
        : 0;
}

sub do_description {
  my $self = shift;
  my ($track_name,$option,$count,$max_labels,$length) = @_;

  my $conf              = $self->config;

  my $maxl              = $conf->setting($track_name => 'label density');
  $maxl                 = $max_labels unless defined $maxl;
  my $maxed_out = $count <= $maxl;

  my $conf_description  = $conf->semantic_setting($track_name => 'description',$length);
  $conf_description     = 0 unless defined $conf_description;
  $option ||= 0;
  return  $option == 0 ? $maxed_out && $conf_description
        : $option == 3 ? $conf_description || 1
        : $option == 5 ? $conf_description || 1
        : 0;
}

# given a feature, return the segment (e.g. chromosome) that it is contained in.
sub whole_segment {
  my $self    = shift;
  my $segment = shift;
  my $factory = $segment->factory;

  # the segment class has been deprecated, but we still must support it
  my $class   = eval {$segment->seq_id->class} || eval{$factory->refclass};

  my ($whole_segment) = $factory->segment(-class=>$class,
					  -name=>$segment->seq_id);
  $whole_segment   ||= $segment;  # just paranoia
  $whole_segment;
}

# fetch a list of Segment objects given a name or range
# (this used to be in gbrowse executable itself)
sub name2segments {
  my $self = shift;
  my ($literal_name,$db,$toomany,$segments_have_priority,$dont_merge) = @_;

  $dont_merge = !$self->setting('merge searches') 
      if defined $self->setting('merge searches');

  $toomany ||= TOO_MANY_SEGMENTS;

  my $max_segment   = $self->get_max_segment;

  my $name = $literal_name;
  my (@segments,$class,$start,$stop);
  if ( ($name !~ /\.\./ and $name =~ /([\w._\/-]+):(-?[-e\d.]+),(-?[-e\d.]+)$/) or
      $name =~ /([\w._\/-]+):(-?[-e\d,.]+?)(?:-|\.\.)(-?[-e\d,.]+)$/) {
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

  my $divisor = $self->config->setting(general=>'unit_divider') || 1;
  $start *= $divisor if defined $start;
  $stop  *= $divisor if defined $stop;

  # automatic classes to try
  my @classes = $class ? ($class) : (split /\s+/,$self->setting('automatic classes')||'');
  my $refclass = $self->setting('reference class') || 'Sequence';

 SEARCHING:
  for my $n ([$name,$class,$start,$stop],[$literal_name,$refclass,undef,undef]) {

    my ($name_to_try,$class_to_try,$start_to_try,$stop_to_try) = @$n;

    # first try the non-heuristic search
    @segments  = $self->_feature_get($db,$name_to_try,$class_to_try,$start_to_try,$stop_to_try,
				     $segments_have_priority,$dont_merge);
    last SEARCHING if @segments;

    # heuristic fetch. Try various abbreviations and wildcards
    my @sloppy_names = $name_to_try;
    if ($name_to_try =~ /^([\dIVXA-F]+)$/) {
      my $id = $1;
      foreach (qw(CHROMOSOME_ Chr chr)) {
	my $n = "${_}${id}";
	push @sloppy_names,$n;
      }
    }

    # try to remove the chr CHROMOSOME_I
    if ($name_to_try =~ /^(chromosome_?|chr)/i) {
      (my $chr = $name_to_try) =~ s/^(chromosome_?|chr)//i;
      push @sloppy_names,$chr;
    }

    # try the wildcard  version, but only if the name is of significant length
    # IMPORTANT CHANGE: we used to put stars at the beginning and end, but this killed performance!
    push @sloppy_names,"$name_to_try*" if length $name_to_try > 3 
	                              and $name_to_try !~ /\*$/ 
				      and !$self->setting('disable wildcards');

    for my $n (@sloppy_names) {
      for my $c (@classes) {
	@segments = $self->_feature_get($db,$n,$c,$start_to_try,$stop_to_try,$segments_have_priority,$dont_merge);
	last SEARCHING if @segments;
      }
    }
  }

  return @segments;
}

sub _feature_get {
  my $self = shift;
  my ($db,$name,$class,$start,$stop,$segments_have_priority,$dont_merge,$f_id) = @_;

  my $refclass = $self->setting('reference class') || 'Sequence';
  $class ||= $refclass;

  my @argv = (-name  => $name);
  push @argv,(-class => $class) if defined $class;
  push @argv,(-start => $start) if defined $start;
  push @argv,(-end   => $stop)  if defined $stop;
  push @argv,(-feature_id => $f_id) if defined $f_id;
  # This step is a hack to turn off relative addressing when getting absolute coordinates on the
  # reference molecule.
  push @argv,(-absolute=>1)     if $class eq $refclass;
  warn "\@argv = @argv" if DEBUG;

  my @segments;
  @segments    = $db->fetch($f_id) if defined $f_id 
      && $db->can('fetch');

  @segments    = $db->get_feature_by_primary_id($f_id) if !@segments 
      && defined $f_id 
      && $db->can('get_feature_by_primary_id');

  if (!@segments) {
      if ($segments_have_priority) {
	  @segments  = grep {$_->length} $db->segment(@argv);
	  @segments  = grep {$_->length} $db->get_feature_by_name(@argv) if !@segments;
      } else {
	  @segments  = grep {$_->length} $db->get_feature_by_name(@argv)  if !defined($start) && !defined($stop);
	  @segments  = grep {$_->length} $db->get_features_by_alias(@argv) if !@segments && !defined($start)
	      && !defined($stop)
	      && $db->can('get_features_by_alias');
	  @segments  = grep {$_->length} $db->segment(@argv)               if !@segments && $name !~ /[*?]/;
      }
  }

  # one last try for Bio::DB::GFF
  if (defined $f_id && defined $name && !@segments) {
    @segments  = grep {$_->length} $db->get_feature_by_name(@argv);
  }

  return unless @segments;

  # Deal with multiple hits.  Winnow down to just those that
  # were mentioned in the config file.
  my $types = $self->_all_types($db);

  my @filtered = 
      grep {
	my $type    = $_->type;
	my $method  = eval {$_->method} || '';
	my $fclass  = eval {$_->class}  || '';
	$type eq 'Segment'      # ugly stuff accomodates loss of "class" concept in GFF3
	  || $type eq 'region'
	    || $types->{$type}
	      || $types->{$method}
		|| !$fclass
		  || $fclass eq $refclass
		    || $fclass eq $class;
      } @segments;


  return @filtered if $dont_merge;

  # consolidate features that have same name and same reference sequence
  # and take the largest one.
  local $^W=0; # uninit variable warning - can't find it
  my %longest;
  foreach (@filtered) {
    my $n   = $_->display_name.$_->abs_ref.(eval{$_->version}||'').(eval{$_->class}||'');
    $longest{$n} = $_ if !defined($longest{$n}) || $_->length > $longest{$n}->length;
  }

  values %longest;
}

sub get_ranges {
  my $self      = shift;
  my $divisor   = $self->setting('unit_divider') || 1;
  my $rangestr  = $self->setting('zoom levels');
  if (!$rangestr) {
    return split /\s+/,DEFAULT_RANGES;
  } elsif ($divisor == 1 ) {
    return split /\s+/,$rangestr;
  } else {
    return map {$_ * $divisor} split /\s+/,$rangestr;
  }
}

sub get_max_segment {
  my $self = shift;
  my $divisor   = $self->setting('unit_divider') || 1;
  my $max_seg   = $self->setting('max segment');
  if (!$max_seg) {
    return MAX_SEGMENT;
  } elsif ($divisor == 1 ) {
    return $max_seg
  } else {
    return $max_seg * $divisor;
  }
}

sub get_default_segment {
  my $self = shift;
  my $divisor   = $self->setting('unit_divider') || 1;
  my $def_seg   = $self->setting('default segment');
  if (!$def_seg) {
    return DEFAULT_SEGMENT;
  } elsif ($divisor == 1 ) {
    return $def_seg
  } else {
    return $def_seg * $divisor;
  }
}

sub _all_types {
  my $self  = shift;
  my $db    = shift;
  return $self->{_all_types} if exists $self->{_all_types}; # memoize
  my %types = map {$_=>1} (
			   (map {$_->get_method}        eval {$db->aggregators}),
			   (map {$self->label2type($_)} $self->labels)
			   );
  return $self->{_all_types} = \%types;
}

# Handle types that are hidden by aggregators so that
# features link correctly when they are subparts rather than
# the top-level part
sub _load_aggregator_types {
  my $self    = shift;
  my $segment = shift;
  return if $self->config->{_load_aggregator_types}++; # don't do it twice
  my $db          = eval {$segment->factory} or return;
  my @aggregators = eval {$db->aggregators } or return;
  for my $a (@aggregators) {
    my $method   = $a->method;
    my @subparts = ($a->part_names,$a->main_name);
    for my $track ($self->type2label($method)) {
      foreach (@subparts) {
	$self->config->{_type2label}{$_}{$track}++;
      }
    }
  }
}


# utility called by hits_on_overview
sub _hits_to_html {
  my $self = shift;
  my ($ref,$gd,$boxes) = @_;
  my ($name, $version) = split /\sversion\s/i, $ref;
  my $source   = $self->source;
  my $self_url = '';   #url(-relative=>1);
  # $self_url   .= "?source=$source";

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
  return unless $ruler->[0];  # don't know why....


  my $length  = $ruler->[0]->length/RULER_INTERVALS;
  $width   = ($ruler->[3]-$ruler->[1])/RULER_INTERVALS;
  for my $i (0..RULER_INTERVALS-1) {
    my $x = $ruler->[1] + $i * $width;
    my $y = $x + $width;
    my $start = int($length * $i);
    my $stop  = int($start + $length);
    my $href      = $self_url . "?ref=$name;start=$start;stop=$stop";
    $href        .= ";version=$version" if defined $version;
    $html .= qq(<area shape="rect" coords="$x,$ruler->[2],$y,$ruler->[4]" href="$href" alt="ruler" />\n);
  }

  foreach (@$boxes){
    my ($start,$stop) = ($_->[0]->start,$_->[0]->end);
    my $href      = $self_url . "?ref=$name;start=$start;stop=$stop";
    $href        .= ";version=$version" if defined $version;
    $html .= qq(<area shape="rect" coords="$_->[1],$_->[2],$_->[3],$_->[4]" href="$href" alt="ruler" />\n);
  }
  $html .= "</map>\n";
  $html;
}

# I know there must be a more elegant way to insert commas into a long number...
sub commas {
  my $i = shift;
  return $i if $i=~ /\D/;
  $i = reverse $i;
  $i =~ s/(\d{3})/$1,/g;
  chop $i if $i=~/,$/;
  $i = reverse $i;
  $i;
}

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

sub overview_pad {
  my $self   = shift;
  my $tracks = shift;

  if ($self->drag_and_drop) { # not relevant when drag and drop is active
    my $padding = $self->image_padding;
    return ($padding,$padding);
  }

  $tracks ||= [$self->config->overview_tracks];
  my $max = 0;
  foreach (@$tracks) {
    my $key = $self->setting($_=>'key');
    next unless defined $key;
    $max = length $key if length $key > $max;
  }
  foreach (@_) {  #extra
    $max = length if length > $max;
  }

  # Tremendous kludge!  Not able to generate overview maps in GD yet
  # This needs to be cleaned...
  my $image_class = 'GD';
  eval "use $image_class";
  return (MIN_OVERVIEW_PAD,MIN_OVERVIEW_PAD) unless $max;
  return ($max * $image_class->gdMediumBoldFont->width + 3,MIN_OVERVIEW_PAD);
}

sub true { 1 }

sub debugging_rectangles {
  my $self = shift;
  my ($image,$boxes) = @_;
  my $red = $image->colorClosest(255,0,0);
  foreach (@$boxes) {
    my @rect = @{$_}[1,2,3,4];
    $image->rectangle(@{$_}[1,2,3,4],$red);
  }
}

# Returns the language code, but only if we have a translate table for it.
sub language_code {
  my $self = shift;
  my $lang = $self->language;
  my $table= $lang->tr_table($lang->language);
  return unless %$table;
  return $lang->language;
}

=head2 error()

  my $error = $browser->error(['new error']);

Retrieve or store an error message. Currently used to pass run-time
errors involving uploaded/remote annotation files.

=cut

sub error {
  my $self = shift; # do nothing
  my $err_msg = shift;
  $err_msg = '' if ref $err_msg;
  $self->{'.err_msg'} = $err_msg;
  $self->{'.err_msg'};
}

sub fatal_error {
    my $self = shift;
    print CGI::header('text/plain'),"@_\n";
    exit 0;
}

=head2 create_panel_args()

  @args = $self->create_panel_args($section,$args);

Return arguments need to create a Bio::Graphics::Panel.
$section is one of 'detail','overview', or 'region'
$args is a hashref that contains the keys:

   keystyle
   title
   image_class
   postgrid
   background

=cut

sub create_panel_args {
  my $self               = shift;
  my ($section,$args) = @_;

  my $segment       = $args->{segment};
  my ($seg_start,$seg_stop,$flip) = $self->segment_coordinates($segment,
							       $args->{flip});

  my $image_class = $args->{image_class} || 'GD';
  eval "use $image_class" unless "${image_class}::Image"->can('new');

  my $keystyle = $self->drag_and_drop($args->{drag_n_drop})
                 ? 'none'
		 : $args->{keystyle} || $self->setting('keystyle') || DEFAULT_KEYSTYLE;

  my @pass_thru_args = map {/^-/ ? ($_=>$args->{$_}) : ()} keys %$args;

  my @argv = (
	      -grid         => 1,
	      -seq_id       => $segment->seq_id,
	      -start        => $seg_start,
	      -end          => $seg_stop,
	      -stop         => $seg_stop,  #backward compatibility with old bioperl
	      -key_color    => $self->setting('key bgcolor')     || 'moccasin',
	      -bgcolor      => $self->setting('detail bgcolor')  || 'white',
	      -width        => $self->width,
	      -key_style    => $keystyle,
	      -empty_tracks => $self->setting('empty_tracks')    || DEFAULT_EMPTYTRACKS,
	      -pad_top      => $args->{title} ? $image_class->gdMediumBoldFont->height : 0,
	      -image_class  => $image_class,
	      -postgrid     => $args->{postgrid}   || '',
	      -background   => $args->{background} || '',
	      -truecolor    => $self->setting('truecolor') || 0,
	      @pass_thru_args,   # position is important here to allow user to override settings
	     );

  push @argv, -flip => 1 if $flip;
  my $p = $self->image_padding;
  my $pl = $self->setting('pad_left');
  my $pr = $self->setting('pad_right');
  $pl    = $p unless defined $pl;
  $pr    = $p unless defined $pr;

  push @argv,(-pad_left =>$pl, -pad_right=>$pr) if $p;


  return (@argv,
	  -pad_top     => 18,
	  -extend_grid => 1)
    if $self->drag_and_drop;

  return @argv;
}

sub image_padding {
  my $self = shift;
  return defined $self->setting('image_padding') ? $self->setting('image_padding')
                                                 : PAD_DETAIL_SIDES;
}

=head2 create_track_args()

  @args = $self->create_track_args($label,$args);

Return arguments need to create a Bio::Graphics::Track.
$label is a config file stanza label for the track.

=cut

sub create_track_args {
  my $self = shift;
  my ($label,$args) = @_;

  my $segment         = $args->{segment};
  my $lang            = $args->{lang};
  my $hilite_callback = $args->{hilite_callback};
  my $override        = $args->{settings}{features}{$label}{override_settings} 
                           || {};   # user-set override settings for tracks
  my @override        = map {'-'.$_ => $override->{$_}} keys %$override;

  my $length = $segment->length;
  my $conf   = $self->config;

  my @default_args = (-glyph => 'generic');
  push @default_args,(-key   => $label)        unless $label =~ /^\w+:/;
  push @default_args,(-hilite => $hilite_callback) if $hilite_callback;

  my @args;
  if ($conf->semantic_setting($label=>'global feature',$length)) {
    @args = ($segment,
	     @default_args,
	     $conf->default_style,
	     $conf->i18n_style($label,
			       $lang),
	     @override,
	    );
  } else {
    @args = (@default_args,
	     $conf->default_style,
	     $conf->i18n_style($label,
			       $lang,
			       $length),
	     @override,
	    );
  }
  return @args;
}

=head2 segment_coordinates()

   ($start,$stop,$flip) = $self->segment_coordinates($segment,$flip)

Method to correct for rare case in which start and stop are flipped.

=cut

sub segment_coordinates {
  my $self    = shift;
  my $segment = shift;
  my $flip    = shift;

  # Create the tracks that we will need
  my ($seg_start,$seg_stop ) = ($segment->start,$segment->end);
  if ($seg_stop < $seg_start) {
    ($seg_start,$seg_stop)     = ($seg_stop,$seg_start);
    $flip = 1;
  }
  return ($seg_start,$seg_stop,$flip);
}

=head2 create_cache_key()

  $cache_key = $self->create_cache_key(@args)

Create a unique cache key for the given args.

=cut

sub create_cache_key {
  my $self = shift;
  my @args = map {$_ || ''} grep {!ref($_)} @_;  # the map gets rid of uninit variable warnings
  return md5_hex(@args);
}

sub get_cache_base {
  my $self            = shift;
  my ($key,$filename) = @_;
  my @comp        = $key =~ /(..)/g;
#  my $rel_path    = join '/',$self->source,'panel_cache',@comp[0..1],$key;
  my $rel_path    = join '/',$self->source,'panel_cache',$comp[0],$key;
  my ($uri,$path) = $self->tmpdir($rel_path);

  return wantarray ? ("$path/$filename","$uri/$filename") : "$path/$filename";
}

sub panel_is_cached {
  my $self  = shift;
  my $key   = shift;
  return unless (my $cache_time = $self->cache_time);
  my $size_file = $self->get_cache_base($key,'size');
  return unless -e $size_file;
  my $mtime    = (stat(_))[9];   # _ is not a bug, but an automatic filehandle
  my $hours_since_last_modified = (time()-$mtime)/(60*60);
  return unless $hours_since_last_modified < $cache_time;
  warn "cache hit for $key" if DEBUG;
  1;
}

=head2 get_cached_panel()

  ($image_uri,$map,$width,$height) = $self->get_cached_panel($cache_key)

Return cached image url, imagemap data, width and height of image.

=cut

sub get_cached_panel {
  my $self = shift;
  my $key  = shift;

  my $map_file                = $self->get_cache_base($key,'map')   or return;
  my $size_file               = $self->get_cache_base($key,'size')  or return;
  my ($image_file,$image_uri) = $self->get_cache_base($key,'image') or return;

  # get map data
  my $map_data = [];
  if (-e $map_file) {
    my $f = IO::File->new($map_file) or return;
    while (my $line = $f->getline) {
      push @$map_data, $line;
    }
    $f->close;
  }

  # get size data
  my ($width,$height);
  if (-e $size_file) {
    my $f = IO::File->new($size_file) or return;
    chomp($width = $f->getline);
    chomp($height = $f->getline);
    $f->close;
  }

  my $base = -e "$image_file.png" ? '.png'
           : -e "$image_file.jpg" ? '.jpg'
	   : -e "$image_file.svg" ? '.svg'
           : '.gif';
  $image_uri  .= $base;
  $image_file .= $base;

  my $gd = GD::Image->new($image_file) unless $image_file =~ /svg$/;
  my $map_html  = $self->map_html(@$map_data);
  return ($image_uri,$map_html,$width,$height,$image_file,$gd,$map_data);
}

# Convert the cached image map data
# into an array structure analogous to
# Bio::Graphics::Panel->boxes
sub map_array {
  my $self = shift;
  my $data = shift;
  chomp @$data;
  my $name = shift @$data or return;
  my $map = [$name];

  for (@$data) {
    my ($type,$x1,$y1,$x2,$y2,@atts) = split "\t";
    pop @atts if @atts % 2;
    my %atts = @atts;
    push @$map, [$type,$x1,$y1,$x2,$y2,\%atts];    
  }
  return $map;
}

# Convert the cached image map data
# into HTML. 
sub map_html {
  my $self = shift;
  my @data = @_;
  chomp @data;
  my $name = shift @data or return '';

#  my $html  = qq(\n<map name="${name}_map" id="${name}_map">\n);
  my $html = '';
  
  for (@data) {
      my @tokens = split "\t";
      push @tokens,undef unless @tokens%2; # ensure an odd number
      my (undef,$x1,$y1,$x2,$y2,%atts) = map {$_||''} @tokens; # get rid of uninit values
      $x1 or next;
      my $coords = join(',',$x1,$y1,$x2,$y2);
      $html .= qq(<area shape="rect" coords="$coords" );
      for my $att (keys %atts) {
	  $html .= qq($att="$atts{$att}" );
      }
      $html .= qq(/>\n);
  }
  
#  $html .= qq(</map>\n);
  return $html;
}

sub map_css {
  my ($self,$data,$view) = @_;
  $data && ref $data eq 'ARRAY' or return;
  my @data = @$data;
  chomp @data;
  my $name = shift @data or return '';

  my $pl = $self->setting('pad_left')|| 0;
  my $pt = $self->setting('pad_top') || 0;

  my $html;
  for (@data) {
      my @elements  = @$_;
      push @elements,'' if @elements%2==0; # get rid of odd-number of elements warning
      my ($ruler,$x1,$y1,$x2,$y2,$atts) = @elements;
      warn "($ruler,$x1,$y1,$x2,$y2,$atts)";
      my %atts = %$atts;
      $x1 or next;
      $x1 += $pl;
      $y1 += $pt;
      my $width  = abs($x2 - $x1);
      my $height = abs($y2 - $y1); 

      next if $ruler eq 'ruler';
      my %style = ( top      => "${y1}px",
		    left     => "${x1}px",
		    cursor   => 'pointer',
		    width    => "${width}px",
		    height   => "${height}px",
		    position => 'absolute');
      
#      my %conf = (name => "${view}_image_map");
      my %conf = ();
      for my $att (keys %atts) {
	  my $val = $atts{$att};
	  if ($att eq 'href') {
	      next if $atts{onclick} || $atts{onmousedown};
	      $att = 'onmousedown';
	      $val = "window.location='$val'";
	      $style{cursor} = 'pointer';
	  }
	  $conf{$att} = $val;
      }
      $conf{style} = _style(%style);
      
      $html .= '<span ';
      for my $label (keys %conf) {
	  $html .= qq($label="$conf{$label}" );
      }
      $html .="></span>\n";
  }

  return $html;
}

sub _style {
  my %h = @_;
  my $style;
  for (keys %h) {
    $style .= join(':',$_,$h{$_}). ';';
  }
  $style;
}


sub set_cached_panel {
  my $self = shift;
  my ($key,$gd,$map_data) = @_;

  my $map_file                = $self->get_cache_base($key,'map')   or return;
  my $size_file               = $self->get_cache_base($key,'size')  or return;
  my ($image_file,$image_uri) = $self->get_cache_base($key,'image') or return;

  # write the map data 
  if ($map_data) {
    my $f = IO::File->new(">$map_file") or die "$map_file: $!";
    $f->print(join("\n", @$map_data),"\n");
    $f->close;
  }

  return unless $gd;

  # get the width and height and write the size data
  my ($width,$height) = $gd->getBounds;
  my $f = IO::File->new(">$size_file") or die "$size_file: $!";
  $f->print($width,"\n");
  $f->print($height,"\n");
  $f->close;

  my $image_data;

  if ($gd->can('svg')) {
    $image_file .= ".svg";
    $image_data = $gd->svg;
  }
  elsif ($gd->can('png')) {
    $image_file .= ".png";
    $image_data = $gd->png;
  }

  elsif ($gd->can('gif')) {
    $image_file .= ".gif";
    $image_data  = $gd->gif;
  }

  elsif ($gd->can('jpeg')) {
    $image_file .= ".jpg";
    $image_data  = $gd->jpeg;
  }

  $f = IO::File->new(">$image_file") or die "$image_file: $!";
  binmode($f);
  $f->print($image_data);
  $f->close;

  return ($image_uri,$map_data,$width,$height,$image_file);
}

# convert bp into nice Mb/Kb units
sub unit_label {
  my $self  = shift;
  my $value = shift;

  my $unit     = $self->setting('units')        || 'bp';
  my $divider  = $self->setting('unit_divider') || 1;
  $value /= $divider;
  my $abs = abs($value);

  my $label;
  $label = $abs >= 1e9  ? sprintf("%.4g G%s",$value/1e9,$unit)
         : $abs >= 1e6  ? sprintf("%.4g M%s",$value/1e6,$unit)
         : $abs >= 1e3  ? sprintf("%.4g k%s",$value/1e3,$unit)
	 : $abs >= 1    ? sprintf("%.4g %s", $value,    $unit)
	 : $abs >= 1e-2 ? sprintf("%.4g c%s",$value*100,$unit)
	 : $abs >= 1e-3 ? sprintf("%.4g m%s",$value*1e3,$unit)
	 : $abs >= 1e-6 ? sprintf("%.4g u%s",$value*1e6,$unit)
	 : $abs >= 1e-9 ? sprintf("%.4g n%s",$value*1e9,$unit)
         : sprintf("%.4g p%s",$value*1e12,$unit);
  if (wantarray) {
    return split ' ',$label;
  } else {
    return $label;
  }
}

# convert Mb/Kb back into bp... or a ratio
sub unit_to_value {
  my $self   = shift;
  my $string = shift;
  my $sign           = $string =~ /out|left/ ? '-' : '+';
  my ($value,$units) = $string =~ /([\d.]+) ?(\S+)/;
  return unless defined $value;
  $value /= 100   if $units eq '%';  # percentage;
  $value *= 1000  if $units =~ /kb/i;
  $value *= 1e6   if $units =~ /mb/i;
  $value *= 1e9   if $units =~ /gb/i;
  return "$sign$value";
}


=head2

   ($region_sizes,$region_labels,$region_default) = $config->region_sizes()

Return information about the region panel:

   1. list of valid region sizes (@$region_sizes)
   2. mapping of size to label   (%$region_labels)
   3. default size               ($region_default)

=cut

sub region_sizes {
  my $self     = shift;
  my $settings = shift;

  my @region_sizes   = sort {$b<=>$a} Bio::Graphics::Browser::Util::shellwords($self->setting('region segments'));
  unless (@region_sizes) {
    my $default      = $self->setting('region segment') || $self->setting('default segment') || 50000;
    @region_sizes    = ($default * 2, $default, int $default/2) unless $default eq 'AUTO';;
  }

  my %region_labels  = map  {$_=>scalar $self->unit_label($_)} @region_sizes;
  my $region_default = $settings->{region_size} || $self->setting('region segment');
  $region_default  ||= $self->setting('default segment');
  
  $region_labels{AUTO} = 'AUTO';
  unshift @region_sizes, 'AUTO';

  return (\@region_sizes,\%region_labels,$region_default);
}

sub clone_feature {
  my $self    = shift;
  my $feature = shift;
  my $clone = Bio::Graphics::Feature->new(-start  => $feature->start,
					  -end    => $feature->end,
					  -strand => $feature->strand,
					  -type   => $feature->primary_tag,
					  -source => $feature->source,
					  -name   => $feature->display_name);
  # transfer attributes if we can
  eval {
    for my $tag ($feature->get_all_tags) {
      my @values = $feature->get_tag_values($tag);
      $clone->add_tag_value($tag=>@values);
      $clone->desc($values[0]) if lc $tag eq 'note';
    }
  };
  warn $@ if $@;

  return $clone;
}

sub coordinate_mapper {
    my $self            = shift;
    my $current_segment = shift;
    my $optimize        = shift;

    my $db              = $current_segment->factory;

    my ($ref,$start,$stop) = ($current_segment->seq_id,
			      $current_segment->start,
			      $current_segment->end);

    my %segments;
    
    my $closure = sub {
	my ($refname,@ranges) = @_;

	unless (exists $segments{$refname}) {
	    my @segments = sort {$a->length<=>$b->length}   # get the longest one
	    map {
		eval{$_->absolute(0)}; $_  # so that rel2abs works properly later
	    }
	    $self->name2segments($refname,$db,TOO_MANY_SEGMENTS,1);
	    $segments{$refname} = $segments[0];
	    return unless @segments;
	}

	my $mapper   = $segments{$refname} || return;
	my $absref   = $mapper->abs_ref;
	my $cur_ref  = eval {$current_segment->abs_ref}
	|| eval{$current_segment->ref};  # account for api changes in Bio::SeqI
	return unless $absref eq $cur_ref;

	my @abs_segs;
	if ($absref eq $refname) {  # doesn't need remapping
	    @abs_segs = @ranges;
	} else {
	    @abs_segs = map {[$mapper->rel2abs($_->[0],$_->[1])]} @ranges;
	}

	# this inhibits mapping outside the displayed region
	if ($optimize) {
	    my $in_window;
	    foreach (@abs_segs) {
		next unless defined $_->[0] && defined $_->[1];
		$in_window ||= $_->[0] <= $stop && $_->[1] >= $start;
	    }
	    return $in_window ? ($absref,@abs_segs) : ();
	} else {
	    return ($absref,@abs_segs);
	}
    };
    return $closure;
}

sub plain_citation {
  my ($self,$label,$truncate) = @_;
  my $text = $self->citation($label,$self->language) || $self->tr('NO_CITATION');
  $text =~ s/\<a/<span/gi;
  $text =~ s/\<\/a/\<\/span/gi;
  if ($truncate) {
    $text =~ s/^(.{$truncate}).+/$1\.\.\./;
  }
  CGI::escape($text);
}

sub search_anchor {
  my $self = shift;
  my $anchor = shift;

  return $self->{'search_anchor'} = $anchor if defined $anchor;
  return $self->{'search_anchor'};
}


package Bio::Graphics::BrowserConfig;
use strict;
use Bio::Graphics::FeatureFile;
use Bio::Graphics::Browser::Util 'shellwords';
use Carp 'croak';
use Socket;  # for inet_aton() call

use vars '@ISA';
@ISA = 'Bio::Graphics::FeatureFile';

sub labels {
  my $self   = shift;

  # Filter out all configured types that correspond to the overview, overview details
  # other non-track configuration and plugins, or other name:value types.
  # Apply restriction rules too
  my @labels =  grep {
    !( $_ eq 'TRACK DEFAULTS' ||          # general track config
       $_ eq 'TOOLTIPS'       ||          # ajax balloon config
       /SELECT MENU/          ||          # rubber-band selection menu config     
       /:(\d+|plugin|DETAILS|details)$/   # plugin, etc config
     )
       && $self->authorized($_)
    }
    $self->configured_types;
  return @labels;
}

sub overview_tracks {
  my $self = shift;
  grep { ($_ eq 'overview' || /:overview$/) && $self->authorized($_) } $self->configured_types;
}

sub regionview_tracks {
  my $self = shift;
  grep { ($_ eq 'region' || /:region$/) && $self->authorized($_) } $self->configured_types;
}

# implement the "restrict" option
sub authorized {
  my $self  = shift;
  my $label = shift;
  my $restrict = $self->setting($label=>'restrict')
    || ($label ne 'general' && $self->setting('TRACK DEFAULTS' => 'restrict'));
  return 1 unless $restrict;
  my $host     = CGI->remote_host;
  my $user     = CGI->remote_user;
  my $addr     = CGI->remote_addr;
  undef $host if $host eq $addr;
  return $restrict->($host,$addr,$user) if ref $restrict eq 'CODE';
  my @tokens = split /\s*(satisfy|order|allow from|deny from|require user|require group|require valid-user)\s+/i,$restrict;
  shift @tokens unless $tokens[0] =~ /\S/;
  my $mode    = 'allow,deny';
  my $satisfy = 'all';
  my (@allow,@deny,%users);
  while (@tokens) {
    my ($directive,$value) = splice(@tokens,0,2);
    $directive = lc $directive;
    $value ||= '';
    if ($directive eq 'order') {
      $mode = $value;
      next;
    }
    my @values = split /[^\w.-]/,$value;
    if ($directive eq 'allow from') {
      push @allow,@values;
      next;
    }
    if ($directive eq 'deny from') {
      push @deny,@values;
      next;
    }
    if ($directive eq 'satisfy') {
      $satisfy = $value;
      next;
    }
    if ($directive eq 'require user') {
      foreach (@values) {
	if ($_ eq 'valid-user' && defined $user) {
	  $users{$user}++;  # ensures that this user will match
	} else {
	  $users{$_}++;
	}
      }
      next;
    }
    if ($user && $directive eq 'require valid-user') {
      $users{$user}++;
    }
    if ($directive eq 'require group') {
      croak "Sorry, but gbrowse does not support the require group limit.  Use a subroutine to implement role-based authentication.";
    }
  }

  my $allow = $mode eq  'allow,deny' 
                ? match_host(\@allow,$host,$addr) && !match_host(\@deny,$host,$addr)
                : 'deny,allow' 
                   ? !match_host(\@deny,$host,$addr) ||  match_host(\@allow,$host,$addr)
		   : croak "$mode is not a valid authorization mode";
  return $allow unless %users;
  $satisfy = 'any'  if !@allow && !@deny;  # no host restrictions

  # prevent unint variable warnings
  $user         ||= '';
  $allow        ||= '';
  $users{$user} ||= '';

  return $satisfy eq 'any' ? $allow || $users{$user}
                           : $allow && $users{$user};
}

sub match_host {
  my ($matches,$host,$addr) = @_;
  my $ok;
  for my $candidate (@$matches) {
    if ($candidate eq 'all') {
      $ok ||= 1;
    } elsif ($candidate =~ /^[\d.]+$/) { # ip match
      $addr      .= '.' unless $addr      =~ /\.$/;  # these lines ensure subnets match correctly
      $candidate .= '.' unless $candidate =~ /\.$/;
      $ok ||= $addr =~ /^\Q$candidate\E/;
    } else {
      $host ||= gethostbyaddr(inet_aton($addr),AF_INET);
      next unless $host;
      $candidate = ".$candidate" unless $candidate =~ /^\./; # these lines ensure domains match correctly
      $host      = ".$host"      unless $host      =~ /^\./;
      $ok ||= $host =~ /\Q$candidate\E$/;
    }
    return 1 if $ok;
  }
  $ok;
}

sub label2type {
  my ($self,$label,$length) = @_;
  my $l = $self->semantic_label($label,$length);
  return Bio::Graphics::Browser::Util::shellwords($self->setting($l,'feature')||$self->setting($label,'feature')||'');
}

sub style {
  my ($self,$label,$length) = @_;
  my $l = $self->semantic_label($label,$length);
  return $l eq $label ? $self->SUPER::style($l) : ($self->SUPER::style($label),$self->SUPER::style($l));
}

# like setting, but obeys semantic hints
sub semantic_setting {
  my ($self,$label,$option,$length) = @_;
  my $slabel = $self->semantic_label($label,$length);
  my $val = $self->setting($slabel => $option) if defined $slabel;
  return $val if defined $val;
  return $self->setting($label => $option);
}

sub semantic_label {
  my ($self,$label,$length) = @_;
  return $label unless defined $length && $length > 0;
  # look for:
  # 1. a section like "Gene:100000" where the cutoff is less than the length of the segment
  #    under display.
  # 2. a section like "Gene" which has no cutoff to use.
  if (my @lowres = map {[split ':']}
      grep {/$label:(\d+)/ && $1 <= $length}
      $self->configured_types)
    {
      ($label) = map {join ':',@$_} sort {$b->[1] <=> $a->[1]} @lowres;
    }
  $label
}

# override inherited in order to be case insensitive
# and to account for semantic zooming
sub type2label {
  my $self           = shift;
  my ($type,$length) = @_;
  $type   ||= '';
  $length ||= 0;

  my @labels;

  @labels = @{$self->{_type2labelmemo}{$type,$length}}
    if defined $self->{_type2labelmemo}{$type,$length};

  unless (@labels) {
    my @array  = $self->SUPER::type2label(lc $type) or return;
    my %label_groups;
    for my $label (@array) {
      my ($label_base,$minlength) = $label =~ /([^:]+):(\d+)/;
      $label_base ||= $label;
      $minlength ||= 0;
      next if defined $length && $minlength > $length;
      $label_groups{$label_base}++;
    }
    @labels = keys %label_groups;
    $self->{_type2labelmemo}{$type,$length} = \@labels;
  }

  return wantarray ? @labels : $labels[0];
}

# override inherited in order to allow for semantic zooming
sub feature2label {
  my $self = shift;
  my ($feature,$length) = @_;
  my $type  = eval {$feature->type}
    || eval{$feature->source_tag} || eval{$feature->primary_tag} or return;

  (my $basetype = $type) =~ s/:.+$//;
  my @label = $self->type2label($type,$length);

  # WARNING: if too many features start showing up in tracks, uncomment
  # the following line and comment the one after that.
  #@label    = $self->type2label($basetype,$length) unless @label;
  push @label,$self->type2label($basetype,$length);

  @label    = ($type) unless @label;

  # remove duplicate labels
  my %seen;
  @label = grep {! $seen{$_}++ } @label; 

  wantarray ? @label : $label[0];
}

sub invert_types {
  my $self = shift;
  my $config  = $self->{config} or return;
  my %inverted;
  for my $label (keys %{$config}) {
#    next if $label=~/:?(overview|region)$/;   # special case
    my $feature = $config->{$label}{'feature'} or next;
    foreach (Bio::Graphics::Browser::Util::shellwords($feature||'')) {
      $inverted{lc $_}{$label}++;
    }
  }
  \%inverted;
}

sub default_labels {
  my $self = shift;
  my $defaults = $self->setting('general'=>'default features');
  return Bio::Graphics::Browser::Util::shellwords($defaults||'');
}

# return a hashref in which keys are the thresholds, and values are the list of
# labels that should be displayed
sub summary_mode {
  my $self = shift;
  my $summary = $self->settings(general=>'summary mode') or return {};
  my %pairs = $summary =~ /(\d+)\s+{([^\}]+?)}/g;
  foreach (keys %pairs) {
    my @l = Bio::Graphics::Browser::Util::shellwords($pairs{$_}||'');
    $pairs{$_} = \@l
  }
  \%pairs;
}

# override make_link to allow for code references
sub make_link {
  my $self     = shift;
  my ($feature,$panel,$label,$data_source,$track)  = @_;

  $data_source ||= $self->source();

  if ($feature->can('url')) {
    my $link = $feature->url;
    return $link if defined $link;
  }

  return $label->make_link($feature) 
      if $label
      && $label =~ /^[a-zA-Z_]/
      && $label->isa('Bio::Graphics::FeatureFile');

  $panel ||= 'Bio::Graphics::Panel';
  $label ||= $self->feature2label($feature);

  # most specific -- a configuration line
  my $link     = $self->setting($label,'link');

  # less specific - a smart feature
  $link        = $feature->make_link if $feature->can('make_link') && !defined $link;

  # general defaults
  $link        = $self->setting('TRACK DEFAULTS'=>'link') unless defined $link;
  $link        = $self->setting(general=>'link')          unless defined $link;


  return unless $link;

  if (ref($link) eq 'CODE') {
    my $val = eval {$link->($feature,$panel,$track)};
    $self->_callback_complain($label=>'link') if $@;
    return $val;
  }
  elsif (!$link || $link eq 'AUTO') {
    my $n     = $feature->display_name;
    unless (defined $n) {
      my @aliases = eval {$feature->attributes('Alias')},eval{$feature->load_id},eval{$feature->primary_id};
      $n = $aliases[0];
    }
    my $c     = $feature->seq_id;
    my $name  = CGI::escape("$n");  # workaround CGI.pm bug
    my $class = eval {CGI::escape($feature->class)}||'';
    my $ref   = CGI::escape("$c");  # workaround again
    my $start = CGI::escape($feature->start);
    my $end   = CGI::escape($feature->end);
    my $src   = CGI::escape($feature->can('source_tag') ? $feature->source_tag : '');
    my $f_id  = $feature->can('feature_id')  ? CGI::escape($feature->feature_id)
               :$feature->can('primary_id')  ? CGI::escape($feature->primary_id)
               :$feature->can('primary_key') ? CGI::escape($feature->primary_key)
               :undef;

    my $url = "../../gbrowse_details/$data_source?name=$name;class=$class;ref=$ref;start=$start;end=$end";
    if (defined $f_id) {
      return $url . ";feature_id=$f_id";
    }
    else {
      return $url;
    }
  }

  return $self->link_pattern($link,$feature,$panel);
}

# make the title for an object on a clickable imagemap
sub make_title {
  my $self = shift;
  my ($feature,$panel,$label,$track) = @_;
  local $^W = 0;  # tired of uninitialized variable warnings

  my ($title,$key) = ('','');

 TRY: {
    if ($label 
	&& $label =~ /^[a-zA-Z_]/ 
	&& $label->isa('Bio::Graphics::FeatureFile')) {
	$key   = $label->name;
	$key   =~ s/^(http|ftp)://;
	$title = $label->make_title($feature) or last TRY;
	return $title;
    }

    else {
      $label     ||= $self->feature2label($feature) or last TRY;
      $key       ||= $self->setting($label,'key') || $label;
      $key         =~ s/s$//;
      $key         = "(".
	  $feature->segment->dsn.")" if $feature->isa('Bio::Das::Feature');  # for DAS sources
      $key         =~ s/^(http|ftp)://;

      my $link     = $self->setting($label,'title')
	|| $self->setting('TRACK DEFAULTS'=>'title')
	  || $self->setting(general=>'title');
      if (defined $link && ref($link) eq 'CODE') {
	$title       = eval {$link->($feature,$panel,$track)};
	$self->_callback_complain($label=>'title') if $@;
	return $title if defined $title;
      }      return $self->link_pattern($link,$feature) if $link && $link ne 'AUTO';
    }
  }

  # otherwise, try it ourselves
  $title = eval {
    if ($feature->can('target') && (my $target = $feature->target)) {
      join (' ',
	    "$key:",
	    $feature->seq_id.':'.
	    $feature->start."..".$feature->end,
	    $feature->target->seq_id.':'.
	    $feature->target->start."..".$feature->target->end);
    } else {
	my ($start,$end) = ($feature->start,$feature->end);
	($start,$end)    = ($end,$start) if $feature->strand < 0;
	join(' ',
	     "$key:",
	     $feature->can('display_name') ? $feature->display_name : $feature->info,
	     ($feature->can('seq_id')      ? $feature->seq_id : $feature->location->seq_id)
	     .":".
	     (defined $start ? $start : '?')."..".(defined $end ? $end : '?')
	    );
    }
  };
  warn $@ if $@;

  return $title;
}

sub balloon_tip_setting {
  my $self = shift;
  my ($option,$label,$feature,$panel,$track) = @_;
  $option ||= 'balloon tip';
  my $value;

  
 TRY: {
     if ($label 
	 && $label =~ /^[a-zA-Z_]/
	 && $label->isa('Bio::Graphics::FeatureFile')) { # a feature file
	 $value ||= $label->setting($_=>$option) foreach $label->feature2label($feature);
     }
     last TRY if $value;
     
     for $label ($label, 'TRACK DEFAULTS','general') {
	 $value = $self->setting($label=>$option);
	 last TRY if $value;
     }
  }

  return unless $value;
  my $val;
  my $balloon_type = 'balloon';

  if (ref($value) eq 'CODE') {
    $val = eval {$value->($feature,$panel,$track)};
    $self->_callback_complain($label=>$option) if $@;
  }
  # catch callbacks for custom balloons
  elsif (my($text,$callback) = $value =~ /^(.+?)(sub\s*(\(\$\$\))*\s*\{.+)/) {
    my $package         = $self->base2package;
    my $coderef         = eval "package $package; $callback";
    $self->_callback_complain($label,$option) if $@;
    my $callback_text = $coderef->($feature,$panel,$track);
    $val = join(' ',$text,$callback_text);
  }
  else {
    $val = $self->link_pattern($value,$feature,$panel);
  }

  if ($val=~ /^\s*\[([\w\s]+)\]\s+(.+)/s) {
    $balloon_type = $1;
    $val          = $2;
  }
  # escape quotes
  $val =~ s/\'/\\'/g;
  $val =~ s/"/\&#34;/g;

  return ($balloon_type,$val);
}

sub make_link_target {
  my $self = shift;
  my ($feature,$panel,$label,$track) = @_;

  if ($feature->isa('Bio::Das::Feature')) { # new window
    my $dsn = $feature->segment->dsn;
    $dsn =~ s/^.+\///;
    return $dsn;
  }

  $label    ||= $self->feature2label($feature) or return;
  my $link_target = $self->setting($label,'link_target')
    || $self->setting('TRACK DEFAULTS' => 'link_target')
    || $self->setting(general => 'link_target');
  $link_target = eval {$link_target->($feature,$panel,$track)} 
      if ref($link_target) eq 'CODE';
  $self->_callback_complain($label=>'link_target') if $@;
  return $link_target;
}

sub default_style {
  my $self = shift;
  return $self->SUPER::style('TRACK DEFAULTS');
}

# return language-specific options
sub i18n_style {
  my $self      = shift;
  my ($label,$lang,$length) = @_;
  return $self->style($label,$length) unless $lang;

  my $charset   = $lang->tr('CHARSET');

  # GD can't handle non-ASCII/LATIN scripts transparently
  return $self->style($label,$length) 
    if $charset && $charset !~ /^(us-ascii|iso-8859)/i;

  my @languages = $lang->language;

  push @languages,'';
  # ('fr_CA','fr','en_BR','en','')

  my $idx = 1;
  my %priority = map {$_=>$idx++} @languages;
  # ('fr-ca'=>1, 'fr'=>2, 'en-br'=>3, 'en'=>4, ''=>5)

  my %options  = $self->style($label,$length);
  my %lang_options = map { $_->[1] => $options{$_->[0]} }
    sort { $b->[2]<=>$a->[2] }
     map { my ($option,undef,$lang) = /^(-[^:]+)(:(\w+))?$/; [$_ => $option, $priority{$lang||''}||99] }
       keys %options;
  %lang_options;
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

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut
