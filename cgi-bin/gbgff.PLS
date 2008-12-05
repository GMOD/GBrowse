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

# $Id: gbgff.PLS,v 1.1.2.13 2008-12-05 15:14:01 lstein Exp $

# Dirt simple GFF3 dumper, suitable for a lightweight replacement to DAS.
# Call this way:
#    http://my.host/cgi-bin/gbgff/volvox?q=ctgA:1..2000;t=Genes+ExampleFeatures
#
# From within the "Add Remote Annotations" section, you can say:
#     http://my.host/cgi-bin/gbgff/volvox?q=$segment;t=Genes+ExampleFeatures
#
# See http://www.gmod.org/wiki/index.php/Gbgff for more information
#
# To share uploads, do this:
#     http://my.host/cgi-bin/gbgff/volvox?q=ctgA:1..2000;\
#           t=Genes+ExampleFeatures+file:my_upload.txt;id=session_id

use strict;
use warnings;
use CGI 'header';
use vars qw($CONF_DIR $VERSION);

my $dumper = GFFDumper->new;
exit_with_format_error() unless $dumper->valid_args;

$dumper->get_segment();

print header($dumper->get_mime_type);
$dumper->print_gff3();
exit 0;

sub exit_with_format_error {
    print header('text/plain');
    print <<END;
# I don't understand this request. Maybe you pasted the URL directly into the
# location box of your browser rather than into the GBrowse remote annotations box?
#
# This URL is supposed to be used indirectly by pasting it into the 
# "Add remote annotations" field at the bottom of a GBrowse page.
# GBrowse will then load the data from this source into a new track.
END
    exit 0;
}

package GFFDumper;

use Bio::Graphics::Browser::Util;
use CGI 'param','path_info','header';
use Bio::Graphics::FeatureFile;
use Bio::Graphics::Browser;

use vars '$CONFIG';

sub new {
    my $class  = shift;
    my $config = $class->initialize();
    return bless {config => $config},ref $class || $class;
}

sub valid_args {
    my $self = shift;
    return unless param();
    my $q = param('q') || param('segment');
    my ($seqid,$start,$end) = 
	$q =~ /^([^:]+)(?::([\d-]+)(?:\.\.|,)([\d-]+))?/;
    $seqid ||= param('ref') || param('seqid');
    return unless $seqid;
    return if     $seqid =~ /^\$segment/;
    1;
}

sub print_gff3 {
    my $self = shift;

    my $labels = $self->get_labels;
    my $types  = $labels ? $self->labels_to_types($labels) : undef;
    my $files  = $labels ? $self->labels_to_files($labels) : undef;

    $self->print_configuration($_,$labels)      for $self->config;
    $self->print_configuration($_,[$_->labels]) for @$files;

    my %filters = map {$_ => $self->config->setting($_=>'filter')||undef} @$labels;

    my $date = localtime;
    print "##gff-version 3\n";
    print "##date $date\n";
    print "##source gbrowse gbgff gff3 dumper\n";

    $self->print_gff3_data($_,$types,\%filters)  for $self->db;
    $self->print_gff3_data($_)                   for @$files;
}

sub config { shift->{config} }

sub db     { 
    my $self = shift;
    return $self->{db} if $self->{db};
    return $self->{db} = open_database($self->config);
}

sub segment {
    my $self = shift;
    my $d    = $self->{segment};
    $self->{segment} = shift if @_;
    $d;
}

sub initialize {
    my $self     = shift;

    my $dir      = conf_dir($main::CONF_DIR);
    my $config   = open_config($dir);  # open_config() is exported from Util.pm

    my $src = param('src') || param('source') || path_info();
    $src    =~ s!^/+!!;  # get rid of leading / from path_info()
    $src    =~ s!/+$!!;  # get rid of trailing / from path_info()

    if ($src) {
	unless ($config->source($src)) {
	    print header('text/plain'),
	    "# Invalid source $src; you may not have permission to access this data source.\n";
	    exit 0;
	}
    }

    return $config;
}


sub get_segment {
    my $self   = shift;
    my $config = $self->config;

    my $q = param('q') || param('segment');
    my ($seqid,$start,$end) = 
	$q =~ /^([^:]+)(?::([\d-]+)(?:\.\.|,)([\d-]+))?/;

    $seqid ||= param('ref')   || param('seqid');
    $start ||= param('start') || 1;
    $end   ||= param('end')   || param('stop');
    unless (defined $seqid) {
	print header('text/plain'),"# Please provide ref, start and end arguments.\n";
	exit 0;
    }

    my $db    = $self->db;
    my ($s)   = $db->segment($seqid,$start=>$end);
    unless (defined $s) {
	print header('text/plain'),"# Unknown segment $seqid:$start..$end.\n";
	exit 0;
    }

    $self->segment($s);
    return $s;
}

sub get_labels {
    my $self   = shift;
    my @labels = (param('type'),param('t'));
    return unless @labels;
    @labels    = shellwords(@labels);
    return \@labels;
}

