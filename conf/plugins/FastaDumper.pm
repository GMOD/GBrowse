package Bio::Graphics::Browser::Plugin::FastaDumper;
# $Id: FastaDumper.pm,v 1.4 2002-06-06 16:57:32 stajich Exp $
# test plugin
use strict;
use Bio::Graphics::Browser::Plugin;

use CGI qw(:standard );

use vars qw($VERSION @ISA @MARKUPS %LABELS 
	    $BACKGROUNDUPPER %COLORNAMES $PANEL);

BEGIN {
    $BACKGROUNDUPPER = 'YELLOW';
    @MARKUPS = ( undef,  # none
		 "background-color: %s",  # for uppercase
		 'font-weight: bold',
		 'text-decoration: underline',
		 'font-style: italic',
		 'color: %s');

    %LABELS =  ( 0 => 'None',
		 1 => 'Upper/Lower Case',
		 2 => 'Bold',
		 3 => 'Underline',
		 4 => 'Italics',
		 5 => 'Color');
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
    my @markup;
    my %markuptype;
#    warn("====== beginning dump =====\n");
    my $objtype = $self->objtype();
    $objtype .= ".";
    my %colors;

    while( my ($type,$val) = each %{$config} ) {
	# skip val when it is 0 anyways and undef
	next unless( defined $val && length($val) && 
		     $val && $type =~ s/^\Q$objtype// &&
		     $type !~ /format$/ );
	if( $type =~ /(\S+)\.color$/ ) {
	    my $t = $1;
	    my $typev = $browser->setting($t,'feature');
	    unless (defined $typev) {  next } 
	    if( $val =~ /^\#([A-F0-9]{6})/ ) { $val = '#'.$1 } 
	    ($typev) = ( $typev =~ /^(\S+)\:/);
	    $colors{$typev} = $val;
	} else {
	    my $typev = $browser->setting($type,'feature');	    
	    if( defined $typev ) {
		push @{ $markuptype{$val} }, ( split(/\s+/,$typev));
	    } else { 		
#		warn("undefined typev for $type\n"); 
	    }
	}
    }
    my @ornament;
#    warn("segment length is ".$segment->length()."\n");
    foreach my $formattype ( keys %markuptype ) { 
#	warn("types are ".join(' ', @{ $markuptype{$formattype} } ) . "\n");
	my $iterator = $segment->get_seq_stream(-types=>$markuptype{$formattype},
						-automerge=>0);

	#warn("segment is ".$segment->start ."..". $segment->end."\n");
	next unless $iterator;
	while (my $markupregion = $iterator->next_seq) {
	    my $start = $markupregion->start - $segment->start;
	    my $end   = $start + $markupregion->length;
	    $start = 0 if( $start < 0);

#	    warn("$markupregion ". $markupregion->location->to_FTstring() . " type is ".$markupregion->primary_tag);

	    my $fontadj = $formattype;

	    # capitalization is a special case
	    if( $formattype == 1  ) {
#		warn("capitalization for $start - $end");
		substr($dna,$start,$end - $start) =~ tr/a-z/A-Z/;
		$fontadj = "$formattype;COLOR=$BACKGROUNDUPPER";
	    } elsif( $formattype == 5 ) {
		$fontadj = "$formattype;COLOR=".$colors{$markupregion->primary_tag};
	    }
	    if( $config->{format} eq 'html') {
		# for HTML formatting		
#		warn("$fontadj $start - $end\n");
		push @ornament,[$fontadj,$start,$end];
	    }
	}
    }
    
    # HTML formatting
    if ($config->{format} eq 'html') {
	
	ornament(\$dna,[sort {$a->[1] <=> $b->[1]} @ornament], [map {[($_+1)*60,"\n"]} (0..int(length($dna)/60))]);
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
#    warn("====== end of dump =====\n");
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
			     td(radio_group('-name'   => "$objtype.$featuretype",
					    '-values' => [ keys %LABELS ], 
					    '-labels' => \%LABELS,
					    '-default'=> $current_config->{"$objtype.$featuretype"} || 0),
				textfield('-name' => "$objtype.$featuretype.color",
					  '-size' => 10,
					  '-default' => $current_config->{"$objtype.$featuretype.color"} || '000000'),
				))); 
    }
    my $html= table(@choices);
    $html;
}

