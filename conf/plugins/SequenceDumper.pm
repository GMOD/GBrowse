# $Id: SequenceDumper.pm,v 1.1 2002-06-03 18:33:40 stajich Exp $
#
# BioPerl module for Bio::Graphics::Browser::Plugin::SequenceDumper
#
# Cared for by Jason Stajich <jason@bioperl.org>
#
# Copyright Jason Stajich and Cold Spring Harbor Laboratories 2002
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::Graphics::Browser::Plugin::SequenceDumper - A plugin for dumping 

=head1 SYNOPSIS

Give standard usage here

=head1 DESCRIPTION

This is a plugin to the Generic Model Organism Database browse used by
Bio::Graphics::Browser to dump out an annotated region in a requested
flatfile format.  Currently the feature formats are 

=head1 FEEDBACK

See the GMOD website for information on bug submission http://www.gmod.org.

=head1 AUTHOR - Jason Stajich

Email jason@bioperl.org

Describe contact details here

=head1 CONTRIBUTORS

Additional contributors names and emails here

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut


# Let the code begin...


package Bio::Graphics::Browser::Plugin::SequenceDumper;
# $Id: SequenceDumper.pm,v 1.1 2002-06-03 18:33:40 stajich Exp $
# Sequence Dumper plugin

use strict;
use Bio::Graphics::Browser::Plugin;
use Bio::SeqIO;
use Bio::Seq;
use CGI qw(:standard *pre);

use vars '$VERSION','@ISA', '%LABELS', '@ORDER';

%LABELS = ( 'fasta'   => 'Fasta',
	    'genbank' => 'Genbank',
	    'embl'    => 'EMBL',
	    'game'    => 'GAME (XML)',
	    'bsml'    => 'BSML (XML)',
	    'gcg'     => 'GCG',
	    'raw'     => 'Raw sequence'
	    );

@ORDER = qw(fasta genbank embl gcg raw game bsml);

$VERSION = '0.11';

@ISA = qw(Bio::Graphics::Browser::Plugin);

sub name { "Sequence File" }
sub description {
  p("The Sequence dumper plugin dumps out the currently displayed genomic segment",
    "in the requested format.").
  p("This plugin was written by Lincoln Stein and Jason Stajich.");
}

sub dump {
  my $self = shift;
  my $segment = shift;
  
  my $config  = $self->configuration;  
  my $browser = $self->browser_config();
  my @markup;
  my %markuptype;
  my $out = new Bio::SeqIO(-format => $config->{'fileformat'});
  if( $config->{'fileformat'} eq 'bsml' ||
      $config->{'fileformat'} eq 'game'  ) {
      print header('text/xml');
      $out->write_seq($segment);
  } elsif( $config->{'format'} eq 'html' ) {
      print header('text/html');
      print start_html($segment),h1($segment), start_pre;
      $out->write_seq($segment);
      print end_pre();
      print end_html;      
  } else { 
      print header('text/plain');
      $out->write_seq($segment);      
  }  
  undef $out;
}

sub config_defaults {
  my $self = shift;
  return { format           => 'html',
	   fileformat       => 'fasta',
       };
}

sub reconfigure {
  my $self = shift;
  my $current_config = $self->configuration;

  my $objtype = $self->objtype();
  
  foreach my $p ( param() ) {
      my ($c) = ( $p =~ /$objtype\.(\S+)/);
      $current_config->{$c} = param($p);
  }
}

sub configure_form {
  my $self = shift;
  my $current_config = $self->configuration;
  my $objtype = $self->objtype();
  my @choices = TR({-class => 'searchtitle'},
			th({-align=>'RIGHT',-width=>'25%'},"Output",
			   td(radio_group('-name'   => "$objtype.format",
					  '-values' => [qw(text html)],
					  '-default'=> $current_config->{'format'},
					  '-override' => 1))));
  my $browser = $self->browser_config();
  # this to be fixed as more general

  push @choices, TR({-class => 'searchtitle'}, 
			th({-align=>'RIGHT',-width=>'25%'},"Sequence File Format",
			   td(popup_menu('-name'   => "$objtype.fileformat",
					 '-values' =>  \@ORDER, 
					 '-labels' => \%LABELS,
					 '-default'=> $current_config->{'fileformat'} ))));
  my $html= table(@choices);
  $html;
}

sub objtype { 
    ( split(/::/,ref(shift)))[-1];
}

1;
