#!perl
use Config;
use File::Basename qw(&basename &dirname);
use FindBin '$Bin';
use Cwd;

my %OPTIONS;
if (open F,"$Bin/GGB.def") {
  while (<F>) {
    next if /^\#/;
    chomp;
    $OPTIONS{$1} = $2 if /^(\w+)\s*=\s*(.+)/;
  }
  close F;
}
$OPTIONS{CONF} ||= '/usr/local/apache/conf';

$origdir = cwd;
chdir dirname($0);
$file = basename($0, '.PL','.PLS');

open OUT,">$file" or die "Can't create $file: $!";

print "Extracting $file (with variable substitutions)\n";

print OUT <<"!GROK!THIS!";
$Config{startperl} -w

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

# $Id: gbrowse_img.PLS,v 1.1 2002-05-04 20:38:26 lstein Exp $

use strict;
use CGI qw(param redirect header start_html end_html p h1);
use Bio::DB::GFF;
use Bio::Graphics;
use Bio::Graphics::Browser;
use Text::Shellwords;
use vars qw($CONFIG $VERSION $CONF_DIR %DB);

# call with following arguments:
# source    database source
# type      list of feature mnemonics
# options   track options, in format mnemonic+option+mnemonic+option...
# name      landmark or range to display, in format Name:start..stop
# width     desired width of image, in pixels (height cannot be set)
# add       a feature to superimpose on top of the image
#             in format: reference+type+name+start..stop,start..stop,start..stop
#           multiple "add" arguments are allowed

BEGIN {
    # here's a patch for a fix in Bio::DB::GFF that didn't get into BioPerl 1.0
    unless (Bio::DB::GFF::Segment->can('seq_id')) {
      *Bio::DB::GFF::Segment::seq_id  = sub { shift->ref };
      *Bio::Graphics::Feature::seq_id = sub { shift->ref };
    }
};

if ($ENV{MOD_PERL}) {
  my $conf  = Apache->request->dir_config('GBrowseConf');
  $CONF_DIR = Apache->server_root_relative($conf) if $conf;
}
$CONFIG  ||= Bio::Graphics::Browser->new;
$CONFIG->read_configuration($CONF_DIR) or message("Can't read configuration files: $!");

unless (param()) {
  print header;
  print_usage();
  exit 0;
}

# set the database source
$CONFIG->source(param('source'))               if param('source');

# self-documentation feature: dump out tab-delimited list of mnemonics and keys
if (param('list')) {
  dump_sources() if param('list') eq 'sources';
  dump_types()   if param('list') eq 'types';
  exit 0;
}

# don't even bother if the name argument is missing
my $segment_id = param('name') or message("Must provide a 'name' parameter to specify region to display.");

# get the segment
my $segment = get_segment($segment_id) or message("Segment $segment_id not found.");

# set the image width
$CONFIG->width(param('width'))                              if param('width');

# set the track types to display.
my @labels = map {split /[+\s]/} param('type');
@labels    = $CONFIG->default_labels unless @labels;

# add external features
my $feature_list = external_features(\@labels,$segment,param('add')) if param('add');

# get the options
my %options = map {split /[+\s]/} param('options');

my $img = $CONFIG->image_and_map(segment       => $segment,
				 tracks        => \@labels,
				 options       => \%options,
				 feature_files => $feature_list||undef,
				 label_scale   => 1,
				);
if ($img->can('gif')) {
  print header('image/gif');
  print $img->gif;
} else {
  print header('image/png');
  print $img->png;
}

sub message {
  my @msg = @_;
  print header();
  print start_html,
        h1('Error'),
        p(@msg),
        end_html;
  exit 0;
}

sub get_segment {
  my $name = shift;
  my $db   = open_database();
  my @segments = $CONFIG->name2segments($name,$db);
  return unless @segments;
  $segments[0]->absolute(1) if param('abs');
  $segments[0];
}

sub open_database {
  my $source  = $CONFIG->source;
  return $DB{$source} if $DB{$source};
  my @argv = eval{$CONFIG->dbgff_settings};
  unless (@argv) {
    warn "gbrowse: trying to reload config, cache must be stale";
    $CONFIG = Bio::Graphics::Browser->new;
    $CONFIG->read_configuration($CONF_DIR) or message("Can't read configuration files: $!");
    $CONFIG->source($source);
    @argv = $CONFIG->dbgff_settings;
  }
  $DB{$source} = eval {Bio::DB::GFF->new(@argv)} or warn $@;
  return $DB{$source};
}

