package Bio::Graphics::Browser::Plugin::GFFDumper;
# $Id: GFFDumper.pm,v 1.3 2002-07-07 21:31:48 lstein Exp $
# test plugin
use strict;
use Bio::Graphics::Browser::Plugin;
use CGI qw(param url header p a);

use vars '$VERSION','@ISA';
$VERSION = '0.10';

@ISA = qw(Bio::Graphics::Browser::Plugin);

sub name { "GFF File" }
sub description {
  p("The GFF dumper plugin dumps out the currently selected features in",
    a({-href=>'http://www.sanger.ac.uk/Software/formats/GFF/'},'Gene Finding Format.')).
  p("This plugin was written by Lincoln Stein.");
}

sub dump {
  my $self = shift;
  my $segment       = shift;
  my $page_settings = $self->page_settings;
  my $conf          = $self->browser_config;

  my @labels   = @{$page_settings->{tracks}};

  my $date = localtime;
  print "##gff-version 2\n";
  print "##date $date\n";
  print "##sequence-region ",join(' ',$segment->ref,$segment->start,$segment->stop),"\n";

  my @feature_types = map {$conf->config->label2type($_)} @labels;
  my $iterator = $segment->get_seq_stream(-types=>\@feature_types) or return;
  while (my $f = $iterator->next_seq) {
    print $f->gff_string,"\n";
    for my $s ($f->sub_SeqFeature) {
      print $s->gff_string,"\n";
    }
  }
}


1;
