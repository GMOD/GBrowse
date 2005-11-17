#!perl
use Config;
use File::Basename qw(&basename &dirname);
use File::Spec;
use FindBin '$Bin';
use Cwd;

my %OPTIONS;
if (open F,"$Bin/../GGB.def") {
  while (<F>) {
    next if /^\#/;
    chomp;
    $OPTIONS{$1} = $2 if /^(\w+)\s*=\s*(.+)/;
  }
  close F;
}

if($OPTIONS{PREFIXSTRIP}){
  $OPTIONS{CONF} =~ s/^$OPTIONS{PREFIX}//;
  $OPTIONS{LIB}  =~ s/^$OPTIONS{PREFIX}//;
}

$OPTIONS{CONF} ||= '/usr/local/apache/conf';

my $dir = dirname($0);
$file   = shift || File::Spec->catfile($dir,basename($0, '.PL','.PLS'));

open OUT,">$file" or die "Can't create $file: $!";

print "Extracting $file (with variable substitutions)\n";

my $startperl = $Config{startperl} ne '#!perl' 
  ? $Config{startperl}
  : "#!$Config{perlpath}";

print OUT <<"!GROK!THIS!";
$startperl -w

###################################################################
# Non-modperl users should change this variable if needed to point
# to the directory in which the configuration files are stored.
#
\$CONF_DIR  = '$OPTIONS{CONF}/gbrowse.conf';
#
###################################################################
\$VERSION   = $OPTIONS{VERSION};
!GROK!THIS!

print OUT "use lib '$OPTIONS{LIB}';\n" if defined $OPTIONS{LIB};

# In the following, perl variables are not expanded during extraction.

print OUT <<'!NO!SUBS!';
# $Id: gbrowse.PLS,v 1.132 2005-11-17 21:04:41 mwz444 Exp $

use strict;
use Bio::Graphics;
use Bio::Graphics::GBrowse_run;
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Constants;
use Bio::Graphics::Browser::Util;
use Data::Dumper;
use Digest::MD5 'md5_hex';
use File::Path 'mkpath';
use Text::Tabs;
use Text::Shellwords;
use File::Basename 'basename','dirname';
use File::Spec;
use Carp qw(:DEFAULT croak);
#use CGI qw(:standard unescape escape escapeHTML center *table *dl *TR *td);
use CGI qw(:standard unescape escape escapeHTML center *table *dl *TR *td);
use CGI qw(cookie escapeHTML param path_info request_method url referer);
use Template;
use URI::Escape;
use vars qw($MAX_SEGMENT $DEFAULT_SEGMENT
	    $HEADER $HTML $UA $VERSION $CONF_DIR
	    $PLUGINS $PRESETS
	    %OBJECT_TYPES %PLUGIN_NAME2LABEL
	    $BROWSER @COLLAPSIBLE_DIV_PARAMS
);

local $CGI::USE_PARAM_SEMICOLONS = 1;

use constant EXPIRES => CGI::Util::expires('+7d');

# IMPORTANT DATA STRUCTURES

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

$ENV{PATH} = '/bin:/usr/bin:/usr/local/bin';

## CONFIGURATION & INITIALIZATION ################################
# preliminaries -- read and/or refresh the configuration directory
# open_config() is exported from Util.pm

#############################
# THIS SINGLETON OBJECT WILL EVENTUALLY HAVE ALL THE FUNCTIONALITY
# OF THE REST OF THIS CGI SCRIPT
$CONF_DIR  = conf_dir($CONF_DIR);  # conf_dir() is exported from Util.pm
$BROWSER = Bio::Graphics::GBrowse_run->new(config     => open_config($CONF_DIR),
                                           config_dir => $CONF_DIR
                                          );
my($source) = get_source();
$BROWSER->config->source($source);
#############################

@COLLAPSIBLE_DIV_PARAMS = qw/
    detail_panel_vis  instruction_panel_vis
    options_panel_vis overview_panel_vis
    search_panel_vis  tracks_panel_vis
    upload_panel_vis
    /;

main(); #at the bottom
exit 0;

#################################################################################
#--------------------------------- lots of subroutines --------------------------
#################################################################################

sub main_display($$) {
  my ($segments,$features) = @_;
  my ($segment);
  my $options = $BROWSER->options();

  # first of all, if there are no segments, then try a keyword search and store the results
  if (@$segments == 0 && (my $n = $options->name())) {
    error($BROWSER->translate('NOT_FOUND',escapeHTML($n)));
  }

  # if there's a single segment, then print a message and store the segment into a scalar
  elsif (@$segments == 1) {
    $segment = $segments->[0];
  }

  # force flipping
  if ($segment && $segment->stop < $segment->start) {
      $segment = $segment->factory->segment(-name  => $segment->seq_id,
					    -start => $segment->stop,
					    -stop  => $segment->start);
      $options->flip(1);
  }



  # if more than one segment, then list them all
  if (@$segments <= 1 && $segment) {
    # if a plugin passes us back a Feature, rather than a Segment, turn it into a segment
    # (this shouldn't happen - hah!)
    $segment = open_database()->segment($segment->seq_id,
				        $segment->start,$segment->end)
      unless $segment->can('features');
  }

################################

  my $feature_files = load_external_sources($segments);

  my $oligo = $PLUGINS->{'OligoFinder'} ? ', oligonucleotide (15 bp minimum)' : '';

  my %seen; #used to keep track of available ranges for display

  my %div_visibility = map {$_ => scalar(param($_))} @COLLAPSIBLE_DIV_PARAMS;

  my $param =
  {
    browser        => $BROWSER,
    plugins        => $PLUGINS,

    htmlfrag1      => html_frag('html1',$segment) || '',
    htmlfrag2      => html_frag('html2',$segment) || '',
    htmlfrag3      => html_frag('html3',$segment) || '',
    htmlfrag4      => html_frag('html4',$segment) || '',
    htmlfrag5      => html_frag('html5',$segment) || '',
    htmlfrag6      => html_frag('html6',$segment) || '',

    examples                   => [shellwords($BROWSER->config->setting('examples'))],

    citation_link              => \&make_citation_link,

    link_bookmark              => bookmark_link(),
    link_image                 => image_link(),
    link_svg                   => svg_link(),
    link_help                  => "?display_help=general",

    rand       => substr(md5_hex(rand),0,5),

    action     => $BROWSER->config->source() ? url()."/".$BROWSER->config->source : url(),

    segment    => $segment,
    prevname   => scalar(param('name')),
    finezoom   => get_zoomincrement(),
    selected_tracks => { map { $_ => $options->get_feature($_)->{'visible'} }
          keys %{ $options->features() || {} } },

#FIXME    multiple_segments => multiple_choices($features),
    detailpanel           => detail_panel_with_timeout($segment,$feature_files),
    toggle_cookie_name    => 'GBROWSE_TOGGLE',
    toggle_cookie_expires => EXPIRES,
    %div_visibility,
  };

  if($segment){
    $param->{ranges}     = [ grep {!$seen{$_}++} sort {$b<=>$a} $segment->length,get_ranges() ];
    $param->{half}       = int($segment->length/2);
    $param->{full}       = $segment->length;
  }

  my $show = $BROWSER->translate('Show');
  my %range_labels = map {$_=>$show.' '.unit_label($_)} @{ $param->{ranges} };
  $param->{range_labels} = \%range_labels;

  my $table = undef;
  $BROWSER->template->process('main.tt2',$param,\$table) or warn $BROWSER->template->error();
  print $table;

################################

  # clean us up
  foreach (values %$feature_files) {
    $_ && ref($_) && eval{$_->finished};
  }
}

sub detail_panel_with_timeout {
    my @args    = @_;
    my $timeout = $BROWSER->config->setting('request timeout') || GLOBAL_TIMEOUT;
    local $SIG{ALRM} = sub { die "timeout\n" };
    my $data = eval {
      alarm($timeout);
      detail_panel(@args);
    };
    alarm(0);
    if ($@ =~ /^timeout/) {
return "A";
#FIXME return p(b(font({-size=>'+2'},$BROWSER->translate('TIMEOUT'))));
    } else {
      return $data;
    }
return "C";
}

