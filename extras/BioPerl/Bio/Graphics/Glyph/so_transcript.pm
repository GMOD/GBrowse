package Bio::Graphics::Glyph::so_transcript;

# $Id: so_transcript.pm,v 1.1.2.5.2.12 2006-07-17 21:05:44 scottcain Exp $

use strict;
use Bio::Graphics::Glyph::processed_transcript;
use vars '@ISA','$VERSION';
@ISA = 'Bio::Graphics::Glyph::processed_transcript';
$VERSION = '1.0';

1;


__END__

=head1 NAME

Bio::Graphics::Glyph::so_transcript - The sequence ontology transcript glyph

=head1 SYNOPSIS

  See L<Bio::Graphics::Panel> and L<Bio::Graphics::Glyph>.

=head1 DESCRIPTION

This is a sequence-ontology compatible glyph, which works hand-in-hand
with the so_transcript aggregator in BioPerl.

This glyph is identical to "processed_transcript," which is described
in detail in L<Bio::Graphics::Glyph::processed_transcript>.

=head1 BUGS

Please report them.

=head1 SEE ALSO

L<Bio::Graphics::Panel>,
L<Bio::Graphics::Glyph>,
L<Bio::Graphics::Glyph::processed_transcript>,
L<Bio::DB::GFF::Aggregators::so_transcript>,
L<GD>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>

Copyright (c) 2005 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut
