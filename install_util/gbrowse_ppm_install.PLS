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
!GROK!THIS!

print OUT <<'!NO!SUBS!';
# After PPM downloads and installs the contents of blib, this script
# prompts the user for the location of htdocs, conf, and cgi-bin
# and installs them.

use strict;
use LWP::Simple;
use Archive::Tar;
use File::Basename 'dirname';
use ExtUtils::MakeMaker 'prompt';  # love it!
!NO!SUBS!


print OUT <<"!GROK!THIS!";
use constant SUPPORT_FILES  => 'gbrowse_ppm_support_files-$OPTIONS{VERSION}.tar.gz';
!GROK!THIS!

print OUT <<'!NO!SUBS!';
use constant PPM_REPOSITORY => 'http://stein.cshl.org/ppm';

# fetch the support files
print "Fetching GBrowse support files...\n";
my $file = SUPPORT_FILES;
my $url  = join '/',PPM_REPOSITORY,SUPPORT_FILES;
my $rc   = mirror($url,$file);

if (is_error($rc)) {
  die "Sorry, couldn't fetch $file from ",PPM_REPOSITORY,". HTTP code: $rc.\n";
}

# unpack them
print "Unpacking support files...\n";
$rc = Archive::Tar->extract_archive($file);
unless ($rc) {
  die "Sorry, couldn't unpack $file: ",Archive::Tar->error,"\n";
}

die "Unexpected error.  There should be an install_util directory here, but there isn't!\n" unless -d "install_util";

# now we get to prompt the user endlessly for the pathnames
my $prefix  = $^O =~ /mswin/ ? 'C:/Program Files/Apache Group/Apache2' : '/usr/local/apache';

my $conf    = prompt_for_directory('web server conf',   "$prefix/conf");
$prefix     = dirname($conf); # update

my $htdocs  = prompt_for_directory('web server htdocs', "$prefix/htdocs");
my $cgibin  = prompt_for_directory('web server cgi-bin',"$prefix/cgi-bin");

system("perl","install_util/htdocs_install.pl","$htdocs/gbrowse");
system("perl","install_util/conf_install.pl","$conf/gbrowse.conf");
system("perl","install_util/cgi_install.pl",$cgibin);

print STDERR "** Installation should be complete.  Now go to http://your.server/gbrowse for further setup instructions. **\n";

exit 0;

sub prompt_for_directory {
  my ($prompt,$default) = @_;
  my $dir;
  while (!$dir) {
    $dir = prompt("Where is your $prompt directory located ('q' to quit)",$default);
    exit 0 if $dir eq 'q';
    $dir = interpolate($dir);
    if (!-d $dir) {
      print STDERR "$dir doesn't exist.  Please try again.\n";
      redo;
    } elsif (!-w $dir) {
      print STDERR "warning: $dir isn't writable. Installation may fail.\n";
    }
  }
  return $dir;
}

sub interpolate {
  my $path = shift;
  my ($to_expand,$homedir);
  return $path unless $path =~ m!^~([^/]*)!;
  eval {
    if ($to_expand = $1) {
      $homedir = (getpwnam($to_expand))[7];
    } else {
      $homedir = (getpwuid($<))[7];
    }
    return $path unless $homedir;
    $path =~ s!^~[^/]*!$homedir!;
  };
  return $path;
}
!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
