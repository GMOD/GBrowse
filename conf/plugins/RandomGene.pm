package Bio::Graphics::Browser::Plugin::RandomGene;
# $Id: RandomGene.pm,v 1.1 2003-02-27 15:14:23 lstein Exp $
# test plugin
use strict;
use Bio::Graphics::Browser::Plugin;
use Bio::SeqFeature::Generic;
use CGI qw(:standard *table);

use vars '$VERSION','@ISA';
$VERSION = '0.1';

@ISA = qw(Bio::Graphics::Browser::Plugin);

sub name { "Simulated Genes" }

sub description {
  p("The simulated gene plugin generates random genes",
    "on the current view.").
  p("It was written to illustrate how annotation plugins work.");
}

sub type { 'annotator' }

sub init { }

sub config_defaults {
  my $self = shift;
  return { };
}

sub reconfigure {
  my $self = shift;
  return;
}



sub configure_form {
  my $self = shift;
  return;
}
  
sub annotate {
  my $self    = shift;
  my $segment = shift;
  my $dna     = $segment->seq;

  my $abs_start = $segment->start;
  my $end       = $segment->end;
  my $length    = $segment->length;

  my $feature_list   = Bio::Graphics::FeatureFile->new;
  $feature_list->add_type('gene' => {glyph => 'transcript',
				     key   => 'simulated gene',
				     bgcolor => 'blue'});

  for (1..5) {
    my $gene_start = int(rand($length));
    my $gene_end   = $gene_start+int(rand(4000));
    my $gene       = Bio::SeqFeature::Generic->new(-start=>$abs_start+$gene_start,
						   -end  =>$abs_start+$gene_end,
						   -display_name => sprintf("ENS%010d",rand(1E6)),
						   -primary_tag=>'gene');

    warn "creating a gene from $gene_start to $gene_end\n";

    my $exon_start = $gene_start;
    my $exon_end;
    do {
      $exon_end   = $exon_start + int(rand(500));
      warn "creating an exon from $exon_start to $exon_end\n";

      my $exon_feature = Bio::SeqFeature::Generic->new(-start=>$abs_start+$exon_start,
						       -end  =>$abs_start+$exon_end,
						       -primary_tag => 'exon');
      $gene->add_SeqFeature($exon_feature,'EXPAND');
      $exon_start = $exon_end + int(rand(500));
    } until ($exon_start > $gene_end);

    $feature_list->add_feature($gene,'gene');
  }

  return $feature_list;
}

1;

