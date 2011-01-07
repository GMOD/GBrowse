package Bio::Graphics::Browser2::Plugin::AuthPlugin;
# $Id#

use strict;
use Bio::Graphics::Browser2::Plugin;
use Bio::Graphics::Browser2::Util 'shellwords';
use CGI qw(:standard);
use base 'Bio::Graphics::Browser2::Plugin';

######################################################33
# OVERRIDE THESE METHODS
######################################################33
sub authenticate {
    my $self = shift;
    my ($name,$password) = $self->credentials;
    return;
}
# use this to return a hint about what type of account is wanted
sub authentication_hint {
    return 'your FooBar account';
}
sub user_in_group {
    my $self = shift;
    my ($user,$group) = @_;
    return;
}


######################################################33
# YOU MAY CUSTOMIZE THESE METHODS
######################################################33

sub name { "Basic Authorizer" }
sub description {
  p("This plugin implements a template authorizer.",
    "It was written by Lincoln Stein.");
}

sub type { 'authorizer' }

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
