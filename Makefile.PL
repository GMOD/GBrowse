use ExtUtils::MakeMaker;
use FindBin '$Bin';
require 5.005003;

my $VERSION = '1.51';

my @OPTIONS = qw(PREFIX CONF HTDOCS CGIBIN LOG);
my $OPTIONS = join ('|',@OPTIONS);
my %OPTIONS;

my @argv = @ARGV;
@ARGV = ();

foreach (@argv) {
  if (/^--?h/i) {
    die <<END;
To customize install locations, provide one or more of the options
PREFIX, CONF, HTDOCS, or CGIBIN, as in CONF=/usr/local/apache/conf.

For RedHat Linux, you will want to use:
    perl Makefile.PL CONF=/etc/httpd/conf \
                     HTDOCS=/var/www/html \
                     LOG=/var/www/log \
                     CGIBIN=/var/www/cgi-bin

For most versions of Apache built from source code, use:
    perl Makefile.PL PREFIX=/usr/local/apache
END
;
  }

  elsif (/($OPTIONS)=(.+)/og) {
    $OPTIONS{$1} = interpolate($2);
  }

  else {
    push @ARGV,$_;
  }
}

if (-e 'GGB.def' && !%OPTIONS) {
  print STDERR "You have installed gbrowse before.  Should I use the previous settings to set the file paths (y/n) [y]? ";
  chomp (my $line = <>);
  if (!$line || $line =~ /^[yY]/) {
    print STDERR "Using previous settings for file paths.\n";
    open F,'GGB.def' or die "GGB.def: $!";
    while (<F>) {
      chomp;
      next if /^\#/;
      next unless /^($OPTIONS)=(.+)/o;
      $OPTIONS{$1} = interpolate($2);
    }
    close F;
  }
}

# set hard-coded values
$OPTIONS{PREFIX} ||= '/usr/local/apache';
unless ($OPTIONS{CONF}) {
  $OPTIONS{CONF} = "$OPTIONS{PREFIX}/conf";
}
unless ($OPTIONS{HTDOCS}) {
  $OPTIONS{HTDOCS} = "$OPTIONS{PREFIX}/htdocs";
}
unless ($OPTIONS{CGIBIN}) {
  $OPTIONS{CGIBIN} = "$OPTIONS{PREFIX}/cgi-bin";
}
unless ($OPTIONS{LOG}) {
  $OPTIONS{LOGS} = "$OPTIONS{PREFIX}/gbrowse-logs";
}

open F,">$Bin/GGB.def" or die "Can't open $Bin/GGB.def for writing: $!";
print F "# This hints file contains configuration information used by the generic browser\n\n";
print F "# To reconfigure, run perl Makefile.PL `cat GGB.def`\n\n";
foreach (keys %OPTIONS) {
  print F "$_=$OPTIONS{$_}\n";
}
print F "VERSION=$VERSION\n";
close F;

print STDERR <<END;
----------------------------------------------
                File Paths

END
;
foreach (qw(PREFIX CONF HTDOCS CGIBIN LOG)) {
  printf STDERR "%7s %s\n",$_,$OPTIONS{$_};
}
print STDERR <<END;

(Run perl Makefile.PL -h for help on changing)
----------------------------------------------
END
;


# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	      'NAME'	     => 'Generic-Genome-Browser',
	      'VERSION'      => $VERSION,
	      'PREREQ_PM'    => {
				 Bio::Graphics => 0.92,
				 Bio::DB::GFF  => 1.01,
				 GD            => 0,
				 IO::String    => 0,
				 Text::Shellwords  => 1.0,
				}, # e.g., Module::Name => 1.1
	      PL_FILES       => {
				 'bin/process_sgd.PLS' => 'bin/process_sgd.pl',
				 'bin/process_gadfly.PLS' => 'bin/process_gadfly.pl',
				 'bin/process_wormbase.PLS' => 'bin/process_wormbase.pl',
				 'bin/process_ncbi_human.PLS' => 'bin/process_ncbi_human.pl',
				 'gbrowse.PLS'  => 'gbrowse',
				 'gbrowse_img.PLS'  => 'gbrowse_img',
				 },
	      EXE_FILES      => [
				 'bin/process_wormbase.pl',
				 'bin/process_sgd.pl',
				 'bin/process_gadfly.pl',
				 'bin/process_ncbi_human.pl',
				],
	      'LIBS'	     => [''], # e.g., '-lm'
	      'DEFINE'	     => '',
	      'INC'	     => '', # e.g., '-I/usr/include/other'
              ($] ge '5.005') ? (
                  'AUTHOR'   => 'Lincoln Stein (lstein@cshl.org)',
                  'ABSTRACT' => 'A CGI-driven browser for genomic annotations.',
                                ) : (),
);

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

sub MY::clean {
  package MY;
  my $inherited = shift->SUPER::clean(@_);
  $inherited .= "\t-\$(PERL) make_clean_add.pl\n";
  $inherited;
}

sub MY::processPL {
  package MY;
  my $inherited = shift->SUPER::processPL(@_);
  $inherited =~ s/:: gbrowse\.PLS/:: gbrowse.PLS GGB.def/;
  $inherited =~ s/:: gbrowse_img\.PLS/:: gbrowse_img.PLS GGB.def/;
  $inherited;
}

sub MY::install {
  package MY;
  my $inherited = shift->SUPER::install(@_);
  $inherited =~ s/doc_install/doc_install conf_install htdocs_install cgi_install/;
  $inherited;
}

sub MY::postamble {
qq{
conf_install ::
	\$(PERL) conf_install.pl $OPTIONS{CONF}/gbrowse.conf

htdocs_install ::
	\$(PERL) htdocs_install.pl $OPTIONS{HTDOCS}/gbrowse

cgi_install :: gbrowse
	\$(PERL) cgi_install.pl $OPTIONS{CGIBIN}

};
}
