use ExtUtils::MakeMaker;
use FindBin '$Bin';
require 5.005003;

my $VERSION = 1.35;

my @OPTIONS = qw(APACHE CONF HTDOCS CGIBIN);
my $OPTIONS = join ('|',@OPTIONS);
my %OPTIONS;

my @argv = @ARGV;
@ARGV = ();

foreach (@argv) {
  if (/^--?h/i) {
    die "To customize install locations, provide one or more of the options APACHE, CONF, HTDOCS, or CGIBIN, as in CONF=/usr/local/apache/conf\n";
  }

  elsif (/($OPTIONS)=(.+)/g) {
    $OPTIONS{$1} = $2;
  }

  else {
    push @ARGV,$_;
  }
}

# set hard-coded values
$OPTIONS{PREFIX} ||= '/usr/local/apache';
unless ($OPTIONS{CONF}) {
  $OPTIONS{CONF} = "$OPTIONS{PREFIX}/conf";
  warn "NOTE: Setting location of browser configuration files to $OPTIONS{CONF}\n";
}
unless ($OPTIONS{HTDOCS}) {
  $OPTIONS{HTDOCS} = "$OPTIONS{PREFIX}/htdocs";
  warn "NOTE: Setting location of browser static files to $OPTIONS{HTDOCS}\n";
}
unless ($OPTIONS{CGIBIN}) {
  $OPTIONS{CGIBIN} = "$OPTIONS{PREFIX}/cgi-bin";
  warn "NOTE: Setting location of browser static files to $OPTIONS{CGIBIN}\n";
}

open F,">$Bin/GGB.def" or die "Can't open $Bin/GGB.def for writing: $!";
print F "# This hints file contains configuration information used by the generic browser\n\n";
foreach (keys %OPTIONS) {
  print F "$_=$OPTIONS{$_}\n";
}
print F "VERSION=$VERSION\n";
close F;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	      'NAME'	     => 'Generic-Genome-Browser',
	      'VERSION'      => $VERSION,
	      'PREREQ_PM'    => {
				 Bio::Graphics => 0.92,
				 Bio::DB::GFF  => 1.01,
				}, # e.g., Module::Name => 1.1
	      PL_FILES       => {
				 'bin/process_sgd.PLS' => 'bin/process_sgd.pl',
				 'bin/process_gadfly.PLS' => 'bin/process_gadfly.pl',
				 'bin/process_wormbase.PLS' => 'bin/process_wormbase.pl',
				 'gbrowse.PLS'  => 'gbrowse',
				 },
	      EXE_FILES      => [
				 'bin/process_wormbase.pl',
				 'bin/process_sgd.pl',
				 'bin/process_gadfly.pl',
				],
	      'LIBS'	     => [''], # e.g., '-lm'
	      'DEFINE'	     => '',
	      'INC'	     => '', # e.g., '-I/usr/include/other'
);

sub MY::clean {
  package MY;
  my $inherited = shift->SUPER::clean(@_);
  $inherited .= "\t-rm -f gbrowse\n";
  $inherited .= "\t-rm GGB.def\n";
  $inherited;
}

sub MY::processPL {
  package MY;
  my $inherited = shift->SUPER::processPL(@_);
  $inherited =~ s/:: gbrowse\.PLS/:: gbrowse.PLS GGB.def/;
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
	\@echo "Installing sample configuration files..."
	\@dir=$OPTIONS{CONF}/gbrowse.conf; \\
	mkdir -p \$\$dir; \\
	cd $Bin/conf; \\
	for i in *.{conf,html}; do \\
		if [ -e "\$\$dir/\$\$i" ]; then \\
			echo "   Found \$\$i in \$\$dir. Skipping..."; \\
		else \\
			cp \$\$i \$\$dir; \\
		fi \\
	done

htdocs_install ::
	\@echo "Installing stylesheet and images..."
	\@dir=$OPTIONS{HTDOCS}/gbrowse; \\
	mkdir -p \$\$dir; \\
	cd $Bin/htdocs; \\
	for i in *.css; do \\
		if [ -e "\$\$dir/\$\$i" ]; then \\
			echo "   Found \$\$i in \$\$dir. Skipping..."; \\
		else \\
			cp \$\$i \$\$dir; \\
		fi \\
	done; \\
	cd $Bin/htdocs/images; \\
	mkdir -p \$\$dir/images; \\
	for i in *; do \\
		cp -pr \$\$i \$\$dir/images; \\
	done; \\
	echo "Making \$\$dir/tmp..."; \\
	mkdir -p \$\$dir/tmp; \\
	echo "Making \$\$dir/tmp world writable..."; \\
	chmod ugo+rwx \$\$dir/tmp

cgi_install :: gbrowse
	\@echo "Installing gbrowse CGI script..."
	\@dir=$OPTIONS{CGIBIN}; \\
	mkdir -p \$\$dir; \\
	cp $Bin/gbrowse \$\$dir; \\
	chmod +x \$\$dir/gbrowse

};
}
