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

# In the following, perl variables are not expanded during extraction.

print OUT <<'!NO!SUBS!';

# $Id: gbrowse_est.PLS,v 1.1 2003-10-20 19:34:38 markwilkinson Exp $

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

my $name  = param('id');

$CONFIG->source(cookie('gbrowse_source'));

print_top("GBrowse EST Details: EST Sequence:$name");
print $CONFIG->header || h1("EST Sequence:$name Details");

my $db = open_database();
my $dbh = $db->dbh;
my $sth = $dbh->prepare("select fdna from fdna where fref=? order by foffset");
$sth->execute($name);
my $sequence;
while (my ($seq) = $sth->fetchrow_array){
    $seq =~ s/\W//g;
    $sequence .= $seq;
}
print print_sequence($name, $sequence);
# footer
print_bottom($VERSION);
exit 0;

######################

sub print_sequence {
    my $name = shift;
    my $seq  = shift;
    my $string;
    $string .= start_table();
    my $options = '';
    $string .= PrintMultiple($options,'Name',b($name));
    $string .= PrintMultiple($options,,'Class','EST Sequence');
    $string .= PrintMultiple($options,"Length",length($seq));
    $string .= end_table();

    if ($seq) {
      my $dna = $seq;
      $string .= print_dna($name, "EST Sequence", $dna) if $dna;
    }

  $string;
}

sub print_dna {
  my ($name, $class,$dna) = @_;
  my $markup = Bio::Graphics::Browser::Markup->new;
  # add a newline every 80 positions
  $markup->add_style('newline',"\n");

  my @markup;
  push @markup,map {['newline',80*$_]} (1..length($dna)/80);
  $markup->markup(\$dna,\@markup);
  return pre(">$name class=$class length=".(length($dna))."\n".$dna);
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

  my $string = join '',TR({-valign=>'top',-class=>'databody'},
                          th({-align=>'LEFT',-valign=>'top',-class=>'datatitle'},length $label>0 ? "$label: " : ''),
                          td($options, $LINK?$LINK:$first)
                         );
  for my $obj (@a) {
    $string .= join '', TR({-class=>'databody'},
			   th({-align=>'RIGHT',-class=>'datatitle'},'&nbsp;'),
			   td($options,$obj)
			  );
  }
  $string;
}


!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
