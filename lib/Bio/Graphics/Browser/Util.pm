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
  print_top($config,$title);
  print_bottom($config,$version);
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

=item print_top($config,$title);

Print the top of the page.

=item print_bottom($config);

Print the bottom of the page.

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
use CGI qw(:standard);
use CGI::Toggle;
use Carp 'carp';
use Text::Shellwords;

use vars qw(@ISA @EXPORT $CONFIG $LANG %DB $HEADER $HTML $ADDED_FEATURES);
require Exporter;
@ISA = 'Exporter';
@EXPORT = qw(conf_dir open_config open_database
	     print_header print_top print_bottom html_frag
	     error fatal_error redirect_legacy_url
	     parse_feature_str url2file modperl_request
	    );

use constant DEBUG => 0;
use constant JS    => '/gbrowse/js';

sub conf_dir {
  my $default = shift;
  if (my $request = modperl_request()) {
    my $conf  = $request->dir_config('GBrowseConf') or return $default;
    return $conf if $conf =~ m!^/!;                # return absolute
    return (exists $ENV{MOD_PERL_API_VERSION} &&
	    $ENV{MOD_PERL_API_VERSION} >= 2)
      ? Apache2::ServerUtil::server_root() . "/$conf"
      : Apache->server_root_relative($conf);
  }
  return $default;
}

sub url2file {
  my $url = shift;
  my $request = modperl_request();

  for my $l ((map {"$url.$_"} $CONFIG->language->language), $url) {
    my $file = $request ? $request->lookup_uri($l)->filename
                        : "$ENV{DOCUMENT_ROOT}/$l";
    return $file if -e $file;
  }
  return;
}

sub modperl_request {
  return unless $ENV{MOD_PERL};
  (exists $ENV{MOD_PERL_API_VERSION} &&
   $ENV{MOD_PERL_API_VERSION} >= 2 ) ? Apache2::RequestUtil->request
                                     : Apache->request;
}


sub open_config {
  my $dir    = shift;
  my $suffix = shift;
  $CONFIG ||= Bio::Graphics::Browser->new;
  $CONFIG->read_configuration($dir,$suffix) or die "Can't read configuration files: $!";
  $LANG    ||= Bio::Graphics::Browser::I18n->new("$dir/languages");
  $CONFIG->source or early_error($LANG,'NO_SOURCES');

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
  patch_old_versions_of_bioperl($adaptor,@argv);
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

sub print_top {
  my $title = shift;
  local $^W = 0;  # to avoid a warning from CGI.pm
  print_header(-expires=>'+1m');
  my @args = (-title => $title,
	      -style  => {src=>$CONFIG->setting('stylesheet')},
	      -encoding=>$CONFIG->tr('CHARSET'),
	     );
  push @args,(-head=>$CONFIG->setting('head'))    if $CONFIG->setting('head');
  push @args,(-lang=>($CONFIG->language_code)[0]) if $CONFIG->language_code;
  push @args,(-script=>{src=>($CONFIG->setting('js')||JS) . "/buttons.js"});
  push @args,(-gbrowse_images => $CONFIG->setting('buttons') || '/gbrowse/images/buttons');
  push @args,(-gbrowse_js     => $CONFIG->setting('js')      || '/gbrowse/js');
  print start_html(@args) unless $HTML++;
}

sub print_bottom {
  my ($version) = @_;
  print
    $CONFIG->footer || '',
      p(i(font({-size=>'small'},
	       $CONFIG->tr('Footer_1'))),br,
	tt(font({-size=>'small'},$CONFIG->tr('Footer_2',$version)))),
	  end_html;
}

sub error {
  my @msg = @_;
  warn "@_" if DEBUG;
  print_top();
  print h2({-class=>'error'},@msg);
}

sub fatal_error {
  my @msg = @_;
  warn "@_" if DEBUG;
  print_top($CONFIG,'GBrowse Error');
  print h2('An internal error has occurred');
  print p({-class=>'error'},@msg);
  my $webmaster = $ENV{SERVER_ADMIN} ?
   "maintainer (".a({-href=>"mailto:$ENV{SERVER_ADMIN}"},$ENV{SERVER_ADMIN}).')'
     : 'maintainer';
  print p("Please contact this site's $webmaster for assistance.");
  print_bottom($CONFIG);
  exit 0;
}


sub early_error {
  my $lang = shift;
  my $msg  = shift;
  $msg     = $lang->tr($msg);
  warn "@_" if DEBUG;
  local $^W = 0;  # to avoid a warning from CGI.pm
  print_header(-expires=>'+1m');
  my @args = (-title  => 'GBrowse Error');
  push @args,(-lang=>$lang->language);
  print start_html();
  print b($msg);
  print end_html;
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
  if ($source && path_info() ne "/$source/") {

    # This ugly-looking code is a workaround for a mod_cgi bug that occurs in
    # Apache version 2 when the path contains double slashes //
    $ENV{SCRIPT_NAME} =~ s!^(.+/gbrowse[^/]*)/.*!$1!;
    $ENV{REQUEST_URI} =~ s!^(.+/gbrowse[^/]*)/.*!$1!;

    my $q = new CGI '';
    $q->path_info("/$source/");

    if (request_method() eq 'GET') {
      foreach (param()) {
	next if $_ eq 'source';
	$q->param($_=>param($_)) if param($_);
      }
    }
    my $new_url = $q->url(-absolute=>1,-path_info=>1,-query=>1);
    print redirect($new_url);
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
