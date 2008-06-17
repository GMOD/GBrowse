#-*-Perl-*-

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'
use lib '/home/lstein/projects/bioperl-live';
use strict;
use warnings;
use Module::Build;
use Bio::Root::IO;
use File::Path 'rmtree';
use IO::String;
use CGI;
use FindBin '$Bin';

use constant TEST_COUNT => 17;
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

  rmtree '/tmp/gbrowse_testing';
}
END {
    rmtree '/tmp/gbrowse_testing' if $$ == $PID;
}

# %ENV = ();

chdir $Bin;
use lib "$Bin/../libnew";
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Render::HTML;
use LWP::UserAgent;
use HTTP::Request::Common;
use Storable 'freeze','thaw';
use Bio::Graphics::Browser::Render::Server;


# Test remote rendering
my @servers = (Bio::Graphics::Browser::Render::Server->new(),  # main
	       Bio::Graphics::Browser::Render::Server->new(LocalPort=>8100), # alignments
	       Bio::Graphics::Browser::Render::Server->new(LocalPort=>8101), # cleavage sites
    );
for my $s (@servers) {
    $s->debug(0);
    ok($s->run);
}

$ENV{REQUEST_URI}    = 'http://localhost/cgi-bin/gbrowse/volvox';
$ENV{PATH_INFO}      = '/volvox';
$ENV{REQUEST_METHOD} = 'GET';
$CGI::Q    = new CGI('name=ctgA:1..20000;label=CleavageSites-Alignments-Motifs-BindingSites-Clones');

# standard initialization incantation
my $globals = Bio::Graphics::Browser->new(CONF_FILE);
my $session = $globals->session;
my $source  = $globals->create_data_source('volvox');
my $render  = Bio::Graphics::Browser::Render::HTML->new($source,$session);
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
	push @{$cumulative_status{$label}},$requests->{$label}->status;
	$status_counts{$requests->{$label}->status}++;
    }
    last if ($status_counts{AVAILABLE}||0) == 5;
    usleep(0.1);
}

# each track should start with either EMPTY or PENDING and end with AVAILABLE
for my $label (keys %cumulative_status) {
    ok($cumulative_status{$label}[0]  =~ /^(EMPTY|PENDING)$/);
    ok($cumulative_status{$label}[-1], 'AVAILABLE');
}

# test caching
$requests = $render->render_deferred($render->segment);
my @cached = map {$requests->{$_}->status} keys %$requests;
ok("@cached",'AVAILABLE AVAILABLE AVAILABLE AVAILABLE AVAILABLE');

# test the render_deferred_track() call
my $track_name1 = 'CleavageSites';
my $key1 = $requests->{$track_name1}->key;
ok($key1);

my $view = $render->render_deferred_track(
    cache_key  => $key1,
    track_name => $track_name1,
);
my @images = $view =~ m!src=\"(/tmpimages/volvox/img/[a-z0-9]+\.png)\"!g;
ok(scalar @images,1);

foreach (@images) {
    s!/tmpimages!/tmp/gbrowse_testing/tmpimages!;
}
ok(-e $images[0] && -s _);

# does cache expire?
$render->data_source->setting(general => 'cache time',0);
sleep 1;

$requests->{$track_name1}->cache_time(-1);
ok( $requests->{$track_name1}->status, 'EXPIRED' );

$render->data_source->setting( general => 'cache time', -1 );
ok( substr(
        $render->render_deferred_track(
            cache_key  => $key1,
            track_name => $track_name1,
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
	foreach (@servers) { $_->kill }
    }
}

