package Bio::Graphics::Browser2::Plugin::Blat;
# $Id: Blat.pm  - Sean O'Keeffe

use strict;
use Bio::Graphics::Browser2::Plugin;
use Bio::Graphics::Feature;
use File::Temp qw/ tempfile /;
use CGI qw(:standard *table);
use CGI::Carp qw(fatalsToBrowser);
use vars '$VERSION','@ISA','$blat_executable','$twobit_dir','$host','$port';


=head1 NAME

Bio::Graphics::Browser2::Plugin::Blat -- plugin to map sequences against the genome

=head1 SYNOPSIS

 in human.conf:
     
[Blat:plugin]
blat_executable = /usr/local/gfClient
2bit_dir = /project/gbrowse/2bit_genomes
host = blat.server.host.name
port = 17780
 
 in mouse.conf:
     
[Blat:plugin]
blat_executable = /usr/local/gfClient
2bit_dir = /project/gbrowse/2bit_genomes
host = blat.server.host.name
port = 17781


=head1 DESCRIPTION

This Gbrowse plugin will take a sequence (entered in the configuration screen)
and BLAT it against the genome of the current organism ( port from conf file).

You must, of course, have the Blat server(gfServer) and client(gfClient) installed,
and you must set plugin parameters in the conf file:
    [Blat:plugin]
    blat_executable = /path/to/your/blat_client

The plugin only works with default psl output format for the moment.

=head1 AUTHOR

Sean O'Keeffe E<lt>okeeffe@molgen.mpg.deE<gt>.

=cut


$blat_executable = "";
$twobit_dir = "";
$host = "";
$port = "";

$VERSION = '0.02';

@ISA = qw(Bio::Graphics::Browser2::Plugin);

sub name { "BLAT Alignment" }

sub description {
  p("This plugin will take an input DNA sequence and run BLAT's gfClient (a Blat client to a local server).");
}

sub type { 'finder' }

sub init {
    my $self = shift;
    my $conf = $self->browser_config;
    $blat_executable = $conf->plugin_setting('blat_executable');
    $twobit_dir = $conf->plugin_setting('2bit_dir');
    $host = $conf->plugin_setting('host');
    $port = $conf->plugin_setting('port');
}
sub config_defaults {
  my $self = shift;
  return {'sequence_to_blat' => '',
  		'hits' => '5'}
}

sub configure_form {
  my $self = shift;
  my $current_config = $self->configuration;

  my $form .= h3("Enter parameters below for alignment of sequences using a Client to a local BLAT Server:")
  .start_table({-border => 0})
  .TR([
    td(b("Input sequence type:"), popup_menu(-align=>'center', -name=>$self->config_name('q'),-values=>['dna', 'rna']))
  ])
  .TR([
    td([b("Input Sequence To Align:"), textarea(-align=>'center', -name=>$self->config_name('sequence_to_blat'),-rows=>10,-cols=>80,-value=>$current_config->{'sequence_to_blat'})])
  ]);

  $form .= end_table();
  $form .= start_table({-border => 0}) . Tr(td(p())) . Tr(td(p())) . Tr(td(p())) . end_table();
  $form .= start_table({-border => 0})
  .TR([
    td(b("Minimum Percent Identity:"), textfield(-align=>'center', -name=>$self->config_name('minIdentity'),-size=>10, -value=>'90'))
  ])
  .TR([
    td(b("Number of Hits to Return:"), textfield(-align=>'center', -name=>$self->config_name('hits'),-size=>10, -value=>$current_config->{'hits'}))
  ]);
  $form .= end_table();
  
  return $form;
}
  
