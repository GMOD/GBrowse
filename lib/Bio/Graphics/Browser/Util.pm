package Bio::Graphics::Browser::Util;

# a package of useful internal routines for GBrowse

=head1 NAME

Bio::Graphics::Browser::Util -- Exported utilities

=head1 SYNOPSIS

  use Bio::Graphics::Browser::Util;

  # imports the following routines:
  $conf_dir = conf_dir($default);
  $config   = open_config($dir);
  $db       = open_database($config,$dir);
  $string   = html_frag('page_part');
  print_header(@args);
  error(@msgs);
  fatal_error(@msgs);

=head1 DESCRIPTION

This package provides functions that support the Generic Genome
Browser.  It is not currently designed for external use.

=head1 FUNCTIONS

=over 4

=item $conf_dir = conf_dir($default_dir)

Return the configuration file directory given a default.

=item $config = open_config($dir)

Create the Bio::Graphics::Browser configuration object.

=item $db = open_database($config);

Open the underlying DAS-compatible database (e.g. Chado).

=item ($ref,$type,$name,@segments) = parse_feature_str($string);

Parse a CGI "added feature" string in the format "reference type name
start1..end1,start2..end2,..." into a list containing the reference,
feature type, name and a list of segments in [start,end] format.

The type defaults to 'Your features' and the name defaults to "Feature
XX" where XX is the number of features parsed so far.

=item error(@msg)

Print an error message.

=item fatal_error(@msg);

Quit with a fatal error in a browser-friendly way.

=back

=head1 SEE ALSO

L<Bio::Graphics::Browser>,
L<Bio::Graphics::Panel>,
L<Bio::Graphics::Glyph>,
L<Bio::Graphics::Feature>,
L<Bio::Graphics::FeatureFile>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2003 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut

use strict;
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::I18n;
use Bio::Graphics::Browser::Constants;
use CGI qw(:standard);
use Text::Shellwords;

use vars qw(@ISA @EXPORT $BROWSER $CONFIG $LANG %DB $HEADER $HTML $ADDED_FEATURES);
require Exporter;
@ISA = 'Exporter';
@EXPORT = qw(conf_dir open_config open_database
	     print_header html_frag
	     error fatal_error redirect_legacy_url
	     parse_feature_str
	    );

sub conf_dir {
  my $default = shift;
  if ($ENV{MOD_PERL} && Apache->can('request')) {
    my $conf  = Apache->request->dir_config('GBrowseConf');
    return Apache->server_root_relative($conf) if $conf;
  }
  return $default;
}

sub open_config {
  my $dir    = shift;
  my $suffix = shift;
  $CONFIG ||= Bio::Graphics::Browser->new;
  $CONFIG->read_configuration($dir,$suffix) or die "Can't read configuration files: $!";
  $LANG    ||= Bio::Graphics::Browser::I18n->new("$dir/languages");

  if ( ! $CONFIG->source ) {
    fatal_error($LANG->tr('NO_SOURCES'));
  }

  set_language($CONFIG,$LANG);
  $CONFIG->language($LANG);
  $CONFIG->dir($dir);
  $CONFIG->clear_cache();  # remove cached information

  # initialize some variables
  $HEADER=0;
  $HTML=0;
  $ADDED_FEATURES = 0;

  $CONFIG;
}

sub open_database {
  my $config  = shift || $CONFIG;
  my $source  = $config->source;
  return $DB{$source} if $DB{$source};
  my ($adaptor,@argv) = eval{$config->db_settings};
  unless ($adaptor) {
    warn "gbrowse: trying to reload config, cache must be stale";
    my $dir = $config->dir;
    $config = Bio::Graphics::Browser->new;
    $config->read_configuration($dir) or fatal_error("Can't read configuration files: $!");
    $config->source($source);
    ($adaptor,@argv) = $config->db_settings;
  }

  ################################################
  # HACK ALERT
  patch_old_versions_of_bioperl($adaptor);
  ################################################

  $DB{$source} = eval {$adaptor->new(@argv)} or warn $@;
  fatal_error('Could not open database.',pre("$@")) unless $DB{$source};

  if (my $refclass = $config->setting('reference class')) {
    eval {$DB{$source}->default_class($refclass)};
  }

  if ($DB{$source}->can('strict_bounds_checking')) {
    $DB{$source}->strict_bounds_checking(1);
  }

  return $DB{$source};
}

