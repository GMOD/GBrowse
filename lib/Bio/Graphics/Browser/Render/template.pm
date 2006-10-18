package Bio::Graphics::Browser::Render::template;
#$Id: template.pm,v 1.1 2006-10-18 18:38:35 sheldon_mckay Exp $

# -- PLACEHOLDER -- #

# A class for rendering HTML for gbrowse
# contains non-template-specific methods

use strict;
use Carp 'croak','cluck';
use Bio::Graphics::Browser;
use CGI ':standard';
use Bio::Graphics::Browser::Render;

use vars qw/@ISA/;
@ISA = Bio::Braphics::Browser::Render;

sub new {
  my $self = shift;
  return bless $self;
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
