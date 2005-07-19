package Bio::Graphics::Browser::Plugin::RandomGene;
# $Id: RandomGene.pm,v 1.1.6.2 2005-07-19 21:41:39 lstein Exp $
# test plugin
use strict;
use Bio::Graphics::Browser::Plugin;
use Bio::SeqFeature::Generic;
use CGI qw(:standard *table);

use vars '$VERSION','@ISA';
$VERSION = '0.2';

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
  return { gene_size   => 5_000,
	   exon_size   => 100,
	   intron_size => 500,
	 };
}

sub reconfigure {
  my $self = shift;
  my $current_config = $self->configuration;
  my $defaults       = $self->config_defaults;

  for my $size ('exon_size','intron_size','gene_size') {
    my $new_size = $self->config_param($size);
    if ($new_size > 0 and $new_size < 1_000_000) { # sanity check
      $current_config->{$size} = $new_size;
    } else { # doesn't pass check, so go to defaults
      $current_config->{$size} = $defaults->{$size};
    }
  }

}



sub configure_form {
  my $self = shift;
  my $current_config = $self->configuration;
  return
    "Average length of simulated gene: ".textfield(-name=>$self->config_name('gene_size'),
						   -default=>$current_config->{gene_size}
						  )
    .br().
      "Average length of simulated exon: ".textfield(-name=>$self->config_name('exon_size'),
						     -default=>$current_config->{exon_size}
						    )
	.br().
	  "Average length of simulated intron: ".textfield(-name=>$self->config_name('intron_size'),
							 -default=>$current_config->{intron_size}
						  );
}

sub annotate {
  my $self    = shift;
  my $segment = shift;
  my $dna     = $segment->seq;

  my $abs_start = $segment->start;
  my $end       = $segment->end;
  my $length    = $segment->length;

  my $exon_size   = $self->configuration->{exon_size};
  my $gene_size   = $self->configuration->{gene_size};
  my $intron_size = $self->configuration->{intron_size};

  my $feature_list   = Bio::Graphics::FeatureFile->new;
  $feature_list->add_type('gene' => {glyph => 'transcript2',
				     key   => 'simulated gene',
				     bgcolor => 'blue',
				    });

  for (1..5) {
    my $gene_start = int(rand($length));
    my $gene_end   = $gene_start+int(rand($gene_size));
    my $strand = rand > 0.5 ? +1 : -1;
    my $gene       = Bio::SeqFeature::Generic->new(-start=>$abs_start+$gene_start,
						   -end  =>$abs_start+$gene_end,
						   -display_name => sprintf("ENS%010d",rand(1E6)),
						   -primary_tag=>'gene',
						   -strand => $strand,
						  );

    my $exon_start = $gene_start;
    my $exon_end;
    do {
      $exon_end   = $exon_start + int(rand($exon_size));
      $exon_end   = $gene_end if $exon_end > $gene_end;

      my $exon_feature = Bio::SeqFeature::Generic->new(-start=>$abs_start+$exon_start,
						       -end  =>$abs_start+$exon_end,
						       -primary_tag => 'exon',
						       -strand => $strand,
						      );
      $gene->add_SeqFeature($exon_feature,'EXPAND');
      $exon_start = $exon_end + int(rand($intron_size));
    } until ($exon_end >= $gene_end);

    $feature_list->add_feature($gene,'gene');
  }

  return $feature_list;
}

1;

