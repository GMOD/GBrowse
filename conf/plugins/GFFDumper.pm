package Bio::Graphics::Browser::Plugin::GFFDumper;
# $Id: GFFDumper.pm,v 1.6 2003-08-25 22:46:26 lstein Exp $
# test plugin
use strict;
use Bio::Graphics::Browser::Plugin;
use CGI qw(param url header p a);

use vars '$VERSION','@ISA';
$VERSION = '0.25';

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

  my @feature_types = $self->selected_features;
  my $iterator = $segment->get_seq_stream(-types=>\@feature_types);
  do_dump($iterator);

  for my $set (@more_feature_sets) {
    next unless $set->can('get_seq_stream');
    do_dump($set->get_seq_stream);
  }
}

sub do_dump {
  my $iterator = shift;
  while (my $f = $iterator->next_seq) {
    print $f->gff_string,"\n";
    for my $s ($f->sub_SeqFeature) {
      print $s->gff_string,"\n";
    }
  }
}


1;
