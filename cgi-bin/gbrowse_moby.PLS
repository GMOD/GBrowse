#!perl
use Config;
use File::Basename qw(&basename &dirname);
use File::Spec;
use FindBin '$Bin';
use Cwd;
use MOBY::MobyXMLConstants;
my %OPTIONS;
if (open F,"$Bin/../GGB.def") {
  while (<F>) {
    next if /^\#/;
    chomp;
    $OPTIONS{$1} = $2 if /^(\w+)\s*=\s*(.+)/;
  }
  close F;
}
$OPTIONS{CONF} ||= '/usr/local/apache/conf';

my $dir = dirname($0);
$file   = shift || File::Spec->catfile($dir,basename($0, '.PL','.PLS'));

open OUT,">$file" or die "Can't create $file: $!";

print "Extracting $file (with variable substitutions)\n";

my $startperl = $Config{startperl} ne '#!perl' 
  ? $Config{startperl}
  : "#!$Config{perlpath}";

print OUT <<"!GROK!THIS!";
$startperl -w

###################################################################
# Non-modperl users should change this variable if needed to point
# to the directory in which the configuration files are stored.
#
\$CONF_DIR  = '$OPTIONS{CONF}/gbrowse.conf';
\$HTML_DIR  = '$OPTIONS{HTDOCS}';
use lib "$OPTIONS{CONF}/gbrowse.conf";
#
###################################################################
\$VERSION   = $OPTIONS{VERSION};

!GROK!THIS!

print OUT "use lib '$OPTIONS{LIB}';\n" if defined $OPTIONS{LIB};
print OUT <<'!NO!SUBS!';

#=======================================================================
#$Id: gbrowse_moby.PLS,v 1.36 2004-12-16 14:56:19 markwilkinson Exp $
###########################################################

use MOBY::Client::Central;
use MOBY::Client::Service;
use MOBY::CommonSubs qw(:all);
use XML::DOM;
use File::Temp qw/ tempfile /;
use MIME::Base64;
use LWP;
use Carp;
use Bio::Graphics::Browser::Util;
use CGI qw(:standard *table *TR);
use strict;
use vars qw($Central %RENDERERS $CONFIG $VERSION $CONF_DIR $HTML_DIR);

# get ready to use the renderers
opendir (DIR, "$CONF_DIR/MobyServices") || die "Can't open directory $CONF_DIR/MobyServices for directory parsing $!\n";
my @files = readdir DIR;

foreach my $file(@files){ 
    next if (-d $file);
    next unless ($file =~ /(.*_renderer)\.pm/);  # find all renderers in the config folder
    my $rendererclass = "MobyServices::$1";   # create the module name
    no strict 'refs';
    eval "require $rendererclass";          # load it
    my $type = &{$rendererclass."::type"};  # invoke the sub type {} routine to get the object type rendered
    $RENDERERS{$type} =   $rendererclass;  # assign this renderer by its object type
    use strict;
}


=head1 NAME

gbrowse_moby -- a Gbrowse accessory that enables browsing of MOBY data

=head1 AUTHOR

Please report all bugs to Mark Wilkinson (markw at illuminae.com)

=head1 SYNOPSIS

=head2 Standalone Installation

gbrowse_moby may be used "standalone" without a complete installation of
Gbrowse.  It relies on the gbrowse configuration file, which should be
in the folder $HTTPD_CONF/gbrowse.conf/ where $HTTPD_CONF is the
/conf/ directory for your webserver (e.g. /usr/local/apache/conf).  The
config filename must end in .conf (e.g. default.conf).  If you are
installing Gbrowse, all of this will be done for you by the gbrowse
installation script.

gbrowse_moby understands the following sub-set of gbrowse configuration
parameters, and you will want to edit the following lines in the
configuration file:

http_proxy = http://whatever.your.proxy/is    
stylesheet  = /gbrowse/moby.css
tmpimages   = /gbrowse/tmp
head = ... what goes between the HEAD HTML tags...
header = ...you header HTML here...
footer = ...you footer HTML here...

