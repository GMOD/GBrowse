# $Id: SequenceDumper.pm,v 1.3 2002-07-05 13:53:10 lstein Exp $
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

Bio::Graphics::Browser::Plugin::SequenceDumper - A plugin for dumping sequences in various formats

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
# $Id: SequenceDumper.pm,v 1.3 2002-07-05 13:53:10 lstein Exp $
# Sequence Dumper plugin

use strict;
use Bio::Graphics::Browser::Plugin;
use Bio::SeqIO;
use Bio::Seq;
use CGI qw(:standard *pre);

use vars qw($VERSION @ISA);
use constant DEBUG => 0;

             # module        label           is xml?
my @FORMATS = ( 'fasta'   => ['Fasta',        undef],
		'genbank' => ['Genbank',      undef],
		'embl'    => ['EMBL',         undef],
		'gcg'     => ['GCG',          undef],
		'raw'     => ['Raw sequence', undef],
		'game'    => ['GAME (XML)',   'xml'],
		'bsml'    => ['BSML (XML)',   'xml'],
	      );

# initialize @ORDER using the even-numbered elements of the array
# and grepping for those that load successfully (some of the
# modules depend on optional XML modules).
my @ORDER = grep {
  my $module = "Bio::SeqIO::$_";
  warn "trying to load $module\n" if DEBUG;
  eval "require $module; 1";
}
  map { $FORMATS[2*$_] } (0..@FORMATS/2-1);

# initialize %FORMATS and %LABELS from @FORMATS
my %FORMATS = @FORMATS;
my %LABELS  = map { $_ => $FORMATS{$_}[0] } keys %FORMATS;

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
  if ($config->{'format'} eq 'html') {
    if ($FORMATS{$config->{'fileformat'}}[1]) {  # is xml
      print header('text/xml');
      $out->write_seq($segment);
    } else {
      print header('text/html');
      print start_html($segment),h1($segment), start_pre;
      $out->write_seq($segment);
      print end_pre();
      print end_html;
    }
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
      my ($c) = ( $p =~ /$objtype\.(\S+)/) or next;
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
					 '-values' => \@ORDER,
					 '-labels' => \%LABELS,
					 '-default'=> $current_config->{'fileformat'} ))));
  my $html= table(@choices);
  $html;
}

sub objtype { 
    ( split(/::/,ref(shift)))[-1];
}

1;
