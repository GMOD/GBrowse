package Bio::Graphics::Browser::Plugin::RestrictionAnnotator;
# $Id: RestrictionAnnotator.pm,v 1.7 2002-06-26 06:13:41 lstein Exp $
# test plugin
use strict;
use Bio::Graphics::Browser::Plugin;
use CGI qw(:standard *table);

use vars '$VERSION','@ISA';
$VERSION = '0.20';

@ISA = qw(Bio::Graphics::Browser::Plugin);

my %SITES;

my @COLORS = qw(red green blue orange cyan black 
		turquoise brown indigo wheat yellow emerald);

sub name { "Restriction Sites" }

sub description {
  p("The restriction site plugin generates a restriction map",
    "on the current view.").
  p("This plugin was written Elizabeth Nickerson &amp; Lincoln Stein.");
}

sub type { 'annotator' }

sub init {shift->configure_enzymes}

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
  configure_enzymes() unless %SITES;
  my @buttons = checkbox_group(-name   => "RestrictionAnnotator.enzyme",
			       -values => [sort keys %SITES],
			       -cols   => 4,
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
		  td(@buttons)));
}
  

sub annotate {
  my $self = shift;
  my $segment = shift;
  my $config  = $self->configuration;
  configure_enzymes() unless %SITES;
  return unless %SITES;
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
    next unless $SITES{$type};
    my ($pattern,$offset) = @{$SITES{$type}};
    $feature_list->add_type($type=>{glyph   => 'generic',
				    key     => "$type restriction site",
				    fgcolor => $COLORS[$i % @COLORS],
				    bgcolor => $COLORS[$i % @COLORS],
				    point   => 0,
				    orient  => 'N',
				   });
    $i++;
    while ($dna =~ /($pattern)/ig) {
      my $pos = $abs_start + pos($dna) - length($1) + $offset;
      my $feature = Bio::Graphics::Feature->new(-start=>$pos,-stop=>$pos,-ref=>$ref,-name=>$type);
      $feature_list->add_feature($feature,$type);
    }
  }

  return $feature_list;
}

sub configure_enzymes {
  my $self = shift;
  my $conf_dir = $self->config_path();
  my $file = "$conf_dir/enzymes.txt";
  open (ENZYMES, "$file") or die "Error: cannot open file $file: $!.\n";
  while (<ENZYMES>) {
    chomp;
    my @hold_enzyme = split(/\t/,$_);
    my $enzyme_name = shift(@hold_enzyme);
    $SITES{$enzyme_name} = \@hold_enzyme;
    next;
  }
  close(ENZYMES);
}

1;