Other lines in the configuration file are ignored by the gbrowse_moby
script, though they may be required by gbrowse itself.

The renderers for MOBY Objects received from MOBY Services live in the
$HTTPD_CONF/gbrowse.conf/MobyServices folder.  These generally do not
need to be edited; please see the documentation of the individual
renderers for information on how to write your own.

Calling this script in your browser will open an initialization
screen allowing you to initiate a MOBY browsing session independent
of any parameters from Gbrowse.  See also the USAGE section
for information about calling this browser with a GET string containing
initialization parameters.


=head2 Installation as a Gbrowse Accessory

In 0X.organism.conf:
     
 [ORIGIN]
 link         = http://yoursite.com/cgi-bin/gbrowse_moby?source=$source&name=$name&class=$class&method=$method&ref=$ref&description=$description
 feature      = origin:Genbank
 glyph        = anchored_arrow
 fgcolor      = orange
 font2color   = red
 linewidth    = 2
 height       = 10
 description  = 1
 key          = Definition line
 link_target  = _MOBY


AND/OR


 [db_xref:DETAILS]
 URL = http://yoursite.com/cgi-bin/gbrowse_moby?namespace=$tag;id=$value


=head1 REQUIRED LIBRARIES

This script requires libraries from the BioMOBY project.  Currently
these are only available from the CVS.  Anonymous checkout of the
BioMOBY project can be accomplished as follows:
    
cvs -d :pserver:cvs@cvs.open-bio.org:/home/repository/moby login
cvs -d :pserver:cvs@cvs.open-bio.org:/home/repository/moby co moby-live
cvs update -dP

You will then either need to enter the moby-live/Perl folder and run 
the Makefile and install the MOBY libraries into your system, or 
alternately you can add "use lib './moby-live/Perl'" to this script 
such that the libraries can be found at run-time.


=head1 DESCRIPTION (using gbrowse_moby as a Gbrowse accessory)

This script will take information passed from a click on
a Gbrowse feature, or a click on a configured DETAILS GFF
attribute type, and initiate a MOBY browsing session with
information from that link.  Most information is discarded.
The only useful information to MOBY is a "namespace" and an
id number within that namespace.

Generally speaking, namespaces in Gbrowse will have to be
mapped to a namespace in the MOBY namespace ontology (which
is derived from the Gene Ontology Database Cross-Reference
Abbreviations list).  Currently, this requires editing of the
gbrowse_moby code, where a hash named source2namespace will
map the GFF source (column 2) value into a MOBY namespace


=head1 USAGE

gbrowse_moby understands the following variables passed by GET:

 source      - converted into a MOBY namespace by parsing the
               'source' GFF tag against the %source2namespace hash
               (see more detailed explanation in the examples below)
 namespace   - used verbatim as a valid MOBY namespace
 name        - used verbatim as a MOBY id interpreted in the namespace
 id          - used verbatim as a MOBY id interpreted in the namespace
 class       - this is the GFF column 9 class; used for the page title
 objectclass - this should be a MOBY Class ontology term
               (becomes 'Object' by default)
 object      - contains the XML of a valid MOBY object
 
to auto-execute a MOBY service on the supplied namespace/id/object you
may use the following GET parameters:
 
 servicename - the service name of the desired MOBY Service (must be
               accompanied by 'authority' parameter, below)
 authority   - the authority of the desired MOBY Service (must be
               accompanied by 'servicenmae' parameter, above)


Note that you MUST at least pass a namespace-type variable (source/namespace)
and an id-type variable (name/id) in order to have a successful MOBY
call.

=head1 EXAMPLES

=head2 Simple GFF

If your GFF were:

      A22344  Genbank  origin  1000  2000  87  +  .
 
You would set your configuration file as follows:
 
     [ORIGIN]
     link         = http://yoursite.com/cgi-bin/gbrowse_moby?source=$source&name=$name&class=$class
     feature      = origin:Genbank

