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
# $Id: gbrowse_details.PLS,v 1.27 2004-08-18 21:42:14 lstein Exp $

use strict;
use CGI qw(:standard *table *TR escape);
use Bio::DB::GFF;
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Markup;
use Bio::Graphics::Browser::Util;
use Bio::Graphics::Browser::Realign 'align';
use vars qw($CONFIG $VERSION $CONF_DIR $LANG @COLORS $INDEX %strands %COLORS %URLS);

use constant DEBUG=>0;

@COLORS = qw(none lightgrey yellow pink orange brown
	     tan teal cyan lime green blue gray);

$CONF_DIR  = conf_dir($CONF_DIR);  # conf_dir() is exported from Util.pm
$CONFIG = open_config($CONF_DIR);  # open_config() is exported from Util.pm

$INDEX  = 0;
%COLORS = ();

my $src   = param('src') || param('source');
my $name  = param('name');
my $class = param('class');
my $ref   = param('ref');
my $start = param('start');
my $end   = param('end');

# Migrate from 1.56 way of specifying source to 1.57 way
# This may cause a redirect and exit 0 at this point!
redirect_legacy_url($src);
$CONFIG->source(get_source());

# This populates the %URLS global with link rules from the config file.
getLinkURLs(\%URLS);

print_top("GBrowse Details: $class:$name");
print $CONFIG->header || h1("$class:$name Details");

my $db = open_database();

my @features = sort {$b->length<=>$a->length} $CONFIG->_feature_get($db,$name,$class);
@features    = sort {$b->length<=>$a->length} $CONFIG->_feature_get($db,$ref,$class,$start,$end,1)
  unless @features;

warn "features = @features" if DEBUG;

warn "segments = ",join ' ',$features[0]->segments if (DEBUG && @features);

if (@features) {
  print print_features(\@features);
} else {
  print p({-class=>'error'},'Requested feature not found in database.');
}

# footer
print_bottom($VERSION);
exit 0;

######################

sub print_features {
  my $features   = shift;
  my $subf       = shift;
  my $string;
  for my $f (@$features) {
    warn "index = $INDEX, method = ",$f->method,"\n" if DEBUG;
    $COLORS{$f->method} ||= $COLORS[$INDEX++ % @COLORS];
    my $options = {-bgcolor => $COLORS{$f->method}} if $subf;

    $string .= start_table();
    unless ($subf) {
      $string .= PrintMultiple($options,'Name',b($f->name));
      $string .= PrintMultiple($options,'Class',$f->class);
    }
    $string .= PrintMultiple($options,'Type',$f->method);
    $string .= PrintMultiple($options,'Source',$f->source) if $f->source;
    $string .= PrintMultiple($options,"Position",position($f));
    $string .= PrintMultiple($options,"Length",$f->length);
    if ($f->target) {
      # try to correct for common GFF2 error of indicating a -/- alignment
      # using a (-) src strand and a target_start > target_end
      my $bug = $f->abs_strand < 0 && $f->target->abs_strand < 0;
      $string .= PrintMultiple($options,'Target',$f->target);
      $string .= PrintMultiple($options,"Matches",position($f->target,undef,$bug));
      $string .= PrintMultiple($options,'',print_matches($f,$f->target,$bug)) if $subf;

    }
    $string .= PrintMultiple($options,"Score",$f->score) if defined $f->score;
    my %attributes = $f->attributes;
    for my $a (sort keys %attributes) {
      $string .= PrintMultiple($options,$a,$f->attributes($a));
    }
#    my @subfeatures = $f->merged_segments;  # broken with old bioperl
    my @subfeatures = $f->segments;          # works with old bioperl
    $string .= PrintMultiple($options,'Parts',print_features(\@subfeatures,1)) if @subfeatures;
    $string .= end_table();

    if (!$subf) {
      my $dna = $f->dna;
      $string .= print_dna($f,$dna,$f->abs_start,$f->strand,\@subfeatures) if $dna;
    }

  }
  $string;
}

sub print_dna {
  my ($feature,$dna,$start,$strand,$features) = @_;
  my %seenit;
  warn "dna=$dna" if DEBUG;

  my $markup = Bio::Graphics::Browser::Markup->new;
  for my $f (@$features) {
    warn "f = $f" if DEBUG;
    my $method = $f->method;
    warn "$method => $COLORS{$method}" if DEBUG;
    next if $COLORS{$f->method} eq 'none';
    $markup->add_style($method => "BGCOLOR $COLORS{$method}");
  }
  # add a newline every 80 positions
  $markup->add_style('newline',"\n");

  my @markup;
  for my $f (@$features) {
    my ($s,$e);
    if ($strand >=0) {
      $s   = $f->low  - $start;
      $e   = $f->high - $start;
    } else {
      if ($start - $f->high < 0) { #how much of a hack is this!
                                   #it fixes chado feature differences
        $s   = $start + length($dna) - $f->low  -1;
        $e   = $start + length($dna) - $f->high -1;
      } else {
        $s   = $start - $f->low;
        $e   = $start - $f->high;
      }
    }

    ($s,$e) = ($e,$s) if $s > $e;
    next if $COLORS{$f->method} eq 'none';
    push @markup,[$f->method,$s,$e+1];  # Duelling off-by-one errors....
  }
  push @markup,map {['newline',80*$_]} (1..length($dna)/80);
  $markup->markup(\$dna,\@markup);
  my $position = position($feature);
  my $name     = $feature->name;
  my $class    = $feature->class;
  return pre(">$name class=$class position=$position\n".$dna);
}

