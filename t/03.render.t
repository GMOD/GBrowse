#-*-Perl-*-

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use warnings;
use Module::Build;
use Bio::Root::IO;
use File::Path 'rmtree';
use IO::String;
use CGI;
use FindBin '$Bin';
use POSIX ":sys_wait_h";

use lib "$Bin/testdata";
use TemplateCopy; # for the template_copy() function

use constant TEST_COUNT => 150;
use constant CONF_FILE  => "$Bin/testdata/conf/GBrowse.conf";

my $PID;

BEGIN {
  # to handle systems with no installed Test module
  # we include the t dir (where a copy of Test.pm is located)
  # as a fallback
  eval { require Test; };
  use Bio::Graphics::FeatureFile;
  if( $@ ) {
    use lib 't';
  }
  use Test;
  plan test => TEST_COUNT;
  $PID = $$;
  rmtree('/tmp/gbrowse_testing');
  rmtree(Bio::Graphics::FeatureFile->cachedir);
}
END {
  rmtree '/tmp/gbrowse_testing' if $$ == $PID;
}

$SIG{SEGV} = $SIG{HUP} = $SIG{INT} = $SIG{TERM} = \&cleanup;

%ENV = ();
use lib "$Bin/../lib";

use Bio::Graphics::Browser2;
use Bio::Graphics::Browser2::Render::HTML;
use Bio::Graphics::Browser2::Render::Slave;

# Test remote rendering
# Notice that $ENV{GBROWSE_DOCS} is NOT set when we launch these servers.
# It is set at run time as part of the exchange between master and slave.
my @servers = (Bio::Graphics::Browser2::Render::Slave->new(LocalPort=>'dynamic'), # alignments
	       Bio::Graphics::Browser2::Render::Slave->new(LocalPort=>'dynamic'), # cleavage sites
    );

chdir $Bin;
$ENV{GBROWSE_DOCS} = $Bin;
$ENV{TMPDIR}       = '/tmp/gbrowse_testing';

# rewrite the template config files
for ('volvox_final.conf','yeast_chr1.conf') {
    template_copy("testdata/conf/templates/$_",
		  "testdata/conf/$_",
		  {'$REMOTE1'=>"http://localhost:".$servers[0]->listen_port,
		   '$REMOTE2'=>"http://localhost:".$servers[1]->listen_port});
}

template_copy('../conf/languages/POSIX.pm','testdata/conf/languages/POSIX.pm',{});

for my $s (@servers) {
    $s->debug(1);
    ok($s->run);
}

my $globals = Bio::Graphics::Browser2->new(CONF_FILE);
ok($globals);

ok(my $session     = $globals->session());
ok(my $id = $session->id);
$session->flush;
undef $session;
ok($session  = $globals->session($id));
ok($id,$session->id);

my $source      = $globals->create_data_source($session->source);
ok($source);

my $render      = Bio::Graphics::Browser2::Render->new($source,$session);
ok($render);

ok($render->globals,$globals);

############### testing language features #############
ok(($render->language->language)[0],'posix');
ok($render->tr('IMAGE_LINK','Link to Image'));

$ENV{'HTTP_ACCEPT_LANGUAGE'} = 'fr';
$render      = Bio::Graphics::Browser2::Render->new($source,$session);
ok(($render->language->language)[0],'fr');
ok($render->tr('IMAGE_LINK','Lien vers une image de cet affichage'));

############### testing initialization code #############
ok(!$render->db);
ok(my $db = $render->init_database);
ok($render->db,$db);
ok($db,$render->db); # should return same thing each time
ok(ref($db),'Bio::DB::GFF::Adaptor::memory');
ok(scalar $db->features,53);

ok($render->init_plugins);
ok(my $plugins = $render->plugins);
my @plugins    = $plugins->plugins;
ok(scalar @plugins,4);

############### testing update code #############
$render->default_state;
ok($render->state->{width},800);
ok($render->state->{grid},1);
$CGI::Q = new CGI('width=1024;grid=0');
$render->update_options;
ok($render->state->{width},1024);
ok($render->state->{grid},0);

