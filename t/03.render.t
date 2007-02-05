#-*-Perl-*-

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use warnings;
use Module::Build;
use Bio::Root::IO;
use File::Path 'rmtree';
use CGI;
use FindBin '$Bin';

use constant TEST_COUNT => 100;
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

chdir $Bin;
use lib "$Bin/../libnew";
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Render;

my $globals = Bio::Graphics::Browser->new(CONF_FILE);
ok($globals);

ok(my $session     = $globals->new_session());
ok(my $id = $session->id);
undef $session;
ok($session  = $globals->new_session($id));
ok($id,$session->id);

my $source      = $globals->create_data_source($session->source);
ok($source);

my $render      = Bio::Graphics::Browser::Render->new($source,$session);
ok($render);

# test the make_{link,title,target} functionality my $feature =
my $feature = Bio::Graphics::Feature->new(-name=>'fred',
					  -source=>'est',-method=>'match',
					  -start=>1,-end=>1000,-seq_id=>'A');
ok($render->make_link($feature),"../../gbrowse_details/volvox?name=fred;class=Sequence;ref=A;start=1;end=1000");

$ENV{REQUEST_URI} = 'http://localhost/cgi-bin/gbrowse/volvox/';
$ENV{REQUEST_METHOD} = 'GET';

ok($render->make_link($feature),"http://localhost/cgi-bin/gbrowse_details/volvox?name=fred;class=Sequence;ref=A;start=1;end=1000");

############### testing language features #############
ok(($render->language->language)[0],'posix');
ok($render->tra('IMAGE_LINK','Link to Image'));

$ENV{'HTTP_ACCEPT_LANGUAGE'} = 'fr';
$render      = Bio::Graphics::Browser::Render->new($source,$session);
ok(($render->language->language)[0],'fr');
ok($render->tra('IMAGE_LINK','Lien vers une image de cet affichage'));

############### testing initialization code #############
ok(!$render->db);
ok(my $db = $render->init_database);
ok($render->db,$db);
ok($db,$render->db); # should return same thing each time
ok(ref($db),'Bio::DB::GFF::Adaptor::memory');
ok(scalar $db->features,16);

ok($render->init_plugins);
ok(my $plugins = $render->plugins);
my @plugins = $plugins->plugins;
ok(scalar @plugins,3);

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
# (Need to undef both the session and the renderer in order to call session's destroy method)
undef $session;
undef $render;

$session = $globals->new_session($id);
ok($session->id,$id);
$render  = Bio::Graphics::Browser::Render->new($source,$session);
ok($render->state->{width},1024);

# test navigation - first we pretend that we are setting position to I:1..1000
$CGI::Q = new CGI('ref=I;start=1;end=1000');
$render->update_coordinates;
ok($render->state->{name},'I:1..1000');
ok($render->state->{ref},'I');
ok($render->state->{start},1);
ok($render->state->{stop},1000);

# lie a little bit to test things
$render->state->{seg_min} = 1;
$render->state->{seg_max} = 5000;

# now we pretend that we've pressed the right button
$CGI::Q = new CGI('right+500.x=yes');
$render->update_coordinates;
ok($render->state->{name},'I:501..1500');

# pretend we want to zoom in 50%
$CGI::Q = new CGI('zoom+in+50%.x=yes');
$render->update_coordinates;
ok($render->state->{name},'I:751..1250');

# pretend that we've selected the popup menu to go to 100 bp
$CGI::Q = new CGI('span=100');
$render->update_coordinates;
ok($render->state->{name},'I:951..1050');

# Do we clip properly? If I scroll right 5000 bp, then we should stick at 4901..5000
$CGI::Q = new CGI('right+5000+bp.x=yes');
$render->update_coordinates;
ok($render->state->{name},'I:4901..5000');


exit 0;


