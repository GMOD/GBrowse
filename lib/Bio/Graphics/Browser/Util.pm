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
use vars qw(@ISA @EXPORT $CONFIG $LANG %DB $HEADER $HTML);
require Exporter;
@ISA = 'Exporter';
@EXPORT = qw(conf_dir open_config open_database
	     print_header print_top print_bottom html_frag
	     error fatal_error);

use constant DEBUG => 0;

sub conf_dir {
  my $default = shift;
  if ($ENV{MOD_PERL}) {
    my $conf  = Apache->request->dir_config('GBrowseConf');
    return Apache->server_root_relative($conf) if $conf;
  }
  return $default;
}

sub open_config {
  my $dir = shift;
  $CONFIG ||= Bio::Graphics::Browser->new;
  $CONFIG->read_configuration($dir) or die "Can't read configuration files: $!";
  $LANG    ||= Bio::Graphics::Browser::I18n->new("$dir/languages");
  set_language($CONFIG,$LANG);
  $CONFIG->language($LANG);

  # initialize some variables
  $HEADER=0;
  $HTML=0;

  $CONFIG;
}

sub open_database {
  my $config  = shift || $CONFIG;
  my $source  = $config->source;
  return $DB{$source} if $DB{$source};
  my ($adaptor,@argv) = eval{$config->db_settings};
  unless ($adaptor) {
    warn "gbrowse: trying to reload config, cache must be stale";
    $config = Bio::Graphics::Browser->new;
    $config->read_configuration($config->dir) or fatal_error("Can't read configuration files: $!");
    $config->source($source);
    ($adaptor,@argv) = $config->db_settings;
  }
  $DB{$source} = eval {$adaptor->new(@argv)} or warn $@;
  fatal_error(pre($@)) unless $DB{$source};
  if (my $refclass = $config->setting('reference class')) {
    eval {$DB{$source}->default_class($refclass)};
  }
  return $DB{$source};
}

sub print_header {
  print header(@_) unless $HEADER++;
}

sub print_top {
  my $title = shift;
  print_header();
  print start_html(-title => $title,
		   -style  => {src=>$CONFIG->setting('stylesheet')}) unless $HTML++;
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

sub set_language {
  my ($config,$lang) = @_;
  my $default_language   = $config->setting('language');
  my @languages     = http('Accept-language') =~ /([a-z]{2}-?[a-z]*)/ig;
  push @languages,$default_language if $default_language;
  warn "languages = ",join(',',@languages) if DEBUG;
  return unless @languages;
  $lang->language(@languages);
}

sub html_frag {
  my $fragname = shift;
  my $a = $CONFIG->config->code_setting(general => $fragname);
  return $a->(@_) if ref $a eq 'CODE';
  return $a;
}

1;
