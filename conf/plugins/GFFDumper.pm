package Bio::Graphics::Browser::Plugin::GFFDumper;
# $Id: GFFDumper.pm,v 1.10 2003-09-27 20:39:18 lstein Exp $
# test plugin
use strict;
use Bio::Graphics::Browser::Plugin;
use CGI qw(:standard super);

use vars '$VERSION','@ISA';
$VERSION = '0.60';

@ISA = qw(Bio::Graphics::Browser::Plugin);

sub name { "GFF File" }
sub description {
  p("The GFF dumper plugin dumps out the currently selected features in",
    a({-href=>'http://www.sanger.ac.uk/Software/formats/GFF/'},'Gene Finding Format.')).
  p("This plugin was written by Lincoln Stein.");
}

sub config_defaults {
  my $self = shift;
  return { 
	  version     => 2,
	  mode        => 'selected',
	  disposition => 'view'
	 };
}

sub reconfigure {
  my $self = shift;
  my $current_config = $self->configuration;

  foreach my $p ( $self->config_param() ) {
    $current_config->{$p} = $self->config_param($p);
  }
}

sub configure_form {
  my $self = shift;
  my $current_config = $self->configuration;
  my $html = p('Dump',
	       popup_menu(-name   => $self->config_name('mode'),
			  -values  => ['selected','all'],
			  -default => $current_config->{mode},
			  -override => 1,
			 ),
	       '&nbsp; features using GFF version',
	       popup_menu(-name   => $self->config_name('version'),
			  -values => [2,2.5,3],
			  -labels => { 2   => '2',
				       2.5 => '2 (Artemis)',
				       3   => '3'},
			  -default => $current_config->{version},
			  -override => 1));
  autoEscape(0);
  $html .= p(
	     radio_group(-name=>$self->config_name('disposition'),
			 -values => ['view','save','edit'],
			 -labels => {view => 'View',
				     save => 'Save to File',
				     edit => 'Edit'.super('*')}
			));
  autoEscape(1);
  $html .= p(super('*'),"To edit, install a helper application for MIME type",
	     cite('application/x-gff2'),'or',
	     cite('application/x-gff3')
	    );
  $html;
}

sub mime_type {
  my $self   = shift;
  my $config = $self->configuration;
  my $ps     = $self->page_settings;
  my $base   = join '_',@{$ps}{qw(ref start stop)};
  my $gff    = $config->{version} < 3 ? 'gff2' : 'gff3';
  return $config->{disposition} eq 'view' ? 'text/plain'
        :$config->{disposition} eq 'save' ? ('application/octet-stream',"$base.$gff")
        :$config->{disposition} eq 'edit' ? "application/x-${gff}"
        :'text/plain';
}


sub dump {
  my $self = shift;
  my ($segment,@more_feature_sets) = @_;
  my $page_settings = $self->page_settings;
  my $conf          = $self->browser_config;
  my $config        = $self->configuration;
  my $version       = $config->{version} || 2;
  my $mode          = $config->{mode}    || 'selected';

  my $date = localtime;
  print "##gff-version $version\n";
  print "##date $date\n";
  print "##sequence-region ",join(' ',$segment->ref,$segment->start,$segment->stop),"\n";
  print "##source gbrowse GFFDumper plugin\n";
    print $mode eq 'selected' ? "##NOTE: Selected features dumped.\n"
                              : "##NOTE: All features dumped.\n";

  my @args;
  if ($mode eq 'selected') {
    my @feature_types = $self->selected_features;
    @args = (-types => \@feature_types);
  }
  my $iterator = $segment->get_seq_stream(@args);
  do_dump($iterator,$version);

  for my $set (@more_feature_sets) {
    do_dump($set->get_seq_stream,$version)  if $set->can('get_seq_stream');
  }
}

sub do_dump {
  my $iterator    = shift;
  my $gff_version = shift;

  while (my $f = $iterator->next_seq) {
    my $s =  $gff_version < 3 ? $f->gff_string : $f->gff3_string(1);  # flag means recurse automatically
    chomp $s;

    # Artemis hack
    $s =~ s/Target \"([^\"]+)\" (\d+) (\d+)/Target "$1" ; tstart $2 ; tend $3/
      if $gff_version == 2.5;

    print $s,"\n";

    next if $gff_version >= 3; # gff3 recurses automatically

    for my $ss ($f->sub_SeqFeature) {
      my $s = $gff_version < 3 ? $ss->gff_string : $f->gff3_string;
      chomp $s;

      # Artemis hack
      $s =~ s/Target \"([^\"]+)\" (\d+) (\d+)/Target "$1" ; tstart $2 ; tend $3/
	if $gff_version == 2.5;

      print $s,"\n";
    }

  }
}


1;
