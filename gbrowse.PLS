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
# $Id: gbrowse.PLS,v 1.12 2002-02-20 22:12:15 lstein Exp $

use strict;
use Bio::DB::GFF;
use Bio::Graphics;
use Bio::Graphics::Browser;
use Digest::MD5 'md5_hex';
use File::Path 'mkpath';
use Text::Tabs;
use Text::Shellwords;
use Carp;
use CGI qw(:standard escape center *table *dl *TR *td);
use vars qw($CONFIG %DB $MAX_SEGMENT $DEFAULT_SEGMENT $HEADER $HTML $UA $VERSION $CONF_DIR);

# if you change the zoom/nav icons, you must change this as well.
use constant MAG_ICON_HEIGHT => 20;
use constant MAG_ICON_WIDTH  => 8;
use constant MAX_SEGMENT     => 1_000_000;
use constant TOO_MANY_SEGMENTS => 5_000;
use constant DEFAULT_SEGMENT => 100_000;
use constant OVERVIEW_RATIO  => 0.9;
use constant ANNOTATION_EDIT_ROWS => 25;
use constant ANNOTATION_EDIT_COLS => 100;
use constant URL_FETCH_TIMEOUT    => 5;  # five seconds max!
use constant URL_FETCH_MAX_SIZE   => 1_000_000;  # don't accept any files larger than 1 Meg
use constant MAX_KEYWORD_RESULTS  => 50;  # max number of results from keyword search
use constant DEFAULT_RANGES       => q(100 500 1000 5000 10000 25000 100000 200000 400000);
use constant DEFAULT_FINE_ZOOM    => '10%';

# if true, turn on surrounding rectangles for debugging the image map
use constant DEBUG => 0;
use constant DEBUGGING_RECTANGLES => 0;

# IMPORTANT DATA STRUCTURES

# $SETTINGS (also called $page_settings): hash reference containing state information
# keys:
#   name      name of a landmark to search for (e.g. keyword search)
#   ref       sequence landmark reference ID (once found)
#   start     start of range relative to ref
#   stop      stop of range relative to ref
#   source    symbolic name of database/configuration to use
#   eurl      array of external URLs to load
#   id        unique cookie-based ID for this user
#   track     array ref which has one element for each track on the
#               display.  The value of each element indicates what
#               track to display in that position.  For example:
#               [3,1,2] means display tracks 3, 1, and 2 in that
#               order.  Tracks are numbered from zero, and default
#               to their order in the configuration file.  Uploaded feature
#               data is track N, where N is the number of tracks defined
#               in the configuration file.  External URL tracks are N+1, N+2,
#               and so on.
#   labels    array ref which has one element for each track on the
#               display.  A true value indicates that the track should
#               be shown.  (NOTE: this key is poorly named; originally,
#               the field was an array of track labels)
#   options   array ref which has one element for each track on the
#               display.  Values control the display options for the
#               track, where 0=automatic, 1=force bump, and 2=force bump & label

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
};

$HEADER=0;
$HTML=0;

if ($ENV{MOD_PERL}) {
    my $conf  = Apache->request->dir_config('GBrowseConf');
    $CONF_DIR = Apache->server_root_relative($conf) if $conf;
}

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
###############################################################################################

## GETTING THE SEGMENT ########################################################################
my @segments  = get_segment($page_settings);
###############################################################################################

## DUMPS ######################################################################################
if ( (my $dump = param('dump')) && @segments == 1) {
  if ($dump eq 'FastA') {
    print header(-type         => 'text/plain',
                 # -attachment   => "$segments[0].fa",
                );
    dump_fasta($segments[0],$page_settings);
  }

  elsif($dump eq 'GFF') {
    print header( -type         => 'text/plain'
                # -attachment   => "$segments[0].gff",
                );
    dump_gff($segments[0],$page_settings);
  }
  exit 0;
}
###############################################################################################

# This gets called if the user wants to download his annotation data
if(param('Download Data') && $page_settings->{'uploaded_file'}) {
  print header(-attachment   =>  $page_settings->{uploaded_file},
	       -type         => 'application/octet-stream');
  print_uploaded_file_features($page_settings);
  exit 0;
}


## HANDLING FILE UPLOADS ######################################################################
if (param('Upload') && (my $file = param('upload_annotations'))) {
  handle_upload($page_settings,$file);
}

elsif (defined(my $data = param('a_data'))) {
  handle_edit($page_settings,$data);
}

elsif ($data = param('quickie')) {
  handle_quickie($page_settings,$data);
}

clear_uploaded_file($page_settings) if param('Delete Data');
adjust_tracks($page_settings);

## UPDATING THE PERSISTENT SETTINGS##############################################################
print header(-cookie => settings2cookie($page_settings)) unless $HEADER++;

my $description = $CONFIG->setting('description');
my $segment;

## STARTING THE PAGE ############################################################################

print
  start_html(-title => 'Genome browser',
	     -style  => {src=>$CONFIG->setting('stylesheet')},
	    ) unless $HTML++;

my $header = $CONFIG->header();
print $header if $header;

## HANDLE UPLOADED PARTY EDITS ##################################################################
if (param('Edit Data...')) {
  edit_uploaded_file($page_settings);
}

## AND THE ABILITY TO CHANGE DISPLAY ORDER#######################################################
elsif (param('Set Track Options...') ||
       param('Update')) {
  set_track_options($page_settings);
}

elsif (param('Revert to Defaults')) {
  set_default_tracks($page_settings);
  set_track_options($page_settings);
} elsif (param('help')) {
  help(param('help'),$CONF_DIR,$page_settings);
}

## MAIN DISPLAY
else {
  print h1($description) unless defined($header);
  main_display(\@segments,$page_settings);
}

footer();

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

#--------------------------------- lots of subroutines --------------------------

sub main_display {
  my ($segments,$page_settings) = @_;
  my ($segment,@keyword_search_results);

  # a bit confusing here, because of the way I want the formatting to work

  # first of all, if there are no segments, then try a keyword search and
  # store the results
  if (@$segments == 0 && (my $n = $page_settings->{name})) {

    # if that doesn't work, then we print a big error at the top
    unless (@keyword_search_results = do_keyword_search($n)) {
      error("The landmark named",i($n),"is not recognized.",
	    "You may need to qualify it with the type, as in",i("PCR_Product:$n"));
    }

  }

  # if there's a single segment, then print a message and store the segment
  # into a scalar
  elsif (@$segments == 1) {
    $segment = $segments->[0];
    $segment = truncated_segment($segment) if $segment->length < 4;
    print h2("Showing",unit_label($segment->length)," from",
	     $segment->ref.", positions ".commas($segment->start)." to ".commas($segment->stop));
  }

  # print the top of the form, with navigation bar, etc
  print start_multipart_form(-name=>'mainform',-action=>url(-relative=>1,-path_info=>1)),
    navigation_table($segment,$page_settings);

  # if more than one segment, then list them all
  if (@$segments > 1) {
    multiple_choices($segments,$page_settings);
  }

  # if there are keyword search results, then print those as well
  elsif (@keyword_search_results) {
    format_keyword_search($page_settings->{name},\@keyword_search_results);
  }

  # get the third party features
  my @feature_file = load_external_sources($segment,$page_settings);

  if ($segment) {
    my $cell = overview($segment,$page_settings);
    $cell .= br();
    if ($segment->length <= $MAX_SEGMENT) {
      $cell .= image_and_map($segment,\@feature_file,$page_settings);
    } else {
      $cell .= i(
		 "Detailed view is limited to",
		 commas($MAX_SEGMENT),"bases.",
		 "Click in the overview to select a region",commas($DEFAULT_SEGMENT),'bp wide.');
    }
    print table({-border=>0,-width=>$page_settings->{width}},
		TR({-class=>'searchbody'},
		   td({-align=>'CENTER'},$cell)
		  )
	       );
  }
  print hidden('ref'),hidden('start'),hidden('stop');
  print settings_table($page_settings,\@feature_file);
  print p(),upload_table($page_settings,\@feature_file);
  print p(),external_table($page_settings,\@feature_file);
  print end_form();

  # clean us up
  foreach (@feature_file) {
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
  my %settings = cookie("gbrowse_$source");

  my $ok = 1;
  my @labels = $CONFIG->labels;
  if (%settings) {  # if cookie is there, then validate it
    $ok &&= defined $settings{width} && $settings{width} > 100 && $settings{width} < 5000;
    warn "ok 1 = $ok" if DEBUG;

    my %ok_sources = map {$_=>1} $CONFIG->sources;
    $ok &&= $ok_sources{$settings{source}};
    warn "ok 2 = $ok" if DEBUG;

    my @labels   = split $;,$settings{labels} if defined $settings{labels};
    $settings{labels} = \@labels if @labels && $ok;

    warn "ok 3 = $ok" if DEBUG;

    my @external = grep {m!^(\w+)://!} split $;,$settings{eurl};
    $settings{eurl} = \@external;

    warn "ok 4 = $ok" if DEBUG;
    $ok &&= $settings{id} =~ /^[a-z0-9]+$/;

    # track order definitions
    my %seen;
    my @track_order     = split $;,$settings{track} if defined $settings{track};
    foreach (@track_order) {
      $ok &&= /^\d+$/;
      $seen{$_}++;
    }
    $ok &&= keys %seen == @track_order;
    $settings{track} =  \@track_order     if $ok && @track_order;
    warn "ok 5 = $ok" if DEBUG;

    # label options
    my @track_options       = split $;,$settings{options} if defined $settings{options};

    $ok &&= @track_options >= $CONFIG->labels;

    for (my $i=0; $i < @track_options; $i++) {
      warn "track_options = $track_options[$i]" if DEBUG;
      $ok &&= ($track_options[$i]=~ /^[\d-]+$/ && $track_options[$i] >= -1 && $track_options[$i] <= 2);
    }
    $settings{options} = \@track_options   if $ok && @track_options;
    warn "ok 6 = $ok" if DEBUG;
  }

  if (!$ok || !%settings) {
    %settings = ();
    default_settings(\%settings);
  }
  \%settings;
}

sub default_settings {
  my $settings = shift;
  @$settings{'name','ref','start','stop'} = ('','','','');
  $settings->{width}   = $CONFIG->setting('default width');
  $settings->{source}  = $CONFIG->source;
  $settings->{eurl}    = [];
  $settings->{id}      = md5_hex(rand);  # new identity
  set_default_tracks($settings);
}

sub set_default_tracks {
  my $settings = shift;
  my @labels = labels($settings);
  $settings->{track}   = [0 .. @labels-1];
  $settings->{labels}  = [(0) x (scalar @labels)];
  $settings->{options} = [(0) x (scalar @labels)];
  foreach ($CONFIG->default_label_indexes) {
    $settings->{labels}[$_] = 1;
  }
}

sub settings2cookie {
  my $settings = shift;
  my %settings = %$settings;
  local $^W = 0;
  for my $key (keys %settings) {
    if (ref($settings{$key}) eq 'ARRAY') {
      $settings{$key} = join $;,@{$settings{$key}};
    }
  }
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

sub adjust_settings {
  my $settings = shift;
  if (my @selected = map {split '-'} param('label')) {
    $settings->{labels} = [];
    $settings->{labels}[$_] = 1 foreach @selected;
  }
  $settings->{width}  = param('width')   if param('width');

  #  if (param('ref') && (request_method() eq 'GET' || grep {/zoom|nav|overview|span/} param()) ) {
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
  $settings->{eurl}   = [grep {m!^([\w.-]+)://!} param('eurl')] if defined param('eurl');

  if (defined(param('track')) && (param('Submit Changes...') || param('Update'))) {
    my $tracks           = adjust_track_order($settings);
    $settings->{track}   = $tracks;
    my $options          = adjust_track_options($settings);
    $settings->{options} = $options;
  }

}

# prints the zooming and navigation bar
sub navigation_table {
  my $segment = shift;
  my $settings = shift;
  my $buttonsDir    = $CONFIG->setting('buttons');
  my $table = '';

  $table .= table({-border=>0, -width=>$settings->{width}},
		  TR({-class=>'searchbody'},
		     td({-align=>'left', -colspan=>2},
			'Search using a sequence name, gene name, locus, or other landmark.',
			show_examples()
		    )),
		  TR({-class=>'searchbody'},
		     td({-align=>'left', -colspan=>2},
			'To center on a location, click the ruler.  User the Scroll/Zoom buttons to',
			'change magnification and position.',
			'To save this view,',a({-href=>bookmark_link($settings)},'bookmark this link.')
		       )),
		  TR({-class=>'searchtitle', -align=>'left'},
		     td({-class=>'searchtitle',-colspan=>$segment ? 1 : 2}, b('Landmark or Region'),
			textfield(-name=>'name',-size=>28),
			submit(-name=>'Go')),
		     td({-align=>'LEFT'},
			$segment ? ('Scroll/Zoom: ',slidertable($segment,$buttonsDir)) : ''
		       ),
		    ));
}

sub slidertable {
  my ($segment,$buttonsDir) = @_;
  my $span      = $segment->length;
  my $half      = unit_label(int $span/2);
  my $full      = unit_label($span);
  my $fine_zoom = get_zoomincrement();

  my @lines;
  push @lines,hidden(-name=>'start',-value=>$segment->start,-override=>1);
  push @lines,hidden(-name=>'stop',-value=>$segment->end,-override=>1);
  push @lines,hidden(-name=>'ref',-value=>$segment->ref,-override=>1);
  push @lines,hidden(-name=>'prevname',-value=>scalar(param('name')),-override=>1);
  push @lines,
    (image_button(-src=>"$buttonsDir/green_l2.gif",-name=>"left $full",-border=>0,-title=>"left $full"),
     image_button(-src=>"$buttonsDir/green_l1.gif",-name=>"left $half",-border=>0,-title=>"left $half"),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/minus.gif",-name=>"zoom out $fine_zoom",-border=>0,-title=>"zoom out $fine_zoom"),
     '&nbsp;',
     zoomBar($segment,$buttonsDir),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/plus.gif",-name=>"zoom in $fine_zoom",-border=>0,-title=>"zoom in $fine_zoom"),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/green_r1.gif",-name=>"right $half",-border=>0,-title=>"right $half"),
     image_button(-src=>"$buttonsDir/green_r2.gif",-name=>"right $full",-border=>0,-title=>"right $full"),
    );

  #  print end_form;
  my $str	= join('', @lines);
  return $str;
}

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
	      ).'&nbsp;';
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
  push @labels,$settings->{'uploaded_file'} ? "$settings->{uploaded_file} (Uploaded)"
                                            : '(Uploaded Annotations)';
  push @labels,@{$settings->{eurl}}   if $settings->{eurl};
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
  my @dumps    = (['GFF'  ,"$self?dump=GFF;start=$start;stop=$stop;ref=$ref;source=$source"]);
  unshift @dumps,['FastA',"$self?dump=FastA;start=$start;stop=$stop;ref=$ref;source=$source"];

  my $ds        = join(', ', (map{a({-href=>"@$_->[1]"},"@$_->[0]")} @dumps));

  my $self_url = url(-relative=>1,-path_info=>1)."?help=citations";
  my @labels = labels($settings);
  my $native_labels = $CONFIG->labels;
  my %labels = map {$_ => make_citation_link($_,
					     $self_url,
					     \@labels,
					     $additional_features,
					     $native_labels) } (0..@labels-1);

  my @defaults;
  for (my $i = 0; $i < @labels; $i++) {
    push @defaults,$i if $settings->{labels}[$i];
  }

  autoEscape(0);
  my $sTable 	= '';
  $sTable.= table({-border=>0,-width=>$settings->{width}},
		  # row
		  TR(
		     th({-class=>'searchtitle', -colspan=>3, -align=>'left'},'Genome Browser Search Settings:')),

		  TR( td({-class=>'searchbody'},'Dump view as: '),
		      td({-class=>'searchbody',-colspan=>2}, $ds)),

		  TR(	td({-class=>'searchbody', -valign=>'top'}, 'Show features: '),
			td({-class=>'searchbody',-colspan=>2,-width=>'85%'},
			   checkbox_group(-name=>'label',
					  # use the track ordering to adjust the order of the checkboxes
					  # this is an array slice
					  -values   => [@{$settings->{track}}[0..@labels-1]],
					  -labels   => \%labels,
					  -defaults => \@defaults,
					  -cols     => 3,
					  -override => 1,
					 ))),

		  # row
		  $CONFIG->sources > 1 ?
		  (TR({-class=>'searchbody'},
		      td('Data Source:'),
		      td({-colspan=>2},
			 popup_menu(-name   => 'source',
				    -values => [$CONFIG->sources],
				    -labels => { map {$_ => $CONFIG->description($_)} $CONFIG->sources},
				    -default => $CONFIG->source
				   )))
		   ) : '',

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
  return $sTable;
}
autoEscape(1);

sub annotation_help {
  return url(-relative=>1,-path_info=>1) . "?help=annotation";
}

sub upload_table {
  my $settings      = shift;
  my $feature_files = shift;

  my @info =   (a({-href=>url(-relative=>1,-path_info=>1)."?Download+Data=1"},
		  "[".$settings->{'uploaded_file'}."]"),
		get_uploaded_file_info($settings->{labels}[scalar $CONFIG->labels] && $feature_files->[0]))
    if $settings->{'uploaded_file'};

  my $cTable= table({-border=>0,-width=>$settings->{width}},
		  # row
		  TR(
		     th({-class=>'datatitle', -colspan=>3, -align=>'left'},
			'Upload your own annotations:',
			a({-href=>annotation_help(),-target=>'_new'},'[Help]'))
		    ),

		  # row
		  TR({-class=>'databody'},
		     td('Upload a File: '),
		     td({-colspan=>2},
			filefield(-size=>40,-name=>'upload_annotations'),
			submit(-name=>'Upload'),br,@info
		       )
		    ),

		  # row
		  TR({-class=>'databody'},
		     td('Create or Modify:'),
		     td({-colspan=>2},
			submit(-name=>'Edit Data...').'&nbsp;'.
			submit(-name=>'Download Data').'&nbsp;'.
			submit(-name=>'Delete Data'))),
		 );
  $cTable;
}

# URLs for external annotations
sub external_table {
  my $settings      = shift;
  my $feature_files = shift;
  my @rows;
  if (my $urls     = $settings->{eurl}) {
    for (my $i=0;$i<@$urls;$i++) {
      push @rows,th({-align=>'RIGHT'},"URL",$i+1).
	td(textfield(-name=>'eurl',-size=>50,-value=>$urls->[$i],-override=>1),br,
	   a({-href=>$urls->[$i],-target=>'_new'},'[download]'),
	   get_uploaded_file_info($settings->{labels}[$CONFIG->labels+$i+1] && $feature_files->[$i+1])
	  );
    }
  }
  push @rows,th({-align=>'RIGHT'},
		"Enter Remote Annotation URL").
		  td(textfield(-name=>'eurl',-size=>50,-value=>'',-override=>1));

  return table({-border=>0,-width=>$settings->{width}},
	       TR({-class=>'datatitle'},
		  th({-align=>'LEFT',-colspan=>2},
		     'Add Remote Annotations:',a({-href=>annotation_help().'#remote',-target=>'_new'},'[Help]'))),
	       TR({-class=>'databody'},\@rows),
	       TR({-class=>'databody'},
		  th({-align=>'RIGHT',-colspan=>2},
		     submit(-name=>'eurl',-value=>'Update URLs')))
	      ).hidden(-name=>'eurl',-value=>1,-override=>1);  # dummy variable
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
sub get_segment {
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
    @segments = name2segments($name,$db);
  }

  elsif (my $ref = $settings->{ref}) {
    my @argv = (-name  => $ref);
    push @argv,(-start => $settings->{start}) if defined $settings->{start};
    push @argv,(-stop  => $settings->{stop})  if defined $settings->{stop};
    @segments = $db->segment(@argv);
  }

  $_->absolute(1) foreach @segments;

  return unless @segments;
  return @segments if @segments > 1;

  # set CGI name parameter to match segment.
  # this prevents any confusion over (ref,start,stop) and (name) addressing.
  $settings->{ref}   = $segments[0]->ref;
  $settings->{start} = $segments[0]->start;
  $settings->{stop}  = $segments[0]->stop;

  return $segments[0];
}

# this gets called when -- for whatever reason -- we got a truncated segment
sub truncated_segment {
  my $seg   = shift;
  my ($trunc_left,$trunc_right) = @{$seg->truncated} if $seg->truncated;
  my $ref   = $seg->ref;
  my $db    = open_database();
  my $whole = $db->segment($ref);
  return $db->segment(-name=>$ref,-start=>$whole->stop-4,-stop=>$whole->stop) if $trunc_right;
  return $db->segment(-name=>$ref,-start=>1,-stop=>4)                         if $trunc_left;
}

# try to guess the reference segment from the name, given the variety of
# ways that people abuse names.
sub name2segments {
  my $name = shift;
  my $db   = shift || open_database();

  my (@segments,$class,$start,$stop);
  if ($name =~ /([\w._-]+):(-?\d+),(-?\d+)$/ or
      $name =~ /([\w._-]+):(-?[\d,]+)(?:-|\.\.)?(-?[\d,]+)$/) {
    $name = $1;
    $start = $2;
    $stop = $3;
    $start =~ s/,//g; # get rid of commas
    $stop  =~ s/,//g;
  }

  elsif ($name =~ /^(\w+):(.+)$/) {
    $class = $1;
    $name  = $2;
  }

  my @argv = (-name  => $name);
  push @argv,(-class => $class) if defined $class;
  push @argv,(-start => $start) if defined $start;
  push @argv,(-stop  => $stop)  if defined $stop;
  @segments = $db->segment(@argv);

  # Here starts the heuristic part.  Try various abbreviations that
  # people tend to use for chromosomal addressing.
  if (!@segments && $name =~ /^([\dIVXA-F]+)$/) {
    my $id = $1;
    foreach (qw(CHROMOSOME_ Chr chr)) {
      my $n = "${_}${id}";
      my @argv = (-name  => $n);
      push @argv,(-class => $class) if defined $class;
      push @argv,(-start => $start) if defined $start;
      push @argv,(-stop  => $stop)  if defined $stop;
      @segments = defined($start) ? $db->segment(@argv) : $db->segment(@argv) unless @segments;
    }
  }

  # try to remove the chr CHROMOSOME_I
  if (!@segments && $name =~ /^(chromosome_?|chr)/i) {
    (my $chr = $name) =~ s/^(chromosome_?|chr)//i;
    @segments = $db->segment($chr);
  }

  # try any "automatic" classes that have been defined in the config file
  if (!@segments && !$class && 
      (my @automatic = split /\s+/,$CONFIG->setting('automatic classes') || '')) {
    @argv = (-name=>$name);
    push @argv,(-start => $start) if defined $start;
    push @argv,(-stop  => $stop)  if defined $stop;
    foreach $class (@automatic) {
      @segments = $db->segment(-class=>$class,@argv);
      last if @segments;
    }
  }

  # This tricky bit is called when we retrieve multiple segments or when
  # there is an unusually large feature to display.  In this case, we attempt
  # to split the feature into its components and offer the user different
  # portions to look at, invoking merge() to select the regions.
  my $max_length = 0;
  foreach (@segments) {
    $max_length = $_->length if $_->length > $max_length;
  }
  if (@segments > 1 || $max_length > $MAX_SEGMENT) {
    @segments     = $db->fetch_feature_by_name(-class => $segments[0]->class,
					       -name  => $segments[0]->ref,
					       -automerge=>0);
    @segments     = $CONFIG->merge(\@segments,(get_ranges())[-1])
      if @segments > 1 && @segments < TOO_MANY_SEGMENTS;
  }
  @segments;
}

################ perform keyword search ###############
sub do_keyword_search {
  my $searchterm = shift;
  my $db = open_database();
  my @results = $db->search_notes($searchterm,MAX_KEYWORD_RESULTS);
  return @results;
}

################ format keyword search ###################
sub format_keyword_search {
  my ($name,$results) = @_;
  my $db = open_database();

  my $regexp = join '|',($name =~ /(\w+)/g);

  print start_table();
  print TR({-class=>'datatitle'},th({-colspan=>4},
	      "No landmark named $name is found, but the following landmarks may be related."));
  print TR({-class=>'datatitle'},th(['Name','Description','Location','Relevance']));
  my $url = url(-relative=>1,-path_info=>1);
  my %position = map { overload::StrVal($_->[0]) => $db->segment($_->[0]) } @$results;

  for my $r (sort {by_score_and_position(\%position)} @$results) {
    my $name  = escape($r->[0]->name);
    my $class    = escape($r->[0]->class);
    my $description = escapeHTML($r->[1]);
    $description =~ s/($regexp)/<b class="keyword">$1<\/b>/ig;

    my $href     = "$url?name=$class:$name";
    my $seg      = $position{overload::StrVal($r->[0])};
    my $position = format_segment($seg);
    print TR({-class=>'databody',-valign=>'TOP'},
	     th({-align=>'RIGHT'},a({-href=>$href},$r->[0])),
	     td($description),
	     td(a({-href=>$href},$position)),
	     td($r->[2]));
  }
  print end_table;
}

sub by_score_and_position {
  my $position = shift;
  my $result = $b->[2] <=> $a->[2];
  return $result unless $result == 0;
  my $apos = $position->{overload::StrVal($a->[0])};
  my $bpos =$position->{overload::StrVal($b->[0])};
  return $apos->abs_ref cmp $bpos->abs_ref
    ||
      $apos->abs_start<=>$bpos->abs_start
	||
	  $apos->abs_stop<=>$bpos->abs_stop;
}

sub format_segment {
  my $s = shift or return 'n/a';
  my $ref = $s->abs_ref;
  my $start = commas($s->abs_start);
  my $stop  = commas($s->abs_stop);
  return "<b>$ref</b>:$start..$stop";
}

sub open_database {
  my $source  = $CONFIG->source;
  return $DB{$source} if $DB{$source};
  my @argv = $CONFIG->dbgff_settings;
  $DB{$source} = eval {Bio::DB::GFF->new(@argv)} or warn $@;
  return $DB{$source};
}

sub image_and_map {
  my ($segment,$additional_features,$settings) = @_;
  return unless $segment;

  $CONFIG->width($settings->{width});

  # get the current track order
  my $labels  = $settings->{labels},
  my $tracks  = $settings->{track};
  my $options = $settings->{options};

  my($image,$map) = $CONFIG->image_and_map(segment       => $segment,
					   feature_files => $additional_features,
					   show          => $labels,
					   order         => $tracks,
					   options       => $options,
                                          );
  if (DEBUGGING_RECTANGLES) { debugging_rectangles($image,$map) }

  my ($width,$height) = $image->getBounds;
  my @mtimes = map {ref($_) && $_->mtime} @$additional_features;

  local $^W = 0;
  my $signature = md5_hex($segment,
			  (map {$_||0} @{$settings->{labels}}),
			  $settings->{width},
			  $CONFIG->source || '',
			  $settings->{id} || '',
			  @mtimes,
			  ref($settings->{track}) && @{$settings->{track}},
			  ref($settings->{options}) && @{$settings->{options}}
			 );
  my $url     = generate_image($image,$signature);
  my $img     = img({-src=>$url,-usemap=>'#hmap',-width => $width,-height => $height,-border=>0});
  my $img_map = make_map($map);
  return join "\n",$img,$img_map;
}

sub overview {
  my ($segment,$settings) = @_;
  return unless $segment;
  $CONFIG->width($settings->{width}*OVERVIEW_RATIO);

  my ($image,$length) = $CONFIG->overview($segment) or return;
  my ($width,$height) = $image->getBounds;
  my $signature = md5_hex($segment,$width);
  my $url = generate_image($image,$signature);
  return image_button(-name=>'overview',
		      -src=>$url,
		      -width=>$width,
		      -height=>$height,
		      -border=>0,
		      -align=>'MIDDLE')
    .hidden(-name=>'seg_length',-value=>$length,-override=>1);
}

sub generate_image {
  my ($image,$signature) = @_;
  my $extension = $image->can('png') ? 'png' : 'gif';
  my ($uri,$path) = tmpdir($CONFIG->source.'/img');
  my $url         = sprintf("%s/%s.%s",$uri,$signature,$extension);
  my $imagefile   = sprintf("%s/%s.%s",$path,$signature,$extension);
  open (F,">$imagefile") || die("Can't open image file $imagefile for writing: $!\n");
  print F $image->can('png') ? $image->png : $image->gif;
  close F;
  return $url;
}

sub tmpdir {
  my $path = shift || '';
  my $tmpuri = $CONFIG->setting('tmpimages') or die "no tmpimages option defined, can't generate a picture";
  $tmpuri .= "/$path" if $path;
  my $tmpdir;
  if ($ENV{MOD_PERL}) {
    my $r          = Apache->request;
    my $subr       = $r->lookup_uri($tmpuri);
    $tmpdir        = $subr->filename;
    my $path_info  = $subr->path_info;
    $tmpdir       .= $path_info if $path_info;
  } else {
    $tmpdir = "$ENV{DOCUMENT_ROOT}/$tmpuri";
  }
  mkpath($tmpdir,0,0777) unless -d $tmpdir;
  return ($tmpuri,$tmpdir);
}

sub get_ranges {
  my @ranges	= split /\s+/,$CONFIG->setting('zoom levels') || DEFAULT_RANGES;
  @ranges;
}

sub get_zoomincrement {
  my $zoom      = $CONFIG->setting('fine zoom')  || DEFAULT_FINE_ZOOM;
  $zoom;
}

sub make_map {
  my $boxes = shift;
  my $map = qq(<map name="hmap">\n);

  # use the scale as a centering mechanism
  my $ruler = shift @$boxes;
  $map .= make_centering_map($ruler);

  foreach (@$boxes){
    next unless $_->[0]->can('primary_tag');
    my $href  = make_href($_->[0]) or next;
    my $alt   = make_alt($_->[0]);
    $map .= qq(<AREA SHAPE="RECT" COORDS="$_->[1],$_->[2],$_->[3],$_->[4]" 
	       HREF="$href" ALT="$alt" TITLE="$alt">\n);
  }
  $map .= "</map>\n";
  $map;
}

sub make_centering_map {
  my $ruler = shift;
  return if $ruler->[3]-$ruler->[1] == 0;

  my $offset = $ruler->[0]->start;
  my $scale  = $ruler->[0]->length/($ruler->[3]-$ruler->[1]);

  # divide into ten intervals
  my $portion = ($ruler->[3]-$ruler->[1])/10;
  Delete_all();
  param(ref => scalar($ruler->[0]->ref));

  my @lines;
  for my $i (0..19) {
    my $x1 = $portion * $i;
    my $x2 = $portion * ($i+1);
    # put the middle of the sequence range into the middle of the picture
    my $middle = $offset + $scale * ($x1+$x2)/2;
    my $start  = int($middle - $ruler->[0]->length/2);
    my $stop   = int($start + $ruler->[0]->length - 1);
    param(start => int($start));
    param(stop  => int($stop));
    param(nav4  => 1);
    param(source=> $CONFIG->source);
    my $url = url(-relative=>1,-query=>1,-path_info=>1);
    push @lines,
      qq(<AREA SHAPE="RECT" COORDS="$x1,$ruler->[2],$x2,$ruler->[4]"
	 HREF="$url" ALT="center" TITLE="center">\n);
  }
  return join '',@lines;
}

sub make_href {
  my $feature = shift;
  if ($feature->can('make_link')) {
    return $feature->make_link;
  } else {
    return $CONFIG->make_link($feature);
  }
}

sub make_alt {
  my $feature = shift;
  my $label = $feature->class .":".$feature->info;
  if ($feature->method =~ /^(similarity|alignment)$/) {
    $label .= " ".commas($feature->target->start)."..".commas($feature->target->end);
  } else {
    $label .= " ".commas($feature->start)."..".commas($feature->stop);
  }
  return $label;
}

sub dump_fasta {
  my $segment = shift;
  my $dna = $segment->dna;
  $dna =~ s/(.{1,60})/$1\n/g;
  print ">$segment\n";
  print $dna;
}

sub dump_gff {
  my $segment = shift;
  my $page_settings = shift;

  my $selected_labels = $page_settings->{labels} or return;
  my @labels   = labels($page_settings);
  my @selected = grep {$selected_labels->[$_]} 0..@labels;
  @selected = @labels[@selected];

  my $date = localtime;
  print "##gff-version 2\n";
  print "##date $date\n";
  print "##sequence-region ",join(' ',$segment->ref,$segment->start,$segment->stop),"\n";

  my $conf = $CONFIG->config;
  my @feature_types = map {$conf->label2type($_)} @selected;

  warn "dumping @feature_types" if DEBUG;

  my $iterator = $segment->features(-types=>\@feature_types,-iterator=>1) or return;
  while (my $f = $iterator->next_feature) {
    print $f->gff_string,"\n";
    for my $s ($f->sub_SeqFeature) {
      print $s->gff_string,"\n";
    }
  }
}

# I know there must be a more elegant way to insert commas into a long number...
sub commas {
  my $i = shift;
  $i = reverse $i;
  $i =~ s/(\d{3})/$1,/g;
  chop $i if $i=~/,$/;
  $i = reverse $i;
  $i;
}

sub multiple_choices {
  my $segments = shift;
  my $settings = shift;

  my $message = "The landmark named ".$settings->{name}." exists in multiple locations";
  $message   .= @$segments > TOO_MANY_SEGMENTS ?  ", but there are too many to choose from (".@$segments.")."
                                                 ." Please try a different landmark." 
                                               : ". Please choose one.";

  print start_table({-class=>'datatitle'});
  print TR(th($message));
  if (@$segments <= TOO_MANY_SEGMENTS) {
    print start_TR({-class=>'databody'}),start_td();

    # aggregate segments by reference and then split on gaps of > 1 M
    my %segs;
    push @{$segs{$_->ref}},$_ foreach @$segments;

    my $url = url(-relative=>1,-path_info=>1);
    my $source = $CONFIG->source;

    print start_dl;
    for my $ref (sort keys %segs) {
      my @spans  = sort {$a->start <=> $b->start} @{$segs{$ref}};
      print dt(b($ref)),"\n";
      foreach (@spans) {
	my ($start,$stop) = ($_->start,$_->stop);
	my $bp = $stop - $start;
	my $s = commas($start);
	my $e = commas($stop);
	print dd(a({-href=>"$url?source=$source;ref=$ref;start=$start;stop=$stop"},"$s..$e ($bp bp)")),"\n";
      }

    }
    print end_dl,end_td,end_TR;
  }
  print end_table;
}


sub show_examples {
  my $examples = $CONFIG->setting('examples') or return;;
  my @examples = split /\s+/,$examples;
  return unless @examples;
  my $url    = url(-relative=>1,-path_info=>1);
  my $source = $CONFIG->source;
  my @urls = map { a({-href=>"$url?source=$source;name=".escape($_)},$_) } @examples;
  return b('Examples: ').join ', ',@urls;
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
  $settings->{'uploaded_file'} = "$fh";
  my $fh_out = open_uploaded_file($settings,'>') or return;
  while (<$fh>) {
    print $fh_out $_;
  }
  close $fh_out;
}

sub handle_edit {
  my ($settings,$data) = @_;
  my @lines = unexpand(split /\r?\n|\r\n?/,$data);
  $data = join "\n",@lines;
  $data .= "\n";
  my $fh = open_uploaded_file($settings,'>');
  print $fh $data;
  close $fh;
  $settings->{'uploaded_file'} ||= 'auto';
}

sub handle_quickie {
  my ($settings,$data) = @_;
  return unless $data;
  # format of quickie data is reference+type+name+start-stop,start-stop,start-stop
  my ($reference,$type,$name,$position) = shellwords($data);
  my $out = open_uploaded_file($settings,">>") or return;
  print $out "\nreference=$reference\n";
  $type .= " " . localtime;
  print $out join ("\t",qq("$type"),$name,$position),"\n";
  close $out;
  $settings->{'uploaded_file'} = 'auto';
}

sub name_uploaded_file {
  my $settings = shift;
  my $id = $settings->{id} or return;
  my (undef,$tmpdir) = tmpdir($CONFIG->source."/uploaded_file/$id");
  $settings->{'uploaded_file'} ||= 'auto';
  return "$tmpdir/$settings->{'uploaded_file'}";
}

sub open_uploaded_file {
  my $settings = shift;
  my $mode     = shift || '<';
  my $file = name_uploaded_file($settings);
  unless ($file) {
    error("Can't find the file named $settings->{'uploaded_file'}.  Perhaps it has been purged?");
    return;
  }

  my $result = open (F,"${mode}${file}");

  unless ($result) {
    warn "Can't open the file named $settings->{'uploaded_file'}.  Perhaps it has been purged? (error: $!)";
    return;
  }

  return \*F;
}

sub load_external_sources {
  my ($segment,$page_settings) = @_;
  my @feature_file = load_uploaded_file($segment,$page_settings) || (undef);
  push @feature_file,load_remote_sources($segment,$page_settings);
  @feature_file;
}

sub load_uploaded_file{
  my ($segment,$settings) = @_;
  $settings->{'uploaded_file'} or return;
  $settings->{labels}[$CONFIG->labels] or return $settings->{'uploaded_file'};

  my $width = $settings->{width} or return;
  my $fh = open_uploaded_file($settings,"<") or return;

  my $rel2abs = coordinate_mapper($segment) if $segment;

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
  $feature_file->name($settings->{uploaded_file});
  return $feature_file;
}

sub load_remote_sources {
  my ($segment,$settings) = @_;
  return unless $settings->{eurl};
  my $rel2abs = coordinate_mapper($segment) if $segment;
  my @files;
  for (my $i = 0; $i < @{$settings->{eurl}}; $i++) {
    my $data;
    my $label_index = $CONFIG->labels+$i+1;
    if ($settings->{labels}[$label_index]) { # show it
      $data = get_remote_feature_data($settings->{eurl}[$i],$rel2abs);
      $data->name($settings->{eurl}[$i]);
    } else {
      $data = $settings->{eurl}[$i];
    }
    push @files,$data;
  }
  return @files;
}

sub get_remote_feature_data {
  my $url = shift;
  my $rel2abs = shift;

  unless ($UA) {
    unless (eval "require LWP") {
      error('This browser is not configured to fetch external URLs');
      return;
    }
    $UA = LWP::UserAgent->new(agent   => 'GenericGenomeBrowser/1.0',
			      timeout => URL_FETCH_TIMEOUT,
			      max_size => URL_FETCH_MAX_SIZE,
			     );
  }
  my $id = md5_hex($url);  # turn into a filename
  my (undef,$tmpdir) = tmpdir($CONFIG->source.'/external');
  my $response = $UA->mirror($url,"$tmpdir/$id");
  if ($response->is_error) {
    error("Could not fetch $url: ",$response->message);
    return;
  }
  open (F,"<$tmpdir/$id") or return;
  my $feature_file = Bio::Graphics::FeatureFile->new(-file           => \*F,
						     -map_coords     => $rel2abs,
						     -smart_features =>1);
  return $feature_file;
}

sub print_uploaded_file_features {
  my $settings = shift;
  if (my $fh = open_uploaded_file($settings)) {
    while (<$fh>) {
      print;
    }
  }
}

sub get_uploaded_file_info {
  my $feature_file = shift or return i("Display off");
  my $modified = localtime($feature_file->mtime);
  my @refs      = $feature_file->refs;
  my $url      = url(-relative=>1,-path_info=>1);
  my $landmarks = @refs < 20 ? b(map {a({-href=>"$url?name=$_"},$_)} sort @refs)
                             : b(@refs." landmarks.  Too many to list.");
  return i("Last modified $modified.  Annotated landmarks:"),$landmarks;
}

sub clear_uploaded_file {
  my $settings = shift;
  my $file = name_uploaded_file($settings) or return;
  unlink $file;
  delete $settings->{'uploaded_file'};
}

sub edit_uploaded_file {
  my $settings = shift;
  print start_form();
  my $data;
  if ($settings->{'uploaded_file'} && 
      (my $fh = open_uploaded_file($settings))) {
    $data = join '',expand(<$fh>);
  }
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
		    a({-href=>url(-relative=>1,-path_info=>1)."?help=annotation#format",-target=>'_new'},
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
  print end_form();
}

sub coordinate_mapper {
  my $current_segment = shift;
  my $db              = $current_segment->factory;

  my ($ref,$start,$stop) = ($current_segment->ref,$current_segment->start,$current_segment->stop);
  my %segments;

  my $closure = sub {
    my ($refname,@ranges) = @_;

    unless ($segments{$refname}) {
      my @segments = grep {
	$_->abs_ref eq $ref && $_->abs_start <= $stop && $_->abs_stop >= $start
      } name2segments($refname,$db);
      return unless @segments;
      $segments{$refname} = $segments[0];
    }
    my $mapper   = $segments{$refname};
    my $absref   = $mapper->abs_ref;
    my @abs_segs = map {[$mapper->rel2abs($_->[0],$_->[1])]} @ranges;
    return unless grep { $_->[0] <= $stop && $_->[1] >= $start } @abs_segs;
    return ($absref,@abs_segs);
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
  my @keys = $settings->{name} ? qw(name source width eurl)
                               : qw(start stop ref source width eurl);
  foreach (@keys) {
    $q->param(-name=>$_,-value=>$settings->{$_});
  }
  # handle selected features slightly differently
  my @selected;
  my @labels = labels($settings);
  for (my $i=0; $i<@labels; $i++) {
    push @selected,$i if $settings->{labels}[$i];
  }
  $q->param(-name=>'label',-value=>join('-',@selected));
  return $q->url(-relative=>1,-path_info=>1,-query=>1);
}

# fix up tracks to adjust for an increase or decrease in their number
sub adjust_tracks {
  my $settings = shift;

  # sanity check as a defense against invalid cookies
  foreach (qw(track options labels)) {
    unless (ref $settings->{$_} eq 'ARRAY') {
       set_default_tracks($settings);
       return;
    }
  }

  my $old_count     = @{$settings->{track}};
  my $new_count     = labels($settings);

  if ($old_count < $new_count) {  # grew
    for ($old_count .. $new_count-1) {
      $settings->{track}[$_]     = $_;
      $settings->{options}[$_]   = 0;
      $settings->{labels}[$_]    = 1;
    }
  }

  elsif ($old_count > $new_count) { # shrank
    $settings->{labels} = [grep {defined($_) && $_ < $new_count} @{$settings->{labels}}];
    $settings->{track}  = [grep {defined($_) && $_ < $new_count} @{$settings->{track}}];
    splice(@{$settings->{options}},$old_count-$new_count,$new_count);
  }

}

sub adjust_track_order {
  my $settings = shift;

  my @labels = labels($settings);

  # tracks[track] => feature
  my @tracks;
  if (param('track')) {
    @tracks = param('track');
  } elsif (my $t = $settings->{track}) {
    @tracks = @$t;
  } else {
    @tracks   = (0..@labels-1);
  }


  # features[feature] => track
  my @features;
  for (my $track=0; $track < @tracks; $track++ ) {
    $features[$tracks[$track]] = $track;
  }

  my %seen_it_already;
  foreach (grep {/^track\./} param()) {
    my ($track) = /(\d+)/;
    my $feature   = param($_);
    next if $feature < 0;
    next if $seen_it_already{$feature}++;

    # remove feature from wherever it is now
    my $current_position = $features[$feature];
    splice(@tracks,$current_position,1);

    # insert feature into desired position
    splice(@tracks,$track,0,$feature);

    # and fix up the @features array
    for (my $track=0; $track < @tracks; $track++ ) {
      $features[$tracks[$track]] = $track;
    }
  }

  return \@tracks;
}

sub adjust_track_options {
  my $settings = shift;
  my @option = @{$settings->{options}};
  foreach (grep {/^option\./} param()) {
    my ($feature) = /(\d+)/;
    my $option    = param($_);
    $option[$feature] = $option;
  }
  \@option;
}

sub set_track_options {
  my $settings = shift;

  my $tracks = adjust_track_order($settings);
  my @labels = labels($settings);

  my @t      = sort { $labels[$a] cmp $labels[$b] } (0..@labels-1);
  my %labels = map { $_ => $labels[$_] } @t;
  unshift @t,-1;
  $labels{-1} = '';

  my @rows;
  for (my $track = 0; $track < @labels; $track++) {
    my $feature = $tracks->[$track];
    my $label   = $labels[$feature];
    push @rows,
      th({-align=>'LEFT',-class=>'searchtitle'},"Track",$track+1).
	th({-align=>'LEFT',-class=>'searchbody'},$label).
	  td({-align=>'CENTER',-class=>'searchbody'},
	     checkbox(-name  => 'label',
		      -value => $feature,
		      -override => 1,
		      -checked  => $settings->{labels}[$feature],
		      -label => '')
	    ).
          td({-align=>'CENTER',-class=>'searchbody'},
	     radio_group(-name     => "option.$feature",
			 -values   => [0,1,2],
			 -override => 1,
			 -default  => $settings->{options}[$feature],
			 -labels   => {0=>'Auto',1=>'Bump',2=>'Bump & Label'}
			)
	    ).
	  td({-align=>'CENTER',-class=>'searchbody'},
	     popup_menu(-name    => "track.$track",
			-values  => \@t,
			-labels  => \%labels,
			-override => 1,
			-default => -1));
  }

  print h1({-align=>'CENTER'},'Settings for ',$CONFIG->setting('description'));
  print start_form(-name=>'settings');
  print table({-width=>'100%',-border=>0},
	      TR({-class=>'searchtitle'},
		 th({-colspan=>5},'Track Options')),
	      TR({-class=>'searchbody'},
		 td({-colspan=>5},
		    'The',i('Show'),'checkbox turns the track on and off.',
		    'The',i('Bump'),'option forces the track to be expanded so that',
		    'annotations bump each other rather than overlap, and',i('Bump and Label'),
		    'forces annotations to be labeled.  If',i('Auto'),'is selected, the bump and label',
		    'options will be set automatically if space permits.',
		    'To change the track order use the',i('Change Track Order'),'popup menu',
		    'to assign an annotation to a track.'
		   ),
		),
	      TR({-class=>'searchtitle'},
		 th('Track'),
		 th('Annotation Type'),
		 th('Show'),
		 th('Format'),
		 th('Change Track Order')
		),
	      TR(\@rows),
	      TR({-class=>'searchtitle'},
		 td({-colspan=>3,-align=>'CENTER'},
		    reset('Undo Changes').'&nbsp;'.
		    submit('Revert to Defaults').'&nbsp;'.
		    submit('Cancel').'&nbsp;'
		   ),
		 td({-align=>'CENTER',-colspan=>2},
		    submit('Update').'&nbsp;'.
		    b(submit('Submit Changes...'))
		   )),
	      hidden(-name=>'track',-value=>$tracks,-override=>1),
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
  my @external_features = load_external_sources(undef,$settings);
  my (@citations);

  print h2('Track Descriptions & Citations');

  # build native features
  print h3('Tracks Built into this Server');
  for my $feature (@features) {
    push @citations,make_citation($CONFIG,$feature);
  }
  print blockquote(dl(@citations));

  # build external features
  if (@external_features) {
    print hr,h3('External Annotation Tracks');
    @citations = ();
    for my $file (@external_features) {
      next unless defined $file;
      my $name   = ref($file) ? $file->name : $file;
      my $is_url = $name =~ m!^(http|ftp)://!;
      my $link   = $is_url  ? $name  : url(-relative=>1,-path_info=>1)."?Download+Data=1";
      my $anchor = $is_url  ? $name  : "$name (Uploaded)";
      $anchor =~ tr/ /-/;

      unless (ref $file) {
	print h3(a{-name=>$anchor,-href=>$link},$name);
	print blockquote('Please activate this track in order to view its information');
	next;
      }
      print h4(a{-name=>$anchor,-href=>$link},$name);
      for my $feature ($file->types) {
	push @citations,make_citation($file,$feature);
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
  open(F,$helpfile) or return;
  print while <F>;
  close F;
}

# Create a link to a citation.  It will point to an external URL if the
# citation looks like a URL (starts with http: or ftp:).  It will be
# self-referential otherwise.

# The persistent problem here is that the regular features are cited on a
# feature-by-feature basis, while the uploaded/external ones are cited as
# a group.  This makes for ugly logic branches.
sub make_citation_link {
  my ($label_index,$self_url,$labels,$extra_labels,$label_count)   = @_;
  my $label = $labels->[$label_index];
  my $is_external = $label_index < $label_count;

  my $config = $is_external ? $CONFIG
                            : $extra_labels->[$label_index-$label_count];

  if ($config && ref($config)) {
    my $citation = $config->citation($is_external ? $label : ());
    (my $anchor  = $label) =~ tr/ /-/;
    my $link = $citation && $citation =~ m!^(http|ftp)://! ? $citation
                                                           : $self_url.'#'.escapeHTML($anchor);
    return a({-href=>$link,-target=>'_new'},$labels->[$label_index]);
  }

  else {
    return $labels->[$label_index];
  }
}

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;