sub external_features {
  my $labels   = shift;
  my $segment  = shift;
  my @features = @_;

  my $rel2abs = coordinate_mapper($segment) if $segment;
  my $feature_list = Bio::Graphics::FeatureFile->new(-smart_features  => 1);
  for my $f (@features) {
    my ($reference,$type,$name,@position) = shellwords($f||'');
    my @segments = map { [/(-?\d+)(?:-|\.\.)(-?\d+)/]} map {split /,/} @position;
    my($ref,@parts) = $rel2abs->($reference,@segments) or next;
    my $feature = Bio::Graphics::Feature->new(
					      -ref      => $ref||'',
					      -type     => $type||'',
					      -name     => $name||'',
					      -segments => \@parts,
					     );
    $feature_list->add_feature($feature);
  }
  push @$labels,'add' unless grep {$_ eq 'add'} @$labels;
  return {add => $feature_list};
}

sub coordinate_mapper {
  my $current_segment = shift;
  my $db              = open_database();

  my ($ref,$start,$stop) = ($current_segment->seq_id,$current_segment->start,$current_segment->stop);
  my %segments;

  my $closure = sub {
    my ($refname,@ranges) = @_;

    unless ($segments{$refname}) {
      my @segments = grep {
	$_->abs_ref eq $ref && $_->abs_start <= $stop && $_->abs_stop >= $start
      } get_segment($refname);
      return unless @segments;
      $segments{$refname} = $segments[0];
    }
    my $mapper   = $segments{$refname};
    my $absref   = $mapper->abs_ref;
    my @abs_segs = map {[$mapper->rel2abs($_->[0],$_->[1])]} @ranges;

    # this inhibits mapping outside the displayed region
    foreach (@abs_segs) {
      return ($absref,@abs_segs) if $_->[0] <= $stop && $_->[1] >= $start;
    }
    return;
  };
  return $closure;
}

sub dump_sources {
  print header('text/plain');
  print "## Sources\n";
  print join "\n",$CONFIG->sources,"\n";
}

sub dump_types {
  print header('text/plain');
  print "## Feature types for source ",$CONFIG->source,"\n";
  my @labels  = $CONFIG->labels;
  my %default = map {$_=>1} $CONFIG->default_labels;
  for my $l (@labels) {
    my $d = $default{$l} ? 'default' : '';
    my $key = $CONFIG->setting($l=>'key')||'';
    print join("\t",$l,$key,$d),"\n";
  }
}

