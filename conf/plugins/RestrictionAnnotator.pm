package Bio::Graphics::Browser::Plugin::RestrictionAnnotator;
# $Id: RestrictionAnnotator.pm,v 1.3 2002-04-08 22:22:00 lstein Exp $
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

  my ($max_label,$max_bump) = (10,50);
  if (my $browser_config = $self->browser_config) {
      $max_label  = $browser_config->setting(general=>'label density');
      $max_bump   = $browser_config->setting(general=>'bump density');
  }

  my $ref        = $segment->ref;
  my $abs_start  = $segment->start;
  my $dna        = $segment->dna;

  my $feature_list   = Bio::Graphics::FeatureFile->new;

  # find restriction sites
  my $i     = 0;
  my $count = 0;
  for my $type (keys %$config) {
    next if $type eq 'on';
    my ($pattern,$offset) = @{$SITES{$type}};
    $feature_list->add_type($type=>{glyph   => 'generic',
				    key     => "$type restriction site",
				    fgcolor => $COLORS[$i % @COLORS],
				    bgcolor => $COLORS[$i % @COLORS],
				    point   => 0,
				    orient  => 'N',
				   });
    $i++;
    while ($dna =~ /$pattern/ig) {
      my $pos = $abs_start + pos($dna) - length($pattern) + $offset;
      my $feature = Bio::Graphics::Feature->new(-start=>$pos,-stop=>$pos,-ref=>$ref,-name=>$type);
      $feature_list->add_feature($feature,$type);
      $count++;
    }
  
    # turn off bumping and labeling at high densities
    $feature_list->set($type,bump  => $count < $max_bump);
    $feature_list->set($type,label => $count < $max_label);
  }

  return $feature_list;
}

# this is a patch for older versions of BioPerl.  Will soon be unecessary
BEGIN {
  unless (Bio::Graphics::FeatureFile->can('add_type')) {
    eval <<'END';

    # add a feature of given type to our list
    # we use the primary_tag() method
    sub Bio::Graphics::FeatureFile::add_feature {
      my $self = shift;
      my ($feature,$type) = @_;
      $type = $feature->primary_tag unless defined $type;
      push @{$self->{features}{$type}},$feature;
    }

    # Add a type to the list.  Hash values are used for key/value pairs
    # in the configuration.  Call as add_type($type,$configuration) where
    # $configuration is a hashref.
    sub Bio::Graphics::FeatureFile::add_type {
      my $self = shift;
      my ($type,$type_configuration) = @_;
      my $cc = $type =~ /^(general|default)$/i ? 'general' : $type;  # normalize
      push @{$self->{types}},$cc unless $cc eq 'general' or $self->{config}{$cc};
      if (defined $type_configuration) {
	for my $tag (keys %$type_configuration) {
	  $self->{config}{$cc}{lc $tag} = $type_configuration->{$tag};
	}
      }
    }

    # change configuration of a type.  Call as set($type,$tag,$value)
    # $type will be added if not already there.
    sub Bio::Graphics::FeatureFile::set {
      my $self = shift;
      croak("Usage: \$featurefile->set(\$type,\$tag,\$value\n")
	unless @_ == 3;
      my ($type,$tag,$value) = @_;
      unless ($self->{config}{$type}) {
	return $self->add_type($type,{$tag=>$value});
      } else {
	$self->{config}{$type}{lc $tag} = $value;
      }
    }
END
  }
}


1;