# is session management working? 
# (Need to undef the renderer in order to call session's destroy method)
$session->flush;
undef $session;
undef $render;

$session = $globals->session($id);
ok($session->id,$id);
$render  = Bio::Graphics::Browser2::Render::HTML->new($source,$session);
ok($render->init_database);
ok($render->init_plugins);
ok($render->state->{width},1024);

# test navigation - first we pretend that we are setting position to ctgA:1..1000
$CGI::Q = new CGI('ref=ctgA;start=1;end=1000');
$render->update_coordinates;
ok($render->state->{name},'ctgA:1..1,000');
ok($render->state->{ref},'ctgA');
ok($render->state->{start},1);
ok($render->state->{stop},1000);

# lie a little bit to test things
$render->state->{seg_min} = 1;
$render->state->{seg_max} = 5000;

# now we pretend that we've pressed the right button
$CGI::Q = new CGI('right+500.x=yes;navigate=1');
$render->update_coordinates;
ok($render->state->{name},'ctgA:501..1,500');

# pretend we want to zoom in 50%
$CGI::Q = new CGI('zoom+in+50%.x=yes;navigate=1');
$render->update_coordinates;
ok($render->state->{name},'ctgA:751..1,250');
my $segment = $render->segment;
ok($segment->start,751);
ok($segment->end,1250);

# pretend that we've selected the popup menu to go to 100 bp
$CGI::Q = new CGI('span=100;navigate=1');
$render->update_coordinates;
ok($render->state->{name},'ctgA:951..1,050');

# Do we clip properly? If I scroll right 5000 bp, then we should stick at 4901..5000
$CGI::Q = new CGI('right+5000+bp.x=yes;navigate=1');
$render->update_coordinates;
ok($render->state->{name},'ctgA:4,901..5,000');

# Is the asynchronous rendering working
my ($render_object,$retrieve_object,$status,$mime);
$CGI::Q = new CGI('action=navigate;navigate=right+5000+bp');
($status,$mime,$render_object) = $render->asynchronous_event();
if (ok($render_object) and ok($render_object->{'track_keys'})){

  # Check the retrieve_multiple option for asynch render

  my $query_str = 'action=retrieve_multiple';
  foreach
    my $track_div_id ( keys %{ $render_object->{'track_keys'} || {} } )
  {
    ok( $render_object->{'track_keys'}{$track_div_id} );
    $query_str .= ";track_div_ids=$track_div_id;tk_$track_div_id="
      . $render_object->{'track_keys'}{$track_div_id};
  }

  check_multiple_renders($query_str)
}

# Check Add Track
$CGI::Q = new CGI('track_names=Motifs;action=add_tracks');
($status,$mime,$render_object) = $render->asynchronous_event();
if (ok($render_object) and ok($render_object->{'track_data'})){

  my $track_data = $render_object->{'track_data'};
  # Check the retrieve_multiple option for asynch render

  my $query_str = 'action=retrieve_multiple';
  foreach my $track_div_id ( keys %{ $track_data || {} } )
  {
    ok( $track_data->{$track_div_id} );
    my $track_key = $track_data->{$track_div_id}{'track_key'};
    $query_str .= ";track_div_ids=$track_div_id;tk_$track_div_id=$track_key";
  }

  check_multiple_renders($query_str)
}


# Check update sections
$CGI::Q = new CGI(
    'action=update_sections'
  . '&section_names=nonsense'
  . '&section_names=page_title'
  . '&section_names=span'
  . '&section_names=tracks_panel'
  . '&section_names=upload_tracks_panel'
);
($status,$mime,$render_object) = $render->asynchronous_event();
if (ok($render_object) and ok($render_object->{'section_html'})){
  my $section_html = $render_object->{'section_html'};
  ok( $section_html->{'nonsense'} eq 'Unknown element: nonsense');
  ok( $section_html->{'page_title'} =~ /^Volvox/);
  ok( $section_html->{'span'} =~ /selected/);
  ok( $section_html->{'tracks_panel'} =~ /Clones/);
}

