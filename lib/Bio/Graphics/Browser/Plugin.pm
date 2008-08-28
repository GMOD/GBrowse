package Bio::Graphics::Browser::Plugin;
# $Id: Plugin.pm,v 1.12.4.6.2.2.2.5 2008-08-28 14:39:06 lstein Exp $

=head1 NAME

Bio::Graphics::Browser::Plugin -- Base class for gbrowse plugins.

=head1 SYNOPSIS

 package Bio::Graphics::Browser::Plugin::MyPlugin;
 use Bio::Graphics::Browser::Plugin;
 use CGI ':standard';
 @ISA = 'Bio::Graphics::Browser::Plugin';

 # called by gbrowse to return name of plugin for popup menu
 sub name        { 'Example Plugin' }

 # called by gbrowse to return the descriptive verb for popup menu
 sub verb        { 'Demonstrate' }

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
   $current->{foo} = $self->config_param('foo');
   $current->{bar} = $self->config_param('bar');
 }

 # called by gbrowse to create a <form> fragment for changing settings
 sub configure_form {
   my $self    = shift;
   my $current = $self->configuration;
   my $form = textfield(-name  => $self->config_name('foo'),
                        -value => $current->{foo})
              .
              textfield(-name  => $self->config_name('bar'),
                        -value => $current->{bar});
   return $form;
 }

 # called by gbrowse to annotate the DNA, returning features
 sub annotate {
    my $self     = shift;
    my ($segment,$coordinate_mapper)  = @_;
    my $config   = $self->configuration;
    my $feature_list = $self->new_feature_list;
    $feature_list->add_type('my_type' => {glyph => 'generic',
					  key   => 'my type',
					  bgcolor => 'green',
					  link    => 'http://www.google.com/search?q=$name'
					 }
			   );
    # do something with the sequence segment
    my @features = do_something();
    $feature_list->add_feature($_ => 'my_type') foreach @features;
    return $feature_list;
 }


=head1 DESCRIPTION

This is the base class for Generic Genome Browser plugins.  Plugins
are perl .pm files that are stored in the gbrowse.conf/plugins
directory.  Plugins are activated in the gbrowse.conf/ configuration
file by including them on the list indicated by the "plugins" setting:

 plugins = BatchDumper FastaDumper GFFDumper
	   OligoFinder RestrictionAnnotator

Site-specific plugins may be placed in one or more site-specific
directories and added to the plugin search path using the plugin_path
setting:

  plugin_path = /usr/local/gbrowse_plugins

GBrowse currently recognizes three distinct types of plugins:

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

These plugins receive the genomic segment object and either 1) return 
a list of features which are overlayed on top of the detailed view 
(Example: restriction site annotator) or 2) update the database with 
new or modified features and return nothing (Example: basic editor)

=back

All plug-ins inherit from Bio::Graphics::Browser::Plugin, which
defines reasonable (but uninteresting) defaults for each of the
methods.  Specific behavior is then implemented by selectively
overriding certain methods.

The best way to understand how this works is to look at the source
code for some working plugins.  Examples provided with the gbrowse
distribution include:

=over 4

=item GFFDumper.pm

A simple dumper which produces GFF format output representing the
features of the currently-selected segment.

=item FastaDumper.pm

A more complex dumper that illustrates how to create and manage
persistent user-modifiable settings.

=item SequenceDumper.pm

Another dumper that shows how plugins interact with the Bio::SeqIO
system.

=item OligoFinder.pm

A finder that searches for short oligos in the entire database.  (Only
works with Bio::DB::GFF databases.)

=item RestrictionAnnotator.pm

An annotator that finds restriction sites in the currently selected
region of the genome.  It creates a new track for each type of
restriction site selected.

=item RandomGene.pm

An example annotator that generates random gene-like structures in the
currently displayed region of the genome.  It's intended as a template
for front-ends to gene prediction programs.

=back

=head1 METHODS

The remainder of this document describes the methods available to the
programmer.

=head2 INITIALIZATION

The initialization methods establish the human-readable name,
description, and basic operating parameters of the plugin.  They
should be overridden in each plugin you write.

=over 4

=item $name = $self->name()

Return a short human-readable name for the plugin.  This will be
displayed to the user in a menu using one of the following forms:

    Dump <name>
    Find <name>
    Annotate <name>
    plugin_defined_verb <name>

=item $description = $self->description()

This method returns a longer description for the plugin.  The text may
contain HTML tags, and should describe what the plugin does and who
wrote it.  This text is displayed when the user presses the "About..."
button.

=item $verb = $self->verb()

