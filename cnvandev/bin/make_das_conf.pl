#!/usr/bin/perl
# $Id: make_das_conf.pl,v 1.1 2008-10-16 17:01:27 lstein Exp $

use strict;
use Bio::Das 1.03;
use Getopt::Long;

my @COLORS = qw(cyan blue red yellow green wheat turquoise orange);  # default colors
my $color = 0;      # position in color cycle
my %known_aggregators = map {$_=>1} qw(clone match processed_transcript wormbase_gene
                                       orf reftranscript waba_alignment
                                       coding cds alignment transcript
                                       ucsc_assembly ucsc_ensgene ucsc_refgene
                                       ucsc_sanger22 ucsc_sanger22pseudo
                                       ucsc_softberry ucsc_twinscan ucsc_unigene);
my $proxy;

GetOptions('proxy=s' => \$proxy) or usage_statement();

my $url = shift;
$url or usage_statement();
$url =~ m!^http:.+das(/\w+)?$! or usage_statement("This doesn't look like a DAS URL to me.");
$ENV{HTTP_PROXY} ||= $proxy;

list_sources($url) && exit 0 if $url =~ m!das/?$!;
generate_config_file($url);

exit 0;

sub usage_statement {
  my $error = shift;
  $error .= "\n" if $error;

die <<END;
${error}Usage: $0 <das URL to load>

Options: -proxy  <http proxy to use>

This utility attempts to contact a DAS source and to create a starter
configuration file for gbrowse.  If you don\'t know the list of data sources
it will retrieve them and ask you to select one.

If you need an HTTP proxy, set the HTTP_PROXY environment variable to
the host and port number, in the form "http://proxy.host:port/", or
pass the proxy URL to the -proxy option.
END
; }

sub list_sources {
  my $url     = shift;
  my $das = Bio::Das->new($url);
  warn "proxy = $ENV{HTTP_PROXY}";
  $das->proxy($ENV{HTTP_PROXY}) if $ENV{HTTP_PROXY};
  my @sources = $das->sources or bad_request_exit($das);
  print "The following DAS URLs are available at this server.  Please call the script again\n";
  print "using one of the following URLs:\n\n";
  for my $s (@sources) {
    print $s->url,"\n";
    print "\t",$s->description,"\n\n";
  }
  1;
}

sub generate_config_file {
  my $url           = shift;
  my ($server,$dsn) = $url=~ m[^(.+/das)/(\w+)];
  my $das   = Bio::Das->new($server=>$dsn);

  $das->proxy($ENV{HTTP_PROXY}) if $ENV{HTTP_PROXY};

  my @sources  = $das->sources or bad_request_exit($das);
  my ($source) = grep {$_->id eq $das->default_dsn} @sources;

  my @types   = $das->types  or bad_request_exit($das);
  $source  or bad_request_exit($das);

  my %seenit;
  my @aggregators = grep {!$seenit{$_}++} 
                      map {
                            my ($method,$source) = split ':';
                            $known_aggregators{$method} ? $method : "$method\{$method\}"
			  } @types;
  my $aggregators = join "\n       ",@aggregators;

  my $description  = $source->description;
  my $mapmaster    = $source->master;
  my @entry_points = sort {"$a" cmp "$b"} $das->entry_points;
  foreach (@entry_points) {  # remove coordinates
    s/:\d+,\d+$//;
  }

  my $proxy = $ENV{HTTP_PROXY} ? "-proxy  $ENV{HTTP_PROXY}" : '';

  # top part of the config file
  print <<END;
[GENERAL]
description   = $description
db_adaptor    = Bio::Das
db_args       = -source $server
	        -dsn    $dsn
                $proxy

# examples to show in the introduction
examples = @entry_points

das mapmaster = $mapmaster

aggregators = $aggregators

########################
# Default glyph settings
########################

[TRACK DEFAULTS]
glyph         = segments
height        = 10
bgcolor       = lightgrey
fgcolor       = black
font2color    = blue
label density = 25
bump density  = 100
label         = 1
description   = 1

END
;

  for my $type (@types) {
    my $method = $type->method || $type;
    my $source = $type->source;
    my $label  = uc ($type eq $method ? $type : "${type}_${method}");
    $label =~ s/:/_/g;
    my $desc   = $source ? "These are ${method} features from $source." : "These are ${method} features.";
    my $key    = $type;
    my $category = $type->category;
    my $idx      = $color++ % @COLORS;
    print <<END;
[$label]
feature      = $type
bgcolor      = $COLORS[$idx]
das category = $category
key          = $key
citation     = $desc

END
  }
}

sub bad_request_exit {
  my $das = shift;
  my $error = $das->error;
  die <<END;
$error

An error was encountered while processing the DAS request.  Are you sure this
is an operational DAS server?
END
}

# boilerplate
__END__

=head1 NAME

make_das_conf.pl - Create GBrowse config files from DAS sources

=head1 SYNOPSIS

  % make_das_conf.pl http://genome.cse.ucsc.edu/cgi-bin/das/hg16 > /usr/local/apache/conf/gbrowse.conf/ucsc.conf

=head1 DESCRIPTION

This script generates a rough draft configuration file suitable for
browsing a remote DAS server.

To use this script, give it the URL of a DAS server.  If you point it
at the DAS base URL (without the data source name), as in
"http://genome.cse.ucsc.edu/cgi-bin/das", it will print a list of
valid data sources to standard output.  If you give it a complete DAS
URL, as in "http://genome.cse.ucsc.edu/cgi-bin/das/hg16", it will
print a gbrowse configuration file to standard output.

You will probably want to tweak the configuration file after you
generate it.  In particular, you will want to customize the glyph
types associated with each track and adjust the list of examples given
in the instructions (by default this script uses the complete list of
entry points, which may be rather long).

Also be aware that this script creates a set of aggregators that may
or may not be correct.  Consider the case of a DAS server which uses
the canonical structure for a spliced mRNA:

     main method:   mRNA
     subparts:      5'-UTR, CDS, 3'-UTR

This conversion script will generate the following set of aggregators:

   mRNA{mRNA}
   5'-UTR{5'-UTR}
   CDS{CDS}
   3'-UTR{3'-UTR}

It will also generate a total of four tracks, one each for the mRNA
and each of its parts.

This is, of course, incorrect. You will want to consolidate these into
a single aggregator:

   mRNA{5'-UTR,3'-UTR,CDS/mRNA}

=head1 SEE ALSO

L<Bio::DB::GFF>, L<bulk_load_gff.pl>, L<load_gff.pl>

=head1 AUTHOR

Lincoln Stein <lstein@cshl.org>.

Copyright (c) 2002 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut

