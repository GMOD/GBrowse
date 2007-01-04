package Bio::Graphics::Browser::Render;

use strict;
use warnings;
use Bio::Graphics::Browser::I18n;
use Text::ParseWords 'shellwords';
use CGI '';
use Carp 'croak';

use constant VERSION => 2.0;
use constant DEBUG   => 0;

my %DB;      # cache opened database connections
my %PLUGINS; # cache initialized plugins

sub new {
  my $class = shift;
  my ($data_source,$session) = @_;
  my $self = bless {},ref $class || $class;
  $self->data_source($data_source);
  $self->session($session);
  $self->state($session->page_settings);
  $self->set_language();
  $self;
}

sub data_source {
  my $self = shift;
  my $d = $self->{data_source};
  $self->{data_source} = shift if @_;
  $d;
}

sub session {
  my $self = shift;
  my $d = $self->{session};
  $self->{session} = shift if @_;
  $d;
}

sub state {
  my $self = shift;
  my $d = $self->{state};
  $self->{state} = shift if @_;
  $d;
}

sub uploaded_sources {
  my $self = shift;
  my $d = $self->{uploaded_sources};
  $self->{uploaded_sources} = shift if @_;
  $d;
}

sub remote_sources {
  my $self = shift;
  my $d = $self->{remote_sources};
  $self->{remote_sources} = shift if @_;
  $d;
}

sub language {
  my $self = shift;
  my $d = $self->{language};
  $self->{language} = shift if @_;
  $d;
}

sub db {
  my $self = shift;
  my $d = $self->{db};
  $self->{db} = shift if @_;
  $d;
}

sub segments {
  my $self = shift;
  my $d = $self->{segments} ||= [];
  if (@_) {
    if (ref $_[0] && ref $_[0] eq 'ARRAY') {
      $self->{segments} = shift;
    } else {
      $self->{segments} = \@_;
    }
  }
  return @$d;
}


###################################################################################
#
# RUN CODE HERE
#
###################################################################################
sub run {
  my $self = shift;
  $self->update_state();
  $self->init_database();
  $self->init_plugins();
  $self->init_remote_sources();
  $self->render();
  $self->clean_up();
}

sub init_database {
  my $self = shift;
  my ($adaptor,@argv) = $self->db_settings;
  my $key             = join ':',$adaptor,@argv;
  return $DB{$key}    if exists $DB{$key};

  my $state = $self->state;

  $DB{$key} = eval {$adaptor->new(@argv)} or warn $@;
  $self->fatal_error("Could not open database: ",pre("$@")) unless $DB{$key};

  if (my $refclass = $self->setting('reference class')) {
    eval {$DB{$key}->default_class($refclass)};
  }

  $DB{$key}->strict_bounds_checking(1) if $DB{$key}->can('strict_bounds_checking');
  $DB{$key}->absolute(1)               if $DB{$key}->can('absolute');

  # I don't know what this is for, but it was there in gbrowse and looks
  # like an important hack.
  eval {$DB{$key}->biosql->version($state->{version})};

  $self->db($DB{$key});
}

sub init_plugins {
  my $self        = shift;
  my $source      = $self->data_source->name;
  my @plugin_path = shellwords($self->data_source->globals->plugin_path);

  my $plugins = $PLUGINS{$source} 
    ||= Bio::Graphics::Browser::PluginSet->new($self->data_source,$self->state,@plugin_path);
  $self->fatal_error("Could not initialize plugins") unless $plugins;
  $plugins->configure($self->db,$self->state,$self->session);
}

sub init_remote_sources {
  my $self = shift;
  my $uploaded_sources = Bio::Graphics::Browser::UploadSet->new($self->data_source,$self->state);
  my $remote_sources   = Bio::Graphics::Browser::RemoteSet->new($self->data_source,$self->state);
  $self->uploaded_sources($uploaded_sources);
  $self->remote_sources($remote_sources);
}

sub render {
  my $self = shift;
  croak 'Please call render() for a subclass of Bio::Graphics::Browser::Render';
}

sub clean_up {
  my $self = shift;
}

sub fatal_error {
  my $self = shift;
  my @msg  = @_;
  croak 'Please call fatal_error() for a subclass of Bio::Graphics::Browser::Render';
}


###################################################################################
#
# SETTINGS CODE HERE
#
###################################################################################

# the setting method either calls the DATA_SOURCE's global_setting or setting(), depending
# on the number of arguments used.
sub setting {
  my $self = shift;

  my $data_source = $self->data_source;

  if (@_ == 1) {
    return $data_source->global_setting(@_);
  }

  else {
    # otherwise we get the data_source-specific settings
    return $data_source->setting(@_);
  }
}

sub plugin_setting {
  my $self           = shift;
  my $caller_package = caller();
  my ($last_name)    = $caller_package =~ /(\w+)$/;
  my $option_name    = "${last_name}:plugin";
  $self->setting($option_name => @_);
}

