package Bio::Graphics::Browser2::Plugin::LDAPAuthenticate;

# $Id$
use strict;
use base 'Bio::Graphics::Browser2::Plugin::AuthPlugin';

use Net::LDAP;
use Carp 'croak';
#use constant SERVER        => 'ldap.res.oicr.on.ca';
#use constant PEOPLE_BASE   => 'ou=People,dc=oicr,dc=on,dc=ca';
#use constant GROUPS_BASE   => 'ou=Groups,dc=oicr,dc=on,dc=ca';

sub authenticate {
    my $self = shift;
    my ($name,$password) = $self->credentials;

    my $ldap = $self->_ldap_connect or return;

    # possibly bind to the server if a root DN and password are needed
    $self->_initial_bind($ldap);

    # do a search to get the user dn with which to bind
    my $search = $ldap->search(
	base   => $self->people_base,
	filter => "(&(objectClass=posixAccount)(uid=$name))"
	)  or die $@;
    return unless $search->count == 1;

    my $entry  = $search->entry(0);

    # now attempt to authenticate with the password
    my $message = $ldap->bind($entry->dn, password => $password);
    return if $message->is_error;

    # get user's full name from the gecos and/or cn/sn fields
    my ($gecos)   = $entry->get('gecos');
    $gecos        =~ s/,+$//;   # trailing unused fields
    my $fullname  = join ' ',($entry->get('cn'),$entry->get('sn'));
    $ldap->unbind;
    return ($name,$gecos||$fullname||$name);
}

sub user_in_group {
    my $self = shift;
    my ($user,$group) = @_;
    
    my $ldap = $self->_ldap_connect or return;

    # do an anonymous search for the posix group with the
    # indicated uid member.
    my $search = $ldap->search(
	base   => $self->groups_base,
	filter => "(&(objectClass=posixGroup)(memberUid=$user))"
	);
    my @entries = $search->entries;

    my %groups  = map {$_->get('cn')=>1} @entries;
    $ldap->unbind;

    return $groups{$group};
}

sub _ldap_connect {
    my $self = shift;
    my $ldap = Net::LDAP->new($self->server);
    unless ($ldap) {
	warn "Could not connect to server ",$self->server;
	return;
    }    
    return $ldap;
}

sub _initial_bind {
    my $self = shift;
    my $ldap = shift;
    my $bind_dn    = $self->bind_dn   or return;
    my $bind_pass  = $self->bind_pass or return;
    my $message    = $ldap->bind($bind_dn,password=>$bind_pass);
    return unless $message->is_error;
    my $text = $message->error_text;
    warn <<END;
Error during initial binding to $bind_dn:
    '$text'
All LDAP logins may fail.
END
;
}

sub server {
    return shift->required_setting('ldap server'); 
}

sub people_base {
    return shift->required_setting('people base');
}

sub groups_base {
    return shift->required_setting('groups base');
}

sub bind_dn {
    return shift->setting('bind dn');
}

sub bind_pass {
    return shift->setting('bind pass');
}

sub required_setting {
    my $self   = shift;
    my $option = shift;
    my $value  = $self->setting($option);
    croak "You must set the '$option' option in the [LDAPAuthenticate:plugin] section of GBrowse.conf\n"
	unless defined $value;
    return $value;
}

1;

__END__

=head1 NAME

Bio::Graphics::Browser2::Plugin::LDAPAuthenticate - Authenticate user against an LDAP server

=head1 SYNOPSIS

In the GBrowse.conf configuration file:

 authentication plugin = LDAPAuthenticate

 [LDAPAuthenticate:plugin]
 login hint = your foobar corp account
 ldap server = ldap.foobar.com
 people base = ou=People,dc=foobar,dc=ny,dc=usa
 groups base = ou=Groups,dc=foobar,dc=ny,dc=usa
 # the following only needed if the LDAP server forbids anonymous (unbound) searches:
 bind dn    = uid=root,ou=People,dc=foobar,dc=ny,dc=usa
 bind pass  = xyzzy

=head1 DESCRIPTION

This plugin uses hard-coded values to authenticate users against an
LDAP database. Users can log in using their Unix login names and
passwords (LDAP "posixAccount"). Groups are authorized against the
posixGroup memberUID fields.

=head1 CONFIGURATION

For this plugin to work, you must configure an [LDAPAuthenticate:plugin] section
in the main GBrowse.conf file. It will look like this:

 [LDAPAuthenticate:plugin]
 login hint = your foobar corp account
 ldap server = ldap.foobar.com
 people base = ou=People,dc=foobar,dc=ny,dc=usa
 groups base = ou=Groups,dc=foobar,dc=ny,dc=usa

B<login hint> (optional) is displayed to the user so that he knows
what account credentials he or she is being asked for.

B<ldap server> (required) is the address of the LDAP server you wish
to contact. If the server is running on a non-standard, port, you can
indicate it as "ldap.foobar.com:1118".

B<people base> (required) is the search base for the People records
where the provided user id will be found.

B<groups base> (required) is the search base for the Group records
where the user's group membership can be determined.

In addition, if your LDAP server requires a username and password to
bind to B<before> permitting searches, then you will need to provide:

B<bind dn> (optional) the distinguished name of the LDAP user to bind to.
This is often called the LDAP "root" user.

B<bind pass> (optional) the password of the LDAP user to bind to.

Note that providing this bind user's account name and password in a
file that is readable by the web server can be considered a security
risk. Consider allowing anonymous searches on the LDAP server, or else
create an unprivileged user account for the initial binding step.

=head1 SEE ALSO

L<Bio::Graphics::Browser2::Plugin>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@oicr.on.caE<gt>.

Copyright (c) 2011 Ontario Institute for Cancer Research

This library is free software distributed under the Perl Artistic License v2; 
you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

