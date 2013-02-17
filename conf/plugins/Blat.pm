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
    td([b("Input Sequence To Align:"), textarea(-align=>'center', -name=>$self->config_name('sequence_to_blat'),-rows=>10,-cols=>80,-value=>$current_config->{'sequence_to_blat'})])
  ]);

  $form .= end_table();
  $form .= start_table({-border => 0}) . Tr(td(p())) . Tr(td(p())) . Tr(td(p())) . end_table();
  $form .= start_table({-border => 0})
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
  my $hits = $self->config_param('hits');
  my ($i_f, $in_file) = tempfile();
  my ($o_f, $out_file) = tempfile();

  my $query_type = check_seq($query) or return; # check for dna or protein (dna queries must be compared against dna databases only & vice versa)
  if ($query !~ /^\s*>/) { print $i_f ">segment\n";} # add FASTA defline if needed
  print $i_f $query; # print it to a temp file

  my $error = `$blat_executable $host $port $twobit_dir -nohead -q=dna $in_file $out_file 2>&1 > /dev/null`;
  die "$error" if $error;

  open (IN, "$out_file") || die "couldn't open $out_file $!\n";
  my $hit_count = 0;
  while(<IN>) {
    last if ++$hit_count > $hits;
    # this could probably be done better but ...
    my ( $matches,$mismatches,$rep_matches,$n_count,$q_num_insert,$q_base_insert,$t_num_insert, $t_base_insert,
         $strand,$q_name,$q_length,$q_start,$q_end,$t_name,$t_length,$t_start,$t_end,$block_count,$block_sizes,
         $q_starts,$t_starts) = split;
    
    $block_sizes =~ s/\,$//;	      # remove trailing comma from block_sizes string     
    $t_starts	 =~ s/\,$//;	      # .. and from t_starts string
    my $score = sprintf "%.2f", ( 100 * ( $matches + $mismatches + $rep_matches ) / $q_length );
    my $percent_id = sprintf "%.2f", ( 100 * ($matches + $rep_matches)/( $matches + $mismatches + $rep_matches ));
    my $alignment = Bio::Graphics::Feature->new(-start=>$t_start,
						-end  =>$t_end,
						-ref => $t_name,
						-type=>'BLAT',
						-name => "Alignment$hit_count",
						-strand => $strand,
						-score => $score
					       );
    
    @hit_starts = split(",", $t_starts);
    @block_sizes = split(",", $block_sizes);
    for($i=0;$i<$block_count;$i++){	# if multihit alignments (block_count > 1), aggregate.
      my $sub_alignment = Bio::Graphics::Feature->new(-start=>$hit_starts[$i],
        				      -end  =>($hit_starts[$i]+$block_sizes[$i]),
        				      -ref => $t_name,
        				      -type=>'BLAT',
        				      -name => 'Alignment',
        				      -strand => $strand,
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

sub check_seq{
  my $query = shift;
  # if any sequence contains a character that is an amino acid and not a 
  # nucleotide, consider input to be "prot"
  if ($query =~ /^(?!\s*>).*([DEFHIKLMPQRSVWY])/mi) {return "prot";}
  else {return "dna";}
}

1;

=head1 AUTHOR

Sean O'Keeffe E<lt>okeeffe@molgen.mpg.deE<gt>.

=cut