sub karyotype_setting {
  my $self           = shift;
  my $caller_package = caller();
  $self->setting('karyotype' => @_);
}

sub db_settings {
  my $self = shift;

  my $adaptor = $self->setting('db_adaptor') or die "No db_adaptor specified";
  eval "require $adaptor; 1" or die $@;

  my $args    = $self->setting('db_args');
  my @argv = ref $args eq 'CODE'
        ? $args->()
	: shellwords($args||'');

  # for compatibility with older versions of the browser, we'll hard-code some arguments
  if (my $adaptor = $self->setting('adaptor')) {
    push @argv,(-adaptor => $adaptor);
  }

  if (my $dsn = $self->setting('database')) {
    push @argv,(-dsn => $dsn);
  }

  if (my $fasta = $self->setting('fasta_files')) {
    push @argv,(-fasta=>$fasta);
  }

  if (my $user = $self->setting('user')) {
    push @argv,(-user=>$user);
  }

  if (my $pass = $self->setting('pass')) {
    push @argv,(-pass=>$pass);
  }

  if (defined (my $a = $self->setting('aggregators'))) {
    my @aggregators = shellwords($a||'');
    push @argv,(-aggregator => \@aggregators);
  }

  ($adaptor,@argv);
}

##################################################################3
#
# STATE CODE HERE
#
##################################################################3

sub update_state {
  my $self = shift;
  my $state = $self->state;
  $self->default_state unless %$state;
  $self->update_segments();
  $self->update_tracks();
  $self->update_options();
}

sub default_state {
  my $self  = shift;
  my $state = $self->state;
  %$state = ();
  @$state{'name','ref','start','stop','flip','version'} = ('','','','','',100);
  $state->{width}        = $self->setting('default width');
  $state->{source}       = $self->data_source->name;
  $state->{region_size}  = $self->setting('region segment');
  $state->{v}            = VERSION;
  $state->{stp}          = 1;
  $state->{ins}          = 1;
  $state->{head}         = 1;
  $state->{ks}           = 'between';
  $state->{grid}         = 1;
  $state->{sk}           = $self->setting("default varying") ? "unsorted" : "sorted";
  $self->default_tracks();
}

sub default_tracks {
  my $self  = shift;
  my $state  = $self->state;
  my @labels = $self->data_source->labels;

  $state->{tracks}   = \@labels;
  warn "order = @labels" if DEBUG;
  foreach (@labels) {
    $state->{features}{$_} = {visible=>0,options=>0,limit=>0};
  }
  foreach ($CONFIG->default_labels) {
    $state->{features}{$_}{visible} = 1;
  }
}

sub update_segments {
  my $self = shift;
  
}

sub update_tracks {
  my $self = shift;
}

sub update_options {
  my $self = shift;
}

##################################################################3
#
# SHARED RENDERING CODE HERE
#
##################################################################3

# override make_link to allow for code references
sub make_link {
  my $self     = shift;
  my ($feature,$panel,$label,$track)  = @_;

  my $data_source = $self->data_source;
  my $ds_name     = $data_source->name;

  if ($feature->can('url')) {
    my $link = $feature->url;
    return $link if defined $link;
  }
  return $label->make_link($feature) if $label && $label->isa('Bio::Graphics::FeatureFile');

  $panel ||= 'Bio::Graphics::Panel';
  $label ||= $data_source->feature2label($feature);

  # most specific -- a configuration line
  my $link     = $data_source->code_setting($label,'link');

  # less specific - a smart feature
  $link        = $feature->make_link if $feature->can('make_link') && !defined $link;

  # general defaults
  $link        = $data_source->code_setting('TRACK DEFAULTS'=>'link') unless defined $link;
  $link        = $data_source->code_setting(general=>'link')          unless defined $link;

  return unless $link;

  if (ref($link) eq 'CODE') {
    my $val = eval {$link->($feature,$panel,$track)};
    $data_source->_callback_complain($label=>'link') if $@;
    return $val;
  }
  elsif (!$link || $link eq 'AUTO') {
    my $n     = $feature->display_name;
    my $c     = $feature->seq_id;
    my $name  = CGI::escape("$n");  # workaround CGI.pm bug
    my $class = eval {CGI::escape($feature->class)}||'';
    my $ref   = CGI::escape("$c");  # workaround again
    my $start = CGI::escape($feature->start);
    my $end   = CGI::escape($feature->end);
    my $src   = CGI::escape(eval{$feature->source} || '');
    my $url   = CGI->request_uri || '../..';
    $url      =~ s!/gbrowse.*!!;
    $url      .= "/gbrowse_details/$ds_name?name=$name;class=$class;ref=$ref;start=$start;end=$end";
    return $url;
  }
  return $data_source->link_pattern($link,$feature,$panel);
}