# Check update sections for plugin conifig
# Nonsense plugin
$CGI::Q = new CGI(
    'action=update_sections'
  . '&section_names=plugin_configure_div'
  . '&plugin_base=blah'
);
($status,$mime,$render_object) = $render->asynchronous_event();
if (ok($render_object) and ok($render_object->{'section_html'})){
  my $section_html = $render_object->{'section_html'};
  ok( $section_html->{'plugin_configure_div'} eq "blah is not a recognized plugin");
}

# No plugin
$CGI::Q = new CGI(
    'action=update_sections'
  . '&section_names=plugin_configure_div'
);
($status,$mime,$render_object) = $render->asynchronous_event();
if (ok($render_object) and ok($render_object->{'section_html'})){
  my $section_html = $render_object->{'section_html'};
  ok( $section_html->{'plugin_configure_div'} eq "No plugin was specified.");
}

# Real plugin
$CGI::Q = new CGI(
    'action=update_sections'
  . '&section_names=plugin_configure_div'
  . '&plugin_base=RestrictionAnnotator'
);
($status,$mime,$render_object) = $render->asynchronous_event();
if (ok($render_object) and ok($render_object->{'section_html'})){
  my $section_html = $render_object->{'section_html'};
  ok( $section_html->{'plugin_configure_div'} =~/RestrictionAnnotator.enzyme/);
}

# Check setting visibility
$CGI::Q = new CGI('action=set_track_visibility;track_name=Motifs;visible=0');
($status,$mime,$render_object) = $render->asynchronous_event();
ok($status, 204);
ok($render->state()->{features}{'Motifs'}{'visible'},undef);

$CGI::Q = new CGI('action=set_track_visibility;track_name=Motifs;visible=1');
($status,$mime,$render_object) = $render->asynchronous_event();
ok($status, 204);
ok($render->state()->{features}{'Motifs'}{'visible'},1);

# Try to fetch the segment.
ok($render->init_database);
ok($render->init_plugins);
my $r = $render->region;
my $s = $r->segments;
ok($s && @$s);

my $skipit = !($s && @$s) ? "segments() failed entirely, so can't check results" : 0;
skip($skipit,scalar @$s,1);
skip($skipit,eval{$s->[0]->seq_id},'ctgA');
skip($skipit,eval{$s->[0]->start},4901);
skip($skipit,eval{$s->[0]->end},5000);

# now pretend we're fetching whole contig
$CGI::Q = new CGI('name=ctgA');
$render->update_coordinates;
ok($render->state->{name},'ctgA');
$r = $render->region;
$s = $r->segments;
ok($s && @$s);
$skipit = !($s && @$s) ? "segments() failed entirely, so can't check results" : 0;
skip($skipit,scalar @$s,1);
skip($skipit,eval{$s->[0]->seq_id},'ctgA');
skip($skipit,eval{$s->[0]->start},1);
skip($skipit,eval{$s->[0]->end},50000);

# now try to fetch a nonexistent feature
$CGI::Q = new CGI('name=foobar');
$render->update_coordinates;
ok($render->state->{name},'foobar');
$r = $render->region;
$s = $r->segments;
ok($s && !@$s);

# try fetching a feature by name
$CGI::Q = new CGI('name=My_feature:f13');
$render->update_coordinates;
ok($render->state->{name},'My_feature:f13');
$r = $render->region;
$s = $r->segments;
ok($s && @$s);
$skipit = !($s && @$s) ? "segments() failed entirely, so can't check results" : 0;
skip($skipit,scalar @$s,1);
skip($skipit,eval{$s->[0]->seq_id},'ctgA');
skip($skipit,eval{$s->[0]->start},19157);
skip($skipit,eval{$s->[0]->end},22915);

# test the make_{link,title,target} functionality
$segment = $s->[0];
my $feature = Bio::Graphics::Feature->new(-name=>'fred',
					  -source=>'est',-method=>'match',
					  -start=>1,-end=>1000,-seq_id=>'A');

my $panel_renderer = $render->get_panel_renderer($segment);
ok($panel_renderer);
ok($panel_renderer->make_link($feature),
   "../../gbrowse_details/volvox?ref=A;start=1;end=1000;name=fred;class=Sequence;db_id=general");

$ENV{REQUEST_URI} = 'http://localhost/cgi-bin/gbrowse/volvox';
$ENV{PATH_INFO}   = '/volvox/';
$ENV{REQUEST_METHOD} = 'GET';

ok($panel_renderer->make_link($feature),
   "http://localhost/cgi-bin/gbrowse_details/volvox?ref=A;start=1;end=1000;name=fred;class=Sequence;db_id=general");

# try automatic class munging
$CGI::Q = new CGI('name=f13');
$render->update_coordinates;
$r = $render->region;
ok($s = $r->segments);
$skipit = !($s && @$s) ? "segments() failed entirely, so can't check results" : 0;
skip($skipit,scalar @$s,1);
skip($skipit,eval{$s->[0]->seq_id},'ctgA');
skip($skipit,eval{$s->[0]->start},19157);
skip($skipit,eval{$s->[0]->end},22915);

# try fetching something that shouldn't match
$CGI::Q = new CGI('name=Foo:f13');
$render->update_coordinates;
$r = $render->region;
ok($s = $r->segments);
ok(@$s,0,"Searching for Foo:f13 should have returned 0 results");

# try fetching something that  matches more than once
# m02 is interesting because there are four entries, but one is a duplicate
# and should be weeded out
$CGI::Q = new CGI('name=Motif:m02');
$render->update_coordinates;
$r = $render->region;
ok($s = $r->features);
ok(scalar @$s,3,"Motif:m02 should have matched exactly three times, but didn't");

# try the * match
$CGI::Q = new CGI('name=Motif:m0*');
$render->update_coordinates;
$r = $render->region;
ok($s = $r->segments);
ok(scalar @$s,7,"Motif:m0* should have matched exactly seven times, but didn't");

# try keyword search
$CGI::Q = new CGI('name=kinase');
$render->update_coordinates;
$r = $render->region;
ok($s = $r->segments);
ok(scalar @$s,4,"'kinase' should have matched 4 times, but didn't");

# Exercise the plugin "find" interface.
# The "TestFinder" plugin treats the name as a feature type and returns all instances
$CGI::Q = new CGI('name=motif;plugin_action=Find;plugin=TestFinder');
$render->update_coordinates;
$r = $render->region;
ok(my $f = $r->features);
ok($s    = $r->segments);
ok(scalar @$f,11,"Finder plugin should have found 11 motifs, but didn't");
ok(scalar @$s,11,"Finder plugin should have found 11 unique motif segments, but didn't");

# The finder plugin creates a "My Tracks" track, which then interferes with
# other tests.
$render->delete_uploads;

# something funny with getting render settings
ok($render->setting('mag icon height') > 0);
ok($render->setting('fine zoom') ne '');

# now try the run() call, using an IO::String to collect what was printed
my $data;
my $io = IO::String->new($data);
$CGI::Q = new CGI('name=kinase;label=Clones-Transcripts-Motifs');
$ENV{'HTTP_ACCEPT_LANGUAGE'} = 'en';

# start with a fresh renderer!
$render      = Bio::Graphics::Browser2::Render::HTML->new($source,$session);

{
    local $^W = 0; # bioperl is giving uninit warnings here
    $render->run($io);
}

ok($data =~ /Set-Cookie/);
ok($data =~ /m11/ && $data =~ /m14/ && $data =~ /m12/ && $data =~ /EDEN/);

# try rendering a segment
$CGI::Q = new CGI('name=ctgA:1..20000;label=Clones-Transcripts-Motifs');
$render->update_state;

$r = $render->region;
$s = $r->segments;
ok($s && @$s==1);

my @labels = $render->detail_tracks;
ok(join(' ',sort @labels),'Clones Motifs Transcripts','failed to update tracks properly');

$panel_renderer = $render->get_panel_renderer($s->[0]);
ok($panel_renderer);

