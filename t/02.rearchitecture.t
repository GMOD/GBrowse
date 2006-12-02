#-*-Perl-*-

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use warnings;
use Module::Build;
use Bio::Root::IO;
use File::Path 'rmtree';
use FindBin '$Bin';

use constant TEST_COUNT => 7;
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
}

chdir $Bin;
use lib "../libnew";
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Render;

my $globals = Bio::Graphics::Browser->new(CONF_FILE);
ok($globals);

# exercise globals a bit
ok($globals->config_base,'./testdata/conf');
ok($globals->htdocs_base,'./testdata/htdocs/gbrowse');
ok($globals->url_base,'/gbrowse');

ok($globals->plugin_path,'./testdata/conf/plugins');
ok($globals->language_path,'./testdata/conf/languages');
ok($globals->templates_path,'./testdata/conf/templates');
ok($globals->moby_path,'./testdata/conf/MobyServices');

ok($globals->js_url,'/gbrowse/js');
ok($globals->button_url,'/gbrowse/images/buttons');
ok($globals->tmpdir_url,'/gbrowse/images');
ok($globals->tmpdir_path,'/tmp/gbrowse_testing/images');
ok($globals->image_url,'/gbrowse/images');
ok($globals->help_url,'/gbrowse/.');

# exercise tmpdir a bit
rmtree('/tmp/gbrowse_testing/images',0,0);  # in case it was left over
my ($url,$path) = $globals->tmpdir('test1/test2');
ok($url  eq '/gbrowse/images/test1/test2');
ok($path eq '/tmp/gbrowse_testing/images/test1/test2');

# test the data sources
my @sources = $globals->data_sources;
ok(@sources == 2);
ok($sources[0] eq 'volvox');
ok($globals->data_source_description('volvox'),'Volvox Example Database');
ok($globals->data_source_path('yeast_chr1'),'./testdata/conf/yeast_chr1.conf');
ok($globals->valid_source('volvox'));
ok(!$globals->valid_source('volvo'));

# try to create a session
my $session = $globals->session;

# test default data source
ok($session->source eq $globals->default_source);
ok($session->source eq 'volvox');

# change data source
$session->source('yeast_chr1');

# remember id and see if we get the same session back again
my $id = $session->id;
$session->flush;
undef $session;
$session = $globals->session($id);
ok($session->id eq $id);
ok($session->source eq 'yeast_chr1');

# try whether we can update the data source via CGI
$ENV{REQUEST_METHOD} = 'GET';
$ENV{QUERY_STRING}   = 'source=volvox';
ok($globals->update_data_source($session),'volvox');

$CGI::Q->delete('source');
$ENV{PATH_INFO}      = '/yeast_chr1';
ok($globals->update_data_source($session),'yeast_chr1');

$ENV{PATH_INFO}      = '/invalid';
ok($globals->update_data_source($session),'yeast_chr1');

ok($globals->update_data_source($session,'volvox'),'volvox');

# see whether the singleton caching system is working
ok($globals,Bio::Graphics::Browser->new(CONF_FILE));
 
my $time = time;
utime($time,$time,CONF_FILE); # equivalent to "touch"
ok($globals ne Bio::Graphics::Browser->new(CONF_FILE));

# test data source creation
my $source = $globals->create_data_source($session->source);
ok($source);
ok($source->name eq 'volvox');
ok($source->description eq 'Volvox Example Database');

exit 0;



