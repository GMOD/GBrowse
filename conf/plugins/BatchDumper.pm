package Bio::Graphics::Browser::Plugin::BatchDumper;

use strict;
use Bio::Graphics::Browser::Plugin;
use Bio::SeqIO;
use Bio::Seq;
use CGI qw(:standard *pre);

use vars qw($VERSION @ISA);
use constant DEBUG => 0;


             # module        label           is xml?
my @FORMATS = ( 'fasta'   => ['Fasta',        undef],
		'genbank' => ['Genbank',      undef],
		'embl'    => ['EMBL',         undef],
		'gcg'     => ['GCG',          undef],
		'raw'     => ['Raw sequence', undef],
		'game'    => ['GAME (XML)',   'xml'],
		'bsml'    => ['BSML (XML)',   'xml'],
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

# initialize %FORMATS and %LABELS from @FORMATS
my %FORMATS = @FORMATS;
my %LABELS  = map { $_ => $FORMATS{$_}[0] } keys %FORMATS;

$VERSION = '0.12';

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

  # for the external viewer (like VNTI) the best import format is genbank (?)
  $config->{'fileformat'} = 'Genbank' if ($config->{'format'} eq 'external_viewer');

  my $out = new Bio::SeqIO(-format => $config->{'fileformat'});
  if ($FORMATS{$config->{fileformat}}[1]) {  # is xml
    $out->write_seq($_) for @segments;
  }
  elsif ($config->{'format'} eq 'html') {
    print start_html();
    foreach my $segment (@segments)
    {
      print h1($segment), start_pre;
      $out->write_seq($segment);
      print end_pre();
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
  return 'text/xml'  if $FORMATS{$config->{fileformat}}[1]; # this flag indicates xml
  return 'text/html' if $config->{format} eq 'html';
  return 'application/chemical-na' if $config->{format} eq 'external_viewer';
  return 'text/plain';
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

  my $objtype = $self->objtype();
  
  foreach my $p ( param() ) {
      my ($c) = ( $p =~ /$objtype\.(\S+)/) or next;
      $current_config->{$c} = param($p);
  }
}

sub configure_form {
  my $self = shift;
  my $current_config = $self->configuration;
  my $objtype = $self->objtype();
  my @choices = TR({-class => 'searchtitle'},
			th({-align=>'RIGHT',-width=>'25%'},"Output",
			   td(radio_group('-name'   => "$objtype.format",
					  '-values' => [qw(text html external_viewer)],
					  '-default'=> $current_config->{'format'},
					  '-override' => 1))));
  my $browser = $self->browser_config();
  # this to be fixed as more general

  push @choices, TR({-class => 'searchtitle'}, 
			th({-align=>'RIGHT',-width=>'25%'},"Sequence File Format",
			   td(popup_menu('-name'   => "$objtype.fileformat",
					 '-values' => \@ORDER,
					 '-labels' => \%LABELS,
					 '-default'=> $current_config->{'fileformat'} ))));



  push @choices, TR({-class=>'searchtitle'},
			th({-align=>'RIGHT',-width=>'25%'},'Sequence IDs','<p><i>(Entry overrides chosen segment)</i></p>',
			   td(textarea(-name=>"$objtype.sequence_IDs",
                           	       -rows=>20,
                              	       -columns=>20,
                                       #-default=>$current_config->{sequence_IDs}))));
                                      ))));


  my $html= table(@choices);
  $html;
}

sub objtype { 
    ( split(/::/,ref(shift)))[-1];
}

1;
