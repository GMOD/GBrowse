package Bio::Graphics::Browser::Render::template;
#$Id: template.pm,v 1.2 2006-12-01 11:20:25 sheldon_mckay Exp $

# -- PLACEHOLDER -- #

# A class for rendering HTML for gbrowse
# contains non-template-specific methods

use strict;
use Carp 'croak','cluck';
use CGI ':standard';

use vars qw/$HEADER/;

use Data::Dumper;


sub new {
  my $caller  = shift;
  my $base    = shift;
  my $self    = bless {}, $caller;

  $self->base($base);
  $self->config($base->$config);
  return $self;
}

=head1 METHODS

=head2 config

Getter/setter for data source-specific configuration
and general utilities via a Bio::Graphics::Browser object.

=cut

sub config {
  my $self   = shift;
  my $config = shift;
  return $config ? $self->{config} = $config : $self->{config};
}


=head2 base

Getter/setter for the parent rendering object.  Provides access
to configuration and shared HTML rendering methods

=cut

sub base {
  my $self = shift;
  my $base = shift;
  return $base ? $self->{base} = $base : $self->{base};
}

=head2 setting

Pass though to Render.pm setting method

=cut

sub setting {
  my $self = shift;
  return $self->base->setting(@_);
}

=head2 global_setting

Pass though to Render.pm global_setting method

=cut

sub global_setting {
  return $self->base->global_setting(@_);
}




sub template_error {
  my $self = shift;
  my @msg = @_;

  my $config = $self->config;
  print_header( -expires => '+1m' );
  $config->template->process(
			          'error.tt2',
			     {   server_admin  => $ENV{SERVER_ADMIN},
				  error_message => join( "\n", @msg ),
			       }
			         )
      or warn $config->template->error();
  exit 0;
}


1;
