package Bio::Graphics::Browser2::Plugin::PamAuthenticate;

# $Id$
use strict;
use base 'Bio::Graphics::Browser2::Plugin::AuthPlugin';

use Authen::Simple::PAM;
use User::grent;
use User::pwent;
use constant DEFAULT_PAM_SERVICE => 'gbrowse';

sub authenticate {
    my $self = shift;
    my ($name,$password) = $self->credentials;
    my $service_name     = $self->setting('pam service name') || 'gbrowse';
    my $pam = Authen::Simple::PAM->new(
	service => $service_name
	) or return;
    if ($pam->authenticate($name,$password)) {
	my $fullname = $self->_get_fullname($name);
	return ($name,$fullname||$name);
    } else {
	return;
    }
}

sub user_in_group {
    my $self = shift;
    my ($user,$group) = @_;
    if ($self->_is_primary_group($user,$group)) {
	return 1;
    }
    my $members = $self->_group_members($group) or return;
    return $members->{$user};
}

sub _get_fullname {
    my $self = shift;
    my $username = shift;
    my $u = getpwnam($username) or return;
    my ($fullname,$office,$phone1,$phone2) =
	split /\s*,\s*/, $u->gecos;
    return $fullname;
}

sub _is_primary_group {
    my $self = shift;
    my ($user,$group) = @_;
    my $gid = eval {getgrnam($group)->gid};
    defined $gid or return;
    my $ugid= eval {getpwnam($user)->gid};
    defined $ugid or return;
    return $gid == $ugid;
}

sub _group_members {
    my $self  = shift;
    my $group = shift;
    return $self->{groupcache}{$group} 
           if exists $self->{groupcache}{$group};
    $self->{groupcache}{$group} = {};
    if (my $gr = getgrnam($group)) {
	my $members = $gr->members;
	foreach (@$members) {
	    $self->{groupcache}{$group}{$_}++;
	}
    }
    return $self->{groupcache}{$group};
}


1;

__END__

=head1 NAME

Bio::Graphics::Browser2::Plugin::PamAuthenticate - Authenticate user via Pluggable Authentication Modules

=head1 SYNOPSIS
