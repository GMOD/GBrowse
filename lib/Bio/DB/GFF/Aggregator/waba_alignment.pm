=head1 NAME

Bio::DB::GFF::Aggregator::waba_alignment -- A WABA alignment

=head1 SYNOPSIS

  use Bio::DB::GFF;

  # Open the sequence database
  my $db      = Bio::DB::GFF->new( -adaptor => 'dbi:mysql',
                                   -dsn     => 'dbi:mysql:elegans42',
				   -aggregator => ['waba_alignment'],
				 );
  # fetch the synthetic feature type "waba_alignment"
  my @waba    = $db->features('waba_alignment');


=head1 DESCRIPTION

Bio::DB::GFF::Aggregator::waba_alignment handles the type of
alignments produced by Jim Kent's WABA program, and was written to be
compatible with the C elegans GFF files.  It aggregates the following
feature types into an aggregate type of "waba_alignment":

   similarity:WABA_weak
   similarity:WABA_strong
   similarity:WABA_coding

=cut

package Bio::DB::GFF::Aggregator::waba_alignment;

use strict;
use Bio::DB::GFF::Aggregator;

use vars qw($VERSION @ISA);
@ISA = qw(Bio::DB::GFF::Aggregator);

$VERSION = '0.10';

=head2 method

 Title   : method
 Usage   : $aggregator->method
 Function: return the method for the composite object
 Returns : the string "waba_alignment"
 Args    : none
 Status  : Public

=cut

sub method { 'waba_alignment' }

=head2 part_names

 Title   : part_names
 Usage   : $aggregator->part_names
 Function: return the methods for the sub-parts
 Returns : the list "similarity:WABA_weak", "similarity:WABA_strong" and "similarity:WABA_coding"
 Args    : none
 Status  : Public

=cut

sub part_names {
  return qw(
   similarity:WABA_weak
   similarity:WABA_strong
   similarity:WABA_coding
);
}

sub aggregate {
  my $self = shift;
  my ($features,$factory) = @_;
  $self->SUPER::aggregate($features,$factory);
  foreach (@$features) {
    $_->source('WABA');
  }
}

1;
__END__

=head1 BUGS

None reported.


=head1 SEE ALSO

L<Bio::DB::GFF>, L<Bio::DB::GFF::Aggregator>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2001 Cold Spring Harbor Laboratory.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