# make the title for an object on a clickable imagemap
sub make_title {
  my $self = shift;
  my ($feature,$panel,$label,$track) = @_;
  local $^W = 0;  # tired of uninitialized variable warnings
  my $data_source = $self->data_source;

  my ($title,$key) = ('','');

 TRY: {
    if ($label && $label->isa('Bio::Graphics::FeatureFile')) {
      $key = $label->name;
      $title = $label->make_title($feature) or last TRY;
      return $title;
    }

    else {
      $label     ||= $data_source->feature2label($feature) or last TRY;
      $key       ||= $data_source->setting($label,'key') || $label;
      $key         =~ s/s$//;
      $key         = $feature->segment->dsn if $feature->isa('Bio::Das::Feature');  # for DAS sources

      my $link     = $data_source->code_setting($label,'title')
	|| $data_source->code_setting('TRACK DEFAULTS'=>'title')
	  || $data_source->code_setting(general=>'title');
      if (defined $link && ref($link) eq 'CODE') {
	$title       = eval {$link->($feature,$panel,$track)};
	$self->_callback_complain($label=>'title') if $@;
	return $title if defined $title;
      }
      return $data_source->link_pattern($link,$feature) if $link && $link ne 'AUTO';
    }
  }

  # otherwise, try it ourselves
  $title = eval {
    if ($feature->can('target') && (my $target = $feature->target)) {
      join (' ',
	    "$key:",
	    $feature->seq_id.':'.
	    $feature->start."..".$feature->end,
	    $feature->target->seq_id.':'.
	    $feature->target->start."..".$feature->target->end);
    } else {
      my ($start,$end) = ($feature->start,$feature->end);
      ($start,$end)    = ($end,$start) if $feature->strand < 0;
      join(' ',
	   "$key:",
	   $feature->can('display_name') ? $feature->display_name : $feature->info,
	   ($feature->can('seq_id')      ? $feature->seq_id : $feature->location->seq_id)
	   .":".
	   (defined $start ? $start : '?')."..".(defined $end ? $end : '?')
	  );
    }
  };
  warn $@ if $@;

  return $title;
}

sub make_link_target {
  my $self = shift;
  my ($feature,$panel,$label,$track) = @_;
  my $data_source = $self->data_source;

  if ($feature->isa('Bio::Das::Feature')) { # new window
    my $dsn = $feature->segment->dsn;
    $dsn =~ s/^.+\///;
    return $dsn;
  }

  $label    ||= $data_source->feature2label($feature) or return;
  my $link_target = $data_source->code_setting($label,'link_target')
    || $data_source->code_setting('LINK DEFAULTS' => 'link_target')
    || $data_source->code_setting(general => 'link_target');
  $link_target = eval {$link_target->($feature,$panel,$track)} if ref($link_target) eq 'CODE';
  $data_source->_callback_complain($label=>'link_target') if $@;
  return $link_target;
}

sub default_style {
  my $self = shift;
  return $self->SUPER::style('TRACK DEFAULTS');
}

##### language stuff
sub set_language {
  my $self = shift;

  my $data_source = $self->data_source;

  my $lang        = Bio::Graphics::Browser::I18n->new($data_source->globals->language_path);
  my $default_language = $data_source->setting('language') || 'POSIX';

  my $accept           = CGI::http('Accept-language') || '';
  my @languages        = $accept =~ /([a-z]{2}-?[a-z]*)/ig;
  push @languages,$default_language if $default_language;

  return unless @languages;
  $lang->language(@languages);
  $self->language($lang);
}

# return language-specific options
sub i18n_style {
  my $self      = shift;
  my ($label,$lang,$length) = @_;

  my $data_source = $self->data_source;

  return $data_source->style($label,$length) unless $lang;

  my $charset   = $lang->tr('CHARSET');

  # GD can't handle non-ASCII/LATIN scripts transparently
  return $data_source->style($label,$length) 
    if $charset && $charset !~ /^(us-ascii|iso-8859)/i;

  my @languages = $lang->language;

  push @languages,'';
  # ('fr_CA','fr','en_BR','en','')

  my $idx = 1;
  my %priority = map {$_=>$idx++} @languages;
  # ('fr-ca'=>1, 'fr'=>2, 'en-br'=>3, 'en'=>4, ''=>5)

  my %options  = $self->style($label,$length);
  my %lang_options = map { $_->[1] => $options{$_->[0]} }
    sort { $b->[2]<=>$a->[2] }
      map { my ($option,undef,$lang) = /^(-[^:]+)(:(\w+))?$/; [$_ => $option, $priority{$lang||''}||99] }
	keys %options;
  %lang_options;
}

sub tra {
  my $self = shift;
  my $lang = $self->language or return @_;
  $lang->tr(@_);
}

1;