and you would edit the gbrowse_moby script as follows:

      my %source2namespace = (
         #   GFF-source           MOBY-namespace
            'Genbank'       =>      'NCBI_Acc',
      );

this maps the GFF source tag "Genbank" to the MOBY namespace "NCBI_Acc"

=cut

=head2 GFF With non-MOBY Attributes

If your GFF were:

      A22344  Genbank origin  1000  2000 87 + . Locus CDC23

You would set your configuration file as follows:
 
     [ORIGIN]
     link         = http://yoursite.com/cgi-bin/gbrowse_moby?source=$source&name=$name&class=$class
     feature      = origin:Genbank

and you might also set a DETAILS call to handle the Locus Xref:
(notice that we use the 'source' tag to force a translation of
the foreign namespace into a MOBY namespace)

     [db_xref:DETAILS]
     URL = http://brie4.cshl.org:9320/cgi-bin/gbrowse_moby?source=$tag;id=$value

then to handle the mapping of Locus to YDB_Locus as well
as the Genbank GFF source tag you would
edit the source2namespace hash in gbrowse_moby to read:

      my %source2namespace = (
         #   GFF-source           MOBY-namespace
            'Genbank'       =>      'NCBI_Acc',
            'Locus'         =>      'YDB_Locus',
      );

=cut

=head2 GFF With MOBY Attributes

If your GFF were (NCBI_gi is a valid MOBY namespace):

      A22344  Genbank origin  1000  2000 87 + . NCBI_gi 118746

You would set your configuration file as follows:
 
     [ORIGIN]
     link         = http://yoursite.com/cgi-bin/gbrowse_moby?source=$source&name=$name&class=$class
     feature      = origin:Genbank

and you might also set a DETAILS call to handle the NCBI_gi Xref:
(notice that we now use the 'namespace' tag to indicate that
the tag is already a valid MOBY namespace)

     [db_xref:DETAILS]
     URL = http://brie4.cshl.org:9320/cgi-bin/gbrowse_moby?namespace=$tag;id=$value

Since there is no need to map the namespace portion, we now
only need to handle the Genbank GFF source as before:

      my %source2namespace = (
         #   GFF-source           MOBY-namespace
            'Genbank'       =>      'NCBI_Acc',
      );

=head1 HINTS

-The full listing of valid MOBY namespaces is available at:
    http://mobycentral.cbr.nrc.ca/cgi-bin/types/Namespaces

-A useful mapping to make is to put the organism name into the
Global_Keyword namespace.  This will trigger discovery of MedLine
searches for papers about that organism.



=cut


my $conf_dir  = conf_dir($CONF_DIR);  # conf_dir() is exported from Util.pm
$CONFIG = open_config($CONF_DIR);  # open_config() is exported from Util.pm

our %source2namespace = (
#   GFF-source      MOBY-namespace
    'Genbank'       =>      'NCBI_Acc',

                    );

param('action')?&execute:&init;


