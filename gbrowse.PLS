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

BEGIN{
    eval{do "config.pl"};
    eval{require "$ENV{SERVER_PATH}/.bin/fbserverenv.pl";};
}

use strict;
use lib $ENV{FLYBASE_MODULE_PATH};
use lib $ENV{GMOD_MODULE_PATH};
use Bio::Graphics;
use WebReports::Browser;
use Digest::MD5 'md5_hex';
use File::Path 'mkpath';
#use Image::Size;
use Carp;
use CGI qw(:standard escape center *table *dl *TR *td);
use CGI::Cookie;
use vars qw($CONFIG %DB $MAX_SEGMENT $DEFAULT_SEGMENT $EXTEND_LEN $MAX_BAC_PIC);
use GxAdapters::ConnectionManager qw(:all);
use BioModel::HasSeqRange qw(valid_arms);
use GxAdapters::GxAnalysis;
use GxAdapters::GxAnnotatedSeq;
use GxAdapters::GxSegment;
use DbUtils::SqlWrapper qw(:all);
use WebReports::WebSite qw(get_abs_docs_dir
			   get_abs_cache_dir get_relative_cache_dir
			   get_js_src get_annotation_database);
use WebReports::AnnotBrowser qw(draw_annotated_seq
				show_blast_hit
				add_blast_to_annseq
				get_preamble get_title get_search_menu
			       );

# if you change the zoom/nav icons, you must change this as well.
use constant MAG_ICON_HEIGHT => 20;
use constant MAG_ICON_WIDTH  => 8;
use constant MAX_SEGMENT     => 1_000_000;
use constant TOO_MANY_SEGMENTS => 5_000;
use constant DEFAULT_SEGMENT => 100_000;
use constant EXTEND_LEN => 50_000;
use constant OVERVIEW_RATIO  => 0.99;
use constant TABLE_COLS => 3; #3=feature search, scroll and zoom

require 'config.pl';

my $pre_messages;
my $scriptname = script_name();
my $NAME_LINKS = {};
my @VALID_ARMS = ();
#my $cookies = [];

###################################################################
# Non-modperl users should change this constant if needed
#
#my $CONF_DIR = '/usr/local/wormbase/conf/gbrowse.conf';
my $CONF_DIR = $ENV{CONFIG_DIR}
  || './gbrowse.conf';
#
###################################################################


BEGIN {
  if ($ENV{MOD_PERL}) {
# causes iterator breakage
# eval "use Apache::DBI";
    eval "use Apache";
    my $conf = Apache->request->dir_config('DasConfigFile');
    $CONF_DIR ||= Apache->server_root_relative($conf) if $conf;
    warn <<END if Apache::DBI->can('connect_on_init');
WARNING: APACHE::DBI DETECTED.
THIS WILL CAUSE THE GFF DUMP TO FAIL INTERMITTENTLY.
THIS SCRIPT DOES NOT BENEFIT FROM APACHE::DBI
END
;
  }
}


# preliminaries -- set up some globals
$CONFIG         = WebReports::Browser->new($CONF_DIR)
  or die "Couldn't open configuration directory: $!";

## PAGE SETTINGS ##############################################################################
#
# Recover a hashref which contains page-specific settings
# (this involves reading a cookie or possibly a database record in some future implementation
#print STDERR 'setting name before get_source', param('name'), "\n";
my ($source,$old_source) = get_source();
$CONFIG->source($source);
my $page_settings = get_settings($source);

if ($CONFIG->setting('valid_arms')) {
    push @VALID_ARMS, (split /\s+/, $CONFIG->setting('valid_arms'));
} else {
    # arm "U" is not valid arm, but some segments "attach" to it (w/o, search could fail)!!
    push @VALID_ARMS, (valid_arms(), 'U');

    my $dbh = get_handle($CONFIG->setting('database'));
    my $segms = GxAdapters::GxSegment->get_entry_points($dbh);
    push @VALID_ARMS, map { $_->name } @$segms;
}

$MAX_SEGMENT     = $CONFIG->setting('max segment')           || MAX_SEGMENT;
$DEFAULT_SEGMENT = $CONFIG->setting('default segment')       || DEFAULT_SEGMENT;
$EXTEND_LEN      = $CONFIG->setting('extend feature length') || EXTEND_LEN;
$MAX_BAC_PIC     = defined($CONFIG->setting('max bac pic')) ?
                   $CONFIG->setting('max bac pic')           : 3;
# Now adjust those settings based on submitted CGI parameters
# With the exception that we ignore parameter changes if the source has changed.
# but sometimes
# this will bring back old name field value when user just types url in browser
# and return page has no value displayed in name field in such cases
#print STDERR 'setting name before call adjust', $page_settings->{name}, "\n";
if (defined($old_source) && $source ne $old_source) {
  param(name => $page_settings->{name});  # restore old reference point
} else {
#print STDERR 'setting name before in else call adjust', $page_settings->{name}, "\n";
  adjust_settings($page_settings);        # set settings from CGI parameters
}

#########################################################################################

## GETTING THE SEGMENT ###################################################################
my @segments  = (); #get_segment($page_settings);
#@segments     = merge(\@segments) if @segments > 1 && @segments < TOO_MANY_SEGMENTS;
my $T0 = time;
my ($arm, $segs_h, $annot_seq) = get_arm_and_annotseq($page_settings);


my $T1 = time;
#log query time in server error_log file
eval {
    #printf STDERR "_LOG_\t%s\t%s\t%d\t%s\t%d\t%d\n",
    $CONFIG->setting('database'),time,$T1-$T0,$arm?$arm->name:"none",$annot_seq?$annot_seq->segment->length:0,$annot_seq?scalar(@{$annot_seq->analysis_list || []}):0;
};
##########################################################################################

## DUMPS #################################################################################
if ( (my $dump = param('dump'))) {
    if ($annot_seq) {
        if ($dump eq 'FASTA') {
            print header(-attachment   => $annot_seq->segment->name.".fa",
                         -type         => 'text/plain');
#            print $annot_seq->segment->to_fasta;
            dump_fasta($annot_seq, $page_settings);
        }
        elsif($dump eq 'GFF') {
            print header(-attachment   => $annot_seq->segment->name.".gff",
                         -type         => 'text/plain');
            $annot_seq->to_gff;
        }
        elsif ($dump eq 'XML') {
            print header(-attachment   => $annot_seq->segment->name.".xml",
                         -type         => 'text/plain');
            $annot_seq->to_xml;
        }
        exit 0;
    } else {
        $pre_messages .= "can only dump what is in detail view\n";
    }
}
###############################################################################################


## PRINTING THE PAGE #####################################################################
print header(-cookie => settings2cookie($page_settings));

#printf STDERR "header: %s |end header\n", header(-cookie => settings2cookie($page_settings));

my $menu = get_search_menu(); #preamble has too much
my $description = $CONFIG->setting('description');
my $segment;

my $browser_title = ($CONFIG->setting('browser title') || 'FlyBase Genome Browser');
#$browser_title .= ": ".$page_settings->{name};

my $header =   $CONFIG->setting('header');
print
  start_html(-title => $browser_title,
             -style  => {src=>$CONFIG->setting('stylesheet')},
             -script=>{language=>'JavaScript', -src=>get_js_src()},
	    ),

  $header?$header:table({-border=>0, -width=>$page_settings->{width}},
        TR(td({-align=>'center', -colspan=>2}, $menu)),
        TR(td({-align=>'center', -colspan=>2}, '')),
        TR(td({-align=>'center', -colspan=>2}, b($browser_title)))
       );

#  $menu,
#  h1(center($description));

$segment = $annot_seq ? $annot_seq->segment : $arm;

#if ($segment) {
#    print h4("Showing",commas($segment->length),"bp from",
#         $segment->name.", positions ".commas($segment->coords_origin1->[0])." to ".commas($segment->coords_origin1->[1]));
#}

print start_form(-action=>url(-relative=>1,-path_info=>1));

print "<b>$pre_messages</b>" if ($pre_messages);

print navigation_table($segment,$page_settings);

