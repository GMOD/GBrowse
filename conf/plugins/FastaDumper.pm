package Bio::Graphics::Browser::Plugin::FastaDumper;
# $Id: FastaDumper.pm,v 1.3 2002-05-09 23:30:20 lstein Exp $
# test plugin
use strict;
use Bio::Graphics::Browser::Plugin;
use CGI qw(:standard);

use vars '$VERSION','@ISA';
$VERSION = '0.10';

@ISA = qw(Bio::Graphics::Browser::Plugin);

sub name { "FASTA File" }
sub description {
  p("The FASTA dumper plugin dumps out the currently displayed genomic segment",
    "in FASTA format.").
  p("This plugin was written by Lincoln Stein.");
}

sub dump {
  my $self = shift;
  my $segment = shift;
  my $config  = $self->configuration;
  my $dna = $segment->dna;

  my @markup;
  if ($config->{capitalize_codings}) {
    my $iterator = $segment->get_seq_stream(-types=>[qw(CDS ORF)],
					    -automerge=>0);
    while (my $coding = $iterator->next_seq) {
      my $start = $coding->start-$segment->start;
      $start = 0 if $start < 0;

      # for Text formatting
      substr($dna,$start,$coding->length) =~ tr/a-z/A-Z/;

      # for HTML formatting
      push @markup,([$start,q(<font style="background-color: yellow">)],
		    [$start+$coding->length,q(</font>)]);
    }
  }

  # HTML formatting
  if ($config->{format} eq 'html') {
    push @markup,map {[($_+1)*60,"\n"]} (0..int(length($dna)/60));
    markup(\$dna,\@markup);
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
}

sub config_defaults {
  my $self = shift;
  return { format           => 'html',
	   capitalize_codings => 0,
	 };
}

sub reconfigure {
  my $self = shift;
  my $current_config = $self->configuration;
  warn "fasta reconfigure()";
  $current_config->{format} = param('FastaDumper.output');
  $current_config->{capitalize_codings} = param('FastaDumper.capitalize_codings');
}

sub configure_form {
  my $self = shift;
  my $current_config = $self->configuration;
  my $html= table(
		  TR({-class=>'searchtitle'},
		     th({-align=>'RIGHT',-width=>'25%'},'Output'),
		     td(radio_group(-name=>'FastaDumper.output',
				    -values=>['text','html'],
				    -default => $current_config->{format},
				    -override => 1))),
		  TR({-class=>'searchtitle'},
		     th({-align=>'RIGHT',-width=>'25%'},'Capitalize/Hilight Coding Regions'),
		     td(radio_group(-name=>'FastaDumper.capitalize_codings',
				    -values=>[0,1],
				    -labels=> {0=>'no',1=>'yes'},
				    -default=>$current_config->{capitalize_codings},
				    -override=>1))));
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

1;
