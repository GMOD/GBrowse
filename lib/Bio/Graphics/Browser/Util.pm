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

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

use strict;
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::I18n;
use CGI qw(:standard);
use CGI::Toggle;
use Carp 'carp','cluck';
use Text::ParseWords ();

use vars qw(@ISA @EXPORT $CONFIG $LANG %DB $HEADER $HTML $ADDED_FEATURES);
require Exporter;
@ISA = 'Exporter';
@EXPORT = qw(conf_dir open_config open_database
	     print_header print_top print_bottom html_frag
	     error fatal_error redirect_legacy_url
	     parse_feature_str url2file modperl_request is_safari
             shellwords
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
  # $CONFIG->source or early_error($LANG,'NO_SOURCES');

  set_language($CONFIG,$LANG);
  $CONFIG->language($LANG);
  $CONFIG->dir($dir);

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

  $DB{$source}->strict_bounds_checking(1) if $DB{$source}->can('strict_bounds_checking');
  $DB{$source}->absolute(1)               if $DB{$source}->can('absolute');

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
  my @segments = map { [/(-?\d+)(?:-|\.\.)(-?\d+)/]} map {split ','} @position;
  ($reference,$type,$name,@segments);
}

sub print_top {
  my $title     = shift;
  my $reset_all = shift;
  my $alert     = shift;
  local $^W = 0;  # to avoid a warning from CGI.pm

  my $titlebar    = is_safari() ? 'titlebar-safari.css' : 'titlebar-default.css';

  my @extra_headers;
  my @stylesheets = shellwords($CONFIG->setting('stylesheet') || '/gbrowse/gbrowse.css');
  for my $ss (@stylesheets) {
      my ($url,$media) = $ss =~ /^([^(]+)(?:\((.+)\))?/;
      $media ||= 'all';
      push @extra_headers,CGI::Link({-rel=>'stylesheet',
				     -type=>'text/css',
				     -href=>$CONFIG->relative_path($url),
				     -media=>$media});
  }

  push @extra_headers,$CONFIG->setting('head') if $CONFIG->setting('head');

  print_header(-expires=>'now');
  my @args = (-title => $title,
	      -style  => [{src=>$CONFIG->relative_path('tracks.css')},
			  {src=>$CONFIG->relative_path($titlebar)}],
	      -encoding=>$CONFIG->tr('CHARSET'),
	     );
  push @args,(-lang=>($CONFIG->language_code)[0]) if $CONFIG->language_code;
  push @args,(-gbrowse_images => $CONFIG->relative_path_setting('buttons') || '/gbrowse/images/buttons');
  push @args,(-gbrowse_js     => $CONFIG->relative_path_setting('js')      || '/gbrowse/js');
  push @args,(-reset_toggle   => 1)               if $reset_all;

  my @onload;
  push @onload, $CONFIG->setting('onload') if $CONFIG->setting('onload');
  push @onload, "alert('$alert')"          if $alert;

  # push all needed javascript files onto top of page
  my $drag_and_drop = $CONFIG->drag_and_drop;
  my $b_tips        = $CONFIG->setting('balloon tips') || $drag_and_drop;
  my $js            = $CONFIG->relative_path_setting('js')||JS;
  my @js            = ('buttons.js','prototype.js');
  push @js, qw(yahoo-dom-event.js balloon.config.js balloon.js)     if $b_tips;
  push @js, qw(rubber.js overviewSelect.js detailSelect.js);
  push @js, 'scriptaculous.js' if $drag_and_drop;
  push @js, 'bookmark.js';
  push @onload, 'Overview.prototype.initialize()';
  push @onload, 'Details.prototype.initialize()';

  if ($CONFIG->setting('region segment')) {
    push @js, 'regionSelect.js';
    push @onload, 'Region.prototype.initialize()';
  }


  my @scripts = map { {src=> "$js/$_" } } @js;
  push @args, (-script => \@scripts);
  push @args, (-onLoad => join('; ',@onload));
  push @args, (-head   => \@extra_headers);

  print start_html(@args) unless $HTML++;
  print_balloon_settings()  if $b_tips;
  print_select_menu($_) for (qw/DETAIL OVERVIEW REGION/);
}

# prepare custom menu(s) for rubber-band selection
sub print_select_menu {
  my $view = shift || 'DETAIL';
  my $config_label = uc($view).' SELECT MENU';

  # HTML for the custom menu is required
  my $menu_html =  $CONFIG->setting($config_label => 'HTML') 
                || $CONFIG->setting($config_label => 'html') 
                || return;

  # should not be visible
  my %style = (display => 'none');
  # optional style attributes
  for my $att (qw/width font background background-color border/) {
    my $val = $CONFIG->setting($config_label => $att) || next;
    $style{$att} = $val;
  } 
  $style{width} .= 'px';
  my $style = join('; ', map {"$_:$style{$_}"} keys %style);

  # clean up the HTML just a bit
  $menu_html =~ s/\</\n\</g;

  print div( { -style => $style, 
	       -id    => lc($view).'SelectMenu' }, 
	     $menu_html );
}

sub print_balloon_settings {
  my $custom_balloons    = $CONFIG->setting('custom balloons');
  my $images             = $CONFIG->relative_path('images');
  my %config_values = $custom_balloons =~ /\[([^]]+)\]([^[]+)/g;
  $config_values{'balloon'} ||= <<END;
images    =  $images/balloons
delayTime =  500
END

  my $balloon_settings;

  for my $balloon (keys %config_values) {
    my %config = $config_values{$balloon} =~ /(\w+)\s*=\s*(\S+)/g;
    my $img    = $config{images} || "$images/balloons";
    $balloon_settings .= <<END;
var $balloon = new Balloon;
BalloonConfig($balloon);
$balloon.images              = '$img';
$balloon.balloonImage        = 'balloon.png';
$balloon.ieImage             = 'balloon_ie.png';
$balloon.upLeftStem          = 'up_left.png';
$balloon.downLeftStem        = 'down_left.png';
$balloon.upRightStem         = 'up_right.png';
$balloon.downRightStem       = 'down_right.png';
$balloon.closeButton         = 'close.png';
END
    for my $option (keys %config) {
      next if $option eq 'images';
      my $value = $config{$option} =~ /^[\d.-]+$/ ? $config{$option} : "'$config{$option}'";
      $balloon_settings .= "$balloon.$option = $value;\n";
    }
  }
  print "<script>\n$balloon_settings\n</script>\n";
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
  cluck "@_" if DEBUG;
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
  my $a = $CONFIG->config->setting(general => $fragname);
  return $a->(@_) if ref $a eq 'CODE';
  return $a || '';
}

sub patch_old_versions_of_bioperl {
  my $adaptor = shift;
  my %argv    = @_;
  local $^W = 0;
  require Bio::Perl;
  if ($adaptor eq 'Bio::DB::GFF' && $Bio::Perl::VERSION == 1.5) {
  eval <<'END';
use Bio::DB::GFF;
sub Bio::DB::GFF::load_gff {
  my $self              = shift;
  my $file_or_directory = shift || '.';
  my $verbose           = shift;

  local $self->{__verbose__} = $verbose;
  return $self->do_load_gff($file_or_directory) if ref($file_or_directory) 
                                                   && tied *$file_or_directory;

  my $tied_stdin = tied(*STDIN);
  open SAVEIN,"<&STDIN" unless $tied_stdin;
  local @ARGV = $self->setup_argv($file_or_directory,'gff','gff3') or return;  # to play tricks with reader
  my $result = $self->do_load_gff('ARGV');
  open STDIN,"<&SAVEIN" unless $tied_stdin;  # restore STDIN
  return $result;
}
sub Bio::DB::GFF::_load_gff_line {
  my $self = shift;
  my $line = shift;
  my $lineend = $self->{load_data}{lineend};

  $self->{load_data}{gff3_flag}++           if $line =~ /^\#\#\s*gff-version\s+3/;
  $self->preferred_groups(split(/\s+/,$1))  if $line =~ /^\#\#\s*group-tags?\s+(.+)/;

  if ($line =~ /^\#\#\s*sequence-region\s+(\S+)\s+(\d+)\s+(\d+)/i) { # header line
    $self->load_gff_line(
			 {
			  ref    => $1,
			  class  => 'Sequence',
			  source => 'reference',
			  method => 'Component',
			  start  => $2,
			  stop   => $3,
			  score  => undef,
			  strand => undef,
			  phase  => undef,
			  gclass => 'Sequence',
			  gname  => $1,
			  tstart => undef,
			  tstop  => undef,
			  attributes  => [],
			 }
			);
    return $self->{load_data}{count}++;
  }

  return if /^#/;

  my ($ref,$source,$method,$start,$stop,$score,$strand,$phase,$group) = split "\t",$line;
  return unless defined($ref) && defined($method) && defined($start) && defined($stop);
  foreach (\$score,\$strand,\$phase) {
    undef $$_ if $$_ eq '.';
  }

  print STDERR $self->{load_data}{count}," records$lineend" 
    if $self->{__verbose__} && $self->{load_data}{count} % 1000 == 0;

  my ($gclass,$gname,$tstart,$tstop,$attributes) = $self->split_group($group,$self->{load_data}{gff3_flag});

  # no standard way in the GFF file to denote the class of the reference sequence -- drat!
  # so we invoke the factory to do it
  my $class = $self->refclass($ref);

  # call subclass to do the dirty work
  if ($start > $stop) {
    ($start,$stop) = ($stop,$start);
    if ($strand eq '+') {
      $strand = '-';
    } elsif ($strand eq '-') {
      $strand = '+';
    }
  }
  # GFF2/3 transition stuff
  $gclass = [$gclass] unless ref $gclass;
  $gname  = [$gname]  unless ref $gname;
  for (my $i=0; $i<@$gname;$i++) {
    $self->load_gff_line({ref    => $ref,
			  class  => $class,
			  source => $source,
			  method => $method,
			  start  => $start,
			  stop   => $stop,
			  score  => $score,
			  strand => $strand,
			  phase  => $phase,
			  gclass => $gclass->[$i],
			  gname  => $gname->[$i],
			  tstart => $tstart,
			  tstop  => $tstop,
			  attributes  => $attributes}
			);
    $self->{load_data}{count}++;
  }
}
END
  warn $@ if $@;
  }

  if ($adaptor eq 'Bio::DB::GFF' && $argv{-adaptor} eq 'memory' && $Bio::Perl::VERSION <= 1.5) {
    # patch memory.pm inability to handle missing gclass fields
    eval <<'END';
use Bio::DB::GFF::Adaptor::memory;
sub Bio::DB::GFF::Adaptor::memory::load_gff_line {
  my $self = shift;
  my $feature_hash  = shift;
  $feature_hash->{strand} = '' if $feature_hash->{strand} && $feature_hash->{strand} eq '.';
  $feature_hash->{phase}  = ''  if $feature_hash->{phase}  && $feature_hash->{phase} eq '.';
  $feature_hash->{gclass} = 'Sequence' unless length $feature_hash->{gclass} > 0;
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

    my $q = new CGI '';
    if (request_method() eq 'GET') {
      foreach (param()) {
	next if $_ eq 'source';
	$q->param($_=>param($_)) if defined param($_);
      }
    }

    # This is infinitely more difficult due to horrible bug in Apache version 2
    # It is fixed in CGI.pm versions 3.11 and higher, but this version is not guaranteed
    # to be available.
    my ($script_name,$path_info) = _broken_apache_hack();
    my $query_string = $q->query_string;
    my $protocol     = $q->protocol;

    my $new_url      = $script_name;
    $new_url        .= "/$source/";
    $new_url        .= "?$query_string" if $query_string;

    print redirect(-uri=>$new_url,-status=>"301 Moved Permanently");
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

  my @segments = map { [/(-?\d+)(?:-|\.\.)(-?\d+)/]} map {split ','} @position;
  ($reference,$type,$name,@segments);
}

# workaround for broken Apache 2 and CGI.pm <= 3.10
sub _broken_apache_hack {
  my $raw_script_name = $ENV{SCRIPT_NAME} || '';
  my $raw_path_info   = $ENV{PATH_INFO}   || '';
  my $uri             = $ENV{REQUEST_URI} || '';

   ## dgg patch; need for what versions? apache 1.x; 
  if ($raw_script_name =~ m/$raw_path_info$/) {
    $raw_script_name =~ s/$raw_path_info$//;
  }

  my @uri_double_slashes  = $uri =~ m^(/{2,}?)^g;
  my @path_double_slashes = "$raw_script_name $raw_path_info" =~ m^(/{2,}?)^g;

  my $apache_bug      = @uri_double_slashes != @path_double_slashes;
  return ($raw_script_name,$raw_path_info) unless $apache_bug;

  my $path_info_search = $raw_path_info;
  # these characters will not (necessarily) be escaped
  $path_info_search    =~ s/([^a-zA-Z0-9$()':_.,+*\/;?=&-])/uc sprintf("%%%02x",ord($1))/eg;
  $path_info_search    = quotemeta($path_info_search);
  $path_info_search    =~ s!/!/+!g;
  if ($uri =~ m/^(.+)($path_info_search)/) {
    return ($1,$2);
  } else {
    return ($raw_script_name,$raw_path_info);
  }
}

sub is_safari {
  return CGI::user_agent =~ /safari/i;
}

# work around an annoying uninit variable warning from Text::Parsewords
sub shellwords {
    my @args = @_;
    return unless @args;
    foreach(@args) {
	s/^\s+//;
	s/\s+$//;
	$_ = '' unless defined $_;
    }
    my @result = Text::ParseWords::shellwords(@args);
    return @result;
}
1;