sub get_id {
    my $self = shift;
    return param('id');
}

sub get_featurefiles {
    my $self   = shift;
    my @ff     = grep {/^file:/} (param('type'),param('t'));
    return unless @ff;
    return shellwords(@ff);
}

sub get_do_stylesheet {
    my $self   = shift;
    my $config = $self->config;
    my $doit = param('stylesheet') || param('s');
    return 0 if defined $doit && $doit =~ /^(no|off|0)$/i;
    return 1;
}

sub get_mime_type {
    my $self   = shift;
    my $config = $self->config;
    my $dump   = param('d') || '';
    return 'application/x-gff3'       if $dump eq 'edit';
    return 'application/octet-stream' if $dump eq 'save';
    return 'text/plain';
}

sub labels_to_types {
    my $self     = shift;
    my $labels   = shift;
    my $config   = $self->config;

    # remove dynamic labels, such as uploads
    my @labels = grep {!/^\w+:/} @$labels;

    my @types;
    for my $l (@labels) {
	my @f = shellwords($config->setting($l=>'feature')||'');
	unless (@f) {
	    print "# Unknown track type $l\n";
	    exit 0;
	}
	push @types,@f;
    }
    return \@types;
}

sub labels_to_files {
    my $self   = shift;
    my $labels = shift;

    my @labels = grep {/^file:/} @$labels;
    @labels                or return [];

    # get the feature files, if appropriate
    my $id = $self->get_id or return [];

    # first get the main source
    my $config  = $self->config;    
    my $segment = $self->segment;

    my @files;

    my $dir    = $config->tmpdir($config->source."/uploaded_file/$id");
    my $mapper = $config->coordinate_mapper($segment,1);
    for my $filename (@labels) {
	my ($base) = $filename =~ /([^:\\\/]+)$/;
	$base      =~ tr/-/_/;
	my $path   = "$dir/$base";
	my $featurefile = eval {
	    Bio::Graphics::FeatureFile->new(-file           => $path,
					    -smart_features => 1,
					    -map_coords     => $mapper,
		);
	};
	push @files,$featurefile if $featurefile;
    }
	
    return \@files;
}


sub print_feature {
    my $self = shift;
    my $f    = shift;
    eval {$f->version(3)};
    my $s = $f->gff_string(1); # the flag is for GFF3 subfeature recursion
    chomp $s;
    $s =~ s/\t\t/\t\.\t/g if $s; # no empty columns
    $self->do_wigfile_substitution(\$s);
    print $s,"\n";
}

sub print_configuration {
    my $self   = shift;
    my $config = shift;
    my $labels = shift;

    my @labels = $labels ? @$labels : $config->labels;

    for my $l (@labels) {
	next if $l =~ m/^\w+:/;  # a special config setting - don't want it to leak through
	print "[$l]\n";
	my @s = $config->_setting($l);
	for my $s (@s) {
	    my $value = $config->setting($l=>$s);
	    if (ref $value eq 'CODE') {
		$value = $config->config->can('get_callback_source')
		    ? $config->config->get_callback_source($l => $s)
		    : $config->setting('TRACK DEFAULTS'=>$s);
		defined $value or next;
	    }
	    next if $s =~ /^balloon/; # doesn't work right
	    print "$s = $value\n";
	}
	print "\n";
    }
}

sub print_gff3_data {
    my $self    = shift;
    my $db      = shift;
    my $types   = shift;
    my $filters = shift;

    my $s       = $self->segment;
    my $c       = $self->config;
    my $len     = $s->length;

    my @args    = (-seq_id => $s->seq_id,
		   -start  => $s->start,
		   -end    => $s->end);
    push @args,(-type=>$types) if $types;
    my $iterator = $db->get_seq_stream(@args);

  FEATURE:
    while ( my $f = $iterator->next_seq ) {
	for my $l ($c->feature2label($f,$len)) {
	    next FEATURE  if $filters->{$l} && !$filters->{$l}->($f);
	}
	$self->print_feature($f);
    }
}

# Because we can't sling whole wigfiles around, we serialize a section
# of the wigfile and send just the data and header information in "wif" format.
sub do_wigfile_substitution {
    my $self = shift;

    my $gff_line_ref = shift;
    $$gff_line_ref =~ /wigfile=/ or return;

    my $segment      = $self->segment;
    my ($start,$end) = ($segment->start,$segment->end);

    eval { # trap all errors, which can be plentiful!
	eval "use Bio::Graphics::Wiggle" unless Bio::Graphics::Wiggle->can('new');
	eval "use MIME::Base64"          unless MIME::Base64->can('encode');

	$$gff_line_ref   =~ s{wigfile=([^;&\n]+)}
	{
          my $wig = Bio::Graphics::Wiggle->new(CGI::unescape($1));
          my $wif = $wig->export_to_wif($start,$end);
          'wigdata='.MIME::Base64::encode_base64($wif,'');
        }exg;
    };
    warn $@ if $@;
}

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
