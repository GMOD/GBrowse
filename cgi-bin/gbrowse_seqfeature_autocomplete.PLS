#!perl
use Config;
use File::Basename qw(&basename &dirname);
use File::Spec;
use FindBin '$Bin';
use Cwd;

my %OPTIONS;
if (open F,"$Bin/../GGB.def") {
  while (<F>) {
    next if /^\#/;
    chomp;
    $OPTIONS{$1} = $2 if /^(\w+)\s*=\s*(.+)/;
  }
  close F;
}
$OPTIONS{CONF} ||= '/usr/local/apache/conf';

my $dir = dirname($0);
$file   = shift || File::Spec->catfile($dir,basename($0, '.PL','.PLS'));

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

print OUT "use lib '$OPTIONS{LIB}';\n" if defined $OPTIONS{LIB};

# In the following, perl variables are not expanded during extraction.

print OUT <<'!NO!SUBS!';
# $Id: gbrowse_seqfeature_autocomplete.PLS,v 1.1 2007-01-05 15:00:16 lstein Exp $

use strict;
use CGI qw(param header path_info);
use DBI;

use vars qw($CONF_DIR $VERSION);

my $dsn = path_info;
$dsn    =~ s!^/!!;
$dsn    = "dbi:mysql:$dsn" unless $dsn =~ /^dbi/;

my $dbh = DBI->connect($dsn) or die DBI->errstr;
my $term = param('query');

print header('text/plain');

my $query = "select distinct name.name from name where name.name like ? LIMIT 50";
warn $query;

my $sth =  $dbh->prepare($query)      or die $dbh->errstr;
$sth->execute(quotemeta($term).'%')   or die $sth->errstr;

while (my ($h) = $sth->fetchrow_array) {
  print $h,"\n";
}

exit 0;

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
