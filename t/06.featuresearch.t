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

use constant TEST_COUNT => 26;
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

chdir $Bin;
use lib "$Bin/../lib";
use Bio::Graphics::Browser2;
use Bio::Graphics::Browser2::Render::Slave;
use Bio::Graphics::Browser2::Region;
use Bio::Graphics::Browser2::RegionSearch;

use lib "$Bin/testdata";
use TemplateCopy; # for the template_copy() function

# Test remote rendering
my @servers = (Bio::Graphics::Browser2::Render::Slave->new(LocalPort=>'dynamic'), # main
	       Bio::Graphics::Browser2::Render::Slave->new(LocalPort=>'dynamic'), # volvox4 "heterodox sites"
	       Bio::Graphics::Browser2::Render::Slave->new(LocalPort=>'dynamic'), # volvox3 "cleavage sites"
    );

for ('volvox_final.conf','yeast_chr1.conf') {
    template_copy("testdata/conf/templates/$_",
		  "testdata/conf/$_",
		  {   '$MAIN'   =>"http://localhost:".$servers[0]->listen_port,
		      '$REMOTE1'=>"http://localhost:".$servers[1]->listen_port,
		      '$REMOTE2'=>"http://localhost:".$servers[2]->listen_port});
}


for my $s (@servers) {
    $s->debug(1);
    ok($s->run);
}


%ENV = ();
$ENV{GBROWSE_DOCS}   = $Bin;

# create objects we need to test region fetching
my $globals = Bio::Graphics::Browser2->new(CONF_FILE);
my $session = $globals->session;
my $source  = $globals->create_data_source('volvox');
my $state   = $session->page_settings;

# first test that the region search is working
my $region = Bio::Graphics::Browser2::Region->new(
    { source => $source,
      state  => $state,
      db     => $source->open_database(), # this will open the default database
    }
    );

my $features = $region->search_features({-search_term => 'Contig:ctgA'});
ok($features);
ok(ref $features,'ARRAY');
ok(scalar @$features,1);
ok($features->[0]->method,'chromosome');
ok($features->[0]->start,1);
ok($features->[0]->end,50000);

$features    = $region->search_features({-search_term => 'Contig:ctgA:10001..20000'});
ok($features->[0]->length,10000);

$features    = $region->search_features({-search_term => 'HOX'});
ok(scalar @$features,4);

$features    = $region->search_features({-search_term => 'Match:seg*'});
ok(scalar @$features,2);

$features    = $region->search_features({-search_term => 'My_feature:f12'});
ok(scalar @$features,1);

$region = Bio::Graphics::Browser2::Region->new(
    { source => $source,
      state  => $state,
      db     => $source->open_database('CleavageSites'),
    }
    );
$features    = $region->search_features({-search_term => 'Cleavage*'});
ok(scalar @$features,15);

$features    = $region->search_features({-search_term => 'Cleavage11'});
ok(scalar @$features,1);

$region = Bio::Graphics::Browser2::Region->new(
    { source => $source,
      state  => $state,
      db     => $source->open_database('Alignments'),
    }
    );

$features    = $region->search_features({-search_term => 'Cleavage11'});
ok(scalar @$features,0);

$features    = $region->search_features({-search_term => 'Heterodox14'});
ok(scalar @$features,1);

# now try the local multidatabase functionality
my $search = Bio::Graphics::Browser2::RegionSearch->new(
    { source => $source,
      state  => $state,
    }
    );
$search->init_databases();
$features    = $search->search_features_locally({-search_term => 'HOX'});
ok(scalar @$features,4);

$features    = $search->search_features_locally({-search_term => 'Binding_site:B07'}); # test removal of duplicate features
ok(scalar @$features,1);

$features    = $search->search_features_locally({-search_term => 'My_feature:f12'});
ok(scalar @$features,1);

$features    = $search->search_features_locally({-search_term => 'My_feature:f12',-shortcircuit=>0});
ok(scalar @$features,2);
my @dbids = sort map {$_->gbrowse_dbid} @$features;
ok("@dbids","general volvox2:database");

my @seqid = sort map {$_->seq_id} @$features;
ok("@seqid","ctgA ctgB");

$features    = $search->search_features_remotely({-search_term => 'Heterodox14'});  # this will appear in volvox4
ok(scalar @$features,1);

$features    = $search->search_features_remotely({-search_term => 'Cleavage11'});  # this will appear in volvox3
ok(scalar @$features,1);

$features    = $search->search_features_remotely({-search_term => 'Cleavage*'});  # this will appear in volvox3
ok(scalar @$features,15);

exit 0;

sub usleep {
    my $fractional_seconds = shift;
    select(undef,undef,undef,$fractional_seconds);
}

END {
    if ($PID == $$) {
	foreach (@servers) { $_->kill }
	unlink 'testdata/conf/volvox_final.conf',
     	       'testdata/conf/yeast_chr1.conf';
	rmtree('/tmp/gbrowse_testing',0,0);
    }
}

