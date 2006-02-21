=head1 NAME

Bio::DB::GFF::Aggregator::chromosome -- Chromosome aggregator

=head1 SYNOPSIS

  use Bio::DB::GFF;

  # Open the sequence database
  my $db      = Bio::DB::GFF->new( -adaptor => 'dbi:mysql',
                                   -dsn     => 'dbi:mysql:human',
				   -aggregator => ['chromosome'],
				 );

 ----------------------------------------------------------------------------
 Aggregator method: chromosome
 Main method:       -none-
 Sub methods:       cytoband cytological_band chromosome_band centromere
 ----------------------------------------------------------------------------

=head1 DESCRIPTION

Bio::DB::GFF::Aggregator::chromosome aggregates chromosome parts
for drawing ideograms.  It aggregates features of type cytoband,
centromere, and the SO terms chromosome_arm, chromosome_band and
cytological_band into a composite 'chromosome' feature.

=cut

package Bio::DB::GFF::Aggregator::chromosome;

# $Id: chromosome.pm,v 1.1 2006-02-21 04:49:16 sheldon_mckay Exp $

use strict;

use Bio::DB::GFF::Aggregator;
use Bio::DB::GFF::Featname;
use Data::Dumper;

use vars qw(@ISA);

@ISA = qw(Bio::DB::GFF::Aggregator);

=head2 aggregate

 Title   : aggregate
 Usage   : $features = $a->aggregate($features,$factory)
 Function: aggregate a feature list into composite features
 Returns : an array reference containing modified features
 Args    : see L<Bio::DB::GFF::Aggregator>
 Status  : Public

=cut


# aggregate whole chromosomes, match criteria are 
# simply one of the listed sub parts and the same
# reference sequence.  The features do not need to be
# grouped in the Group field.
sub aggregate {
  my $self = shift;
  my $features = shift;
  my @parts = $self->part_names;
  my %chromosome;

  for my $f (@$features) {
    next unless grep  {$_ eq $f->method} @parts;
    my $ref  = $f->ref;

    $chromosome{$ref} ||= $f->clone;
    $chromosome{$ref}->method($self->method);
    $chromosome{$ref}->compound(1);

    $chromosome{$ref}->add_subfeature($f);
    $chromosome{$ref}->adjust_bounds;
  }

  unshift @$features, values %chromosome;

  return $features;
}

=head2 method

 Title   : method
 Usage   : $aggregator->method
 Function: return the method for the composite object
 Returns : the string "chromosome"
 Args    : none
 Status  : Public

=cut

sub method { 
  return 'chromosome'; 
}

=head2 part_names

 Title   : part_names
 Usage   : $aggregator->part_names
 Function: return the methods for the sub-parts
 Returns : the list (cytoband, cytological_band, chromosome_band, centromere)
 Args    : none
 Status  : Public

=cut

# cytoband is not a SO term -- deprecate eventually
sub part_names {
  return qw/cytoband cytological_band chromosome_band centromere/;
}

1;

__END__

=head1 BUGS

None reported.

=head1 SEE ALSO

L<Bio::DB::GFF>, L<Bio::DB::GFF::Aggregator>

=head1 AUTHOR

Sheldon McKay E<lt>mckays@cshl.eduE<gt>.

Copyright (c) 2006 Cold Spring Harbor Laboratory.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

