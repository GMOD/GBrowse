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
# $Id: gbrowse_details.PLS,v 1.7 2003-06-07 03:32:41 lstein Exp $

use strict;
use CGI qw(:standard *table *TR);
use Bio::DB::GFF;
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Markup;
use Bio::Graphics::Browser::Util;
use Bio::Graphics::Browser::Realign 'align';
use vars qw($CONFIG $VERSION $CONF_DIR $LANG @COLORS $INDEX %strands %COLORS);

use constant DEBUG=>0;

@COLORS = qw(none lightgrey yellow pink orange brown
	     tan teal cyan lime green blue gray);

$CONF_DIR  = conf_dir($CONF_DIR);  # conf_dir() is exported from Util.pm
$CONFIG = open_config($CONF_DIR);  # open_config() is exported from Util.pm

$INDEX  = 0;
%COLORS = ();

my $src   = param('src');
my $name  = param('name');
my $class = param('class');
my $ref   = param('ref');
my $start = param('start');
my $end   = param('end');

$CONFIG->source($src || cookie('gbrowse_source'));

print_top("GBrowse Details: $class:$name");
print $CONFIG->header || h1("$class:$name Details");

my $db = open_database();
my @args     = (-class=>$class,-name=>$name);
push @args,(-ref=>$ref)     if defined $ref;
push @args,(-start=>$start) if defined $start;
push @args,(-end=>$end)     if defined $end;
my @features = sort {$b->length<=>$a->length} $db->get_feature_by_name(@args);

warn "features = @features" if DEBUG;
print print_features(\@features);

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
      $string .= PrintMultiple($options,,'Class',$f->class);
    }
    my %attributes = $f->attributes;
    for my $a (sort keys %attributes) {
      $string .= PrintMultiple($options,$a,$f->attributes($a));
    }
    $string .= PrintMultiple($options,'Type',  $f->method);
    $string .= PrintMultiple($options,'Source',$f->source);
    $string .= PrintMultiple($options,"Position",position($f));
    $string .= PrintMultiple($options,"Length",$f->length);
    if ($f->target) {
      $string .= PrintMultiple($options,"Matches",position($f->target));
      $string .= PrintMultiple($options,'',print_matches($f,$f->target)) if $subf;

    }
    $string .= PrintMultiple($options,"Score",$f->score) if defined $f->score;
    my @subfeatures = $f->merged_segments;
    $string .= PrintMultiple($options,'Parts',print_features(\@subfeatures,1)) if @subfeatures;
    $string .= end_table();

    if (!$subf) {
      my $dna = $f->dna;
      $string .= print_dna($f,$dna,$f->abs_start,\@subfeatures) if $dna;
    }

  }
  $string;
}

sub print_dna {
  my ($feature,$dna,$start,$features) = @_;
  my %seenit;
  warn "dna=$dna" if DEBUG;

  my $markup = Bio::Graphics::Browser::Markup->new;
  for my $f (@$features) {
    warn "f = $f" if DEBUG;
    my $method = $f->method;
    warn "$method => $COLORS{$method}" if DEBUG;
    $markup->add_style($method => "BGCOLOR $COLORS{$method}");
  }
  # add a newline every 80 positions
  $markup->add_style('newline',"\n");

  my @markup;
  for my $f (@$features) {
    my $s   = $f->low  - $start;
    my $e   = $f->high - $start;
    ($s,$e) = ($e,$s) if $s > $e;
    next if $COLORS{$f->method} eq 'none';
    push @markup,[$f->method,$s-1,$e];
  }
  push @markup,map {['newline',80*$_]} (1..length($dna)/80);
  $markup->markup(\$dna,\@markup);
  my $position = position($feature);
  my $name     = $feature->name;
  my $class    = $feature->class;
  return pre(">$name class=$class position=$position\n".$dna);
}

sub print_matches {
  my ($src,$tgt) = @_;
  my $sdna = $src->dna or return;
  my $tdna = $tgt->dna or return;
  my ($top,$middle,$bottom) = align($sdna,$tdna);
  my $top_label = b($src->abs_ref);
  my $bot_label = b($tgt->abs_ref);

  my $src_x = $src->abs_start;
  my $tgt_x = $tgt->abs_start;
  my $dir   = $tgt->abs_strand || +1;

  my $m = length($top_label) > length($bot_label) ? length($top_label) : length($bot_label);
  my $p = length($src_x) > length($tgt_x) ? length($src_x) : length($tgt_x);
  my $t = $m+$p-2;
  my $sp = "%${t}s %s";
  my $l  = ' ' x ($m+$p-8);  # adjusting for HTML

  my $string;
  my @top    = $top    =~ /(.{1,60})/g;
  my @middle = $middle =~ /(.{1,60})/g;
  my @bottom = $bottom =~ /(.{1,60})/g;

  for (my $i=0; $i<@top; $i++) {
    my $src_delta = length($top[$i]) - $top[$i]=~tr/-/-/;
    my $tgt_delta = $dir * (length($bottom[$i]) - $bottom[$i]=~tr/-/-/);

    $string .= sprintf("$sp %d\n$l%s\n$sp %d\n\n",
		       "$top_label $src_x",$top[$i],$src_x + $src_delta - 1,
		       $middle[$i],
		       "$bot_label $tgt_x",$bottom[$i],$tgt_x + $tgt_delta - $dir);

    $src_x  += $src_delta;
    $tgt_x  += $tgt_delta;

  }
  return pre($string);
}

sub PrintMultiple {
  local $^W = 0;  # get rid of uninit variable warnings

  my $options = shift;
  my $label   = shift;
  $options ||= {};
  my @a = @_;
  return unless @a;
  my $first = shift @a;
  my $string = join '',TR({-valign=>'top',-class=>'databody'},
			  th({-align=>'LEFT',-valign=>'top',-class=>'datatitle'},length $label>0 ? "$label: " : ''),
			  td($options, $first)
			 );
  for my $obj (@a) {
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
  my $ref = $f->abs_ref;
  my $start = $f->abs_start;
  my $end   = $f->abs_end;
  if ($simple) {
    ($start,$end) = ($end,$start) if $f->strand < 0;
    return "<b>$ref</b> $start..$end";
  }
  my $strand = $f->abs_strand > 0 ? '+' : $f->abs_strand < 0 ? '-' : '';
  my $url = "gbrowse?name=$ref:$start..$end;src=".$CONFIG->source;
  return a({-href=>$url},$strand ? "$ref:$start..$end ($strand strand)" : "$ref:$start..$end");
}

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;
