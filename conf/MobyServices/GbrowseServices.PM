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
$file   = shift || File::Spec->catfile($dir,basename($0, '.PM'));

open OUT,">$file" or die "Can't create $file: $!";

print "Extracting $file (with variable substitutions)\n";

my $startperl = $Config{startperl} ne '#!perl' 
  ? $Config{startperl}
  : "#!$Config{perlpath}";

print OUT <<"!GROK!THIS!";
$startperl -w
package MobyServices::GbrowseServices;

###################################################################
# Non-modperl users should change this variable if needed to point
# to the directory in which the configuration files are stored.
#
\$CONF_DIR  = '$OPTIONS{CONF}/gbrowse.conf';
#
###################################################################

!GROK!THIS!

# In the following, perl variables are not expanded during extraction.

print OUT <<'!NO!SUBS!';
$Id: GbrowseServices.PM,v 1.4 2003-12-15 18:26:42 markwilkinson Exp $

use strict;
use Text::Shellwords;
use Bio::DB::GFF;
use SOAP::Lite;
use MOBY::CommonSubs qw{:all};
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Util;
use vars qw(%dbh $CONFIG $authURI $CONF_DIR);

sub _settings {
    $CONF_DIR  = conf_dir($CONF_DIR);  # conf_dir() is exported from Util.pm

    ## CONFIGURATION & INITIALIZATION ################################  
    # preliminaries -- read and/or refresh the configuration directory
    $CONFIG = open_config($CONF_DIR);  # open_config() is exported from Util.pm
    my @sources = $CONFIG->sources; # get all data sources

    foreach (@sources){  # grab the database handle for each source
        $CONFIG->source($_);
        my $db = open_database($CONFIG);
        $dbh{$_}=$db;
    }
    
    open (IN, "$CONF_DIR/MobyServices/moby.conf") || die "\n**** GbrowseServices.pm couldn't open configuration file $CONF_DIR/MobyServices/moby.conf:  $!\n";
    while (<IN>){
        chomp; next unless $_; # filter out blank lines
        next if m/^#/;  # filter out comment lines
        my @res = shellwords($_);  # parse the tokens key = value1 value2 value3
        $CONFIG->{MOBY}->{$res[0]} = [@res[2..scalar(@res)]];  # add them to the existing config with a new tag MOBY in key = \@values format
    }
}

sub GbrowseGetReferenceFasta {
    my ($caller, $data) = @_;
    _settings();
    my $reference = $CONFIG->{'MOBY'}->{'Reference'};
    $reference = shift(@$reference); $reference ||='';
    unless ($reference){
        print STDERR "\n\nMobyServices::GbrowseServices - you have not set a reference class in your moby.conf file\n\n";
        return SOAP::Data->type('base64' => responseHeader($authURI) . responseFooter());
    }

    my $authURI = $CONFIG->{'MOBY'}->{'authURI'};
    $authURI = shift(@$authURI); $authURI ||='unknown.org';
    
    my @validNS = validateNamespaces($reference);  # ONLY do this if you are intending to be namespace aware!
    unless (scalar(@validNS)){
        print STDERR "\n\nMobyServices::GbrowseServices - namespace $reference does not exist in the MOBY Namespace ontology\n\n";
        return SOAP::Data->type('base64' => responseHeader($authURI) . responseFooter());
    }

    my $MOBY_RESPONSE;
    foreach my $source($CONFIG->sources){
        $CONFIG->source($source); # set the current source
        my $db = $dbh{$source};  # get the database object
        next unless $db;

        my (@inputs)= genericServiceInputParser($data); # ([SIMPLE, $queryID, $simple],...)
        return SOAP::Data->type('base64' => responseHeader($authURI) . responseFooter()) unless (scalar(@inputs));

        foreach (@inputs){
            my ($articleType, $qID, $input) = @{$_};
            unless (($articleType == SIMPLE) && ($input)){
                $MOBY_RESPONSE .= simpleResponse("", "", $qID) ;
                next;
            } else {
                my $namespace = getSimpleArticleNamespaceURI($input);
                (($MOBY_RESPONSE .= simpleResponse("", "", $qID)) && next) unless validateThisNamespace($namespace, @validNS);
                my ($identifier) = getSimpleArticleIDs($input);  # note array output!
                # do your thing here!
                my $seg = $db->segment(-name => $identifier);
                (($MOBY_RESPONSE .= simpleResponse("", "", $qID)) && next) unless $seg;
                my $seq = $seg->seq;
                $seq =~ s/\s//g;
                $seq =~ s/(\S{70})/$1\n/g;
                my $fasta = ">$identifier\n$seq\n";
                $MOBY_RESPONSE .= simpleResponse("<moby:FASTA moby:namespace='$namespace' moby:id='$identifier'>\n$fasta\n</moby:FASTA>", "", $qID);
            }
        }
    }
    print STDERR (responseHeader($authURI) . $MOBY_RESPONSE . responseFooter);
    return SOAP::Data->type('base64' => (responseHeader($authURI) . $MOBY_RESPONSE . responseFooter));    
}


sub GbrowseGetReferenceSeqObj {
    my ($caller, $data) = @_;
    _settings();

    my $reference = $CONFIG->{'MOBY'}->{'Reference'};
    $reference = shift(@$reference); $reference ||='';
    unless ($reference){
        print STDERR "\n\nMobyServices::GbrowseServices - you have not set a reference class in your moby.conf file\n\n";
        return SOAP::Data->type('base64' => responseHeader($authURI) . responseFooter());
    }

    my $authURI = $CONFIG->{'MOBY'}->{'authURI'};
    $authURI = shift(@$authURI); $authURI ||='unknown.org';

    my @validNS = validateNamespaces($reference);  # ONLY do this if you are intending to be namespace aware!
    unless (scalar(@validNS)){
        print STDERR "\n\nMobyServices::GbrowseServices - namespace $reference does not exist in the MOBY Namespace ontology\n\n";
        return SOAP::Data->type('base64' => responseHeader($authURI) . responseFooter());
    }
    
    my %types = ('dna', 'DNASequence', 'rna', 'RNASequence', 'protein', 'AminoAcidSequence');
    my $MOBY_RESPONSE;
    foreach my $source($CONFIG->sources){
        $CONFIG->source($source); # set the current source
        my $db = $dbh{$source};  # get the database object
        next unless $db;
        
        my (@inputs)= genericServiceInputParser($data); # ([SIMPLE, $queryID, $simple],...)
        return SOAP::Data->type('base64' => responseHeader($authURI) . responseFooter()) unless (scalar(@inputs));

        my @validNS = validateNamespaces($reference);  # ONLY do this if you are intending to be namespace aware!
        unless (scalar(@validNS)){
            print STDERR "\n\nMobyServices::GbrowseServices - namespace $reference does not exist in the MOBY Namespace ontology\n\n";
            return SOAP::Data->type('base64' => responseHeader($authURI) . responseFooter());
        }

        foreach (@inputs){
            my ($articleType, $qID, $input) = @{$_};
            unless (($articleType == SIMPLE) && ($input)){
                $MOBY_RESPONSE .= simpleResponse("", "", $qID) ;
                next;
            } else {
                my $namespace = getSimpleArticleNamespaceURI($input);
                (($MOBY_RESPONSE .= simpleResponse("", "", $qID)) && next) unless validateThisNamespace($namespace, @validNS);
                my ($identifier) = getSimpleArticleIDs($input);  # note array output!
                # do your thing here!
                my $seg = $db->segment(-name => $identifier);
                (($MOBY_RESPONSE .= simpleResponse("", "", $qID)) && next) unless $seg;
                my $seq = $seg->seq;
                $seq =~ s/\s//g;
                my $length = $seg->length;
                my $objtype = $types{$seg->alphabet};
                (($MOBY_RESPONSE .= simpleResponse("", "", $qID)) && next) unless $objtype;
                $MOBY_RESPONSE .= simpleResponse("<moby:$objtype moby:namespace='$namespace' moby:id='$identifier'>
                                                 <moby:String namespace='' id=''>$seq</moby:String>
                                                 <moby:Integer namespace='' id=''>$length</moby:Integer>
                                                 </moby:$objtype>", "", $qID);
            }
        }
    }
    #print STDERR (responseHeader($authURI) . $MOBY_RESPONSE . responseFooter);
    return SOAP::Data->type('base64' => (responseHeader($authURI) . $MOBY_RESPONSE . responseFooter));    
}


1;

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