sub print_usage {
   print <<'END';

<html>
<h1>gbrowse_img - CGI script to generate genome images via the Generic Genome Browser</h1>

<h2>SYNOPSIS</h2>

<pre>

  &lt;img src="http://www.wormbase.org/db/seq/gbrowse_img?source=wormbase;name=mec-3;width=400"&gt;
<blockquote>
  <i>Will generate this picture:</i>
 <img src="http://localhost/perl/gbrowse_img?source=wormbase;name=mec-3;width=400">
</blockquote>

  &lt;a href="http://www.wormbase.org/db/seq/gbrowse_img?list=sources"&gt;list&lt;/a&gt;
<blockquote>
  <i>Will return this document:</i>
  ## Sources
  fly
  yeast
  wormbase
</blockquote>

  &lt;a href="http://www.wormbase.org/db/seq/gbrowse_img?source=list=sources"&gt;types&lt;/a&gt;
<blockquote>
  <i>Will return this document:</i>
  ## Feature types for source wormbase
  tRNA	tRNAs	
  NG	Named Genes	default
  CG	Curated genes	default
  PG	Predicted genes	
  WABA	Briggsae alignments (WABA)	
  ESTB	ESTs aligned by BLAT (best)	
  ESTO	ESTs aligned by BLAT (other)	
  mRNAB	mRNAs aligned by BLAT (best)	
  mRNAO	mRNAs aligned by BLAT (other)	
  RNAi	RNAi experiments	
  EXPR	Expression chip profiles	
  WTP	Worm Transcriptome Project genes	
  SNP	SNPs	
  TcI	Transposon Insertions
</blockquote>

</pre>

<h2>DESCRIPTION</h2>

<p>
This CGI script is an interface to the Generic Genome Browser for the
purpose of retrieving dynamic images of a region of the genome.  It
can be used as the destination of an &lt;img&gt; tag like this:
</p>

<blockquote><pre>
&lt;img src="http://www.wormbase.org/db/seq/gbrowse_img?source=wormbase;name=III:1..1000"&gt;
</pre></blockquote>

<p>

The script can also be used to superimpose one or more external
features onto the display, for example for the purpose of displaying
BLAST hits, an STS or a knockout in the context of the genome.

</p>

<h2>CGI arguments</h2>

<p>

The script recognizes the following CGI arguments, which can be passed
either as GET or POST argument=value pairs.  Argument pairs must be
separated by semicolons (preferred) or by ampersands.
</p>

<table border="1">
<tr><th>Argument</th><th>Description</th></tr>
<tr> <td>list</td>    <td>get certain types of configuration information</td></tr>
<tr> <td>source</td>  <td>database name</td></tr>
<tr> <td>name</td>    <td>genomic landmark or range</td></tr>
<tr> <td>type</td>    <td>list of feature names</td></tr>
<tr> <td>width</td>   <td>desired width of image</td></tr>
<tr> <td>options</td> <td>list of track options (compact, labeled, etc)</td></tr>
<tr> <td>add</td>     <td>additional features to superimpose on image</td></tr>
<tr> <td>abs</td>     <td>display position in absolute coordinates</td></tr>
</table>

<p>The arguments are explained in more detail here</p>

<dl>
  <dt><b>list</b>
  <dd><p>
      If this argument is present, it will cause the script to dump
      out various types of information in plain text form.  Currently the two
      values for this argument are <i>sources</i>, to dump out the list of
      data sources, and <i>types</i>, to dump out the list of configured
      types.  For <i>list=sources</i>, the script will return a simple
      text list of the data source names.  For <i>list=types</i>, the
      script will return a three-column tab-delimited list giving the
      track names and feature types corresponding to the currently-selected
      data source.  The format is as follows:
      </p>
      <blockquote>
      <pre>
      Mnemonic &lt;tab&gt; Full description of feature &lt;tab&gt; [default]
      </pre>
      </blockquote>
      <p>
      The third column contains the word "default" if the track will be shown
      by default when no <i>type</i> argument is provided.
      <p>
  <dt><b>source</b>
  <dd>This argument specifies the database for the images.  The list of sources
      can be found using <i>list=sources</i>.
      <p>
  <dt><b>name</b>
  <dd>This argument specifies the region of the genome to be displayed.  Several
      forms are recognized:
      <ul>
	<li><i>name=Landmark</i>  Display the landmark named "Landmark".  Valid landmark
	    names include chromosomes, contigs, clones, STSs, predicted genes, and any other
	    landmark that the administrator has designated.  Be careful when fetching large
	    landmarks such as whole chromosomes!
	<li><i>name=Landmark:start..end</i>  Display the region between <i>start</i> and <i>end</i>
	    relative to "Landmark".
	<li><i>name=Class:Landmark</i>  Display "Landmark", restricting to a particular class, such
	    as "PCR_Product".  The list of classes is under the control of the database administrator
	    and is not yet available through this interface.
	<li><i>name=Class:Landmark:start..end</i>  As above, but restricted to the designated range.
      </ul>
      <p>
  <dt><b>type</b>
  <dd>This argument lists the feature types to display.  The value of this argument is
      a list of mnemonics separated by spaces ("+" characters when URL-escaped).  For example:
      <p>
      <pre>
      &lt;img src="http://www.wormbase.org/db/seq/gbrowse_img?source=wormbase;name=mec-3;
                   type=tRNA+NG+WABA+CG+ESTB"&gt;
      </pre>
      Multiple <i>type=</i> arguments will be combined to form a single space-delimited list.
      <p>
  <dt><b>options</b>
  <dd>A space-delimited list ("+" characters when URL-escaped) of mnemonic/option
      pairs describing how features should be
      formatted. Options are integers from 0 to 3, where
      0=auto, 1=compact, 2=expanded, 3=expanded and labeled.  For example, to specify that
      the tRNA and NG tracks should always be expanded and labeled, but that the WABA
      track should be compact, use:
      <p>
      <pre>
      options=tRNA+3+NG+3+WABA+1
      </pre>
      <p>
  <dt><b>add</b>
  <dd>Superimpose one or more additional features on top of the view.  Features are specified
      as space ("+") delimited lists in the following format:
      <p>
      <pre>
      add=Landmark+Type+Name+start..end,start..end,start..end
      </pre>
      "Landmark" is the landmark name, "Type" is a descriptive type that will be printed
      in the image caption, "Name" is a name for the feature to be printed above it,
      and start..end is a comma-delimited list of ranges for discontinuous feature.
      Names that contain white space must be quoted, for example "BLAST hit".
      Note that this all has to be URL-escaped, so an additional
      feature named "Your Sequence", type "Blast Hit", that is located on chromosome III
      in a gapped range between 20000 and 22000, will be formatted as:
      <p>
      <pre>
      add=III+%22Blast%20Hit%22+%22Your%20Sequence%22+20000..21000,21550..22000
      </pre>
      Multiple <i>add=</i> arguments are allowed.
  <dt><b>abs</b>
  <dd>Use absolute (chromosome) coordinates when displaying the image.  An argument of
      <i>abs=1</i> will turn on absolute coordinate addressing.  An argument of
      <i>abs=0</i> will use relative coordinate addressing (this is the default).
</dl>

<h2>AUTHOR</h2>

<p>Lincoln Stein <a href="mailto:lstein@cshl.org">lstein@cshl.org</a>
<p>
Copyright (c) 2002 Cold Spring Harbor Laboratory
<p>
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
<p>

For additional help, see <a href="http://www.gmod.org">The GMOD Project</a> pages.

END
;
}


!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;
