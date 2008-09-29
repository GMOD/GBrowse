package Bio::Graphics::Browser::Util;

# a package of useful internal routines for GBrowse

=head1 NAME

Bio::Graphics::Browser::Util -- Exported utilities

=head1 SYNOPSIS

  use Bio::Graphics::Browser::Util;

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

our @EXPORT    = qw(modperl_request error citation shellwords get_section_from_label);
our @EXPORT_OK = qw(modperl_request error citation shellwords get_section_from_label);

use constant DEBUG => 1;

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
  my @msg = @_;
  cluck "@_" if DEBUG;
  print CGI::h2({-class=>'error'},@msg);
}

=item citation(DataSource, 'label, [Language])

Returns a track citation

=cut

sub citation {
  my $data_source = shift;
  my $label       = shift;
  my $language    = shift;
  my $c;
  if ($language) {
    for my $l ($language->language) {
      $c ||= $data_source->setting($label=>"citation:$l");
    }
  }
  $c ||= $data_source->setting($label=>'citation');
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

sub get_section_from_label {
    my $label = shift;
    if ($label eq 'overview' || $label =~ /:overview$/){
        return 'overview';
    }
    elsif ($label eq 'region' || $label =~  /:region$/){
        return 'region';
    }
    return 'detail'
}

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
