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

use constant TEST_COUNT => 24;
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
use Bio::Graphics::Browser::Render::Server;
use Bio::Graphics::Browser::Region;
use Bio::Graphics::Browser::RegionSearch;

# create objects we need to test region fetching
my $globals = Bio::Graphics::Browser->new(CONF_FILE);
my $session = $globals->session;
my $source  = $globals->create_data_source('volvox');
my $state   = $session->page_settings;

# first test that the region search is working
my $region = Bio::Graphics::Browser::Region->new(
    { source => $source,
      state  => $state,
      db     => $source->open_database(), # this will open the default database
    }
    );

my $features = $region->search_features('Contig:ctgA');
ok($features);
ok(ref $features,'ARRAY');
ok(scalar @$features,1);
ok($features->[0]->method,'chromosome');
ok($features->[0]->start,1);
ok($features->[0]->end,50000);

$features    = $region->search_features('Contig:ctgA:10001..20000');
ok($features->[0]->length,10000);

$features    = $region->search_features('HOX');
ok(scalar @$features,4);

$features    = $region->search_features('Match:seg*');
ok(scalar @$features,2);

$features    = $region->search_features('My_feature:f12');
ok(scalar @$features,1);

$region = Bio::Graphics::Browser::Region->new(
    { source => $source,
      state  => $state,
      db     => $source->open_database('CleavageSites'),
    }
    );
$features    = $region->search_features('Cleavage*');
ok(scalar @$features,15);

$features    = $region->search_features('Cleavage11');
ok(scalar @$features,1);

$region = Bio::Graphics::Browser::Region->new(
    { source => $source,
      state  => $state,
      db     => $source->open_database('Alignments'),
    }
    );

$features    = $region->search_features('Cleavage11');
ok(scalar @$features,0);

$features    = $region->search_features('Heterodox14');
ok(scalar @$features,1);


# now try the local multidatabase functionality
my $search = Bio::Graphics::Browser::RegionSearch->new(
    { source => $source,
      state  => $state,
    }
    );
$search->init_databases();
$features    = $search->search_features_locally('HOX');
ok(scalar @$features,4);

$features    = $search->search_features_locally('Binding_site:B07'); # test removal of duplicate features
ok(scalar @$features,1);

$features    = $search->search_features_locally('My_feature:f12');
ok(scalar @$features,2);

my @seqid = sort map {$_->seq_id} @$features;
ok("@seqid","ctgA ctgB");

# Test remote rendering
my @servers = (Bio::Graphics::Browser::Render::Server->new(),  # main
	       Bio::Graphics::Browser::Render::Server->new(LocalPort=>8100), # volvox4 "heterodox sites"
	       Bio::Graphics::Browser::Render::Server->new(LocalPort=>8101), # volvox3 "cleavage sites"
    );

for my $s (@servers) {
    $s->debug(1);
    ok($s->run);
}

$features    = $search->search_features_remotely('Heterodox14');  # this will appear in volvox4
ok(scalar @$features,1);

$features    = $search->search_features_remotely('Cleavage11');  # this will appear in volvox3
ok(scalar @$features,1);

$features    = $search->search_features_remotely('Cleavage*');  # this will appear in volvox3
ok(scalar @$features,15);

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

