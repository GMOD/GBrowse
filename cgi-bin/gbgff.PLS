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

# $Id: gbgff.PLS,v 1.1.2.6 2008-05-15 17:46:23 lstein Exp $

# Dirt simple GFF3 dumper, suitable for a lightweight replacement to DAS.
# Call this way:
#    http://my.host/cgi-bin/gbgff/volvox?q=ctgA:1..2000;t=Genes+ExampleFeatures
#
# From within the "Add Remote Annotations" section, you can say:
#     http://my.host/cgi-bin/gbgff/volvox?q=$segment;t=Genes+ExampleFeatures
#
# See http://www.gmod.org/wiki/index.php/Gbgff for more information

use strict;
use warnings;

use vars qw($CONF_DIR $VERSION);

use CGI 'param','path_info','header';
use Bio::Graphics::FeatureFile;
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Util;
use Text::ParseWords 'shellwords';

use vars '$CONFIG';

my $config        = initialize();
my $segment       = get_segment($config);
my $labels        = get_labels($config);
my $types         = get_types($config,$labels) if $labels;
my $do_stylesheet = get_do_stylesheet($config);
my $mime          = get_mime_type($config);

print header($mime);

# print relevant configuration
print_configuration($config,$labels) if $do_stylesheet;
print_gff3($segment,$types);
exit 0;

sub initialize {

    my $dir      = conf_dir($CONF_DIR);
    my $config   = open_config($dir);  # open_config() is exported from Util.pm

    my $src = param('src') || param('source') || path_info();
    $src    =~ s!^/+!!;  # get rid of leading / from path_info()
    $src    =~ s!/+$!!;  # get rid of trailing / from path_info()

    if ($src) {
	unless ($config->source($src)) {
	    print "# Invalid source $src; you may not have permission to access this data source.\n";
	    exit 0;
	}
    }

    $config;
}

sub get_segment {
    my $config = shift;

    my ($seqid,$start,$end) = param('q') =~ /^([^:]+):([\d-]+)(?:\.\.|,)([\d-]+)/;
    $seqid ||= param('ref') || param('seqid');
    $start ||= param('start');
    $end   ||= param('end') || param('stop');
    unless (defined $seqid && defined $start && defined $end) {
	print "# Please provide ref, start and end arguments.\n";
	exit 0;
    }

    my $db    = open_database($config);
    my $s     = $db->segment($seqid,$start=>$end);
    unless (defined $s) {
	print "# Unknown segment $seqid:$start..$end.\n";
	exit 0;
    }

    return $s;
}

sub get_labels {
  my $config = shift;
  my @labels = (param('type'),param('t'));
  @labels    = shellwords(@labels) if @labels;
  \@labels;
}

sub get_do_stylesheet {
  my $config = shift;
  my $doit = param('stylesheet') || param('s');
  return 0 if defined $doit && $doit =~ /^(no|off|0)$/i;
  return 1;
}

sub get_mime_type {
  my $config = shift;
  return 'application/x-gff3'       if param('d') eq 'edit';
  return 'application/octet-stream' if param('d') eq 'save';
  return 'text/plain';
}

sub get_types {
    my $config   = shift;
    my $labels   = shift;

    my @types;
    for my $l (@$labels) {
	my @f = shellwords($config->setting($l=>'feature')||'');
	unless (@f) {
	    print "# Unknown track type $l\n";
	    exit 0;
	}
	push @types,@f;
    }
    return \@types;
}

sub print_feature {
    my $f = shift;
    eval {$f->version(3)};
    my $s = $f->gff_string(1); # the flag is for GFF3 subfeature recursion
    chomp $s;
    $s =~ s/\t\t/\t\.\t/g if $s; # no empty columns 
    print $s,"\n";
}

sub print_configuration {
    my $config = shift;
    my $labels = shift;

    my @labels = @$labels;
    @labels    = $config->labels unless @labels;

    for my $l (@labels) {
	print "[$l]\n";
	my @s = $config->config->_setting($l);
	for my $s (@s) {
	    my $value = $config->setting($l=>$s);
	    if (ref $value eq 'CODE') {
	      $value = $config->setting('TRACK DEFAULTS'=>$s) or next;
	    }
	    next if $s =~ /^balloon/; # doesn't work right
	    print "$s = $value\n";
	}
	print "\n";
    }
}

sub print_gff3 {
    my ($segment,$types) = @_;

    my $date = localtime;
    print "##gff-version 3\n";
    print "##date $date\n";
    print "##source gbrowse gbgff gff3 dumper\n";
    print "##sequence-region ",join(' ',$segment->ref,$segment->start,$segment->stop),"\n";

    my @args     = $types && @$types ? (-type=>$types) : ();
    my $iterator = $segment->get_seq_stream(@args);
    while ( my $f = $iterator->next_seq ) {
	print_feature($f);
    }
}

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
