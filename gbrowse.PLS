#!perl
use Config;
use File::Basename qw(&basename &dirname);
use FindBin '$Bin';
use Cwd;

my %OPTIONS;
if (open F,"$Bin/GGB.def") {
  while (<F>) {
    next if /^\#/;
    chomp;
    $OPTIONS{$1} = $2 if /^(\w+)\s*=\s*(.+)/;
  }
  close F;
}
$OPTIONS{CONF} ||= '/usr/local/apache/conf';

$origdir = cwd;
chdir dirname($0);
$file = basename($0, '.PL','.PLS');

open OUT,">$file" or die "Can't create $file: $!";

print "Extracting $file (with variable substitutions)\n";

print OUT <<"!GROK!THIS!";
$Config{startperl} -w

###################################################################
# Non-modperl users should change this variable if needed to point
# to the directory in which the configuration files are stored.
#
\$CONF_DIR  = '$OPTIONS{CONF}/gbrowse.conf';
#
###################################################################
\$VERSION   = $OPTIONS{VERSION};

!GROK!THIS!

# In the following, perl variables are not expanded during extraction.

print OUT <<'!NO!SUBS!';

# Bio::DB::GFF/Bio::Graphics-based annotation browser
# $Id: gbrowse.PLS,v 1.42 2002-07-04 15:49:43 lstein Exp $

use strict;
use Bio::DB::GFF;
use Bio::Graphics;
use Bio::Graphics::Browser;
use Digest::MD5 'md5_hex';
use File::Path 'mkpath';
use Text::Tabs;
use Text::Shellwords;
use File::Basename 'basename';
use Carp qw(:DEFAULT croak);
use CGI qw(:standard escape escapeHTML center *table *dl *TR *td);
use vars qw($CONFIG %DB $MAX_SEGMENT $DEFAULT_SEGMENT 
	    $HEADER $HTML $UA $VERSION $CONF_DIR %OBJECT_TYPES
	    $PLUGINS);

# if you change the zoom/nav icons, you must change this as well.
use constant MAG_ICON_HEIGHT => 20;
use constant MAG_ICON_WIDTH  => 8;
use constant MAX_SEGMENT     => 1_000_000;
use constant TOO_MANY_SEGMENTS => 5_000;
use constant TOO_MANY_FEATURES => 100;
use constant TOO_MANY_REFS     => 30;
use constant DEFAULT_SEGMENT => 100_000;
use constant OVERVIEW_RATIO  => 0.9;
use constant ANNOTATION_EDIT_ROWS => 25;
use constant ANNOTATION_EDIT_COLS => 100;
use constant URL_FETCH_TIMEOUT    => 5;  # five seconds max!
use constant URL_FETCH_MAX_SIZE   => 1_000_000;  # don't accept any files larger than 1 Meg
use constant MAX_KEYWORD_RESULTS  => 50;  # max number of results from keyword search
use constant DEFAULT_RANGES       => q(100 500 1000 5000 10000 25000 100000 200000 400000);
use constant DEFAULT_FINE_ZOOM    => '10%';
use constant GBROWSE_HELP         => '/gbrowse';

# if true, turn on surrounding rectangles for debugging the image map
use constant DEBUG => 0;
use constant DEBUG_PLUGINS => 0;
use constant DEBUGGING_RECTANGLES => 0;

# IMPORTANT DATA STRUCTURES

# $SETTINGS (also called $page_settings): hash reference containing state information
# keys:
#   name      name of a landmark to search for (e.g. keyword search)
#   ref       sequence landmark reference ID (once found)
#   start     start of range relative to ref
#   stop      stop of range relative to ref
#   source    symbolic name of database/configuration to use
#   id        unique cookie-based ID for this user
#   tracks    array ref which has one element for each track on the
#               display.  The value of each element indicates what
#               track to display in that position using the configuration
#               key code.  For example: [HMM,BAB,GB]
#               means display the "HMM", "BAB" and "GB" features in that
#               order.  Uploaded feature data is named "UPLOAD",
#               External URL tracks are indicated using the URL of the data.
#   features    hash ref which has one element for each feature type.
#               Its values are hashrefs with subkeys {visible} and {options}.
#               A true value in {visible} indicates that the feature is active.
#               The values of {options} are integers with the following meaning:
#               0=auto, 1=force no bump, 2=force bump, 3=force label.
# $CONFIG
# This is a global Bio::Graphics::Browser object.  It contains information on
# all the configuration files for this browser and provides access to the various
# settings within the configuration file.

BEGIN {
    eval "use Apache"; 
    warn <<END if Apache::DBI->can('connect_on_init');
WARNING: APACHE::DBI DETECTED.
THIS WILL CAUSE THE GFF DUMP TO FAIL INTERMITTENTLY.
THIS SCRIPT DOES NOT BENEFIT FROM APACHE::DBI
END
;
    # here's a patch for a fix in Bio::DB::GFF that didn't get into BioPerl 1.0
    unless (Bio::DB::GFF::Segment->can('seq_id')) {
      *Bio::DB::GFF::Segment::seq_id  = sub { shift->ref };
      *Bio::Graphics::Feature::seq_id = sub { shift->ref };
    }

};

$HEADER=0;
$HTML=0;

if ($ENV{MOD_PERL}) {
    my $conf  = Apache->request->dir_config('GBrowseConf');
    $CONF_DIR = Apache->server_root_relative($conf) if $conf;
}

## CONFIGURATION & INITIALIZATION #############################################################
# preliminaries -- read and/or refresh the configuration directory
$CONFIG  ||= Bio::Graphics::Browser->new;
$CONFIG->read_configuration($CONF_DIR) or die "Can't read configuration files: $!";

## PAGE SETTINGS ##############################################################################
#
# Recover a hashref which contains page-specific settings
# (this involves reading a cookie or possibly a database record in some future implementation
my ($source,$old_source) = get_source();
$CONFIG->source($source);
my $page_settings = get_settings($source);

$MAX_SEGMENT     = $CONFIG->setting('max segment')     || MAX_SEGMENT;
$DEFAULT_SEGMENT = $CONFIG->setting('default segment') || DEFAULT_SEGMENT;

# Now adjust those settings based on submitted CGI parameters
# With the exception that we ignore parameter changes if the source has changed.
if (defined($old_source) && $source ne $old_source) {
  param(name => $page_settings->{name});  # restore old reference point
} else {
  adjust_settings($page_settings);        # set settings from CGI parameters
}

### PLUGINS ###################################################################################
$PLUGINS = initialize_plugins($CONF_DIR) unless defined $PLUGINS;
configure_plugins($PLUGINS,$page_settings,open_database(),$CONFIG,$CONF_DIR);
my $plugin_type   = $PLUGINS->{param('plugin')}->type if param('plugin') && $PLUGINS->{param('plugin')};
my $plugin_action = param('plugin_action') || '';
warn "plugin_action = $plugin_action" if DEBUG_PLUGINS;

## GETTING THE SEGMENT ########################################################################
my @segments = get_segments($page_settings);

if ($plugin_action eq 'Find' && param('plugin')) {
  do_plugin_find($page_settings,
		 param('plugin'),
		 \@segments) or ($plugin_action='Configure...'); #reconfigure
} elsif (!@segments && $page_settings->{name}) {
  do_keyword_search($page_settings,\@segments);
  do_plugin_autofind($page_settings,\@segments) unless @segments;  # last resort
}


###############################################################################################

# SETTINGS FOR UPLOADED FILES
my ($file_action) = grep {/^modify\./} param();
(my $file = $file_action) =~ s/^modify\.// if $file_action;


###############################################################################################
## DUMPS ######################################################################################
###############################################################################################
# Check to see whether one of the plugin dumpers was invoked.  We have to do this first
# before printing the header because the plugins are responsible for generating the header.
# NOTE THE EXIT 0 HERE IF THE DUMP IS SUCCESSFUL!
if (@segments && $plugin_action eq 'Go!'&& $plugin_type eq 'dumper') {
  do_plugin_dump(param('plugin'),$segments[0]) && exit 0
}


###############################################################################################
## HANDLING FILE DOWNLOADS ######################################################################

# This gets called if the user wants to download his annotation data
if (my $to_download = (param('Download File') ||
		       ($file_action && param($file_action) eq 'Download File') && $file)) {
  warn "FILE DOWNLOAD, download = $to_download" if DEBUG;
  print header(-attachment   =>  $to_download,
	       -type         => 'application/octet-stream');
  print_uploaded_file_features($page_settings,$to_download);
  exit 0;
}


## HANDLING FILE UPLOADS ######################################################################
if (param('Upload') && (my $file = param('upload_annotations'))) {
  handle_upload($page_settings,$file);
}

elsif (defined(my $data = param('a_data'))) {
  handle_edit($page_settings,$data);
}

elsif ($data = param('auto')) {
  handle_quickie($page_settings,$data);
}

clear_uploaded_file($page_settings,$file) if $file_action && param($file_action) eq 'Delete File';

warn "TRACKS = @{$page_settings->{tracks}}" if DEBUG;

load_plugin_annotators($page_settings);
adjust_tracks($page_settings);

warn "ADJUSTED TRACKS = @{$page_settings->{tracks}}" if DEBUG;

