package Bio::Graphics::Browser::Plugin::Submitter;

# $Id: Submitter.pm,v 1.1.2.1 2008-01-15 01:33:20 sheldon_mckay Exp $  
# Submitter is an invisible plugin (Does not appear in the "Reports and Analysis" menu)
# designed to support rubber-band select menu items that submit sequence data and
# other parameters to external web sites such as NCBI blast.  Check the GMOD wiki
# for documentation.
# This plugin: http://www.gmod.org/wiki/index.php/Submitter.pm
# Rubber-band selection: http://www.gmod.org/wiki/index.php/GBrowse_Rubber_Band_Selection.pm

use strict;
use CGI qw/standard escape unescape/;
use CGI::Pretty 'html3';
use Bio::Graphics::Browser::Plugin;
use Bio::Graphics::Browser::Util;
use Bio::Graphics::FeatureFile;
use Text::Shellwords;
use CGI qw(:standard *pre);
use vars qw($VERSION @ISA);
use Data::Dumper;

$VERSION = 0.1;

@ISA = qw(Bio::Graphics::Browser::Plugin);

# not visible in plugin menu
sub hide {1}

sub mime_type {'text/html'}

sub targets {
  my $self = shift;
  return $self->{targets} if $self->{targets};

  my $submitter_cfg  = $self->browser_config->plugin_setting('submitter');
  my $text = _prepare_text($submitter_cfg);
  my %config_values  = $text =~ /\[([^\]]+)\]([^\[]+)/gm;

  for my $target (keys %config_values) {
    my %config = $config_values{$target} =~ /(\w+)\s*=(.+)$/gm;
    next unless %config >= 2;
    for (keys %config) {
      $config{$_} =~ s/^\s+|\s+$//g;
    }
    $self->{targets}->{$target} = \%config;
  }

  $self->{targets}
}

sub _prepare_text {
  my $text = shift;
  my @html = $text =~ /(\<.+\>)\[?/;
  for my $html (@html) {
    $text =~ s/$html/escape($html)/em;
  }
  $text =~ s/\[/\n\[/g;
  $text =~ s/(\w+\s*=)/\n$1/g;
  $text;
}

sub dump {
  my $self = shift;
  my $segment = shift;
  my $targets = $self->targets;

  my $target = $self->config_param('target') 
    || fatal_error(qq(Error: A target for the submitter must be included in the URL "Submitter.target=target"));

  my $config = $targets->{$target}
    || fatal_error(qq(Error: No configuration for target $target!));

  my $seq  = $segment->seq;
  $seq = $seq->seq if ref $seq;
  my $name = $segment->name;
  
  my $url       = $config->{url} 
    || fatal_error('Error: a url for the external website is required');
  my $seq_label = $config->{seq_label} 
    || fatal_error('Error: a label is required for the sequence submission');

  # Other form elements to include
  my $extra_html = unescape($config->{extra_html});

  my $confirm = $config->{confirm};

  # Whether to format the sequence as fasta
  my $fasta = $seq;
  $fasta =~ s/(\S{60})/$1\n/g;
  $fasta = ">$name\n$fasta\n";

  unless ($url =~ /^http/i) {
    $url = "http://$url";
  }

  # pass-thru arguments -- to be sent to the extertnal web-site
  my %args;
  for my $arg (keys %$config) {
    next if $arg =~ /^seq_label$|^confirm$|^url$|^fasta$|^extra_html$/;
    $args{$arg} = unescape($config->{$arg});
  }

  # print a hidden form
  print start_form(-name=>'f1', -method=>'POST', -action=>$url), "\n";
  for my $arg (keys %args) {
    print hidden($arg => $args{$arg}), "\n";
  }
  print hidden($seq_label => $seq);

  if ($extra_html || $confirm) {
    my @rows = th({-colspan => 2, -style => "background:lightsteelblue"}, 
		  b("The following data will be submitted to $url"),
		  p(submit(-name => 'Confirm'),'&nbsp;&nbsp;',
		   button(-name => 'Cancel', -onclick => 'javascript:window.close()')));
    
    for my $arg (keys %args) {
      next if $arg eq $seq_label;
      $arg =~ s/extra_html/Additional options/;
      push @rows, td({-width => 100, -style => 'background:lightyellow'},
		     [b("$arg:"), unescape($args{$arg})]); 
    }

    if ($extra_html) {
      push @rows, td({-width => 100, -style => 'background:lightyellow'},
		     [b("Other options"), pre(unescape($extra_html))]);
    }
    push @rows, td({-width => 100, -style => 'background:lightyellow'},
		   [b($seq_label), pre($fasta)]);

    print table({-border=> 1}, Tr({-valign => 'top'}, \@rows));
  }

  print end_form;

  unless ($confirm || $extra_html) {
    print qq(<script type="text/javascript">document.f1.submit();</script>);
  }
}

sub description{'A plugin to submit the selected region to an external website'}
sub config_defaults {{}}
sub configure_form {''}

1;

