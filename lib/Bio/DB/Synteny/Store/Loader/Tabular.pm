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
            $self->store->load_alignment(
                [ $src1,$ref1,$start1,$end1,$strand1,$seq1, { @map1 } ],
                [ $src2,$ref2,$start2,$end2,$strand2,$seq2, { @map2 } ],
               );
        }
    }
}

1;
