#!perl
use Config;
use File::Basename qw( &basename &dirname );
use FindBin '$Bin'; # $Bin is the path of the directory containing this script
use Cwd;

## Read in options from the GGB.def file in the same directory as this script
my %OPTIONS;
if( open GGBDEF,"$Bin/GGB.def" ) {
  while( <GGBDEF> ) {
    next if /^\#/;
    chomp;
    $OPTIONS{ $1 } = $2 if /^(\w+)\s*=\s*(.+)/;
  }
  close GGBDEF;
}
$OPTIONS{ 'CONF' } ||= '/usr/local/apache/conf';

$origdir = cwd;
chdir dirname( $0 );
$file = basename( $0, '.PL','.PLS' );

open OUT,">$file" or die "Can't create $file: $!";

print "Extracting $file (with variable substitutions)\n";

print OUT <<"!GROK!THIS!";
$Config{ 'startperl' }

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
# Bio::Graphics-based annotation browser
# $Id: gbrowse.PLS,v 1.74.2.4 2003-08-13 18:16:40 ccavnor Exp $

use strict;
use vars qw( $VERSION $CONF_DIR );

use Bio::Graphics::Browser qw( &configureBrowsers &retrieveBrowser );
use CGI qw( :standard );

my %defaults =
(
 # if you change the zoom/nav icons, you must change this as well.
 'mag_icon_height'      => 20,
 'mag_icon_width'       => 8,

 # hard-coded values for segment sizes
 # many of these can be overridden by configuration file entries
 'max_segment'          => 1_000_000,
 'min_seg_size'         => 50,
 'tiny_seg_size'        => 2,
 'expand_seg_size'      => 5000,
 'too_many_segments'    => 5_000,
 'too_many_features'    => 100,
 'too_many_refs'        => 100,
 'default_segment'      => 100_000,

 'overview_ratio'       => 0.9,
 'annotation_edit_rows' => 25,
 'annotation_edit_cols' => 100,
 'url_fetch_timeout'    => 5,  # five seconds max!
 'url_fetch_max_size'   => 1_000_000,  # don't accept any files larger than 1 Meg
 'keyword search max'   => 1_000,     # max number of results from keyword search
 'zoom levels'          => q(100 500 1000 5000 10000 25000 100000 200000 400000),
 'fine zoom'            => '10%',
 'help'                 => '/gbrowse', # gbrowse help dir
 #'plugins'              => 'FastaDumper RestrictionAnnotator SequenceDumper',

 'width'                => 800,
 'default_db_adaptor'   => 'Bio::DB::GFF',
 'keystyle'             => 'bottom',
 'empty_tracks'         => 'key',
 'ruler_intervals'      => 20,  # fineness of the centering map on the ruler
 'too_many_segments'    => 5_000,
 'max_segment'          => 1_000_000,
 'default_ranges'       => q(100 500 1000 5000 10000 25000 100000 200000 400000),
 'min_overview_pad'     => 25,
 'pad_overview_bottom'  => 3,
 'browser_ttl'          => '+3d' # Browsers are recycled after 3 days of disuse

);

## CONFIGURATION & INITIALIZATION ################################
# preliminaries -- read and/or refresh the configuration directory

BEGIN {
  eval "use Apache"; 
  warn <<END if Apache::DBI->can('connect_on_init');
WARNING: APACHE::DBI DETECTED.
THIS WILL CAUSE THE GFF DUMP TO FAIL INTERMITTENTLY.
THIS SCRIPT DOES NOT BENEFIT FROM APACHE::DBI
END
;
  ## Redirect STDERR to a log file.
  use CGI::Carp qw( carpout fatalsToBrowser );
  $ENV{LOG_LOCATION} ||= '/usr/local/apache/logs/gbrowse-log';
  open( LOG, ">>$ENV{LOG_LOCATION}" ) or
    die( "Unable to open $ENV{LOG_LOCATION}: $!\n");
  carpout( \*LOG );
};




## Build a Browser object and load the config directory's config files.
# first set $CONF_DIR
if( $ENV{ 'MOD_PERL' } ) {
  my $conf  = Apache->request->dir_config( 'GBrowseConf' );
  $CONF_DIR = Apache->server_root_relative( $conf ) if $conf;
}
## Note that if we're not in mod-perl, this script must specify
## $CONF_DIR, above.

# Load the configuration files, if necessary.
configureBrowsers( $CONF_DIR ) or
  die "Can't read configuration files: $!";

# The session id is the unique_id of the Browser being used.
# Browsers expire to be garbage-collected after a while of disuse.
my $session_id = param( 'session_id' );
my $source = param( 'source' );
my ( $browser, $old_source );
if( !defined( $session_id ) ||
    !( $browser = retrieveBrowser( $session_id ) ) ) {
  $session_id = cookie( 'gbrowse_session_id' );
}
if( !defined( $session_id ) ||
    !( $browser = retrieveBrowser( $session_id ) ) ) {
  $old_source = param( 'last_source' );
  unless( defined( $old_source ) ) {
    ## TODO: Why do we not get the cookie when we're in GET mode?;
    $old_source = cookie( 'gbrowse_source' );
    #  unless ( $source && ( request_method() eq 'GET' ) );
  }
  $browser =
    Bio::Graphics::Browser->new(
      %defaults
    );
  $session_id = $browser->unique_id();
}
unless( defined $old_source ) {
  $old_source = $browser->source();
}
unless( defined $source ) {
  $source = $old_source;
}

$browser->gbrowse( \*STDOUT, $source, $old_source );

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;
