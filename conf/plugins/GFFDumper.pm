package Bio::Graphics::Browser::Plugin::GFFDumper;
# $Id: GFFDumper.pm,v 1.13 2003-10-13 18:58:51 sheldon_mckay Exp $
# test plugin
use strict;
use Bio::Graphics::Browser::Plugin;
use CGI qw(:standard super);
use Data::Dumper;

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
  $mode             = 'all' if $version == 2.5;  

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
  
  my @feats = ();

  if ( $version == 2.5 ) {
    # don't want aggregate features
    map { push @feats, $_ unless /component/i } $segment->contained_features;  
  }
  else {
    my $iterator = $segment->get_seq_stream(@args);
    while ( my $f = $iterator->next_seq ) {
      push @feats, $f;
    }  
  }

  do_dump(\@feats, $version);

  for my $set (@more_feature_sets) {
    if ( $set->can('get_seq_stream') ) {
      my @feats = ();
      my $iterator = $set->get_seq_stream;
      while ( my $f = $iterator->next_seq ) {
        push @feats, $f;
      }
      do_dump(\@feats, $version); 
    }  
  }

  if ( $version == 2.5 ) {
    my $db = $self->database;
    my $whole_segment = $db->segment($segment->ref);
    my $seq = $whole_segment->seq;
    $seq ||= ('N' x $whole_segment->length);
    $seq =~ s/\S{60}/$&\n/g;
    print $seq, "\n";
  }
}

sub do_dump {
  my $feats       = shift;
  my $gff_version = shift;
  my @gff;
  
  for my $f ( @$feats ) {
    
    my $s = $gff_version == 3 ? $f->gff3_string(1) :  # flag means recurse automatically
	    $gff_version == 2 ? $f->gff_string     : gff25_string($f);
 
    push @gff, $s if $s;
 
    next if $gff_version >= 3; # gff3 recurses automatically

    for my $ss ($f->sub_SeqFeature) {
      my $s = $gff_version == 2 ? $ss->gff_string : gff25_string($f);
      push @gff, $s if $s;
    }
  }
  
  do_gff(@gff);
}

sub do_gff {
    my @gff = @_;
    chomp @gff;
    print join "\n", 
      map  { $_->[3] }
      sort { $a->[0] <=> $b->[0] or
             $b->[1] <=> $a->[1] or
             lc $a->[2] cmp lc $b->[2] }
      map  { [ (split)[3], (split)[4], (split)[2], $_ ] } @gff;
    print "\n";
}

sub gff25_string {
    my $f  = shift;
    return 0 if $f->primary_tag =~ /component/i;
    my $gff = $f->gff_string;    

    # remove embedded semicolons
    my %r;
    for ( $f->get_all_tags ) {
	my ($v) = $f->get_tag_values($_); 
	
	if ( $v =~ /;/ ) {
	    ( my $V = $v ) =~ s/;/,/g;
	    $gff =~ s/$v/$V/;
	}
    }    

    # controlled vocabulary for Target
    $gff =~ s/Target \"?([^\"]+)\"? (\d+) (\d+)/Target "$1" ; tstart $2 ; tend $3/;

    $gff;
}


1;