#call bac_insitu_image here as it changes $NAME_LINK
#so image_map can make right link for bac feature
my $bac_img_table = bac_insitu_image($annot_seq, $page_settings);

if ($segment) {
  my $cell = "\n".overview($arm, $segs_h,$page_settings, $annot_seq)."\n";
  if ($annot_seq && $annot_seq->segment->length < $MAX_SEGMENT) {
      $cell .= image_and_map($annot_seq,$page_settings);
  } else {
      $cell .= i(
	       "Detailed view is limited to",
           commas($MAX_SEGMENT),
	       "Click in the overview to select a region",commas($DEFAULT_SEGMENT),'bp wide.');
  }
  print table({-border=>0,-width=>$page_settings->{width}},
              TR({-class=>'searchbody'},
                 td($cell)
                )
             );
}

print settings_table($page_settings);

print "\n$bac_img_table\n" if ($bac_img_table); # bac_insitu_image($annot_seq, $page_settings);

#remember some values
print "\n";
print &hidden_fields($page_settings);
print "\n";

my $diff1 = $T1-$T0;
my $diff2 = time - $T0;
print end_form(), 
  $CONFIG->setting('footer'),
#  p(i(font({-size=>'small'}, "Note: This page uses cookie to save and restore preference information. No information is shared ($diff1,$diff2)."))),
  end_html;

###############################################################################################

sub hidden_fields {
    my $settings = shift;
    my $str = "";
    $str .= hidden(-name=>'hl_gene', -value=>$settings->{hl_gene},-override=>1)
      if ($settings->{hl_gene});
    $str .= hidden(-name=>'hl_rset', -value=>$settings->{hl_rset},-override=>1)
      if ($settings->{hl_rset});
    $str .= hidden(-name=>'blastfile', -value=>$settings->{blastfile},-override=>1)
      if ($settings->{blastfile});
    $str .= hidden(-name=>'hd_seq', -value=>$settings->{hd_seq},-override=>)
      if ($settings->{hd_seq});
    return $str;
}

sub get_source {
  my $new_source = param('source');
  my $old_source = cookie($scriptname."_source") unless request_method() eq 'GET';
#request_method is 'GET' when this called at beginning and it IS default value

#  my %cookies = fetch CGI::Cookie;
#  my $p_old_source = $cookies{$scriptname."_source"};
#  $p_old_source = "all cookies value \n".join("\n",map{$_."=".$cookies{$_}}keys %cookies);

#  my $old_source = cookie($scriptname."_source") unless param('DEBUG');
  $old_source = "" if (param('DEBUG'));

  my $source   = $new_source || $old_source;
  my @sources = $CONFIG->sources();
  $source = $source || $ENV{DEFAULT_SOURCE} || $CONFIG->source || $sources[0];  # the default, whatever it is
#printf STDERR "source old: %s this: %s\n", $old_source, $source;
  return ($source,$old_source);
}

# read from cookie, if there is one
# if not, set  from defaults
sub get_settings {
  my $source   = shift;
  my %settings = cookie($scriptname."_$source");

  %settings = () if (param('DEBUG'));

  my $ok = 1;
  if (%settings) {  # if cookie is there, then validate it
#print STDERR 'setting name in get_settings', $settings{name}, "\n";

    $ok &&= defined $settings{width} && $settings{width} > 100 && $settings{width} < 5000;
    my %ok_sources = map {$_=>1} $CONFIG->sources;
    $ok &&= $ok_sources{$settings{source}};
    my %ok_labels       = map {$_=>1} $CONFIG->labels;
    my @selected_labels = split $;,$settings{labels} if defined $settings{labels};
    foreach (@selected_labels) {
      $ok &&= $ok_labels{$_};
    }
    $settings{labels} = \@selected_labels if $ok;
  }

  if (!$ok || !%settings) {
    %settings = ();
    @settings{'name','arm','start','stop'} = ('','','','');
    $settings{width}  = $CONFIG->setting('default width');
    $settings{source} = $CONFIG->source;
    $settings{labels} = [$CONFIG->default_labels];
    $settings{landmark} = $CONFIG->setting('default landmark') || 'Cyto Band';
    $settings{tier} = 'Default';
    $settings{show_bac_img} = 'Default';
  }
  #remove what should not be cookied
  $settings{hl_rset} = '';
  $settings{hl_gene} = '';
  \%settings;
}

sub settings2cookie {
  my $settings = shift;
  my %settings = %$settings;
  for my $key (keys %settings) {
    if (ref($settings{$key}) eq 'ARRAY') {
      $settings{$key} = join $;,@{$settings{$key}};
    }
  }
  my @cookies;
  my $source = $CONFIG->source;
#printf STDERR "source saved to cookie %s\n", $source;

#there is diff b/n perl5.6.0 and perl.5.6.1 (diff CGI version) to put path in cookie
#explicitly set to be consistent, otherwise, 2 settings for each version of perl (or CGI)
#and script gets confusing setting (failed miserably!)
  push @cookies,cookie(-name    => $scriptname."_$source",
		      -value   => \%settings,
                       -path => $scriptname,
		      -expires => '+7d');
  push @cookies,cookie(-name   => $scriptname."_source",
		       -value  => $source,
                       -path => $scriptname,
		       -expires => '+7d');
  return \@cookies;
}

sub adjust_settings {
  my $settings = shift;

  if (my @selected = param('label')) {
    $settings->{labels} = \@selected;
  }
  $settings->{width}  = param('width')   if param('width');
  $settings->{landmark} = param('landmark') if param('landmark');
  $settings->{tier} = param('tier') if param('tier');
  $settings->{show_bac_img} = param('show_bac_img') if param('show_bac_img');

  if (param('arm') && (request_method() eq 'GET' || grep {/zoom|nav|overview/} param()) ) {
    $settings->{arm}   = param('arm');
    $settings->{start} = int(param('start')) if param('start') =~ /^[\d-]+/;
    $settings->{stop}  = int(param('stop'))  if param('stop')  =~ /^[\d-]+/;
    zoomnav($settings);
    $settings->{name} = "$settings->{arm}:$settings->{start}..$settings->{stop}";
    param(name => $settings->{name});
  }

  $settings->{name}   = param('name')   if param('name');

  #backward compatibility
  if (param('seq')) {
      $settings->{name}  = param('seq');
      $settings->{hd_seq} = param('seq');
      param(name => $settings->{name});
      $settings->{hl_gene} = param('gene')if (param('gene')) ;
      $settings->{hl_rset} = param('rset')if (param('rset')) ;
  }
  $settings->{name} = "subj:".param('subj_seq') if (param('subj_seq'));
  unless (grep {/overview/} param()) { #prevent from remember them when clicking on overview
      $settings->{hl_gene} = param('hl_gene') if (param('hl_gene'));
      $settings->{hl_rset} = param('hl_rset') if (param('hl_rset'));
      $settings->{blastfile} = param('blastfile') if (param('blastfile'));
      $settings->{hd_seq} = param('hd_seq') if (param('hd_seq'));
  }
  #end backward compat

  $settings->{source} = param('source') if param('source');
}

# prints the zooming and navigation bar
sub navigation_table {
  my $segment = shift;
  my $settings = shift;
  my $buttonsDir    = $CONFIG->setting('buttons');
  my $table = '';

  my $text_field_size = $settings->{width} eq 1024 ? 28 : 24;
  my $search_w = int($settings->{width} / 2);
  my $show_name = $segment->name;
  $show_name =~ s/:.*//g;
  unless (grep {$_ eq $show_name} @VALID_ARMS) {
      $show_name = $show_name." on ".$segment->src_seq->name;
  }
  $table .= table({-border=>0, -width=>$settings->{width}},
		  TR({-class=>'searchbody'},
		     td({-align=>'left', -colspan=>TABLE_COLS},
			'Search using a sequence name, gene name, or other feature.',
			show_examples()
		    )),
		  TR({-class=>'searchbody'},
		     td({-align=>'left', -colspan=>TABLE_COLS},
		     'To center on a location, click the ruler.  Use the Scroll/Zoom buttons to',
		     'change magnification and position.')
		    ),
          TR({-class=>'searchbody'},
             td({-align=>'left', -colspan=>TABLE_COLS},
                $segment ? "<b>Currently showing ".commas($segment->length)." bp from ".$show_name.", positions ".commas($segment->coords_origin1->[0])." to ".commas($segment->coords_origin1->[1])."</b>" : "")
             ),
          "\n",
		  TR({-class=>'searchtitle', -align=>'left'},
		     td({-class=>'searchtitle', -width=>$search_w}, b('Feature or Region:'),
			textfield(-name=>'name', -size=>$text_field_size),
			submit(-name=>'Go')),
#		     td({-align=>'LEFT'},
#			$segment ? ('Scroll/Zoom: ',slidertable($segment,$buttonsDir)) : ''
#		       ),
             td({-align=>'center'},
                $segment?('Scroll: ', slidertable($segment, $buttonsDir)):''
               ),
             td({-align=>'center'},
                $segment?('Zoom: <b>+</b>', zoomBar($segment, $buttonsDir), "<b>-</b>"):''
               ),
		    ));
}

