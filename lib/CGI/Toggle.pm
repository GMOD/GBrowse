package CGI::Toggle;

use strict;
use base 'Exporter';
use CGI 'div','span','img','url';
use CGI::Util;

use vars '$next_id';

our @EXPORT = ('toggle_section',
	       'start_html');

use constant PLUS    => '/gbrowse/images/buttons/plus.png';
use constant MINUS   => '/gbrowse/images/buttons/minus.png';
use constant JS      => '/gbrowse/js/toggle.js';
use constant EXPIRES => CGI::Util::expires('+7d');

my $cookie_name = __PACKAGE__;
$cookie_name    =~ s/:/_/g;

my $jscript = <<"END";
function turnOn (a) {
    a.style.display=(a.className=="ctl_hidden" || a.className=="ctl_visible")
           ? "inline" : "block";
}
function turnOff (a) {
    a.style.display="none";
}

function visibility (a,state) {
   var element = document.getElementById(a);
   var show_control = document.getElementById(a + "_show");
   var hide_control = document.getElementById(a + "_hide");
   if (state == "on") {
      turnOn(element);
      turnOff(show_control);
      turnOn(hide_control);
   } else if (state == "off"){
      turnOff(element);
      turnOff(hide_control);
      turnOn(show_control);
   }
   setVisState(a,state);
   return false;
}

function setVisState (a,state) {
   var cookie_name    = '$cookie_name';
   var cookie_path    = location.pathname;
   var cookie_expires = '${\EXPIRES}';
   var el_index       = a.substring(1);
   var cookie_value   = xGetCookie(cookie_name);
   if (!cookie_value) { cookie_value = 0xFFFFFF; }
   if (state == "on") { cookie_value |= (1 << el_index) }
                 else { cookie_value &= ~(1 << el_index) }
   xSetCookie(cookie_name,cookie_value,cookie_expires,cookie_path);
}

function getVisState (a) {
   var cookie_name    = '$cookie_name';
   var el_index       = a.id.substring(1);
   var cookie_value   = xGetCookie(cookie_name);
   if (!cookie_value) { cookie_value = 0xFFFFFF; }
   return (cookie_value &= (1 << el_index)) == 0 ? 'off' : 'on';
}

// The x{Set,Get}Cookie functions are derived from cross-brower.com
// Copyright (c) 2004 Michael Foster, Licensed LGPL (gnu.org)
function xSetCookie(name, value, expire, path)
{
  document.cookie = name + "=" + escape(value) +
                    (!expire ? "" : "; expires=" + expire) +
                    "; path=" + ((!path) ? "/" : path);
}

function xGetCookie(name)
{
  var value=null, search=name+"=";
  if (document.cookie.length > 0) {
    var offset = document.cookie.indexOf(search);
    if (offset != -1) {
      offset += search.length;
      var end = document.cookie.indexOf(";", offset);
      if (end == -1) end = document.cookie.length;
      value = unescape(document.cookie.substring(offset, end));
    }
  }
  return value;
}

function startPage() {
 var spans=document.getElementsByTagName("div");
 for (var i=0; i < spans.length; i++){
    if (spans[i].className=="ctl_hidden" || spans[i].className=="el_hidden" ) {
           spans[i].style.display = "none";
    }
 }
}
END

my $style = <<'END';
.el_hidden  {display:none}
.el_visible {display:block}
.ctl_hidden {
             cursor:hand;
             display:none;
            }
.ctl_visible {
             cursor:hand;
             display:inline;
            }
.tctl      {  text-decoration:underline; }
END

my $noscript = <<'END';
<style>
.el_hidden { display:block }
.nojs      { display:none }
</style>
END


sub start_html {
  $next_id = 'T0000';
  my %args = @_ == 1 ? (-title=>shift) : @_;

  $args{-noscript}     = $noscript;
  $args{-onLoad}       = "startPage()";

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

    push @{$args{-script}},{code=>$jscript};
  }

  my $state = CGI::cookie($cookie_name);
# these various attempts to default end up forcing all sections either open or closed.
#  $state = 0 unless defined $state && $state >= 0;
#  $state = 0xFFFFFF unless defined $state && $state >= 0 && $state <= 0xFFFFFF;
  if (defined $state) {
    my $cookie = CGI::cookie(-name=>$cookie_name,
			     -value=>$state,
			     -path=>url(-path_info=>1,-absolute=>1),
			     -expires=>'+7d');
    $args{-head}         = CGI::meta({-http_equiv=>'Set-Cookie',
				      -content => $cookie});
  }

  my $result = CGI::start_html(%args);

  if ($CGI::VERSION < 3.05) {
    my $style_section  = join '',CGI->_style({code=>$style});
    my $script_section = join '',CGI->_script({code=>$jscript});
    $result =~ s/<\/head>/$style_section\n$script_section\n<\/head>/i;
  }

  return $result;
}

# The weird playing around with class names is to accomodate the need to have
# a default setting of visibility that can be overridden by a stored cookie.
sub toggle_section {
  my %config = ref $_[0] eq 'HASH' ? %{shift()} : ();
  my ($section_title,@section_body) = @_;

  my $id = $next_id++;
  if (!$config{override} && (my $cookie = CGI::cookie($cookie_name))) {
    $config{on} = ($cookie & (1<<substr($id,1)||0)) != 0;
  }

  my $plus  = $config{plus_img}  || PLUS;
  my $minus = $config{minus_img} || MINUS;

  my $show_ctl = span({-id=>"${id}_show",
		       -class=>$config{on} ? "ctl_hidden" : "ctl_visible",
		       -onClick=>"visibility('$id','on')"},
		      img({-src=>$plus}).'&nbsp;'.span({-class=>'tctl'},$section_title));
  my $hide_ctl = span({-id=>"${id}_hide",
		       -class=>$config{on} ? "ctl_visible" : "ctl_hidden",
		       -onClick=>"visibility('$id','off')"},
		      img({-src=>$minus}).'&nbsp;'.span({-class=>'tctl'},$section_title));
  my $content  = div({-id    => $id,
		      -class => $config{on} ? 'el_visible' : 'el_hidden'},
		     @section_body);
  my @result = ($show_ctl.$hide_ctl,$content);
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
cookie.  If true, the initial state will be taken from the b<on>
option, ignoring the cookie (which will, however, still be generated).

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

The xGetCookie() and xSetCookie() JavaScript functions were derived
from www.cross-browser.com, and are copyright (c) 2004 Michael Foster,
and licensed under the LGPL (gnu.org).

=cut
