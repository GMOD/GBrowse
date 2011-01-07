package Bio::Graphics::Browser2::Plugin::TestAuthorizer;
# $Id$
use strict;
use base Bio::Graphics::Browser2::Plugin::AuthPlugin;

sub authenticate {
    my $self = shift;
    my ($name,$password) = $self->credentials;
    warn "credentials = ('$name','$password')";
    return unless $name eq 'lincoln' && $password eq 'foobar';
    return ($name,'Lincoln Stein');  # username, fullname
}

# use this to return a hint about what type of account is wanted
sub authentication_hint {
    return 'your FooBar LDAP  account';
}

1;

__END__