This method returns a verb to be used in the plugin popup menu
in cases where the main three don't fit.  This method should
be set return whitespace or an empty string (not undefined) 
if you do not want a descriptive verb for the menu

=item $suppress_title = $self->suppress_title()

The purpose of this methods is to suppress the 'Configure...'
or 'Find...' title that is printed at the top of the page when the 
plugin is loaded.  It will return false unless overriden by a plugin where
this behaviour is desired.

=item $type = $self->type()

This tells gbrowse what the plugin's type is.  It must return one of
the scripts "dumper," "finder,", "annotator" as described in the
introduction to this documentation.  If the method is not overridden,
type() will return "dumper."

=item $self->init()

This method is called before any methods are invoked and allows the
plugin to do any run-time initialization it needs.  The default is to
do nothing.  Ordinarily this method does not need to be implemented.

=back

=head2 ACCESS TO THE ENVIRONMENT

The following methods give the plugin access to the environment,
including the gbrowse page settings, the sequence features database,
and the plugin's own configuration settings.

These methods do not generally need to be overridden.

=over 4

=item $config = $self->configuration()

Call this method to retrieve the persistent configuration for this
plugin.  The configuration is a hashref containing the default
configuration settings established by config_defaults(), possibly
modified by the user.  Due to cookie limitations, the values of the
hashref must be scalars or array references.

See CONFIGURATION METHODS for instructions on how to create and
maintain the plugin's persistent configuration information.

=item $database = $self->database

This method returns a copy of the sequence database.  Depending on the
data source chosen by the gbrowse administrator, this may be a
Bio::DB::GFF database, a Bio::DB::Das::Chado database, a Bio::Das
database, a Bio::DB::Das::BioSQL database, or any of the other
Das-like databases that gbrowse supports.

=item @track_names = $self->selected_tracks

This method returns the list of track names that the user currently
has turned on.  Track names are the internal names identified in
gbrowse configuration file stanzas, for example "ORFs" in the
01.yeast.conf example file.

=item @feature_types = $self->selected_features

This method returns the list of feature types that the user currently
has turned on.  Feature types are the feature identifiers indicated by
the "feature" setting in each track in the gbrowse configuration file,
for example "ORF:sgd" in the 01.yeast.conf [ORFs] track.

=item $gbrowse_settings = $self->page_settings

This method returns a big hash containing the current gbrowse
persistent user settings.  These settings are documented in the
gbrowse executable source code.  You will not ordinarily need to
access the contents of this hash, and you should *not* change its
values.

=item $browser_config = $self->browser_config

This method returns a copy of the Bio::Graphics::Browser object that
drives gbrowse.  This object allows you to interrogate (and change!)
the values set in the current gbrowse configuration file.

The recommended use for this object is to recover plugin-specific
settings from the gbrowse configuration file.  These can be defined by
the gbrowse administrator by placing the following type of stanza into
the gbrowse config file:

  [GOSearch:plugin]
  traverse_isa = 1
  use_server   = http://amigo.geneontology.org

"GOSearch" is the package name of the plugin, and the ":plugin" part
of the stanza name tells gbrowse that this is a plugin-private
configuration section.

You can now access these settings from within the plugin by using the
following idiom:

   my $browser_config = $self->browser_config; 
   my $traverse_isa = $browser_config->plugin_setting('traverse_isa');
   my $server       = $browser_config->plugin_setting('use_server');

This facility is intended to be used for any settings that should not
be changed by the end user.  Persistent user preferences should be
stored in the hash returned by configuration().

=item $language = $self->language

This method returns the current I18n language file. You can use this
to make translations with the tr() method:

  print $self->language->tr('WELCOME');


=item $segments = $self->segments 

This method returns the current segments in use by gbrowse.  The active
segments are set from within gbrowse

 $plugin->segments(\@segments);

The active segments can then be retrieved from within the plugin.  This is 
useful in cases where segment-specific information is required by plugin methods
that are not passed a segment object.


=item $config_path   = $self->config_path

This method returns the path to the directory in which gbrowse stores
its configuration files.  This is very useful for storing
plugin-specific configuration files.  See the sourcecode of
RestrictionAnnotator for an exmaple of this.

=item $feature_file  = $self->new_feature_file

This method creates a new Bio::Graphics::FeatureFile for use by
annotators.  The annotate() method must invoke this method, configure
the resulting feature file, and then add one or more
Bio::Graphics::Feature objects to it.

This method is equivalent to calling
Bio::Graphics::FeatureFile->new(-smart_features=>1), where the
-smart_features argument allows features to be turned into imagemap
links.

=back

=head2 METHODS TO BE IMPLEMENTED IN DUMPERS

All plugins that act as feature dumpers should override one or more of
the methods described in this section.

=over 4

