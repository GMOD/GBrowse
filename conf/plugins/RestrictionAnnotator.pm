package Bio::Graphics::Browser::Plugin::RestrictionAnnotator;
# $Id: RestrictionAnnotator.pm,v 1.1 2002-03-31 21:41:49 lstein Exp $
# test plugin
use strict;
use Bio::Graphics::Browser::Plugin;
use CGI qw(:standard *table);

use vars '$VERSION','@ISA';
$VERSION = '0.10';

@ISA = qw(Bio::Graphics::Browser::Plugin);

my %SITES = (#           regexp
	     #name        site    offset of cleavage point
	     EcoRI   => ['GAATTC',1],
	     HindIII => ['TTCGAA',6],
	     BamHI   => ['GGATCC',1],
	     NotI    => ['GCGGCCGC',2],
	     Sau3A   => ['GATC',0],
);

my @COLORS = qw(red green blue orange cyan black 
		turquoise brown indigo wheat yellow emerald);

sub name { "Restriction Sites" }

sub description {
  p("The restriction site plugin generates a restriction map",
    "on the current view.").
  p("This plugin was written by Lincoln Stein.");
}

sub type { 'annotator' }

sub config_defaults {
  my $self = shift;
  return { };
}

sub reconfigure {
  my $self = shift;
  my $current_config = $self->configuration;
  %$current_config = map {$_=>1} param('RestrictionAnnotator.enzyme');
  $current_config->{on} = param('RestrictionAnnotator.on');
}

sub configure_form {
  my $self = shift;
  my $current_config = $self->configuration;
  my @buttons = checkbox_group(-name   => "RestrictionAnnotator.enzyme",
			       -values => [sort keys %SITES],
			       -defaults => [grep {$current_config->{$_}} keys %$current_config]
			       );
  return table(TR({-class=>'searchtitle'},
		  th("Select Restriction Sites To Annotate (limited selection right now)")),
	       TR({-class=>'searchtitle'},
		  th({-align=>'LEFT'},
		     "Restriction Site Display ",
		     radio_group(-name=>'RestrictionAnnotator.on',
				 -values=>[0,1],
				 -labels => {0=>'off',1=>'on'},
				 -default => $current_config->{on},
				 -override=>1,
				))),
	       TR({-class=>'searchbody'},
		  [map {td($_)} @buttons]));
}

sub annotate {
  my $self = shift;
  my $segment = shift;
  my $config  = $self->configuration;
  return unless %$config;
  return unless $config->{on};

  my $ref        = $segment->ref;
  my $abs_start  = $segment->start;
  my $dna        = $segment->dna;

  my $feature_list   = Bio::Graphics::FeatureFile->new;

  # find restriction sites
  my $i = 0;
  for my $type (keys %$config) {
    next if $type eq 'on';
    my ($pattern,$offset) = @{$SITES{$type}};
    $feature_list->add_type($type=>{glyph   => 'generic',
				    key     => "$type restriction site",
				    fgcolor => $COLORS[$i % @COLORS],
				    bgcolor => $COLORS[$i % @COLORS],
				    bump    => 1,
				    label   => 1,
				    point   => 0,
				    orient  => 'N',
				   });
    $i++;
    while ($dna =~ /$pattern/ig) {
      my $pos = $abs_start + pos($dna) - length($pattern) + $offset;
      my $feature = Bio::Graphics::Feature->new(-start=>$pos,-stop=>$pos,-ref=>$ref,-name=>$type);
      $feature_list->add_feature($feature,$type);
    }
  }

  return $feature_list;
}

1;
