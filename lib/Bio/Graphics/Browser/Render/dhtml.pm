package Bio::Graphics::Browser::Render::dhtml;
#$Id: dhtml.pm,v 1.2 2006-12-01 11:20:24 sheldon_mckay Exp $
#
# A package for adding DHTML functionality to gbrowse
# This served mainly as a wrapper for CGI::Toggle to add javascript and
# style information to the page header.  It will also supply other methods
# for DHTML functionality

use strict;
use base 'Exporter';
use CGI ':standard';
use CGI::Toggle;

our @EXPORT = ('toggle_section',
	       'start_gbrowse_html',
	       'selectable_detail_panel');

use constant JSFILES   => ('rubber.js', 'cross-browser.js');
use constant JSDIR     => '/gbrowse/js';

sub start_gbrowse_html {
  my %args = @_ == 1 ? (-title=>shift) : @_;

  my $js_dir = $args{-gbrowse_js} || JSDIR;

  if ($args{-style}) {
    $args{-style}= [{src => $args{-style}}] if !ref $args{-style};
    $args{-style}= [$args{-style}]          if ref $args{-style} && ref $args{-style} ne 'ARRAY';
  }

  if ($args{-script}) {
    $args{-script} = [{src => $args{-script}}] if !ref $args{-script};
    $args{-script} = [$args{-script}]          if ref $args{-script} && ref $args{-script} ne 'ARRAY';
  }

  for my $js (JSFILES) {
    push @{$args{-script}},{src=>"$js_dir/$js"};
  }

  my $layers = <<END;
<DIV ID="selectBox"></DIV>
<DIV ID="selectMenu"></DIV>
<DIV ID="debug" style="position:static;top:0;width:500;visibility:visible;font-size:small"></DIV>
END
;

  return CGI::Toggle::start_html(%args) . $layers;
}

sub selectable_detail_panel {
  my ($img,$map,$seg,$pl) = @_;
  $img = lc $img;
  my %img_data = $img =~ /(\S+)="(\S+)"/g;
  my ($img_url,$map_id,$w,$h) = map {$img_data{$_}} qw/src usemap width height/;
  my ($r,$s,$e) = map {$seg->$_} qw/ref start stop/;
  $map_id =~ s/\#//;  

  my $result;
  # pass the image stats to the javasript function
  $result .= qq(<div ID="imageData" style="display:none">$w $h $pl $r $s $e $map_id</div>\n);
  # parent layer for the image -- gives dynamic top position
  $result .= qq(<div style="width:100%;text-align:center" class="databody" ID="imageLoc">\n);
  $result .= qq(<input type="image" id="detailPanel" src="$img_url" onload="loadImageData()" onclick="return false" \>\n);
  $result .= qq(<div ID="cssMap">$map</div>\n<\div>\n);

  return $result;
}

1;

__END__

=head1 NAME

Bio::Graphics::Browser::Render::DHTML -- Utility methods for gbrowse DHTML

=cut
