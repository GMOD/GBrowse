package Bio::Graphics::Browser2::Plugin::TestAuthorizer;
# $Id$
use strict;
use Bio::Graphics::Browser2::Plugin;
use Bio::Graphics::Browser2::Util 'shellwords';
use CGI qw(:standard);
use base 'Bio::Graphics::Browser2::Plugin';

sub name { "Test Authorizer" }
sub description {
  p("This plugin implements a simple authorizer.",
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
  warn "name=$current_config->{name}";
  warn "pass=$current_config->{pass}";
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

sub authenticate {
    my $self = shift;
    my ($name,$password) = $self->credentials;
    return $name eq 'lincoln' && $password eq 'foobar';
}

1;

__END__
