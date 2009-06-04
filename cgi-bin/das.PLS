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

# In the following, perl variables are not expanded during extraction.

print OUT <<'!NO!SUBS!';
#$Id: das.PLS,v 1.6.8.1.2.14 2009-06-04 21:52:11 lstein Exp $

use strict;
use Bio::DB::GFF;
use File::Basename 'basename';
use CGI qw/header path_info param url request_method escapeHTML/ ;
use Carp;
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Util;
use File::Spec;
use Date::Parse;
use Date::Format;
use vars qw($DB $DSN $TRACK $HEADER %ERRCODES $CONFIG
            $VERSION $DAS_VERSION $CONF_DIR 
            $SO_FETCH %SO_HASH %TYPE2SUBTYPES
            %CACHED_TYPES %FORCED_GROUP %NO_PARENT);

use constant SO => 'http://song.cvs.sourceforge.net/viewvc/*checkout*/song/ontology/so.obo';
use constant DEBUG => 0;

#$Id: das.PLS,v 1.6.8.1.2.14 2009-06-04 21:52:11 lstein Exp $

# minimal DAS annotation/reference server
$DAS_VERSION = 'DAS/1.50';
use constant CAPABILITIES => join '; ',qw(error-segment/1.0 unknown-segment/1.0 unknown-feature/1.0
					  feature-by-id/1.0 group-by-id/1.0 sources/1.0
                                          dna/1.0 features/1.0 stylesheet/1.1 types/1.0
                                          entry_points/1.0 dsn/1.0 sequence/1.0
                                          );

(my $BASENAME = url(-absolute=>1)) =~ s!http://[^/]+/!!;
%ERRCODES = (
	     200 => 'OK',
	     400 => 'Bad command',
	     401 => 'Bad data source',
	     402 => 'Bad command arguments',
	     403 => 'Bad reference object',
	     404 => 'Bad stylesheet',
	     405 => 'Coordinate error',
	     500 => 'Internal server error (oops)',
	     501 => 'Unimplemented feature',
	     );
$CONFIG = open_config($CONF_DIR) or error_header('Could not read config files'=> 500);
$HEADER = 0;
%FORCED_GROUP = ();
%NO_PARENT    = ();

warn "[$$] RUN(): ",
    CGI::request_method(),': ',
    CGI::url(-path=>1),' ',
    CGI::query_string() if DEBUG;


my ($junk,$dsn,$operation) = split '/',path_info();

$DSN = $dsn;
if ($DSN =~ /(.+)\|(.+)/) { # composite
    $DSN   = $1;
    $TRACK = $2;
}

$operation ||= '';
my %sources = map {$_=>1} $CONFIG->sources;

do { error_header('please append a command such as /types, to this URL',400); exit 0 } unless $DSN;
do { list_dsns();      exit 0 } if $dsn eq 'dsn'     or $operation eq 'dsn';
do { list_sources();   exit 0 } if $dsn eq 'sources' or $operation eq 'sources';
do { error_header('invalid data source; use the sources or dsn command to get list',401); exit 0 } 
      unless $sources{$DSN};
$CONFIG->source($DSN);

do { error_header('invalid data source; use the sources or dsn command to get a list',401); exit 0}
     if $TRACK && !$CONFIG->setting($TRACK=>'das category');

do { error_header('Could not open database',500); exit 0 }
     unless $DB = open_database();

do { entry_points(); exit 0 }      if $operation eq 'entry_points';
do { types();        exit 0 }      if $operation eq 'types';
do { features();     exit 0 }      if $operation eq 'features';
do { stylesheet();   exit 0 }      if $operation eq 'stylesheet';
do { dna();          exit 0 }      if $operation eq 'dna';

error_header('invalid request; please append a command such as /types to this URL',400);
exit 0;

# -----------------------------------------------------------------
sub list_dsns {
  my $j = ' 'x3;
  ok_header();
  print qq(<?xml version="1.0" standalone="yes"?>\n<!DOCTYPE DASDSN SYSTEM "http://www.biodas.org/dtd/dasdsn.dtd">\n);
  my $self_url = url(-full=>1);
  $self_url    =~ s/dsn.*$//;

  print "<DASDSN>\n";

  for my $dsn (sort $CONFIG->sources) {
    my $old_source = $CONFIG->source($dsn);
    if (my $mapmaster = $CONFIG->setting('das mapmaster')) {
      $mapmaster = "$self_url/$dsn" if $mapmaster eq 'SELF';
      for my $track ($CONFIG->labels) {
	  next if $track =~ /:/;
	  next unless $CONFIG->setting($track=>'das category');
	  my $citation    = $CONFIG->citation($track);
	  my $key         = $CONFIG->setting($track=>'key');
	  my $description = $CONFIG->description($dsn)."; $track track";
	  $description   .= "; $key"      if $key;
	  $description   .= "; $citation" if $citation;
	  print "$j<DSN>\n";
	  print qq($j$j<SOURCE id="$dsn|$track">$dsn|$track</SOURCE>\n);
	  print qq($j$j<MAPMASTER>),$mapmaster,qq(</MAPMASTER>\n);
	  print qq($j$j<DESCRIPTION>),$description,qq(</DESCRIPTION>\n);
	  print "$j</DSN>\n";
      }
    }
    $CONFIG->source($old_source);
  }
  print "</DASDSN>\n";
}