#have slider separate from zoom
sub slidertable {
  my ($segment,$buttonsDir) = @_;

  my @lines;
  push @lines,hidden(-name=>'start',-value=>$segment->start,-override=>1);
  push @lines,hidden(-name=>'stop',-value=>$segment->end,-override=>1);
  push @lines,hidden(-name=>'arm',-value=>$segment->src_seq ? $segment->src_seq->name : $segment->name,-override=>1);
  push @lines, (image_button(-src=>"$buttonsDir/green_l2.gif",-name=>'nav0',-border=>0,-title=>"b1"),
		image_button(-src=>"$buttonsDir/green_l1.gif",-name=>'nav1',-border=>0,-title=>"b2"),
                " ",
#		zoomBar($segment,$buttonsDir),
		image_button(-src=>"$buttonsDir/green_r1.gif",-name=>'nav2',-border=>0,-title=>"b3"),
		image_button(-src=>"$buttonsDir/green_r2.gif",-name=>'nav3',-border=>0,-title=>"b4"),
	       );

  #  print end_form;
  my $str	= join('', @lines);
  return $str;
}

sub zoomBar {
  my ($segment,$buttonsDir) = @_;

  my @letters;
  my @ranges	= get_ranges();
  my $span = $segment->length;
  my $pixels_per_range = MAG_ICON_HEIGHT/@ranges;

  for(my $i=0; $i < @ranges; $i++){
    my $altText	   = qq{show $ranges[$i] bp};
    my $titleText  = qq{show $ranges[$i] bp};
    my $color;
    if($i>0){
      $color = ($ranges[$i-1] < $span) && ($ranges[$i] >= $span) ? 'red' : 'green';
    }else{
      $color = ($ranges[$i] >= $span) ? 'red' : 'green';
    }
    my $c = $i+1;
    $letters[$i] = image_button(-src    => "$buttonsDir/$color$c.gif",
                                -name   => "zoom${i}",
                                -alt    => $altText,
                                -border => ,
#				-height => ($i+1)*$pixels_per_range,
#				-width  => MAG_ICON_WIDTH,
                                -title  => $titleText
                               );
  }

  return join('', @letters);
}


sub settings_table {
  my $settings = shift;

  my @widths = split /\s+/,$CONFIG->setting('image widths');
  my $landmarks = [$CONFIG->overview_landmarks];

  @widths = (640,800,1024) unless @widths;

  # set up the dumps line.
  my($arm,$start,$stop) = @{$settings}{qw(arm start stop)};
  my $source   = $CONFIG->source;
  my $self     = url(-relative=>1,-path_info=>1);
  my $partial_url;
  if ($settings->{name} =~ /^AE\d+$/) {
      $partial_url = sprintf "name=%s;source=%s",$settings->{name},$source;
  }
  else {
      $partial_url = "start=$start;stop=$stop;arm=$arm;source=$source";
  }
  my @dumps    = (['GFF'  ,"$self?dump=GFF;".$partial_url]);
  unshift @dumps,['XML',"$self?dump=XML;".$partial_url];
  unshift @dumps,['FASTA',"$self?dump=FASTA;".$partial_url];
  unshift @dumps,['TABLE',"basic.pl?location=$arm:$start..$stop&format=default"];

#  my @dumps    = (['GFF'  ,"$self?dump=GFF;start=$start;stop=$stop;arm=$arm;source=$source"]);
#  unshift @dumps,['XML',"$self?dump=XML;start=$start;stop=$stop;arm=$arm;source=$source"];
#  unshift @dumps,['FASTA',"$self?dump=FASTA;start=$start;stop=$stop;arm=$arm;source=$source"];
#    if $CONFIG->setting('fasta_files');

  my $ds        = join(', ', (map{a({-href=>"@$_->[1]"},"@$_->[0]")} @dumps));

  my @labels = $CONFIG->labels;
  my $selected_labels = $settings->{labels};

  my @expands = ("Default", "Collapse All", "Expand All", "Gene Labelling On");
  my @bac_img_choices = ("Default", "Off");
  #may not work as it is very recently feature in CSS
  my $bac_img_row_visible = $MAX_BAC_PIC ? "visible" : "hidden";
  my $chk_cols = $settings->{width} > 801 ? 9 : 6;
  my $sTable 	= '';
  $sTable.= table({-border=>0,-width=>$settings->{width}},
		  TR(
		     th({-class=>'searchtitle', -colspan=>3, -align=>'left'},'Display Settings:')),
		  TR( td({-class=>'searchbody'},'Dump view as: '),
		      td({-class=>'searchbody',-colspan=>2}, $ds)),
#		  TR( td({-class=>'searchbody'},'Overview Landmarks: '),
#		      td(
#			 radio_group( -name=>'landmark',
#				      -values=>$landmarks,
#				      -default=>$settings->{landmark},
#				      -override=>1
#				    )
#			)),
		  TR(	td({-class=>'searchbody', -valign=>'top'}, 'Show features: '),
			td({-class=>'searchbody',-colspan=>2},
			   checkbox_group(-name=>'label',
					  -values   => \@labels,
					  -defaults => $selected_labels,
					  -cols     => $chk_cols,
					  -override => 1,
					 ))),
		  $CONFIG->sources > 1 ?
		  (TR({-class=>'searchbody'},
		      td('Data Source:'),
		      td({-colspan=>2},
			 popup_menu(-name   => 'source',
				    -values => [$CONFIG->sources],
				    -labels => { map {$_ => $CONFIG->source_description($_)} $CONFIG->sources},
				    -default => $CONFIG->source
				   )))
		   ) : '',
		  TR( td({-class=>'searchbody'},'Data View: '),
		      td(
			 radio_group( -name=>'tier',
				      -values=>\@expands,
				      -default=>$settings->{tier},
				      -override=>1
				    )
			)),
		  TR({-visibility=>$bac_img_row_visible},
             td({-class=>'searchbody'},'in situ BAC Image: '),
             td(
			 radio_group( -name=>'show_bac_img',
				      -values=>\@bac_img_choices,
				      -default=>$settings->{show_bac_img},
				      -override=>1
				    )
			)),
		  TR( td({-class=>'searchbody'},'Image Width: '),
		      td(
			 radio_group( -name=>'width',
				      -values=>\@widths,
				      -default=>$settings->{width},
				      -override=>1
				    )
			),
		      td({-class=>'searchbody',-align=>'left'},
			 hidden('arm'),hidden('start'),hidden('stop'),
			 submit(-name=>'Change Display Settings')))
		 );
  return $sTable;
}