sub init {
    # Gbrowse    MOBY
    # source   = namespace
    # name     = id
    my $class = param('class');  # this is a Gbrowse variable, (the GFF column 9 class)
    $class ||=param('namespace');  # for MOBY calls, we will need to use the namespace rather than the GFF class
    $class ||=param('source');  # failsafe
    
    my $namespace = param('source');  # this is a Gbrowse variable (GFF Column 2)
    $namespace ||= param('namespace');  # if this is a MOBY call, the $source variable will still be undef, so take the namespace as the "source"

    my $id = param('name');  # name is a Gbrowse variable    
    $id ||= param('id'); # for MOBY calls we call it "id" not "name", but they are ~the same thing

    unless (defined($namespace) && defined($id)){
        print_top("MOBY-S Client Initialization");
        print $CONFIG->header || h1("MOBY-S Client Initialization");
        print h1("Initialization Required");
        print h2("This browsing session must be primed with a Namespace and ID:");
        &INITIALIZE;
        print $CONFIG->footer;
        return;
    }

    my $authority = param('authority');
    my $servicename = param('servicename');

    if ($authority && $servicename){
      &execute();
      return;
    }
    
    my $keyword = param('keyword');
    my $output = param('output');
    my $serviceType = param('serviceType');
    my $expandObjects = param('expandObjects');
    
    $Central = MOBY::Client::Central->new();  # CENTRAL is a global variable

    my $objectclass =param('objectclass');  # for MOBY calls we may have a data class (e.g. VirtualSequence)
    $objectclass ||="Object";  # by default, the base object class is "Object"
    my $XML_Object = param('object');  # a recursive MOBY call may pass the current MOBY Object (XML) as a hidden field
    
    print_top("BioMOBY Details: $objectclass - $class:$id");
    print $CONFIG->header || h1("$objectclass - $class:$id Details");
    print p;
    
    # okay, prepare the list of list's input structure for the MOBY::Central->findService call
    my @namespace;
    if (param('namespace')){  # if this is already a MOBY call (i.e. we are calling it 'namespace')
        push @namespace, $namespace;  # then use it as-is
    } else {  # otherwise we are using the namespace of Gbrowse, which is not consistent with the MOBY namespace ontology
        push @namespace, $source2namespace{$namespace};  # so do a translation from Gbrowse -> MOBY namespace
    }

    Delete_all();  # reset all CGI parameters
    my @Services = &findService($objectclass, \@namespace, $keyword, $authority, $output, $serviceType, $expandObjects);
    return unless scalar(@Services);

    print start_table();
    foreach my $SERVICE(@Services){
        
            my $form= join "", (start_form(-action => url(-full)),
            hidden('namespace',$namespace[0]),
            hidden('id',$id),
            hidden('servicename',$SERVICE->name),
            hidden('authority',$SERVICE->authority),
            hidden('object', $XML_Object),
            hidden('action',"execute"),
            submit("Execute This Service"),
            end_form());
            my $email = $SERVICE->contactEmail;
            my @outtypes;
            my $collection = 0;
            if ($SERVICE->output->[0]->isCollection){
                $collection = 1;
                my $simples = $SERVICE->output->[0]->Simples;
                foreach (@{$simples}){
                    #print STDERR "\n\nfound simple article\n\n";
                    my $ob = $_->objectType;
                    $ob =~ s/.*\:(\S+)/$1/;
                    my $link = getObjectDescription($ob);
                    push @outtypes, $link;
                }
            } else {
                my $ob = $SERVICE->output->[0]->objectType;
                $ob =~ s/.*\:(\S+)/$1/;
                my $link = getObjectDescription($ob);
                push @outtypes, $link;
            }
            print TR({-valign=>'top', -class=>'databody'},
            th({-align => 'left', -valign=>'top', -class=>'datatitle'},"Service Name: "),
            td($SERVICE->name, "provided by: ".($SERVICE->authority)," (<a href='mailto:$email'>contact</a>)")),

            TR({-valign=>'top', -class=>'databody'},
            th({-align => 'left', -valign=>'top', -class=>'datatitle'},"Service Type: "),
            td(b($SERVICE->type))),
               
            TR({-valign=>'top', -class=>'databody'},
            th({-align => 'left', -valign=>'top', -class=>'datatitle'},"Provides: "),
            td(b($collection?"Collection of ":"", (join ",", @outtypes)))),
            
            TR({-valign=>'top', -class=>'databody'},
            th({-align => 'left', -valign=>'top', -class=>'datatitle'},"Description: "),
            td(b(i($SERVICE->description)))),

            TR({-valign=>'top', -class=>'databody'},
            th({-align => 'left', -valign=>'top', -class=>'datatitle'},"Execute: "),
            td($form)),

            TR({-valign=>'top', -class=>'databody'},
            th({-colspan=>3,-align => 'left', -valign=>'top', -class=>'datatitle'},"")),
    }
    print end_table();
    print_bottom($CONFIG,"BioMOBY project:  http://www.biomoby.org");
}

