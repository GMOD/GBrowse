package Bio::Graphics::Browser::Plugin;
# $Id: Plugin.pm,v 1.6 2003-05-13 01:08:38 lstein Exp $
# base class for plugins for the Generic Genome Browser

=head1 NAME

Bio::Graphics::Browser::Plugin -- Base class for gbrowse plugins.

=head1 SYNOPSIS

 package Bio::Graphics::Browser::Plugin::MyPlugin;
 use Bio::Graphics::Browser::Plugin;
 use CGI ':standard';
 @ISA = 'Bio::Graphics::Browser::Plugin';

 # called by gbrowse to return name of plugin for popup menu
 sub name        { 'Example Plugin' }

 # called by gbrowse to return description of plugin
 sub description { 'This is an example plugin' }

 # called by gbrowse to return type of plugin
 sub type        { 'annotator' }

 # called by gbrowse to configure default settings for plugin
 sub config_defaults {
     my $self = shift;
     return {foo => $value1,
             bar => $value2}
 }

 # called by gbrowse to reconfigure plugin settings based on CGI parameters
 sub reconfigure {
   my $self = shift;
   my $current = $self->configuration;
   $current->{foo} = $self->param('foo');
   $current->{bar} = $self->param('bar');
 }

 # called by gbrowse to create a <form> fragment for changing settings
 sub configure_form {
   my $self    = shift;
   my $current = $self->configuration;
   my $form = textfield(-name  => $self->pname('foo'),
                        -value => $current->{foo})
              .
              textfield(-name  => $self->pname('bar'),
                        -value => $current->{bar});
   return $form;
 }

 # called by gbrowse to annotate the DNA, returning features
 sub annotate {
    my $self     = shift;
    my $segment  = shift;
    my $config   = $self->configuration;
    # do something with the sequence segment
    my @features = do_something();
    return \@features;
 }

=head1 DESCRIPTION

This is the base class for Generic Genome Browser plugins.  Plugins
are perl .pm files that are stored in the gbrowse.conf/plugins
directory.  There are three types of plugins:

=over 4

=item 1) dumpers

These plugins receive the genomic segment object and generate a dump
-- the output can be text, html or some other specialized
format. Example: GAME dumper.

=item 2) finders

These plugins accept input from the user and return a
list of genomic regions.  The main browser displays the found regions
and allows the user to select among them. Example: BLAST search.

=item 3) annotators 

These plugins receive the genomic segment object and return a list of
features which are overlayed on top of the detailed view.  Example:
restriction site annotator.

=back
	
All plug-ins inherit from Bio::Graphics::Browser::Plugin.  It defines
reasonable defaults for each of the methods.  Specific behavior is
then implemented by selectively overriding certain methods.

The best way to understand how this works is to look at some simple
plugins.  Examples provided with the gbrowse distribution include:

=over 4

=item GFFDumper.pm

A 

=back

=head1 METHODS

The remainder of this document describes the methods available to the
programmer.

=head2 CONFIGURATION ACCESS METHODS

The following methods can be called to retrieve data about the
environment in which the plugin is running.  These methods are also
used by gbrowse to change the plugin state.  See the section at the
end of this document for more details.

=over 4

=item $config = $self->config_defaults()

This method will be called once at plugin startup time to give the
plugin a chance to set up its default configuration state.  The
configuration is represented as a hash reference.  If the plugin has no
configuration, this method does not need to be implemented.

=item $config = $self->configuration()

Retrieve the persistent configuration for this plugin.  The
configuration is a hashref.  Due to cookie limitations, the values of
the hashref must be scalars or array references.

=item 


=cut



use strict;
use Bio::Graphics::Browser;
use CGI qw(param url header p);

use vars '$VERSION','@ISA','@EXPORT';
$VERSION = '0.15';

# currently doesn't inherit
@ISA = ();

# currently doesn't export
@EXPORT = ();

sub new {
  my $class = shift;
  return bless {},$class;
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

# get/store database
sub database {
  my $self = shift;
  my $d = $self->{g_database};
  $self->{g_database} = shift if @_;
  $d;
}

# get/store configuration file
# it's a Bio::Graphics::Browser file
sub browser_config {
  my $self = shift;
  my $d = $self->{g_config_file};
  $self->{g_config_file} = shift if @_;
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

sub pkg {
  my $self  = shift;
  my $class = ref $self or return;
  $class =~ /(\w+)$/    or return;
  return $1;
}

sub param {
  my $self = shift;
  my $pkg  = $self->pkg;
  unless (@_) {
    my @result;
    foreach (CGI::param()) {
      next unless /^$pkg\.(.+)/;
      push @result,$1;
    }
    return @result;
  }
  CGI::param($self->pname(shift()));
}

sub pname {
  my $self = shift;
  my $name = shift;
  my $pkg = $self->pkg;
  return "$pkg.$name";
}

sub selected_tracks {
  my $self = shift;
  my $page_settings = $self->page_settings;
  return grep {$page_settings->{features}{$_}{visible}} @{$page_settings->{tracks}};
}

sub selected_features {
  my $self = shift;
  my $conf   = $self->browser_config;
  my @tracks = $self->selected_tracks;
  return map {$conf->config->label2type($_)} @tracks;
}

1;

__END__


=head1 SEE ALSO

L<Bio::Graphics::Browser>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2003 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut

