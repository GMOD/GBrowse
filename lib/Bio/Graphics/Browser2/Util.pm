package Bio::Graphics::Browser2::Util;

# a package of useful internal routines for GBrowse

=head1 NAME

Bio::Graphics::Browser2::Util -- Exported utilities

=head1 SYNOPSIS

  use Bio::Graphics::Browser2::Util;

  my $r = modperl_request();

=head1 DESCRIPTION

This package provides functions that support the Generic Genome
Browser.  It is not currently designed for external use.

=head2 FUNCTIONS


=cut

use strict;
use base 'Exporter';
use Text::ParseWords qw();
use Carp 'carp','cluck';
use Digest::MD5;

our @EXPORT    = qw(modperl_request error citation shellwords url_label);
our @EXPORT_OK = qw(modperl_request error citation shellwords url_label segment_str);

my $CURRENT_LANGUAGE;

use constant DEBUG => 0;

=over 4

=item my $r = modperl_request()

Return an Apache2::Request or an Apache::Request object, depending on
whichever version of Apache is running.

=cut

sub modperl_request {
  return unless $ENV{MOD_PERL};
  (exists $ENV{MOD_PERL_API_VERSION} &&
   $ENV{MOD_PERL_API_VERSION} >= 2 ) ? Apache2::RequestUtil->request
                                     : Apache->request;
}

=item error('message')

Prints an error message

=cut

sub error {
  my ($msg,$details) = @_;
  warn "@_";# if DEBUG;
  $msg     =~ s/'/\\'/g;
  $details =~ s/'/\\'/g;
  $msg     =~ s/\n/<br>/g;
  $details =~ s/\n/<br>/g;
  print CGI::script({-type=>'text/javascript'},
	       qq[Controller.show_error('$msg','$details')]);
#  print CGI::h2({-class=>'error'},@msg);
}


=item url_label($yucky_url)

Creates a label.alias for URL strings starting with 'http' or 'ftp'.
The last word (following a '/') in the url is used for the label.
Returns a string "url:label".

=cut

sub url_label {
  my $label = shift;
  my $key;
  if ($label =~ m!^(?:http|ftp)://([^/]+)!) {
    my $l    = $label;
    my $host = $1;
    $l =~ s!^\W+//!!;
    my (undef,$type) = $l =~ /\S+t(ype)?=([^;\&]+)/;
    $l =~ s/\?.+//;
    ($key) = grep /$_/, reverse split('/',$l);
    $key = "$host/$key" if $key;
    $key .= ":$type"  if $type;
  }
  return $key || $label;
}


=item citation(DataSource, 'label, [Language])

Returns a track citation

=cut

sub citation {
  my $data_source = shift;
  my $label       = shift;
  my $language    = shift;
  if ($label =~ /^plugin\:/) { 
    my $label_fix = $'; 
    $label_fix =~ s/\:detail$//;
    $label = join(":",($label_fix,'plugin'));
  }
  my $c;
  if ($language) {
    for my $l ($language->language) {
      $c ||= $data_source->setting($label=>"citation:$l");
    }
  }
  $c ||= $data_source->setting($label=>'citation');

  my $keywords                 = $data_source->code_setting($label=>'keywords');

  $c          .= "<br><i>$keywords</i>"         if $keywords;
  return $c;
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

=item $id = generate_id

Generate a new md5 hash of a random value for use in various IDs.

=cut

sub generate_id {
    my $md5 = new Digest::MD5();
    $md5->add($$ , time() , rand(time) );
    return $md5->hexdigest();
}

=item $string = segment_str($segment)

Returns a nicely formatted string in the format chr:start..stop with commas

=cut

sub segment_str {
    my $segment = shift;
    my $s  = 'Bio::Graphics::Browser2::DataSource';
    return $segment->seq_id . ':' .
	   $s->commas($segment->start) . '..' .
	   $s->commas($segment->end);
}

sub set_language {
    my $self = shift;
    $CURRENT_LANGUAGE = shift;
}

sub translate {
    my $self = shift;
    return 'untranslatable' unless $CURRENT_LANGUAGE;
    return $CURRENT_LANGUAGE->translate(@_);
}

1;

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
