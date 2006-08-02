#!perl
use Config;
use File::Basename qw(&basename &dirname);
use File::Spec;
use FindBin '$Bin';
use Cwd;
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
#$Id: gbrowse_moby.PLS,v 1.52 2006-08-02 21:58:34 markwilkinson Exp $
###########################################################

#use SOAP::Lite +trace;
use MOBY::Client::Central;
use MOBY::Client::Service;
use MOBY::CommonSubs qw(:all);
use MOBY::MobyXMLConstants;
use File::Temp qw/ tempfile /;
use MIME::Base64;
use LWP;
use Carp;
use XML::LibXML;
use Bio::Graphics::Browser::Util;
use CGI qw(:standard *table *TR);
use LS::ID;
use LS::Locator;
#use Compress::LZW;

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
    my $types = &{$rendererclass."::types"};  # invoke the sub type {} routine to get the object type rendered
    foreach (@$types){
        $RENDERERS{$_} =   $rendererclass;  # assign this renderer by its object type
    }
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
    http://mobycentral.icapture.ubc.ca/cgi-bin/types/Namespaces

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

if (param('getscufl')){&retrieveSCUFL(); exit 0}  # calls to retrieve scufl simply retrieve scufl and stop

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

    unless (defined($namespace) && defined($id)){ &firstTimeInit(); exit 1;}   # this is a real first-time initlialization

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
    my $oldPortName = param('portname');
    my $scufl = param('scufl');
    my $sid = param('sid');   # unique service id iterator - every service has to be suffixed with a unique id because it may be re-used in the workflow, causing it to be circular rather than linear
    
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
            hidden('sid',$sid),
            hidden('servicename',$SERVICE->name),
            hidden('authority',$SERVICE->authority),
            hidden('object', $XML_Object),
            hidden('scufl', $scufl),
            hidden('portname', $oldPortName),
            hidden('action',"execute"),
            submit("Execute This Service"),
            end_form());
            my $email = $SERVICE->contactEmail;
            my @outtypes;
            my $collection = 0;
            if ($SERVICE->output->[0]  && $SERVICE->output->[0]->isCollection){
                $collection = 1;
                my $simples = $SERVICE->output->[0]->Simples;
                foreach (@{$simples}){
                    my $ob = $_->objectType;
                    $ob =~ s/.*\:(\S+)/$1/;
                    my $link = getObjectDescription($ob);
                    push @outtypes, $link;
                }
            } elsif ($SERVICE->output->[0]) {
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

sub firstTimeInit {
        print_top("MOBY-S Client Initialization");
        print $CONFIG->header || h1("MOBY-S Client Initialization");
        print h1("Initialization Required");
        print h2("This browsing session must be primed with a Namespace and ID:");
        &INITIALIZE;
	print h2("Instructions");
	print "
This browser utilizes BioMoby as a data-driven Web Service discovery system - it discovers bioinformatics resources that can consume whatever data-type is currently displayed in your browser window.  
To begin your browsing session you must provide a starting point for your exploration in the form of a <b>Namespace</b> <i>(the common abbreviation for a particular category of identifiers)</i>, and an <b>ID</b> <i>(the identifier itself)</i>.  
For example, the Genbank record for the <i>Arabidopsis</i> ubiquitin conjugating enzyme (gi|431260) is in the Namespace NCBI_gi with the ID 431260.  After selecting the Namespace and ID that you are interested in, click the 
<b>Initialize</b> button below to begin searching for appropriate bioinformatics services.  An example Namespace and ID have been selected for you already if you want to start exploring quickly!";
	print "<br><br>After initialization, you will be presented with a selection of services that consume the data-type you initialized.  The services description includes the <b>Service Name</b>, the Web domain of the 
service provider, the <b>Service Type</b> (the function that the Service will execute on your data, e.g. 'Retrieval' or 'Blast'), the type of output data that the Service </b>Provides</b>, and a textual description of the Service 
as provided by the author of that Service.  Once you find the one you need, click the <b>Execute This Service</b> button.  Your results (one or more, depending on what the Service does) will be displayed.  For each result, you 
will have the opportunity to re-initialize the system using that piece of data, in order to discover BioMoby services that operate on it.  This discover/execute cycle continues until you decide to quit.<br><br>Have fun swimming 
in the BioMoby ocean!";
        print $CONFIG->footer;
        return;
}

sub getObjectDescription {
    my $ob = shift;
    return unless $ob;
    if ($ob eq 'Object') {
	return "<a href='http://mobycentral.icapture.ubc.ca/types/Objects?lsid=$ob' alt='The base BioMoby Object' title='The base BioMoby Object'/>$ob</a>";
    }
    my $proxy = $CONFIG->setting('http_proxy');
    my $ua = LWP::UserAgent->new;
    $proxy && $ua->proxy(['http'],$proxy);
    
    my $req = HTTP::Request->new(GET => "http://mobycentral.icapture.ubc.ca/types/Objects?lsid=$ob");
    
    my $res = $ua->request($req);
    return unless $res->is_success;
    my $content = $res->content;
    return unless $content =~ /\S+\t\S+\t\S+\t(.*)/;
    $content = $1;
    $content =~ s/\'//g;
    $content =~ s/\"//g;
    return "<a href='http://mobycentral.icapture.ubc.ca/types/Objects?lsid=$ob' alt='$content' title='$content'/>$ob</a>";
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
    $authority = "" if $authority eq "select";
    $authority && ($args{authURI} = $authority);
    $serviceType && ($args{serviceType} = $serviceType);
    $keyword && ($args{keywords} = [split ",", $keyword]);
    my ($Services, $REG) = $Central->findService(%args);
    unless ($Services){
            print h2("Service discovery failed with the following errror: ").i($REG->message).p;
            return
    }
    unless (scalar @{$Services}){
            print h2("No BioMOBY Services were discovered ", $authority?"from $authority ":"", " that could operate on $class data ", @$namespace[0]?"in the @$namespace[0] namespace.  Try enabling Semantics if you have not already":"  Try enabling Semantics if you have not already").p;
            return
    }
    my @goodServices;
    while (my $serv = shift @$Services){
        my @inputs = @{$serv->input};
        my $bad = 0;
        map {++$bad if ($_->isCollection)} @inputs;  # weed out collectioninputs because gbrowse_moby cannot create collection inputs
        next if $bad;
        map {++$bad if ($_->isSimple)} @inputs;  # weed out collectioninputs because gbrowse_moby cannot create collection inputs
        next if $bad > 1;
        
	my $ls = $serv->LSID;  # get the LSID of the service instance
	my $lsid = LS::ID->new($ls);
        my $locator = LS::Locator->new if $ls;
        my $authority = $locator->resolveAuthority($lsid) if $locator;
        my $resource = $authority->getResource($lsid) if $authority;
        my $data = $resource->getMetadata if $resource;
	my $filehandle =  $data->response if $data;
	my $content = join "", (<$filehandle>);
	if ($content =~ /isAlive(.*?)isAlive/s){
		my $alive = $1;
		next unless ($alive =~ /true/i);
	}
	push @goodServices, $serv;
     }
    unless (scalar @goodServices){
            print h2("No BioMOBY Services were discovered ", $authority?"from $authority ":"", " that could operate on $class data ", @$namespace[0]?"in the @$namespace[0] namespace.  Try enabling Semantics if you have not already":"  Try enabling Semantics if you have not already").p;
            return
    }
    my @sorted = sort {$a->authority cmp $b->authority} @goodServices;
     return @sorted;
}


sub execute {
    
    my $namespace = param('namespace');
    my $id = param('id');
    my $service = param('servicename');
    my $auth = param('authority');
    my $sid = generateUniqueServiceID();
    my $OBJECT = param('object');  # this is XML
    my $oldOutputPortName = param('portname');  # the port of the last service executed - needed for SCUFL connection
    $OBJECT ||= "<Object namespace='$namespace' id='$id'/>";  # this should never happen, but just in case... make a default base object

    print_top("BioMOBY Details: $namespace:$id");
    print $CONFIG->header || h1("$namespace:$id Details");
    print p;
    
    $Central = MOBY::Client::Central->new();
    my @providers = $Central->retrieveServiceProviders;  # this will be passed to the form generator later
    my ($SI, $reg) = $Central->findService(authURI => $auth,
                       serviceName => $service);
    $SI = $$SI[0]; # there can only be one, since authURI/serviceName is a unique index
    my $provider = $SI->contactEmail;

    my $inputs = $SI->input;
    my $outputs = $SI->output;
    my ($articleName, $outputArticleName, $outputObjectType, $isCollection);

    # this code assumes only one input as a primary
    foreach my $input(@$inputs){
	next unless $input->isSimple;
	$articleName = $input->articleName;
	last;
    }		    

    foreach my $output(@$outputs){
	next unless ($output->isSimple || $output->isCollection);
	$outputArticleName = $output->articleName;
        ($isCollection = 1) if $output->isCollection;
	if ($isCollection){($output) = @{$output->Simples}} # just take the first one since we can't deal with collections of different types of simples
        $outputObjectType = $output->objectType;  # only simples have objectTypes, so we have to do this after extracting the simple from the collection
	last;
    }

    my $newOutputPortName;  # need to know the name of the output port for the current service to send to the getSCUFL Button routine so that it can append an output sink if necessary
    if ($isCollection){
	$newOutputPortName = "$service"."__$sid:$outputObjectType(Collection - '$outputArticleName' As Simples)";  # SCUFL needs this to connect ports together.  This is a record of the last 
    } else {
	$newOutputPortName = "$service"."__$sid:$outputObjectType($outputArticleName)";  # SCUFL needs this to connect ports together.  This is a record of the last 
    }
    my $scufl = &addSCUFLService($SI, $oldOutputPortName, $sid);    # append the selected service to the SCUFL document, connect old port name to the input of this new service


    my $WSDL = $Central->retrieveService($SI); # get the WSDL
    my $SERVICE = MOBY::Client::Service->new(service => $WSDL);  # prepare the connection stubs
    
    print h2("\nBioMOBY Service: ".($SI->name)),i($SI->description),hr,h2("\nResult for $namespace:$id\n");
    my $result;

    eval {$result = $SERVICE->execute(XMLinputlist => [["$articleName", $OBJECT]]);};
    unless ($result){
        print h3("404 - Service returned no response.  This indicates that this service is currently unavailable.  Try again later.");
        exit 0;
    }
    my ($collections, $objects) = extractResponseArticles($result);

    unless (scalar @$objects || scalar @$collections){
	my $code;
	my $message;
	if ($result =~ /\<exceptionCode\>(\d+).*?\<exceptionMessage\>([^<]+)/){
		$code = $1; $message = $2;
	} else {
		$code = "200";
		$message = "UNKNOWN NAME";
	}
        print h3("ERROR $code"), "<br><br>The following information may assist you in determining the cause of the failure: $message<br><br>Please contact your service provider (<a href='mailto:$provider'>$provider</a>) for more 
assistance.  Error codes are derived from the Life Sciences Analysis Engine specification <a href='http://www.omg.org/cgi-bin/doc?dtc/2005-04-01'>http://www.omg.org/cgi-bin/doc?dtc/2005-04-01</a>.  This may assist you if you 
have further difficulties\n";
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
            my $MOBYClass = $_->tagName; #FIXME - this might be qualified
            if ($MOBYClass =~ /^(moby:)(.*)/) {
 	        $MOBYClass = $2;
            }
            my $namespace = $_->getAttributeNode('namespace');
            $namespace = $_->getAttributeNode('moby:namespace') unless $namespace; #FIXME - check for qualified value
            $namespace = $namespace?($namespace->getValue):"";
            my $short_namespace = $namespace =~ /urn:lsid:biomoby.org:namespacetype:(\S+)/?$1:$namespace; # namespaces may or may not be fully qualified LSID's.  if they are, and if they are MOBY ID's, then we can just take the last field, otherwise we should take the whole thing
            my $id = $_->getAttributeNode('id');
            $id = $_->getAttributeNode('moby:id') unless $id; #FIXME - check for qualified value
            $id = $id ?($id->getValue):"";
            print TR({-valign=>'top', -class=>'databody'},
                th({-align => 'left', -valign=>'top', -class=>'datatitle'},"ID: "),
                td(b($short_namespace.":".$id),
                   "  ",
                   start_form(-action => url(-full)),
                   hidden("object", $_->toString(2)), #FIXME - print pretty xml
                   hidden("namespace", $namespace),
                   hidden("scufl", $scufl),
                   hidden("id",$id),
                   hidden("sid",$sid),   # attach the next number
                   hidden("objectclass",$MOBYClass),
                   hidden("portname", $newOutputPortName),
                   submit("Re-Initialize MOBY Search with This Data"),
                   &setupFilters(providers => \@providers),
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

    &getSCUFLButton($scufl, $newOutputPortName);  # note that this routine collects the new port name, so if you move this button be sure that the NEW port name is available!

    print_bottom("of the gbrowse_moby executable written by the <a href='http://www.biomoby.org'>BioMOBY project</a> (http://www.biomoby.org)");    
}


sub printIt {
    my ($this) = @_;
    my $thisdatatype = $this->tagName; #FIXME - this could be qualified
    if ($thisdatatype =~ /^(moby:)(.*)/) {
	$thisdatatype = $2;
    }
    my $imgdir = $CONFIG->setting('tmpimages');
    my $renderer;
    my @rtypes = keys %RENDERERS;
    # @rtypes are all of the object types that we have renderers for
    # $thisdatatype is the datatype that we have
    # whichDeepestParentObject subroutine (exported from CommonSubs.pm)
    # will compare the in-hand object with the list of renderable objects and
    # chose the parent object type of $thisdatatype that is closest
    # in our list of known object types.
    my ($renderer_term, $renderer_lsid) = ("","");
    ($renderer_term, $renderer_lsid) = &whichDeepestParentObject($Central, $thisdatatype, \@rtypes); 
    $renderer_term ||='text-formatted';
    $renderer = $RENDERERS{$renderer_term};


    die "Can't render this information\n" unless $renderer;
    
    # first parse the object to get all of the CrossReference objects out of it.
    foreach my $subnode($this->getChildNodes){
        next unless ($subnode->nodeType == ELEMENT_NODE);
        if (($subnode->tagName =~ /(moby:)?CrossReference/) || ($subnode->tagName =~ /(moby:)?Xref/)){  # if it is one of the two types of Xrefs, then pass it to the Xref parser
            &processXrefs($subnode);
            last;
        }
    }

    my $done=0;  # this is a boolean that indicates whether the renderer handles ALL sub-objects, or if it handles only the top-level content of an object and requires that the sub-nodes (objects) be parsed and rendered
    my $article = $this->getAttributeNode('articleName');  # get the article name
    $article = $this->getAttributeNode('moby:articleName') unless $article;  # get the article name
    $article = $article?($article->getValue):"";
    no strict 'refs';
    my $content;
    # pass by ref so that we can delete nodes that we don't need
    # and what's left will be re-passd to this routine to try rendering it again.
    my ($HTMLcontent) = &{$renderer."::render"}($this, $HTML_DIR, $imgdir);  # renderer renders what it can, deletes those DOM nodes from the $this reference, and passes back HTML of what it could render
    use strict;
    if ($article || ($HTMLcontent =~ /\S/)){ # if we have an articlename or any textual content then we want to print this information no matter what came back from the renderer
        print TR({-valign=>'top', -class=>'databody'}, # print the HTML content that you got back from the renderer
            th({-align => 'left', -valign=>'top', -class=>'datatitle'},"$article "),
            td("$HTMLcontent"));
    }  # if we have no article name or no textual content, then this is almost certainly a blank node, and we can ignore it
    
    #return if $done;  # if the renderer said that it handled the entire object, then quit

    foreach my $subnode($this->getChildNodes){  # otherwise, we need to now start unpacking the object and rendering its subcomponents
        next unless ($subnode->nodeType == ELEMENT_NODE);
        next if ($subnode->tagName eq "CrossReference" or $subnode->tagName eq "moby:CrossReference"); #FIXME check for qualified
        &printIt($subnode);
    }
    print "<tr><td colspan=2><hr width = 25%></td></tr>";

}

sub processXrefs {
    my ($XrefBlock) = @_;
    foreach my $xref ($XrefBlock->getChildNodes()){
        next unless $xref->nodeType == ELEMENT_NODE;
        my $ns = $xref->getAttributeNode("namespace");
		$ns = $xref->getAttributeNode("moby:namespace") unless $ns; #FIXME - check for qualified name
        next unless $ns;
        $ns = $ns->getValue();
        next unless $ns;
        my $id = $xref->getAttributeNode("id");
        $id = $xref->getAttributeNode("id") unless $id; #FIXME - check for qualified name
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
    my (%args) = @_;
    my @providers = @{$args{providers}};
    my $x = "<table border=1><tr><td>".(checkbox_group(-name => 'expandObjects', -values => ['?'], -checked=>"ON"));
    $x .= "<SPAN title=' When this box is checked, your input object will be decomposed into its ISA parentage and services that operate on any parent class will also be discovered. ' class='popup' cursor='help'>Semantics Enabled</span></td>";
    $x .= "<td><SPAN title=' Enter a comma-delimited list of keywords that should appear in the service description. ' class='popup' cursor='help'>Keywords:</span> ".( textfield(-name => 'keyword', -size => 15))."</td>";
    $x .= "<td><SPAN title=' Enter the full URI for the authority (service provider) that you want to restrict your search to.  e.g. sgn.cornell.edu ' class='popup' cursor='help'>Authority:</span> ";
    $x .= popup_menu(-name => 'authority',
        '-values' => ["select", sort(@providers)],
        '-default' => '',
        '-width' => 18,
    );
    $x .= "</td>";
    $x .= "<td><SPAN title=' Enter a valid term from the Service Type Ontology. ' class='popup' cursor='help'>Service Type:</span> ".(textfield(-name => "serviceType", -size => 10))."</td>";
    $x .= "<td><SPAN title=' Your search will be restricted to only those services that output this Object.  The ontology is NOT traversed. ' class='popup' cursor='help'>Desired Output:</span> ".(textfield(-name => "output", -size => 10))."</td>";
    $x .= "</tr></table>";
    return $x;

}

sub INITIALIZE {	
    my $Central = MOBY::Client::Central->new();
    my $NameSpaces = $Central->retrieveNamespaces;
    my @Namespaces = sort keys(%{$NameSpaces});
    my @providers = $Central->retrieveServiceProviders;
    print start_form(-action => url(-full)),
    "<table border=1><tr><td>",
    "<h2>Select a <SPAN title=' Namespaces are, usually, the abbreviation for a particular database, e.g. PDB is the abbreviation for the Protein Data Bank ' class='popup' cursor='help'>Namespace</span>: </h2>",
    "</td>",
    "<td>";
    print popup_menu(-name => 'namespace',
        '-values' => ["select", @Namespaces],
        '-default' => 'NCBI_gi',
    );
    print "</td></tr>";

    print "<tr>",
    "<td>",
    "<h2>Which <SPAN title=' The ID is the identifier for a particular piece of data within the namespace above.  For example, the Genbank record gi|163483 would have the ID 163483 ' class='popup' cursor='help'>ID</span> within this namespace?: </h2>",   
    "</td><td>",textfield(-name => 'id',-width=>'15', -value => "431260",),
    "</td></tr>",
    "</table>";
    print "</h2>",p, &setupFilters(providers => \@providers),p,
    submit("Initialize"),
    end_form;

}

sub addSCUFLService {
    my ($SI, $oldOutputPortName, $newsid) = @_;
    my $inputs = $SI->input;
    my ($articleName, $datatype);
    # this code assumes only one input as a primary
    foreach my $input(@$inputs){
	next unless $input->isSimple;
	$articleName = $input->articleName;
	$datatype = $input->objectType;
	last;
    }		    
    my $description =  $SI->description;  
    my $name  =$SI->name;
    my $authority  =$SI->authority;
    my $oldscufl = param('scufl');

    $oldscufl = &addSCUFLSource unless $oldscufl;  # if this is an initialization, then add the source namespace and id

    my $servicename = $name."__$newsid";  # this is the name of the service with its unique id attached
    $oldOutputPortName = "Object:mobyData" unless $oldOutputPortName;
    my $SCUFL = qq{

  <s:processor name="$servicename">
    <s:description><![CDATA[$description]]></s:description>
    <s:biomobywsdl>
      <s:mobyEndpoint>http://mobycentral.icapture.ubc.ca/cgi-bin/MOBY05/mobycentral.pl</s:mobyEndpoint>
      <s:serviceName>$name</s:serviceName>
      <s:authorityName>$authority</s:authorityName>
    </s:biomobywsdl>
  </s:processor>


  <s:link source="$oldOutputPortName" sink="$servicename:$datatype($articleName)" />

	};

	return $oldscufl.$SCUFL;

}

sub addSCUFLSource {

  my $namespace = param('namespace');
  my $id = param('id');

  my $source = qq{    
  <s:processor name="namespace" boring="true">
    <s:stringconstant>$namespace</s:stringconstant>
  </s:processor>
  <s:processor name="id" boring="true">
    <s:stringconstant>$id</s:stringconstant>
  </s:processor>

  <s:processor name="Object">
    <s:description>an identifier</s:description>
    <s:biomobyobject>
      <s:mobyEndpoint>http://mobycentral.icapture.ubc.ca/cgi-bin/MOBY05/mobycentral.pl</s:mobyEndpoint>
      <s:serviceName>Object</s:serviceName>
      <s:authorityName />
    </s:biomobyobject>
  </s:processor>

  <s:link source="namespace:value" sink="Object:namespace" />
  <s:link source="id:value" sink="Object:id" />

   };

   return $source;

}

sub retrieveSCUFL {

   my $scufl = param('scufl');
#   $scufl = decompress($scufl);
   my $head = qq{<?xml version="1.0" encoding="UTF-8"?>
                 <s:scufl xmlns:s="http://org.embl.ebi.escience/xscufl/0.1alpha" version="0.2" log="0">
                 <s:workflowdescription lsid="urn:lsid:www.mygrid.org.uk:operation:FXBCXOWFFC0" author="" title="" />
                 };

  my $oldport = param('portname');

  my $finalcontent = qq{ 
   <s:link source="$oldport" sink="output" />
   <s:sink name="output" />
   };

   my $foot = qq{</s:scufl>};

   print header(-type=>'text/xml'), $head.$scufl.$finalcontent.$foot;
  

}


sub getSCUFLButton {

	my ($scufl, $portname) = @_;

	print      "<center>",
			start_form(-action => url(-full)),
                   hidden("scufl", $scufl),
                   hidden("portname", $portname),
                   hidden("getscufl", "true"),
                   submit("Retrieve Current SCUFL Workflow"),
                   end_form, "</center>";


}

sub generateUniqueServiceID {
	my ($null) = @_;
	my $id = param('sid');

	++$id;	
	return $id;

}


#=================================================



!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';