sub print_matches {
  my ($src,$tgt,$bug) = @_;
  my $sdna = $src->dna or return;
  my $tdna = $tgt->dna or return;
  my $top_label = $src->abs_ref;
  my $bot_label = $tgt->abs_ref;

  my $src_x = $src->abs_start;
  my $src_y = $src->abs_end;
  my $tgt_x = $tgt->abs_start;
  my $tgt_y = $tgt->abs_end;
  my $tdir  = $tgt->abs_strand || +1;
  my $sdir  = $src->abs_strand || +1;

  if ($bug) { # correct for buggy data files that show -/- alignments; really -/+
    $tdir = +1;
    ($tgt_x,$tgt_y) = ($tgt_y,$tgt_x);
    $tdna =~ tr/gatcGATC/ctagCTAG/;
    $tdna = reverse $tdna;
  }
  warn ("sdir = $sdir, $src_x -> $src_y / $tgt_x -> $tgt_y") if DEBUG;
  my ($top,$middle,$bottom) = align($sdna,$tdna);

  my $m = max(length($top_label),length($bot_label));
  my $p = max(length($src_x),length($src_y),length($tgt_x),length($tgt_y));
  my $l  = ' ' x ($m+$p+2);  # adjusting for HTML

  my $string;
  my @top    = $top    =~ /(.{1,60})/g;
  my @middle = $middle =~ /(.{1,60})/g;
  my @bottom = $bottom =~ /(.{1,60})/g;

  for (my $i=0; $i<@top; $i++) {
    my $src_delta = $sdir * (length($top[$i]) - $top[$i]=~tr/-/-/);
    my $tgt_delta = $tdir * (length($bottom[$i]) - $bottom[$i]=~tr/-/-/);

    $string .= sprintf("%${m}s %${p}d %s %d\n$l%s\n%${m}s %${p}d %s %d\n\n",
		       $top_label,$src_x,$top[$i],$src_x + $src_delta - $sdir,
		       $middle[$i],
		       $bot_label,$tgt_x,$bottom[$i],$tgt_x + $tgt_delta - $tdir);

    $src_x  += $src_delta;
    $tgt_x  += $tgt_delta;

  }
  return pre($string);
}

sub max {
  if (@_ == 2) {
    return $_[0] > $_[1] ? $_[0] : $_[1];
  } else {
    return (sort {$b<=>$a} @_)[0];
  }
}

sub PrintMultiple {
  local $^W = 0;  # get rid of uninit variable warnings

  my $options = shift;
  my $label   = shift;
  $options ||= {};
  my @a = @_;
  return unless @a;
  my $first = shift @a;
  my $LINK = "";
  if ($URLS{$label}){
    $LINK = $URLS{$label};
    $LINK =~ s/\$tag/$label/;
    $LINK=~ s/\$value/$first/;
    $LINK = "<a href='$LINK'>$first</a>";
  }

  # for EST alignment features, create a link to get the orignal EST sequence
  if (($label eq 'Target') && ($URLS{'alignment'}) && ($first =~ /alignment/i)){
    my $name = shift @a;
    $LINK = $URLS{'alignment'};
    $LINK=~ s/\$value/$name/;
    $LINK = "$first : (<a href='$LINK'>Aligned Sequence</a>)";
  }

  $first =~ s/(\S{60})/$1 /g;  # wrap way long lines

  my $string = join '',TR({-valign=>'top',-class=>'databody'},
                          th({-align=>'LEFT',-valign=>'top',-class=>'datatitle'},length $label>0 ? "$label: " : ''),
                          td($options, $LINK?$LINK:$first)
                         );
  for my $obj (@a) {
    $obj =~ s/(\S{60})/$1 /g;  # wrap way long lines
    $string .= join '', TR({-class=>'databody'},
			   th({-align=>'RIGHT',-class=>'datatitle'},'&nbsp;'),
			   td($options,$obj)
			  );
  }
  $string;
}

sub position {
  my $f      = shift;
  my $simple = shift;
  my $bug    = shift; # for (-) (-) alignments

  my $ref = $f->abs_ref;
  my $start = $f->abs_start;
  my $end   = $f->abs_end;
  if ($simple) {
    ($start,$end) = ($end,$start) if $f->strand < 0;
    return "<b>$ref</b> $start..$end";
  }
  my $s = $f->abs_strand;
  if ($bug) {  # data bug
    ($start,$end) = ($end,$start);
    $s *= -1;
  }
  my $strand = $s > 0 ? '+' : $s < 0 ? '-' : '';

  my $src = escape($CONFIG->source);
  my $url = "../gbrowse/$src?name=$ref:$start..$end";
  return a({-href=>$url},$strand ? "$ref:$start..$end ($strand strand)" : "$ref:$start..$end");
}

sub getLinkURLs {
  my $urls = shift;
  my $THIS_CONFIG = $CONFIG->config;
  $THIS_CONFIG->safe(0);
  my @LINK_CONFIGS = map{$_=~/\:DETAILS$/?$_:undef} $THIS_CONFIG->setting;
  foreach (@LINK_CONFIGS){
    next unless $_;
    next unless $_=~/(.*?)\:DETAILS/;
    next unless $1;
    my $URL = $THIS_CONFIG->setting("$_", 'url');
    next unless $URL;
    $urls->{$1}=$URL;
  }
}

sub get_source {
  my $new_source = param('source') || param('src') || path_info();
  $new_source    =~ s!^/!!;  # get rid of leading / from path_info()
  my $old_source = cookie('gbrowse_source') unless $new_source && request_method() eq 'GET';

  my $source   = $new_source || $old_source;
  $source ||= $CONFIG->source;  # the default, whatever it is
  return ($source,$old_source);
}

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
