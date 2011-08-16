=head1 NAME

Bio::DB::Synteny::Loader - superclass to load a Bio::DB::Synteny::Store

=head1 SYNOPSIS

see subclasses

=head1 METHODS

=cut

package Bio::DB::Synteny::Store::Loader;
use strict;

use base 'Bio::Root::Root';

use Bio::DB::GFF::Util::Rearrange qw(rearrange);

use constant VERBOSE  => 0;
use constant DEFAULT_MAPRES   => 100;

=head2 new( -store => $store, -format => $format )

Construct and configure a new loader object, which will load into the
given store.  Arguments and options:

=over 4

=item -store

The L<Bio::DB::Synteny::Store> object, which is the data store to load into.

=cut

sub new {
    my $class = shift;
    my ( $store, $format, $mapres ) = rearrange([qw[ STORE FORMAT MAPRES ]], @_ );
    return bless {
        store    => $store,
    }, ref $class || $class;
}

sub verbose { shift->{verbose}  }
sub store   { shift->{store}    }


1;

