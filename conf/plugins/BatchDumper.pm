package Bio::Graphics::Browser::Plugin::BatchDumper;

use strict;
use lib '/home/lstein/projects/Generic-Genome-Browser/lib';
use Bio::Graphics::Browser::Plugin;
use Bio::SeqIO;
use Bio::Seq;
use CGI qw(:standard *pre);

use vars qw($VERSION @ISA);
use constant DEBUG => 0;
$VERSION = 1.0;

             # module        label           is xml?
my @FORMATS = ( 'fasta'   => ['Fasta',        undef],
		'genbank' => ['Genbank',      undef],
		'embl'    => ['EMBL',         undef],
		'gcg'     => ['GCG',          undef],
		'raw'     => ['Raw sequence', undef],
		'game'    => ['GAME (XML)',   'xml'],
		'bsml'    => ['BSML (XML)',   'xml'],
		'gff'     => ['GFF',          undef],
	      );

# initialize @ORDER using the even-numbered elements of the array
# and grepping for those that load successfully (some of the
# modules depend on optional XML modules).
my @ORDER = grep {
  my $module = "Bio::SeqIO::$_";
  warn "trying to load $module\n" if DEBUG;
  eval "require $module; 1";
}
  map { $FORMATS[2*$_] } (0..@FORMATS/2-1);

unshift @ORDER,'gff';

# initialize %FORMATS and %LABELS from @FORMATS
my %FORMATS = @FORMATS;
my %LABELS  = map { $_ => $FORMATS{$_}[0] } keys %FORMATS;

$VERSION = '0.13';

@ISA = qw(Bio::Graphics::Browser::Plugin);

sub name { "(Multiple) Sequence File" }
sub description {
  p("The Sequence dumper plugin dumps out the currently displayed genomic segment",
    "or the segments corresponding to the given accessions, in the requested format.").
  p("This plugin was written by Lincoln Stein and Jason Stajich.");
}

sub dump {
  my $self = shift;
  my $segment = shift;

  my $browser = $self->browser_config;
  my $config  = $self->configuration;

  my @segments = map { ( $browser->name2segments($_,$self->database) ) } split /\s+/m, $config->{sequence_IDs};
  # take the original segment if no segments were found/entered via the sequence_IDs textarea field
  @segments = ($segment) unless (@segments); 

  # special case for GFF dumping
  if ($config->{fileformat} eq 'gff') {
    $self->gff_dump(@segments);
    return;
  }

  # for the external viewer (like VNTI) the best import format is genbank (?)
  $config->{'fileformat'} = 'Genbank' if ($config->{'format'} eq 'external_viewer');

  my $out = new Bio::SeqIO(-format => $config->{'fileformat'});
  my $mime_type = $self->mime_type;
  if ($mime_type =~ /html/) {
    print start_html($segment);
    foreach my $segment (@segments) {
      print h1($segment),"\n",
            start_pre,"\n";
      $out->write_seq($segment);
      print end_pre(),"\n";
    }
    print end_html;
  } else {
    $out->write_seq($_) for @segments;
  }
  undef $out;
}

sub mime_type {
  my $self = shift;
  my $config = $self->configuration;
  return 'text/plain' if $config->{format} eq 'text';
  return 'text/xml'   if $config->{format} eq 'html' && $FORMATS{$config->{fileformat}}[1]; # this flag indicates xml
  return 'text/html'  if $config->{format} eq 'html';
  return 'application/chemical-na'  if $config->{format} eq 'external_viewer';
  return wantarray ? ('application/octet-stream','dumped_region') : 'application/octet-stream'
    if $config->{format} eq 'todisk';
  return 'text/plain';  # default
}

sub config_defaults {
  my $self = shift;
  return { format           => 'html',
	   fileformat       => 'fasta',
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
  my @choices = TR({-class => 'searchtitle'},
			th({-align=>'RIGHT',-width=>'25%'},"Output",
			   td(radio_group('-name'   => $self->config_name('format'),
					  '-values' => [qw(text html external_viewer todisk)],
					  '-default'=> $current_config->{'format'},
					  -labels   => {'html' => 'html/xml',
							'external_viewer' => 'GenBank Helper Application',
							'todisk' => 'Save to Disk',
						       },
					  '-override' => 1))));
  my $browser = $self->browser_config();
  # this to be fixed as more general

  push @choices, TR({-class => 'searchtitle'}, 
			th({-align=>'RIGHT',-width=>'25%'},"Sequence File Format",
			   td(popup_menu('-name'   => $self->config_name('fileformat'),
					 '-values' => \@ORDER,
					 '-labels' => \%LABELS,
					 '-default'=> $current_config->{'fileformat'} ))));



  push @choices, TR({-class=>'searchtitle'},
			th({-align=>'RIGHT',-width=>'25%'},'Sequence IDs','<p><i>(Entry overrides chosen segment)</i></p>',
			   td(textarea(-name=>$self->config_name('sequence_IDs'),
                           	       -rows=>20,
                              	       -columns=>20,
                                      ))));


  my $html= table(@choices);
  $html;
}

sub gff_dump {
  my $self          = shift;
  my @segments      = @_;
  my $page_settings = $self->page_settings;
  my $conf          = $self->browser_config;
  my $date = localtime;

  my $mime_type = $self->mime_type;
  my $html      = $mime_type =~ /html/;
  print start_html($segments[0]) if $html;

  for my $segment (@segments) {
    print h1($segment),start_pre() if $html;
    print "##gff-version 2\n";
    print "##date $date\n";
    print "##sequence-region ",join(' ',$segment->ref,$segment->start,$segment->stop),"\n";

    my @feature_types = $self->selected_features;
    my $iterator = $segment->get_seq_stream(-types=>\@feature_types) or return;
    while (my $f = $iterator->next_seq) {
      print $f->gff_string,"\n";
      for my $s ($f->sub_SeqFeature) {
	print $s->gff_string,"\n";
      }
    }
    print end_pre() if $html;
  }
  print end_html() if $html;
}

1;