sub find {
  my $self = shift;
  my ($i,@hit_starts,@block_sizes,@results);
  my $query = $self->config_param('sequence_to_blat');  
  my $hits = int($self->config_param('hits'));
  my $minIdentity = int($self->config_param('minIdentity'));
  my $q = ($self->config_param('q') eq 'rna') ? 'rna' : 'dna';
  my ($i_f, $in_file) = tempfile();
  my ($o_f, $out_file) = tempfile();

  if ($query !~ /^\s*>/) { print $i_f ">segment\n";} # add FASTA defline if needed
  print $i_f $query; # print it to a temp file

  my $error = `$blat_executable $host $port $twobit_dir -minIdentity=$minIdentity -nohead -q=$q $in_file $out_file 2>&1 > /dev/null`;
  die "$error" if $error;

  open (IN, "$out_file") || die "couldn't open $out_file $!\n";
  my $hit_count = 0;
  my @blat_hits;
  # indexes each blat hit array of @blat_hits
  use constant {
    MATCHES       => 0,
    MISMATCHES    => 1,
    REP_MATCHES   => 2,
    N_COUNT       => 3,
    Q_NUM_INSERT  => 4,
    Q_BASE_INSERT => 5,
    T_NUM_INSERT  => 6,
    T_BASE_INSERT => 7,
    STRAND        => 8,
    Q_NAME        => 9,
    Q_LENGTH      => 10,
    Q_START       => 11,
    Q_END         => 12,
    T_NAME        => 13,
    T_LENGTH      => 14,
    T_START       => 15,
    T_END         => 16,
    BLOCK_COUNT   => 17,
    BLOCK_SIZES   => 18,
    Q_STARTS      => 19,
    T_STARTS      => 20,
  };

  while(<IN>) {
    push (@blat_hits, [ split ]);
  }

  for my $hit (
    # sort hits in descending order by calculated score
    sort {
      ($b->[MATCHES]+$b->[MISMATCHES]+$b->[REP_MATCHES])/$b->[Q_LENGTH]
      <=>
      ($a->[MATCHES]+$a->[MISMATCHES]+$a->[REP_MATCHES])/$a->[Q_LENGTH]
    } @blat_hits
  ) {
    last if ++$hit_count > $hits;
    
    $hit->[BLOCK_SIZES] =~ s/\,$//;      # remove trailing comma from block_sizes string     
    $hit->[T_STARTS]    =~ s/\,$//;      # .. and from t_starts string
    my $score = sprintf "%.2f", ( 100 * ( $hit->[MATCHES] + $hit->[MISMATCHES] + $hit->[REP_MATCHES] ) / $hit->[Q_LENGTH] );
    my $percent_id = sprintf "%.2f", ( 100 * ($hit->[MATCHES] + $hit->[REP_MATCHES]) /
                                             ($hit->[MATCHES] + $hit->[MISMATCHES] + $hit->[REP_MATCHES]));
    my $alignment = Bio::Graphics::Feature->new(-start=>$hit->[T_START]+1,
						-end  =>$hit->[T_END],
						-ref => $hit->[T_NAME],
						-type=>'BLAT',
						-name => "Alignment$hit_count",
						-strand => ($hit->[STRAND] eq '+') ? 1 : -1,
						-score => $score
					       );
    
    @hit_starts = map { $_ + 1 } split(",", $hit->[T_STARTS]);
    @block_sizes = split(",", $hit->[BLOCK_SIZES]);
    for($i=0;$i<$hit->[BLOCK_COUNT];$i++){      # if multihit alignments (block_count > 1), aggregate.
      my $sub_alignment = Bio::Graphics::Feature->new(-start=>$hit_starts[$i],
        				      -end  =>($hit_starts[$i]+$block_sizes[$i]),
        				      -ref => $hit->[T_NAME],
        				      -type=>'BLAT',
        				      -name => 'Alignment',
        				      -strand => ($hit->[STRAND] eq '+') ? 1 : -1,
        				      -score => $percent_id
        				     );
      $alignment->add_segment($sub_alignment);
    }
    push @results, $alignment;
  }
  
  unlink $in_file;
  unlink $out_file;
  return (\@results, @results ? '' : 'No alignments found');
}

1;

=head1 AUTHOR

Sean O'Keeffe E<lt>okeeffe@molgen.mpg.deE<gt>.

=cut
