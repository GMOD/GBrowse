#-*-Perl-*-

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use warnings;
use Module::Build;
use Bio::Root::IO;
use File::Path 'rmtree';
use FindBin '$Bin';
use File::Spec;

use constant TEST_COUNT => 69;
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
use lib "$Bin/../libnew";
use Bio::Graphics::Browser;

my $globals = Bio::Graphics::Browser->new(CONF_FILE);
ok($globals);

# exercise globals a bit
ok($globals->config_base,'./testdata/conf');
ok($globals->htdocs_base,'./testdata/htdocs/gbrowse');
ok($globals->url_base,'/gbrowse');

ok($globals->plugin_path,'testdata/conf/../../../conf/plugins');
ok($globals->language_path,'testdata/conf/languages');
ok($globals->templates_path,'testdata/conf/templates');
ok($globals->moby_path,'testdata/conf/MobyServices');

ok($globals->js_url,'/gbrowse/js');
ok($globals->button_url,'/gbrowse/images/buttons');
ok($globals->tmpdir_url,'/tmpimages');
ok($globals->tmpdir_path,'/tmp/gbrowse_testing/tmpimages');
ok($globals->image_url,'/gbrowse/images');
ok($globals->help_url,'/gbrowse/.');

# does setting the environment variable change things?
@ENV{qw(GBROWSE_CONF GBROWSE_DOCS GBROWSE_ROOT)} = ('/etc/gbrowse','/usr/local/gbrowse','/');
ok($globals->config_base,'/etc/gbrowse');
ok($globals->htdocs_base,'/usr/local/gbrowse');
ok($globals->url_base,'/');

ok($globals->plugin_path,'/etc/gbrowse/../../../conf/plugins');
ok($globals->language_path,'/etc/gbrowse/languages');
ok($globals->templates_path,'/etc/gbrowse/templates');
ok($globals->moby_path,'/etc/gbrowse/MobyServices');

ok($globals->js_url,'/js');
ok($globals->button_url,'/images/buttons');
ok($globals->image_url,'/images');
ok($globals->help_url,'/.');

delete $ENV{$_} foreach qw(GBROWSE_CONF GBROWSE_DOCS GBROWSE_ROOT);

# exercise tmpdir a bit
rmtree('/tmp/gbrowse_testing/images',0,0);  # in case it was left over
my ($url,$path) = $globals->tmpdir('test1/test2');
ok($url,'/tmpimages/test1/test2');
ok($path,'/tmp/gbrowse_testing/tmpimages/test1/test2');

# test the data sources
my @sources = $globals->data_sources;
ok(@sources == 2);
ok($sources[0] eq 'volvox');
ok($globals->data_source_description('volvox'),'Volvox Example Database');
ok($globals->data_source_path('yeast_chr1'),'testdata/conf/yeast_chr1.conf');
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
ok($globals->update_data_source($session));
ok($session->source eq 'volvox');

ok($globals->update_data_source($session,'yeast_chr1'),'yeast_chr1');
ok($session->source eq 'yeast_chr1');

$CGI::Q->delete('source');
$ENV{PATH_INFO}      = '/yeast_chr1';
ok($globals->update_data_source($session),'yeast_chr1');

$ENV{PATH_INFO}      = '/invalid';
ok($globals->update_data_source($session),'yeast_chr1');

ok($globals->update_data_source($session,'volvox'),'volvox');

# see whether the singleton caching system is working
ok(Bio::Graphics::Browser->new(CONF_FILE),$globals);

my $time = time;
utime($time,$time,CONF_FILE); # equivalent to "touch"
ok(Bio::Graphics::Browser->new(CONF_FILE) ne $globals);

# test data source creation
my $source = $globals->create_data_source($session->source);
ok($source);
ok($source->name eq 'volvox');
ok($source->description eq 'Volvox Example Database');

# is it cached correctly?
# we should get exactly the same object each time we call create_data_source....
ok($globals->create_data_source($session->source),$source);

# ... unless the config file has been updated more recently
$time = time();
utime($time,$time,$globals->data_source_path($session->source));
ok($globals->create_data_source($session->source) ne $source);

# Is data inherited? 
ok($source->html1,'This is inherited');
ok($source->html2,'This is overridden');

# does the timeout calculation work?
ok($source->global_time('cache time'),3600);

# Do semantic settings work?
ok($source->safe,1,'source should be safe');
ok($source->setting(general => 'plugins'),'Aligner RestrictionAnnotator ProteinDumper TestFinder');
ok($source->setting('plugins'),'Aligner RestrictionAnnotator ProteinDumper TestFinder');
ok($source->semantic_setting(Alignments=>'glyph'),'segments');
ok($source->semantic_setting(Alignments=>'glyph',30000),'box');
ok($source->type2label('alignment',0),'Alignments');

# Do callbacks work (or at least, do we get a CODE reference back)?
ok(ref($source->code_setting(EST=>'bgcolor')),'CODE');

# Test other modifiers
my @types = sort $source->overview_tracks;
ok("@types","Motifs:overview Transcripts:overview");

# Test restrictions/authorization
my %tracks = map {$_=>1} $source->labels;
ok(! exists $tracks{Variation});

$ENV{REMOTE_HOST} = 'foo.cshl.edu';
%tracks = map {$_=>1} $source->labels;
ok(! exists $tracks{Variation});

$ENV{REMOTE_USER} = 'lstein';
%tracks = map {$_=>1} $source->labels;
ok(exists $tracks{Variation});

# test that make_link should produce a fatal error
ok(!eval{$source->make_link();1});

# test that environment variable interpolation is working in dbargs
$source = $globals->create_data_source('yeast_chr1');
$ENV{GBROWSE_DOCS} = '/foo/bar';
my ($adapter,@args) = $source->db_settings;
ok($args[3]=~m!^/foo/bar!);

$ENV{GBROWSE_DOCS} = '/buzz/buzz';
($adapter,@args) = $source->db_settings;
ok($args[3]=~m!^/foo/bar!);  # old value cached

$source->clear_cache;
($adapter,@args) = $source->db_settings;
ok($args[3]=~m!^/buzz/buzz!);  # old value cached

exit 0;