sub detail_panel($$) {
  my ($segment,$feature_files) = @_;

  my ($img,$map);
  my $cell = '';

  warn $segment if DEBUG;
  warn $feature_files if DEBUG;

  if ($segment->length <= $MAX_SEGMENT) {
    # this is invoked to force small segments to be larger than the minimum size that can
    # easily be displayed.  Avoids zooming into 1 bp features like SNPs.
    resize(\$segment);

    if($BROWSER->options->{width}){
      $BROWSER->config->width($BROWSER->options->{width});
    }

    my @tracks_to_show = grep {$BROWSER->options->{features}{$_}{visible} && !/:overview$/ }
      @{$BROWSER->options->{tracks}};

#warn Dumper($BROWSER->options->{tracks});
#warn Dumper($BROWSER->options->{features});
#@tracks_to_show = @{ $BROWSER->options->{tracks} };
#warn Dumper(\@tracks_to_show);

    my %options = map {$_=>$BROWSER->options->{features}{$_}{options}} @tracks_to_show;
    my %limit   = map {$_=>$BROWSER->options->{features}{$_}{limit}}   @tracks_to_show;
    my $h_callback = make_hilite_callback();
    ($img,$map) = $BROWSER->config->render_html(
                       segment       => $segment,
				       feature_files => $feature_files,
				       tracks        => \@tracks_to_show,
				       options       => \%options,
				       limit         => \%limit,
				       do_map        => 1,
				       do_centering_map => 1,
				       lang          => $BROWSER->config->language,
				       keystyle      => $BROWSER->options->ks(),
				       flip          => $BROWSER->options->flip(),
				       hilite_callback => $h_callback,
				      );
return $img;
    $cell .= $img;
  }

#  else {
#    $cell .= i($BROWSER->translate('TOO_BIG',unit_label($MAX_SEGMENT),unit_label($DEFAULT_SEGMENT)));
#  }
#  $cell .= "\n";
#  my $table = table({-border=>0,-width=>'100%'},
#		    TR({-class=>'databody'},
#		       td({-align=>'center'},$cell)
#		      )
#		   );
#  $table .= "\n";
#  $table .= $map if $map;
#  $table .= join '',hidden('ref'),hidden('start'),hidden('stop');
#  return $table;
}

###############################################################################################

sub get_source {
  my $new_source = param('source') || param('src') || path_info();
  $new_source    =~ s!^/!!;  # get rid of leading / from path_info()
  #FIXME cookie access shouldn't be happening here..
  my $old_source = cookie('gbrowse_source') unless $new_source && request_method() eq 'GET';

  my $source   = $new_source || $old_source;
  $source ||= $BROWSER->config->source;  # the default, whatever it is
  return ($source,$old_source);
}

# This is called to check that the list of feature types given
# in the configuration file are consistent with the features
# given in the user's cookie.  If not, the settings are adjusted
# as best we can. The attempt here is to allow
# the administrator to add new feature stanzas
# without invalidating users' old settings.
sub adjust_tracks() {
  my %configured_labels = map {$_=>1} $BROWSER->config->labels;

  # tracks added to the config file recently that are not contained in
  # user's stored settings.
  foreach (grep {!$BROWSER->options->{features}{$_}} keys %configured_labels) {
    $BROWSER->options->{features}{$_}{visible} = 0;  # not visible
    $BROWSER->options->{features}{$_}{options} = 0;  # automatic
    push @{$BROWSER->options->{tracks}},$_;           # at the end
  }
  # Remove any feature types that are not mentioned in the
  # config file, excepting Uploaded and remote URL features.
  # This may happen if a stanza is removed from the config file.
  my %extra = map {$_=>1} grep {!/^(http|ftp|das|file|plugin):/
				    && !$configured_labels{$_}} keys %{$BROWSER->options->{features}};
  # remove extra from tracks && options
  if (%extra) {
    delete $BROWSER->options->{features}{$_} foreach keys %extra;
  }

  # make sure that tracks are completely consistent with options
  $BROWSER->options->tracks(grep {exists $BROWSER->options->{features}{$_}} @{$BROWSER->options->{tracks}});
}

# auto-open any tracks that match the search term
sub auto_open($) {
  my ($features) = @_;
  my $tracks = $BROWSER->options->{features};
  for my $feature (@$features) {
    my $desired_label = $BROWSER->config->feature2label($feature) or next;
    if (exists $tracks->{$desired_label}) {
      $tracks->{$desired_label}{visible} = 1;
      $BROWSER->options->h_feat($feature->display_name);
      $BROWSER->options->h_type($feature->type);
    }
  }
}

# this generates the callback for highlighting "interesting" features
sub make_hilite_callback() {
  my @hiliters = grep {$_->type eq 'highlighter'} values %$PLUGINS;
  return unless @hiliters or ($BROWSER->options->h_feat() && $BROWSER->options->h_type());
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
    # return unless $feature->type         eq $BROWSER->options->h_type();
    return unless $feature->display_name && $feature->display_name eq $BROWSER->options->h_feat();
    'yellow';
  }
}

# convert bp into nice Mb/Kb units
sub unit_label {
  my $value = shift;
  my $unit     = $BROWSER->config->setting('units')        || 'bp';
  my $divider  = $BROWSER->config->setting('unit_divider') || 1;
  return 0 if ($value == 1 and $divider > 1);
  $value /= $divider;

  my $label;
  $label = $value >= 1e9  ? sprintf("%.4g G%s",$value/1e9,$unit)
         : $value >= 1e6  ? sprintf("%.4g M%s",$value/1e6,$unit)
         : $value >= 1e3  ? sprintf("%.4g k%s",$value/1e3,$unit)
	 : $value >= 1    ? sprintf("%.4g %s", $value,    $unit)
	 : $value >= 1e-2 ? sprintf("%.4g c%s",$value*100,$unit)
	 : $value >= 1e-3 ? sprintf("%.4g m%s",$value*1e3,$unit)
	 : $value >= 1e-6 ? sprintf("%.4g u%s",$value*1e6,$unit)
	 : $value >= 1e-9 ? sprintf("%.4g n%s",$value*1e9,$unit)
         : sprintf("%.4g p%s",$value*1e12,$unit);
  return $label;
}

sub labels {
  my $settings = shift;
  my @labels = $BROWSER->config->labels;
  @labels;
}

# This subroutine is invoked to draw the checkbox group underneath the main display.
# It creates a hyperlinked set of feature names.
sub tracks_table($) {
  my $additional_features = shift;

  # set up the dumps line.
  my($ref,$start,$stop) = ($BROWSER->options->ref(),$BROWSER->options->start(),$BROWSER->options->stop());
  my $source   = $BROWSER->config->source;
  my $self_url = "?display_help=citations";

  my @labels = $BROWSER->options->tracks();
  my %labels          = map {$_ => make_citation_link($_,$self_url) } @labels;

  if ($BROWSER->options->sk() eq 'sorted') {
    my %keys = map {$_=>label2key($_)} @labels;
    @labels    = sort { lc($keys{$a}) cmp lc($keys{$b})} @labels;
  }
  my @defaults = grep {$BROWSER->options->{features}{$_}{visible}  } @labels;

  autoEscape(0);
  my $sTable 	= $BROWSER->options->stp()
    ? hidden(-name=>'label',-value=>'_',-override=>1) 
    : '';  # dummy, just to keep param() happy.

  my $overview_color = $BROWSER->config->setting('overview bgcolor') || DEFAULT_OVERVIEW_BGCOLOR;

  $sTable.= table({-border=>0,-width=>'100%'},
		  # row
		  $BROWSER->options->stp() ?
		  (
		   TR(	td({-class=>'searchbody', -valign=>'top',-align=>'left'},
			   b($BROWSER->translate('Tracks')),a({-href=>"?stp=0"},'['.$BROWSER->translate('HIDE').']'),
			   p(i($BROWSER->translate('External_tracks')),
			     div({-style=>"background: $overview_color"},$BROWSER->translate('Overview_tracks'))
			    )),
			td({-class=>'searchbody',-colspan=>3,-width=>'85%'},
			   checkbox_group(-name=>'label',
					  # use the track ordering to adjust the order of the checkboxes
					  # this is an array slice
					  -values     => \@labels,
					  -labels     => \%labels,
					  -defaults   => \@defaults,
					  -cols       => 3,
					  -override   => 1,
					 ))),
		  ) :
		  TR(td({-class=>'searchbody',-colspan=>3},
			b($BROWSER->translate('Tracks')),a({-href=>"?stp=1"},'['.$BROWSER->translate('SHOW').']'))
		    )
		 );
  autoEscape(1);
  return $sTable;
}

