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

use constant TEST_COUNT => 19;
use constant CONF_FILE  => "$Bin/testdata/conf/GBrowse.conf";

my $PID;

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

  $PID = $$;

  use Bio::Graphics::FeatureFile;
  rmtree '/tmp/gbrowse_testing';
  rmtree(Bio::Graphics::FeatureFile->cachedir);
}
END {
    rmtree '/tmp/gbrowse_testing' if $$ == $PID;
}

# %ENV = ();
%ENV = ();
$ENV{GBROWSE_DOCS} = $Bin;
$ENV{TMPDIR}       = '/tmp/gbrowse_testing';


chdir $Bin;
use lib "$Bin/../lib";
use Bio::Graphics::Browser2;
use Bio::Graphics::Browser2::Render::HTML;
use LWP::UserAgent;
use HTTP::Request::Common;
use Storable 'freeze','thaw';
use Bio::Graphics::Browser2::Render::Slave;

use lib "$Bin/testdata";
use TemplateCopy; # for the template_copy() function

# Test remote rendering
# Notice that $ENV{GBROWSE_DOCS} is NOT set when we launch these servers.
# It is set at run time as part of the exchange between master and slave.
my @servers = (Bio::Graphics::Browser2::Render::Slave->new(LocalPort=>'dynamic'), # main
	       Bio::Graphics::Browser2::Render::Slave->new(LocalPort=>'dynamic'), # alignments
	       Bio::Graphics::Browser2::Render::Slave->new(LocalPort=>'dynamic'), # cleavage sites
    );

for my $s (@servers) {
    $s->debug(0);
    ok($s->run);
}

# rewrite the template config files
for ('volvox_final.conf','yeast_chr1.conf') {
    template_copy("testdata/conf/templates/$_",
		  "testdata/conf/$_",
		  {   '$MAIN'   =>"http://localhost:".$servers[0]->listen_port,
		      '$REMOTE1'=>"http://localhost:".$servers[1]->listen_port,
		      '$REMOTE2'=>"http://localhost:".$servers[2]->listen_port});
}




%ENV = ();
$ENV{GBROWSE_DOCS}   = $Bin;
$ENV{REQUEST_URI}    = 'http://localhost/cgi-bin/gbrowse/volvox';
$ENV{PATH_INFO}      = '/volvox';
$ENV{REQUEST_METHOD} = 'GET';

$CGI::Q = new CGI('name=ctgA:1..20000;label=CleavageSites-Alignments-Motifs-BindingSites-Clones');

# standard initialization incantation
my $globals = Bio::Graphics::Browser2->new(CONF_FILE);
my $session = $globals->session;
my $source  = $globals->create_data_source('volvox');
my $render  = Bio::Graphics::Browser2::Render::HTML->new($source,$session);
$render->default_state(); 
$render->init_database;
$render->init_plugins;
$render->update_state;
$render->segment;  # this sets the segment

my $requests = $render->render_deferred();

my (%cumulative_status,$probe_count);
push @{$cumulative_status{$_}},$requests->{$_}->status foreach keys %$requests;

my $time = time();

while (time()-$time < 10) {
    $probe_count++;
    my %status_counts;
    for my $label (keys %$requests) {
	my $status = $requests->{$label}->status;
	push @{$cumulative_status{$label}},$status;
	$status_counts{$requests->{$label}->status}++;
    }
    last if ($status_counts{AVAILABLE}||0) == 5;
    usleep(0.2);
}

# each track should start with either EMPTY or PENDING and end with AVAILABLE
for my $label (keys %cumulative_status) {
    ok($cumulative_status{$label}[0]  =~ /^(EMPTY|PENDING)$/);
    ok($cumulative_status{$label}[-1], 'AVAILABLE');
}

# test caching
$requests = $render->render_deferred();
my @cached = map {$requests->{$_}->status} keys %$requests;
ok("@cached",'AVAILABLE AVAILABLE AVAILABLE AVAILABLE AVAILABLE');

# test the render_deferred_track() call
my $track_name1 = 'CleavageSites';
my $key1 = $requests->{$track_name1}->key;
ok($key1);

my $view = $render->render_deferred_track(
    cache_key  => $key1,
    track_id => $track_name1,
);
my @images = $view =~ m!src=\"(/gbrowse/i/volvox/[a-z0-9]+\.png)\"!g;
ok(scalar @images,2);  # one for the main image, and one for the pad

foreach (@images) {
    s!/gbrowse/i!/tmp/gbrowse_testing/images!;
}
ok(-e $images[0] && -s _);

# does cache expire?
$requests->{$track_name1}->cache_time(-1);
ok( $requests->{$track_name1}->status, 'EXPIRED' );

$render->data_source->cache_time(-1);

ok( substr(
        $render->render_deferred_track(
            cache_key  => $key1,
            track_id   => $track_name1,
        ),
        0, 16
    ),
    "<!-- EXPIRED -->"
);

exit 0;

sub usleep {
    my $fractional_seconds = shift;
    select(undef,undef,undef,$fractional_seconds);
}

END {
    if ($PID == $$) {
	$SIG{CHLD} = 'IGNORE'; # prevent error codes from children propagating to Test::Harness
	foreach (@servers) { $_->kill }
	unlink 'testdata/conf/volvox_final.conf',
	       'testdata/conf/yeast_chr1.conf';
	rmtree('/tmp/gbrowse_testing',0,0);
    }
}

