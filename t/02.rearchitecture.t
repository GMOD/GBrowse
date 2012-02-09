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
use FindBin '$Bin';
use IO::String;

use lib "$Bin/testdata";
use TemplateCopy; # for the template_copy() function

use constant TEST_COUNT => 90;
use constant CONF_FILE  => "$Bin/testdata/conf/GBrowse.conf";

BEGIN {
  # to handle systems with no installed Test module
  # we include the t dir (where a copy of Test.pm is located)
  # as a fallback
  eval { require Test; };
  if( $@ ) {
    use lib 't';
  }
  rmtree '/tmp/gbrowse_testing';
  use Test;
  plan test => TEST_COUNT;
}

chdir $Bin;
use lib "$Bin/../lib";
use Bio::Graphics::Browser2;

$ENV{TMPDIR}       = '/tmp/gbrowse_testing';

for ('volvox_final.conf','yeast_chr1.conf') {
    template_copy("testdata/conf/templates/$_",
		  "testdata/conf/$_",
		  {'$REMOTE1'=>"http://localhost:8100",
		   '$REMOTE2'=>"http://localhost:8101"});
}

# this avoids a race condition when checking the cache time of the config file
sleep 1;

my $globals = Bio::Graphics::Browser2->new(CONF_FILE);
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
ok($globals->tmpimage_dir,'/tmp/gbrowse_testing/images');
ok($globals->image_url,'/gbrowse/i');
ok($globals->help_url,'/gbrowse/.');

# does setting the environment variable change things?
$ENV{GBROWSE_CONF} = '/etc/gbrowse';
ok($globals->config_base,'/etc/gbrowse');

ok($globals->plugin_path,'/etc/gbrowse/../../../conf/plugins');
ok($globals->language_path,'/etc/gbrowse/languages');
ok($globals->templates_path,'/etc/gbrowse/templates');
ok($globals->moby_path,'/etc/gbrowse/MobyServices');

ok($globals->js_url,'/gbrowse/js');
ok($globals->button_url,'/gbrowse/images/buttons');
ok($globals->help_url,'/gbrowse/.');

delete $ENV{$_} foreach qw(GBROWSE_CONF GBROWSE_DOCS GBROWSE_ROOT);

$ENV{GBROWSE_DOCS} = $Bin;

# exercise tmpdir a bit
rmtree('/tmp/gbrowse_testing/images',0,0);  # in case it was left over
my $path = $globals->tmpdir('test1/test2');
ok($path,'/tmp/gbrowse_testing/test1/test2');

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
CGI->_reset_globals;
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
ok(Bio::Graphics::Browser2->new(CONF_FILE),$globals);

my $time = time;
utime($time,$time,CONF_FILE); # equivalent to "touch"
ok(Bio::Graphics::Browser2->new(CONF_FILE) ne $globals);

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
ok($source->global_time('expire cache'),7200);

# Do semantic settings work?
ok($source->safe,1,'source should be safe');
ok($source->setting(general => 'plugins'),'Aligner RestrictionAnnotator ProteinDumper TestFinder');
ok($source->setting('plugins'),'Aligner RestrictionAnnotator ProteinDumper TestFinder');
ok($source->semantic_setting(Alignments=>'glyph'),'segments');
ok($source->semantic_setting(Alignments=>'glyph',30000),'box');
ok($source->type2label('alignment',0,'Alignments'),'Alignments');

# Do callbacks work (or at least, do we get a CODE reference back)?
ok(ref($source->code_setting(EST=>'bgcolor')),'CODE');

# Test other modifiers
my @types = sort $source->overview_tracks;
ok("@types","Motifs:overview Transcripts:overview");

# Test that :database sections do not come through in labels
my %tracks = map {$_=>1} $source->labels;
ok(! exists $tracks{'volvox2:database'});

# Test that we retrieve four database labels
my @dbs   = sort $source->databases;
ok(scalar @dbs,4);
ok($dbs[0],'volvox1');


# Test that we can get db args from "volvox2"
my ($dbid,$adapter,@args) = $source->db2args('volvox2');
ok($adapter,'Bio::DB::GFF');
ok("@args[0,1]",'-adaptor memory');

# Test that we get the same args from the binding sites track
my($dbid2,$adapter2,@args2) = $source->db_settings('BindingSites');
ok($adapter,$adapter2);
ok("@args[0..3]","@args2[0..3]");

# Test that we get the same database from two tracks
my $db1 = $source->open_database('Linkage2');
my $db2 = $source->open_database('Linkage2');
my $db3 = $source->open_database('BindingSites');
ok($db1,$db2);
ok($db1,$db3);

# Test reverse mapping
ok(scalar $source->db2id($db1),'volvox2:database');
ok(join(' ',sort $source->db2id($db1)),'volvox2:database');

# Test that anonymous databases that use the same open 
# arguments get mapped onto a single database
my $db4 = $source->open_database('Linkage');
ok($db1,$db4);
ok(scalar $source->db2id($db4),'volvox2:database');
ok(join(' ',$source->db2id($db1)),'volvox2:database');

# Test restrictions/authorization
%tracks = map {$_=>1} $source->labels;
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
$ENV{GBROWSE_DOCS} = '/foo/bar';
$source = $globals->create_data_source('yeast_chr1');
(undef,$adapter,@args) = $source->db_settings;
ok($args[3]=~m!^/foo/bar!);

$ENV{GBROWSE_DOCS} = '/buzz/buzz';
(undef,$adapter,@args) = $source->db_settings;
ok($args[3]=~m!^/foo/bar!);  # old value cached

$source->clear_cache;
(undef,$adapter,@args) = $source->db_settings;
ok($args[3]=~m!^/buzz/buzz!);  # old value cached

# Test the data_source_to_label() and track_source_to_label() functions
my @labels = sort $source->track_source_to_label('foobar');
ok(scalar @labels, 0);
@labels = sort $source->track_source_to_label('modENCODE');
ok("@labels","CDS Genes ORFs");
@labels    = sort $source->track_source_to_label('marc perry','nicole washington');
ok("@labels","CDS ORFs");
@labels    = sort $source->data_source_to_label('SGD');
ok("@labels","CDS Genes ORFs");
@labels    = sort $source->data_source_to_label('flybase');
ok("@labels","CDS");

# Test whether user data can be added to the data source
@labels = $source->labels;
{
    local $source->{_user_tracks};
    $source->add_user_type('fred',{glyph=>'segments',
				   feature=>'genes',
				   color => sub { return 'blue' },
			   });
    my @new_labels = $source->labels;
    ok(@new_labels == @labels+1);
    my $setting    = $source->setting(fred=>'glyph');
    ok($setting,'segments');
    ok('blue',$source->code_setting(fred=>'color'));

    my $fh = IO::String->new(<<END);
[tester]
glyph = test
feature = test
bgcolor = orange
END
    $source->parse_user_fh($fh);
    ok($source->labels+0,@labels+2);
    ok('orange',$source->setting(tester => 'bgcolor'));
}

ok(@labels+0, $source->labels+0);
ok(undef,$source->setting(fred=>'glyph'));

exit 0;

END {
	unlink 'testdata/conf/volvox_final.conf',
     	       'testdata/conf/yeast_chr1.conf';
	rmtree('/tmp/gbrowse_testing/images',0,0);  # in case it was left over
}

