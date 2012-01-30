package Bio::Graphics::Browser2::PluginSet;
# API for using plugins

#  $Id$

use strict;
use Bio::Graphics::Browser2;
use Bio::Graphics::Browser2::Util 'shellwords';
use CGI 'param';
use constant DEBUG=>0;

sub new {
  my $package       = shift;
  my $config        = shift;
  my @search_path    = @_;
  my %plugin_list    = ();

  warn "initializing plugins with $config..." if DEBUG;
  my @plugins = shellwords($config->plugins);
  # only one authorization plugin allowed, from globals
  if (my $auth = $config->auth_plugin) {
      unshift @plugins,$auth; # first one
  }
  warn "PLUGINS = @plugins" if DEBUG;

 PLUGIN:
  for my $plugin (@plugins) {
    my $class = "Bio\:\:Graphics\:\:Browser2\:\:Plugin\:\:$plugin";
    for my $search_path (@search_path) {
      my $plugin_with_path = "$search_path/$plugin.pm";
      if (eval {require $plugin_with_path}) {
	warn "plugin $plugin loaded successfully" if DEBUG;
	my $obj = eval{$class->new};
	unless ($obj) {
	  warn "$plugin: $@";
	  next PLUGIN;
	}
	warn "plugin name = ",$obj->name," base = $plugin" if DEBUG;
	$plugin_list{$plugin} = $obj;
	next PLUGIN;
      } else {
	warn $@ if $@ and $@ !~ /^Can\'t locate/;
      }
    }
    warn $@ if !$plugin_list{$plugin} && $@ =~ /^Can\'t locate/;
  }
  my $self = bless {
		config        => $config,
		plugins       => \%plugin_list
	       },ref $package || $package;
  return $self;
}

sub config        { shift->{config}         }
sub plugins       {
  my $self = shift;
  return wantarray ? values %{$self->{plugins}} : $self->{plugins};
}

sub plugin        {
  my $self = shift;
  my $plugin_base = shift;
  $self->plugins->{$plugin_base};
}

sub language {
  my $self = shift;
  my $d = $self->{language};
  $self->{language} = shift if @_;
  $d;
}

sub auth_plugin {
    my $self = shift;
    my @a    = grep {$_->type eq 'authenticator'} values %{$self->{plugins}};
    return unless @a;
    return $a[0];
}

sub configure {
  my $self     = shift;
  my $render   = shift;

  my $database      = $render->db;
  my $page_settings = $render->state;
  my $language      = $render->language;
  my $session       = $render->session;
  my $search        = $render->get_search_object;

  my $conf     = $self->config;
  my $plugins  = $self->plugins;
  my $conf_dir = $conf->globals->config_base;
  $self->language($language);

  for my $name (keys %$plugins) {

    eval {
      my $p = $plugins->{$name};
      $p->renderer($render);
      $p->database($database);
      $p->browser_config($conf);
      $p->config_path($conf_dir);
      $p->language($language);
      $p->page_settings($page_settings);
      $p->db_search($search);
      $p->init();  # other initialization

      # retrieve persistent configuration
      my $config = $session->plugin_settings($p->name);
      unless (%$config) {
	my $defaults = $p->config_defaults;
	%$config     = %{$defaults} if $defaults;
      }

      # and tell the plugin about it
      $p->configuration($config);

      # if there are any CGI parameters from the
      # plugin's configuration screen, set it here
      if (my @params = grep {/^$name\./} param()) {
	  $p->reconfigure unless param('plugin_action') eq $language->tr('Cancel');

	  # turn the plugin on
	  my $setting_name = 'plugin:'.$p->name;
	  $p->page_settings->{features}{$setting_name}{visible} = 1;
      }

      if ($p->type eq 'authenticator') {
	  my $source = $self->config;
	  $source->set_authenticator($p);
	  $source->set_username($render->session->username);
      }
    };

    warn "$name: $@" if $@;
  }


  $self->set_filters();  # allow filter plugins to adjust the data source
}

sub destroy {
    my $self = shift;
    my $plugins  = $self->plugins;
    for my $name (keys %$plugins) {
	eval {
	    my $p = $plugins->{$name};
	    $p->renderer(undef);
	};
    }
}

sub set_filters {
    my $self   = shift;
    my $source = $self->config;

    my @labels = grep {!/^_/} $source->labels;
    for my $p ($self->plugins) {
	next unless $p->type eq 'filter';
	for my $l (@labels) {
	    $self->{'.ok'}{$l}    ||= $source->setting($l,'key');    # remember this!
	    $self->{'.of'}{$l}    ||= $source->setting($l,'filter'); # remember this!
	    
	    if (my ($filter,$new_key) = $p->filter($l,$self->{'.ok'}{$l})) {
		$source->set($l, filter => $filter);
		$source->set($l, key    => $new_key);
	    }
	    else {
		$source->set($l, key    => $self->{'.ok'}{$l}) if exists $self->{'.ok'}{$l};
		$source->set($l, filter => $self->{'.of'}{$l}) if exists $self->{'.of'}{$l};
	    }
	}
    }
}

sub annotate {
  my $self = shift;
  my $segment                = shift;
  my $feature_files          = shift || {};
  my $fast_mapper            = shift;  # fast mapper filters out features that are outside cur segment
  my $slow_mapper            = shift;  # slow mapper doesn't
  my $max_segment            = shift;  # ignored
  my $whole_segment          = shift;
  my $region_segment         = shift;

  my @plugins = $self->plugins;

  for my $p (@plugins) {
    next unless $p->type eq 'annotator';
    my $name = "plugin:".$p->id;
    next unless $p->page_settings && $p->page_settings->{features}{$name}{visible};
    warn "Plugin $name is visible, so running it on segment $segment" if DEBUG;
    if ($segment->length > $max_segment) {
	$feature_files->{$name} = Bio::Graphics::FeatureFile->new();  # empty
    } else {
	my $features = $p->annotate($segment,$fast_mapper) or next;
	$features->name($name);
	$feature_files->{$name} = $features;
    }
  }
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
  my $lang    = $self->language;

  my %verbs = (dumper       => $lang->tr('Dump'),
	       finder       => $lang->tr('Find'),
	       highlighter  => $lang->tr('Highlight'),
	       annotator    => $lang->tr('Annotate'),
	       filter       => $lang->tr('Filter'),
      );
  my %labels = ();

  # Adjust plugin menu labels
  for ( keys %{$plugins} ) {

    # plugin-defined verb
    if ( $plugins->{$_}->verb ) {
      $labels{$_} = $lang->tr($plugins->{$_}->verb) ||
        ucfirst $plugins->{$_}->verb;
    }
    # default verb
    else {
      $labels{$_} = $verbs{$plugins->{$_}->type} ||
        ucfirst $plugins->{$_}->type;
    }
    my $name = $plugins->{$_}->name;
    $labels{$_} .= " $name";
    $labels{$_} =~ s/^\s+//;
  }
  return \%labels;
}

1;

__END__

=head1 NAME

Bio::Graphics::Browser2::PluginSet -- A set of plugins

=head1 SYNOPSIS

None.  Used internally by gbrowse & gbrowse_img.

=head1 METHODS

=over 4

=item $plugin_set = Bio::Graphics::Browser2::PluginSet->new($config,$page_settings,@search_path)

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

L<Bio::Graphics::Browser2>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2005 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut

