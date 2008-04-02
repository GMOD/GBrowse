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

use constant TEST_COUNT => 79;
use constant CONF_FILE  => "$Bin/testdata/conf/GBrowse.conf";

BEGIN {
  # to handle systems with no installed Test module
  # we include the t dir (where a copy of Test.pm is located)
  # as a fallback
  eval { require Test; };
  if( $@ ) {
    use lib 't';
  }
  use Test;
  plan test => TEST_COUNT;

  rmtree '/tmp/gbrowse_testing';
}
END {
  rmtree '/tmp/gbrowse_testing';
}

%ENV = ();

chdir $Bin;
use lib "$Bin/../libnew";
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Render::HTML;

my $globals = Bio::Graphics::Browser->new(CONF_FILE);
ok($globals);

ok(my $session     = $globals->session());
ok(my $id = $session->id);
undef $session;
ok($session  = $globals->session($id));
ok($id,$session->id);

my $source      = $globals->create_data_source($session->source);
ok($source);

my $render      = Bio::Graphics::Browser::Render->new($source,$session);
ok($render);

ok($render->globals,$globals);

############### testing language features #############
ok(($render->language->language)[0],'posix');
ok($render->tr('IMAGE_LINK','Link to Image'));

$ENV{'HTTP_ACCEPT_LANGUAGE'} = 'fr';
$render      = Bio::Graphics::Browser::Render->new($source,$session);
ok(($render->language->language)[0],'fr');
ok($render->tr('IMAGE_LINK','Lien vers une image de cet affichage'));

############### testing initialization code #############
ok(!$render->db);
ok(my $db = $render->init_database);
ok($render->db,$db);
ok($db,$render->db); # should return same thing each time
ok(ref($db),'Bio::DB::GFF::Adaptor::memory');
ok(scalar $db->features,37);

ok($render->init_plugins);
ok(my $plugins = $render->plugins);
my @plugins    = $plugins->plugins;
ok(scalar @plugins,4);

ok($render->init_remote_sources);
ok(!$render->uploaded_sources->files);
ok(!$render->remote_sources->sources);

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
undef $session;
undef $render;

$session = $globals->session($id);
ok($session->id,$id);
$render  = Bio::Graphics::Browser::Render->new($source,$session);
ok($render->state->{width},1024);

# test navigation - first we pretend that we are setting position to ctgA:1..1000
$CGI::Q = new CGI('ref=ctgA;start=1;end=1000');
$render->update_coordinates;
ok($render->state->{name},'ctgA:1..1000');
ok($render->state->{ref},'ctgA');
ok($render->state->{start},1);
ok($render->state->{stop},1000);

# lie a little bit to test things
$render->state->{seg_min} = 1;
$render->state->{seg_max} = 5000;

# now we pretend that we've pressed the right button
$CGI::Q = new CGI('right+500.x=yes;navigate=1');
$render->update_coordinates;
ok($render->state->{name},'ctgA:501..1500');

# pretend we want to zoom in 50%
$CGI::Q = new CGI('zoom+in+50%.x=yes;navigate=1');
$render->update_coordinates;
ok($render->state->{name},'ctgA:751..1250');

# pretend that we've selected the popup menu to go to 100 bp
$CGI::Q = new CGI('span=100;navigate=1');
$render->update_coordinates;
ok($render->state->{name},'ctgA:951..1050');

# Do we clip properly? If I scroll right 5000 bp, then we should stick at 4901..5000
$CGI::Q = new CGI('right+5000+bp.x=yes;navigate=1');
$render->update_coordinates;
ok($render->state->{name},'ctgA:4901..5000');

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
my $segment = $s->[0];
my $feature = Bio::Graphics::Feature->new(-name=>'fred',
					  -source=>'est',-method=>'match',
					  -start=>1,-end=>1000,-seq_id=>'A');

my $panel_renderer = $render->get_panel_renderer($segment);
ok($panel_renderer);
ok($panel_renderer->make_link($feature),
   "../../gbrowse_details/volvox?name=fred;class=Sequence;ref=A;start=1;end=1000");

$ENV{REQUEST_URI} = 'http://localhost/cgi-bin/gbrowse/volvox';
$ENV{PATH_INFO}   = '/volvox';
$ENV{REQUEST_METHOD} = 'GET';

ok($panel_renderer->make_link($feature),
   "http://localhost/cgi-bin/gbrowse_details/volvox?name=fred;class=Sequence;ref=A;start=1;end=1000");

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

# try fetching something that  matches more than once twice
# m02 is interesting because there are three entries, two of which are on the same
# chromosome. Using somewhat dubious logic, we keep the longest of the two.
$CGI::Q = new CGI('name=Motif:m02');
$render->update_coordinates;
$r = $render->region;
ok($s = $r->segments);
ok(scalar @$s,2,"Motif:m02 should have matched exactly twice, but didn't");

# try the * match
$CGI::Q = new CGI('name=Motif:m0*');
$render->update_coordinates;
$r = $render->region;
ok($s = $r->segments);
ok(scalar @$s,6,"Motif:m0* should have matched exactly 6 times, but didn't");

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
ok($s = $r->segments);
ok(scalar @$s,11);

# something funny with getting render settings
ok($render->setting('mag icon height') > 0);
ok($render->setting('fine zoom') ne '');

# now try the run() call, using an IO::String to collect what was printed
my $data;
my $io = IO::String->new($data);
$CGI::Q = new CGI('name=kinase;label=Clones-Transcripts-Motifs');
$ENV{'HTTP_ACCEPT_LANGUAGE'} = 'en';

# start with a fresh renderer!
$render      = Bio::Graphics::Browser::Render::HTML->new($source,$session);
$render->run($io);
ok($data =~ /Set-Cookie/);
ok($data =~ /rendering 4 features/);

# try rendering a segment
$CGI::Q = new CGI('name=ctgA:1..10000;label=Clones-Transcripts-Motifs');
$render->update_state;
$r = $render->region;
$s = $r->segments;
ok($s && @$s==1);

my @labels = $render->detail_tracks;
ok(join(' ',sort @labels),'Clones Motifs Transcripts','failed to update tracks properly');

$panel_renderer = $render->get_panel_renderer($s->[0]);
ok($panel_renderer);

my $panels         = $panel_renderer->render_panels(
    {
	labels => \@labels,
    });

exit 0;
