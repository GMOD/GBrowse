package Bio::Graphics::Browser::Plugin;
# $Id: Plugin.pm,v 1.1 2002-03-24 23:18:47 lstein Exp $
# base class for plugins for the Generic Genome Browser

use strict;
use Bio::Graphics::Browser;
use CGI qw(param url header p);

use vars '$VERSION','@ISA','@EXPORT';
$VERSION = '0.10';

# currently doesn't inherit
@ISA = ();

# currently doesn't export
@EXPORT = ();

sub new {
  my $class = shift;
  return bless {},$class;
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

sub configure {
  my $self = shift;
  my $configuration = shift;
  # do nothing
}

sub change_configuration {
  my $self = shift;
  my ($conf_name,@conf_values) = @_;
  # do nothing
}

# get/store database
sub database {
  my $self = shift;
  my $d = $self->{g_database};
  $self->{g_database} = shift if @_;
  $d;
}

# get/store configuration file
# it's a Bio::Graphics::Browser file
sub config_file {
  my $self = shift;
  my $d = $self->{g_config_file};
  $self->{g_config_file} = shift if @_;
  $d;
}

# get/store configuration directory path
sub config_path {
  my $self = shift;
  my $d = $self->{g_config_path};
  $self->{g_config_path} = shift if @_;
  $d;
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


1;

