=head1 NAME

Bio::DB::GFF::Aggregator::coding -- An aggregator for coding regions

=head1 SYNOPSIS

  use Bio::DB::GFF;

  # Open the sequence database
  my $db      = Bio::DB::GFF->new( -adaptor => 'dbi:mysql',
                                   -dsn     => 'dbi:mysql:elegans42',
				   -aggregator => ['coding','clone'],
				 );


=head1 DESCRIPTION

Bio::DB::GFF::Aggregator::coding was written to work with the "cds"
glyph.  GFF files.  It aggregates raw "CDS" features into "coding"
features.  For compatibility with the idiosyncrasies of the Sanger GFF
format, it expects that the full range of the transcript is contained
in a feature of type "Sequence".

=cut

package Bio::DB::GFF::Aggregator::coding;

use strict;
use Bio::DB::GFF::Aggregator;

use vars qw($VERSION @ISA);
@ISA = qw(Bio::DB::GFF::Aggregator);

$VERSION = '1.00';

=head2 method

 Title   : method
 Usage   : $aggregator->method
 Function: return the method for the composite object
 Returns : the string "coding"
 Args    : none
 Status  : Public

=cut

sub method { 'coding' }

# sub require_whole_object { 1; }

=head2 part_names

 Title   : part_names
 Usage   : $aggregator->part_names
 Function: return the methods for the sub-parts
 Returns : the list "CDS"
 Args    : none
 Status  : Public

=cut

sub part_names {
  return qw(CDS);
}

=head2 main_name

 Title   : main_name
 Usage   : $aggregator->main_name
 Function: return the method for the main component
 Returns : the string "Sequence"
 Args    : none
 Status  : Public

=cut

sub main_name {
  return 'Sequence';
}

1;
__END__

=head1 BUGS

None reported.


=head1 SEE ALSO

L<Bio::DB::GFF>, L<Bio::DB::GFF::Aggregator>, L<Bio::Graphics::Glyph::cds>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2001 Cold Spring Harbor Laboratory.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

