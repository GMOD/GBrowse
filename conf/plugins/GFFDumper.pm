package Bio::Graphics::Browser::Plugin::GFFDumper;
# $Id: GFFDumper.pm,v 1.21 2004-02-22 20:28:57 lstein Exp $
# test plugin
use strict;
use Bio::Graphics::Browser::Plugin;
use Bio::Graphics::Browser::GFFhelper;
use CGI qw(:standard *sup);

use vars '$VERSION','@ISA';
$VERSION = '0.80';

@ISA = qw/ Bio::Graphics::Browser::Plugin /;

sub name { "GFF File" }
sub description {
  p("The GFF dumper plugin dumps out the currently selected features in",
    a({-href=>'http://www.sanger.ac.uk/Software/formats/GFF/'},'Gene Finding Format.')).
  p("This plugin was written by Lincoln Stein &amp; Sheldon McKay.");
}

sub config_defaults {
  my $self = shift;
  return { 
	  version     => 2,
	  mode        => 'selected',
	  disposition => 'view',
	  coords      => 'absolute',
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
				       2.5 => '2 (Artemis)*',
				       3   => '3'},
			  -default => $current_config->{version},
			  -override => 1));
  $html .= p(
	     'Coordinates',
	     radio_group(-name   => $self->config_name('coords'),
			 -values => ['absolute','relative'],
			 -labels => { absolute => 'relative to chromosome/contig/clone',
				      relative => 'relative to dumped segment (start at 1)'
				    },
			 -default => $current_config->{coords},
			 -override => 1
			 )
	    );
  autoEscape(0);
  $html .= p(
	     radio_group(-name=>$self->config_name('disposition'),
			 -values => ['view','save','edit'],
			 -labels => {view => 'View',
				     save => 'Save to File',
				     edit => 'Edit'.sup('**'),
				 }
			));
  autoEscape(1);
  $html .= p(sup('*'),
	     "Note: Artemis GFF will contain the ENTIRE annotated sequence. Do NOT run this on whole chromosomes!") .
		 p(sup('**'),
		   "To edit, install a helper application for MIME type",
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
  my ($segment, @more_feature_sets) = @_;
  my $page_settings = $self->page_settings;
  my $conf          = $self->browser_config;
  my $config        = $self->configuration;
  my $version       = $config->{version} || 2;
  my $mode          = $config->{mode}    || 'selected';
  my $db            = $self->database;
  my $whole_segment = $db->segment(Accession => $segment->ref) ||
                      $db->segment($segment->ref);
  my $coords        = $config->{coords};
  $mode             = 'all'      if $version == 2.5;
  $coords           = 'absolute' if $version == 2.5;

  $segment->refseq($segment) if $coords eq 'relative';

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
    @feats = $whole_segment->features;
    $self->mangle_and_dump(\@feats,$whole_segment);
    my $seq = $whole_segment->seq;
    $seq  ||= ('N' x $whole_segment->length);
    $seq    =~ s/\S{60}/$&\n/g;
    print $seq, "\n";
  }
  else {
    my $iterator = $segment->get_seq_stream(@args);
    while ( my $f = $iterator->next_seq ) {
      $self->print_feature($f,$version);
    }
  }

  for my $set (@more_feature_sets) {
    if ( $set->can('get_seq_stream') ) {
      my @feats = ();
      my $iterator = $set->get_seq_stream;
      while ( my $f = $iterator->next_seq ) {
	$self->print_feature($f);
      }
    }
  }

}

sub print_feature {
  my $self = shift;
  my ($f,$version) = @_;
  $f->version($version);
  my $s = $f->gff_string(1); # the flag is for GFF3 subfeature recursion
  chomp $s;
  print $s,"\n";
  return if $version >= 3; # gff3 recurses automatically
  for my $ss ($f->sub_SeqFeature) {
    # next if $ss eq $f;
    my $s = $ss->gff_string;
    print $s,"\n";
  }
}

# used only for Artemis GFF 2.5
sub mangle_and_dump {
  my ($feats,$segment) = @_;
  my (@gff,%seen);
  for my $f ( @$feats ) {
    $f->version(2.5);
    my $s = $f->gff_string(1); # the flag is for GFF3 subfeature recursion
    chomp $s;
    push @gff, $s;
    for my $ss ($f->sub_SeqFeature) {
      # next if $ss eq $f;
      my $s = $ss->gff_string;
      push @gff, $s;
    }
  }

  # out of range features break Artemis (some kind of off by one error?)
  my $len = $segment->length - 1;
  for ( @gff ) {
    my $num = (split)[4];
    s/$num/$len/ if $num > $len;
  }

  # sigh... Artemis mangles uppercase 'Note' attributes
  @gff = grep { s/Note/note/g; chomp($_); $_; } @gff;
  print join "\n", 
    map  { $_->[3] }
      # sort first asc. by start, then desc. by stop, then ascibetically 
      sort { $a->[0] <=> $b->[0] or
	       $b->[1] <=> $a->[1] or
		 lc $a->[2] cmp lc $b->[2] }
	map  { [ (split)[3], (split)[4], (split)[2], $_ ] } @gff;
  print "\n";
}

sub gff25_string {
    my ($self, $f)  = @_;
    return 0 if $f->primary_tag =~ /component/i;
    
    $f->{version} = 2.5;
    my $gff = $f->gff_string;
    
    # convert embedded ';' to ',' 
    $gff =~ s/\"([^\"]);([^\"])\"/$1,$2/g;
    $gff;
}


1;