=item $self->dump($segment)

Given a Bio::Das::SegmentI object, produce some output from its
sequence and/or features.  This can be used to dump something as
simple as a FASTA file, or as complex as a motif analysis performed on
the sequence.

As described in L<Bio::Das::SegmentI>, the segment object represents
the region of the genome currently on display in the gbrowse "detail"
panel.  You may call its seq() method to return the sequence as a
string, or its features() method to return a list of all features that
have been annotated onto this segment of the genome.

At the time that dump() is called, gbrowse will already have set up
the HTTP header and performed other initialization.  The dump() method
merely needs to begin printing output using the appropriate MIME
type.  By default, the MIME type is text/plain, but this can be
changed with the mime_type() method described next.  

The following trivial example shows a dump() method that prints the
name and length of the segment:

  sub dump {
     my $self = shift;
     my $segment = shift;
     print "name   = ",$segment->seq_id,"\n";
     print "length = ",$segment->length,"\n";
  }

=item $type = $self->mime_type

Return the MIME type of the information produced by the plugin.  By
default, this method returns "text/plain".  Override it to return
another MIME type, such as "text/xml".

=back

=head2 METHODS TO BE IMPLEMENTED IN FINDERS

All finder plugins will need to override one or more of the methods
described in this section.

=over 4

=item $features = $self->find($segment);

The find() method will be passed a Bio::Das::SegmentI segment object,
as described earlier for the dump() method.  Your code should search
the segment for features of interest, and return a two element
list. The first element should be an arrayref of Bio::SeqFeatureI
objects (see L<Bio::SeqFeatureI>), or an empty list if nothing was
found. These synthetic feature objects should indicate the position,
name and type of the features found. The second element of the
returned list should be a (possibly shortened) version of the search
string for display in informational messages.

Depending on the type of find you are performing, you might search the
preexisting features on the segment for matches, or create your own
features from scratch in the way that the annotator plugins do.  You
may choose to ignore the passed segment and perform the search on the
entire database, which you can obtain using the database() method
call.

To create features from scratch I suggest you use either
Bio::Graphics::Feature, or Bio::SeqFeature::Generic to generate the
features.  See their respective manual pages for details, and the
OligoFinder.pm plugin for an example of how to do this.

If the plugin requires user input before it can perform its task,
find() should return undef.  Gbrowse will invoke configure_form()
followed by reconfigure() in order to prompt the user for input.  If
nothing is found, the plugin should return an empty list.  The
following is an example of how to prompt the user for input -- in this
case, a gene ontology term:

  sub find {
     my $self = shift;
     my $segment  = shift;  # we ignore this!
     my $config   = $self->configuration;
     my $query    = $config->{query} or return undef;  # PROMPT FOR INPUT
     my $database = $self->database;
     my @features = $database->features(-attributes=>{GO_Term => $query});
     return (\@features,$query); 
  }

  sub configure_form {
     my $self = shift;
     return "Enter a GO Term: "
            . textfield(-name=>$self->config_name('query'));
  }

  sub reconfigure {
     my $self = shift;
     my $config = $self->configuration;
     $config->{query} = $self->config_param('query');
  }

See the sections below for more description of the configure_form()
and reconfigure() methods.  

NOTE: If you need to use auxiliary files like BLAST files, you can
store the location of those files in the gbrowse .conf file under the
stanza [YourPlugin:plugin]:

   [YourPlugin:plugin]
   blast_path = /usr/local/blast/databases

   sub find {
      my $self = shift;
      my $segment = shift;  # ignored
      my $blast_path = $self->browser_config->plugin_setting('blast_path');
      # etc etc etc  
   }

=back

=head2 METHODS TO BE IMPLEMENTED IN ANNOTATORS

All annotator plugins will need to override the method described in
this section.

=over 4

=item $feature_file = $plugin->annotate($segment[,$coordinate_mapper])

The annotate() method will be invoked with a Bio::Das::SegmentI
segment representing the region of the genome currently on view in the
gbrowse detail panel.  The method should first call its own
new_feature_list() to create a Bio::Graphics::FeatureFile feature set
object, and define one or more feature types to added to the feature
set.  The method should then create one or more Bio::Graphics::Feature
objects and add them to the feature set using add_feature.

The reason that annotate() returns a Bio::Graphics::FeatureFile rather
than an array of features the way that find() does is because
Bio::Graphics::FeatureFile also allows you to set up how the features
will be rendered; you can define tracks, assign different feature
types to different tracks, and assign each feature type a glyph,
color, and other options.