# URLs for external annotations
sub external_table($) {
  my $feature_files = shift;
  my (@rows,$count);

  my ($preset_labels,$preset_urls) = get_external_presets();  # (arrayref,arrayref)
  my $presets = '&nbsp;';
  if ($preset_labels && @$preset_labels) {  # defined AND non-empty
    my %presets;
    @presets{@$preset_urls} = @$preset_labels;
    unshift @$preset_urls,'';
    $presets{''} = $BROWSER->translate('PRESETS');
    $presets = popup_menu(-name   => 'eurl',
			  -values => $preset_urls,
			  -labels => \%presets,
			  -override => 1,
			  -default  => '',
			  -onChange => 'document.externalform.submit()'
			 );
  }
  my $segment = $BROWSER->options->ref().':'.$BROWSER->options->start().','.$BROWSER->options->stop();

  local $^W = 0;
  for my $filename ($BROWSER->options->tracks()) {

    (my $f = $filename) =~ s!(http:.+/das/\w+)(?:\?(.+))?$!$1/features?segment=$segment;$2!;

    warn "filename = $filename" if DEBUG_EXTERNAL;
    next unless $filename =~ /^(ftp|http):/ && $feature_files->{$filename};
    warn "external_table(): filename = $filename" if DEBUG;
    push @rows,th({-align=>'right',-valign=>'TOP'},"URL",++$count).
      td(textfield(-name=>'eurl',-size=>50,-value=>$filename,-override=>1),'<br/>',
	 a({-href=>$f,-target=>'help'},'['.$BROWSER->translate('Download').']'),
	 get_uploaded_file_info($BROWSER->options->{features}{$filename}{visible} && $feature_files->{$filename})
	);
  }
  push @rows,th({-align=>'right'},
		$BROWSER->translate('Remote_url')).
		  td(textfield(-name=>'eurl',-size=>40,-value=>'',-override=>1),
		     $presets);

  return table({-border=>0,-width=>'100%'},
	       TR({-class=>'uploadtitle'},
		  th({-align=>'left',-colspan=>2},
		     $BROWSER->translate('Remote_title').':',
		     a({-href=>'?display_help=annotation'.'#remote',-target=>'help'},'['.$BROWSER->translate('Help').']'))),
	       TR({-class=>'uploadbody'},\@rows),
	       TR({-class=>'uploadbody'},
		  th('&nbsp;'),
		  th({-align=>'left'},submit($BROWSER->translate('Update_urls'))))
	      );
}

sub get_external_presets() {
  my $presets  = $BROWSER->config->setting('remote sources') or return;
  my @presets  = shellwords($presets||'');
  my (@labels,@urls);
  while (@presets) {
    my ($label,$url) = splice(@presets,0,2);
    next unless $url && $url =~ /^(http|ftp)/;
    push @labels,$label;
    push @urls,$url;
  }
  return unless @labels;
  return (\@labels,\@urls) if wantarray;
  my %presets;
  @presets{@urls} = @labels;
  return \%presets;
}

# The get_features() call fetches the genome segments specified in the
# current settings.  It is really just a front end to lookup_segments()
# which does the real work.  The main work in get_segments() is to
# identify any segments that are below MIN_SEG_SIZE in length, and to
# recenter on a window MIN_SEG_SIZE wide.  This prevents the browser
# from getting brain damaged when fetching 1bp features like SNPs.
sub get_features {
  my $db = open_database();
  unless ($db) {
    fatal_error("ERROR: Unable to open database",$BROWSER->config->setting('description'),pre($@));
  }

  if($db->can('biosql')){
    eval {$db->biosql->version($BROWSER->options->version())};
  }

  my @features = lookup_features_from_db($db);

  # sort of hacky way to force keyword search on wildcards
  if (defined $BROWSER->options->name() && $BROWSER->options->name() =~ /[*?]/) {
    (my $searchterm = $BROWSER->options->name()) =~ tr/*?//d;
    push @features,do_keyword_search($searchterm) if length $searchterm > 0;
  }

  # h'mmm.  Couldn't find the feature.  See if it is in an uploaded file.
  @features    = lookup_features_from_external_sources($BROWSER->options->name(),undef)
    unless @features;

  return \@features;
}

sub features2segments {
  my $features = shift;
  my $refclass = $BROWSER->config->setting('reference class') || 'Sequence';
  my $db = open_database();
  my @segments = map {
    my $version = eval {$_->isa('Bio::SeqFeatureI') ? undef : $_->version};
    $db->segment(-class => $refclass,
		 -name  => $_->ref,
		 -start => $_->start,
 		 -stop  => $_->end,
		 -absolute => 1,
                  defined $version ? (-version => $version) : ())} @$features;
  warn "segments = @segments\n" if DEBUG;
  \@segments;
}


# sort of un-perlish -- we pass a reference to the handle that holds the segment
sub resize {
  my $segment_ref = shift;
  my $s = $$segment_ref;
  return unless $s->length < MIN_SEG_SIZE;

  # resize
  my $resize = ($s->length <= TINY_SEG_SIZE) ? EXPAND_SEG_SIZE : MIN_SEG_SIZE;
  error($BROWSER->translate('Small_interval',$resize)); # error message

  my $middle = int(($s->start + $s->end)/2);
  my $new_seg = $s->factory->segment(-name  => $s->seq_id,
				     -start => $middle - int($resize/2),

				     -end   => $middle + int($resize/2)-1);
  $$segment_ref = $new_seg;
}

# interesting heuristic way of fetching sequence segments based on educated guesses
sub lookup_features_from_db($) {
  my ($db) = @_;
  my @segments;

  warn "name = ".$BROWSER->options->name().", ref = ".$BROWSER->options->ref().", start = ".$BROWSER->options->start().", stop = ".$BROWSER->options->stop().", version = ".$BROWSER->options->version()."\n" if DEBUG;

  $db->debug(0);
  my $divisor = $BROWSER->config->setting(general=>'unit_divider') || 1;
  my $padding = $BROWSER->config->setting(general=>'landmark_padding') || 0;

  if (my $name = $BROWSER->options->name()) {
    warn "name = $name" if DEBUG;
    @segments = $BROWSER->config->name2segments($name,$db,TOO_MANY_SEGMENTS);
  }

  elsif (my $names = $BROWSER->options->q()) {
    warn "q = $names" if DEBUG;
    my $max = (TOO_MANY_SEGMENTS) / @$names;
    @segments = map {$BROWSER->config->name2segments($_,$db,$max)} @$names;
  }

  elsif (my $ref = $BROWSER->options->ref()) {
    my @argv = (-name  => $ref);
    push @argv,(-start => $BROWSER->options->start()*$divisor) if defined $BROWSER->options->start();
    push @argv,(-end   => $BROWSER->options->stop()*$divisor)  if defined $BROWSER->options->stop();
    warn "looking up @argv" if DEBUG;
    @segments = $db->segment(@argv);
  }

   # expand by a bit if padding is requested
   # THIS CURRENTLY ISN'T WORKING PROPERLY
   if (@segments == 1 && $padding > 0 && !$BROWSER->options->name()) {
     $segments[0] = $segments[0]->subseq(-$padding,$segments[0]->length+$padding);
   }

  # some segments are not going to support the absolute() method
  # if they come out of BioPerl
  eval {$_->absolute(1)} foreach @segments;

  return unless @segments;
  # Filter out redundant segments; this can happen when the same basic feature is
  # present under several names, such as "genes" and "frameworks"
  my %seenit;
  my $version = eval {$_->isa('Bio::SeqFeatureI') ? undef : $_->version};
  $version ||= 0;
  @segments = grep {!$seenit{$_->seq_id,$_->start,$_->end,$version}++} @segments;
  return @segments if @segments > 1;

  # this prevents any confusion over (ref,start,stop) and (name) addressing.
  $BROWSER->options->ref($segments[0]->seq_id);
  $BROWSER->options->start($segments[0]->start/$divisor);
  $BROWSER->options->stop($segments[0]->end/$divisor);

  return $segments[0];
}

# Find features named in external sources.
# Currently this only works with uploaded files, but it should
# be extended to work with DAS files too.
sub lookup_features_from_external_sources($) {
  my ($searchterm) = @_;

  my @uploaded_files = load_uploaded_files(undef) or return;
  for my $file (@uploaded_files) {
    next unless $file->can('get_feature_by_name');
    my @features = $file->get_feature_by_name($searchterm);
    return @features if @features;
  }

  # No exact match.  Try inexact match.
  my $max_keywords = $BROWSER->config->setting('keyword search max')|| MAX_KEYWORD_RESULTS;

  for my $file (@uploaded_files) {
    next unless $file->can('search_notes');
    my @matches = $file->search_notes($searchterm,$max_keywords);
    return map {
      my ($feature,$description,$score) = @$_;
      Bio::Graphics::Feature->new(-name => $feature->display_name,
				  -type => $description,
				  -score => $score,
				  -ref   => $feature->ref,
				  -start => $feature->start,
				  -end   => $feature->end)
      } @matches if @matches;
  }

  return;
}


################ perform keyword search ###############
sub do_keyword_search {
  my $searchterm = shift;

  # if they wanted something specific, don't give them non-specific results.
  return if $searchterm =~ /^[\w._-]+:/;

  # Need to untaint the searchterm.  We are very lenient about
  # what is accepted here because we wil be quote-metaing it later.
  $searchterm =~ /([\w .,~!@\#$%^&*()-+=<>?\/]+)/;
  $searchterm = $1;

  my $match_sub = 'sub {';
  foreach (split /\s+/,$searchterm) {
    $match_sub .= "return unless \$_[0] =~ /\Q$_\E/i; ";
  }
  $match_sub .= "};";
  my $match = eval $match_sub;

  my $db = open_database();
  my $max_keywords = $BROWSER->config->setting('keyword search max')
		    || MAX_KEYWORD_RESULTS;
  my @matches = grep { $match->($_->[1]) }
    $db->search_notes($searchterm,$max_keywords);

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
					      -end    => $seg->abs_stop,
					      -factory=> $db);

  }
  return @results;
}

################ format keyword search ###################
sub multiple_choices($) {
  my ($results) = @_;

  my $result = '';

  my $db   = open_database();
  my $name = $BROWSER->options->name();
  my $regexp = join '|',($name =~ /(\w+)/g);

  # sort into bins by reference and version
  my %refs;
  foreach (@$results) {
    my $version = eval {$_->isa('Bio::SeqFeatureI') ? undef : $_->version};
    my $ref = $_->seq_id;
    $ref .= " version $version" if defined $version;    
    push @{$refs{$ref}},$_;
  }

  $BROWSER->config->width($BROWSER->options->width()*OVERVIEW_RATIO);
  my $overviews = $BROWSER->config->hits_on_overview($db,$results,$BROWSER->options->{features});
  my $count = @$results;

  $result .= '<table>';
  $result .= TR({-class=>'datatitle'},
	   th({-colspan=>4},
	      $BROWSER->translate('Hit_count',$count)));
  $result .= TR({-class=>'datatitle'},
	   th({-colspan=>4},
	      $BROWSER->translate('Possible_truncation',MAX_KEYWORD_RESULTS)))
    if $count >= MAX_KEYWORD_RESULTS;

  local $^W = 0;  # get rid of non-numeric warnings coming out of by_score_and_position
  for my $ref(sort keys %refs) {
    my ($id) = split /\s/, $ref; 
    my @results = @{$refs{$ref}};
    $result .= TR(th({-class=>'databody',-colspan=>4,-align=>'center'},$BROWSER->translate('Matches_on_ref',$ref),'<br/>',
		$overviews->{$ref}));

    my $padding = $BROWSER->config->setting(general=>'landmark_padding') || 0;

    for my $r (sort by_score_and_position @results) {
      my $version = eval {$r->isa('Bio::SeqFeatureI') ? undef : $r->version};
      my $name        = eval {$r->name}  || $r->primary_tag;

      my $class       = eval {$r->class} || $BROWSER->translate('Sequence');
      my $score       = eval {$r->score} || $BROWSER->translate('NOT_APPLICABLE');
      my ($start,$stop) = ($r->start,$r->end);
      my $padstart = $start - $padding;
      my $padstop  = $stop  + $padding;
      my $description = escapeHTML(eval{join ' ',$r->attributes('Note')}
				   ||eval{$r->method}||eval{$r->source_tag}||$r->{ref});
      if (my @aliases = eval{$r->attributes('Alias')}) {
        $description .= escapeHTML " [@aliases]";
      }
      my $n           = uri_escape("$name");
      my $c           = uri_escape($class);
      $description =~ s/($regexp)/<b class="keyword">$1<\/b>/ig;
      $description =~ s/(\S{60})/$1 /g;  # wrap way long lines

      my $objref     = $class ? "?name=$c:$n" : "?name=$n";
      my $posref     = "?ref=$id;start=$padstart;stop=$padstop;version=$version";
      my $position = format_segment($r);
      $result .= TR({-class=>'databody',-valign=>'TOP'},
	       th({-align=>'right'},ref($name) ? a({-href=>$objref},$name):tt($name)),
	       td($description),
	       td(a({-href=>$posref},$position . ' ('.($stop-$start+1).' '.$BROWSER->translate('bp').')')),
	       td($BROWSER->translate('SCORE',$score)));
    }
  }
  $result .= '</table>';

  return $result;
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
  my $s = shift or return $BROWSER->translate('Not_applicable');
  my $ref = $s->seq_id;
  my $start = commas($s->start);
  my $stop  = commas($s->end);
  return "<b>$ref</b>:$start..$stop";
}

sub get_ranges {
  return $BROWSER->config->get_ranges;
}

sub get_zoomincrement {
  my $zoom      = $BROWSER->config->setting('fine zoom')  || DEFAULT_FINE_ZOOM;
  $zoom;
}

sub segment2link {
  my ($segment,$label) = @_;

  my $source = $BROWSER->config->source;
  return  qq(<a href="?name=$segment">$segment</a>) unless ref $segment;

  my ($start,$stop) = ($segment->start,$segment->end);
  my $ref = $segment->seq_id;
  my $bp = $stop - $start;
  my $s = commas($start);
  my $e = commas($stop);
  $label ||= "$ref:$s..$e";
  return qq(<a href="?ref=$ref;start=$start;stop=$stop">$label</a>);
}


########## upload stuff ########
sub new_upload() {
  my $rand = int(1000*rand);
  my $file = "upload.$rand";
  my $fh_out = open_uploaded_file($file,'>');
  close $fh_out;
  my (undef,$url) = name_uploaded_file($file);
  warn "url = $url" if DEBUG;
  push @{$BROWSER->options->{tracks}},$url;
  $BROWSER->options->{features}{$url} = {visible=>1,options=>0,limit=>0};
  return $file;
}

sub handle_upload($) {
  my ($fh) = @_;
  warn "handle_upload($fh)" if DEBUG;
  # $fh is a CGI string/filehandle object, so be careful
  my ($filename) = "$fh" =~ /([^\/\\:]+)$/;
  my $fh_out = open_uploaded_file($filename,'>') or return;
  my $buffer;
  while (read($fh,$buffer,1024)) {
     $buffer =~ s/\r\n?/\n/g;
     print $fh_out $buffer;
  }
  close $fh_out;
  my (undef,$url) = name_uploaded_file($filename);
  warn "url = $url" if DEBUG;
  push @{$BROWSER->options->{tracks}},$url;
  $BROWSER->options->{features}{$url} = {visible=>1,options=>0,limit=>0};
}

sub handle_edit($) {
  my ($data) = @_;
  my $file = param('edited file') or return;
  my @lines = unexpand(split /\r?\n|\r\n?/,$data);
  $data = join "\n",@lines;
  $data .= "\n";
  my $fh = open_uploaded_file($file,'>');
  print $fh $data;
  close $fh;
}

sub handle_quickie($) {
  my ($data) = @_;
  return unless $data;

  # format of quickie data is reference+type+name+start-end,start-end,start-end
  my ($reference,$type,$name,@position) = shellwords($data||'');
  my @segments = map { [/(-?\d+)(?:-|\.\.)(-?\d+)/]} map {split /,/} @position;
  my $feature = Bio::Graphics::Feature->new(
					    -ref      => $reference||'',
					    -type     => $type||'',
					    -name     => $name||'',
					    -segments => \@segments,
					    );
  write_auto([$feature]);
}

sub write_auto($) {
  my ($features) = @_;

  my $file = 'search_results';
  clear_uploaded_file($file);
  return unless @$features;

  my %seenit;

  warn "opening $file...\n" if DEBUG;
  my $out = open_uploaded_file($file,">>") or return;
  warn "writing $file...\n" if DEBUG;
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
  my (undef,$url) = name_uploaded_file($file);
  unshift @{$BROWSER->options->{tracks}},$url;
  $BROWSER->options->{features}{$url} = {visible=>1,options=>0,limit=>0};
}

sub name_uploaded_file($) {
  my ($filename) = @_;
  warn "name_uploaded_file(): filename = $filename" if DEBUG;
  # keep last non-[/\:] part of name
  my ($name) = $filename =~ /([^:\\\/]+)$/;
  $name =~ tr/-/_/;
  my $id = $BROWSER->options->id() or return;
  my (undef,$tmpdir) = $BROWSER->config->tmpdir($BROWSER->config->source."/uploaded_file/$id");
  my $physical = "$tmpdir/$name";
  my $url      = "file:$name";
  return wantarray ? ($physical,$url) : $physical;
}

sub open_uploaded_file($$) {
  my ($filename,$mode) = @_;
  $filename =~ s/^file://;
  $mode ||= "<";

  my $file = name_uploaded_file($filename);
  warn "file = $file" if DEBUG;
  unless ($file) {
    error($BROWSER->translate('Purged',$filename));
    clear_uploaded_file($filename);
    return;
  }

  my $result = open (F,"${mode}${file}");

  unless ($result) {
    warn "Can't open the file named $filename.  Perhaps it has been purged? (error: $!)";
    clear_uploaded_file($filename);
    return;
  }

  return \*F;
}

sub load_external_sources($) {
  my ($segments) = @_;

  unless ($segments && ref $segments eq 'ARRAY') {
    $segments = [open_database()->segment($segments)];
  }
  elsif ($segments) {
    return if @$segments > 1;
  }

  my $segment = $segments->[0] if $segments;

  return undef unless defined $segment && (ref($segment) || $segment =~ /\S/);

  my @feature_file = load_uploaded_files($segment);
  warn "uploaded feature_file = @feature_file" if DEBUG_EXTERNAL;

  my @external = load_remote_sources($segment);
  push @feature_file,@external if @external;

  warn "feature_file = @feature_file" if DEBUG_EXTERNAL;

  my %feature_file = map {(ref($_) ? $_->name: $_) => $_} @feature_file;
  warn join "\n",%feature_file if DEBUG_EXTERNAL;
  my $f = \%feature_file;

  load_plugin_annotations($segment,$f) if $segment && $segment->length <= $MAX_SEGMENT;
  return $f;
}

sub load_uploaded_files($) {
  my ($segment) = @_;
  my @files;
  my $width = $BROWSER->options->width() or return;
  my $rel2abs = coordinate_mapper($segment) if $segment;

  my @uploads = grep {/^file:/} $BROWSER->options->tracks();
  my @result;
  for my $file (@uploads) {
    warn "loading $file" if DEBUG;
    if (!$BROWSER->options->{features}{$file}{visible}) { # turned off
      push @result,$file;
      next;
    }

    my $fh = open_uploaded_file($file,"<") or return;

    my @coord_mapper = $rel2abs ? (-map_coords=>$rel2abs) : ();

    my $feature_file = Bio::Graphics::FeatureFile->new(-file           => $fh,
						       -smart_features =>1,
						       @coord_mapper,
						       );
    close $fh;
    next unless $feature_file;
    $feature_file->name($file);
    push @result,$feature_file;
  }
  @result;
}

sub line_end {
   my $agent  = CGI->user_agent();
   return "\r"   if $agent =~ /Mac/;
   return "\r\n" if $agent =~ /Win/;
   return "\n";
}

sub load_remote_sources {
  my ($segment) = @_;
  my @uploads = grep {/^(http|ftp):/} $BROWSER->options->tracks();
  my $rel2abs = coordinate_mapper($segment) if $segment;
  my @result;
  for my $file (@uploads) {
    warn "load_remote_sources(): loading $file" if DEBUG;
    if (!$BROWSER->options->{features}{$file}{visible}) { # turned off
      push @result,$file;
      next;
    }
    my $feature_file = get_remote_feature_data($file,$rel2abs) or next;
    push @result,$feature_file;
  }
  return @result;
}

sub load_plugin_annotations($$) {
  my ($segment,$feature_files) = @_;
  for my $p (keys %$PLUGINS) {
    next unless $PLUGINS->{$p}->type eq 'annotator';
    my $name = "plugin:".$PLUGINS->{$p}->name;
    next unless $BROWSER->options->{features}{$name}{visible};
    my $features = $PLUGINS->{$p}->annotate($segment) or next;
    $features->name($name);
    $feature_files->{$name} = $features;
  }
}

sub load_plugin_annotators() {
  my %default_plugin = map {$_=>1} map {s/^plugin:// && $_} 
    grep {/^plugin:/} $BROWSER->config->default_labels;

  for my $p (keys %$PLUGINS) {
    next unless $PLUGINS->{$p}->type eq 'annotator';
    my $name = $PLUGINS->{$p}->name;
    $name = "plugin:$name";
    $PLUGIN_NAME2LABEL{$name} = $p;
    unless ($BROWSER->options->{features}{$name}) {
      push @{$BROWSER->options->{tracks}},$name;
      $BROWSER->options->{features}{$name} = {visible=>$default_plugin{$p}||0,options=>0,limit=>0};
    }
  }
}


sub get_remote_feature_data($$) {
  my ($url,$rel2abs) = @_;
  warn "get_remote_feature_data(): fetching $url" if DEBUG;

  if ($url =~ m!^(http://.+/das)/([^/?]+)(?:\?(.+))?$!) { # DAS source!
    unless (eval "require Bio::Das; 1;") {
      error($BROWSER->translate('NO_DAS'));
      return;
    }

    my ($src,$dsn,$cgi_args) = ($1,$2,$3);
    my @aggregators = shellwords($BROWSER->config->setting('aggregators') ||'');
    my (@types,@categories);

    if ($cgi_args) {
      my @a = split /[;&]/,$cgi_args;
      foreach (@a) {
	my ($arg,$val) = split /=/;
	push @types,uri_unescape($val)      if $arg eq 'type';
	push @categories,uri_unescape($val) if $arg eq 'category';
      }
    }
    my @args = (-source     => $src,
		-dsn        => $dsn,
		-aggregators=> \@aggregators);
    push @args,(-types => \@types)           if @types;
    push @args,(-categories => \@categories) if @categories;
    my $das      =  Bio::Das->new(@args);

    return unless $das;
    my $segment = $das->segment($BROWSER->options->ref(),$BROWSER->options->start(),$BROWSER->options->stop());
    # the next step gives the current segment the same name as the DAS source
    # and ensures that the DAS source appears in the list of external sources in the UI
    $segment->name($url);
    return $segment;
  }

  unless ($UA) {
    unless (eval "require LWP") {
      error($BROWSER->translate('NO_LWP'));
      return;
    }
    $UA = LWP::UserAgent->new(agent    => "Generic-Genome-Browser/$VERSION",
			      timeout  => URL_FETCH_TIMEOUT,
			      max_size => URL_FETCH_MAX_SIZE,
			     );
  }
  my $id = md5_hex($url);     # turn into a filename
  $id =~ /^([0-9a-fA-F]+)$/;  # untaint operation
  $id = $1;

  my (undef,$tmpdir) = $BROWSER->config->tmpdir($BROWSER->config->source.'/external');
  my $response = $UA->mirror($url,"$tmpdir/$id");
  if ($response->is_error) {
    error($BROWSER->translate('Fetch_failed',$url,$response->message));
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

sub print_uploaded_file_features($) {
  my ($file) = @_;
  my $line_end = line_end();
  if (my $fh = open_uploaded_file($file,"<")) {
    while (<$fh>) {
      chomp;
      print $_,$line_end;
    }
  }
}

sub get_uploaded_file_info {
  my $feature_file = shift or return i("Display off");
  warn "get_uploaded_file_info(): feature_file = $feature_file" if DEBUG;

  my $modified = localtime($feature_file->mtime);
  #my @refs      = sort $feature_file->refs;
  #my @refs      = sort $feature_file->features;
  my @refs      = sort($feature_file->features)
    unless $feature_file->name =~ m!/das/!;

  my $db        = open_database();

  my ($landmarks,@landmarks,@links);

  if (@refs > TOO_MANY_REFS) {
    $landmarks = b($BROWSER->translate('Too_many_landmarks',scalar @refs));
  } else {
    @links = map {segment2link($_,$_->display_name)} @refs;
    $landmarks = tableize(\@links);
  }
  warn "get_uploaded_file_info(): modified = $modified, landmarks = $landmarks" if DEBUG;
  return i($BROWSER->translate('File_info',$modified,$landmarks||''));
}

sub clear_uploaded_file($) {
  my ($file) = @_;
  warn "clear_uploaded_file(): file = $file" if DEBUG;
  my $path = name_uploaded_file($file) or return;
  unlink $path;
  delete $BROWSER->options->{features}{"file:$file"};
  warn "clear_uploaded_file(): deleting file = file:$file" if DEBUG;
  $BROWSER->options->tracks(grep {$_ ne "file:$file"} @{$BROWSER->options->{tracks}});
}

sub edit_uploaded_file($) {
  my ($file) = @_;
  warn "edit_uploaded_file(): file = $file" if DEBUG;
  print '<form>';
  my $data;
  my $fh = open_uploaded_file($file,"<") or return;
  $data = join '',expand(<$fh>);
  print table({-width=>'100%'},
	      TR({-class=>'searchbody'},
		 td($BROWSER->translate('Edit_instructions')),
		),
	      TR({-class=>'searchbody'},
		 td(
		    a({-href=>"?display_help=annotation#format",-target=>'help'},
		      b('['.$BROWSER->translate('Help_format').']'))
		   ),
		),
	      TR({-class=>'searchtitle'},
		 th($BROWSER->translate('Edit_title'))),
	      TR({-class=>'searchbody'},
		 td({-align=>'center'},
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
		 th(reset($BROWSER->translate('Undo')).'&nbsp;'.
		    submit('Cancel').'&nbsp;'.
		    b(submit('Submit Changes...'))))
	     );
  print hidden(-name=>'edited file',-value=>$file);
  print '</form>';
}

sub coordinate_mapper {
  my $current_segment = shift;
  my $db              = open_database();

  my ($ref,$start,$stop) = ($current_segment->seq_id,
			    $current_segment->start,$current_segment->end);
  my %segments;

  my $closure = sub {
    my ($refname,@ranges) = @_;

    # hack for timing tests - this disables coordinate remapping
    # and shows what would happen if user uploaded everything in abs
    # coordinates.
    if (0)  {  # turn on for timing tests
      return unless $refname eq $ref;
      my @in_range = grep {$_->[0] <= $stop && $_->[1] >= $start} @ranges;
      return unless @in_range;
      return ($refname,@in_range);
    }

    unless (exists $segments{$refname}) {
      my @segments = $BROWSER->config->name2segments($refname,$db,TOO_MANY_SEGMENTS,1);
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
    foreach (@abs_segs) {
      return ($absref,@abs_segs) if $_->[0] <= $stop && $_->[1] >= $start;
    }
    return;
  };
  return $closure;
}

sub bookmark_link() {
  my $q = new CGI('');
  my @keys = $BROWSER->options->name() ? qw(name source width version)
                               : qw(start stop ref source width version);
  foreach (@keys) {
    $q->param(-name=>$_,-value=>$BROWSER->options->{$_});
  }

  # handle selected features slightly differently
  my @selected = grep {$BROWSER->options->{features}{$_}{visible} && !/^(file|ftp|http):/} @{$BROWSER->options->{tracks}};
  $q->param(-name=>'label',-value=>join('-',@selected));

  # handle external urls
  my @url = grep {/^(ftp|http):/} $BROWSER->options->tracks();
  $q->param(-name=>'eurl',-value=>\@url);

  return "?".$q->query_string();
}

sub image_link {
  my $rand = md5_hex(rand);
  return "?display_help=link_image;rand=$rand";
}

sub svg_link {
  my $rand = md5_hex(rand);
  return "?display_help=svg_image;rand=$rand";
}

# reorder @labels based on settings in the 'track.XXX' parameters
sub adjust_track_order {
  my $settings = shift;

  my @labels  = $BROWSER->options->tracks();
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
  $BROWSER->options->tracks(@labels);
}

sub adjust_track_options {
  my $settings = shift;
  foreach (grep {/^option\./} param()) {
    my ($track)   = /(\d+)/;
    my $feature   = $BROWSER->options->{tracks}[$track];
    my $option    = param($_);
    $BROWSER->options->{features}{$feature}{options} = $option;
  }
  foreach (grep {/^limit\./} param()) {
    my ($track)   = /(\d+)/;
    my $feature   = $BROWSER->options->{tracks}[$track];
    my $option    = param($_);
    $BROWSER->options->{features}{$feature}{limit} = $option;
  }
  foreach (@{$BROWSER->options->{tracks}}) {
    $BROWSER->options->{features}{$_}{visible} = 0;
  }

  foreach (param('track.label')) {
    $BROWSER->options->{features}{$_}{visible} = 1;
  }
}

# this controls the "adjust track options" screen
sub set_track_options() {
  my @labels =  $BROWSER->options->tracks();

  my %keys            = map {$_ => $BROWSER->config->setting($_=>'key') || $_} @labels;
  my @sorted_labels   = ('',sort {lc $keys{$a} cmp lc $keys{$b}} @labels);

  my $oc = $BROWSER->config->setting('overview bgcolor') || DEFAULT_OVERVIEW_BGCOLOR;

  my @rows;
  for (my $track = 0; $track < @labels; $track++) {
    my $label = $labels[$track];
    push @rows,
      th({-align=>'left',-class=>'searchtitle'},$BROWSER->translate("Track"),$track+1).
      th({-align=>'left',-class=>'searchbody'},$label=~/:overview$/ ? div({-style=>"background: $oc"},
									  "$keys{$label}<sup>*</sup>")
	                                                            :$keys{$label}).
      td({-align=>'center',-class=>'searchbody'},
	     checkbox(-name     => 'track.label',
		      -value    => $label,
		      -override => 1,
		      -checked  => $BROWSER->options->{features}{$label}{visible},
		      -label => '')
	    ).
      td({-align=>'center',-class=>'searchbody'},
	     popup_menu( -name     => "option.$track",
			 -values   => [0..3],
			 -override => 1,
			 -default  => $BROWSER->options->{features}{$label}{options},
			 -labels   => {0=> $BROWSER->translate('Auto'),
                                       1=> $BROWSER->translate('Compact'),
                                       2=> $BROWSER->translate('Expand'),
				       3=> $BROWSER->translate('Expand_Label'),
				      })
	   ).
	td({-align=>'center',-class=>'searchbody'},
	   popup_menu(-name    => "limit.$track",
		      -values  => [0,5,10,25,100],
		      -labels  => {0=>$BROWSER->translate('No_limit')},
		      -override => 1,
		      -default => $BROWSER->options->{features}{$label}{limit})
	    ).
	td({-align=>'center',-class=>'searchbody'},
	   popup_menu(-name    => "track.$track",
		      -values  => \@sorted_labels,
		      -labels  => \%keys,
		      -override => 1,
		      -onChange => 'document.settings.submit()',
		      -default => '')
	    );
  }
  my $controls = TR({-class=>'searchtitle'},
		    td({-colspan=>3,-align=>'center'},
		       reset($BROWSER->translate('Undo')).'&nbsp;'.
		       submit(-name=>'revert', -label=>$BROWSER->translate('Revert')).'&nbsp;'.
		       submit(-name=>'refresh',-label=>$BROWSER->translate('Refresh')).'&nbsp;'
		      ),
		    td({-align=>'center',-colspan=>3},
		       submit  (-name=>$BROWSER->translate('Cancel'),   -value=>$BROWSER->translate('Cancel_Return')).'&nbsp;'.
		       b(submit(-name=>$BROWSER->translate('Redisplay'),-value=>$BROWSER->translate('Accept_Return')))
		      ));

  print h1({-align=>'center'},$BROWSER->translate('Settings',$BROWSER->config->setting('description')));
  print start_form(-name=>'settings');
  print table({-width=>'100%',-border=>0},
	      $controls,
	      TR({-class=>'searchtitle'},
		 th({-colspan=>6},$BROWSER->translate('Options_title'))),
	      TR({-class=>'searchbody'},
		 td({-colspan=>6},
		    $BROWSER->translate('Settings_instructions')
		   ),
		),
	      TR({-class=>'searchtitle'},
		 th($BROWSER->translate('Track')),
		 th($BROWSER->translate('Track Type')),
		 th($BROWSER->translate('Show')),
		 th($BROWSER->translate('Format')),
		 th($BROWSER->translate('Limit')),
		 th($BROWSER->translate('Change_Order')),
		),
	      TR(\@rows),
	      $controls,
	      hidden(-name=>$BROWSER->translate('Set_options'), -value=>1,-override=>1),
	      hidden(-name=>$BROWSER->translate('Adjust_order'),-value=>1,-override=>1),
	     );
  print $BROWSER->translate('EXTERNAL_TRACKS'),
    '<br/>',
      div({-style=>"background: $oc"},
	  $BROWSER->translate('OVERVIEW_TRACKS')
	  );
  print '</form>';
}

sub help() {
  my $help_type = $BROWSER->options->display_help();
  my $conf_dir = $BROWSER->config->setting('help') || GBROWSE_HELP;

  my $param = {
               referer => referer(),
               browser => $BROWSER,
              };

  if ($help_type eq 'citations') {
    build_citation_page();
  }

  elsif ($help_type eq 'link_image') {
#FIXME    build_link_image_page(undef);
  } elsif ($help_type eq 'svg_image') {
#FIXME    build_svg_image_page(undef);
  }

  else {
    my @components = File::Spec->splitdir($help_type);
    my $updir      = File::Spec->updir;
    # don't let evil people get into root directory
    my $evil       = grep { /^$updir$/o } @components;
    if ( ! grep { /^$updir$/o } @components ) {
      $param->{help_message} = build_help_page("$conf_dir/${help_type}_help.html");
    }
  }

  my $result = undef;
  $BROWSER->template->process('help.tt2',$param,\$result);
  print $result;
}

sub build_help_page {
  my $helpfile = shift or return;
  my $file = url2file($helpfile) or return;
  my $root = $BROWSER->config->setting('help') || GBROWSE_HELP;
  open(F,$file) or return;

  my $page = undef;

  while (<F>) { # fix up relative addressing of images
    s/(href|src)=\"([^\"\#\$]+)\"/$1=\"$root\/$2\"/g;
    s/<!--\s*\#include-classes\s*-->/object_classes_for_help()/e;
    $page .= $_;
  }
  close F;

  return $page;
}

sub make_citation {
  my $config  = shift;
  my $feature = shift;
  my $citation = eval {$config->citation($feature,$BROWSER->config->language)};
  # BUG: here's where we should remove "bad" HTML, but we don't!
  # should remove active content and other nasties
  (my $link     = $feature) =~ tr/ /-/;
  my $text      = label2key($feature);
  return join ('',
	       dt(a({-name=>$link},b($text))),
	       dd($citation||$BROWSER->translate('NO_CITATION')),
	       p());
}

# build a citation page
sub build_citation_page() {
  my @labels   = $BROWSER->config->labels();

  my @features = $BROWSER->config->labels;
  my $external_features = load_external_sources(undef);
  my (@citations);

#FIXME  print h2($BROWSER->translate('Track_descriptions'));

  # build native features
  print h3($BROWSER->translate('Built_in'));
  for my $feature (@features) {
    push @citations,make_citation($BROWSER->config,$feature);
  }
  print blockquote(dl(@citations));

  # build external features
  if (%$external_features) {
    print '<hr/>',h3($BROWSER->translate('External'));
    for my $file (keys %$external_features) {
      my @citations = ();
      my $f = uri_escape($file);
      my $name   = $file;
      my $is_url = $name =~ m!^(http|ftp)://!;
      my $download = uri_escape($BROWSER->translate('Download_data'));
      my $link   = $is_url  ? $name  : "?$download=1;file=$f";
      my $anchor = $name;
      $anchor =~ tr/ /-/;

      unless (ref $external_features->{$file}) {
	print h3(a{-name=>$anchor,-href=>$link},$name);
	print blockquote($BROWSER->translate('Activate'));
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
    print p($BROWSER->translate('No_external')) unless @citations;
  }

}

sub build_link_image_page($) {
  my $segment  = shift;
  my $source = $BROWSER->config->source;
  my $url = url(-base=>1);
  $url   .= url(-absolute=>1);
  $url    = dirname($url) . "/gbrowse_img/".uri_escape($source);
  my $width  = $BROWSER->config->width;
  my $name   = $BROWSER->options->name() || $BROWSER->options->ref().':'.$BROWSER->options->start().'..'.$BROWSER->options->stop();
  my $type   = join '+',map{uri_escape($_)} grep {$BROWSER->options->{features}{$_}{visible}} $BROWSER->options->tracks();
  my $img_url = "$url?name=$name;type=$type;width=$width";
  print $BROWSER->translate('IMAGE_DESCRIPTION',$img_url,$img_url);
}

sub build_svg_image_page($) {
  my $segment  = shift;
  my $source = $BROWSER->config->source;
  my $url = url(-base=>1);
  $url   .= url(-absolute=>1);
  $url    = dirname($url) . "/gbrowse_img/".uri_escape($source);
  my $width  = $BROWSER->config->width;
  my $name   = $BROWSER->options->name() || $BROWSER->options->ref().':'.$BROWSER->options->start().'..'.$BROWSER->options->stop();
  my $type   = join '+',map{uri_escape($_)} grep {$BROWSER->options->{features}{$_}{visible}} $BROWSER->options->tracks();
  my $img_url = "$url?name=$name;type=$type;width=$width;image_class=SVG";
  print $BROWSER->translate('SVG_DESCRIPTION',$img_url,$img_url);
}


sub url2file {
  my $url = shift;
  for my $l ((map {"$url.$_"} $BROWSER->config->language->language), $url) {
    my $file = $ENV{MOD_PERL} && Apache->can('request') ? Apache->request->lookup_uri($l)->filename
                                                        : "$ENV{DOCUMENT_ROOT}/$l";
    return $file if -e $file;
  }
  return;
}


# get list of object types for help pages
sub object_classes_for_help {
  return $OBJECT_TYPES{$BROWSER->config->source} if exists $OBJECT_TYPES{$BROWSER->config->source};
  my $db = open_database();
  my @classes = eval {$db->classes};
  return $OBJECT_TYPES{$BROWSER->config->source} = undef unless @classes;
  return $OBJECT_TYPES{$BROWSER->config->source} = ul(li(\@classes));
}

# Create a link to a citation.  It will point to an external URL if the
# citation looks like a URL (starts with http: or ftp:).  It will be
# self-referential otherwise.

# The persistent problem here is that the regular features are cited on a
# feature-by-feature basis, while the uploaded/external ones are cited as
# a group.  This makes for ugly logic branches.
sub make_citation_link {
  my ($label,$self_url)   = @_;
  my ($link,$key);
  if ($label =~ /^plugin:/) {
    $key = $label || '';
    my $about = uri_escape($BROWSER->translate('About')) || '';
    my $plugin = $PLUGIN_NAME2LABEL{$label} ? ";plugin=$PLUGIN_NAME2LABEL{$label}" : '';
    $link = "?plugin_action=${about}${plugin}";
  } else {
    $key = label2key($label);
    (my $anchor  = $label) =~ tr/ /-/;
    $link = $self_url.'#'.escapeHTML($anchor);
  }
  my $overview_color = $BROWSER->config->setting('overview bgcolor') || DEFAULT_OVERVIEW_BGCOLOR;
  my @args = (-href=>$link,-target=>'citation');
  push @args,-style=>'Font-style: italic' if $label =~ /^(http|ftp|file):/;
  push @args,-style=>"background: $overview_color" if $label =~ /:overview$/;
#FIXME return a({@args},$key);
  return qq(<a href="$link" target="citation">$key</a>);
}

sub label2key {
  my $label = shift;
  my $key;
  $PRESETS ||= get_external_presets() || {};
  for my $l ($BROWSER->config->language->language) {
    $key     ||= $BROWSER->config->setting($label=>"key:$l");
  }
  $key     ||= $BROWSER->config->setting($label => 'key');
  $key     ||= $PRESETS->{$key} if defined $key;
  $key     ||= $label;
  $key     .= '*' if $label =~ /:overview$/;
  $key;
}

### PLUGINS ###################################################################################
###############################################################################################
sub initialize_plugins {
  my @path = @_;
  my %plugin_list = ();

  warn "initializing plugins..." if DEBUG_PLUGINS;
  my @plugins = shellwords($BROWSER->config->setting('plugins')||''); # || DEFAULT_PLUGINS);

 PLUGIN:
  for my $plugin (@plugins) {
    my $class = "Bio\:\:Graphics\:\:Browser\:\:Plugin\:\:$plugin";
    for my $path (@path) {
      my $plugin_with_path = "$path/$plugin.pm";
      if (eval {require $plugin_with_path}) {
	warn "plugin $plugin loaded successfully" if DEBUG_PLUGINS;
	my $obj = $class->new;
	warn "plugin name = ",$obj->name," base = $plugin" if DEBUG_PLUGINS;
	$plugin_list{$plugin} = $obj;
	next PLUGIN;
      } else {
	warn $@ if $@ and $@ !~ /^Can\'t locate/;
      }
    }
    warn $@ if !$plugin_list{$plugin} && $@ =~ /^Can\'t locate/;
  }

  return \%plugin_list;
}

sub configure_plugins {
  my ($plugins,$db,$conf,$conf_dir) = @_;

  for my $name (keys %$plugins) {
    my $p = $plugins->{$name};
    $p->database($db);
    $p->browser_config($conf);
    $p->config_path($conf_dir);
    $p->page_settings($BROWSER->options);
    $p->init();  # other initialization

    # retrieve persistent configuration
    my $config = retrieve_plugin_config($p);
    # and tell the plugin about it
    $p->configuration($config);
    $p->filter if ($p->type eq 'filter');

    # if there are any CGI parameters from the
    # plugin's configuration screen, set it here
    my @params = grep {/^$name\./} param();
    next unless @params;
    $p->reconfigure unless param('plugin_action') eq $BROWSER->translate('Cancel');
    $p->filter if ($p->type eq 'filter');

    # turn the plugin on
    my $setting_name = 'plugin:'.$p->name;
    $BROWSER->options->{features}{$setting_name}{visible} = 1;
    warn "\$BROWSER->options->{features}{$setting_name}{visible} = 1"
  }
}

sub do_plugin_header {
  my $plugin        = shift;
  my ($mime_type,$attachment)     = $PLUGINS->{$plugin}->mime_type;
  my @cookies                     = plugins2cookies({$plugin => $PLUGINS->{$plugin}});
  print_header(-cookie => \@cookies,
	       -type=>$mime_type,
	       $attachment ? (-attachment=>$attachment) : (),
	      );
}

sub do_plugin_dump {
  my $plugin   = shift;
  my $segment  = shift;
  my $p        = $PLUGINS->{$plugin} or return;
  my @additional_feature_sets;
  if ($segment && $segment->length <= $MAX_SEGMENT) {
     my $feature_files = load_external_sources($segment);
     @additional_feature_sets = values %{$feature_files};
  }
  $p->dump($segment,@additional_feature_sets);
  return 1;
}

sub do_plugin_about {
  my $plugin = shift;
  my $p = $PLUGINS->{$plugin};
  my $type  = ( split ( /::/, ref($p) ) )[-1];
  my $labels = plugin_adjust_labels($PLUGINS);
  print h1($BROWSER->translate('About_plugin',$labels->{$type}));
  print $p->description;
  print '<form>',submit($BROWSER->translate('Back_to_Browser')),hidden('plugin'),'</form>';
}

sub do_plugin_find {
  my ($plugin,$features,$search_string) = @_;

  my $p = $PLUGINS->{$plugin} or return;
  my $plugin_name = $p->name;

  my $results = $p->can('auto_find') && defined $search_string
              ? $p->auto_find($search_string) 
              : $p->find($features);
  return unless $results;  # reconfigure message
  return unless @$results;

  @$features = @$results;
  $BROWSER->options->name(defined($search_string) ? $BROWSER->translate('Plugin_search_1',$search_string,$plugin_name)
                                              : $BROWSER->translate('Plugin_search_2',$plugin_name));
  # remember the search
  write_auto($results);
  1; # return a true result to indicate that we don't need further configuration
}

sub do_plugin_configure {
  my $plugin   = shift;
  my $p = $PLUGINS->{$plugin} or return;
  my $type = $p->type;
  my @action_labels = ($BROWSER->translate('Cancel'),$BROWSER->translate('Configure_plugin'));
  push @action_labels,$BROWSER->translate('Find') if $type eq 'finder';
  push @action_labels,$BROWSER->translate('Go')   if ($type eq 'dumper' or $type eq 'filter');
  my @buttons = map {submit(-name=>'plugin_action',-value=>$_)} @action_labels;

  print h1($p->type eq 'finder' ? $BROWSER->translate('Find') : $BROWSER->translate('Configure'),$p->name);
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
                 : ( p($BROWSER->translate('Boring_plugin')),
		     b(submit($BROWSER->translate('Back_to_Browser')))
		   ),
     hidden('plugin'),
     '</form>';
}

# invoke any finder plugins that define the auto_find() method
sub do_plugin_autofind {
  my ($searchterm) = @_;
  my $segments = [];

  for my $p (keys %$PLUGINS) {
    next unless $PLUGINS->{$p}->type eq 'finder' && $PLUGINS->{$p}->can('auto_find');
    do_plugin_find($p,$segments,$searchterm);
    last if @$segments;
  }
  return @$segments;
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
    warn "plugins2cookies for $plugin\n" if DEBUG_PLUGINS;
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
  my $html = qq(<table border="0">);
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

sub main {
  ## PAGE SETTINGS #################################################
  #
  # Recover a hashref which contains page-specific settings
  # (this involves reading a cookie or possibly a database record
  # in some future implementation)
  my ($source,$old_source) = get_source();

  # Migrate from 1.56 way of specifying source to 1.57 way
  # This may cause a redirect and exit 0 at this point!
  redirect_legacy_url($source);


  ###FIXME remove instances of these vars -- just get them from the obj when you need them
  $MAX_SEGMENT     = $BROWSER->config->get_max_segment;
  $DEFAULT_SEGMENT = $BROWSER->config->get_default_segment;

  # Now adjust those settings based on submitted CGI parameters
  # With the exception that we ignore parameter changes if the source has changed.
  if (defined($old_source) && $source ne $old_source) {
    param(name => $BROWSER->config->name);  # restore old reference point
  } else {
    #FIXMEadjust_settings($page_settings);        # set settings from CGI parameters
  }

  ### PLUGINS #################################################################
  my @plugin_path = "$CONF_DIR/plugins";
  unshift @plugin_path,shellwords($BROWSER->config->setting('plugin_path'))
    if $BROWSER->config->setting('plugin_path');

  $PLUGINS = initialize_plugins(@plugin_path) unless defined $PLUGINS;
  configure_plugins($PLUGINS,
                    open_database(),
                    $BROWSER->config,$CONF_DIR);
  my $plugin_type   = $PLUGINS->{param('plugin')}->type
    if param('plugin') && $PLUGINS->{param('plugin')};
  my $plugin_action = param('plugin_action') || '';
  warn "plugin_action = $plugin_action" if DEBUG_PLUGINS;

  # for activating the plugin by URL
  if (param('plugin_do')) {
    $plugin_action = $BROWSER->translate(param('plugin_do')) || $BROWSER->translate('Go');
  }

  ## GETTING THE SEGMENT ######################################################
  my $features = get_features();

  if ($plugin_action eq $BROWSER->translate('Find') && param('plugin')) {
    do_plugin_find(
                   param('plugin'),
                   $features) or ($plugin_action = 'Configure'); #reconfigure
  }

  elsif (!@$features && $BROWSER->options->{name}) {
    @$features = do_keyword_search($BROWSER->options->{name});
    @$features = do_plugin_autofind($BROWSER->options->{name})
      if !@$features;  # last resort
  }

  my $segments = features2segments($features);
  my @segments = @$segments;

  # tell the plugins which segments are in play
  for my $k ( keys %$PLUGINS ) {
    $PLUGINS->{$k}->segments( \@segments );
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
  if (@segments && $plugin_action eq $BROWSER->translate('Go') && $plugin_type eq 'dumper') {
    do_plugin_header(param('plugin'));
    do_plugin_dump(param('plugin'),$segments[0]) && exit 0
  }

  # The ImportFeatures plugin is a dumper plugin but does not require a segment.
  # it will be invoked here if no segment is defined
  elsif ($plugin_action eq $BROWSER->translate('Go') && $plugin_type eq 'dumper' &&
         $PLUGINS->{param('plugin')}->verb eq ($BROWSER->translate('Import')||'Import') ) {
    do_plugin_header(param('plugin'));
    do_plugin_dump(param('plugin'),$segments[0]) && exit 0
  }

  ###############################################################################################
  ## HANDLING FILE DOWNLOADS ######################################################################

  # This gets called if the user wants to download his annotation data
  if (my $to_download = (param($BROWSER->translate('Download_file')) ||
                         ($file_action && param($file_action) eq $BROWSER->translate('Download_file')) && $file)) {
    warn "FILE DOWNLOAD, download = $to_download" if DEBUG;
    print_header(-attachment   =>  $to_download,
                 -type         => 'application/octet-stream');
    print_uploaded_file_features($to_download);
    exit 0;
  }

  ## HANDLING FILE UPLOADS ######################################################################
  if (param('Upload') && (my $f = param('upload_annotations'))) {
    handle_upload($f);
  }

  elsif (param('new_upload')) {
    $file = new_upload();  # global
    $file_action = "modify.$file";       # global
    param(-name=>"modify.$file",-value=>$BROWSER->translate('Edit'));
  }

  elsif (defined(my $data = param('a_data'))) {
    handle_edit($data);
  }

  elsif ($data = param('auto') or $data = param('add')) {
    handle_quickie($data);
  }

  clear_uploaded_file($file) if $file_action && param($file_action) eq 'Delete File';

#  warn "TRACKS = @{$BROWSER->options->{tracks}}" if DEBUG;
  load_plugin_annotators();
  warn "ANNOTATOR TRACKS = ".$BROWSER->options->tracks() if DEBUG;
  adjust_tracks();
  auto_open($features) if @$features;

  warn "ADJUSTED TRACKS = ".$BROWSER->options->tracks() if DEBUG;

  ## UPDATING THE PERSISTENT SETTINGS ##############################################################
  my $cookies = $BROWSER->cookie();

  #FIXMEpush @$cookies,plugins2cookies($PLUGINS);

  ## STARTING THE PAGE #############################################################################
  print_header(
               -expires => '+1m',
               -cookie  => $cookies,
               -charset => $BROWSER->translate('CHARSET'),
              );
  if (request_method eq 'HEAD') {exit 0}

  ## HANDLE UPLOADED FILE EDITS ####################################################################
  if ($file_action && param($file_action) eq $BROWSER->translate('Edit')) {
    edit_uploaded_file($file);
  }

  ## HANDLE TRACK SETTINGS #########################################################################
  elsif ((param($BROWSER->translate('Set_options')) || param('revert'))
         && !param($BROWSER->translate('Cancel'))
         && !param($BROWSER->translate('Redisplay'))) {
    set_track_options();
  }

  ## HANDLE HELP PAGE ##############################################################################
  elsif ( $BROWSER->options->display_help() ) {
    help();
#    help(param('help'),$BROWSER->config->setting('help')||GBROWSE_HELP);
  }

  ## HANDLE PLUGIN ABOUT PAGE ######################################################################
  elsif ($plugin_action eq $BROWSER->translate('About')) {
    do_plugin_about(param('plugin'));
  }

  ## HANDLE PLUGIN CONFIGURATION ###################################################################
  elsif ($plugin_action eq $BROWSER->translate('Configure')) {
    do_plugin_configure(param('plugin'));
  }

  elsif ($plugin_action eq $BROWSER->translate('Go') && $plugin_type=~/^(finder|annotator|highlighter)$/i) {
    do_plugin_configure(param('plugin'));
  }

  ## MAIN DISPLAY ##################################################################################
  else {
    main_display($segments,$features);
  }
}

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