sub getObjectDescription {
    my $ob = shift;
    return unless $ob;
    my $proxy = $CONFIG->setting('http_proxy');
    my $ua = LWP::UserAgent->new;
    $proxy && $ua->proxy(['http'],$proxy);
    
    my $req = HTTP::Request->new(GET => "http://mobycentral.cbr.nrc.ca/cgi-bin/types/Objects?lsid_name=$ob");
    
    my $res = $ua->request($req);
    return unless $res->is_success;
    my $content = $res->content;
    return unless $content =~ /\S+\t\S+\t\S+\t(.*)/;
    $content = $1;
    $content =~ s/\'//g;
    $content =~ s/\"//g;
    return "<a href='http://mobycentral.cbr.nrc.ca/cgi-bin/types/Objects?lsid_name=$ob' alt='$content' title='$content'/>$ob</a>";
}

sub findService {
    my ($class, $namespace, $keyword, $authority, $output, $serviceType, $expandObjects) = @_;  # class is scalar, $namespace is listref    

    # put together a simple article query
    my @simpleArticle = ($class, $namespace);
    my @input = (\@simpleArticle);

    my @outputs = split ",", $output;
    my @output;
    if (scalar(@outputs) > 1){
        @output = [[@outputs],undef];
    } else {
        @output = [(shift @outputs), undef];
    }

    my %args;
    $args{input} = \@input;
    $output && ($args{output} = \@output);
    $args{expandObjects} = 0;
    $expandObjects && ($args{expandObjects} = 1);
    $args{expandServices} = 1;
    $authority && ($args{authURI} = $authority);
    $serviceType && ($args{serviceType} = $serviceType);
    $keyword && ($args{keywords} = [split ",", $keyword]);
    
    print STDERR keys %args,"\n";
    my ($Services, $REG) = $Central->findService(%args);
    unless ($Services){
            print h2("Service discovery failed with the following errror: ").i($REG->message).p;
            return
    }
    unless (scalar @{$Services}){
            print h2("No BioMOBY Services were discovered that could operate on $class data ", @$namespace[0]?"in the @$namespace[0] namespace.  Try switching 'Decompose Objects' on...":"").p;
            return
    }
    return @$Services
}

sub execute {
    
    my $namespace = param('namespace');
    my $id = param('id');
    my $service = param('servicename');
    my $auth = param('authority');
    my $OBJECT = param('object');  # this is XML
    $OBJECT ||= "<Object namespace='$namespace' id='$id'/>";  # this should never happen, but just in case... make a default base object

    print_top("BioMOBY Details: $namespace:$id");
    print $CONFIG->header || h1("$namespace:$id Details");
    print p;
    
    $Central = MOBY::Client::Central->new();
    my ($SI, $reg) = $Central->findService(authURI => $auth,
                       serviceName => $service);
    $SI = $$SI[0]; # there can only be one, since authURI/serviceName is a unique index

    my $WSDL = $Central->retrieveService($SI); # get the WSDL
    my $SERVICE = MOBY::Client::Service->new(service => $WSDL);  # prepare the connection stubs
    
    print h2("\nBioMOBY Service: ".($SI->name)),i($SI->description),hr,h2("\nResult for $namespace:$id\n");
    my $result = $SERVICE->execute(XMLinputlist => [['', $OBJECT]]); # execute the service with the given input data; this *assumes* that the arguments are not named!!!

    unless ($result){
        print h3("Service returned no response");
        exit 0;
    }
    my ($collections, $objects) = extractResponseArticles($result);
    unless (scalar @$objects || scalar @$collections){
        print h3("Service Response contained no data.  Message body contained the following: \n<br><pre>".(escapeHTML($result))."</pre>\n");
        exit 0;
    }
    my $service_notes = getServiceNotes($result);

    if ($service_notes){
        print start_table,
        TR({-valign=>'top', -class=>'databody'},
        th({-align => 'left', -valign=>'top', -class=>'datatitle'},"Notes from Service Provider:"),
        td($service_notes));
        print end_table;
    }

    Delete_all();  # reset all CGI parameters so we don't conflict
    print start_table;
    my @colls = @{$collections};  # flatten the list of lists
    foreach my $objlist($objects, @colls){  # we just treat collections as simples here.
        foreach (@{$objlist}){
            my $MOBYClass = $_->nodeName;
            my $namespace = $_->getAttributeNode('namespace');
            $namespace = $namespace?($namespace->getValue):"";
            my $short_namespace = $namespace =~ /urn:lsid:biomoby.org:namespacetype:(\S+)/?$1:$namespace; # namespaces may or may not be fully qualified LSID's.  if they are, and if they are MOBY ID's, then we can just take the last field, otherwise we should take the whole thing
            my $id = $_->getAttributeNode('id');
            $id = $id ?($id->getValue):"";
            print TR({-valign=>'top', -class=>'databody'},
                th({-align => 'left', -valign=>'top', -class=>'datatitle'},"ID: "),
                td(b($short_namespace.":".$id),
                   "  ",
                   start_form(-action => url(-full)),
                   hidden("object", $_->toString),
                   hidden("namespace", $namespace),
                   hidden("id",$id),
                   hidden("objectclass",$MOBYClass),
                   submit("Re-query MOBY with This Data"),
                   &setupFilters,
                   end_form                   
                   ));
            print TR({-valign=>'top', -class=>'databody'},
                th({-align => 'left', -valign=>'top', -class=>'datatitle'},"Data Type: "),
                td($MOBYClass));
                print "<!-- SCRAPE_ME_START -->";
            &printIt($_);
                print "<!-- SCRAPE_ME_END -->";
        }
    }
    print end_table;
    print_bottom("of the gbrowse_moby executable written by the <a href='http://www.biomoby.org'>BioMOBY project</a> (http://www.biomoby.org)");    
}

# the printIt subroutine will print the content of an object
# in a very particular way. It does the following:

sub printIt {
    my ($this) = @_;
    my $thisdatatype = $this->getTagName;
    my $imgdir = $CONFIG->setting('tmpimages');
    my $renderer;
    my @rtypes = keys %RENDERERS;
    # @rtypes are all of the object types that we have renderers for
    # $thisdatatype is the datatype that we have
    # whichDeepestParentObject subroutine (exported from CommonSubs.pm)
    # will compare the in-hand object with the list of renderable objects and
    # chose the parent object type of $thisdatatype that is closest
    # in our list of known object types.
    my ($renderer_term, $renderer_lsid) = &whichDeepestParentObject($Central, $thisdatatype, \@rtypes); 
    $renderer_term ||='text-formatted';
    $renderer = $RENDERERS{$renderer_term};

    die "Can't render this information\n" unless $renderer;
    
    # first parse the object to get all of the CrossReference objects out of it.
    foreach my $subnode($this->getChildNodes){
        next unless ($subnode->getNodeType == ELEMENT_NODE);
        if (($subnode->getTagName =~ /(moby:)?CrossReference/) || ($subnode->getTagName =~ /(moby:)?Xref/)){  # if it is one of the two types of Xrefs, then pass it to the Xref parser
            &processXrefs($subnode);
            last;
        }
    }

    my $done=0;  # this is a boolean that indicates whether the renderer handles ALL sub-objects, or if it handles only the top-level content of an object and requires that the sub-nodes (objects) be parsed and rendered
    my $article = $this->getAttributeNode('articleName');  # get the article name
    $article = $article?($article->getValue):"";
    no strict 'refs';
    my $content;
    ($content, $done) = &{$renderer."::render"}($this, $HTML_DIR, $imgdir);  # if the renderer handles everything, then $done is set and we can stop parsing this object
    use strict;
    if ($article || ($content =~ /\S/)){ # if we have an articlename or any textual content then we want to print this information no matter what came back from the renderer
        print TR({-valign=>'top', -class=>'databody'}, # print the HTML content that you got back from the renderer
            th({-align => 'left', -valign=>'top', -class=>'datatitle'},"$article "),
            td("$content"));
    }  # if we have no article name or no textual content, then this is almost certainly a blank node, and we can ignore it
    
    return if $done;  # if the renderer said that it handled the entire object, then quit

    foreach my $subnode($this->getChildNodes){  # otherwise, we need to now start unpacking the object and rendering its subcomponents
        next unless ($subnode->getNodeType == ELEMENT_NODE);
        next if ($subnode->getTagName eq "CrossReference"); 
        &printIt($subnode);
    }
}

