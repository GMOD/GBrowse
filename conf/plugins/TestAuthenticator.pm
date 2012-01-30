package Bio::Graphics::Browser2::Plugin::TestAuthenticator;
# $Id$
use strict;
use base 'Bio::Graphics::Browser2::Plugin::AuthPlugin';

sub authenticate {
    my $self = shift;
    my ($name,$password) = $self->credentials;
    if ($name eq 'lincoln' && $password eq 'foobar') {
	return ($name,'Lincoln Stein');  # username, fullname	
    } elsif ($name eq 'jane' && $password eq 'foobar') {
	return ($name,'Jane Doe');
    }
    return;
}


1;

__END__
