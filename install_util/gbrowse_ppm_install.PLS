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
use Config;
use LWP::Simple;
use PPM::Archive;
use File::Basename 'dirname';
use ExtUtils::MakeMaker 'prompt';  # love it!
!NO!SUBS!


print OUT <<"!GROK!THIS!";
use constant SUPPORT_FILES  => 'gbrowse_ppm_support_files-$OPTIONS{VERSION}.tar.gz';
!GROK!THIS!

print OUT <<'!NO!SUBS!';
use constant PPM_REPOSITORY => 'http://www.gmod.org/ggb/ppm';

my $startperl = $Config{startperl} ne '#!perl' 
  ? $Config{startperl}
  : "#!$Config{perlpath}";

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
my $a     = PPM::Archive->new($file);
my @files = $a->list_files;
foreach (@files) {
  $a->extract($_);
}
undef $a;

die "Unexpected error.  There should be an install_util directory here, but there isn't!\n" unless -d "install_util";

eval <<'END'
  use lib './install_util';
  use GuessDirectories;
END
;

# now we get to prompt the user endlessly for the pathnames
print STDERR "\n** Installing GBrowse CGI and config files **\n";
print STDERR "** Please indicate the location of the following Web Server directories:\n";
my $prefix  = $^O =~ /mswin/i ? 'C:/Program Files/Apache Group/Apache2'
                              : '/usr/local/apache';

my $conf    = prompt_for_directory('conf',   GuessDirectories->conf || "$prefix/conf");
$prefix     = dirname($conf); # update

my $htdocs  = prompt_for_directory('htdocs', GuessDirectories->htdocs || "$prefix/htdocs");
my $cgibin  = prompt_for_directory('cgi-bin',GuessDirectories->cgibin || "$prefix/cgi-bin");

fixup($_,"$conf/gbrowse.conf") foreach grep {-T} @files;

my @args = (
             "'APACHE=$prefix'",
             "'CGIBIN=$cgibin'",
             "'CONF=$conf'",
             "'HTDOCS=$htdocs'"
           );

for my $inst ("cgi_install.pl","htdocs_install.pl","conf_install.pl") {
  system("perl","install_util/$inst",@args); #==0
    # or die "The install script, $inst, failed.  I don't know why\n";;
}

print STDERR "\n** GBrowse installation complete.\n";
print STDERR "** Now go to http://your.server/gbrowse for further setup instructions.\n";

exit 0;

sub prompt_for_directory {
  my ($prompt,$default) = @_;
  my $dir;
  while (!$dir) {
    $dir = prompt("\t\"$prompt\" directory ([q]uit)",$default);
    if ($dir eq 'q') {
      print STDERR "ABORTED: your installation is NOT complete\n\n";
      exit 0;
    } 
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

# horrible -- fix line endings for proper architecture
sub fixup {
  my $file = shift;
  my $conf = shift;
  return unless -f $file;
  local $/ = "\012";
  open F,$file or die "Can't open $file: $!";
  open OUT,">$file.new" or die "Can't open $file.new: $!";
  while (<F>) {
    chomp;
    s/^\#!.+/$startperl -w/;
    s/^\$CONF_DIR\s*=\s*\'.+/\$CONF_DIR = '$conf';/;
    print OUT $_,"\n";
  }
  close F;
  close OUT;
  rename "$file.new",$file;
}
!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
