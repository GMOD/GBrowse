#!perl
use Config;
use File::Basename qw(&basename &dirname);
use FindBin '$Bin';
use Cwd;

my %OPTIONS;
if (open F,"$Bin/GGB.def") {
  while (<F>) {
    next if /^\#/;
    chomp;
    $OPTIONS{$1} = $2 if /^(\w+)\s*=\s*(.+)/;
  }
  close F;
}
$OPTIONS{CONF} ||= '/usr/local/apache/conf';

$origdir = cwd;
chdir dirname($0);
$file = basename($0, '.PL','.PLS');

open OUT,">$file" or die "Can't create $file: $!";

print "Extracting $file (with variable substitutions)\n";

my $startperl = $Config{startperl} ne '#!perl' 
  ? $Config{startperl}
  : "#!$Config{perlpath}";

print OUT <<"!GROK!THIS!";
$startperl -w

###################################################################
# Non-modperl users should change this variable if needed to point
# to the directory in which the configuration files are stored.
#
\$CONF_DIR  = '$OPTIONS{CONF}/gbrowse.conf';
#
###################################################################
\$VERSION   = $OPTIONS{VERSION};

!GROK!THIS!

# In the following, perl variables are not expanded during extraction.

print OUT <<'!NO!SUBS!';
use lib '/home/lstein/projects/Generic-Genome-Browser/lib';
use strict;
use CGI qw(:standard);
use Bio::Graphics;
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Util;
use Bio::Graphics::Browser::PadAlignment;
use Bio::Graphics::Browser::Realign qw(align_segs);

use constant IMAGEWIDTH    => 800;
use constant MAX_REGION    => 100_000;
use constant BUTTONSDIR    => '/gbrowse/images/buttons/';
use constant FINEZOOM      => '20%';

use constant DEBUG => 1;

use vars qw($CONF_DIR $DBCONF $SYNCONF $VERSION);

# initialization
$CONF_DIR  = conf_dir($CONF_DIR);    # conf_dir() is exported from Util.pm

# open_config() is exported from Util.pm
$DBCONF    = open_config($CONF_DIR);         # $DBCONF is the gbrowse database config set
$SYNCONF   = open_config($CONF_DIR,'syn');   # $SYNCONF is the synteny browser database set

my $source = set_source($SYNCONF);
print header(-cookie=>[make_cookie()]);

print start_html();
print h1($SYNCONF->setting('description'));
print end_html();


exit 0;

sub set_source {
  my $conf  = shift;
  my $new_source = param('src') || param('source');
  my $old_source = cookie('gbrowse_source') unless $new_source && request_method() eq 'GET';
  my $source = $new_source || $old_source || $conf->source;
  $conf->source($source);
  return $source;
}

sub make_cookie {
  my $cookie = cookie(-name  => 'gbrowse_syn_src',
		      -value => $SYNCONF->source);
  return $cookie;
}
!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;
