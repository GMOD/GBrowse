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

use constant TEST_COUNT => 47;
use constant CONF_FILE  => "$Bin/testdata/conf/GBrowse.conf";
use constant DEBUG => 0;

my $PID;

BEGIN {
    print STDERR "Sometimes this test gets 'stuck'. If this happens, kill the test and Build test again.\n";

  # to handle systems with no installed Test module
  # we include the t dir (where a copy of Test.pm is located)
  # as a fallback
  eval { require Test; };
  if( $@ ) {
    use lib 't';
  }
  use Test;
  plan test => TEST_COUNT;

  $PID = $$;

  rmtree "/tmp/gbrowse_testing";
  rmtree "/tmp/gbrowse";
}

$SIG{INT} = sub {exit 0};

%ENV = ();
$ENV{GBROWSE_DOCS} = $Bin;
$ENV{TMPDIR}       = '/tmp/gbrowse_testing';

chdir $Bin;
use lib "$Bin/../lib";
use Bio::Graphics::Browser2;
use Bio::Graphics::Browser2::Render::HTML;
use LWP::UserAgent;
use HTTP::Request::Common;
use Storable 'nfreeze','thaw';
use Bio::Graphics::Browser2::Render::Slave;

use lib "$Bin/testdata";
use TemplateCopy; # for the template_copy() function

# alignments requires the server at 8100
my $alignment_server = Bio::Graphics::Browser2::Render::Slave->new(LocalPort=>'dynamic');
$alignment_server->debug(DEBUG);
$alignment_server->run();

# cleavage sites track requires the server at 8101
my $cleavage_server  = Bio::Graphics::Browser2::Render::Slave->new(LocalPort=>'dynamic');
$cleavage_server->debug(DEBUG);
$cleavage_server->run();

# rewrite the template config files
for ('volvox_final.conf','yeast_chr1.conf') {
    template_copy("testdata/conf/templates/$_",
		  "testdata/conf/$_",
		  {'$REMOTE1'=>"http://localhost:".$alignment_server->listen_port,
		   '$REMOTE2'=>"http://localhost:".$cleavage_server->listen_port});
}


# Test remote rendering
my $server = Bio::Graphics::Browser2::Render::Slave->new(LocalPort=>'dynamic');
ok($server);
$server->debug(DEBUG);
my $server_pid = $server->run;
ok($server_pid);

sleep 1; # give slave renderers a chance to settle down
$ENV{REQUEST_URI}    = 'http://localhost/cgi-bin/gbrowse/volvox';
$ENV{PATH_INFO}      = '/volvox';
$ENV{REQUEST_METHOD} = 'GET';
$CGI::Q    = new CGI('name=ctgA:1..20000;label=Clones-Motifs-Transcripts;cache=1');

# this is the standard initialization, ok?
my $globals = Bio::Graphics::Browser2->new(CONF_FILE);

my $session = $globals->session;
my $source  = $globals->create_data_source('volvox');
my $render  = Bio::Graphics::Browser2::Render::HTML->new($source,$session);

$render->init_database;
$render->init_plugins;
$render->update_state;
$render->segment;  # this sets the segment

# this is what is needed to invoke the remote renderer, ok?
my @labels   = $render->detail_tracks;
my $settings = $render->state;
my $lang     = $render->language;

my $port     = $server->listen_port;

my $request  = POST("http://localhost:$port/",
		    [
		     tracks     => nfreeze(\@labels),
		     settings   => nfreeze($settings),
		     datasource => nfreeze($source),
		     data_name  => $source->name,
		     data_mtime => $source->mtime,
		     language   => nfreeze($lang),
		     panel_args => nfreeze({}),
		     operation  => 'render_tracks',
		    ]);
for (1..3) {
    my $ua        = LWP::UserAgent->new;
    my $response  = $ua->request($request);

    ok($response->is_success,1,$response->as_string);
    my $skipit = !$response->is_success;
    skip($skipit,
	 $response->header('Content-type'),
	 'application/gbrowse-encoded-genome');
    my $content  = thaw $response->content;
    skip($skipit,ref $content,'HASH');
    for (qw(Clones Motifs Transcripts)) {
	    skip($skipit,exists $content->{$_});
	    skip($skipit,exists $content->{$_}{imagedata});
	    skip($skipit,length($content->{$_}{imagedata}) > 0);
	}
}
# now we test whether parallel rendering is working
@labels = qw(CleavageSites Alignments Motifs BindingSites);

$render->set_tracks(@labels);

my $view = $render->render_detailview($render->segment);
my @images = $view =~ m!src=\"(/gbrowse/i/volvox/[a-z0-9]+\.png)\"!g;
foreach (@images) {
    s!/gbrowse/i!/tmp/gbrowse_testing/images!;
}
for my $img (@images) {
    ok (-e $img && -s _);
}

ok (scalar @images,8);

# uncomment to see the images
#warn join ' ',@images;
#sleep 5000;

exit 0;

END {
    if ($PID == $$) {
	$SIG{CHLD} = 'IGNORE'; # prevent error codes from children propagating to Test::Harness
	foreach ($server,$alignment_server,$cleavage_server) { 
	    kill TERM=>$_->pid if $_
	}
	sleep 1;
	unlink 'testdata/conf/volvox_final.conf',
     	       'testdata/conf/yeast_chr1.conf';
	rmtree "/tmp/gbrowse_testing" if $$ == $PID;
	rmtree "/tmp/gbrowse"         if $$ == $PID;
    }
}
