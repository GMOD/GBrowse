package Bio::Graphics::Browser2::Plugin::TestAuthorizer;
# $Id$
use strict;
use base 'Bio::Graphics::Browser2::Plugin::AuthPlugin';

sub authenticate {
    my $self = shift;
    my ($name,$password) = $self->credentials;
    warn "credentials = ('$name','$password')";
    return unless $name eq 'lincoln' && $password eq 'foobar';
    return ($name,'Lincoln Stein');  # username, fullname
}


1;

__END__