## UPDATING THE PERSISTENT SETTINGS##############################################################
my $cookies = settings2cookie($page_settings);
push @$cookies,plugins2cookies($PLUGINS);
print header(-cookie => $cookies) unless $HEADER++;

my $description = $CONFIG->setting('description');
my $segment;

## STARTING THE PAGE ############################################################################
my $title = @segments == 1 ? "$description: $segments[0]" : $description;

print
  start_html(-title  => $title,
	     -style  => {src=>$CONFIG->setting('stylesheet')},
	    ) unless $HTML++;

my $header = $CONFIG->header();
print $header if $header;

## HANDLE UPLOADED FILE EDITS ##################################################################
if ($file_action && param($file_action) eq 'Edit File...') {
  edit_uploaded_file($page_settings,$file);
}

## HANDLE TRACK SETTINGS   #######################################################
elsif ((param('Set Track Options...') || param('Revert fo Defaults..'))
       && !param('Cancel')
       && !param('Redisplay')) {
  set_track_options($page_settings);
}

## HANDLE HELP PAGE   #######################################################

elsif (param('help')) {
  help(param('help'),$CONFIG->setting('help')||GBROWSE_HELP,$page_settings);
}

## HANDLE PLUGIN ABOUT PAGE #####################################################
elsif ($plugin_action eq 'About...') {
  do_plugin_about(param('plugin'));
}

## HANDLE PLUGIN CONFIGURATION####################################################
elsif ($plugin_action eq 'Configure...') {
  do_plugin_configure(param('plugin'));
} elsif ($plugin_action eq 'Go!' && $plugin_type=~/^(finder|annotator)$/i) {
  do_plugin_configure(param('plugin'));
}

## MAIN DISPLAY
else {
  print h1($description) unless defined($header);
  main_display(\@segments,$page_settings);
}

footer();

#--------------------------------- lots of subroutines --------------------------

sub main_display {
  my ($segments,$page_settings) = @_;
  my ($segment,@keyword_search_results);

  # first of all, if there are no segments, then try a keyword search and store the results
  if (@$segments == 0 && (my $n = $page_settings->{name})) {
      error("The landmark named",i($n),"is not recognized. See the help pages for suggestions.");
  }

  # if there's a single segment, then print a message and store the segment into a scalar
  elsif (@$segments == 1) {
    $segment = $segments->[0];
    $segment = truncated_segment($segment) if $segment->length < 4;
    print h2("Showing",unit_label($segment->length)," from",
	     $segment->seq_id.", positions ".commas($segment->start)." to ".commas($segment->stop));
  }

  # print the top of the form, with navigation bar, etc
  print start_multipart_form(-name=>'mainform',-action=>url(-relative=>1,-path_info=>1)),
    navigation_table($segment,$page_settings);

  # if more than one segment, then list them all
  if (@$segments > 1) {
    multiple_choices($page_settings,$segments);
  }

  my $feature_files;

  if ($segment) {

      # if a plugin passes us back a Feature, rather than a Segment, turn it into a segment
      # (this shouldn't happen - hah!)
    $segment = open_database()->segment($segment->seq_id,$segment->start,$segment->end)
	unless $segment->can('features');

    # get the third party features
    $feature_files = load_external_sources($segment,$page_settings);

    my ($img,$map);
    my $cell = overview($segment,$page_settings).br();

    if ($segment->length <= $MAX_SEGMENT) {

      # add plugin annotators, but only if the length is reasonable!
      load_plugin_annotations($segment,$feature_files,$page_settings);

      $CONFIG->width($page_settings->{width});
      my @tracks_to_show = grep {$page_settings->{features}{$_}{visible}} @{$page_settings->{tracks}};
      my %options = map {$_=>$page_settings->{features}{$_}{options}} @tracks_to_show;
      my %limit   = map {$_=>$page_settings->{features}{$_}{limit}}   @tracks_to_show;
      ($img,$map) = $CONFIG->render_html(segment       => $segment,
					 feature_files => $feature_files,
					 tracks        => \@tracks_to_show,
					 options       => \%options,
					 limit         => \%limit,
					 do_map        => 1,
					 do_centering_map => 1,
					);
      $cell .= $img;
    }

    else {
      $cell .= i(
		 "Detailed view is limited to",
		 commas($MAX_SEGMENT),"bases.",
		 "Click in the overview to select a region",commas($DEFAULT_SEGMENT),'bp wide.');
    }
    print "\n",
      table({-border=>0,-width=>$page_settings->{width}},
	    TR({-class=>'searchbody'},
	       td({-align=>'CENTER'},$cell)
	      )
	   ),"\n";
    print $map,"\n" if $map;
  }
  print hidden('ref'),hidden('start'),hidden('stop');
  print settings_table($page_settings,$feature_files);
  print plugin_and_data_source_table($page_settings,$PLUGINS);
  print p(),upload_table($page_settings,$feature_files);
  print p(),external_table($page_settings,$feature_files);
  print end_form();

  # clean us up
  foreach (keys %$feature_files) {
    $_ && ref($_) && $_->destroy;
  }
}

###############################################################################################

sub get_source {
  my $new_source = param('source');
  my $old_source = cookie('gbrowse_source') unless param('source') && request_method() eq 'GET';

  my $source   = $new_source || $old_source;
  $source ||= $CONFIG->source;  # the default, whatever it is
  return ($source,$old_source);
}

# read from cookie, if there is one
# if not, set  from defaults
sub get_settings {
  my $source   = shift;
  open_database() or croak "Can't open database defined by source $source";
  my %settings = cookie("gbrowse_$source");

  my $ok = 1;

  if (%settings) {  # if cookie is there, then validate it
    $ok &&= defined $settings{width} && $settings{width} > 100 && $settings{width} < 5000;
    warn "ok 1 = $ok" if DEBUG;

    my %ok_sources = map {$_=>1} $CONFIG->sources;
    $ok &&= $ok_sources{$settings{source}};
    warn "ok 2 = $ok" if DEBUG;

    # the single "tracks" key of the cookie gets mapped to the
    # "track" and "features" key of the page settings
    my @features = split $;,$settings{tracks} if $ok && defined $settings{tracks};
    $settings{tracks}    = [];  # make sure these are clean
    $settings{features}  = {};
    foreach (@features) {
      warn "feature = $_" if DEBUG;
      my ($label,$visible,$option,$limit) = m!^(.+)/(\d+)/(\d+)/(\d+)$!;
      warn "label = $label, visible = $visible, option = $option, limit = $limit" if DEBUG;
      unless ($label) {   # corrupt cookie; purge it.
	undef $ok;
	last;
      }
      push @{$settings{tracks}},$label;
      $settings{features}{$label}{visible} = $visible;
      $settings{features}{$label}{options} = $option;
      $settings{features}{$label}{limit}   = $limit;
    }
    warn "ok 3 = $ok" if DEBUG;
  }

  $ok &&= ref($settings{tracks}) && @{$settings{tracks}} > 0;

  warn "ok 4 = $ok" if DEBUG;

  if ($ok && %settings) {
    adjust_tracks(\%settings);
  }
  else {
    %settings = ();
    default_settings(\%settings);
  }

  warn "order = @{$settings{tracks}}" if $settings{tracks} && DEBUG;

  if (DEBUG) {
    foreach (@{$settings{tracks}}) {
      my $s = $settings{features}{$_};
      warn "$_: ",$CONFIG->setting($_=>'key')," vis=$s->{visible}, opt=$s->{options}, limit=$s->{limit}\n";
    }
  }

  \%settings;
}

sub default_settings {
  my $settings = shift;
  warn "Setting default settings" if DEBUG;
  @$settings{'name','ref','start','stop'} = ('','','','');
  $settings->{width}   = $CONFIG->setting('default width');
  $settings->{source}  = $CONFIG->source;
  $settings->{id}      = md5_hex(rand);  # new identity
  set_default_tracks($settings);
}

sub set_default_tracks {
  my $settings = shift;
  my @labels = labels($settings);
  $settings->{tracks}   = \@labels;
  warn "order = @labels" if DEBUG;
  foreach (@labels) {
    $settings->{features}{$_} = {visible=>0,options=>0,limit=>0};
  }
  foreach ($CONFIG->default_labels) {
    $settings->{features}{$_}{visible} = 1;
  }
}

# This is called to check that the list of feature types given
# in the configuration file are consistent with the features
# given in the user's cookie.  If not, the settings are adjusted
# as best we can. The attempt here is to allow
# the administrator to add new feature stanzas
# without invalidating users' old settings.
sub adjust_tracks {
  my $settings = shift;
  my %configured_labels = map {$_=>1} $CONFIG->labels;

  foreach (grep {!$settings->{features}{$_}} keys %configured_labels) {
    $settings->{features}{$_}{visible} = 0;  # not visible
    $settings->{features}{$_}{options} = 0;  # automatic
    push @{$settings->{tracks}},$_;           # at the end
  }
  # Remove any features that are not mentioned in the
  # config file, excepting Uploaded and remote URL features.
  # This may happen if a stanza is removed from the config file.
  my %extra = map {$_=>1} grep {!/^(http|ftp|das|file|plugin):/
				    && !$configured_labels{$_}} keys %{$settings->{features}};
  # remove extra from tracks && options
  if (%extra) {
    delete $settings->{features}{$_} foreach keys %extra;
  }

  # make sure that tracks are completely consistent with options
  $settings->{tracks} = [grep {exists $settings->{features}{$_}} @{$settings->{tracks}}];
}

