package MobyServices::b64_encoded_gif_renderer;
use strict;
our @ISA = qw(Exporter);
use File::Temp qw/ tempfile /;
our @EXPORT = qw(render type);
our @EXPORT_OK = qw(render type);
use MIME::Base64;

sub type {
    return "b64_encoded_gif";
}

sub render {
    my ($data, $htmldir,$imgdir) = @_;
    my $bindata = decode_base64($data);
    my ($fh, $filename) = tempfile( DIR => "$htmldir/$imgdir/", SUFFIX=> ".gif" );
    $filename =~ /(\w+\.jpg)$/;
    $filename = $1;
    binmode($fh);
    print $fh $bindata;
    close $fh;
    return "<img src='$imgdir/$filename'>";
}

1;



=head1 NAME

b64_encoded_gif_renderer.pm - a renderer (HTML) for b64_encoded_gif type MOBY Objects

=head1 AUTHOR

Please report all bugs to Mark Wilkinson (markw at illuminae.com)

=head1 SYNOPSIS

just put the renderer in your gbrowse.conf/MobyServices folder
and it will work.

=head1 DESCRIPTION

This renderer returns HTML that fits between the
<td>; tags in a web-page to display the content
of the b64_encoded_gif (or ontological child of) object.

The module has two methods:

=over

=item type

this returns a scalar indicating the MOBY Object Ontology
class that this renderer is designed to handle.  Objects
of this type, or objects that inherit from this type,
will be passed to this renderer.

=item render

This accepts the string representing the data contained in the
object and returns HTML that will represent that object
properly when put into a table-cell.

=back

=cut
