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
	     error fatal_error redirect_legacy_url
	    );

use constant DEBUG => 0;

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
  set_language($CONFIG,$LANG);
  $CONFIG->language($LANG);
  $CONFIG->dir($dir);
  $CONFIG->clear_cache();  # remove cached information

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
    my $dir = $config->dir;
    $config = Bio::Graphics::Browser->new;
    $config->read_configuration($dir) or fatal_error("Can't read configuration files: $!");
    $config->source($source);
    ($adaptor,@argv) = $config->db_settings;
  }

  ################################################
  # HACK ALERT - REMOVE AFTER BIOPERL 2.0 RELEASED
  patch_old_versions_of_bioperl($adaptor);
  ################################################

  $DB{$source} = eval {$adaptor->new(@argv)} or warn $@;
  fatal_error(pre($@)) unless $DB{$source};

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

sub print_top {
  my $title = shift;
  local $^W = 0;  # to avoid a warning from CGI.pm
  print_header(-expires=>'+1m');
  my @args = (-title => $title,
	      -style  => {src=>$CONFIG->setting('stylesheet')});
  push @args,(-head=>$CONFIG->setting('head')) if $CONFIG->setting('head');
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
  local $^W = 0;
  if ($adaptor eq 'Bio::DB::GFF') {

    # patch missing is_circular method
    eval <<'END' unless defined &Bio::DB::GFF::Segment::is_circular;
sub Bio::DB::GFF::Segment::is_circular { 0; }
END

    warn $@ if $@;

    # patch problems on Windows platforms with memory adaptor
    # (having to do with broken glob() in perl 5.8)
  if ($^O =~ /^MSWin/ && $Bio::DB::GFF::VERSION <= 1.4) {

    eval <<'END';
sub Bio::DB::GFF::setup_argv {
  my $self = shift;
  my $file_or_directory = shift;
  my @suffixes          = @_;
  no strict 'refs';  # so that we can call fileno() on the argument
  my @argv;

  if (-d $file_or_directory) {
    # Because glob() is broken with long file names that contain spaces
    $file_or_directory = Win32::GetShortPathName($file_or_directory)
      if $^O =~ /^MSWin/i && eval "use Win32; 1;";
    @argv = map { glob("$file_or_directory/*.{$_,$_.gz,$_.Z,$_.bz2}")} @suffixes;
  }elsif (my $fd = fileno($file_or_directory)) {
    open STDIN,"<&=$fd" or $self->throw("Can't dup STDIN");
    @argv = '-';
  } elsif (ref $file_or_directory) {
    @argv = @$file_or_directory;
  } else {
    @argv = $file_or_directory;
  }

  foreach (@argv) {
    if (/\.gz$/) {
      $_ = "gunzip -c $_ |";
    } elsif (/\.Z$/) {
      $_ = "uncompress -c $_ |";
    } elsif (/\.bz2$/) {
      $_ = "bunzip2 -c $_ |";
    }
  }
  @argv;
}
END
   warn $@ if $@;

   eval <<'END';
sub Bio::DB::Fasta::new {
  my $class = shift;
  my $path  = shift;
  my %opts  = @_;

  my $self = bless { debug      => $opts{-debug},
		     makeid     => $opts{-makeid},
		     glob       => $opts{-glob}    || '*.{fa,fasta,FA,FASTA,fast,FAST,dna,fsa}',
		     maxopen    => $opts{-maxfh}   || 32,
		     dbmargs    => $opts{-dbmargs} || undef,
		     fhcache    => {},
		     cacheseq   => {},
		     curopen    => 0,
		     openseq    => 1,
		     dirname    => undef,
		     offsets    => undef,
		   }, $class;
  my ($offsets,$dirname);

  if (-d $path) {
    # Because Win32 glob() is broken with respect to 
    # long file names that contain spaces
    $path = Win32::GetShortPathName($path)
      if $^O =~ /^MSWin/i && eval 'use Win32; 1';
    $offsets = $self->index_dir($path,$opts{-reindex});
    $dirname = $path;
  } elsif (-f _) {
    $offsets = $self->index_file($path,$opts{-reindex});
    $dirname = dirname($path);
  } else {
    $self->throw( "$path: Invalid file or dirname");
  }
  @{$self}{qw(dirname offsets)} = ($dirname,$offsets);

  $self;
}
END
    ;
    warn $@ if $@;
    }
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


1;