my $panels   = $panel_renderer->render_panels({labels => \@labels});
if ($$ != $PID) {
    die "FATAL: A forked child was allowed to return!!!!";
}
ok(join ' ',(sort keys %$panels),'Clones Motifs Transcripts','panels keys incorrect');
my ($png)    = grep m!/gbrowse/i/!,$panels->{Motifs} =~ /src="([^"]+\.png)"/g;
ok($png);
$png =~ s!/gbrowse/i!/tmp/gbrowse_testing/images!;
ok (-e $png);

$CGI::Q         = new CGI('name=ctgA:1..20000;label=Clones-Transcripts-Motifs-BindingSites-TransChip');
$render->update_state;
$s              = $render->region->segments;
$panel_renderer = $render->get_panel_renderer($s->[0]);
$panels         = $panel_renderer->render_panels({labels => [$render->detail_tracks]});
ok(join ' ',(sort keys %$panels),'BindingSites TransChip Clones Motifs Transcripts','panels keys incorrect');
($png)          = grep m!/gbrowse/i/!,$panels->{BindingSites} =~ /src="([^"]+\.png)"/g;
ok ($png);
$png =~ s!/gbrowse/i!/tmp/gbrowse_testing/images!;
ok (-e $png);

# test different ways of splitting labels
$CGI::Q         = new CGI('name=ctgA:1..20000;l=Clones%1EMotifs%1EBindingSites%1ETransChip');
$render->update_state;
ok(join(' ',sort $render->detail_tracks),"BindingSites Clones Motifs TransChip");

$CGI::Q         = new CGI('name=ctgA:1..20000;label=Clones-Motifs-BindingSites');
$render->update_state;
ok(join(' ',sort $render->detail_tracks),"BindingSites Clones Motifs");

### check user tracks
my $usertracks = $render->user_tracks;
ok($usertracks);
ok($usertracks =~ /(database|filesystem)/i);
ok($usertracks->{config});
ok($usertracks->{globals});

my $url = 'http://www.foo.bar/this/is/a/remotetrack';
my $escaped_url = $usertracks->escape_url($url);
ok($usertracks->path =~ m!/gbrowse_testing/userdata/volvox/[0-9a-h]{32}$!);

my $file = $usertracks->import_url($url);
my @tracks = $usertracks->tracks;
ok(@tracks,1);
ok($tracks[0], $file);
ok($usertracks->is_imported($file));
my $conf = $usertracks->track_conf($tracks[0]);
ok(-e $conf);

{
    local $^W = 0; # kill annoying warning from bioperl
    $f = Bio::Graphics::FeatureFile->new(-file=>$conf);
    my $configured_types = ($f->configured_types)[0];
    ok ($configured_types, $escaped_url);
    ok ($f->setting($escaped_url=>'remote feature'), $url);
    ok ($f->setting($escaped_url=>'category'), 'My Tracks:Remote Tracks');

    ok($usertracks->filename($file), $escaped_url);
    ok($usertracks->get_file_id($escaped_url), $file);
    ok($usertracks->title($file), $escaped_url);
    ok($usertracks->description($file, "This is a test description"));
    ok($usertracks->description($file), "This is a test description");
    ok($usertracks->file_type($file), "imported");
    ok($usertracks->created($file));
    ok($usertracks->modified($file));
    
    $usertracks->delete_file($file);
    ok(!-e $conf);
    ok($usertracks->tracks+0,0);
}

exit 0;

sub check_multiple_renders {
  my $query_str = shift;
  $CGI::Q = new CGI($query_str);
  my ($status,$mime,$retrieve_object) = $render->asynchronous_event();
  if ( ok($retrieve_object) and ok( $retrieve_object->{'track_html'} ) ) {
    foreach my $track_div_id (
      keys %{ $retrieve_object->{'track_html'} || {} } )
    {
      ok( $retrieve_object->{'track_html'}{$track_div_id} );
    }
  }
}

sub cleanup {
    return unless $PID == $$;
    foreach (@servers) { $_->kill }
    unlink 'testdata/conf/volvox_final.conf',
    'testdata/conf/yeast_chr1.conf';
}

END {
    if ($PID == $$) {
	$SIG{CHLD} = 'IGNORE'; # prevent error codes from children propagating to Test::Harness
	cleanup();
    }
}