sub processXrefs {
    my ($XrefBlock) = @_;
    foreach my $xref ($XrefBlock->childNodes()){
        next unless $xref->nodeType == ELEMENT_NODE;
        my $ns = $xref->getAttributeNode("namespace");
        next unless $ns;
        $ns = $ns->getValue();
        next unless $ns;
        my $id = $xref->getAttributeNode("id");
        next unless $id;
        $id = $id->getValue();        
        next unless $id;
        my $CGI = CGI->new();
        $CGI->delete_all;
        print TR({-valign=>'top', -class=>'databody'},
            th({-align => 'left', -valign=>'top', -class=>'datatitle'},"CrossReference "),
            td("<a href=".($CGI->url)."?namespace=$ns&id=$id>$ns:$id</a>"));        
    }
}

sub setupFilters {
#<SPAN title=" description here " class="popup">text</SPAN>
    return "<table border=1><tr><td>",checkbox_group(-name => 'expandObjects', -values => ['?'], -checked=>"ON"),
    "  <SPAN title=' When this box is checked, your input object will be decomposed into its ISA parentage and services that operate on any parent class will also be discovered. ' class='popup' cursor='help'>Decompose Objects?</span> ",
    "<td>","  <SPAN title=' Enter a comma-delimited list of keywords that should appear in the service description. ' class='popup' cursor='help'>Keywords:</span> ", textfield(-name => 'keyword', -size => 20),"</td>",
    "<td>","  <SPAN title=' Enter the full URI for the authority (service provider) that you want to restrict your search to.  e.g. sgn.cornell.edu ' class='popup' cursor='help'>Authority:</span> ",textfield(-name => 'authURI', -size => 20),"</td>",
    "<td>","  <SPAN title=' Enter a valid term from the Service Type Ontology. ' class='popup' cursor='help'>Service Type:</span> ", textfield(-name => "serviceType", -size => 10),"</td>",
    "<td>","  <SPAN title=' Your search will be restricted to only those services that output this Object.  The ontology is NOT traversed. ' class='popup' cursor='help'>Output Object:</span> ", textfield(-name => "output", -size => 10),"</td>",
    "</tr></table>"

}

sub INITIALIZE {	
    my $Central = MOBY::Client::Central->new();
    my $NameSpaces = $Central->retrieveNamespaces;
    my @Namespaces = sort keys(%{$NameSpaces});
    print start_form(-action => url(-full)),
    "<table border=1><tr><td>",
    "<h2>Select a namespace: </h2>",
    "</td>",
    "<td>";
    print popup_menu(-name => 'namespace',
        '-values' => ["select", @Namespaces],
        '-default' => 'NCBI_gi',
    );
    print "</td></tr>";

    print "<tr>",
    "<td>",
    "<h2>Which ID within this namespace?: </h2>",   
    "</td><td>",textfield(-name => 'id',-width=>'15', -value => "431260",),
    "</td></tr>",
    "</table>";
    print "</h2>",p, &setupFilters,p,
    submit("Initialize with this seed data"),
    end_form;

}


#=================================================



!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
