package Bio::Graphics::Browser::CAlign;

use 5.005;
use Carp;
use vars qw(@ISA @EXPORT @EXPORT_OK $VERSION);
use strict;

require Exporter;
require DynaLoader;

@ISA = qw(Exporter DynaLoader);
@EXPORT    = ();
@EXPORT_OK = qw(align);

$VERSION = '1.00';
bootstrap Bio::Graphics::Browser::CAlign $VERSION;

sub align {
  my $class = shift;
  my ($src,$tgt,$matrix) = @_;
  return $class->_do_alignment($src,$tgt,$matrix);
}

1;
__END__

=head1 NAME

Bio::Graphics::Browser::CAlign - Compiled helper for Bio::Graphics::Browser::Realign

=head1 SYNOPSIS

No user serviceable parts.

=head1 DESCRIPTION

This module is used internally by Bio::Graphics::Browser::Realign.  If
the module is present, the Smith-Waterman alignment will be faster.
Otherwise, Bio::Graphics::Browser::Realign will fall back to a slower
pure-perl implementation.

=head1 SEE ALSO

L<Bio::Graphics::Browser::Realign>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2003 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut
