package MobyServices::text_xml_renderer;
use strict;
use XML::LibXML;
use MOBY::MobyXMLConstants;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(render type);

sub types {
    return ["text-xml"];
}

sub render {
    my ($DOM, $htmldir,$imgdir) = @_;
    my $content;
    $content = &getStringContent($DOM);
    $content =~ s/<!\[cdata\[/&lt;[CDATA[/ig;
    $content =~ s/<([^>]+)>/&lt;$1&gt;/g; # mask '>' and '<' in tags
    return ("<pre>$content</pre>");# the 0 indicates that we have only rendered the top-level XML of this object
}
sub getStringContent {
    my ($ROOT) = @_;
    my $content;
    my @childnodes = $ROOT->childNodes;
    foreach (@childnodes){
	next unless ($_->nodeType == ELEMENT_NODE);
	next unless ($_->localname eq "String");
	my $article = $_->getAttributeNode('articleName');
	$article = $_->getAttributeNode('moby:articleName') unless $article;
	next unless $article;
	next unless $article->getValue eq 'content'; # the articleName for String content of a text-xml node
	foreach my $subnode($_->childNodes){ # if it is correct, then get the text content
	    next unless  (($subnode->nodeType == TEXT_NODE) || ($subnode->nodeType == CDATA_SECTION_NODE));
	    $content .=$subnode->textContent;
	}
        $ROOT->removeChild($_);
	last;
    }
    return $content;
}

1;



=head1 NAME

text_xml_renderer.pm - a renderer (HTML) for text_xml type MOBY Objects

=head1 AUTHOR

Please report all bugs to Mark Wilkinson (markw at illuminae.com)

=head1 SYNOPSIS

just put the renderer in your gbrowse.conf/MobyServices folder
and it will work.

=head1 DESCRIPTION

This renderer returns HTML that fits between the
<td> tags in a web-page to display the content
of a text_xml (or ontological child of) object.

Without the renderer your browser will ignore the
tags which are not part of the HTML specification.
In consequence the xml document structure, element
names and attributes/values will be invisible in 
the result output - which is probably not what
you would expect...

=head1 METHODS

The module has two methods:

=over

=item type

this returns a scalar indicating the MOBY Object
Class that this renderer is designed to handle.  Objects
of this type, or objects that inherit from this type,
will be passed to this renderer.

=item render

This is called with three pieces of data which may or may not
be useful to your script:
    
=over

=item 1)  $data - an XML::LibXML object
representing the deserialized MOBY object


=item 2)  $htmldir - the full path to the directory serving your html

 e.g. /usr/local/apache/htdocs/
 
 (this is the HTDOCS parameter you specified
  when you installed Gbrowse)

=item 3)  $imgdir - the additional path information to a writable directory for images

 e.g. /gbrowse/tmp
 
 (this is the folder specified in the tmpimages parameter
  in your organism.conf file)


=back

=back

=head1 RETURNS

The subroutine should return two pieces of data:

=over

=item 1)  An HTML representation of the Object

 this will appear between <td></td> tags in the webpage

=item 2)  A boolean indicating whether the renderer has parsed all sub-objects, or just the top level object

 '1' indicates that the renderer has fully parsed the Object XML
 '0' indicates that you need Gbrowse to follow child objects
     and render them independently

=back

=cut