The annotate() function will also be passed a coordinate_mapper
variable.  This is a code ref to a function that will transform
coordinates from relative to absolute coordinates.  The function takes
a reference sequence name and a list of [$start,$end] coordinate
pairs, and returns a similar function result, except that the sequence
name and coordinates are all in absolute coordinate space.  Currently
there are no plugins that make use of this facility.

See L<Bio::Graphics::FeatureFile> for details, and the
RestrictionAnnotator.pm plugin for an example.

=back

=head2 PERSISTENT CONFIGURATION METHODS

The following methods can be called to retrieve data about the
environment in which the plugin is running.  These methods are also
used by gbrowse to change the plugin state.

=over 4

=item $config = $self->config_defaults()

This method will be called once at plugin startup time to give the
plugin a chance to set up its default configuration state.  If you
implement this method you should return the configuration as a hash
reference in which the values of the hash are either scalar values or
array references.  The contents of this hash will be placed in a
CGI::Session.

You will wish to implement this method if the plugin has
user-modifiable settings.

NOTE ON FILEHANDLES: You are not allowed to permanently store a
filehandle in the persistent configuration data structure because the
session-handling code will try to serialize and store the filehandle,
which is not allowed by the default serializer. If you must store a
filehandle in the configuration data structure, be sure to delete it
within the annotate(), find() or dump() methods once you are finished
using it.

=item $self->configure_form()

This method will be called when the user presses the "Configure
plugin" button.  You should return the HTML for a fill-out form that
allows the user to change the current settings.  The HTML should
contain the contents of an HTML <form> section, but B<not> the actual
<form> and </form> tags.  These tags, along with the Submit and Cancel
buttons, will be added automatically.  Typically you will build up the
HTML to return using a series of .= append operations.

It is highly recommended that you use the CGI module to generate the
fill-out form.  In order to avoid clashing with other parts of
gbrowse, plugin fill-out forms must respect a namespacing convention
in which the name of each form field is preceded by the plugin package
name and a dot.  The package name is the last component of the
plugin's package; for example "GoSearch" is the package name for
Bio::Graphics::Browser::Plugin::GoSearch. To represent the "query"
field of the plugin named "GOSearch", the text field must be named
"GOSearch.query".

To make this easier to do right, the Plugin module provides a method
named config_name() which will add the prefix for you.  Here is how
to use it with the "query" example:

   $html .= textfield(-name  => $self->config_name('query'));

=item $self->reconfigure()

If you implement a configure_form() method, you must also implement a
reconfigure() method.  This method is called after the user submits
the form and should be used to integrate the form values with the
current configuration.

Remember that the form fields are namespaced.  You may recover them
using the CGI param() method by preceding them with the proper prefix.
To make this easier to manage, this module provides a config_param()
method that manages the namespaces transparently.

Here is a working example:

  sub reconfigure {
      my $self = shift;
      my $current_configuration = $self->configuration;
      $current_configuration->{query} = $self->config_param('query');
  }

All this does is to retrieve the current configuration by calling the
configuration() method.  The value of the "query" key is then replaced
by a fill-out form parameter named "query", using config_param()
instead of the more familiar CGI module's param() function.

=back

=cut


use strict;
use Bio::Graphics::Browser;
use Data::Dumper;
use Digest::MD5 'md5_hex';
use CGI qw(url header p);

$Data::Dumper::Sortkeys = 1;

use vars '$VERSION','@ISA','@EXPORT';
$VERSION = '0.20';

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

# return nothing unless the plugin overides this method 
sub verb {
  my $self = shift;
  return '';
}

# return nothing unless the plugin overrides this method
sub suppress_title {
  my $self = shift;
  return '';
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

# get/store language
sub language {
  my $self = shift;
  my $d = $self->{g_language};
  $self->{g_language} = shift if @_;
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

# get/store the current segments
sub segments {
  my $self = shift;
  my $d = $self->{segments};
  $self->{segments} = shift if @_;
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
  my $coordinate_mapper = shift;
  # do nothing
  return;
}

sub pkg {
  my $self  = shift;
  my $class = ref $self or return;
  $class =~ /(\w+)$/    or return;
  return $1;
}

sub config_param {
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
  CGI::param($self->config_name(shift()));
}

sub config_name {
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

# called by annotators when they need to create a new list of features
sub new_feature_list {
  my $self     = shift;
  return Bio::Graphics::FeatureFile->new(-smart_features=>1,
					 -safe => 1);
}

# install the plugin but do not show it in the "Reports & Analysis" menu
# off by default
sub hide {}

sub config_hash {
  return md5_hex( Dumper( shift->configuration ) );
}

1;

__END__


=head1 SEE ALSO

L<Bio::Graphics::Browser>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2003 Cold Spring Harbor Laboratory

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.


=cut

