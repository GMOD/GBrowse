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
# $Id: gbrowse_details.PLS,v 1.1 2003-05-08 05:06:38 lstein Exp $

use strict;
use CGI qw(:standard *table *TR);
use Bio::DB::GFF;
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Markup;
use vars qw($CONFIG $VERSION $CONF_DIR $LANG @COLORS $INDEX %strands %COLORS);

use constant DEBUG=>0;

@COLORS = qw(none lightgrey yellow pink orange brown
	     tan teal cyan lime green blue gray);
# allow sharing with a global configuration variable
*CONFIG = *GBrowse::CONFIG;

if ($ENV{MOD_PERL}) {
  my $conf  = Apache->request->dir_config('GBrowseConf');
  $CONF_DIR = Apache->server_root_relative($conf) if $conf;
}
$CONFIG  ||= Bio::Graphics::Browser->new;
$CONFIG->read_configuration($CONF_DIR) or message("Can't read configuration files: $!");
$LANG    ||= Bio::Graphics::Browser::I18n->new("$CONF_DIR/languages");
set_language($CONFIG,$LANG);

$INDEX  = 0;
%COLORS = ();

my $src   = param('src');
my $name  = param('name');
my $class = param('class');

$CONFIG->source($src || cookie('gbrowse_source'));

print header();

# header
print
  start_html(-title  => "GBrowse Details: $class:$name",
	     -style  => {src=>$CONFIG->setting('stylesheet')},
	    );
print $CONFIG->header || h1("$class:$name Details");

my $db = open_database();
my @features = $db->get_feature_by_name($class=>$name);

warn "features = @features" if DEBUG;
print print_features(\@features);

# footer
print $CONFIG->footer || '',
  p(i(font({-size=>'small'},
	   $LANG->tr('Footer_1'))),br,
    tt(font({-size=>'small'},$LANG->tr('Footer_2',$VERSION)))),
  end_html;

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
    $string .= PrintMultiple($options,'Type',$f->method);
    $string .= PrintMultiple($options,"Position",position($f));
    $string .= PrintMultiple($options,"Score",$f->score) if defined $f->score;
    my %attributes = $f->attributes;
    for my $a (sort keys %attributes) {
      $string .= PrintMultiple($options,$a,$f->attributes($a));
    }
    my @subfeatures = $f->merged_segments;
    $string .= PrintMultiple($options,'SubFeatures',print_features(\@subfeatures,1)) if @subfeatures;
    $string .= end_table();
    my $dna = $f->dna;
    $string .= print_dna($f->name,$dna,$f->abs_start,\@subfeatures) 
      if $dna && !$subf;
  }
  $string;
}

sub print_dna {
  my ($name,$dna,$start,$features) = @_;
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
    my $start = $f->abs_start - $start;
    my $end   = $start + $f->length;
    next if $COLORS{$f->method} eq 'none';
    push @markup,[$f->method,$start,$end];
  }
  push @markup,map {['newline',80*$_]} (1..length($dna)/80);
  $markup->markup(\$dna,\@markup);
  return pre(">$name\n".$dna);
}

sub open_database {
  my $source  = $CONFIG->source;
  return $GBrowse::DB{$source} if $GBrowse::DB{$source};
  my ($adaptor,@argv) = eval{$CONFIG->db_settings};
  unless ($adaptor) {
    warn "gbrowse: trying to reload config, cache must be stale" if DEBUG;
    $CONFIG = Bio::Graphics::Browser->new;
    $CONFIG->read_configuration($CONF_DIR) or fatal_error("Can't read configuration files: $!");
    $CONFIG->source($source);
    ($adaptor,@argv) = $CONFIG->db_settings;
  }
  $GBrowse::DB{$source} = eval {$adaptor->new(@argv)} or warn $@;
  fatal_error(pre($@)) unless $GBrowse::DB{$source};
  if (my $refclass = $CONFIG->setting('reference class')) {
    eval {$GBrowse::DB{$source}->default_class($refclass)};
  }
  return $GBrowse::DB{$source};
}

sub set_language {
  my ($config,$lang) = @_;
  my $default_language   = $config->setting('language');
  my @languages     = http('Accept-language') =~ /([a-z]{2}-?[a-z]*)/ig;
  push @languages,$default_language if $default_language;
  warn "languages = ",join(',',@languages) if DEBUG;
  return unless @languages;
  $lang->language(@languages);
}

sub fatal_error {
  my @msg = @_;
  warn "@_" if DEBUG;
  maybe_print_top();
  print h2('An internal error has occurred');
  print p({-class=>'error'},@msg);
  my $webmaster = $ENV{SERVER_ADMIN} ?
   "maintainer (".a({-href=>"mailto:$ENV{SERVER_ADMIN}"},$ENV{SERVER_ADMIN}).')'
     : 'maintainer';
  print p("Please contact this site's $webmaster for assistance.");
  print footer();
  exit 0;
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
    $string = join '', TR({-class=>'databody'},
			  th({-align=>'RIGHT',-class=>'datatitle'},'&nbsp;'),
			  td($options,$obj)
			 );
  }
  $string;
}

sub position {
  my $f = shift;
  my $ref = $f->abs_ref;
  my $start = $f->abs_start;
  my $end   = $f->abs_end;
  my $strand = $f->abs_strand > 0 ? '+' : $f->abs_strand < 0 ? '-' : '';
  my $url = "gbrowse?name=$ref:$start..$end;src=".$CONFIG->source;
  return a({-href=>$url},$strand ? "$ref:$start..$end ($strand strand)" : "$ref:$start..$end");
}

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;
