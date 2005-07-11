package Bio::Graphics::Browser;
# $Id: Browser.pm,v 1.167.4.13 2005-07-11 16:28:44 lstein Exp $
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
use Carp qw(carp croak);
#use GD 'gdMediumBoldFont','gdLargeFont';
use CGI qw(img param escape unescape url);
use Digest::MD5 'md5_hex';
use File::Path 'mkpath';
use Text::Shellwords;
use Bio::Graphics::Browser::I18n;

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

use constant DEBUG => 0;

if( $ENV{MOD_PERL} && 
    $ENV{MOD_PERL} =~ /mod_perl\/(\d+\.\d+)/ && 
    $1 > 1.98 ) { 
    require Apache::SubRequest;
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
  my @conf_files = map { "$conf_dir/$_" } grep {/\.$suffix$/} grep {$_ !~ /log4perl/} readdir(D);
  close D;

  # try to work around a bug in Apache/mod_perl which appears when
  # running under linux/glibc 2.2.1
  unless (@conf_files) {
    @conf_files = glob("$conf_dir/*.$suffix");
  }

  # get modification times
  my %mtimes     = map { $_ => (stat($_))[9] } @conf_files;

  for my $file (sort {$a cmp $b} @conf_files) {
    my $basename = basename($file,".$suffix");
    $basename =~ s/^\d+\.//;
    next if defined($self->{conf}{$basename}{mtime})
      && ($self->{conf}{$basename}{mtime} >= $mtimes{$file});
    my $config = Bio::Graphics::BrowserConfig->new(-file => $file,-safe=>1) or next;
    $self->{conf}{$basename}{data}  = $config;
    $self->{conf}{$basename}{mtime} = $mtimes{$file};
    $self->{conf}{$basename}{path}  = $file;
    $self->{source}               ||= $basename if $config->authorized('general');
  }
  $self->{width} = DEFAULT_WIDTH;
  $self->{dir}   = $conf_dir;
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
  my @authorized = grep {$conf->{$_}{data}->authorized('general')} @sources;

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
  my $self = shift;
  my @args = @_;
  if (@args == 1) {
    unshift @args,'general';
  } else {
    $args[0] = 'general'
      if $args[0] ne 'general' && lc($args[0]) eq 'general';  # buglet
  }
  my $config = $self->config or return;
  $config->setting(@args);
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

  my $args    = $self->config->code_setting(general => 'db_args');
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

  if (defined (my $a = $self->setting('aggregators'))) {
    my @aggregators = shellwords($a||'');
    push @argv,(-aggregator => \@aggregators);
  }

  ($adaptor,@argv);
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
  $self->{cached_data}{labels} ||= [$self->config->labels];
  my @labels = @{$self->{cached_data}{labels}};
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
    }
  }
  $c ||= $config->setting($label=>'citation');
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
  my $header = $self->config->code_setting(general => 'header');
  if (ref $header eq 'CODE') {
    my $h = eval{$header->(@_)};
    warn $@ if $@;
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
  my $footer = $self->config->code_setting(general => 'footer');
  if (ref $footer eq 'CODE') {
    my $f = eval {$footer->(@_)};
    warn $@ if $@;
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
  my $source = $self->source;
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
  my ($feature,$panel,$label) = @_;
  my @results = $self->config->make_link($feature,$panel,$self->source,$label);
  return wantarray ? @results : $results[0];
}

=head2 render_html()

  ($image,$image_map) = $browser->render_html(%args);

Render an image and an image map according to the options in %args.
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
                        tracks arrayref in order for render_html() to
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

Any arguments names that begin with an initial - (hyphen) are passed
through to Bio::Graphics::Panel->new() directly

Any arguments names that begin with an initial - (hyphen) are passed
through to Bio::Graphics::Panel->new() directly

=cut

sub render_html {
  my $self = shift;
  my %args = @_;

  my $segment         = $args{segment};
  my $do_map          = $args{do_map};
  my $do_centering_map= $args{do_centering_map};

  return unless $segment;
  my($image,$map,$panel,$tracks) = $self->image_and_map(%args);

  $self->debugging_rectangles($image,$map) if DEBUG;

  my ($width,$height) = $image->getBounds;
  my $url     = $self->generate_image($image);
  my $img     = img({-src=>$url,-align=>'middle',-usemap=>'#hmap',-width=>$width,
		     -height=>$height,-border=>0,-name=>'detailedView',-alt=>'detailed view'});
  my $img_map = '';
  if ($do_map) {
    $self->_load_aggregator_types($segment);
    $img_map = $self->make_map($map,$do_centering_map,$panel,$tracks)
  }
  eval {$panel->finished};  # should quash memory leaks when used in conjunction with bioperl 1.4
  return wantarray ? ($img,$img_map) : join "<br>",$img,$img_map;
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
  my $extension = $image->can('png') ? 'png' : 'gif';
  my $data      = $image->can('png') ? $image->png : $image->gif;
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
  return $url;
}

=head2 gd_cache_path()

 my $path = $browser->gd_cache_path($cache_name,@keys)

Return path to a GD cache file.  $cache_name is a cache expiration
option in the config file (currently only 'cache_overview'), and @keys
are settings that make the file unique, such as the list of tracks
that are activated.

=cut

sub gd_cache_path {
  my $self = shift;
  my ($cache_name,@keys) = @_;
  return unless $self->config->setting(general=>$cache_name);
  my $signature = md5_hex(@keys);
  my ($uri,$path) = $self->tmpdir($self->source.'/cache_overview');
  my $extension   = 'gd';
  return "$path/$signature.$extension";
}

=head2 gd_cache_check()

 my $gd = $browser->gd_cache_check($cache_name,$path)

Returns a GD file if its cached version is still valid.

=cut

sub gd_cache_check {
  my $self = shift;
  my ($cache_name,$path) = @_;
  return if param('nocache');
  my $cache_file_mtime   = (stat($path))[9] || 0;
  my $conf_file_mtime    = $self->mtime;
  my $cache_expiry       = $self->config->setting(general=>$cache_name) * 60*60;  # express expiry time as seconds
  if ($cache_file_mtime && ($cache_file_mtime > $conf_file_mtime) && (time() - $cache_file_mtime < $cache_expiry)) {
    my $gd = GD::Image->newFromGd($path);
    return $gd;
  }
  else {
    return;
  }
}

=head2 gd_cache_write()

 my $gd = $browser->gd_cache_write($cache_path,$gd)

Write a GD file into the indicated path.

=cut

sub gd_cache_write {
  my $self = shift;
  my $path = shift or return;
  my $gd   = shift;
  my $file = IO::File->new(">$path") or return;
  print $file $gd->gd;
  close $file;
}

=head2 clear_cache()

 $browser->clear_cache;

Clears out cached per-request values that might take some time to
compute, such as per-track authorization information.  This is only
relevant when gbrowse is run under a persistent environment such as
mod_perl.  It is ordinarily called internally by the open_config()
routine in Bio::Graphics::Browser::Util.

=cut

sub clear_cache {
  my $self = shift;
  delete $self->{cached_data};
}

sub tmpdir {
  my $self = shift;

  my $path = shift || '';
  my $tmpuri = $self->setting('tmpimages') or die "no tmpimages option defined, can't generate a picture";
  $tmpuri .= "/$path" if $path;
  my $tmpdir;
  if ($ENV{MOD_PERL} ) {
      my $r          = Apache->request;
      my $subr       = $r->lookup_uri($tmpuri);
      $tmpdir        = $subr->filename;
      my $path_info  = $subr->path_info;
      $tmpdir       .= $path_info if $path_info;
  } else {
    $tmpdir = "$ENV{DOCUMENT_ROOT}/$tmpuri";
  }
  # we need to untaint tmpdir before calling mkpath()
  return unless $tmpdir =~ /^(.+)$/;
  $path = $1;

  mkpath($path,0,0777) unless -d $path;
  return ($tmpuri,$path);
}

sub make_map {
  my $self = shift;
  my ($boxes,$centering_map,$panel,$tracks) = @_;
  my %track2label = reverse %$tracks;
  my $map = qq(<map name="hmap" id="hmap">\n);

  my $flip = $panel->flip;

  my $did_map;

  local $^W = 0; # avoid uninit variable warnings due to poor coderefs

  foreach (@$boxes){
    next unless $_->[0]->can('primary_tag');

    # use the scale as a centering mechanism
    # potential fragility here: we are depending on the arrow being
    # the very first box that is returned to us.
    if ($centering_map && !$did_map++) {
      $map .= $self->make_centering_map($_,$flip) if $centering_map;
      next;
    }

    my $label  = $_->[5] ? $track2label{$_->[5]} : '';
    my $href   = $self->make_href($_->[0],$panel,$label) or next;
    my $alt    = unescape($self->make_title($_->[0],$panel,$label));
    my $target = $self->config->make_link_target($_->[0],$panel,$label);
    my $t      = defined($target) ? qq(target="$target") : '';
    $map .= qq(<area shape="rect" coords="$_->[1],$_->[2],$_->[3],$_->[4]" href="$href" title="$alt" alt="$alt" $t/>\n);
  }
  $map .= "</map>\n";
  $map;
}

# this creates image map for rulers and scales, where clicking on the scale
# should center the image on the scale.
sub make_centering_map {
  my $self   = shift;
  my $ruler  = shift;
  my $flip   = shift;

  return if $ruler->[3]-$ruler->[1] == 0;

  my $length = $ruler->[0]->length;
  my $offset = $ruler->[0]->start;
  my $end    = $ruler->[0]->end;
  my $scale  = $length/($ruler->[3]-$ruler->[1]);
  my $pl     = $ruler->[-1]->panel->pad_left;

  # divide into RULER_INTERVAL intervals
  my $portion = ($ruler->[3]-$ruler->[1])/RULER_INTERVALS;
  my $ref    = $ruler->[0]->seq_id;
  my $source = $self->source;
  my $plugin = escape(param('plugin')||'');

  my @lines;
  for my $i (0..RULER_INTERVALS-1) {
    my $x1 = $pl + int($portion * $i+0.5);
    my $x2 = $pl + int($portion * ($i+1)+0.5);
    # put the middle of the sequence range into the middle of the picture
    my $middle = $flip ? $end - $scale * ($x1+$x2)/2 : $offset + $scale * ($x1+$x2)/2;
    my $start  = int($middle - $length/2);
    my $stop   = int($start  + $length - 1);
    my $url = "?ref=$ref;start=$start;stop=$stop;nav4=1;plugin=$plugin";
    $url .= ";flip=1" if $flip;
    push @lines,
      qq(<area shape="rect" coords="$x1,$ruler->[2],$x2,$ruler->[4]" href="$url" title="recenter" alt="recenter" />\n);
  }
  return join '',@lines;
}

sub make_href {
  my $self = shift;
  my ($feature,$panel,$label)   = @_;
  return $self->make_link($feature,$panel,$label);
}

sub make_title {
  my $self             = shift;
  my ($feature,$panel,$label) = @_;
  return $feature->make_title if $feature->can('make_title');
  return $self->config->make_title($feature,$panel,$label);
}

# Generate the image and the box list, and return as a two-element list.
# arguments: a key=>value list
#    'segment'       A feature iterator that responds to next_seq() methods
#    'feature_files' A hash of Bio::Graphics::FeatureFile objects containing 3d party features
#    'options'       An hashref of options, where 0=auto, 1=force no bump, 2=force bump, 3=force label
#                       4=force fast bump, 5=force fast bump and label
#    'limit'         Place a limit on the number of features of each type to show.
#    'tracks'        List of named tracks, in the order in which they are to be shown
#    'label_scale'   If true, prints chromosome name next to scale
#    'title'         A title for the image
#    'noscale'       Suppress scale entirely
#    'image_class'   Optional image class for generating SVG output (by passing GD::SVG)
#
# any arguments that begin with an initial - (hyphen) are passed through to Panel->new
# directly
#
sub image_and_map {
  my $self    = shift;
  my %config  = @_;

  my $segment       = $config{segment};
  my $feature_files = $config{feature_files} || {};
  my $tracks        = $config{tracks}        || [];
  my $options       = $config{options}       || {};
  my $limit         = $config{limit}         || {};
  my $lang          = $config{lang} || $self->language;
  my $keystyle      = $config{keystyle};
  my $title         = $config{title};
  my $flip          = $config{flip};
  my $suppress_scale= $config{noscale};
  my $hilite_callback = $config{hilite_callback};
  my $image_class   = $config{image_class} || 'GD';

  $segment->factory->debug(1) if DEBUG;

  # Bring in the appropriate package - just for the fonts. Ugh.
  eval "use $image_class";

  # these are natively configured tracks
  my @labels = $self->labels;

  my $width = $self->width;
  my $conf  = $self->config;
  my $max_labels     = $self->label_density;
  my $max_bump       = $self->bump_density;
  my $length         = $segment->length;

  my @feature_types = map { $conf->label2type($_,$length) } @$tracks;
  my %filters = map { my %conf =  $conf->style($_); 
		      $conf{'-filter'} ? ($_ => $conf{'-filter'})
			               : ($_ => \&true)
		      } @$tracks;

  # Create the tracks that we will need
  my ($seg_start,$seg_stop ) = ($segment->start,$segment->end);
  if ($seg_stop < $seg_start) {
    ($seg_start,$seg_stop)     = ($seg_stop,$seg_start);
    $flip = 1;
  }

   my @pass_thru_args = map {/^-/ ? ($_=>$config{$_}) : ()} keys %config;
  my @argv = (
	      @pass_thru_args,
	      -start     => $seg_start,
	      -end       => $seg_stop,
	      -stop      => $seg_stop,  #backward compatibility with old bioperl
	      -key_color => $self->setting('key bgcolor')     || 'moccasin',
	      -bgcolor   => $self->setting('detail bgcolor')  || 'white',
	      -width     => $width,
	      -grid      => 1,
	      -key_style    => $keystyle || $conf->setting(general=>'keystyle') || DEFAULT_KEYSTYLE,
	      -empty_tracks => $conf->setting(general=>'empty_tracks') 	        || DEFAULT_EMPTYTRACKS,
	      -pad_top      => $title ? $image_class->gdMediumBoldFont->height : 0,
	      -image_class  => $image_class,
	     );

  push @argv, -flip => 1 if $flip;
  my $p = defined $conf->setting(general=>'image_padding') ? $conf->setting(general=>'image_padding')
                                                           : PAD_DETAIL_SIDES;
  push @argv,(-pad_left =>$p, -pad_right=>$p) if $p;

  my $panel = Bio::Graphics::Panel->new(@argv);

  $panel->add_track($segment   => 'arrow',
		    -double    => 1,
		    -tick      => 2,
		    -label     => $config{label_scale} ? $segment->seq_id : 0,
		    -units     => $conf->setting(general=>'units') || '',
		    -unit_divider => $conf->setting(general=>'unit_divider') || 1,
		   ) unless $suppress_scale;

  my (%tracks,@blank_tracks);

  for (my $i= 0; $i < @$tracks; $i++) {

    my $label = $tracks->[$i];

    # if we don't have a built-in label, then this is a third party annotation
    if (my $ff = $feature_files->{$label}) {
      push @blank_tracks,$i;
      next;
    }

    # if the glyph is the magic "dna" glyph (for backward compatibility), or if the section
    # is marked as being a "global feature", then we apply the glyph to the entire segment
    if ($conf->setting($label=>'global feature')) {
      $panel->add_track($segment,
			$conf->default_style,
			$conf->i18n_style($label,$lang),
			);
    }

    else {
      my @settings = ($conf->default_style,$conf->i18n_style($label,$lang,$length));
      push @settings,(-hilite => $hilite_callback) if $hilite_callback;
      my $track = $panel->add_track(-glyph => 'generic',@settings);
      $tracks{$label}  = $track;
    }

  }

  if (@feature_types) {  # don't do anything unless we have features to fetch!

    my $iterator = $segment->get_feature_stream(-type=>\@feature_types);
    warn "feature types = @feature_types\n" if DEBUG;
    my (%groups,%feature_count,%group_pattern);

    while (my $feature = $iterator->next_seq) {

      warn "next feature = $feature, type = ",$feature->type,' method = ',$feature->method,
	' start = ',$feature->start,' end = ',$feature->end,"\n" if DEBUG;

      # allow a single feature to live in multiple tracks
      for my $label ($self->feature2label($feature,$length)) {
	my $track = $tracks{$label}  or next;
	$filters{$label}->($feature) or next;

	warn "feature = $feature, label = $label, track = $track\n" if DEBUG;

	$feature_count{$label}++;

	# Handle name-based groupings.  Since this occurs for every feature
	# we cache the pattern data.
	warn "$track group pattern => ",$conf->code_setting($label => 'group_pattern') if DEBUG;
	exists $group_pattern{$label} or $group_pattern{$label} = $conf->code_setting($label => 'group_pattern');
	
	if (defined $group_pattern{$label}) {
	  push @{$groups{$label}},$feature;
	  next;
	}

	$track->add_feature($feature);
      }
    }

    # handle pattern-based group matches
     for my $label (keys %groups) {
       my $set     = $groups{$label};
       my $pattern = $group_pattern{$label} or next;
       $pattern =~ s!^/(.+)/$!$1!;  # clean up regexp delimiters
       my %pairs;
       for my $a (@$set) {
	 (my $base = $a->name) =~ s/$pattern//i;
 	push @{$pairs{$base}},$a;
       }
       my $track = $tracks{$label};
       foreach (values %pairs) {
	 $track->add_group($_);
       }
     }

    # configure the tracks based on their counts
    for my $label (keys %tracks) {
      next unless $feature_count{$label};

      $options->{$label} ||= 0;

      my $count = $feature_count{$label};
      $count    = $limit->{$label} if $limit->{$label} && $limit->{$label} < $count;

      my $do_bump  = $self->do_bump($label, $options->{$label},$count,$max_bump);
      my $do_label = $self->do_label($label,$options->{$label},$count,$max_labels,$length);
      my $do_description = $self->do_description($label,$options->{$label},$count,$max_labels,$length);

      $tracks{$label}->configure(-bump  => $do_bump,
				 -label => $do_label,
				 -description => $do_description,
				);
      $tracks{$label}->configure(-connector  => 'none') if !$do_bump;
      $tracks{$label}->configure(-bump_limit => $limit->{$label}) 
	if $limit->{$label} && $limit->{$label} > 0;
    }
  }

  # add additional features, if any
  my $offset = 0;
  my $select = sub {
    my $file  = shift;
    my $type  = shift;
    my $section = $file->setting($type=>'section');
    return 1 unless defined $section;
    return $section =~ /detail/;
  };
  for my $track (@blank_tracks) {
    my $file = $feature_files->{$tracks->[$track]} or next;
    ref $file or next;
    $track += $offset + 1;
    my $name = $file->name || '';
    $options->{$name} ||= 0;
    my $inserted = $file->render($panel,$track,$options->{$name},
				 $max_bump,$max_labels,
				 $select
				);
    $offset += $inserted;
  }

  my $gd = $panel->gd;

  if ($title) {
    my $x = ($width - length($title) * $image_class->gdMediumBoldFont->width)/2;
    $gd->string($image_class->gdMediumBoldFont,$x,0,$title,$panel->translate_color('black'));
  }
  return $gd   unless wantarray;

  my $boxes    = $panel->boxes;

  return ($gd,$boxes,$panel,\%tracks);
}

=head2 overview()

  ($gd,$length) = $browser->overview($segment,$track_options);

This method generates a GD::Image object containing the image data for
the overview panel.  Its argument is a Bio::DB::GFF::Segment (or
Bio::Das::SegmentI) object. It returns a two element list consisting
of the image data and the length of the segment (in bp).

In the configuration file, any section labeled "[something:overview]"
will be added to the overview panel.

=cut

# generate the overview, if requested, and return it as a GD
sub overview {
  my $self = shift;
  $self->_overview('overview',@_);
}

# generate the regionview, if requested, and return it as a GD
sub regionview {
  my $self = shift;
  $self->_overview('region',@_);
}

sub _overview {
  my $self = shift;
  my ($region_name,$segment,$partial_segment,$track_options,$feature_files) = @_;
  my $gd;

  # Temporary kludge until I can figure out a more
  # sane way of rendering overview with SVG...
  my $image_class = 'GD';
  eval "use $image_class";

  my $conf           = $self->config;
  my $width          = $self->width;
  my @tracks         = grep {$track_options->{$_}{visible}} 
    $region_name eq 'region' ? $conf->regionview_tracks : $conf->overview_tracks;

  my ($padl,$padr)   = $self->overview_pad(\@tracks);

  my $panel = Bio::Graphics::Panel->new(-segment => $segment,
					-width   => $width,
					-bgcolor => $self->setting('overview bgcolor')
					|| 'wheat',
					-key_style => 'left',
					-pad_left  => $padl,
					-pad_right => $padr,
					-pad_bottom => PAD_OVERVIEW_BOTTOM,
					-image_class=> $image_class,
					-auto_pad   => 0,
				       );

  # cache check so that we can cache the overview images
  my $cache_path;
  $cache_path = $self->gd_cache_path('cache_overview',$segment,
				     @tracks,$width,
				     map {@{$track_options->{$_}}{'options','limit','visible'}
					} @tracks);
  $gd         = $self->gd_cache_check('cache_overview',$cache_path) if $cache_path;

  # no cached data, so do it ourselves
  unless ($gd) {

    my $units = $self->setting('overview units');
    $panel->add_track($segment,
		      -glyph     => 'arrow',
		      -double    => 1,
		      -label     => "\u$region_name\E of ".$segment->seq_id,
		      -labelfont => $image_class->gdMediumBoldFont,
		      -tick      => 2,
		      -units     => $conf->setting(general=>'units') ||'',
		      -unit_divider => $conf->setting(general=>'unit_divider') || 1,
		     );

    $self->_add_landmarks(\@tracks,$panel,$segment,$track_options);

    # add uploaded files that have the "(over|region)view" option set
    if ($feature_files) {
      my $select = sub {
	my $file  = shift;
	my $type  = shift;
	my $section = $file->setting($type=>'section') || '';
	return defined $section && $section =~ /$region_name/;
      };
      foreach (keys %$feature_files) {
	my $ff = $feature_files->{$_};
	next unless $ff->isa('Bio::Graphics::FeatureFile'); #only FeatureFile supports this
	$ff->render($panel,-1,$track_options->{$_},undef,undef,$select);
      }
    }

    $gd = $panel->gd;
    $self->gd_cache_write($cache_path,$gd) if $cache_path;
  }

  my $red = $gd->colorClosest(255,0,0);
  my ($x1,$x2) = $panel->map_pt($partial_segment->start,$partial_segment->end);
  my ($y1,$y2) = (0,($gd->getBounds)[1]);
  $x2 = $panel->right-1 if $x2 >= $panel->right;
  my $pl = $panel->can('auto_pad') ? $panel->pad_left : 0;

  $gd->rectangle($pl+$x1,$y1,
		 $pl+$x2,$y2-1,
		 $red);

  eval {$panel->finished};  # should quash memory leaks when used in conjunction with bioperl 1.4

  return ($gd,$segment->length);
}

sub add_overview_landmarks {
  my $self = shift;
  my ($panel,$segment,$options) = @_;
  my @tracks = $self->config->overview_tracks;
  $self->_add_landmarks(\@tracks,$panel,$segment,$options);
}

sub add_regionview_landmarks {
  my $self = shift;
  my ($panel,$segment,$options) = @_;
  my @tracks = $self->config->regionview_tracks;
  $self->_add_landmarks(\@tracks,$panel,$segment,$options);
}

sub _add_landmarks {
  my $self = shift;
  my ($tracks_to_add,$panel,$segment,$options) = @_;
  my $conf = $self->config;
  my @tracks = grep {$options->{$_}{visible}} @$tracks_to_add;

  my (@feature_types,%type2track,%track);

  for my $overview_track (@tracks) {
    my @types = $conf->label2type($overview_track);
    my $track = $panel->add_track(-glyph  => 'generic',
				  -height  => 3,
				  -fgcolor => 'black',
				  -bgcolor => 'black',
				  $conf->style($overview_track),
				 );
    foreach (@types) {
      $type2track{lc $_} = $overview_track
    }
    $track{$overview_track} = $track;
    push @feature_types,@types;
  }
  return unless @feature_types;

  my $iterator = $segment->features(-type=>\@feature_types,-iterator=>1,-rare=>1);

  my %count;
  while (my $feature = $iterator->next_seq) {

    my $track_name = eval{$type2track{lc $feature->type}}
      || $type2track{lc $feature->primary_tag}
	|| eval{$type2track{lc $feature->method}}
	  || next;

    my $track = $track{$track_name} or next;
    $track->add_feature($feature);
    $count{$track_name}++;
  }

  my $max_bump   = $self->bump_density;
  my $max_label  = $self->label_density;

  for my $track_name (keys %count) {
    my $track = $track{$track_name};

    my $bump  = $self->do_bump($track_name,$options->{$track_name}{options},$count{$track_name},$max_bump);
    my $label = $self->do_label($track_name,$options->{$track_name}{options},$count{$track_name},
				$max_label,$segment->length);
    my $description = $self->do_description($track_name,$options->{$track_name}{options},$count{$track_name},
				$max_label,$segment->length);

    $track->configure(-bump  => $bump,
		      -label => $label,
		      -description => $description,
		     );
  }
  return \%track;
}


=head2 hits_on_overview()

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

sub hits_on_overview {
   my $self = shift;
   my ($db,$hits,$options,$keyname) = @_;
   $self->_hits_on_overview($db,$hits,$options,$keyname,'htmlize');
}

=head2 hits_on_overview_raw()

  $hashref = $browser->hits_on_overview_raw($db,$hits,$options,$keyname);

This behaves the same as hits_on_overview() except that the values of
the returned hashref are a three-element array consisting of 
a segment, a GD image showing the segment and its hits, and the
array of hit coordinates returned by the panel->boxes() call.

=cut

sub hits_on_overview_raw {
   my $self = shift;
   my ($db,$hits,$options,$keyname) = @_;
   $self->_hits_on_overview($db,$hits,$options,$keyname,undef);
}

# Return an HTML showing where multiple hits fall on the genome.
# Can either provide a list of objects that provide the ref() method call, or
# a list of arrayrefs in the form [ref,start,stop,[name]]
sub _hits_on_overview {
  my $self = shift;
  my ($db,$hits,$options,$keyname,$htmlize) = @_;

  my %html; # results are a hashref sorted by chromosome

  my $conf  = $self->config;
  my $width = $self->width;
  my $units = $self->setting('overview units');
  my $max_label  = $self->label_density;
  my $max_bump   = $self->bump_density;
  my $class      = eval{$hits->[0]->factory->default_class} || 'Sequence';
  my ($padl,$padr)  = $self->overview_pad([grep { $options->{$_}{visible}}
					   $self->config->overview_tracks],
					  'Matches');

  # sort hits out by reference and version
  my (%refs);
  for my $hit (@$hits) {
    if (ref($hit) eq 'ARRAY') {
      my ($ref,$start,$stop,$name) = @$hit;
      push @{$refs{$ref}},Bio::Graphics::Feature->new(-start=>$start,
						      -end=>$stop,
						      -name=>$name||'');
    } elsif (UNIVERSAL::can($hit,'seq_id')) {
      my $name = $hit->can('seq_name') ? $hit->seq_name : $hit->name;
      eval {$hit->absolute(1)};
      my $ref  = my $id = $hit->seq_id;
      my $version = eval {$hit->isa('Bio::SeqFeatureI') ? undef : $hit->version};
      $ref .= " version $version" if defined $version;
      my($start,$end) = ($hit->start,$hit->end);
      $name =~ s/\:\d+,\d+$//;  # remove coordinates if they're there
      $name = substr($name,0,7).'...' if length $name > 10;
      my $feature = Bio::Graphics::Feature->new(-start=>$start,
						-end=>$end,
						-name=>$name,
						# -segments=>[$hit->get_SeqFeatures]  # this has an awful performance hit
					       );
      push @{$refs{$ref}},$feature;
    } elsif (UNIVERSAL::can($hit,'location')) {
      my $location = $hit->location;
      my ($ref,$start,$stop,$name) = ($location->seq_id,$location->start,
				      $location->end,$location->primary_tag);
      push @{$refs{$ref}},Bio::Graphics::Feature->new(-start=>$start,
						      -end=>$stop,
						      -name=>$name||'');
    }
  }

  # Temporary kludge until I can figure out a more
  # sane way of rendering overview with SVG...
  # Should be handled by being passed a $image_class param
  my $image_class = 'GD';
  eval "use $image_class";

  $keyname = 'Matches' unless defined $keyname;

  for my $ref (sort keys %refs) {
    my ($name, $version) = split /\sversion\s/i, $ref;
    my $segment = ($db->segment(-class=>$class,-name=>$name,
				defined $version ? (-version => $version):()))[0] or next;
    my $panel = Bio::Graphics::Panel->new(-segment => $segment,
					  -width   => $width,
					  -bgcolor => $self->setting('overview bgcolor') || 'wheat',
					  -pad_left  => $padl,
					  -pad_right => $padr,
					  -pad_bottom => PAD_OVERVIEW_BOTTOM,
					  -key_style => 'left',
					  -image_class => $image_class
					 );

    # add the arrow
    $panel->add_track($segment,
		      -glyph     => 'arrow',
		      -double    => 1,
		      -label     => ($htmlize ? 0 : $segment->seq_id),
		      -labelfont => $image_class->gdMediumBoldFont,
		      -tick      => 2,
		      $units ? (-units => $units) : (),
		     );

    # add the landmarks
    $self->add_overview_landmarks($panel,$segment,$options);

    # add the hits
    $panel->add_track($refs{$ref},
		      -glyph     => 'diamond',
		      -height    => 8,
		      -fgcolor   => 'red',
		      -bgcolor   => 'red',
		      -fallback_to_rectangle => 1,
		      -connector => 'solid',
		      -key       => $keyname,
		      -bump      => @{$refs{$ref}} <= $max_bump,
		      -label     => @{$refs{$ref}} <= $max_bump,  # deliberate
		     );

    my $gd    = $panel->gd;
    my $boxes = $panel->boxes;

    eval {$panel->finished};
    $html{$ref} = $htmlize? $self->_hits_to_html($ref,$gd,$boxes) : [$ref,$gd,$boxes];
  }

  return \%html;
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
  my ($track_name,$option,$count,$max) = @_;

  my $conf              = $self->config;
  my $maxb              = $conf->code_setting($track_name => 'bump density');
  $maxb                 = $max unless defined $maxb;

  my $maxed_out = $count <= $maxb;
  my $conf_bump = $conf->code_setting($track_name => 'bump');
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

  my $maxl              = $conf->code_setting($track_name => 'label density');
  $maxl                 = $max_labels unless defined $maxl;
  my $maxed_out = $count <= $maxl;

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

  my $maxl              = $conf->code_setting($track_name => 'label density');
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

# fetch a list of Segment objects given a name or range
# (this used to be in gbrowse executable itself)
sub name2segments {
  my $self = shift;
  my ($name,$db,$toomany,$segments_have_priority) = @_;
  $toomany ||= TOO_MANY_SEGMENTS;

  my $max_segment   = $self->get_max_segment;

  my (@segments,$class,$start,$stop);
  if ($name =~ /([\w._\/-]+):(-?[-e\d.]+),(-?[-e\d.]+)$/ or
      $name =~ /([\w._\/-]+):(-?[-e\d,.]+)(?:-|\.\.)(-?[-e\d,.]+)$/) {
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

 SEARCHING: {
    # non-heuristic fetch
    @segments  = $self->_feature_get($db,$name,$class,$start,$stop,$segments_have_priority);
    last SEARCHING if @segments;

    # heuristic fetch. Try various abbreviations and wildcards
    my @sloppy_names = $name;
    if ($name =~ /^([\dIVXA-F]+)$/) {
      my $id = $1;
      foreach (qw(CHROMOSOME_ Chr chr)) {
	my $n = "${_}${id}";
	push @sloppy_names,$n;
      }
    }

    # try to remove the chr CHROMOSOME_I
    if ($name =~ /^(chromosome_?|chr)/i) {
      (my $chr = $name) =~ s/^(chromosome_?|chr)//i;
      push @sloppy_names,$chr;
    }

    # try the wildcard  version, but only if the name is of significant length
    # IMPORTANT CHANGE: we used to put stars at the beginning and end, but this killed performance!
    push @sloppy_names,"$name*" if length $name > 3;

    # automatic classes to try
    my @classes = $class ? ($class) : (split /\s+/,$self->setting('automatic classes'));

    for my $n (@sloppy_names) {
      for my $c (@classes) {
	@segments = $self->_feature_get($db,$n,$c,$start,$stop,$segments_have_priority);
	last SEARCHING if @segments;
      }
    }
  }
  @segments;
}

sub _feature_get {
  my $self = shift;
  my ($db,$name,$class,$start,$stop,$segments_have_priority) = @_;

  my $refclass = $self->setting('reference class') || 'Sequence';
  $class ||= $refclass;

  my @argv = (-name  => $name);
  push @argv,(-class => $class) if defined $class;
  push @argv,(-start => $start) if defined $start;
  push @argv,(-end   => $stop)  if defined $stop;
  warn "\@argv = @argv" if DEBUG;
  my @segments;
  if ($segments_have_priority) {
    @segments  = grep {$_->length} $db->segment(@argv);
    @segments  = grep {$_->length} $db->get_feature_by_name(@argv) if !@segments;
  } else {
    @segments  = grep {$_->length} $db->get_feature_by_name(@argv) if !defined($start) && !defined($stop);
    @segments  = grep {$_->length} $db->segment(@argv)             if !@segments && $name !~ /[*?]/;
  }
  return unless @segments;

  # Deal with multiple hits.  Winnow down to just those that
  # were mentioned in the config file.
  my $types = $self->_all_types($db);
  my @filtered = grep {
    my $type    = $_->type;
    my $method  = eval {$_->method} || '';
    my $fclass  = eval {$_->class}  || '';
    $type eq 'Segment'
      || $types->{$type}
	|| $types->{$method}
	  || $fclass eq $refclass
	    || $fclass eq $class;
  } @segments;

  # consolidate features that have same name and same reference sequence
  # and take the largest one.
  my %longest;
  foreach (@filtered) {
    # try the second line from Scott.  If multi-hit searches start coming up with too many
    # identical hits, try the first one again.
    # my $n = $_->display_name.$_->abs_ref.(eval{$_->version}||''); # avoiding uninit warnings
    # my $n = $_->display_name.$_->abs_ref.(eval{$_->version}||'').$_->class;
    my $n = $_->display_name.$_->abs_ref.(eval{$_->version}||'').(eval{$_->class}||'');
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
  my $black = $image->colorClosest(0,0,0);
  foreach (@$boxes) {
    my @rect = @{$_}[1,2,3,4];
    $image->rectangle(@{$_}[1,2,3,4],$black);
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

package Bio::Graphics::BrowserConfig;
use strict;
use Bio::Graphics::FeatureFile;
use Text::Shellwords;
use Carp 'croak';
use Socket;  # for inet_aton() call

use vars '@ISA';
@ISA = 'Bio::Graphics::FeatureFile';

sub labels {
  my $self   = shift;

  # filter out all configured types that correspond to the overview, overview details
  # plugins, or other name:value types
  my @labels =  grep {
    !($_ eq 'TRACK DEFAULTS' || /:(\d+|plugin|DETAILS)$/)
       } $self->configured_types;
  # apply restriction rules
  return grep { $self->authorized($_)} @labels;
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
  my $restrict = $self->code_setting($label=>'restrict')
    || ($label ne 'general' && $self->code_setting('TRACK DEFAULTS' => 'restrict'));
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

  my $allow = $mode eq  'allow,deny' ? match_host(\@allow,$host,$addr) && !match_host(\@deny,$host,$addr)
                      : 'deny,allow' ? !match_host(\@deny,$host,$addr) ||  match_host(\@allow,$host,$addr)
		      : croak "$mode is not a valid authorization mode";
  return $allow unless %users;
  $satisfy = 'any'  if !@allow && !@deny;  # no host restrictions
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
  return shellwords($self->setting($l,'feature')||$self->setting($label,'feature')||'');
}

sub style {
  my ($self,$label,$length) = @_;
  my $l = $self->semantic_label($label,$length);
  return $l eq $label ? $self->SUPER::style($l) : ($self->SUPER::style($label),$self->SUPER::style($l));
}

# like code_setting, but obeys semantic hints
sub semantic_setting {
  my ($self,$label,$option,$length) = @_;
  my $slabel = $self->semantic_label($label,$length);
  my $val = $self->code_setting($slabel => $option) if defined $slabel;
  return $val if defined $val;
  return $self->code_setting($label => $option);
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
      my ($label_base,$minlength) = $label =~ /([^:]+)(?::(\d+))?/;
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
    next if $label=~/:?overview$/;   # special case
    my $feature = $config->{$label}{'feature'} or next;
    foreach (shellwords($feature||'')) {
      $inverted{lc $_}{$label}++;
    }
  }
  \%inverted;
}

sub default_labels {
  my $self = shift;
  my $defaults = $self->setting('general'=>'default features');
  return shellwords($defaults||'');
}

# return a hashref in which keys are the thresholds, and values are the list of
# labels that should be displayed
sub summary_mode {
  my $self = shift;
  my $summary = $self->settings(general=>'summary mode') or return {};
  my %pairs = $summary =~ /(\d+)\s+{([^\}]+?)}/g;
  foreach (keys %pairs) {
    my @l = shellwords($pairs{$_}||'');
    $pairs{$_} = \@l
  }
  \%pairs;
}

# override make_link to allow for code references
sub make_link {
  my $self     = shift;
  my ($feature,$panel,$source,$label)  = @_;
  $panel ||= 'Bio::Graphics::Panel';
  $label     ||= $self->feature2label($feature);

  my $link     = $self->code_setting($label,'link');
  $link        = $self->code_setting('TRACK DEFAULTS'=>'link') unless defined $link;
  $link        = $self->code_setting(general=>'link')          unless defined $link;

  return $feature->make_link if !$link && $feature->can('make_link');
  return unless $link;

  if (ref($link) eq 'CODE') {
    my $val = eval {$link->($feature,$panel)};
    warn $@ if $@;
    return $val;
  }
  elsif (!$link || $link eq 'AUTO') {
    my $n     = $feature->display_name;
    my $c     = $feature->seq_id;
    my $name  = CGI::escape("$n");  # workaround CGI.pm bug
    my $class = eval {CGI::escape($feature->class)}||'';
    my $ref   = CGI::escape("$c");  # workaround again
    my $start = CGI::escape($feature->start);
    my $end   = CGI::escape($feature->end);
    my $src   = CGI::escape($source);
    return "../../gbrowse_details/$src?name=$name;class=$class;ref=$ref;start=$start;end=$end";
  }
  return $self->link_pattern($link,$feature,$panel);
}

# make the title for an object on a clickable imagemap
sub make_title {
  my $self = shift;
  my ($feature,$panel,$label) = @_;
  local $^W = 0;  # tired of uninitialized variable warnings

  my ($title,$key) = ('','');
 TRY: {
    $label     ||= $self->feature2label($feature) or last TRY;
    $key         = $self->setting($label,'key') || $label;
    $key         =~ s/s$//;
    my $link     = $self->code_setting($label,'title')
      || $self->code_setting('TRACK DEFAULTS'=>'title')
      || $self->code_setting(general=>'title');
    if (defined $link && ref($link) eq 'CODE') {
      $title       = eval {$link->($feature,$panel)};
      warn $@ if $@;
      return $title if defined $title;
    }
    return $self->link_pattern($link,$feature) if $link && $link ne 'AUTO';
  }

  # otherwise, try it ourselves
  $title = eval {
    if ($feature->can('target') && (my $target = $feature->target)) {
      join (' ',
	    "$key:",
	    $feature->seq_id.':'.
	    $feature->start."..".$feature->end,
	    $feature->target.':'.
	    $feature->target->start."..".$feature->target->end);
    } else {
      my ($start,$end) = ($feature->start,$feature->end);
      ($start,$end)    = ($end,$start) if $feature->strand < 0;
      join(' ',
	   "$key:",
	   $feature->can('display_name') ? $feature->display_name : $feature->info,
	   ($feature->can('seq_id')      ? $feature->seq_id : $feature->location->seq_id)
	   .":".
	   ($start||'?')."..".($end||'?')
	  );
    }
  };
  warn $@ if $@;

  return $title;
}

sub make_link_target {
  my $self = shift;
  my ($feature,$panel,$label) = @_;
  $label    ||= $self->feature2label($feature) or return;
  my $link_target = $self->code_setting($label,'link_target')
    || $self->code_setting('LINK DEFAULTS' => 'link_target')
    || $self->code_setting(general => 'link_target');
  $link_target = eval {$link_target->($feature,$panel)} if ref($link_target) eq 'CODE';
  warn $@ if $@;
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

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut
