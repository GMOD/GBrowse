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
if ($OPTIONS{PACKAGE_DIR}) {
  $OPTIONS{CONF} =~ s/$OPTIONS{PACKAGE_DIR}//;
}

$OPTIONS{CONF} ||= '/usr/local/apache/conf';

my $dir = dirname($0);
$file   = shift || File::Spec->catfile($dir,basename($0, '.PL','.PLS'));

open OUT,">$file" or die "Can't create $file: $!";

print "Extracting MOBY $file (with variable substitutions)\n";

my $startperl = $Config{startperl} ne '#!perl' 
  ? $Config{startperl}
  : "#!$Config{perlpath}";

print OUT <<"!GROK!THIS!";
$startperl -w
use lib '$OPTIONS{CONF}/gbrowse.conf/';

!GROK!THIS!

print OUT "use lib '$OPTIONS{LIB}';\n" if defined $OPTIONS{LIB};

# In the following, perl variables are not expanded during extraction.

print OUT <<'!NO!SUBS!';
#$Id: moby_server.PLS,v 1.6.12.1 2008-09-12 14:32:35 scottcain Exp $
use SOAP::Transport::HTTP;
use MobyServices::GbrowseServices;
use strict;

my $x = new SOAP::Transport::HTTP::CGI;

$x->dispatch_with({
    'http://biomoby.org/#GbrowseGetReferenceSeqObj' =>  'MobyServices::GbrowseServices',
    'http://biomoby.org/#GbrowseGetReferenceFasta' =>  'MobyServices::GbrowseServices',
    'http://biomoby.org/#GbrowseGetReferenceGFF2' =>  'MobyServices::GbrowseServices',
    'http://biomoby.org/#GbrowseGetReferenceGFF3' =>  'MobyServices::GbrowseServices',
    'http://biomoby.org/#GbrowseGetFeatureSequenceObject' =>  'MobyServices::GbrowseServices',
    'http://biomoby.org/#GbrowseGetFeatureGFF3' =>  'MobyServices::GbrowseServices',
    'http://biomoby.org/#GbrowseGetFeatureGFF2' =>  'MobyServices::GbrowseServices',
    
    });
$x->handle;

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