###### utilities

# insert HTML tags into a string without disturbing order
sub markup {
    my $string = shift;
    my $markups = shift;
    for my $m (sort by_position @$markups) { #insert later tags first so position remains correct
	my ($position,$markup) = @$m;
	next unless $position <= length $$string;
	substr($$string,$position,0) = $markup;
    }
}

sub by_position {
    return $b->[0]<=>$a->[0] || $b->[1] cmp $a->[1];
}

# get the <<unique name>> for the COOKIES (may not actually be unique but good 
# enough for our purposes) of the module
sub objtype { ( split(/::/,ref(shift)))[-1]; }


# annotation structure is:
# @ann = ( ['LABEL',$start,$end], ['LABEL',$start,$end],...)
sub ornament {
  my $string       = shift;
  my $markups      = shift;
  my $extra        = shift;
  # linearize markups into a set of start,/end tags, sorted by position
  
  my @markups = sort {  $a->[1]<=>$b->[1] } map { ([ @{$_}[0,1] ],
						  ["/$_->[0]",$_->[2]]) } @$markups;
  
  my (@stack,@tags);
  for my $m ( @markups ) {
      my ($type,$pos) = @{$m};
#      warn("$type -> $pos\n");
      my $last = pop @stack;
      if( $type !~ m!^/! ) { # a start tag then
	  # we need to stop the current tag first
	  # and build a combo tag
	  push @stack, $type;
	  if( $last ) {
	      my $st = aggregate_styles(split(/\s+/,$last),$type);
	      push @stack, $st;
	      
	      # chuck this start/end pair if they have the exact same
	      # start and end
	      if( $pos == $tags[-1]->[0] ) {
		  pop @tags;
	      } else {
		  push @tags, [ $pos, "END-$last"];
	      }
	      push @tags, [ $pos, "START-$st"];
	  } else { 
	      push @tags, [ $pos, "START-$type"];
	  }
      } else {
	  # omit the cases where we have start/end at the same spot
	  if( $tags[-1]->[0] == $pos ) { 
	      pop @tags;
	  } else {
	      push @tags, [ $pos, "END-$last"];
	  }
	  my $last = pop @stack;
	  if( $last) {
	      push @tags, [ $pos, "START-$last"];
	      push @stack, $last;
	  }
      }
  }
  # this is done we don't have this redundant <start></end> at the 
  # same position, so only the last declared start will be counted
  # we could probably detect this in the above loop but I *know* 
  # this will work

  my (%endpos,%startpos);
  
  # process each tag grouping
  my @ret ;

  for ( sort { $a->[0] <=> $b->[0] } @tags ) {
      my ($p,$v) = @{$_};
      if( $v =~ /^END-/ ) { 
	  next unless $p > 0;
	  $v = q(</font>);
      } else { 
	  my ($styles) = ($v =~ /START\-(.+)/);
	  my (@styles,%colors);
	  foreach my $s ( split( /\s+/,$styles) ) {
	      if( $s =~ /^(\d+);COLOR=(\S+)/)  {
		  push @{$colors{$1}},$2; 
	      } else { 
		  push @styles, $MARKUPS[$s];
	      }   
	  }
	  # handle background and font colors by separating
	  # into color regions and doing the aggregation
	  while( my ($colorregion,$colorvals) = each %colors ) {
	      push @styles, sprintf($MARKUPS[$colorregion],
				    color_aggregator(@$colorvals));
	  }
	  
	  $v = sprintf('<font style="%s">',
		       join('; ', @styles));
      }
      push @ret, [$p,$v];
  }
#  foreach my $t ( @ret )  {
#      warn(join(" ", @$t), "\n");
#  }
  markup($string,[ @ret, @$extra]);
}

sub aggregate_styles {
    my %seen;
    map { $seen{$_}++ } @_;
    return join(' ', keys %seen);
}

sub color_aggregator {
    my (@colors) = @_;
    my $c = shift @colors;
    foreach ( @colors ) {
	$c |= $_;
    }
    return $c;
}
1;
