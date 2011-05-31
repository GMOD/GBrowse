package Bio::Graphics::Browser2::Plugin::OICRAuthenticate;

# $Id$
use strict;
use base 'Bio::Graphics::Browser2::Plugin::AuthPlugin';

use Net::LDAP;
use constant SERVER        => 'ldap.res.oicr.on.ca';
use constant PEOPLE_BASE   => 'ou=People,dc=oicr,dc=on,dc=ca';
use constant GROUPS_BASE   => 'ou=Groups,dc=oicr,dc=on,dc=ca';

sub authenticate {
    my $self = shift;
    my ($name,$password) = $self->credentials;

    my $ldap = $self->_ldap_connect or return;

    # do an anonymous search to get the dn with which to bind
    my $search = $ldap->search(
	base   => PEOPLE_BASE,
	filter => "(&(objectClass=posixAccount)(uid=$name))"
	)  or die $@;
    return unless $search->count == 1;

    my $entry  = $search->entry(0);

    # now attempt to authenticate with the password
    my $message = $ldap->bind($entry->dn, password => $password);
    return if $message->is_error;

    # get user's full name from the gecos field
    my ($gecos) = $entry->get('gecos');
    $ldap->unbind;

    return ($name,$gecos||$name);
}

sub user_in_group {
    my $self = shift;
    my ($user,$group) = @_;
    
    my $ldap = $self->_ldap_connect or return;

    # do an anonymous search for the posix group with the
    # indicated uid member.
    my $search = $ldap->search(
	base   => GROUPS_BASE,
	filter => "(&(objectClass=posixGroup)(memberUid=$user))"
	);
    my @entries = $search->entries;

    my %groups  = map {$_->get('cn')=>1} @entries;
    $ldap->unbind;

    return $groups{$group};
}

sub _ldap_connect {
    my $self = shift;
    my $ldap = Net::LDAP->new(SERVER);
    unless ($ldap) {
	warn "Could not connect to server ",SERVER;
	return;
    }    
    return $ldap;
}

1;

__END__

=head1 NAME

Bio::Graphics::Browser2::Plugin::OICRAuthenticate - Authenticate user OICR's LDAP system

=head1 SYNOPSIS

In the appropriate gbrowse configuration file:

 authentication plugin = OICRAuthenticate

=head1 DESCRIPTION

This plugin uses hard-coded values to authenticate users against the
OICR LDAP database. Users can log in using their Unix login names and
passwords (LDAP "posixAccount"). Groups are authorized against the
posixGroup memberUID fields.

=head1 SEE ALSO

L<Bio::Graphics::Browser2::Plugin>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@oicr.on.caE<gt>.

Copyright (c) 2011 Ontario Institute for Cancer Research

This library is free software distributed under the Perl Artistic License v2; 
you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

