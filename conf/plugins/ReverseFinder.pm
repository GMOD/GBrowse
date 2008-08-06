package Bio::Graphics::Browser::Plugin::ReverseFinder;
# $Id: ReverseFinder.pm,v 1.1.2.1 2008-08-06 16:21:01 lstein Exp $
# test plugin
use strict;
use Bio::Graphics::Browser::Plugin;
use Bio::Graphics::Feature;
use Text::Shellwords;
use DBI;
use CGI qw(:standard *table);

use vars '$VERSION','@ISA';
$VERSION = '0.15';

@ISA = qw(Bio::Graphics::Browser::Plugin);

sub name { "Reversed names" }

sub description {
  p("This plugin will search the database for the REVERSE of the search string.",
    "It is just a demo and debugging tool."),
  p("This plugin was written by Lincoln Stein.");
}

sub type { 'finder' }

sub config_defaults {
  my $self = shift;
  return { drowyek => ''};
}

sub reconfigure { 
    my $self = shift;
    my $current_config         = $self->configuration;
    $current_config->{drowyek} = $self->config_param('drowyek');
}

sub configure_form {
  my $self    = shift;
  my $current = $self->configuration;
  return 
      table(TR({-class=>'searchtitle'},
	       th({-colspan=>2,-align=>'LEFT'},
		  'Enter a feature name in reverse order')),
	    TR({-class=>'searchbody'},
	       th('Enter reversed name:'),
	       td(textfield(-name=>$self->config_name('drowyek'),
			    -size=>50,-width=>50,
			    -default=>$current->{drowyek},
		  )
	       )
	    )
      );
}

# find() returns undef unless the OligoFinder.drowyek parameter
# is specified and valid.  Returning undef signals the browser to invoke the
# configure_form() method.
# If successful, it returns an array ref of Bio::SeqFeatureI objects.
sub find {
  my $self     = shift;
  my $segments = shift; # current segments - can search inside them or ignore
                        # In this example we do a global search.

  my $drowyek = $self->config_param('drowyek');
  $self->auto_find($drowyek);
}

# auto_find() does the actual work
# It is also called by the main page as a last resort when the user
# types something into the search box that isn't recognized.
sub auto_find {
  my $self    = shift;
  my $drowyek = shift;

  my $keyword = reverse $drowyek;
  my $db    = $self->database or die "I do not have a database";

  my @features = $db->get_features_by_alias($keyword);
  return (\@features,$drowyek);
}

1;
