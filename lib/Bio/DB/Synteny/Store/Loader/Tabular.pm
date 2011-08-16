=head1 NAME

Bio::DB::Synteny::Store::Loader::Tabular - loader for tabular synteny data.

=head1 SYNOPSIS

  my $syn_store = Bio::DB::Synteny::Store->new(
    -adaptor => $adaptor,
    -dsn     => $dsn,
    -user    => $user,
    -pass    => $pass,
    -create  => $create,
    -verbose => $verbose,
   );

  my $loader = Bio::DB::Synteny::Store::Loader::Tabular->new(
      -store   => $syn_store,
      -nomap   => $nomap,
      -verbose => $verbose,
      );

  $loader->load( $file1, $file2, $file3 );

=head1 DESCRIPTION

The expected file format is tab-delimited (shown below):

  species1  ref1  start1 end1 strand1  cigar_string1 \
  species2  ref2  start2 end2 strand2  cigar_string2 \
  coords1... | coords2...

the coords (coordinate) format:

  pos1_species1 pos1_species2 ... posn_species1 posn_species2 | \
  pos1_species2 pos1_species1 ... posn_species2 posn_species1

where pos is the matching sequence coordinate (ungapped) in each
species.

=cut

package Bio::DB::Synteny::Store::Loader::Tabular;
use strict;

use base 'Bio::DB::Synteny::Store::Loader';

=head2 load( filename, filename, ... )

Load the given files.

=cut

sub load {
    my $self = shift;

    while ( my $infile = shift ) {
        print "Processing alignment file $infile...\n" if $self->verbose;
        open my $fh, '<', $infile or die "$! reading $infile";

        while ( <$fh> ) {
            chomp;
            my ($src1,$ref1,$start1,$end1,$strand1,$seq1,
                $src2,$ref2,$start2,$end2,$strand2,$seq2,@maps) = split "\t";

            # deal with coordinate maps
            my ($switch,@map1,@map2);
            for (@maps) {
                if ($_ eq '|') {
                    $switch++;
                    next;
                }
                $switch ? push @map2, $_ : push @map1, $_;
            }
            $self->store->add_alignment(
                [ $src1,$ref1,$start1,$end1,$strand1,$seq1, { @map1 } ],
                [ $src2,$ref2,$start2,$end2,$strand2,$seq2, { @map2 } ],
               );
        }
    }
}

1;
