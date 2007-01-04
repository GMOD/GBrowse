#-*-Perl-*-

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

use strict;
use warnings;
use Module::Build;
use Bio::Root::IO;
use File::Path 'rmtree';
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
}

chdir $Bin;
use lib "$Bin/../libnew";
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Render;

my $globals = Bio::Graphics::Browser->new(CONF_FILE);
ok($globals);

my $session     = $globals->session;
my $dsn         = $globals->update_data_source($session,'volvox');

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
ok($render->make_link($feature),"http://localhost/cgi-bin/gbrowse_details/volvox?name=fred;class=Sequence;ref=A;start=1;end=1000");

############### testing language features #############
ok(($render->language->language)[0],'posix');
ok($render->tra('IMAGE_LINK','Link to Image'));

$ENV{'HTTP_ACCEPT_LANGUAGE'} = 'fr';
$render      = Bio::Graphics::Browser::Render->new($source,$session);
ok(($render->language->language)[0],'fr');
ok($render->tra('IMAGE_LINK','Lien vers une image de cet affichage'));

exit 0;


