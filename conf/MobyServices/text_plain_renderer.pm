package MobyServices::text_plain_renderer;
use strict;
our @ISA = qw(Exporter);
#our @EXPORT = qw(render type);
our @EXPORT_OK = qw(render type);


sub type {
    return "text-plain";
}

sub render {
    my ($data, $htmldir,$imgdir) = @_;
    return "$data";
}

1;



=head1 NAME

text_plain_renderer.pm - a renderer (HTML) for text-plain type MOBY Objects

=head1 AUTHOR

Please report all bugs to Mark Wilkinson (markw at illuminae.com)

=head1 SYNOPSIS

just put the renderer in your gbrowse.conf/MobyServices folder
and it will work.

=head1 DESCRIPTION

This renderer returns HTML that fits between the
<td>; tags in a web-page to display the content
of the text-plain (or ontological child of) object.

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
