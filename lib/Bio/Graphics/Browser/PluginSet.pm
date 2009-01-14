package Bio::Graphics::Browser::PluginSet;
# API for using plugins

#  $Id: PluginSet.pm,v 1.1.2.7.2.2.2.4 2009-01-14 16:16:28 lstein Exp $

use strict;
use Digest::MD5;
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Util 'shellwords';
use CGI 'param';
use constant DEBUG=>0;

sub new {
  my $package = shift;
  my $config        = shift;
  my $page_settings = shift;
  my @search_path    = @_;
  my %plugin_list = ();

  warn "initializing plugins..." if DEBUG;
  my @plugins = shellwords($config->setting('plugins')||''); # || DEFAULT_PLUGINS);

 PLUGIN:
  for my $plugin (@plugins) {
    my $class = "Bio\:\:Graphics\:\:Browser\:\:Plugin\:\:$plugin";
    for my $search_path (@search_path) {
      my $plugin_with_path = "$search_path/$plugin.pm";
      if (eval {require $plugin_with_path}) {
	warn "plugin $plugin loaded successfully" if DEBUG;
	my $obj = $class->new;
	warn "plugin name = ",$obj->name," base = $plugin" if DEBUG;
	$plugin_list{$plugin} = $obj;
	next PLUGIN;
      } else {
	warn $@ if $@ and $@ !~ /^Can\'t locate/;
      }
    }
    warn $@ if !$plugin_list{$plugin} && $@ =~ /^Can\'t locate/;
  }

  return bless {
		config        => $config,
		plugins       => \%plugin_list
	       },ref $package || $package;
}

sub config        { shift->{config}         }
sub plugins       {
  my $self = shift;
  return wantarray ? values %{$self->{plugins}} : $self->{plugins};
}
sub plugin        {
  my $self = shift;
  my $plugin_name = shift;
  $self->plugins->{$plugin_name};
}

sub configure {
  my $self     = shift;
  my ($database,$page_settings,$session) = @_;
  my $conf     = $self->config;
  my $plugins  = $self->plugins;
  my $conf_dir = $conf->dir;

  for my $name (keys %$plugins) {

    my $p = $plugins->{$name};
    $p->database($database);
    $p->browser_config($conf);
    $p->config_path($conf_dir);
    $p->page_settings($page_settings);
    $p->init();  # other initialization

    # retrieve persistent configuration
    my $config = $session->plugin_settings($p->name);
    unless (%$config) {
      my $defaults = $p->config_defaults;
      %$config     = %{$defaults} if $defaults;
    }
    # and tell the plugin about it
    $p->configuration($config);
    $p->filter if ($p->type eq 'filter');

    # if there are any CGI parameters from the
    # plugin's configuration screen, set it here
    my @params = grep {/^$name\./} param() or next;
    $p->reconfigure unless param('plugin_action') eq $conf->tr('Cancel');
    $p->filter if ($p->type eq 'filter');

    # turn the plugin on
    my $setting_name = 'plugin:'.$p->name;
    $p->page_settings->{features}{$setting_name}{visible} = 1;

  }
}

sub annotate {
  my $self = shift;
  my $segment       = shift;
  my $feature_files = shift || {};
  my $coordinate_mapper = shift;

  my @plugins = $self->plugins;

  for my $p (@plugins) {
    next unless $p->type eq 'annotator';
    my $name = "plugin:".$p->name;
    next unless $p->page_settings && $p->page_settings->{features}{$name}{visible};
    warn "Plugin $name is visible, so running it on segment $segment" if DEBUG;
    my $features = $p->annotate($segment,$coordinate_mapper) or next;
    $features->name($name);
    $features->mtime($self->config_hash($p));
    $feature_files->{$name} = $features;
  }
}

# generate a unique md5hash for the configuration of a plugin
sub config_hash {
  my $self   = shift;
  my $plugin = shift;
  my $config = $plugin->configuration;
  my $hash   = Digest::MD5->new;
  for my $key (sort keys %$config) {
    my @values = ref $config->{$key} ? @{$config->{$key}} : $config->{$key};
    $hash->add($key,@values);
  }

  return $hash->hexdigest;
}

sub set_segments {
  my $self = shift;
  my $segments = shift;

  my $plugins = $self->plugins;
  for my $k ( values %$plugins ) {
    $k->segments($segments);
  }
}

sub _retrieve_plugin_config {
  my $plugin = shift;
  my $name   = $plugin->name;
  my %settings = cookie("${name}_config");
  return $plugin->config_defaults unless %settings;
  foreach (keys %settings) {
    # need better serialization than this...
    if ($settings{$_} =~ /$;/) {
      my @settings = split $;,$settings{$_};
      pop @settings unless defined $settings[-1];
      $settings{$_} = \@settings;
    }
  }
  \%settings;
}

sub menu_labels {
  my $self = shift;
  my $plugins = $self->plugins;
  my $config  = $self->config;

  my %verbs = (dumper       => $config->tr('Dump'),
	       finder       => $config->tr('Find'),
	       highlighter  => $config->tr('Highlight'),
	       annotator    => $config->tr('Annotate'));
  my %labels = ();

  # Adjust plugin menu labels
  for ( keys %{$plugins} ) {

    # plugin-defined verb
    if ( $plugins->{$_}->verb ) {
      $labels{$_} = $config->tr($plugins->{$_}->verb) ||
        ucfirst $plugins->{$_}->verb;
    }
    # default verb
    else {
      $labels{$_} = $verbs{$plugins->{$_}->type} ||
        ucfirst $plugins->{$_}->type;
    }
    my $name = $plugins->{$_}->type eq 'filter' 
	            ? $config->setting($plugins->{$_}->name => 'key') || $plugins->{$_}->name
                    : $plugins->{$_}->name;
    $labels{$_} .= " $name";
    $labels{$_} =~ s/^\s+//;
  }
  return \%labels;
}

1;

__END__

=head1 NAME

Bio::Graphics::Browser::PluginSet -- A set of plugins

=head1 SYNOPSIS

None.  Used internally by gbrowse & gbrowse_img.

=head1 METHODS

=over 4

=item $plugin_set = Bio::Graphics::Browser::PluginSet->new($config,$page_settings,@search_path)

Initialize plugins according to the configuration, page settings and
the plugin search path.  Returns an object.

=item $plugin_set->configure($database)

Configure the plugins given the database.

=item $plugin_set->annotate($segment,$feature_files,$rel2abs)

Run plugin annotations on the $segment, adding the resulting feature
files to the hash ref in $feature_files ({track_name=>$feature_list}).
The $rel2abs argument holds a coordinate mapper callback, but is
currently unused.

=back

=head1 SEE ALSO

L<Bio::Graphics::Browser>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2005 Cold Spring Harbor Laboratory

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

