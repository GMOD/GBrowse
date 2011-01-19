package Bio::Graphics::Browser2::Plugin::AuthPlugin;
# $Id#

=head1 NAME

Bio::Graphics::Browser2::Plugin::AuthPlugin -- Base class for authentication plugins

=head1 SYNOPSIS

 package Bio::Graphics::Browser2::Plugin::MyPlugin;
 use base 'Bio::Graphics::Browser2::Plugin::AuthPlugin';

 sub authenticate {
     my $self = shift;
     my ($user,$password) = $self->credentials;
     return unless  $user eq 'george' && $password eq 'washington';
     return ($user,'George Washington','george@whitehouse.gov');
 }

 sub user_in_group {
     my $self = shift;
     my ($user,$group) = @_;
     return $user eq 'george' && $group eq 'potomac';
 }

=head1 DESCRIPTION

This is a template for authorizer plugins. To define a new type of
authorizer, you need only inherit from this class and define an
authenticate() method. This method takes two arguments: the username
and password and returns an empty list if authentication fails, or a 
list of (username, fullname, email) if authentication succeeds (fullname
and email are optional).

In addition, you may override the user_in_group() method, which takes
two argumetns: the username and group. Return true if the user belongs
to the group, and false otherwise.

Other methods you may wish to override include:

 * authentication_hint()
 * authentication_help()
 * configure_form()
 * reconfigure()
 * credentials()

These are described below.

=cut


use strict;
use Bio::Graphics::Browser2::Plugin;
use Bio::Graphics::Browser2::Util 'shellwords';
use CGI qw(:standard);
use base 'Bio::Graphics::Browser2::Plugin';

=head2 Methods you will need to override

=over 4

=item $boolean = $plugin->authenticate($username,$password)

Return true if username and password are correct. False otherwise.

=item $boolean = $plugin->user_in_group($username,$groupname)

Return true if user belongs to group. False otherwise.

=back

=cut

######################################################33
# OVERRIDE THESE METHODS
######################################################33
sub authenticate {
    my $self = shift;
    my ($name,$password) = $self->credentials;
    return;
}
sub user_in_group {
    my $self = shift;
    my ($user,$group) = @_;
    return;
}

=head2 Methods that you may want to customize

=over 4

=item $message = $plugin->authentication_hint

Returns a message printed at the top of the login dialog, that will
help the user know which credentials he is expected to present. For
example, returning "Acme Corp Single Sign-on" will present the user
with "Please log into your Acme Corp Single Sign-on".

The default behavior is to take this value from the "login hint"
option in a stanza named [AuthPlugin:plugin]. Example:

=item $message = $plugin->authentication_help

Returns a message printed at the bottom of the login dialog. It is 
expected to be used for a help message or link that will give the user
help with logging in. For example, it can take him to a link to reset
his password.

The default behavior is to take this value from the "login help"
option in a stanza named [AuthPlugin:plugin].

  [AuthPlugin:plugin]
  login hint = your Acme Corp Single Sign-on Account
  login help = <a href="www.acme.com/passwd_help">Recover forgotten password</a>

=back

=cut

######################################################33
# YOU MAY CUSTOMIZE THESE METHODS
######################################################33

# use this to return a hint about what type of account is wanted
sub authentication_hint {
    my $self = shift;
    return $self->setting('login hint');
}
sub authentication_help {
    my $self = shift;
    return $self->setting('login help');
}

sub name { "Authorizer Template" }
sub description {
  p("This plugin implements a template authorizer.",
    "It was written by Lincoln Stein.");
}

sub type { 'authenticator' }

=head2 Methods that you may want to override

=over 4

=item $html = $plugin->configure_form()

This method returns the contents of the login form. The default
behavior is to produce two text fields, one named 'name' and the
other named 'password'.

=item $plugin->reconfigure()

This method is called to copy the values from the filled-out form into
the plugin's hash of configuration variables. If you add fields to
configure_form() will you need to adjust this method as well.

=item $plugin->config_defaults()

Set up defaults for the configuration hash. Use this if you wish to
default to a particular username.

=item $plugin->credentials()

This returns a two-element list containing the username and password
last entered into the authentication dialog. It reads these values
from the configuration hash returned by $self->configuration().
If you add additional types of credentials to the login dialog, you 
may need to override this method.

=back

=cut

sub config_defaults {
    my $self = shift;
    return { };
}

sub reconfigure {
  my $self = shift;
  my $current_config = $self->configuration;
  $current_config->{name} = $self->config_param('name');
  $current_config->{pass} = $self->config_param('password');
}

sub configure_form {
    my $self = shift;
    my $current_config = $self->configuration;
    return table(
	TR(th({-align=>'right'},'Name'),
	   td(textfield(-name  => $self->config_name('name'),
			-value => $current_config->{name},
			-size  => 20))),
	TR(th({-align=>'right'},'Password'),
	   td(password_field(-name  => $self->config_name('password'),
			     -value => '',
			     -override=>1,
			     -size  => 20)))
	);
}

sub credentials {
    my $self = shift;
    my $current_config = $self->configuration;
    return ($current_config->{name},
	    $current_config->{pass});
}

1;

__END__

=head1 SEE ALSO

L<Bio::Graphics::Browser2>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.com<gt>.

Copyright (c) 2011 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

