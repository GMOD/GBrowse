package Bio::DB::GFF::Aggregator::match_gap;
use strict;

################################################################################

use base 'Bio::DB::GFF::Aggregator';

################################################################################

=head1 NAME

Bio::DB::GFF::Aggregator::match_gap -- GFF3 match aggregator

=head1 SYNOPSIS

 -------------------------------------------------
 Aggregator method: match_gap
 Main method:       match
 Sub methods:       match
 -------------------------------------------------

=head1 DESCRIPTION

This aggregator is used for GFF3 style gapped alignments,
in which there is a single feature of method 'match' with
a 'Gap' attribute.

The 'Gap' attribute's format consists of a series of
(operartion,length) pairs separated by space characters,
for example: 'M8 D3 M6'.
(see GFF reference for complete explanation)

This module only recognizes the M and D operators, which
should be sufficient for simple nucleotide to nucleotide
alignments.

################################################################################

=cut

sub method {
	return 'match_gap';
}

sub part_names {
	return 'match';
}

sub main_name {
	return 'match';
}

sub require_whole_object {
	return 0;
}

sub aggregate {
	my $class = shift;
	my $features = shift;
	my @compound;
	foreach my $feature (@$features){
		if($feature->method eq 'match'){
			my $nf = $feature->clone;
			$nf->method('match_gap');
			my($offset, $start, $stop) = (0, $feature->start, $feature->stop);
			push @compound, $nf;		
			foreach my $code (split /\s+/, uc $feature->attributes('Gap')){
				my($op,$len) = split //, $code, 2;
				if($op eq 'M'){
					my $subf = $feature->clone;
					$subf->absolute(1);
					$subf->{start} = $start + $offset;
					$subf->{stop} = $start + $offset + $len - 1;
					$subf->method('HSP');
					$nf->add_subfeature($subf);
					$offset += $len;
				}
				elsif($op eq 'D'){
					$offset += $len;
				}
			}
		    $nf->adjust_bounds;
		}
	}
	push @$features, @compound;
	return $features;
}

################################################################################
1;

__END__

=head1 BUGS

None reported.

=head1 SEE ALSO

L<Bio::DB::GFF>, L<Bio::DB::GFF::Aggregator>

=head1 AUTHOR

Dmitri Bichko

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