# computes the new values for start and stop when the user made use of the zooming bar or navigation bar
sub zoomnav {
  my $settings = shift;
  return unless $settings->{arm};
  my $start = $settings->{start};
  my $stop  = $settings->{stop};

  # get zoom parameters
  my ($zoom) = grep {/^zoom\d+/} param();
  my ($nav)  = grep {/^nav\d+/}  param();
  my $overview_x     = param('overview.x');
  my $segment_length = param('seg_length');

  my $zoomlevel = $1 if $zoom && $zoom =~ /(\d+)/;
  my $navlevel  = $1 if $nav && $nav  =~ /(\d+)/;
  my ($center, $ohalf, $nhalf, $span);

  my @ranges	= get_ranges();
  $span	        = $stop - $start + 1;

  if (defined $zoomlevel) {
    $center	    = int($span / 2) + $start;
    my $range	    = int(($ranges[$zoomlevel])/2);
    ($start, $stop) = ($center - $range , $center + $range -1);
  }

  elsif (defined $navlevel){
    if($navlevel == 0){ $start -= int($span / 2); $stop -= int($span / 2)}
    if($navlevel == 1){ $start -= int($span / 4); $stop -= int($span / 4)}
    if($navlevel == 2){ $start += int($span / 4); $stop += int($span / 4)}
    if($navlevel == 3){ $start += int($span / 2); $stop += int($span / 2)}
  }

  elsif (defined $overview_x && defined $segment_length) {
    my $overview_width = $settings->{width} * OVERVIEW_RATIO
      - $CONFIG->setting('overview pad_right');
    my $click_position = $overview_x * ($segment_length/$overview_width);
    $span = $DEFAULT_SEGMENT if $span > $MAX_SEGMENT;
    $start = int($click_position - $span/2);
    $stop  = $start + $span - 1;
  }

  $start = 1 if ($start < 1);
  $settings->{start} = $start;
  $settings->{stop}  = $stop;
}

sub get_arm_and_annotseq {
    my $settings = shift;

    my ($arm, $segs_h, $annotseq);

    #parse feature input text box value
    if (my $p_name = $settings->{name}) {
        my ($name, $class,$start,$stop);
        #eg: 2L:1234555..1235555
        if ($p_name =~ /(\w+\.\d|\w+):([\d,-]+)(?:-|\.\.)?([\d,-]+)$/) {
            $name = $1;
            $start = $2;
            $stop = $3;
            $start =~ s/,//g;   # get rid of commas
            $stop  =~ s/,//g;
            # try to remove the chr CHROMOSOME_I
            if ($name =~ /^(chromosome_?|chr)/i) {
                $name =~ s/^(chromosome_?|chr)//i;
            }
        }
        #e.g gene:CG1234
        elsif ($p_name =~ /^(\w+):(.+)$/) {
            $class = $1;
            $name  = $2;
        } else {                #other wise $name get all (e.g AE*, gene symbol)
            $name = $p_name;
        }

        #arm name only
        #    if (!($start || $stop) && grep {$_ eq $name} valid_arms()) {
        if (grep {$_ eq $p_name} @VALID_ARMS) {
            $settings->{arm} = $p_name;
            $name = '';         #don't generate annot seq for an arm!
        }
        my $constr = {};
        $constr->{name} = $name;
        $constr->{class} = $class if defined $class;
        #class =  gene, analysis homol seq name (cDNA, pinsertin, etc)
        $constr->{start} = $start - 1 if defined($start); #user: 1-based, gadfly: 0-based
        $constr->{stop} = $stop if defined($stop);

        $annotseq = get_annotated_seq($settings, $constr);

        print STDERR "annseq=$annotseq\n";

        #    # Here starts the heuristic part.  Try various abbreviations that
        #    # people tend to use for chromosomal addressing.
        #    if (!@segments && $name =~ /^([\dIVXA-F]+)$/) {
        #        my $id = $1;
        #        foreach (qw(CHROMOSOME_ Chr chr)) {
        #            my $n = "${_}${id}";
        #            my @argv = (-name  => $n);
        #            push @argv,(-class => $class) if defined $class;
        #            push @argv,(-start => $start) if defined $start;
        #            push @argv,(-stop  => $stop)  if defined $stop;
        #            @segments = defined($start) ? $db->segment(@argv) : $db->segments(@argv) unless @segments;
        #        }
        #    }
    } elsif (my $arm = $settings->{arm}) { #arm param without name para?
        my @argv = (-name  => $arm);
        push @argv,(-start => $settings->{start}) if defined $settings->{start};
        push @argv,(-stop  => $settings->{stop})  if defined $settings->{stop};
        #   @segments = $db->segment(@argv);
    }

    # set CGI name parameter to match segment.
    # this prevents any confusion over (arm,start,stop) and (name) addressing.
    if ($annotseq) {
        $settings->{arm}   = $annotseq->segment->src_seq->name;
        $settings->{start} = $annotseq->segment->start;
        $settings->{stop}  = $annotseq->segment->end;
    }
    ($arm, $segs_h) = get_arm_sf($settings);
    return ($arm, $segs_h, $annotseq);
}

sub get_arm_sf {
    my $settings = shift;

#    printf STDERR "db=%s\n", $CONFIG->setting('database');
#    printf STDERR "settings=%s\n", join("; ", map {"$_=$settings->{$_}"} keys %$settings);
    my $dbh = get_handle($CONFIG->setting('database'));
    my $armn = $settings->{arm} || $ENV{DEFAULT_OVERVIEW_ARM}
      || $CONFIG->setting('default_arm') || @VALID_ARMS[0];
    my $armh = select_hash($dbh, ['seq'], 
                           ['name = '.sql_quote($armn)], 
                           ['id', 'length']);

    if ($armh->{'length'} == 0) {
        $armn =  $ENV{DEFAULT_OVERVIEW_ARM}
          || $CONFIG->setting('default_arm') || '2L';
        $armh = select_hash($dbh, ['seq'], 
                            ['name = '.sql_quote($armn)], 
                            ['id', 'length']);
    }
    confess ("The arm ($armn) has no sequence at all as length is 0")
      if ($armh->{'length'} == 0);

    my $arm = BioModel::Segment->new
      (-start => 0,
       -end   => $armh->{'length'},
       -name  => $armn
      );

    my $segments_h = {};
    my $arm_seqid = $armh->{id} || 0;
    my $feature = $settings->{landmark};
    #only alow cyto band
    $feature = "Cyto Band";
    if (lc($feature) eq 'gb unit') {
        my $seg_h = select_hashlist($dbh,
                                    ['seq_feature sf'],
                                    ['src_seq_id = '.$arm_seqid,
                                     'type = '.sql_quote('segment')],
                                    ['sf.name', 'start', 'end']);
        foreach my $seg (@{$seg_h}) {
            my $seg = BioModel::Segment->new
              (-name  => $seg->{name},
               -start => $seg->{start},
               -end   => $seg->{end},
              );
            $seg->info($seg->name);
            push @{$segments_h->{$feature}}, $seg;
        }
    } elsif (lc($feature) eq 'cyto band') {
        my $cyto_h = select_hashlist
          ($dbh,
           ['seq_feature sf'],
           ['sf.type = '.sql_quote("cyto band"),
            'sf.src_seq_id = '.$arm_seqid],
           ['sf.name', 'sf.start', 'sf.end'] #need global start
          );
        my @cytos = ();
        foreach my $cyto (@{$cyto_h}) {
            my $segment = BioModel::Segment->new;
            my $name = $cyto->{name};
            #use biggest band (only digit as name)
            $name =~ s/^band\-//i;
            next unless ($name =~ /^\d+$/); # || $name =~ /^4\w$/);#what it is w cyto 4?
            $segment->name($name);
            $segment->info($segment->name);
            $segment->start($cyto->{start});
            $segment->end($cyto->{end});
            push @{$segments_h->{$feature}}, $segment;
        }
    } elsif (lc($feature) eq 'tiling bac') {
        my ($program, $dbname);
        $program = "clonelocator";
        $dbname = "scaffoldbacs";

        my $bac_h = select_hashlist($dbh,
                                    ['seq_feature sf',
                                     'analysis a', 'sf_analysis sfa'],
                                    ['src_seq_id ='.$arm_seqid,
                                     'a.program ='.sql_quote($program),
                                     'a.dbname ='.sql_quote($dbname),
                                     'sf.id = sfa.seq_feature_id',
                                     'a.id = sfa.analysis_id'],
                                    ['sf.name', 'sf.start', 'sf.end']);
        foreach my $bac (@{$bac_h}) {
            my $segment = BioModel::Segment->new;
            my $name = $bac->{name};
            $name =~ s/\-hit$//;
            $segment->name($name);
            $segment->info($segment->name);
            $segment->start($bac->{start});
            $segment->end($bac->{end});
            push @{$segments_h->{$feature}}, $segment;
        }
    }
    close_handle($dbh);

    unless ($settings->{name}) {
        $settings->{name} = $settings->{arm} = $armn;
        param(name => $settings->{name});
    }

    return ($arm, $segments_h);
}

