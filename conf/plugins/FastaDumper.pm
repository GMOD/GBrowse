package Bio::Graphics::Browser::Plugin::FastaDumper;
# $Id: FastaDumper.pm,v 1.6 2002-07-07 03:13:36 lstein Exp $
# test plugin
use strict;
use Bio::Graphics::Browser::Plugin;
use Bio::Graphics::Browser::Markup;

use CGI qw(:standard );

use constant DEBUG => 1;

use vars qw($VERSION @ISA @MARKUPS %LABELS 
	    $BACKGROUNDUPPER %COLORNAMES $PANEL);

my @COLORS = sort qw(red green blue yellow orange
		     cyan magenta
		     chartreuse maroon lime deeppink
		     orchid salmon brown crimon aqua
		     silver tan teal tomato thistle
		     lightgrey grey darkgrey
		    );

BEGIN {
    $BACKGROUNDUPPER = 'YELLOW';
    @MARKUPS = ( undef,  # none
		 "UPPERCASE",  # for uppercase
		 'Font-weight: bold',
		 'Text-decoration: underline',
		 'Font-style: italic',
		 'FGCOLOR %s',
		 'BGCOLOR %s',
	       );

    %LABELS =  ( 0 => 'None',
		 1 => 'Uppercase',
		 2 => 'Bold',
		 3 => 'Underline',
		 4 => 'Italics',
		 5 => 'Text',
		 6 => 'Background',
	       );
}

$VERSION = '0.11';

@ISA = qw(Bio::Graphics::Browser::Plugin);

sub name { "FASTA File" }
sub description {
  p("The FASTA dumper plugin dumps out the currently displayed genomic segment",
    "in FASTA format.").
  p("This plugin was written by Lincoln Stein and Jason Stajich.");
}

sub dump {
    my $self = shift;
    my $segment = shift;
    my $config  = $self->configuration;
    my $dna = lc $segment->dna;
    my $browser = $self->browser_config();
    warn("====== beginning dump =====\n") if DEBUG;
    my $objtype = $self->objtype();
    $objtype .= ".";

    my %types;
    my @regions_to_markup;

    my $markup = Bio::Graphics::Browser::Markup->new;


    while( my ($type,$val) = each %{$config} ) {


      next unless $val;
      next if $type =~ /\.(f|b)gcolor$/i;
      next if $type =~ /format$/;

      warn "configuring $type => $val\n";

      my $style = $MARKUPS[$val];
      if ($style =~ /^(F|B)GCOLOR/) {
	$style = sprintf($style,$config->{"$type.\L$1\Egcolor"});
      }

      (my $feature_type = $type) =~ s/^[^.]+\.//;
      my @types = $browser->label2type($feature_type) or next;  # there may be several feature types defined for each track
      for my $t (@types) {
	$markup->add_style($t => $style);
	warn "adding style $t => $style\n" if DEBUG
      }

      foreach (@types) { $types{$_}++ };
    }

    warn("segment length is ".$segment->length()."\n") if DEBUG;
    my $iterator = $segment->get_seq_stream(-types=>[keys %types],
					    -automerge=>1) or return;
    while (my $markupregion = $iterator->next_seq) {

      warn "got feature $markupregion\n" if DEBUG;

      # handle both sub seqfeatures and split locations...
      # somebody rescue me from this insanity!
      my @parts = eval { $markupregion->sub_SeqFeature } ;
      @parts = eval { my $id   = $markupregion->location->seq_id;
		      my @subs = $markupregion->location->sub_Location;
		      grep {$id eq $_->seq_id} @subs } unless @parts;
      @parts = ($markupregion) unless @parts;

      for my $p (@parts) {
	my $start = $p->start - $segment->start;
	my $end   = $start + $p->length;

	warn "annotating $p $start..$end" if DEBUG;
	$start = 0             if $start < 0;  # this can happen
	$end   = $segment->end if $end > $segment->end;

	warn("$p ". $p->location->to_FTstring() . " type is ".$p->primary_tag) if DEBUG;

	my $style_symbol;
	foreach ($p->type,$p->method,$markupregion->type,$markupregion->method) {
	  $style_symbol ||= $markup->valid_symbol($_) ? $_ : undef;
	}
	warn "style symbol for $p is $style_symbol\n" if DEBUG;
	next unless $style_symbol;

	push @regions_to_markup,[$style_symbol,$start,$end];
      }
    }

    # add a newline every 60 positions
    $markup->add_style('newline',"\n");
    push @regions_to_markup,map {['newline',60*$_]} (1..length($dna)/60);

    # HTML formatting
    if ($config->{format} eq 'html') {
      $markup->markup(\$dna,\@regions_to_markup);
	
      print header('text/html');
      print start_html($segment),h1($segment);
      print pre(">$segment\n$dna");
      print end_html;
    }

    # text/plain formatting
    else {
	$dna =~ s/(.{1,60})/$1\n/g;
	print header('text/plain');
	print ">$segment\n";
	print $dna;
    }
    warn("====== end of dump =====\n") if DEBUG;
}

sub config_defaults {
    my $self = shift;
    return { format           => 'html' };
}

sub reconfigure {
  my $self = shift;
  my $current_config = $self->configuration;

  my $objtype = $self->objtype();
  foreach my $p ( param() ) {
    if( $p =~ /^$objtype\./) {
      $current_config->{$p} = param($p);
    }
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
    my @labels;
    foreach ( $browser->labels() ) {
	push @labels, $_ unless ! defined $browser->setting($_,'feature');
    }

    foreach my $featuretype ( @labels ) {
	my $realtext = $browser->setting($featuretype,'key') || $featuretype;
	push @choices, TR({-class => 'searchtitle'}, 
			  th({-align=>'RIGHT',-width=>'25%'}, $realtext,
			     td(join ('&nbsp;',
				      radio_group(-name     => "$objtype.$featuretype",
						  -values   => [ (sort keys %LABELS)[0..4] ],
						  -labels   => \%LABELS,
						  -default  => $current_config->{"$objtype.$featuretype"} || 0),
				      radio_group(-name     => "$objtype.$featuretype",
						  -values   => 5,
						  -labels   => \%LABELS,
						  -default  => $current_config->{"$objtype.$featuretype"} || 0),
				      popup_menu(-name      => "$objtype.$featuretype.fgcolor",
						 -values    => \@COLORS),
				      radio_group(-name     => "$objtype.$featuretype",
						  -values   => 6,
						  -labels   => \%LABELS,
						  -default  => $current_config->{"$objtype.$featuretype"} || 0),
				      popup_menu(-name      => "$objtype.$featuretype.bgcolor",
						 -values    => \@COLORS),
				     ))));
    }
    my $html= table(@choices);
    $html;
}

# get the <<unique name>> for the COOKIES (may not actually be unique but good 
# enough for our purposes) of the module
sub objtype { ( split(/::/,ref(shift)))[-1]; }

1;
