package Bio::Graphics::Browser::Plugin;
# $Id: Plugin.pm,v 1.5.4.1 2003-05-23 16:38:06 pedlefsen Exp $
# base class for plugins for the Generic Genome Browser

use strict;
use Bio::Graphics::Browser;
use CGI qw(param url header p);

use vars '$VERSION','@ISA','@EXPORT';
$VERSION = '0.11';

# currently doesn't inherit
@ISA = ();

# currently doesn't export
@EXPORT = ();

sub new {
  my $class = shift;
  return bless {}, ref($class)||$class; 
}

# initialize other globals
sub init {
  my $self = shift;
  # do nothing
}

sub name {
  my $self = shift;
  return "generic";
}

sub description {
  my $self = shift;
  return p("This is the base class for all GBrowse plugins.",
	   "The fact that you're seeing this means that the author of",
	   "this plugin hasn't yet entered a real description");
}

sub type {
  my $self = shift;
  return 'dumper';
}

sub mime_type {
  return 'text/plain';
}

sub config_defaults {
  my $self = shift;
  return;  # no configuration
}

sub configuration {
  my $self = shift;
  my $d = $self->{g_config};
  if (@_) {
    $self->{g_config} = shift;
  }
  $d;
}

sub configure_form {
  return;
}

sub reconfigure {
  my $self = shift;
  # do nothing
}

# just dump out the name of the thing
sub dump {
  my $self    = shift;
  my $segment = shift;
  print header('text/plain');
  print "This is the base class for all GBrowse plugins.\n",
    "The fact that you're seeing this means that the author of ",
      "this plugin hasn't yet implemented a real dump() method.\n";
}

sub find {
  my $self = shift;
  my $segment = shift;
  return ();
}

sub annotate {
  my $self = shift;
  my $segment = shift;
  # do nothing
  return;
}

# get/store Browser object representing this plugin's session.
sub browser_config {
  my $self = shift;
  my $d = $self->{ g_browser_config };
  $self->{ g_browser_config } = shift if @_;
  $d;
}

# get/store page settings
# it's a big hash as described in the notes of the gbrowse executable
sub page_settings {
  my $self = shift;
  my $d = $self->{g_page_settings};
  $self->{g_page_settings} = shift if @_;
  $d;
}

1;