sub get_annotated_seq {
  my $settings = shift;
  my $constr = shift;

  my $annseq;
  my $seqname = ""; # use to decide to get annot seq by name or by range;
  my $range;
  my ($hl_gene, $hl_rset); # use to highligh features

  #use value in settings to get which analysis
  my $config = $CONFIG->config;
  my $dbh = get_handle($CONFIG->setting('database'));
  my @selected_analyses;
  my @an_ids = ();
  my $extra;

  for my $feature (@{$settings->{labels}}) {
      if ($config->setting($feature=>'gadfly_type') eq 'analysis') {
          my $f_val = $config->setting($feature=>'feature');
          $f_val =~ s/\*/\%/g;
          push @selected_analyses,(split /\s+/, $f_val);
      }
  }
  if (@selected_analyses) {
      my $an_l =
        GxAdapters::GxAnalysis->select_objlist($dbh,
                                               {analysis_list=>\@selected_analyses});
      @an_ids = map {$_->id} @$an_l;
  }
  if ($constr->{start} || $constr->{stop}) {
      return unless (defined($constr->{start}) && defined($constr->{stop}));
      unless (grep {$_ eq $constr->{name}} @VALID_ARMS) {
          $pre_messages .= "<h2>Nothing found for \"".param('name')."\"</h2>";
          return;
      }
      #name better be arm
      $range = {};
      $range = {start => $constr->{start},
                end   => $constr->{stop},
                arm   => $constr->{name}};
      return unless ($range->{end} - $range->{start} <= $MAX_SEGMENT);
  }
  elsif ($constr->{name}) {
      return if (grep {$_ eq $constr->{name}} @VALID_ARMS);
      if (!$constr->{class}) {
          if ($constr->{name} =~ /^AE.*/) {
              $seqname = $constr->{name};
              $extra = "GB unit";
              add_label($dbh, $settings, $extra);
              if (param('rset')) {
                  my $rsets = get_rsets($dbh, $settings, param('rset'));
                  my $rset = $rsets->[0];
                  if ($rset && $rset->isa("BioModel::ResultSet")) {
                      $extra = $CONFIG->analysis2label($rset->analysis_name);
                      add_label($dbh, $settings, $extra, \@an_ids);
                  }
              }
          } else { #assume gene symbol
              $constr->{class} = 'symbol'; #manual to constr class
          }
      }
      if (defined($constr->{class})) {
          #problem: multiple hits like P insertion (X93507) and maybe blastx hits
          my $subj_seqname = $constr->{name};
          my $the_rset  = get_class_sf($dbh, $constr, $settings);
          if (!$the_rset) {
              $pre_messages .= "<h2>Nothing found for \"".param('name')."\"</h2>";
          }
          else {
              #from subject_seq, get src_seq name (e.g gb unit) and get annot on this segment
              $seqname = $the_rset->src_seq->name;
              $seqname =~ s/\.\d// if $seqname =~ /^AE/;
              if (lc($constr->{class}) eq 'gene' || lc($constr->{class}) eq 'symbol') {
                  $hl_gene = $subj_seqname;
                  $extra = "Gene";
                  add_label($dbh, $settings, $extra);
              } else {
                  $hl_rset = $settings->{hl_rset} || $subj_seqname;
              }
              #if thing attached to arm, need to narrow down using range constraint
#              print STDERR "Checking $seqname vs @VALID_ARMS\n";
              if (grep {$seqname eq $_} @VALID_ARMS) {
                  $range = {};
                  $range->{arm} = $seqname;
                  my $middle;
                  if ($the_rset->length > $MAX_SEGMENT
                      || $the_rset->length < 2 * $EXTEND_LEN) {
                      $middle = $the_rset->range_low + $the_rset->length / 2;
                      $range->{start} = $middle - $EXTEND_LEN;
                      $range->{start} = 1 if ($range->{start} < 1);
                      $range->{end} = $middle + $EXTEND_LEN;
                  } else {
                      $range->{start} = $the_rset->range_low;
                      $range->{end} = $the_rset->range_high;
                  }
                  ($range->{start}, $range->{end}) = ($range->{end}, $range->{start}) if ($range->{start} > $range->{end});
                  ($range->{start}, $range->{end}) = (int($range->{start}),
                                                      int($range->{end}));
                  $seqname=""; # get annot seq by range now
#printf STDERR "Gene: %s arm %s start %d-%d\n", $the_rset->name, $range->{arm},$range->{start},$range->{end};
              }
              if ($the_rset->isa("BioModel::ResultSet")) {
                  $extra = $CONFIG->analysis2label($the_rset->analysis_name);
                  add_label($dbh, $settings, $extra, \@an_ids);
              }
          }
      } #end if has class
  }
  else {
      return; # no annot seq
  }

@an_ids = (0) unless (@an_ids); #make sure no analysis unless analysis is specified

  #finally construct annotated seq
eval {
  if ($seqname) {
      $annseq = GxAdapters::GxAnnotatedSeq->select_obj
        ($dbh,
         {name         => $seqname,
          analysis_ids => \@an_ids},
         ["visual"]
        );
  } elsif ($range) {
      $annseq = GxAdapters::GxAnnotatedSeq->select_obj
        ($dbh,
         {range        => $range,
          analysis_ids => \@an_ids},
         ["visual"]
        );
  }
};
  if ($@) {
      printf STDERR "get annotseq encounter an error for seqn: %s constr start: %s end:%s: %s\n",$seqname, $constr->{start},$constr->{stop}, $@;
      printf STDERR "what in range: arm:%s, start:%d, end%d\n",$range->{arm},$range->{start},$range->{end};
  }
  return unless ($annseq);

  #hack release 3: display autopromote as gray instead of blue
  if ($CONFIG->source =~ /3/) {
      my $ad = GxAdapters::GxTranscript->new;
      my $gray = "lightslategray";
      my $trs = [];
      map {
          map {
              push @$trs, $_
          } @{$_->gene->transcript_list}
      }@{$annseq->annotation_list || []};
      $ad->get_properties($dbh, $trs);
      foreach my $ann (@{$annseq->annotation_list || []}) {
          my @trs = @{$ann->gene->transcript_list };
          map {
              if (defined($_->properties)) {
                  $_->highlighting($gray)
                    if (lc($_->properties->{status}) ne 'all done');
              } else {
                  $_->highlighting($gray);
              }
          } @trs;
      }
  }

  #highlighting
  $hl_gene = $settings->{hl_gene} unless ($hl_gene);
  $hl_rset = $settings->{hl_rset} unless ($hl_rset);
  if ($hl_gene) {
      my $hlighted = 0;
      foreach my $ann (@{$annseq->annotation_list || []}) {
          my @trs = @{$ann->gene->transcript_list };
          map {
              if ($ann->gene->symbol eq $hl_gene
                  || $ann->gene->name eq $hl_gene) {
                  $_->highlighting(1);
                  $hlighted = 1;
              }
          } @trs;
      }
      $settings->{hl_gene} = $hl_gene;
      $settings->{hl_gene} = "" unless ($hlighted);
  }
  elsif ($hl_rset) { #from param('rset')
      my $is_wildc = ($hl_rset =~ s/\*$//);
      $is_wildc ||= ($hl_rset =~ s/\%$//);
      my $hlighted = 0;
      foreach my $an (@{$annseq->analysis_list || []}) {
          map {
              my $rset_name = $_->name;
              $rset_name = (length($rset_name) > length($hl_rset))
                ? substr($rset_name, 0, length($hl_rset)) : $rset_name;
              my $homol_seqn = $_->homol_seq?$_->homol_seq->name:$rset_name;
              $homol_seqn = substr($homol_seqn, 0, length($hl_rset)) if ($is_wildc);
              if (lc($homol_seqn) eq lc($hl_rset)) {
                  $_->highlighting(1);
                  $hlighted = 1;
              }
          } @{$an->result_set_list || []};
      }
      $settings->{hl_rset} = $hl_rset;
      $settings->{hl_rset} = "" unless ($hlighted);
  }
#$ENV{SQL_TRACE}=1;
  foreach my $an (@{$annseq->analysis_list || []}) {
      my $label = $CONFIG->analysis2label($an->name);
      if ($CONFIG->config->setting($label=>'homol_seq_dbxref')) {
          my $seqs;
          map{push @$seqs, $_->homol_seq}@{$an->result_set_list || []};
          my $ad = GxAdapters::GxSeq->new;
          $ad->get_dbxrefs($dbh, $seqs);
      }
  }
#$ENV{SQL_TRACE}=0;

  $annseq->segment->db_adapter->get_segment($dbh, $annseq->segment) if ($annseq);
  if ($settings->{blastfile}) {
      my $blastfile = get_abs_docs_dir."/".$settings->{blastfile};
#      print STDERR "BLASTFILE:$blastfile\n";
      my $hd_seq = $settings->{hd_seq};
      my $rset = add_blast_to_annseq($annseq, $blastfile, $hd_seq);
      # need to do all these massaging to get blast results showing correctly (coords)
      # w new Gadfly API (e.g regular rsets not nec. attached to gb unit rather to v. seg)
      if ($hd_seq && $rset) {
          my $segment;
          map {
              if ($_->seq->name =~ /$hd_seq/) {
                  $segment = $_;
              }
          } @{$annseq->segment->overlapping_segment_list || []};
          $segment = $annseq->segment unless ($segment);
          if ($segment) {
              $rset->src_seq($segment->seq);
              $rset->transform_up($segment); #global coords on gbrowse!!
          }
      }
      my $in_view;
      if ($rset) {
          my ($low, $hi) = ($rset->range_low, $rset->range_high);
          my ($as_start, $as_end) = ($annseq->segment->start, $annseq->segment->end);
          $in_view = ($low >= $as_start && $low <= $as_end
                      || $hi >= $as_start && $hi <= $as_end);
      }
      if ($in_view) {
          push @{$settings->{labels}}, 'Your BLAST hit';
          $pre_messages .= "<i>Your blast results should be visible in the tier in dark red and marked *Your BLAST hit*</i><br>";
      } else {
          $settings->{blastfile} = '';
          $settings->{hd_seq} = '';
      }
  }
  return $annseq;
}
#side effect: change settings (add label) and add analysis id to $ids
sub add_label {
    my $dbh = shift;
    my $settings = shift;
    my $extra = shift;
    my $ids = shift;

    my $config = $CONFIG->config;

    # to dyn add a label so annot seq has that tier that is not selected if search warrants
    # restricted to what is in config file
    my $existed = 0;
    foreach (@{$settings->{labels}}) {
        if ($_ eq $extra) {
            $existed = 1;
            last;
        }
    }
    if (!$existed) {
        my $ans_str = $config->setting($extra=>'feature');
        $ans_str =~ s/\*/\%/g;
        my @extra_analyses = split /\s+/, $ans_str
          if ($config->setting($extra=>'gadfly_type') eq 'analysis');
        if (@extra_analyses) {
            my $an_l =
              GxAdapters::GxAnalysis->select_objlist
                  ($dbh,
                   {analysis_list=>\@extra_analyses});
            map {push @$ids, $_->id} @$an_l;
        }
        push @{$settings->{labels}}, $extra;
    }
}
sub get_rsets {
  my $dbh = shift;
  my $settings = shift;
  my $subj_seqname = shift;

  # get all the result sets by the specified subj seq (homol_seq) name
  # restrict to analysese specified in config and select the tier if necessary?
  # (only the selected for now)
  my $config = $CONFIG->config;
  my @selected_analyses;
  #      for my $feature (@{$settings->{labels}}) {
  for my $feature ($CONFIG->labels) {
      if ($config->setting($feature=>'gadfly_type') eq 'analysis') {
          my $f_val = $config->setting($feature=>'feature');
          $f_val =~ s/\:any/\:\%/i;
          $f_val =~ s/\*/\%/;
          push @selected_analyses,(split /\s+/, $f_val);
      }
  }
  my $rsets =
    GxAdapters::GxResultSet->select_objlist
        ($dbh,
         {anlist=>\@selected_analyses,
          subject_seq=>$subj_seqname},
         ["*", "result_spans", "analysis"]);

  if (!@$rsets) { #try to get it based on seq feature name (seq descripttion when ready)
      $rsets =
        GxAdapters::GxResultSet->select_objlist
            ($dbh,
             {anlist=>\@selected_analyses,
              name_search =>$subj_seqname."*"},
             ["*", "result_spans", "analysis"]);
      if (@$rsets) {
          $settings->{hl_rset} = $rsets->[0]->homol_seq->name;
      }
  }

  return $rsets;
}
sub get_class_sf {
  my $dbh = shift;
  my $constr = shift;
  my $settings = shift;
  my $class = lc($constr->{class});
  my $subj_seqname = $constr->{name};
  my ($src_seqn, $sf);
  eval {
  if ($class eq 'gene') {
      $sf = GxAdapters::GxGene->select_obj($dbh, {name=>$subj_seqname});
  }
  elsif ($class eq 'symbol') {
      $sf = GxAdapters::GxGene->select_obj($dbh, {alt_symbol=>$subj_seqname});
  }
  else { # rset homol seq name
#      # get all the result sets by the specified subj seq (homol_seq) name
#      # restrict to analysese specified in config and select the tier if necessary?
#      # (only the selected for now)
      my $config = $CONFIG->config;
      my @selected_analyses;
      my $rsets = get_rsets($dbh, $settings, $subj_seqname);
      my @rests;
      foreach my $rset (@$rsets) {
          #look for gb unit (hard code!!) or arm ($sf is NOT set!!)
          #if gb, need to transform_up
          $src_seqn = $rset->src_seq->name;
          next if (scalar(grep {$src_seqn eq $_} @VALID_ARMS));
          next unless ($src_seqn =~ /AE/);
          $src_seqn =~ s/\.\d+$//; #remove version
          unless ($sf) {
              $sf = $rset;
              if ($src_seqn =~ /AE/) {
                  my $gb = GxAdapters::GxSeqFeature->select_obj
                    ($dbh,{name=>$src_seqn});
                  $sf->transform_up($gb);
              }
          } else {
              push @rests, $rset;
          }
      }
      $sf = $rsets->[0] unless ($sf);
      if (scalar(@$rsets) > 1) {
          $pre_messages .= "Warning: Your query gets >1 hits, what is shown is one of them. Click link(s) below to see others.<br>\n";
          my @sortedrests = sort {lc($a->src_seq->name) <=> lc($b->src_seq->name)} @rests;
          my $url    = url(-relative=>1,-path_info=>1);
          my $source = $CONFIG->source;
          my @urls = map
            {
                my $name=$_->src_seq->name;
                $name =~ s/\.\d+$//;
                a({-href=>"$url?source=$source&seq=".$name."&rset=".$_->homol_seq->name, -target=>"MORE RESULTS"}, $name)
            } @sortedrests;
          $pre_messages .= join '; ',@urls;
          $pre_messages .= "<br>\n";

      }
  }
  };
  return ($sf);
}

# interesting heuristic way of fetching sequence segments based on educated guesses
sub get_segment {
  my $settings = shift;
  my @segments;

  my $db = open_database();
  $db->debug(0);

  if (my $name = $settings->{name}) {
    my ($class,$start,$stop);
    #eg: 2L:1234555..1235555
    if ($name =~ /(\w+):([\d,-]+)(?:-|\.\.)?([\d,-]+)$/) {
      $name = $1;
      $start = $2;
      $stop = $3;
      $start =~ s/,//g; # get rid of commas
      $stop  =~ s/,//g;
    }
    #e.g gene:CG1234
    elsif ($name =~ /^(\w+):(.+)$/) {
      $class = $1;
      $name  = $2;
    }

    my @argv = (-name  => $name);
    push @argv,(-class => $class) if defined $class;
    push @argv,(-start => $start) if defined $start;
    push @argv,(-stop  => $stop)  if defined $stop;
    @segments = defined($start) ? $db->segment(@argv) : $db->segments(@argv);

    # Here starts the heuristic part.  Try various abbreviations that
    # people tend to use for chromosomal addressing.
    if (!@segments && $name =~ /^([\dIXA-F]+)$/) {
      my $id = $1;
      foreach (qw(CHROMOSOME_ Chr chr)) {
	my $n = "${_}${id}";
	my @argv = (-name  => $n);
	push @argv,(-class => $class) if defined $class;
	push @argv,(-start => $start) if defined $start;
	push @argv,(-stop  => $stop)  if defined $stop;
	@segments = defined($start) ? $db->segment(@argv) : $db->segments(@argv) unless @segments;
      }
    }

    # try to remove the chr CHROMOSOME_I
    if (!@segments && $name =~ /^(chromosome_?|chr)/i) {
      (my $chr = $name) =~ s/^(chromosome_?|chr)//i;
      @segments = $db->segment($chr);
    }

    # try any "automatic" classes that have been defined in the config file
    if (!@segments && !$class && 
	(my @automatic = split /\s+/,$CONFIG->setting('automatic classes'))) {
      foreach $class (@automatic) {
	@segments = $db->segments($class => $name);
	last if @segments;
      }
    }
  }

  elsif (my $ref = $settings->{ref}) {
    my @argv = (-name  => $ref);
    push @argv,(-start => $settings->{start}) if defined $settings->{start};
    push @argv,(-stop  => $settings->{stop})  if defined $settings->{stop};
    @segments = $db->segment(@argv);
  }

  return unless @segments;
  return @segments if @segments > 1;

  return unless @segments;
  $segments[0]->absolute(1);

  # set CGI name parameter to match segment.
  # this prevents any confusion over (ref,start,stop) and (name) addressing.
  $settings->{ref}   = $segments[0]->ref;
  $settings->{start} = $segments[0]->start;
  $settings->{stop}  = $segments[0]->stop;

  return $segments[0];
}

#sub open_database {
#  my $source  = $CONFIG->source;
#  return $DB{$source} if $DB{$source};

#  my $dsn     = $CONFIG->setting('database') or die "No database defined in $source";
#  my $adaptor = $CONFIG->setting('adaptor') || 'dbi::mysqlopt';
#  my @argv = (-adaptor => $adaptor,
#	      -dsn     => $dsn);
#  if (my $fasta = $CONFIG->setting('fasta_files')) {
#    push @argv,(-fasta=>$fasta);
#  }
#  if (my $user = $CONFIG->setting('user')) {
#    push @argv,(-user=>$user);
#  }
#  if (my $pass = $CONFIG->setting('pass')) {
#    push @argv,(-pass=>$pass);
#  }
#  if (my @aggregators = split /\s+/,$CONFIG->setting('aggregators')) {
#    push @argv,(-aggregator => \@aggregators);
#  }
#  $DB{$source} = Bio::DB::GFF->new(@argv) or die "Couldn't open database: ",Bio::DB::GFF->error;
#  return $DB{$source};
#}

sub image_and_map {
  my ($annotseq,$settings) = @_;  return unless $annotseq;

  $CONFIG->width($settings->{width});

  my $option = {};
  $option->{expand} = $settings->{tier} =~ /Expand/i;
  $option->{collapse} = $settings->{tier} =~ /Collapse/i;
  $option->{labelling} = $settings->{tier} eq 'Gene Labelling On';

  my($image,$map) = $CONFIG->annot_seq_image_boxes($annotseq,$settings->{labels}, $option);
  my ($width,$height) = $image->getBounds;

  my $signature = md5_hex($annotseq,@{$settings->{labels}},$settings->{width},$CONFIG->source);
  $signature = $annotseq->segment->name.$$.".detail.".time;
  my $url       = generate_image($image,$signature);
#  print STDERR "sssssss=$signature\n";
  my $img     = img({-src=>$url,-usemap=>'#hmap',-width => $width,-height => $height,-border=>0});
  my $img_map = make_map($map, $annotseq, $settings);
  return center(join "\n",$img,$img_map);
}

sub overview {
  my ($arm, $segs_h, $settings, $annot_seq) = @_;
  return unless $arm;
  $CONFIG->width($settings->{width}*OVERVIEW_RATIO);

  my $partial = BioModel::SeqFeature->new
    (-name=>'',
     -start=>$settings->{start},
     -end=>$settings->{stop},
    );

  if (!$annot_seq) {
      $partial->start($arm->start);
      $partial->end($arm->end);
  }

  my ($image,$length) = $CONFIG->overview($arm, $segs_h, $partial) or return;
  my ($width,$height) = $image->getBounds;
  my $signature = md5_hex($segment,$width);
  $signature = $arm->name.$$.".arm.".time;
  my $url = generate_image($image,$signature);

  return center(
		table(TR(
			 td({-classs=>'searchbody',-align=>'CENTER'},
			    image_button(-name=>'overview',
					 -src=>$url,
                     #-usemap=>'#ovmap',
					 -width=>$width,
					 -height=>$height,
					 -border=>0,
					 -align=>'MIDDLE')
			   )
			)
		     ).hidden(-name=>'seg_length',-value=>$length,-override=>1)
		);
}

sub make_ov_map {

}

sub generate_image {
  my ($image,$signature) = @_;

  my $extension = $image->can('png') ? 'png' : 'gif';
  my ($uri,$path) = picture_tmpdir();
  my $url         = sprintf("%s/%s.%s",$uri,$signature,$extension);
  my $imagefile   = sprintf("%s/%s.%s",$path,$signature,$extension);
  open (F,">$imagefile") || die("Can't open image file $imagefile for writing: $!\n");
  print F $image->can('png') ? $image->png : $image->gif;
  close F;
  return $url;
}

sub picture_tmpdir {
  my $tmpuri = $CONFIG->setting('tmpimages') or die "no tmpimages option defined, can't generate a picture";
  my $tmpdir;
  if ($ENV{MOD_PERL}) {
    my $r = Apache->request;
    my $subr   = $r->lookup_uri($tmpuri);
    $tmpdir = $subr->filename;
  } else {
    $tmpdir = "$ENV{DOCUMENT_ROOT}/$tmpuri";
  }
  mkpath($tmpdir,0,0777) unless -d $tmpdir;
  return ($tmpuri,$tmpdir);
}


sub get_ranges {
  my @ranges	= split /\s+/,$CONFIG->setting('zoom levels');
  @ranges       = qw(500 1000 5000 10000 25000 100000 200000 400000) unless @ranges;
  @ranges;
}

sub make_map {
  my $boxes = shift;
  my $annot_seq = shift;
  my $settings = shift;
  my $map = qq(<map name="hmap">\n);

  # use the scale as a centering mechanism
  my $ruler; # = shift @$boxes;
  for my $box (@$boxes) {
      if ($box->[0]->name eq $annot_seq->segment->name) {
          $ruler = $box;
          last;
      }
  }

  $map .= make_centering_map($ruler, $settings);

  my $hl;
  foreach (@$boxes){
    if ($_->[0]->highlighting && $_->[0]->highlighting eq '1') {
        map {push @$hl, $_}@$_;
        last;
    }
  }
  #print out high lighted feature map first
  if ($hl) {
    my $f = shift @$hl;
    my $coords = join(",", map{int($_)}@$hl);
    $coords =~ s/^(\d+),(\d+),/$1,$2 /;
    my $alt   = make_alt($f);
    my $href  = make_href($f);
    my $target = make_target($f);
    $map .= qq(
               <AREA SHAPE="RECT" 
               COORDS="$coords" 
               HREF="$href" 
               ALT="$alt" 
               TITLE="$alt" 
               onmouseover='window.status = "$alt"; return true;' 
               onmouseexit='window.status = ""; return true;' 
               $target>\n);
  }
  foreach (@$boxes){
    my $f = shift @$_;
    if ($f->highlighting && $f->highlighting eq '1') {
        push @{$hl}, ($f, @$_);
        next;
    }
    my $coords = join(",", map{int($_)}@$_);
    $coords =~ s/^(\d+),(\d+),/$1,$2 /;
    my $alt   = make_alt($f);
    my $href  = make_href($f);
    my $target = make_target($f);
    $map .= qq(
               <AREA SHAPE="RECT" 
               COORDS="$coords" 
               HREF="$href" 
               ALT="$alt" 
               TITLE="$alt" 
               onmouseover='window.status = "$alt"; return true;' 
               onmouseexit='window.status = ""; return true;' 
               $target>\n);
  }
#  #print out high lighted feature map last
#  if ($hl) {
#    my $f = shift @$hl;#$hl->[0];
#    my $coords = join(",", map{int($_)}@$hl);
#    $coords =~ s/^(\d+),(\d+),/$1,$2 /;
#    my $alt   = make_alt($f);
#    my $href  = make_href($f);
#    my $target = make_target($f);
#    $map .= qq(
#               <AREA SHAPE="RECT" 
#               COORDS="$coords" 
#               HREF="$href" 
#               ALT="$alt" 
#               TITLE="$alt" 
#               onmouseover='window.status = "$alt"; return true;' 
#               onmouseexit='window.status = ""; return true;' 
#               $target>\n);
#  }
  $map .= "</map>\n";
  $map;
}

sub make_centering_map {
  my $ruler = shift;
  my $settings = shift;
  return if $ruler->[3]-$ruler->[1] == 0;

  my $offset = $ruler->[0]->start;
  my $scale  = $ruler->[0]->length/($ruler->[3]-$ruler->[1]);

  # divide into ten intervals
  my $portion = ($ruler->[3]-$ruler->[1])/10;
  Delete_all();
  param(arm => scalar($ruler->[0]->src_seq->name));
  param(hl_gene=>$settings->{hl_gene}) if ($settings->{hl_gene});
  param(hl_rset=>$settings->{hl_rset}) if ($settings->{hl_rset});
  param(blastfile => $settings->{blastfile}) if ($settings->{blastfile});
  param(hd_seq=>$settings->{hd_seq}) if ($settings->{hd_seq});

  my @lines;
  my $alt = "click to center";
  for my $i (0..19) {
    my $x1 = int($portion * $i);
    my $x2 = int($portion * ($i+1));
    # put the middle of the sequence range into
    # the middle of the picture
    my $middle = $offset + $scale * ($x1+$x2)/2;
    my $start  = int($middle - $ruler->[0]->length/2);
    my $stop   = int($start + $ruler->[0]->length - 1);
    param(start => int($start));
    param(stop  => int($stop));
    param(nav   => 1);
    param(source=> $CONFIG->source);
    my $url = url(-relative=>1,-query=>1,-path_info=>1);
    push @lines,
      qq(<AREA SHAPE=RECT COORDS="$x1,$ruler->[2] $x2,$ruler->[4]"
         HREF="$url" ALT="$alt" TITLE="$alt"
         onmouseover='window.status = "$alt"; return true' 
         onmouseexit='window.status = ""; return true;'>\n);
  }
  return join '',@lines;
}

sub bac_insitu_image {
  my $annot_seq = shift;
  my $settings = shift;

  my $sTable;
  return if ($settings->{show_bac_img} eq 'Off');

  if ($annot_seq && $annot_seq->segment->length < $MAX_SEGMENT) {
#      $sTable .= "<hr>\n";
      my $t_bac_analysis;
      foreach my $a (@{$annot_seq->analysis_list || []}) {
          if ($a->name eq $CONFIG->config->setting('Tiling BAC'=>'feature')) {
              $t_bac_analysis = $a;
              last;
          }
      }
      my @tiling_bacs = ();
      if ($t_bac_analysis) {
          @tiling_bacs =
            sort {$a->start <=> $b->start}
              @{$t_bac_analysis->result_set_list || []};
      }
      if (@tiling_bacs && @tiling_bacs <= $MAX_BAC_PIC) {
          my $bac_href = "tiling_bac_images";
          $NAME_LINKS->{'Tiling BAC'}=$bac_href;
          my $page_width = $page_settings->{width};
#          my $page_width = 0;
#          my %cols_width;
#          foreach my $col (@tiling_bacs) {
#              my $url = $CONFIG->setting("bac_insitu_pic")."/".$col->info.".jpeg";
#              my $width;
#              ($width, undef, my $id) = imgsize($ENV{DOCUMENT_ROOT}."/".$url);
#              $width = $width || $page_width / scalar(@tiling_bacs);
#              $page_width += $width;
#              $cols_width{$col->name} = $width;
#          }
          $sTable .= qq[<table width=$page_width>
                        <TR>
                        <TH align="LEFT" class="searchtitle">
                        <A Name=$bac_href>Tiling BAC in situ Image:</A>
                        </TH>
                        </TR>
                        </table>];

          $sTable .= "<table border=0 width=$page_width>";
          $sTable .= "<TR>";
          foreach my $col (@tiling_bacs) {
              my $bac_name = $col->homol_seq?$col->homol_seq->name:$col->name;
              $bac_name =~ s/-hit$//;
              my $url = $CONFIG->setting("bac_insitu_pic")."/".$bac_name.".jpeg";
#              my $width = $cols_width{$col->name};
              my $width = $page_width / scalar(@tiling_bacs);
              my $height = 188;
              my $img = img({-src=>$url, -height => $height,-border=>0, center=>1});
              $sTable .= "<td align='center' class='searchbody'>$img</td>";
          }
          $sTable .= "</TR>";
          $sTable .= "</TABLE>";
      }
  }
  return $sTable;
}

#as targe is optional, so full html text is return
sub make_target {
  my $feature = shift;
  my $t = $CONFIG->feature2target($feature);
  return $t ? "TARGET=$t" : '';
}

sub make_href {
  my $feature = shift;
  my $href    = $CONFIG->make_link($feature);
  if ($href =~ /self\#(.*)/) {
      my $label = $1;
      $label =~ s/\s+$//;
      if (exists $NAME_LINKS->{$label}) {
          my $self = url(-relative=>1,-path_info=>1);
          $href = $self."#".$NAME_LINKS->{$label};
      }
      $href = "#" if ($href =~ /self\#(.*)/);
  }
  return $href;
}

sub make_alt {
  my $feature = shift;
  my $label = $feature->info;
#  if ($feature->method =~ /^(similarity|alignment)$/) {
#    $label .= " ".commas($feature->target->start)."..".commas($feature->target->end);
#  } else {
#    $label .= " ".commas($feature->start)."..".commas($feature->stop);
#  }
  $label .= " ".commas($feature->start)."..".commas($feature->stop);
  $label = $CONFIG->make_alt($feature) || $feature->info;
  return $label;
}

sub dump_fasta {
  my $annseq = shift;
  my $settings = shift;

  #hack but with better description line
  if ($settings->{name} =~ /AE\d+/) {
      print $annseq->segment->to_fasta;
      return;
  }

  #segment is not one gb unit
  my $config = $CONFIG->config;
  my $dbh = get_handle($CONFIG->setting('database'));
  my $seq = 
    GxAdapters::GxSeqFeature->generate_seq($dbh, $annseq->segment);
  $annseq->seq($seq);
  $annseq->seq->residues($seq->residues);#need set residues explicitly?
  $annseq->seq->name($annseq->segment->name);
  $annseq->seq->description($annseq->segment->description);
  print $annseq->segment->to_fasta;
}

sub dump_gff {
  my $segment = shift;
  my $page_settings = shift;
  my $labels = $page_settings->{labels} or return;
  my $date = localtime;
  print "##gff-version 2\n";
  print "##date $date\n";
  print "##sequence-region ",join(' ',$segment->name,$segment->start,$segment->stop),"\n";

  my $conf = $CONFIG->config;
  my @feature_types = map {$conf->label2type($_)} @$labels;

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

sub show_examples {
  my @examples = split /\s+/,$CONFIG->setting('examples');
  return unless @examples;
  my $url    = url(-relative=>1,-path_info=>1);
  my $source = $CONFIG->source;
  my @urls = map { a({-href=>"$url?source=$source;name=".escape($_)},$_) } @examples;
  return b('Examples: ').join ', ',@urls;
}

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;