# this is called to flatten the settings into an HTTP cookie
sub settings2cookie {
  my $settings = shift;
  my %settings = %$settings;
  local $^W = 0;
  for my $key (keys %settings) {
    next if $key =~ /^(tracks|features)$/;  # handled specially
    if (ref($settings{$key}) eq 'ARRAY') {
      $settings{$key} = join $;,@{$settings{$key}};
    }
  }

  # the "features" and "track" key map to a single array
  # contained in the "tracks" key of the settings
  my @array = map {join("/",
			$_,
			$settings{features}{$_}{visible},
			$settings{features}{$_}{options},
			$settings{features}{$_}{limit})} @{$settings{tracks}};
  $settings{tracks} = join $;,@array;
  delete $settings{features};

  warn "cookie => ",join ' ',%settings,"\n" if DEBUG;

  my @cookies;
  my $source = $CONFIG->source;
  push @cookies,cookie(-name    => "gbrowse_$source",
		      -value   => \%settings,
		      -expires => '+3M');
  push @cookies,cookie(-name   => 'gbrowse_source',
		       -value  => $source,
		       -expires => '+3M');
  return \@cookies;
}

# This is called to change the values of the settings
sub adjust_settings {
  my $settings = shift;
  if (my @selected = map {split /[+-]/} param('label')) {
    $settings->{features}{$_}{visible} = 0 foreach keys %{$settings->{features}};
    $settings->{features}{$_}{visible} = 1 foreach @selected;
  }
  $settings->{width}  = param('width')   if param('width');

  local $^W = 0;  # kill uninitialized variable warning
  if (param('ref') &&
      ( request_method() eq 'GET'
	|| param('name') eq param('prevname')
	|| grep {/zoom|nav|overview/} param())
     )
    {
      $settings->{ref}   = param('ref');
      $settings->{start} = param('start') if param('start') =~ /^[\d-]+/;
      $settings->{stop}  = param('stop')  if param('stop')  =~ /^[\d-]+/;
      zoomnav($settings);
      $settings->{name} = "$settings->{ref}:$settings->{start}..$settings->{stop}";
      param(name => $settings->{name});
    }
  $settings->{name}   = param('name')                       if param('name');
  $settings->{source} = param('source')                     if param('source');

  if (my @external = param('eurl')) {
    my %external = map {$_=>1} @external;
    foreach (@external) {
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

  if (param('Revert to Defaults') || param('Reset')) {
    warn "resetting defaults..." if DEBUG;
    set_default_tracks($settings);
  }

  elsif (param('Adjust Order') && !param('Cancel')) {
    adjust_track_options($settings);
    adjust_track_order($settings);
  }

}

# prints the zooming and navigation bar
sub navigation_table {
  my $segment = shift;
  my $settings = shift;
  my $buttonsDir    = $CONFIG->setting('buttons');
  my $table = '';
  my $oligo = $PLUGINS->{'OligoFinder'} ? ', oligonucleotide (15 bp minimum)' : '';

  $table .= table({-border=>0, -width=>$settings->{width}},
		  TR({-class=>'searchbody'},
		     td({-align=>'left', -colspan=>3},
			"Search using a sequence name, gene name, locus${oligo} or other landmark.",
			'The wildcard character "*" is allowed.',
			show_examples()
		    )),
		  TR({-class=>'searchbody'},
		     td({-align=>'left', -colspan=>3},
			'To center on a location, click the ruler.  User the Scroll/Zoom buttons to',
			'change magnification and position.',
			'To save this view,',a({-href=>bookmark_link($settings)},'bookmark this link.')
		       )),
		  TR({-class=>'searchtitle', -align=>'left'},
		     td({-class=>'searchtitle'}, b('Landmark or Region'),
			textfield(-name=>'name',-size=>20),
			submit(-name=>'Go')),
		     td({-align=>'LEFT'},
			$segment ? ('Scroll/Zoom: ',slidertable($segment,$buttonsDir)) : ''
		       ),
		     td(submit(-name=>'Reset',-class=>'reset_button'))
		    ));
}

# This generates the navigation bar with the arrows
sub slidertable {
  my ($segment,$buttonsDir) = @_;
  my $span      = $segment->length;
  my $half      = unit_label(int $span/2);
  my $full      = unit_label($span);
  my $fine_zoom = get_zoomincrement();

  my @lines;
  push @lines,hidden(-name=>'start',-value=>$segment->start,-override=>1);
  push @lines,hidden(-name=>'stop',-value=>$segment->end,-override=>1);
  push @lines,hidden(-name=>'ref',-value=>$segment->seq_id,-override=>1);
  push @lines,hidden(-name=>'prevname',-value=>scalar(param('name')),-override=>1);
  push @lines,
    (image_button(-src=>"$buttonsDir/green_l2.gif",-name=>"left $full",
		  -border=>0,-title=>"left $full"),
     image_button(-src=>"$buttonsDir/green_l1.gif",-name=>"left $half",
		  -border=>0,-title=>"left $half"),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/minus.gif",-name=>"zoom out $fine_zoom",
		  -border=>0,-title=>"zoom out $fine_zoom"),
     '&nbsp;',
     zoomBar($segment,$buttonsDir),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/plus.gif",-name=>"zoom in $fine_zoom",
		  -border=>0,-title=>"zoom in $fine_zoom"),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/green_r1.gif",-name=>"right $half",
		  -border=>0,-title=>"right $half"),
     image_button(-src=>"$buttonsDir/green_r2.gif",-name=>"right $full",
		  -border=>0,-title=>"right $full"),
    );

  #  print end_form;
  my $str	= join('', @lines);
  return $str;
}

# this generates the popup zoom menu with the window sizes
sub zoomBar {
  my ($segment,$buttonsDir) = @_;

  my %seen;
  my @ranges	= grep {!$seen{$_}++} sort {$b<=>$a} $segment->length,get_ranges();
  my %labels    = map {$_=>"Show ".unit_label($_)} @ranges;
  return popup_menu(-class   => 'searchtitle',
	       -name    => 'span',
	       -values  => \@ranges,
	       -labels  => \%labels,
	       -default => $segment->length,
	       -force   => 1,
	       -onChange => 'document.mainform.submit()',
	      );
}

# convert bp into nice Mb/Kb units
sub unit_label {
  my $value = shift;
  my $label;
  $label = $value >= 1e9 ? sprintf("%.4g Gbp",$value/1e9)
         : $value >= 1e6 ? sprintf("%.4g Mbp",$value/1e6)
         : $value >= 1e3 ? sprintf("%.4g Kbp",$value/1e3)
	 : $value." bp";
  return $label;
}

# convert Mb/Kb back into bp... or a ratio
sub unit_to_value {
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

sub labels {
  my $settings = shift;
  my @labels = $CONFIG->labels;
#  push @labels,$settings->{'uploaded_file'} ? "$settings->{uploaded_file} (Uploaded)"
#                                            : '(Uploaded Annotations)';
# this needs to be fixed
#  push @labels,@{$settings->{eurl}}   if $settings->{eurl};
  @labels;
}


# This subroutine is invoked to draw the checkbox group underneath the main display.
# It creates a hyperlinked set of feature names.
sub settings_table {
  my $settings = shift;
  my $additional_features = shift;

  my @widths = split /\s+/,$CONFIG->setting('image widths');
  @widths = (640,800,1024) unless @widths;

  # set up the dumps line.
  my($ref,$start,$stop) = @{$settings}{qw(ref start stop)};
  my $source   = $CONFIG->source;
  my $self     = url(-relative=>1,-path_info=>1);
  my $self_url = url(-relative=>1,-path_info=>1)."?help=citations";

  my @labels = @{$settings->{tracks}};
  my %labels = map {$_ => make_citation_link($_,$self_url) } @labels;
  my @defaults = grep {$settings->{features}{$_}{visible}} @labels;

  autoEscape(0);
  my $sTable 	= '';
  $sTable.= table({-border=>0,-width=>$settings->{width}},
		  # row
		  TR(
		     th({-class=>'searchtitle', -colspan=>3, -align=>'left'},'Display Settings:')),
		  TR(	td({-class=>'searchbody', -valign=>'top'}, 'Show features: '),
			td({-class=>'searchbody',-colspan=>2,-width=>'85%'},
			   checkbox_group(-name=>'label',
					  # use the track ordering to adjust the order of the checkboxes
					  # this is an array slice
					  -values   => \@labels,
					  -labels   => \%labels,
					  -defaults => \@defaults,
					  -cols     => 3,
					  -override => 1,
					 ))),

		  # row
		  TR({-class=>'searchbody'},
		     td('Image Width: '),
		     td(
			radio_group( -name=>'width',
				     -values=>\@widths,
				     -default=>$settings->{width},
				     -override=>1
				   )
		       ),
		     td({-align=>'RIGHT'},
			submit(-name => 'Set Track Options...')
			.'&nbsp;'.
			b(submit(-name => 'Update Image'))
		       )
		    ),
		 );
  autoEscape(1);
  return $sTable;
}

sub annotation_help {
  return url(-relative=>1,-path_info=>1) . "?help=annotation";
}

sub general_help {
  return url(-relative=>1,-path_info=>1) . "?help=general";
}

sub upload_table {
  my $settings      = shift;
  my $feature_files = shift;

  # start the table.
  my $cTable = start_table({-border=>0,-width=>$settings->{width}})
    . TR(
	 th({-class=>'datatitle', -colspan=>3, -align=>'left'},
	    'Upload your own annotations:',
	    a({-href=>annotation_help(),-target=>'help'},'[Help]'))
	);

  # now add existing files
  for my $filename (@{$settings->{tracks}}) {
    next unless $filename =~ /^file:/ && $feature_files->{$filename};
    (my $file = $filename) =~ s/^file://;
    my $name = escape($file);
    my $link = a({-href=>url(-relative=>1,-path_info=>1)."?Download+File=$name"},"[$name]");
    my @info =  get_uploaded_file_info($settings->{features}{$filename}{visible}
					 && $feature_files->{$filename});
    $cTable .=  TR({-class=>'databody'},
		   th($link),
		   td({-colspan=>2},
		      submit(-name=>"modify.$file",-value=>'Edit File...').'&nbsp;'.
		      submit(-name=>"modify.$file",-value=>'Download File').'&nbsp;'.
		      submit(-name=>"modify.$file",-value=>'Delete File')));
    $cTable .= TR({-class=>'databody'},td('&nbsp;'),td({-colspan=>2},@info));
  }

  # end the table.
  $cTable .= TR({-class=>'databody'},
		th({-align=>'RIGHT'},'Upload a File'),
		td({-colspan=>2},
		   filefield(-size=>40,-name=>'upload_annotations'),
		   submit(-name=>'Upload')));
  $cTable .= end_table;
  $cTable;
}

# URLs for external annotations
sub external_table {
  my $settings      = shift;
  my $feature_files = shift;
  my (@rows,$count);

  my ($preset_labels,$preset_urls) = get_external_presets($settings);  # (arrayref,arrayref)
  my $presets = '&nbsp;';
  if ($preset_labels && @$preset_labels) {  # defined AND non-empty
    my %presets;
    @presets{@$preset_urls} = @$preset_labels;
    unshift @$preset_urls,'';
    $presets{''} = '--Choose Preset URL--';
    $presets = popup_menu(-name   => 'eurl',
			  -values => $preset_urls,
			  -labels => \%presets,
			  -override => 1,
			  -default  => '',
			  -onChange => 'document.mainform.submit()'
			 );
  }

  for my $filename (@{$settings->{tracks}}) {
    next unless $filename =~ /^(ftp|http):/ && $feature_files->{$filename};
    warn "external_table(): filename = $filename" if DEBUG;
    push @rows,th({-align=>'RIGHT'},"URL",++$count).
      td(textfield(-name=>'eurl',-size=>50,-value=>$filename,-override=>1),br,
	 a({-href=>$filename,-target=>'help'},'[download]'),
	 get_uploaded_file_info($settings->{features}{$filename}{visible} && $feature_files->{$filename})
	);
  }
  push @rows,th({-align=>'RIGHT'},
		"Enter Remote Annotation URL").
		  td(textfield(-name=>'eurl',-size=>40,-value=>'',-override=>1),
		     $presets);

  return table({-border=>0,-width=>$settings->{width}},
	       TR({-class=>'datatitle'},
		  th({-align=>'LEFT',-colspan=>2},
		     'Add Remote Annotations:',a({-href=>annotation_help().'#remote',-target=>'help'},'[Help]'))),
	       TR({-class=>'databody'},\@rows),
	       TR({-class=>'databody'},
		  th('&nbsp;'),
		  th({-align=>'LEFT'},submit('Update URLs')))
	      );
}

sub get_external_presets {
  my $settings = shift;
  my $presets  = $CONFIG->setting('remote sources') or return;
  my @presets  = shellwords($presets);
  my (@labels,@urls);
  while (@presets) {
    my ($label,$url) = splice(@presets,0,2);
    next unless $url && $url =~ /^(http|ftp)/;
    push @labels,$label;
    push @urls,$url;
  }
  return unless @labels;
  (\@labels,\@urls);
}

# computes the new values for start and stop when the user made use of the zooming bar or navigation bar
sub zoomnav {
  my $settings = shift;
  return unless $settings->{ref};
  my $start = $settings->{start};
  my $stop  = $settings->{stop};
  my $span  = $stop - $start + 1;

  # get zoom parameters
  my $selected_span  = param('span');
  my ($zoom)         = grep {/^zoom (out|in) \S+/} param();
  my ($nav)          = grep {/^(left|right) \S+/}  param();
  my $overview_x     = param('overview.x');
  my $segment_length = param('seg_length');

  my $zoomlevel = unit_to_value($1) if $zoom && $zoom =~ /((?:out|in) .+)\.[xy]/;
  my $navlevel  = unit_to_value($1) if $nav  && $nav  =~ /((?:left|right) .+)/;

  if (defined $zoomlevel) {
    warn "zoom = $zoom, zoomlevel = $zoomlevel" if DEBUG;
    my $center	    = int($span / 2) + $start;
    my $range	    = int($span * (1-$zoomlevel)/2);
    $range          = 2 if $range < 2;
    ($start, $stop) = ($center - $range , $center + $range -1);
  }

  elsif (defined $navlevel){
    $start += $navlevel;
    $stop  += $navlevel;
  }

  elsif (defined $overview_x && defined $segment_length) {
    my $overview_width = $settings->{width} * OVERVIEW_RATIO;
    my $click_position = $segment_length * $overview_x/$overview_width;
    $span = $DEFAULT_SEGMENT if $span > $MAX_SEGMENT;
    $start = int($click_position - $span/2);
    $stop  = $start + $span - 1;
  }

  elsif ($selected_span) {
    my $center	    = int($span / 2) + $start;
    my $range	    = int(($selected_span)/2);
    ($start, $stop) = ($center - $range , $center + $range -1);
  }

  # to prevent from going off left end
  $start = 1 if $start < 1;
  $stop  = $start + ($span > 4 ? $span - 1 : 4) if $stop <= $start+2;

  $settings->{start} = $start;
  $settings->{stop}  = $stop;
}


# interesting heuristic way of fetching sequence segments based on educated guesses
sub get_segments {
  my $settings = shift;
  my @segments;

  my $db = open_database();
  unless ($db) {
    error("ERROR: Unable to open database",$CONFIG->setting('description'),pre($@));
    footer();
    exit 0;
  }

  $db->debug(0);

  if (my $name = $settings->{name}) {
    @segments = $CONFIG->name2segments($name,$db,TOO_MANY_SEGMENTS);
  }

  elsif (my $ref = $settings->{ref}) {
    my @argv = (-name  => $ref);
    push @argv,(-start => $settings->{start}) if defined $settings->{start};
    push @argv,(-stop  => $settings->{stop})  if defined $settings->{stop};
    @segments = $db->segment(@argv);
  }

  # some segments are not going to support the absolute() method
  # if they come out of BioPerl
  eval {$_->absolute(1)} foreach @segments;

  return unless @segments;
  # Filter out redundant segments; this can happen when the same basic feature is
  # present under several names, such as "genes" and "frameworks"
  my %seenit;
  @segments = grep {!$seenit{$_->name,$_->ref,$_->start,$_->end}++} @segments;
  return @segments if @segments > 1;

  # set CGI name parameter to match segment.
  # this prevents any confusion over (ref,start,stop) and (name) addressing.
  $settings->{ref}   = $segments[0]->seq_id;
  $settings->{start} = $segments[0]->start;
  $settings->{stop}  = $segments[0]->stop;

  return $segments[0];
}

# this gets called when -- for whatever reason -- we got a truncated segment
sub truncated_segment {
  my $seg   = shift;
  my ($trunc_left,$trunc_right) = @{$seg->truncated} if $seg->truncated;
  my $ref   = $seg->seq_id;
  my $db    = open_database();
  my $whole = $db->segment($ref);
  return $db->segment(-name=>$ref,-start=>$whole->stop-4,-stop=>$whole->stop) if $trunc_right;
  return $db->segment(-name=>$ref,-start=>1,-stop=>4)                         if $trunc_left;
}

################ perform keyword search ###############
sub do_keyword_search {
  my $settings = shift;
  my $segments = shift;
  my $searchterm = $settings->{name};

  my $match_sub = 'sub {';
  foreach (split /\s+/,$searchterm) {
    $match_sub .= "return unless \$_[0] =~ /\Q$_\E/i; ";
  }
  $match_sub .= "};";
  my $match = eval $match_sub;

  my $db = open_database();
  my @matches = grep { $match->($_->[1]) }
    $db->search_notes($searchterm,MAX_KEYWORD_RESULTS);
  my @results;
  for my $r (@matches) {
    my ($name,$description,$score) = @$r;
    my ($seg) = $db->segment($name) or next;
    push @results,Bio::Graphics::Feature->new(-name   => $name,
					      -class  => $name->class,
					      -type   => $description,
					      -score  => $score,
					      -ref    => $seg->abs_ref,
					      -start  => $seg->abs_start,
					      -stop   => $seg->abs_stop);

  }
  @$segments = @results;
}

################ format keyword search ###################
sub multiple_choices {
  my ($settings,$results) = @_;
  my $db   = open_database();
  my $name = $settings->{name};
  my $regexp = join '|',($name =~ /(\w+)/g);

  # sort into bins by reference
  my %refs;
  foreach (@$results) {
    my $ref = $_->seq_id;
    push @{$refs{$ref}},$_;
  }

  $CONFIG->width($settings->{width}*OVERVIEW_RATIO);
  my $overviews = $CONFIG->hits_on_overview($db,$results);
  my $count = @$results;

  print start_table();
  print TR({-class=>'datatitle'},th({-colspan=>4},
	      "The following $count regions match your request."));
  my $url = url(-relative=>1,-path_info=>1);

  local $^W = 0;  # get rid of non-numeric warnings coming out of by_score_and_position
  for my $ref(sort keys %refs) {
    my @results = @{$refs{$ref}};
    print TR(th({-class=>'databody',-colspan=>4,-align=>'CENTER'},"Matches on $ref",br,
		$overviews->{$ref}));
    for my $r (sort by_score_and_position @results) {
      my $name        = eval {$r->name}  || $r->primary_tag;
      my $class       = eval {$r->class} || 'Sequence';
      my $score       = eval {$r->score} || 'n/a';
      my ($start,$stop) = ($r->start,$r->end);
      my $description = escapeHTML(eval{$r->notes}||eval{$r->method}||eval{$r->source_tag}||$r->{ref});
      my $n           = escape($name);
      my $c           = escape($class);
      $description =~ s/($regexp)/<b class="keyword">$1<\/b>/ig;

      my $objref     = $class ? "$url?name=$c:$n" : "$url?name=$n";
      my $posref     = "$url?ref=$ref;start=$start;stop=$stop";
      my $position = format_segment($r);
      print TR({-class=>'databody',-valign=>'TOP'},
	       th({-align=>'RIGHT'},ref($name) ? a({-href=>$objref},$name):tt($name)),
	       td($description),
	       td(a({-href=>$posref},$position . ' ('.($stop-$start+1).' bp)')),
	       td("score=$score"));
    }
  }
  print end_table;

}

sub by_score_and_position {
  my $result = eval{$b->score <=> $a->score};
  return $result unless $result == 0;

  return $a->seq_id cmp $b->seq_id
    ||
      $a->start<=>$b->start
	||
	  $a->end<=>$b->end;
}

sub format_segment {
  my $s = shift or return 'n/a';
  my $ref = $s->seq_id;
  my $start = commas($s->start);
  my $stop  = commas($s->end);
  return "<b>$ref</b>:$start..$stop";
}

sub open_database {
  my $source  = $CONFIG->source;
  return $DB{$source} if $DB{$source};
  my @argv = eval{$CONFIG->dbgff_settings};
  unless (@argv) {
    warn "gbrowse: trying to reload config, cache must be stale";
    $CONFIG = Bio::Graphics::Browser->new;
    $CONFIG->read_configuration($CONF_DIR) or die "Can't read configuration files: $!";
    $CONFIG->source($source);
    @argv = $CONFIG->dbgff_settings;
  }
  $DB{$source} = eval {Bio::DB::GFF->new(@argv)} or warn $@;
  return $DB{$source};
}

sub overview {
  my ($segment,$settings) = @_;
  return unless $segment;
  $CONFIG->width($settings->{width}*OVERVIEW_RATIO);

  my ($image,$length) = $CONFIG->overview($segment) or return;
  my ($width,$height) = $image->getBounds;
  my $url             = $CONFIG->generate_image($image);
  return image_button(-name=>'overview',
		      -src=>$url,
		      -width=>$width,
		      -height=>$height,
		      -border=>0,
		      -align=>'MIDDLE')
    .hidden(-name=>'seg_length',-value=>$length,-override=>1);
}

sub get_ranges {
  my @ranges	= split /\s+/,$CONFIG->setting('zoom levels') || DEFAULT_RANGES;
  @ranges;
}

sub get_zoomincrement {
  my $zoom      = $CONFIG->setting('fine zoom')  || DEFAULT_FINE_ZOOM;
  $zoom;
}

sub segment2link {
  my ($base,$segment) = @_;

  my $source = $CONFIG->source;
  return  a({-href=>"$base?source=$source;name=$segment"},$segment) unless ref $segment;

  my ($start,$stop) = ($segment->start,$segment->end);
  my $ref = $segment->seq_id;
  my $bp = $stop - $start;
  my $s = commas($start);
  my $e = commas($stop);
  return a({-href=>"$base?source=$source;ref=$ref;start=$start;stop=$stop"},"$ref:$s..$e");
}


sub show_examples {
  my $examples = $CONFIG->setting('examples') or return;;
  my @examples = split /\s+/,$examples;
  return unless @examples;
  my $url    = url(-relative=>1,-path_info=>1);
  my $source = $CONFIG->source;
  my @urls = map { a({-href=>"$url?source=$source;name=".escape($_)},$_) } @examples;
  return b('Examples: ').join(', ',@urls) .'.  '.a({-href=>general_help(),-target=>'help'},b('[Help]'));
}

sub debugging_rectangles {
  my ($image,$boxes) = @_;
  my $black = $image->colorClosest(0,0,0);
  foreach (@$boxes) {
    my @rect = @{$_}[1,2,3,4];
    $image->rectangle(@{$_}[1,2,3,4],$black);
  }
}

########## upload stuff ########
sub handle_upload {
  my ($settings,$fh) = @_;
  warn "handle_upload($settings,$fh)" if DEBUG;
  # $fh is a CGI string/filehandle object, so be careful
  my $filename = "$fh";
  my $fh_out = open_uploaded_file($settings,$filename,'>') or return;
  while (<$fh>) {
    print $fh_out $_;
  }
  close $fh_out;
  my (undef,$url) = name_uploaded_file($settings,$filename);
  warn "url = $url" if DEBUG;
  push @{$settings->{tracks}},$url;
  $settings->{features}{$url} = {visible=>1,options=>0,limit=>0};
}

sub handle_edit {
  my ($settings,$data) = @_;
  my $file = param('edited file') or return;
  my @lines = unexpand(split /\r?\n|\r\n?/,$data);
  $data = join "\n",@lines;
  $data .= "\n";
  my $fh = open_uploaded_file($settings,$file,'>');
  print $fh $data;
  close $fh;
}

sub handle_quickie {
  my ($settings,$data) = @_;
  return unless $data;

  # format of quickie data is reference+type+name+start-stop,start-stop,start-stop
  my ($reference,$type,$name,$position) = shellwords($data||'');
  my @segments = map { [/(-?\d+)(?:-|\.\.)(-?\d+)/]} split /,/,$position;
  my $feature = Bio::Graphics::Feature->new(
					    -ref      => $reference||'',
					    -type     => $type||'',
					    -name     => $name||'',
					    -segments => \@segments,
					    );
  write_auto($settings,[$feature]);
}

sub write_auto {
  my ($settings,$features) = @_;

  my $file = 'search_results';
  clear_uploaded_file($settings,$file);
  return unless @$features;

  my %seenit;

  my $out = open_uploaded_file($settings,$file,">>") or return;
  for my $f (@$features) {
    my $reference = $f->can('seq_id') ? $f->seq_id : $f->seq_id;
    my $type      = $f->primary_tag;
    my $name      = $f->seqname;
    my $position  = $f->sub_SeqFeature ? join (',',map {$_->start.'..'.$_->end} $f->sub_SeqFeature)
                                       : $f->start.'..'.$f->end;
    $name .= "($seenit{$name})" if $seenit{$name}++;
    print $out "\nreference=$reference\n";
    print $out join ("\t",qq("$type"),qq("$name"),$position),"\n";
  }
  close $out;
  my (undef,$url) = name_uploaded_file($settings,$file);
  push @{$settings->{tracks}},$url;
  $settings->{features}{$url} = {visible=>1,options=>0};
}

sub name_uploaded_file {
  my ($settings,$filename) = @_;
  warn "name_uploaded_file(): filename = $filename" if DEBUG;
  # keep last non-[/\:] part of name
  my ($name) = $filename =~ /([^:\\\/]+)$/;
  my $id = $settings->{id} or return;
  my (undef,$tmpdir) = $CONFIG->tmpdir($CONFIG->source."/uploaded_file/$id");
  my $physical = "$tmpdir/$filename";
  my $url      = "file:$filename";
  return wantarray ? ($physical,$url) : $physical;
}

sub open_uploaded_file {
  my ($settings,$filename,$mode) = @_;
  $filename =~ s/^file://;

  my $file = name_uploaded_file($settings,$filename);
  warn "file = $file" if DEBUG;
  unless ($file) {
    error("Can't find the file named $filename.  Perhaps it has been purged?");
    clear_uploaded_file($settings,$filename);
    return;
  }

  my $result = open (F,"${mode}${file}");

  unless ($result) {
    warn "Can't open the file named $filename.  Perhaps it has been purged? (error: $!)";
    clear_uploaded_file($settings,$filename);
    return;
  }

  return \*F;
}

sub load_external_sources {
  my ($segment,$page_settings) = @_;
  my @feature_file = load_uploaded_files($segment,$page_settings);
  warn "uploaded feature_file = @feature_file" if DEBUG;

  my @external = load_remote_sources($segment,$page_settings);
  push @feature_file,@external if @external;

  my %feature_file = map {(ref($_) ? $_->name: $_) => $_} @feature_file;
  warn join "\n",%feature_file if DEBUG;
  \%feature_file;
}

sub load_uploaded_files {
  my ($segment,$settings) = @_;
  my @files;
  my $width = $settings->{width} or return;
  my $rel2abs = coordinate_mapper($segment) if $segment;

  my @uploads = grep {/^file:/} @{$settings->{tracks}};
  my @result;
  for my $file (@uploads) {
    warn "loading $file" if DEBUG;
    if (!$settings->{features}{$file}{visible}) { # turned off
      push @result,$file;
      next;
    }

    my $fh = open_uploaded_file($settings,$file,"<") or return;

    # nasty little bit in which we handle differing line-endings for the various
    # types of operating systems...
    my $agent  = CGI->user_agent();
    local $/ = $/;
    $/ = "\r"    if $agent =~ /Mac/;
    $/ = "\r\n"  if $agent =~ /Win/;

    my $feature_file = Bio::Graphics::FeatureFile->new(-file           => $fh,
						       -map_coords     => $rel2abs,
						       -smart_features =>1);
    close $fh;
    next unless $feature_file;
    $feature_file->name($file);
    push @result,$feature_file;
  }
  @result;
}

sub load_remote_sources {
  my ($segment,$settings) = @_;
  my @uploads = grep {/^(http|ftp):/} @{$settings->{tracks}};
  my $rel2abs = coordinate_mapper($segment) if $segment;
  my @result;
  for my $file (@uploads) {
    warn "load_remote_sources(): loading $file" if DEBUG;
    if (!$settings->{features}{$file}{visible}) { # turned off
      push @result,$file;
      next;
    }
    my $feature_file = get_remote_feature_data($file,$rel2abs) or next;
    push @result,$feature_file;
  }
  return @result;
}

sub load_plugin_annotations {
  my ($segment,$feature_files,$settings) = @_;
  for my $p (keys %$PLUGINS) {
    next unless $PLUGINS->{$p}->type eq 'annotator';
    my $name = "plugin:".$PLUGINS->{$p}->name;
    next unless $settings->{features}{$name}{visible};
    my $features = $PLUGINS->{$p}->annotate($segment) or next;
    $features->name($name);
    $feature_files->{$name} = $features;
  }
}

sub load_plugin_annotators {
  my ($settings) = @_;
  for my $p (keys %$PLUGINS) {
    next unless $PLUGINS->{$p}->type eq 'annotator';
    my $name = $PLUGINS->{$p}->name;
    $name = "plugin:$name";
    unless ($settings->{features}{$name}) {
      push @{$settings->{tracks}},$name;
      $settings->{features}{$name} = {visible=>1,options=>0,limit=>0};
    }
  }
}


sub get_remote_feature_data {
  my ($url,$rel2abs) = @_;
  warn "get_remote_feature_data(): fetching $url" if DEBUG;

  unless ($UA) {
    unless (eval "require LWP") {
      error('This browser is not configured to fetch external URLs');
      return;
    }
    $UA = LWP::UserAgent->new(agent   => "Generic-Genome-Browser/$VERSION",
			      timeout => URL_FETCH_TIMEOUT,
			      max_size => URL_FETCH_MAX_SIZE,
			     );
  }
  my $id = md5_hex($url);  # turn into a filename
  my (undef,$tmpdir) = $CONFIG->tmpdir($CONFIG->source.'/external');
  my $response = $UA->mirror($url,"$tmpdir/$id");
  if ($response->is_error) {
    error("Could not fetch $url: ",$response->message);
    return;
  }
  open (F,"<$tmpdir/$id") or return;
  my $feature_file = Bio::Graphics::FeatureFile->new(-file           => \*F,
						     -map_coords     => $rel2abs,
						     -smart_features =>1);
  $feature_file->name($url);
  warn "get_remote_feature_data(): got $feature_file" if DEBUG;
  return $feature_file;
}

sub print_uploaded_file_features {
  my ($settings,$file) = @_;
  if (my $fh = open_uploaded_file($settings,$file)) {
    while (<$fh>) {
      print;
    }
  }
}

sub get_uploaded_file_info {
  my $feature_file = shift or return i("Display off");
  warn "get_uploaded_file_info(): feature_file = $feature_file" if DEBUG;

  my $modified = localtime($feature_file->mtime);
  my @refs      = $feature_file->refs;
  my $db        = open_database();

  my ($landmarks,@landmarks);
  my $url      = url(-relative=>1,-path_info=>1);

  if (@refs > TOO_MANY_REFS) {
    $landmarks = b(@refs." landmarks.  Too many to list.");
  } else {
    for my $r (sort @refs) {
      my $features = $feature_file->features;
      my @features = grep {$_->seq_id && ($_->seq_id eq $r)} map {@$_} values %{$features};
      my @merged   = @features > TOO_MANY_FEATURES ? $CONFIG->merge($db,\@features) : @features;
      my @links    = map {segment2link($url,$_)} @merged;
      @links       = segment2link($url,$r) unless @links;
      push @landmarks,@links;
    }
  }
  $landmarks = tableize(\@landmarks);
  warn "get_uploaded_file_info(): modified = $modified, landmarks = $landmarks" if DEBUG;
  return i("Last modified $modified.  Annotated landmarks:"),$landmarks;
}

sub clear_uploaded_file {
  my ($settings,$file) = @_;
  warn "clear_uploaded_file(): file = $file" if DEBUG;
  my $path = name_uploaded_file($settings,$file) or return;
  unlink $path;
  delete $settings->{features}{"file:$file"};
  warn "clear_uploaded_file(): deleting file = file:$file" if DEBUG;
  $settings->{tracks} = [grep {$_ ne "file:$file"} @{$settings->{tracks}}];
}

sub edit_uploaded_file {
  my ($settings,$file) = @_;
  warn "edit_uploaded_file(): file = $file" if DEBUG;
  print start_form();
  my $data;
  my $fh = open_uploaded_file($settings,$file) or return;
  $data = join '',expand(<$fh>);
  print table({-width=>'100%'},
	      TR({-class=>'searchbody'},
		 td('Edit your uploaded annotation data here.',
		    'You may use tabs or spaces to separate fields,',
		    'but fields that contain whitespace must be contained in',
		    'double or single quotes.',
		   ),
		),
	      TR({-class=>'searchbody'},
		 td(
		    a({-href=>url(-relative=>1,-path_info=>1)."?help=annotation#format",-target=>'help'},
		      b('[Help with File Format]'))
		   ),
		),
	      TR({-class=>'searchtitle'},
		 th('Enter/Edit Annotation data')),
	      TR({-class=>'searchbody'},
		 td({-align=>'CENTER'},
		    pre(
			textarea(-name    => 'a_data',
				 -value   => $data,
				 -rows    => ANNOTATION_EDIT_ROWS,
				 -cols    => ANNOTATION_EDIT_COLS,
				 -wrap    => 'off',
				 -style   => "white-space : pre"
				))
		   )
		),
	      TR({-class=>'searchtitle'},
		 th(reset('Undo Changes').'&nbsp;'.
		    submit('Cancel').'&nbsp;'.
		    b(submit('Submit Changes...'))))
	     );
  print hidden(-name=>'edited file',-value=>$file);
  print end_form();
}

sub coordinate_mapper {
  my $current_segment = shift;
  my $db              = open_database();

  my ($ref,$start,$stop) = ($current_segment->seq_id,$current_segment->start,$current_segment->stop);
  my %segments;

  my $closure = sub {
    my ($refname,@ranges) = @_;

    unless ($segments{$refname}) {
      my @segments = grep {
	$_->abs_ref eq $ref && $_->abs_start <= $stop && $_->abs_stop >= $start
      } $CONFIG->name2segments($refname,$db,TOO_MANY_SEGMENTS);
      return unless @segments;
      $segments{$refname} = $segments[0];
    }
    my $mapper   = $segments{$refname};
    my $absref   = $mapper->abs_ref;
    my @abs_segs = map {[$mapper->rel2abs($_->[0],$_->[1])]} @ranges;

    # this inhibits mapping outside the displayed region
    foreach (@abs_segs) {
      return ($absref,@abs_segs) if $_->[0] <= $stop && $_->[1] >= $start;
    }
    return;
  };
  return $closure;
}

sub error {
  warn "@_" if DEBUG;
  print header() unless $HEADER++;
  print start_html(-title => 'Genome browser',
		   -style  => {src=>$CONFIG->setting('stylesheet')}) unless $HTML++;
  print h2({-class=>'error'},@_);
}

sub bookmark_link {
  my $settings = shift;
  my $q = new CGI('');
  my @keys = $settings->{name} ? qw(name source width)
                               : qw(start stop ref source width);
  foreach (@keys) {
    $q->param(-name=>$_,-value=>$settings->{$_});
  }

  # handle selected features slightly differently
  my @selected = grep {$settings->{features}{$_}{visible} && !/^(file|ftp|http):/} @{$settings->{tracks}};
  $q->param(-name=>'label',-value=>join('-',@selected));

  # handle external urls
  my @url = grep {/^(ftp|http):/} @{$settings->{tracks}};
  $q->param(-name=>'eurl',-value=>\@url);

  return $q->url(-relative=>1,-path_info=>1,-query=>1);
}

# reorder @labels based on settings in the 'track.XXX' parameters
sub adjust_track_order {
  my $settings = shift;

  my @labels  = @{$settings->{tracks}};
  warn "adjust_track_order(): labels = @labels" if DEBUG;

  my %seen_it_already;
  foreach (grep {/^track\./} param()) {
    warn "$_ =>",param($_) if DEBUG;
    next unless /^track\.(\d+)/;
    my $track = $1;
    my $label   = param($_);
    next unless length $label > 0;
    next if $seen_it_already{$label}++;
    warn "$label => track $track" if DEBUG;

    # figure out where features currently are
    my $i = 0;
    my %order = map {$_=>$i++} @labels;

    # remove feature from wherever it is now
    my $current_position = $order{$label};
    warn "current position of $label = $current_position" if DEBUG;
    splice(@labels,$current_position,1);

    warn "new position of $label = $track" if DEBUG;
    # insert feature into desired position
    splice(@labels,$track,0,$label);
  }
  $settings->{tracks} = \@labels;
}

sub adjust_track_options {
  my $settings = shift;
  foreach (grep {/^option\./} param()) {
    my ($track)   = /(\d+)/;
    my $feature   = $settings->{tracks}[$track];
    my $option    = param($_);
    $settings->{features}{$feature}{options} = $option;
  }
  foreach (grep {/^limit\./} param()) {
    my ($track)   = /(\d+)/;
    my $feature   = $settings->{tracks}[$track];
    my $option    = param($_);
    $settings->{features}{$feature}{limit} = $option;
  }
  foreach (@{$settings->{tracks}}) {
    $settings->{features}{$_}{visible} = 0;
  }

  foreach (param('track.label')) {
    $settings->{features}{$_}{visible} = 1;
  }
}

# this controls the "adjust track options" screen
sub set_track_options {
  my $settings = shift;

  my @labels = @{$settings->{tracks}};

  my %keys            = map {$_ => $CONFIG->setting($_=>'key') || $_} @labels;
  my @sorted_labels   = ('',sort {lc $keys{$a} cmp lc $keys{$b}} @labels);

  my @rows;
  for (my $track = 0; $track < @labels; $track++) {
    my $label = $labels[$track];
    push @rows,
      th({-align=>'LEFT',-class=>'searchtitle'},"Track",$track+1).
      th({-align=>'LEFT',-class=>'searchbody'},$keys{$label}).
      td({-align=>'CENTER',-class=>'searchbody'},
	     checkbox(-name     => 'track.label',
		      -value    => $label,
		      -override => 1,
		      -checked  => $settings->{features}{$label}{visible},
		      -label => '')
	    ).
      td({-align=>'CENTER',-class=>'searchbody'},
	     popup_menu( -name     => "option.$track",
			 -values   => [0..5],
			 -override => 1,
			 -default  => $settings->{features}{$label}{options},
			 -labels   => {0=>'Auto',
                                       1=>'Compact',
                                       2=>'Expand',3=>'Expand & Label',
                                       4=>'Hyperexpand',5=>'Hyperexpand & label'})
			).
	td({-align=>'CENTER',-class=>'searchbody'},
	   popup_menu(-name    => "limit.$track",
		      -values  => [0,5,10,25,100],
		      -labels  => {0=>'No limit'},
		      -override => 1,
		      -default => $settings->{features}{$label}{limit})
	    ).
	td({-align=>'CENTER',-class=>'searchbody'},
	   popup_menu(-name    => "track.$track",
		      -values  => \@sorted_labels,
		      -labels  => \%keys,
		      -override => 1,
		      -onChange => 'document.settings.submit()',
		      -default => '')
	    );
  }
  my $controls = TR({-class=>'searchtitle'},
		    td({-colspan=>3,-align=>'CENTER'},
		       reset('Undo Changes').'&nbsp;'.
		       submit('Revert to Defaults').'&nbsp;'.
		       submit('Refresh').'&nbsp;'
		      ),
		    td({-align=>'CENTER',-colspan=>3},
		       submit(-name=>'Cancel',-value=>'Cancel Changes and Return...').'&nbsp;'.
		       b(submit(-name=>'Redisplay',-value=>'Accept Changes and Return...'))
		      ));

  print h1({-align=>'CENTER'},'Settings for ',$CONFIG->setting('description'));
  print start_form(-name=>'settings');
  print table({-width=>'100%',-border=>0},
	      $controls,
	      TR({-class=>'searchtitle'},
		 th({-colspan=>6},'Track Options')),
	      TR({-class=>'searchbody'},
		 td({-colspan=>6},
		    'The',i('Show'),'checkbox turns the track on and off.',
		    'The',i('Compact'),'option forces the track to be condensed so that',
		    'annotations will overlap. The',i('Expand'),'and',i('Hyperexpand'),
                    'options turn on collision control using slower and faster layout algorithms.',
		    'The',i('Expand & label'),'and',i('Hyperexpand & label'), 'options force',
                    'annotations to be labeled.  If',i('Auto'),'is selected, the bump and label',
		    'options will be set automatically if space permits.',
		    'To change the track order use the',i('Change Track Order'),'popup menu',
		    'to assign an annotation to a track.',
                    'To limit the number of annotations of this type shown, change the value of the',
                    i('Limit'),'menu.',
		   ),
		),
	      TR({-class=>'searchtitle'},
		 th('Track'),
		 th('Track Type'),
		 th('Show'),
		 th('Format'),
		 th('Limit'),
		 th('Change Track Order'),
		),
	      TR(\@rows),
	      $controls,
	      hidden(-name=>'Set Track Options...',-value=>1,-override=>1),
	      hidden(-name=>'Adjust Order',-value=>1,-override=>1),
	     );
    print end_form();
}

sub help {
  my ($help_type,$conf_dir,$settings) = @_;

  my $ref = referer();
  my $do_close = join('',
		      start_form(-action=>$ref),
		      button(-onClick=>'window.close()',-label=>'Close this Window'),
		      end_form());
  print div({-align=>'RIGHT'},$do_close);
  if ($help_type eq 'citations') {
    build_citation_page($settings);
  } else {
    build_help_page("$conf_dir/${help_type}_help.html");
  }
  print div({-align=>'RIGHT'},$do_close);
}

# build a citation page
sub build_citation_page {
  my $settings = shift;
  my @labels   = labels($settings);

  my @features = $CONFIG->labels;
  my $external_features = load_external_sources(undef,$settings);
  my (@citations);

  print h2('Track Descriptions & Citations');

  # build native features
  print h3('Tracks Built into this Server');
  for my $feature (@features) {
    push @citations,make_citation($CONFIG,$feature);
  }
  print blockquote(dl(@citations));

  # build external features
  if (%$external_features) {
    print hr,h3('External Annotation Tracks');
    @citations = ();
    for my $file (keys %$external_features) {
      my $f = escape($file);
      my $name   = $file;
      my $is_url = $name =~ m!^(http|ftp)://!;
      my $link   = $is_url  ? $name  : url(-relative=>1,-path_info=>1)."?Download+Data=1;file=$f";
      my $anchor = $name;
      $anchor =~ tr/ /-/;

      unless (ref $external_features->{$file}) {
	print h3(a{-name=>$anchor,-href=>$link},$name);
	print blockquote('Please activate this track in order to view its information');
	next;
      }
      print h4(a{-name=>$anchor,-href=>$link},$name);
      for my $feature ($external_features->{$file}->types) {
	push @citations,make_citation($external_features->{$file},$feature);
      }
      print blockquote(dl(@citations));
    }
    print p("No external features loaded.") unless @citations;
  }

}

sub make_citation {
  my $config  = shift;
  my $feature = shift;
  my $citation = $config->citation($feature);
  # BUG: here's where we should remove "bad" HTML, but we don't!
  # should remove active content and other nasties
  (my $link     = $feature) =~ tr/ /-/;
  my $text      = $config->setting($feature=>'key') || $feature;
  return join ('',
	       dt(a({-name=>$link},b($text))),
	       dd($citation||'No additional information available'),
	       p());
}

sub build_help_page {
  my $helpfile = shift or return;
  my $file = $ENV{MOD_PERL} ? Apache->request->lookup_uri($helpfile)->filename
                            : "$ENV{DOCUMENT_ROOT}/$helpfile";
  my $root = $CONFIG->setting('help') || GBROWSE_HELP;
  my $url  = url(-relative=>1);
  open(F,$file) or return;
  while (<F>) { # fix up relative addressing of images
    s/(src|href)=\"([^\"\#\$]+)\"/$1=\"$root\/$2\"/g;
    s/<!--\s*\#include-classes\s*-->/object_classes_for_help()/e;
    s/href=\"\$GBROWSE/href=\"$url/g;
    print;
  }
  close F;
}

# get list of object types for help pages
sub object_classes_for_help {
  return $OBJECT_TYPES{$CONFIG->source} if exists $OBJECT_TYPES{$CONFIG->source};
  my $db = open_database();
  my @classes = eval {$db->classes};
  return $OBJECT_TYPES{$CONFIG->source} = undef unless @classes;
  return $OBJECT_TYPES{$CONFIG->source} = ul(li(\@classes));
}

# Create a link to a citation.  It will point to an external URL if the
# citation looks like a URL (starts with http: or ftp:).  It will be
# self-referential otherwise.

# The persistent problem here is that the regular features are cited on a
# feature-by-feature basis, while the uploaded/external ones are cited as
# a group.  This makes for ugly logic branches.
sub make_citation_link {
  my ($label,$self_url)   = @_;
  my $key      = $CONFIG->setting($label=>'key') || $label;
  (my $anchor  = $label) =~ tr/ /-/;
  my $link = $self_url.'#'.escapeHTML($anchor);
  return a({-href=>$link,-target=>'citation'},$key);
}

### PLUGINS ###################################################################################
###############################################################################################
sub initialize_plugins {
  my $path = shift;
  my %plugin_list = ();

  my $plugins = "$path/plugins";
  warn "initializing plugins..." if DEBUG_PLUGINS;

  croak("$plugins: not a directory") unless -d $plugins;
  opendir(D,$plugins) or croak "Couldn't open $plugins: $!";
  my @plugins = map { "$plugins/$_" } grep {/\.pm$/} readdir(D);
  close D;

  # try to work around a bug in Apache/mod_perl which appears when
  # running under linux/glibc 2.2.1
  unless (@plugins) {
    @plugins = glob("$plugins/*.pm");
  }

  for my $plugin (@plugins) {
    my $base = basename($plugin,'.pm');
    my $class = "Bio\:\:Graphics\:\:Browser\:\:Plugin\:\:$base";
    if (eval {require $plugin}) {
      warn "plugin $base loaded successfully" if DEBUG_PLUGINS;
      my $obj = $class->new;
      warn "plugin name = ",$obj->name," base = $base" if DEBUG_PLUGINS;
      $plugin_list{$base} = $obj;
    } else {
      warn $@ if $@;
    }
  }
  return \%plugin_list;
}

sub configure_plugins {
  my ($plugins,$settings,$db,$conf,$conf_dir) = @_;
  for my $name (keys %$plugins) {
    my $p = $plugins->{$name};
    $p->database($db);
    $p->browser_config($conf);
    $p->config_path($conf_dir);
    $p->page_settings($settings);
    $p->init();  # other initialization

    # retrieve persistent configuration
    my $config = retrieve_plugin_config($p);
    # and tell the plugin about it
    $p->configuration($config);

    # if there are any CGI parameters from the
    # plugin's configuration screen, set it here
    my @params = grep {/^$name\./} param();
    next unless @params;
    $p->reconfigure;
  }
}

sub plugin_and_data_source_table {
  my ($settings,$plugins) = @_;
  my $sources = $CONFIG->sources > 1;

  my %verbs = (dumper    => 'Dump',
	       finder    => 'Find',
	       annotator => 'Annotate');
  my %labels = map {$_=> ($verbs{$plugins->{$_}->type}
			  ||
			  $plugins->{$_}->type)
		      .' '.$plugins->{$_}->name}
    keys %$plugins;

  my @plugins = sort {$labels{$a} cmp $labels{$b}} keys %labels;
  my $table = table({-border=>0,-width=>$settings->{width}},
		    TR({-class=>'searchtitle'},
		       th({-align=>'left'},
			  'Dumps, Searches and other Operations:'),
		       $sources ? th({-align=>'left'},'Data Source:') : th('&nbsp;'),
		      ),
		    TR({-class=>'searchtitle'},
		       td({-colspan=>1,-align=>'left'},
			  popup_menu(-name=>'plugin',
				     -values=>\@plugins,
				     -labels=>\%labels,
				    ),'&nbsp;',
			  submit(-name=>'plugin_action',-value=>'About...'),'&nbsp;',
			  submit(-name=>'plugin_action',-value=>'Configure...'),'&nbsp;',
			  submit(-name=>'plugin_action',-value=>'Go!'),
			 ),
		       td({-colspan=>1,-align=>'left'},
			  $sources ?
			  popup_menu(-name   => 'source',
				     -values => [sort $CONFIG->sources],
				     -labels => { map {$_ => $CONFIG->description($_)} $CONFIG->sources},
				     -default => $CONFIG->source,
                                     -onChange => 'document.mainform.submit()',
				    )
			 : '&nbsp;')
		      )
		   );
  $table;
}

sub do_plugin_dump {
  my $plugin  = shift;
  my $segment = shift;
  my $p = $PLUGINS->{$plugin} or return;
  $p->dump($segment);
  return 1;
}

sub do_plugin_about {
  my $plugin = shift;
  my $p = $PLUGINS->{$plugin};
  print h1("About",$p->name);
  print $p->description;
  print start_form(),submit('Back to Browser'),hidden('plugin'),end_form();
}

sub do_plugin_find {
  my ($settings,$plugin,$segments,$search_string) = @_;

  my $p = $PLUGINS->{$plugin} or return;
  my $plugin_name = $p->name;

  my $results = $p->can('auto_find') && defined $search_string
    ? $p->auto_find($search_string) : $p->find($segments);
  return unless $results;  # reconfigure message

  @$segments = @$results;
  $settings->{name} = defined($search_string) ? "$search_string (via $plugin_name search)"
                                              : "&lt;$plugin_name search&gt;";
  # remember the search
  write_auto($settings,$results);
  1; # return a true result to indicate that we don't need further configuration
}

sub do_plugin_configure {
  my $plugin = shift;
  my $p = $PLUGINS->{$plugin} or return;
  my $action_label = $p->type eq 'finder' ? 'Find'
    : $p->type eq 'annotator' ? 'Configure'
    : 'Go!';

  print h1($p->type eq 'finder' ? 'Find' : 'Configure',$p->name);
  my $config_html = $p->configure_form;

  print start_form(),
    $config_html ? (
		    $config_html,p(),
		    submit(-name=>'plugin_action',-value=>'Cancel'),'&nbsp;',
		    b(submit(-name=>'plugin_action',-value=>$action_label)),
		    # This is an insurance policy in case user hits return in text field
		    # in which case the plugin_action is not going to be defined
		    hidden(-name=>'plugin_action',-value=>$action_label,-override=>1),
		   )
                 : ( p('This plugin has no extra configuration settings.'),
		     b(submit('Back to Browser'))
		   ),
     hidden('plugin'),
     end_form();
}

# invoke any finder plugins that define the auto_find() method
sub do_plugin_autofind {
  my ($settings,$segments) = @_;

  for my $p (keys %$PLUGINS) {
    next unless $PLUGINS->{$p}->type eq 'finder' && $PLUGINS->{$p}->can('auto_find');
    do_plugin_find($settings,$p,$segments,$settings->{name});
    last if @$segments;
  }
}

sub retrieve_plugin_config {
  my $plugin = shift;
  my $name   = $plugin->name;
  my %settings = cookie("${name}_config");
  return $plugin->config_defaults unless %settings;
  foreach (keys %settings) {
    # need better serialization than this...
    if ($settings{$_} =~ /$;/) {
      my @settings = split $;,$settings{$_};
      pop @settings unless defined $settings[-1];
      $settings{$_} = \@settings;
    }
  }
  \%settings;
}

sub plugins2cookies {
  my $plugins = shift;
  my @cookies;
  for my $plugin (values %$plugins) {
    my $name = $plugin->name;
    my $conf = $plugin->configuration or next;
    my %conf = %$conf;

    # we need a better serialization than this...
    for my $key (keys %conf) {
      if (ref $conf{$key} eq 'ARRAY') {
	$conf{$key}  = join $;,@{$conf{$key}};
	$conf{$key} .= $; unless $conf{$key} =~ /$;/;
      }
    }
    push @cookies,cookie(-name    => "${name}_config",
			 -value   => \%conf,
			 -expires => '+3M');
  }
  warn "plugin cookies = @cookies" if DEBUG_PLUGINS;
  @cookies;
}

sub tableize {
  my $array = shift;
  return unless @$array;
  my $rows    = int(sqrt(@$array));
  my $columns = int(0.99+@$array/$rows);
  my $html = qq(<table border="1">);
  for (my $row=0;$row<$rows;$row++) {
    $html .= "<tr>";
    for (my $column=0;$column<$columns;$column++) {
      $html .= "<td>" . $array->[$column*$rows + $row] . "</td>"
	if defined($array->[$column*$rows + $row]);
    }
    $html .= "</tr>\n";
  }
  $html .= "</table>\n";
}

sub footer {
  ## FOOTER
  print
    $CONFIG->footer || '',
      p(i(font({-size=>'small'},
	       'Note: This page uses cookie to save and restore preference information.',
	       'No information is shared.')),br,
       tt(font({-size=>'small'},"Generic genome browser version $VERSION"))),
       end_html;
}

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;