sub list_sources {
  my $j = ' 'x3;
  ok_header();
  print <<END;
<?xml version='1.0' encoding='UTF-8' ?>
END


  my $self_url = url(-full=>1);
  $self_url    =~ s/sources.*$//;

  my $old_source = $CONFIG->source();
  
  print "<SOURCES>\n";

 SOURCE:
  for my $dsn (sort $CONFIG->sources) {
      $CONFIG->source($dsn);
      my $sourceinfo = $CONFIG->setting('das source') or next;
      my %a = $sourceinfo =~ m/-(\w+)\s+([^-].+?(?=\s|$))/g;
      for (keys %a) { $a{$_} =~ s/\s+$// }; # trim
      for (qw(maintainer created coordinates authority source testrange)) {
	  next if exists $a{$_};
	  warn "'das source' option requires mandatory '$_' field; skipping\n";
	  next SOURCE;
      }
      
      my $created;
      {
	  local $^W = 0;  # to quench uninit warnings from Date::Parser
	  my @time    = strptime($a{created});
	  @time       = localtime unless @time;
	  $created = strftime("%Y-%m-%dT%T%z",@time) || '';
      }
      my $version = $a{version} || $a{coordinates_version} || '';
      for my $track ($CONFIG->labels) {
	  next if $track =~ /:/;
	  next unless $CONFIG->setting($track=>'das category');
	  my $citation    = $CONFIG->citation($track);
	  my $key         = $CONFIG->setting($track=>'key');
	  my $title       = $CONFIG->description($dsn);
	  my $description = $CONFIG->description($dsn)."; $track track";
	  $description   .= "; $key"      if $key;
	  $description   .= "; $citation" if $citation;
	  my $authority   = $a{authority};
	  $authority     .= "_$version" if $version;
	  my $base        = url();

	  my $uri = CGI::escape($dsn).'|'.CGI::escape($track);
	  
	  print <<END;
     <SOURCE uri="$uri" title="$key" description="$description">
        <MAINTAINER email="$a{maintainer}" />
        <VERSION uri="$dsn|$track" created="$created">
  	  <COORDINATES uri="$a{coordinates}" authority="$a{authority}" test_range="$a{testrange}" taxid="$a{taxid}" version="$version">$authority,$a{source},$a{species}</COORDINATES>
END
;
	  for ('types','features','entry_points','stylesheet') {
	      print <<END;
          <CAPABILITY type="das1:$_" query_uri="$base/$dsn|$track/$_" />
END
	  }
	  print  <<END;
        </VERSION>
     </SOURCE>
END
      }
  }
  print "</SOURCES>\n";
  $CONFIG->source($old_source);
}

# -----------------------------------------------------------------
sub dna {
  my $segments = get_segments();

  ok_header();
  print qq(<?xml version="1.0" standalone="yes"?>\n);
  print qq(<!DOCTYPE DASDNA SYSTEM "http://www.wormbase.org/dtd/dasdna.dtd">\n);
  print qq(<DASDNA>\n);
  for my $segment (@$segments) {
    my ($reference,$refclass,$start,$stop) = @$segment;
    my @seq = get_segment_obj($reference,$refclass,$start,$stop);
    error_segment($reference,$start,$stop) unless @seq;

    for my $obj (@seq) {
      my $dna = $obj->dna;
      my $length = length $dna;
      $dna =~ s/(.{60})/$1\n/g;
      my $ref = $obj->ref;
      my $s   = $obj->start;
      my $e   = $obj->end;
      print <<END
<SEQUENCE id="$ref" start="$s" stop="$e" version="1.0">
<DNA length="$length">
$dna
</DNA>
</SEQUENCE>
END
    }
  }
  print qq(</DASDNA>\n);
}

# -----------------------------------------------------------------
sub entry_points {
  my $segments = get_segments();

  my @parts;
  my @type_filter = map {$CONFIG->label2type($_)}
    grep {$CONFIG->setting($_=>'das landmark')}
      $CONFIG->labels;

  my ($category2type,$type2category) = categories($CONFIG);
  my $refclass = $CONFIG->setting('das entry point') || $CONFIG->setting('reference class') || 'Chromosome';

  if ($segments) {
    @parts = map { get_segment_obj(@$_) } @$segments;
    @parts = map { $_->contained_features(-types=>\@type_filter,-merge=>0) } @parts;
  } else {
    @parts = $DB->features(-types=>\@type_filter) if @type_filter;
    push @parts,$DB->get_feature_by_name($refclass=>'*');
    # last ditch effort if we've got nothing
    push @parts,$DB->features(-type=>$refclass) unless @parts;
  }

  my $url = get_url();

  ok_header();
  print <<END;
<?xml version="1.0" standalone="no"?>
<!DOCTYPE DASEP SYSTEM "http://www.biodas.org/dtd/dasep.dtd">
<DASEP>
<ENTRY_POINTS href="$url" version="1.0">
END
;

  my %seenit;
  for my $part (@parts) {
    # I dunno, consider putting this back in for reference servers?
    # next unless $part->ref eq $part->group;
    $part->absolute(1);
    my $name  = $part->name;
    next if $seenit{$name}++;
    my $st    = $part->start;
    my $en    = $part->stop;
    my $class = $part->class;
    my $length = $part->length;
    my $orientation = $part->strand >= 0 ? '+' : '-';
    my $subparts    = $type2category->{__subparts__}{$part->type} ? 'yes' : 'no';
    print qq(<SEGMENT id="$name" size="$length" start="$st" stop="$en" class="$class" orientation="$orientation" subparts="$subparts">$name</SEGMENT>\n);
  }
  print "</ENTRY_POINTS>\n</DASEP>\n";
}

# -----------------------------------------------------------------
# get the features for the segment indicated
sub features {
  my @segments = get_segments();

  my $summary  = param('summary');
  my $url      = get_url();
  my @filter   = param('type');
  my @category = param('category');

  my ($category2type,$type2category,$top_types) = categories($CONFIG);
  my %valid_types = map {$_=>1} @$top_types;

  unless (@filter || @category) {
    @filter = @$top_types;
  }

  push @filter,map {exists $category2type->{$_}
		    ? @{$category2type->{$_}} 
		    : $_ 
                    } @category;
  my @tracks = $TRACK ? $TRACK : $CONFIG->labels;
  @filter = map  {shellwords($CONFIG->setting($_ => 'feature'))} 
           @tracks unless @filter && !$TRACK;
  @filter = grep {$valid_types{$_}} @filter;

  ok_header();
  print <<END
<?xml version="1.0" standalone="yes"?>
<!DOCTYPE DASGFF SYSTEM "http://www.biodas.org/dtd/dasgff.dtd">
<DASGFF>
<GFF version="1.01" href="$url">
END
;

  foreach (@segments) {
    my ($reference,$refclass,$start,$stop) = @$_;

    my @segs = get_segment_obj($reference,$refclass,$start,$stop);
    error_segment($reference,$start,$stop) unless @segs;

    for my $seq (@segs) {
      dump_segment($seq,\@filter,undef,$type2category);
    }
  }

  # dump feature requests, if any
  for my $id (param('feature_id'),param('group_id')) {
    my @segments = get_feature_obj($id);
    error_id($id) unless @segments;
    foreach (@segments) {
      $_->absolute(1);
    }
    my @exact_matches = grep {$id eq $_->display_name} @segments;
    my @to_dump       = @exact_matches ? @exact_matches : @segments;
    dump_segment($_,\@filter,'toplevel') foreach @to_dump;
  }

print <<END;
</GFF>
</DASGFF>
END
}

sub dump_segment {
  my $seq           = shift;
  my $filter        = shift;
  my $toplevel      = shift;
  my $type2category = shift;

  my $r = $seq->seq_id;
  my $s = $seq->start;
  my $e = $seq->stop;
  ($s,$e) = ($e,$s) if $s > $e;

  my %subparts     = map {$_=>1} map {$CONFIG->label2type($_)}
    grep {$CONFIG->setting($_=>'das subparts')}
      $CONFIG->labels;
  my %superparts     = map {$_=>1} map {$CONFIG->label2type($_)}
    grep {$CONFIG->setting($_=>'das superparts')}
      $CONFIG->labels;

  my $version = seq2version($r);
  if ($toplevel) {
    print qq(<SEGMENT id="$r" start="$s" stop="$e" version="$version" />\n);
    return;
  }
  print qq(<SEGMENT id="$r" start="$s" stop="$e" version="$version">\n);

  my %agg_map;
  if ($DB->can('aggregators')) {
    %agg_map = map {($_->get_method||'') => ($_->main_name||'')} $DB->aggregators;
  }

  if (@$filter) {
    my $iterator = $seq->features(-types=>$filter,-merge=>1,-iterator=>1);
    while (my $f = $iterator->next_seq) {
	print_feature($f,undef,transmute($f->type,$type2category),\%agg_map);
    }
  }

  print qq(</SEGMENT>\n);
}

sub print_feature {
    my $f             = shift;
    my $parent        = shift;
    my $category      = shift;
    my $agg_map       = shift;
    my $count         = shift || 0;
    my $group         = shift || $parent || $f;
    my $level         = shift || 0;
    my $sequence      = shift || 0;

    my @subparts     = $f->get_SeqFeatures;
    my $no_parent    = @subparts && no_parent_wanted($f);

    _print_feature($f,
		   $parent,
		   $category,
		   $agg_map,
		   $count,
		   $group,
		   $level,
		   $sequence,
	)
	unless $no_parent;

    print_feature($_,
		  ($no_parent ? undef : $f),
		  $category,
		  $agg_map,
		  ++$count,
		  $group,
		  $level+1,
		  $sequence++,
	) foreach @subparts;
}

sub _print_feature {
  local $^W = 0; # kill some uninit variable warnings

  my $f             = shift;
  my $parent        = shift;
  my $category      = shift;
  my $agg_map       = shift || {};
  my $count         = shift;
  my $group         = shift;
  my $level         = shift || 0;
  my $sequence      = shift || 0;

  my $flabel      = $f->display_name;
  my $source      = $f->source;
  my $method      = $f->method;
  my $start       = $f->start;
  my $end         = $f->stop;
  my $score       = $f->score;
  my $orientation = $f->strand || 0;
  my $phase       = $f->phase;

  my $type        = guess_type($f);
  my $typelabel   = $f->type;

  my $pid         = feature2id($parent) if $parent;
  my $id          = feature2id($f) || $pid;
  $id            .= ".$sequence" if $id eq $pid;
  my $counter     = 0;
  my @child_ids   = map {feature2id($_)||"$id.".$counter++} $f->get_SeqFeatures;

  my @notes       = $f->notes if $f->can('notes');
  my %attributes  = $f->attributes if $f->can('attributes');

  my $gclass;
  if ($f->can('group')) { # Bio::DB::GFF feature
    $gclass      = (ref($group) && $group->can('class')) 
	               ? $group->class 
		       : 'anonymous';
  } else {
    $gclass      = '';
  }

  my $group_type  = forced_group($parent||$f) || $type;

  $group_type     =~ s/\:\w+$//;

  # This is way nasty.  The aggregator may have changed the method of the
  # main feature, so we need to change it back to what it was originally
  # for the purpose of serializing on the net.  What amazing shortsightedness
  # on the part of someone who should know better.
  $method = $agg_map->{$method} if defined $agg_map->{$method};
	
  $phase       ||= 0;
  $orientation ||= 0;
  $score       = '-' unless defined $score;
  $orientation = $orientation >= 0 ? '+' : '-';

  ($start,$end) = ($end,$start) 
      if defined($start) && defined($end) && $start > $end;

  # group stuff
  my $groupid       = $group->primary_id;
  my $grouplabel    = $group->display_name;
  my ($group_info,$link,$gtype,$url);

  $url = $CONFIG->make_link($f);
  $url  ||= 'none';
  if ($url ne 'none') {
      hack_link(\$url);
      $link = qq(<LINK href="$url">$flabel</LINK>);
  }
  if (@child_ids) {
      my $track = $TRACK || $CONFIG->feature2label($group);
      my $glyph = $CONFIG->fallback_setting($track=>'glyph');
      $gtype    = " type='$type'";
  }

  if (%attributes) {
    for my $tag (keys %attributes) {
	next if $tag =~ /parent_id/ || $tag =~ /load_id/;
	my @values = ref($attributes{$tag}) ? @{$attributes{$tag}} : $attributes{$tag};
	$group_info .= qq(\n\t<NOTE tag="$tag">$_</NOTE>) foreach @values;
    }
  } elsif (@notes) {
      $group_info = join "\n",map {qq(<NOTE>$_</NOTE>)} @notes;
  }

  my ($target,$target_info);
  if (($target = $f->target) && $target->can('start')) {
    my $start = $target->start;
    my $stop  = $target->stop;
    my $seqid = $target->ref;
    $target_info = qq(<TARGET id="$seqid" start="$start" stop="$stop" />);
  }
	
  my ($map,$type2category);
  $map = qq() ;

  $start ||= '';  $end ||= '';

  print <<END;
   <FEATURE id="$id" label="$flabel">
      <TYPE id="$type" category="$category"$map>$typelabel</TYPE>
      <METHOD id="$method">$method</METHOD>
      <START>$start</START>
      <END>$end</END>
      <SCORE>$score</SCORE>
      <ORIENTATION>$orientation</ORIENTATION>
      <PHASE>$phase</PHASE>
END
;
  print qq(      <PARENT id="$pid"/>\n)  if defined $pid;
  print qq(      <PART   id="$_"/>\n)    foreach @child_ids;
  print qq(      $link\n)                if $link;
  print qq(      $target_info\n)         if $target_info;

  if (defined $groupid) {
    $gtype     ||= '';
    if ($group_info) {
      print qq(      <GROUP id="$groupid" label="$grouplabel" $gtype>\n);
      print qq(        $group_info\n)  if $group_info;
      print qq(      </GROUP>\n);
    } else {
      print qq(      <GROUP id="$groupid"$gtype/>\n);
    }
  }
  print <<END;
   </FEATURE>
END
    ;
}

sub error_segment {
  my ($reference,$start,$stop) = @_;
  my $mapmaster     = $CONFIG->setting('das mapmaster');
  my $authoritative = $mapmaster && $mapmaster eq (url(-full=>1) . "/".$CONFIG->source);
  my $tag = $authoritative ? 'ERRORSEGMENT' : 'UNKNOWNSEGMENT';
  my $attributes = '';
  $attributes .= qq( start="$start") if defined $start;
  $attributes .= qq( stop="$stop")   if defined $stop;
  print qq(    <$tag id="$reference"$attributes />\n);
}

sub error_id {
  my $id = shift;
  print qq(    <UNKNOWNFEATURE id="$id" />\n);
}

sub feature2id {
    my $f     = shift;

    my $id = $f->primary_id;
    # HACK
    $id             = unpack('L',$id)
	if ref($DB) eq 'Bio::DB::GFF::Adaptor::berkeleydb';
    return $id;
}

sub dump_components {
  my ($reference,$refclass,$reqstart,$reqend,$type2category) = @_;
  my @seq = grep {lc($_->abs_ref) eq lc($reference)} get_segment_obj($reference,$refclass,$reqstart,$reqend);

  error_segment($reference,$reqstart,$reqend) ;

  for my $seq (@seq) {
    $seq->absolute(1);
    my $refseq = $seq->refseq;
    my $start = defined $reqstart ? $reqstart : $seq->start;
    my $stop  = defined $reqend   ? $reqend   : $seq->end;

    my $component_type = 'superparts';

    my @types = keys %{$type2category->{__superparts__}} or return;

    my @parts = $seq->contained_features(-type=>\@types,-merge=>0);
    @parts    = grep { $_->name ne $refseq } @parts;

    my $version = seq2version($refseq);
    print qq(<SEGMENT id="$refseq" start="$start" stop="$stop" version="$version">\n);

    for my $part (@parts) {

      my $length = $part->length;
      my ($start,$end,$tstart,$tend,$targetid);

      ($start,$end)   =  ($part->start,$part->stop);
      if (my $target = $part->target) {
	($tstart,$tend) =  ($target->start,$target->end);
      } else {
	($tstart,$tend) = (1,$length);
      }
      $targetid = $part->target || $part->info;


      my $orientation = $part->strand >= 0 ? '+1' : '-1';
      my $type   = $part->type;
      my $method = $type->method;
      my $description = qq(category="component" reference="yes");
      my ($has_subparts,$has_superparts) = describe_component($type,$type2category);

      $description .= qq( subparts="yes")   if $has_subparts;
      $description .= qq( superparts="yes") if $has_superparts;
      my $id = $part->info;

      if ($tstart > $tend) {
	$orientation = '-1';
	($tstart,$tend) = ($tend,$tstart);
      }

      # avoid giving out information on nonrequested parts
      if (defined($reqstart) && defined($reqend)) {
	next unless $start <= $reqend && $end >= $reqstart;
      }

      my $part_id = $part->name;
    print <<END
   <FEATURE id="$id" label="$part_id">
      <TYPE id="$type" $description>$part_id</TYPE>
      <METHOD id="$method">$method</METHOD>
      <START>$start</START>
      <END>$end</END>
      <SCORE>-</SCORE>
      <ORIENTATION>$orientation</ORIENTATION>
      <PHASE>-</PHASE>
      <TARGET id="$targetid" start="$tstart" stop="$tend">$part_id</TARGET>
   </FEATURE>
END
  ;
    }
    print qq(</SEGMENT>\n);
  }
}

sub types {
  return all_types() unless param('ref') or param('segment');

  my ($category2type,$type2category,$types) = categories($CONFIG);

  my $summary = param('summary');
  my $url     = get_url();
  my @filter  = param('type');
  unless (@filter) {
      @filter = @$types;
  }

  my @segments = get_segments() or return;

  ok_header();

  print <<END;
<?xml version="1.0" standalone="yes"?>
<!DOCTYPE DASTYPES SYSTEM "http://www.biodas.org/dtd/dastypes.dtd">
<DASTYPES>
<GFF version="1.2" summary="yes" href="$url">
END
;

  foreach (@segments) {
    my ($reference,$class,$start,$stop) = @$_;
    next unless $reference;
    my ($seq) = get_segment_obj($reference,$class,$start,$stop) or next;
    unless ($seq) {  #empty section
      my $version = seq2version($reference);
      print qq(<SEGMENT id="$reference" start="$start" stop="$stop" version="$version">\n);
      print qq(</SEGMENT>\n);
      next;
    }

    my $s = $seq->start;
    my $e = $seq->stop;

    # use absolute coordinates -- people expect it
    my $name = $seq->seq_id;

    my $version = seq2version($name);
    print qq(<SEGMENT id="$name" start="$s" stop="$e" version="$version">\n);

    my @args = (-enumerate=>1);
    push @args,(-types=>\@filter) if @filter;
    my %histogram = $seq->types(@args);
    foreach (keys %histogram) {
      my ($method,$source) = split ':';
      my $count = $histogram{$_};
      my $category  = transmute($_,$type2category);
      $category ||= '';  #get rid of uninit variable warnings
      $method   ||= '';
      $source   ||= '';
      $count    ||= 0;
      (my $type  = $_) =~ s/:[^:]+$//;
      my $id    = type2so($type);
      print qq(\t<TYPE id="$id" category="$category" method="$method" source="$source">$count</TYPE>\n);
    }
    print qq(</SEGMENT>\n);
  }
print <<END;
</GFF>
</DASTYPES>
END
}

sub type2so {
    my $type    = shift;
    my ($track) = $CONFIG->type2label($type);
    return $type unless $CONFIG->fallback_setting($track=>'das use so');
    my $hash = so_hash() or return $type;
    return $hash->{lc $type} || $type;
}

# list of all the types
sub all_types {
  my ($category2type,$type2category,$types) = categories($CONFIG);
  ok_header();
  my $url = get_url();
  print <<END;
<?xml version="1.0" standalone="yes"?>
<!DOCTYPE DASTYPES SYSTEM "http://www.biodas.org/dtd/dastypes.dtd">
<DASTYPES>
<GFF version="1.2" summary="yes" href="$url">
<SEGMENT>
END
    ;

  for my $t (@$types) {
    my $category = transmute($t,$type2category);
    my $typeobj  = Bio::DB::GFF::Typename->new($t);
    my $method   = $typeobj->method;
    my $source   = $typeobj->source;
    my $id = $t;


    my ($track)  = $CONFIG->type2label($t);
    $id          = type2so($id);
    print qq(\t<TYPE id="$id" category="$category" method="$method" source="$source" />\n);
  }

  print <<END
</SEGMENT>
</GFF>
</DASTYPES>
END
    ;

}

sub stylesheet {
  my $config = $CONFIG;
  my ($category2type,$type2category) = categories($config);

  my %default_style       = $config->config->default_style;
  $default_style{-link} ||= $config->setting(general=>'link');

  ok_header();
  print <<END;
<?xml version="1.0" standalone="yes"?>
<!DOCTYPE DASSTYLE SYSTEM "http://www.biodas.org/dtd/dasstyle.dtd">
<DASSTYLE>
<STYLESHEET version="1.0">
END
;

  local $^W=0;

  for my $cat ('default',keys %{$category2type}) {

    print qq(  <CATEGORY id="$cat">\n);

    my (%seenit,%doneit);

    my @types = grep {!$seenit{$_}++} exists $category2type->{$cat} 
                       ? @{$category2type->{$cat}} 
                       : 'default';

    for my $toplevel (@types) {
	
	my $subtypemap     = expand_types($toplevel);
	
	for my $type ('default',keys %$subtypemap) {

	    my $label =  $type eq 'default' ? 'TRACK DEFAULTS'
		: $type2category->{__label__}{$toplevel} || $CONFIG->type2label($toplevel);

	    my $forced_type = $CONFIG->setting($label=>'das type');
	    my $typeid = $type eq 'default' 
		           ? 'default' 
			   : ($forced_type || guess_type($type));
	    next if $doneit{$typeid}++;

	    my ($glyph,%style);

	    my %type_style = $config->config->style($label);
	    %style = (%default_style,map {ref $type_style{$_}
					  ?()
					      :($_=>$type_style{$_})
		      } keys %type_style);
	    delete $style{-feature};
	    delete $style{-feature_low};
	    delete $style{-link} if $style{-link} eq 'AUTO';

	    my $parts = $subtypemap->{$type};

	    if ($parts > 0) { # a group!
		next unless $cat eq 'group';
		$glyph = guess_glyph($style{-glyph},1);
		if ($style{-glyph} eq 'gene' && $type eq $toplevel) {
		    $glyph = 'HIDDEN' ;
		    %style = ();
		}
	    }
	    else {
		next if $cat eq 'group';
		$glyph = $style{'-das glyph'} || guess_glyph($style{-glyph} || 'box');
	    }

	    print qq(     <TYPE id="$typeid" label="$type">\n);

	    print qq(        <GLYPH>\n);
	    print qq(           <\U$glyph\E>\n);
	    for my $attribute (keys %style) {
		(my $name = $attribute) =~ s/^-//;
		$name =~ s/\s/_/g;
		next if $name =~ /glyph|category|das/;
		my $value = escapeHTML($style{$attribute});
		print qq(              <\U$name\E>$value<\U/$name\E>\n);
	    }
	    print qq(           </\U$glyph\E>\n);
	    print qq(        </GLYPH>\n);
	    print qq(     </TYPE>\n);
	}
    }

    print qq(  </CATEGORY>\n);
  }
  
  print <<END;
</STYLESHEET>
</DASSTYLE>
END
;
}

sub guess_glyph {
    my $suggested_glyph = shift;
    my $group           = shift;

    my $class = "Bio::Graphics::Glyph::$suggested_glyph";

    eval "require $class" unless $class->can('new');
    if ($group) {
	return $class->isa('Bio::Graphics::Glyph::transcript') ? 'HAT'
	      : $class->isa('Bio::Graphics::Glyph::cds')       ? 'HAT'
	      : 'LINE';
    } else {
	return $class->isa('Bio::Graphics::Glyph::arrow')        ? 'ARROW'
	    :$class->isa('Bio::Graphics::Glyph::anchored_arrow') ? 'ANCHORED_ARROW'
	    :$class->isa('Bio::Graphics::Glyph::crossbox')       ? 'CROSS'
	    :$class->isa('Bio::Graphics::Glyph::ex')             ? 'EX'
	    :$class->isa('Bio::Graphics::Glyph::line')           ? 'LINE'
	    :$class->isa('Bio::Graphics::Glyph::segments')       ? 'LINE'
	    :$class->isa('Bio::Graphics::Glyph::span')           ? 'SPAN'
	    :$class->isa('Bio::Graphics::Glyph::text_in_box')    ? 'TEXT'
	    :$class->isa('Bio::Graphics::Glyph::toomany')        ? 'TOOMANY'
	    :$class->isa('Bio::Graphics::Glyph::triangle')       ? 'TRIANGLE'
	    :$class->isa('Bio::Graphics::Glyph::primers')        ? 'PRIMERS'
	    :'BOX';
    }
}

# calculate type and category from type and method
sub transmute {
  my $type = shift;
  my $map  = shift;

  # try fast exact match first
  return $map->{$type} if exists $map->{$type};

  # otherwise do a fuzzy match
  for my $typeobj (values %{$map->{__fuzzy__}}) {

    if ($typeobj->match($type)) {
      my $category  = $map->{$typeobj};   # fetch category for this object
      $map->{$type} = $category;          # remember exact match for later
      return $category;
    }
  }
  return 'miscellaneous';  # no success
}

# -----------------------------------------------------------------
sub forced_group {
  my $feature = shift;
  return unless $feature;
  my $type = $feature->type;
  return $FORCED_GROUP{$type} if exists $FORCED_GROUP{$type};
  my $forced_group;
  my $label = $CONFIG->type2label($type);
  unless ($label) {
    $type =~ s/:\w+//;
    $label = $CONFIG->type2label($type);
  }
  $forced_group = $CONFIG->setting($label => 'das type') if $label;
  return $FORCED_GROUP{$type} = $forced_group;
}

sub no_parent_wanted {
  my $feature = shift;
  return unless $feature;
  my $type = $feature->type;
  return $NO_PARENT{$type} if exists $NO_PARENT{$type};
  my $no_parent;
  my $label = $CONFIG->type2label($type);
  unless ($label) {
    $type =~ s/:\w+//;
    $label = $CONFIG->type2label($type);
  }
  $no_parent = $CONFIG->setting($label => 'das flatten')
                || $CONFIG->setting('TRACK DEFAULTS' => 'das flatten')
	       if $label;
  return $NO_PARENT{$type} = $no_parent;
}

# -----------------------------------------------------------------
sub get_url {
  my $url = url(-path=>1, -query=>1);
  $url =~ tr/&/\;/;
  return $url;
}

sub seq2version {
  my $seqname = shift;
  return $seqname =~ /\.(\d+)$/ ? $1 : '1.0';
}

# -----------------------------------------------------------------
sub error_header {
  my ($message,$code) = @_;
  $code ||= 500;
  print header(-type          =>'text/plain',
	       -X_DAS_Version => $DAS_VERSION,
	       -X_DAS_Status  => $code,
	       -X_DAS_Capabilities => CAPABILITIES,
	      ) unless $HEADER++;
  return if request_method() eq 'HEAD';
  print $message;
}

sub ok_header {
  print header(-type          =>'text/xml',
	       -X_DAS_Version => $DAS_VERSION,
	       -X_DAS_Status  => "200",
	       -X_DAS_Capabilities => CAPABILITIES,
	      ) unless $HEADER++;
}

# phony dtd
sub dtd {
    ok_header();
    print <<DTD;
<!-- phony dtd for debugging parsers -->
DTD
}

# -----------------------------------------------------------------
sub get_segments {
  # extended segment argument
  my @segments;
  foreach (param('segment')) {
    my ($ref,$start,$stop) = /^(\S+?)(?::(\d+)(?:\.\.|,)(\d+))?$/;
    push @segments,[$ref,$start,$stop];
  }
  push @segments,[scalar param('ref'),
		  scalar param('start'),
		  scalar param('stop')] if param('ref');
  return unless @segments;

  foreach (@segments){
    my ($reference,$start,$stop) = @$_;
    my $class = $CONFIG->setting('reference class') || 'Sequence';
    my $name  = $reference;

    if ($reference =~ /^(\w+):(\S+)$/) {
      $class = $1;
      $name  = $2;
    }
    my @values = ($name,$class,$start,$stop);
    $_ = \@values;
  }

  return wantarray ? @segments : \@segments;
}

# -----------------------------------------------------------------
sub get_feature_obj {
  my $id = shift;
  if ($id =~ m!^(.+)/(\d+)$!) {
    return $DB->fetch_feature_by_id($2);
  } elsif ($id =~ /^(\w+):(\S+)$/) {
    return $DB->segments($1 => $2);
  }  else {
    return $DB->segments($id);
  }
}

# -----------------------------------------------------------------
sub get_segment_obj {
  my ($reference,$class,$start,$stop,$as_feature) = @_;
  my @args = (-name=>$reference);
  push @args,(-class=>$class) if defined $class;
  push @args,(-start=>$start) if defined $start;
  push @args,(-stop=>$stop)   if defined $stop;


  # the "feature" flag is used when we are looking for supercomponents
  # and we want to fetch the segment as a feature object so as to find its parent
  if ($as_feature) {
    my @segments = $DB->fetch_feature(@args);
    warn $DB->error unless @segments;
    @segments;
  }

  else {
    my @segments = $DB->segment(@args);
    my @s = grep {$_->abs_ref eq $reference} @segments;
    return @s if @s;
    return @segments;
  }
}

sub das_die { my $message = shift; my $message2 = shift;
  warn $message;
  do { error_header("Configuration error: ".($message2||$message),500); exit 0 } 
}

sub categories {
  my $config = shift;
  my $dsn    = $config->source;
  return @{$CACHED_TYPES{$dsn}} if exists $CACHED_TYPES{$dsn};

  my (%category2type,%type2category,@types);
  my @labels = $config->labels;

  for my $label (@labels) {
      next if $TRACK && $TRACK ne $label;
      my $category       = $config->setting($label=>'das category');
      my $has_subparts   = $config->setting($label=>'das subparts');
      my $has_superparts = $config->setting($label=>'das superparts');
      my $structural     = $config->setting($label=>'das landmark') ||
	  $has_subparts || $has_superparts;
	
      $category ||= 'structural' if $structural;
      next unless $category;  # skip sections without a category marked

      my @composite_types = $config->label2type($label);

      push @types,@composite_types;
      my $t   = Bio::DB::GFF->parse_types(@composite_types);

      if ($DB->can('aggregators')) {
	  $_->disaggregate($t,$DB) foreach $DB->aggregators;
      }
      my @t = map {defined($_->[1]) ? join(':',@$_) : $_->[0]} @$t;

      my %seenit;
      my @all_types = grep {!$seenit{$_}++} @t,@composite_types;

      push @{$category2type{$category}},    (@composite_types,@all_types);
      push @{$category2type{'group'}},      (@composite_types,@all_types);
      $type2category{$_} = $category foreach @composite_types;

      for my $type (@all_types) {

	  $type2category{$type} = $category;
	  my $typeobj      = Bio::DB::GFF::Typename->new($type);
	  $type2category{__label__}{$type}      = $label;
	  $type2category{__fuzzy__}{$typeobj}   = $typeobj;
	  $type2category{__subparts__}{$type}++   if $has_subparts;
	  $type2category{__superparts__}{$type}++ if $has_superparts;
      }
  }
  $CACHED_TYPES{$dsn} = [\(%category2type,%type2category,@types)];
  return @{$CACHED_TYPES{$dsn}};
}

# unfortunately, the gbrowse library returns a relative address
# for AUTO links
sub hack_link {
  my $url_ref = shift;
  return unless $$url_ref =~ /^\.\./;
  my $self_url = url(-full=>1);
  $self_url =~ s!/das(/.+)?!!;
  $$url_ref =~ s!^(\.\.\/)+!!;
  $$url_ref = $self_url."/$$url_ref";
}

sub guess_type {
    my $feature  = shift;
    my $type     = ref $feature ? $feature->method : $feature;

    my $track    = $TRACK || $CONFIG->feature2label($feature);

    return $type unless $CONFIG->fallback_setting($track=>'das use so');

    my $glyph    = $CONFIG->fallback_setting($track=>'glyph');
    my $hash     = so_hash() or return $type;
    return $hash->{lc $type} || $type;
}

sub so_hash {
    return \%SO_HASH if tied %SO_HASH;

    my $so_file = File::Spec->catfile(File::Spec->tmpdir,'SO.obo');
    my $so_hash = File::Spec->catfile(File::Spec->tmpdir,'SO.db');

    fetch_sofile($so_file) or return unless -e $so_file;

    eval 'use DB_File' unless DB_File->can('new');
    eval 'use Fcntl'   unless Fcntl->can('O_CREAT');

    hash_sofile($so_file,$so_hash)
	or return unless -e $so_hash && 
	                 (stat($so_hash))[9] >= (stat($so_file))[9];
    tie %SO_HASH,'DB_File',$so_hash,Fcntl->O_RDONLY,0666,$DB_File::DB_HASH or return;    
    return \%SO_HASH;
}

sub fetch_sofile {
    return if $SO_FETCH++; # only try once per session

    my $so_file = shift;
    my $so_url  = SO;
    require 'LWP::Simple' unless LWP::Simple->can('mirror');

    my $result = eval {
	local $SIG{ALRM} = sub {die "timeout"};
	alarm(5);
	my $result = LWP::Simple::mirror($so_url => $so_file);
	alarm 0;
	LWP::Simple::is_success($result);
    };
    return $result;
}

sub hash_sofile {
    my ($so_file,$so_hash) = @_;
    my %hash;
    tie %hash,'DB_File',$so_hash,Fcntl->O_CREAT|Fcntl->O_RDWR,0666,$DB_File::DB_HASH or return;
    open my $f,$so_file or return;
    local $/ = '';  # paragraph mode
    while (<$f>) {
	next unless /\[Term\]/;
	my ($id)     = /^id: +(SO:\d+)/m;
	my ($name)   = /^name: (.+)/m;
	my @synonyms = /^synonym: "(.+)"/mg;
	$hash{lc $_} = $id foreach ($name,@synonyms);
    }
}

# Given a feature type, return all the subtypes that it contains
# in the form [type,has_children]
sub expand_types {
    my $type = shift;
    unless (exists $TYPE2SUBTYPES{$type}) {
	$TYPE2SUBTYPES{$type} = {};
      TRY: {
	  my $iterator = $DB->features(-types=>$type,-iterator=>1) or last TRY;
	  my $example  = $iterator->next_seq                       or last TRY;
	  _add_types($TYPE2SUBTYPES{$type},$example);
	}
    }

    return $TYPE2SUBTYPES{$type};
}

sub _add_types {
    my ($hash,$feature)       = @_;
    my @subparts              = $feature->get_SeqFeatures;
    $hash->{$feature->method} = @subparts;
    _add_types($hash,$_) foreach @subparts;
}

__END__

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