sub print_header {
  print header(@_) unless $HEADER++;
}

sub parse_added_feature {
  my $f      = shift;
  my $fcount = shift;
  my $zero   = 0;
  $fcount    ||= \$zero;
  my ($reference,$type,$name,@position);
  my @args = shellwords($f||'');
  if (@args > 3) {
    ($reference,$type,$name,@position) = @args;
  } elsif (@args > 2) {
    ($reference,$name,@position) = @args;
    $type = 'Your Features';
  } elsif (@args > 1) {
    ($reference,@position) = @args;
    ($type,$name) = ('Your Features',"Feature ".++$$fcount);
  }
  my @segments = map { [/(-?\d+)(?:-|\.\.)(-?\d+)/]} map {split /,/} @position;
  ($reference,$type,$name,@segments);
}

sub error {
  ###FIXME this should be made more graceful by making a header.tt2
  return fatal_error(@_);
#  my @msg = @_;
#  warn "@_" if DEBUG;
#  print_top();
#  print h2({-class=>'error'},@msg);
}

sub fatal_error {
  my @msg = @_;
  print_header(-expires=>'+1m');
  $BROWSER->template->process(
                              'error.tt2',
                              {
                               server_admin  => $ENV{SERVER_ADMIN},
                               error_message => join("\n",@msg),
                              }
                             ) or warn $BROWSER->template->error();
  exit 0;
}

sub set_language {
  my ($config,$lang) = @_;
  my $default_language   = $config->setting('language');
  my $accept         = http('Accept-language') || '';
  my @languages    = $accept =~ /([a-z]{2}-?[a-z]*)/ig;
  push @languages,$default_language if $default_language;
  warn "languages = ",join(',',@languages) if DEBUG;
  return unless @languages;
  $lang->language(@languages);
}

sub html_frag {
  my $fragname = shift;
  my $a = $CONFIG->config->code_setting(general => $fragname);
  return $a->(@_) if ref $a eq 'CODE';
  return $a || '';
}

sub patch_old_versions_of_bioperl {
  my $adaptor = shift;
  my %argv    = @_;
  local $^W = 0;
  if ($adaptor eq 'Bio::DB::GFF' && $argv{-adaptor} eq 'memory' && $Bio::Perl::VERSION <= 1.5) {
    # patch memory.pm inability to handle missing gclass fields
    eval <<'END';
use Bio::DB::GFF::Adaptor::memory;
sub Bio::DB::GFF::Adaptor::memory::load_gff_line {
  my $self = shift;
  my $feature_hash  = shift;
  $feature_hash->{strand} = '' if $feature_hash->{strand} && $feature_hash->{strand} eq '.';
  $feature_hash->{phase}  = ''  if $feature_hash->{phase}  && $feature_hash->{phase} eq '.';
  $feature_hash->{gclass} = 'Sequence' if length $feature_hash->{gclass} == 0;
  # sort by group please
  push @{$self->{tmp}{$feature_hash->{gclass},$feature_hash->{gname}}},$feature_hash;
}
END
  warn $@ if $@;
  }
}

sub redirect_legacy_url {
  my $source      = shift;
  my @more_args   = @_;
  if ($source && path_info() ne "/$source") {
    my $q = new CGI '';
    $q->path_info($source);
    if (request_method() eq 'GET') {
      foreach (qw(name ref start stop),@more_args) {
	$q->param($_=>param($_)) if param($_);
      }
    }
    print redirect($q->url(-absolute=>1,-path_info=>1,-query=>1));
    exit 0;
  }
}
sub parse_feature_str {
  my $f      = shift;
  my ($reference,$type,$name,@position);
  my @args = shellwords($f||'');
  if (@args > 3) {
    ($reference,$type,$name,@position) = @args;
  } elsif (@args > 2) {
    ($reference,$name,@position) = @args;
  } elsif (@args > 1) {
    ($reference,@position)       = @args;
  } elsif ($f =~ /^(.+):(\d+.+)$/) {
    ($reference,@position) = ($1,$2);
  } elsif ($f =~ /^(.+)/) {
    $reference = $1;
    @position  = '1..1';
  }
  return unless $reference;

  $type = 'Your Features'              unless defined $type;
  $name = "Feature ".++$ADDED_FEATURES unless defined $name;

  my @segments = map { [/(-?\d+)(?:-|\.\.)(-?\d+)/]} map {split /,/} @position;
  ($reference,$type,$name,@segments);
}


1;
