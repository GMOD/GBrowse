#!/usr/bin/perl -w 
use strict;

use LWP::UserAgent;
use IO::File;

my $bWINDOWS = ($^O =~ /MSWin32/i) ? 1 : 0;

my $tmpdir = $ENV{TMP} || $ENV{TMPDIR} || '/usr/tmp';
$tmpdir =~ s!\\!\\\\!g if $bWINDOWS; #eliminates backslash mis-interpretation

my $ua = LWP::UserAgent->new;

my $req = HTTP::Request->new(GET => 'http://brie4.cshl.org:8000/');

my $res = $ua->request($req);

die "Failed to connect to gbrowse data source server\n" unless ($res->is_success);
 
my $result = $res->content;
my @result = split /\n/, $result;
my %available_data;

# note that since I control both the page being retrieved and
# this script, I can parse the html "by hand".  Were that not
# the case, I would certainly use HTML::Parser (or something
# like that).

foreach (@result) {
  if (/<li>.*href=\"(.*)\">(.*)<.*<\/li>/) {
    $available_data{$2} = $1;
  }
}

my $i = 0;
my @keys;
$keys[0] = '';

foreach my $key (reverse sort keys %available_data) {
  $i++;
  push @keys, $key;
  print "[$i] $key\n";
}
print "Choose data sets to install (comma delimited list) [0]:";
my $answer;
chomp($answer = <STDIN>);

die "OK, won't install anything\n" unless $answer;
my @data_sets = split /\,\s*/, $answer;

print "\nInstall these datasets?\n";
foreach my $set (@data_sets) {
  print "$keys[$set]\n";
}
print "yes/no [y]?";
chomp($answer = <STDIN>);

die if ($answer =~ /^n/i);

my %FH;
warn "retrieving data (this could take a while) ...\n";
foreach my $set (@data_sets) {

  warn "getting $keys[$set] ...\n";
  $req = HTTP::Request->new(GET => $available_data{$keys[$set]});
  $res = $ua->request($req);

  if ($res->is_success) {
    $result = $res->content;
    $FH{$keys[$set]} = IO::File->new("$tmpdir/$keys[$set].$$",">")
        or die "couldn't open $tmpdir/$keys[$set].$$: $!\n";
    $FH{$keys[$set]}->autoflush;
    $FH{$keys[$set]}->print($result);
    $FH{$keys[$set]}->close;
  } else {
    warn "unable to get dataset $keys[$set] ($available_data{$keys[$set]})\n";
  }
}

#figure out which data sets, and if they include fastas
#don't allow loading fasta without gff

#this loop is really taking advantage of my control of the download site
#it assumes that for every gff file there is a fasta, and than they are named
#with the same prefix (eg, yeast_), and that the gff file comes second 
#alphabetically (ie, first when reverse sorted).
for ($i=0;$i < scalar @data_sets;$i++) {
  my $set = $data_sets[$i];
  if ($set % 2 == 0) {
    warn "Importing of fasta without gff is not permitted from this interface\n";
    next;
  }   
  

  if (defined $data_sets[$i+1] && $set + 1 == $data_sets[$i+1]) { # fasta is to be imported too
    print "key1: $keys[$set], $keys[$set+1]\n";
    $i++;
  } else {  # don't import fasta
    print "key1: $keys[$set]\n";
  } 

}
