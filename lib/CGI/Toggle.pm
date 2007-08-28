package CGI::Toggle;

use strict;
use base 'Exporter';
use CGI 'div','span','img','url';

our @EXPORT = ('toggle_section',
	       'start_html');

use constant PLUS    => 'plus.png';
use constant MINUS   => 'minus.png';
use constant JS      => 'toggle.js';

my $image_dir = '/gbrowse/images/buttons';
my $js_dir    = '/gbrowse/js';

my $style = <<'END';
.el_hidden  {display:none}
.el_visible {display:inline}
.ctl_hidden {
             cursor:pointer;
             display:none;
            }
.ctl_visible {
             cursor:pointer;
             display:inline;
            }
.tctl      {  text-decoration:underline; }
END

sub start_html {
  my %args = @_ == 1 ? (-title=>shift) : @_;

  $image_dir           = $args{-gbrowse_images} if defined $args{-gbrowse_images};
  $js_dir              = $args{-gbrowse_js}     if defined $args{-gbrowse_js};

  delete $args{-gbrowse_images};
  delete $args{-gbrowse_js};

  # earlier versions of CGI.pm don't support multiple -style and -script args.
  if ($CGI::VERSION >= 3.05) {
    if ($args{-style}) {
      $args{-style}= [{src => $args{-style}}] if !ref $args{-style};
      $args{-style}= [$args{-style}]          if ref $args{-style} && ref $args{-style} ne 'ARRAY';
    }
    push @{$args{-style}},{code=>$style};

    if ($args{-script}) {
      $args{-script} = [{src => $args{-script}}] if !ref $args{-script};
      $args{-script} = [$args{-script}]          if ref $args{-script} && ref $args{-script} ne 'ARRAY';
    }

    push @{$args{-script}},{src=>"$js_dir/".JS};
  }

  my $result = CGI::start_html(%args);

  if ($CGI::VERSION < 3.05) {
    my $style_section  = join '',$CGI::Q->_style({code=>$style});
    my $script_section = join '',$CGI::Q->_script({src=>"$js_dir/".JS});
    $result =~ s/<\/head>/$style_section\n$script_section\n<\/head>/i;
  }

  return $result;
}

sub toggle_section {
  my %config = ref $_[0] eq 'HASH' ? %{shift()} : ();
  my ($name,$section_title,@section_body) = @_;
  my $visible = $config{on};

  my $plus  = $config{plus_img}  || "$image_dir/".PLUS;
  my $minus = $config{minus_img} || "$image_dir/".MINUS;
  my $class = $config{class}     || 'tctl';

  my $show_ctl = div({-id=>"${name}_show",
		       -class=>'ctl_hidden',
		       -style=>$visible ? 'display:none' : 'display:inline',
		       -onClick=>"visibility('$name',1)"
                     },
		     img({-src=>$plus,-alt=>'+'}).'&nbsp;'.span({-class=>$class},$section_title));
  my $hide_ctl = div({-id=>"${name}_hide",
		       -class=>'ctl_visible',
		       -style=>$visible ? 'display:inline' : 'display:none',
		       -onClick=>"visibility('$name',0)"
                     },
		     img({-src=>$minus,-alt=>'-'}).'&nbsp;'.span({-class=>$class},$section_title));
  my $content  = div({-id    => $name,
		      -style=>$visible ? 'display:inline' : 'display:none',
		      -class => 'el_visible'},
		     @section_body);
  my @result = $config{nodiv} ? ($show_ctl.$hide_ctl,$content) : div($show_ctl.$hide_ctl,$content);
  return wantarray ? @result : "@result";
}

1;

__END__

=head1 NAME

CGI::Toggle -- Utility methods for collapsible sections

=head1 SYNOPSIS

use CGI ':standard';
use CGI::Toggle

print header(),
  start_html('Toggle Test'),
  h1("Toggle Test"),
  toggle_section({on=>1},p('This section is on by default'),
  toggle_section({on=>0},p('This section is off by default'),
  toggle_section({plus_img=>'/icons/open.png',
                  minus_img=>'/icons/close.png'},
                 p('This section has custom open and close icons.')),
  hr,
  end_html;

=head1 DESCRIPTION

This package adds JavaScript-based support for collapsible sections by
adding a single new function toggle_section().

It overrides the CGI start_html() method, so CGI must be imported
before bringing this module in.

=head2 METHODS

=over 4

=item ($control,$content) = toggle_section([\%options],$section_title=>@section_content)

This method takes an optional \%options hashref, a section title and
one or more strings containing the section content and returns a list
of HTML fragments corresponding to the control link and the content.
In a scalar context the control and content will be concatenated
together.

The option keys are as follows:

=over 4

=item b<on>

If true, the section will be on (visible) by default.  The default is
false (collapsed).

=item b<plus_img>

URL of the icon to display next to the section title when the section
is collapsed.  The default is /gbrowse/images/plus.png.

=item b<minus_img>

URL of the icon to display next to the section title when the section
is expanded..  The default is /gbrowse/images/minus.png.

=item b<override>

If false (default), the state of the section will be remembered in a
session variable.  If true, the initial state will be taken from the
b<on> option, ignoring the session.

=back

=back


=head1 SEE ALSO

L<CGI>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2005 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut
