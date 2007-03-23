=head1 NAME

Bio::DB::Das::BioSQL::DBAdaptor - class that helps to use custom object adaptors

=head1 SYNOPSIS

    This is a private class.

=head1 DESCRIPTION

In order to use custom object adaptors in BioSQL, first one has to 
provide a custom "driver" class. Then the method 
_get_object_adaptor_class has to be overloaded to return
custom adaptors.

=head1 AUTHOR - Vsevolod (Simon) Ilyushchenko

Email simonf@cshl.edu

=cut

package Bio::DB::Das::BioSQL::DBAdaptor;

use strict;
use base 'Bio::DB::BioSQL::DBAdaptor';

use Bio::DB::Das::BioSQL::PartialSeqAdaptor;

sub _get_object_adaptor_class
{
    my ($self, $class) = @_;
    
    if ($class eq "Bio::Seq")
    {
        return "Bio::DB::Das::BioSQL::PartialSeqAdaptor";
    }
    
    return $self->SUPER::_get_object_adaptor_class($class);
}

1;
