package Bio::Graphics::Browser::Plugin::GFFDumper;
# $Id: GFFDumper.pm,v 1.9 2003-09-26 16:19:31 lstein Exp $
# test plugin
use strict;
use Bio::Graphics::Browser::Plugin;
use CGI qw(param url header p a);

use vars '$VERSION','@ISA';
$VERSION = '0.50';

@ISA = qw(Bio::Graphics::Browser::Plugin);

sub name { "GFF File" }
sub description {
  p("The GFF dumper plugin dumps out the currently selected features in",
    a({-href=>'http://www.sanger.ac.uk/Software/formats/GFF/'},'Gene Finding Format.')).
  p("This plugin was written by Lincoln Stein.");
}

sub dump {
  my $self = shift;
  my ($segment,@more_feature_sets) = @_;
  my $page_settings = $self->page_settings;
  my $conf          = $self->browser_config;

  my $date = localtime;
  print "##gff-version 2\n";
  print "##date $date\n";
  print "##sequence-region ",join(' ',$segment->ref,$segment->start,$segment->stop),"\n";
  print "##source gbrowse GFFDumper plugin\n";
  print "##NOTE: Selected features dumped.\n";

  my @feature_types = $self->selected_features;
  my $iterator = $segment->get_seq_stream(-types=>\@feature_types);
  do_dump($iterator);

  for my $set (@more_feature_sets) {
    do_dump($set->get_seq_stream)  if $set->can('get_seq_stream');
  }
}

sub do_dump {
  my $iterator = shift;
  while (my $f = $iterator->next_seq) {
    my $s = $f->gff_string;
    chomp $s;
    print "$s\n";
    for my $ss ($f->sub_SeqFeature) {
      my $string = $ss->gff_string;
      chomp $string;
      print "$string\n";
    }
  }
}


1;
