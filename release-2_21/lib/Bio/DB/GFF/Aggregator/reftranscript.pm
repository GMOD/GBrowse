=head1 NAME

package Bio::DB::GFF::Aggregator::reftranscript -- Aggregates references transcripts

=head1 SYNOPSIS

use Bio::DB::GFF::Aggregator;

=head1 DESCRIPTION

Bio::DB::GFF::Aggregator::retranscript was written to make the compound 
feature, "reftranscript" for use with Gbrowse editing software 
developed outside of the GMOD development group.  It can be used to 
aggregate "reftranscripts" from "refexons", loaded as second copy 
features.  These features, in contrast to "transcripts", are usually 
implemented as features which cannot be edited and serve as starting
point references for annotations added using Gbrowse for feature 
visualization.

Adding features to the compound feature, "reftranscript", can be done 
by adding to the "part_names" call (i.e. "refCDS").

=cut

package Bio::DB::GFF::Aggregator::reftranscript;

use strict;
use Bio::DB::GFF::Aggregator;

use vars qw($VERSION @ISA);
@ISA = qw(Bio::DB::GFF::Aggregator);

$VERSION = '0.10';

=head2 method

 Title   : method
 Usage   : $aggregator->method
 Function: return the method for the composite object
 Returns : the string "reftranscript"
 Args    : none
 Status  : Public

=cut

sub method { 'reftranscript' }

=head2 part_names

 Title   : part_names
 Usage   : $aggregator->part_names
 Function: return the methods for the sub-parts
 Returns : the list "refexon"
 Args    : none
 Status  : Public

=cut

sub part_names {
    return qw(refexon);
}

=head2 main_name

 Title   : main_name
 Usage   : $aggregator->main_name
 Function: return the method for the main component
 Returns : the string "reftranscript"
 Args    : none
 Status  : Public

=cut

sub main_name {
    return 'reftranscript';
}

1;
__END__

=head1 BUGS

None reported.


=head1 SEE ALSO

L<Bio::DB::GFF>, L<Bio::DB::GFF::Aggregator>

=head1 AUTHOR

Paul Rudnick E<lt>rudnick@ncifcrf.govE<gt>.

Copyright (c) 2002 Advanced Biomedical Computing Center, SAIC/NCI-Frederick.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
