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


#=======================================================================
use MOBY::Client::Central;
use strict;
use Text::Shellwords;
use MOBY::CommonSubs qw{:all};
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Util;

use vars qw(%dbh $CONFIG $authURI $CONF_DIR $CGIDIR);

if ($ARGV[0] && $ARGV[0] =~ /clean/){
    &DEREGISTER_SERVICES();
    print "services deregistered\n";
    exit 1;
} elsif ($ARGV[0] && $ARGV[0] =~ /register/){
    &REGISTER_SERVICES();
    print "services registered\n";
    exit 1;
} else {
    print <<USAGE;

usage:  perl register_moby_services.pl -register  (to register services)
        perl register_moby_services.pl -clean     (to deregister them)
    
USAGE
exit 0;
}

&REGISTER_SERVICES() || die "Registration of your services failed for unknown reasons\n\n";

exit 1;
    

sub REGISTER_SERVICES {
    _settings();
    system 'clear';
    print STDOUT "
You MUST have configured the moby.conf file in your
./gbrowse.conf/MobyServices folder to reflect your
own server settings BEFORE you run this registration script!\n\n";
    
    print STDOUT "Have you done this? [N/y]: ";
    my $resp = <STDIN>;
    chomp $resp;
    die "
Please go ahead and configure this file, then run this script again
    " unless ($resp =~ /y/i);
    
    open (DONE, ">>registeredMOBYServices.dat") || die "can't open the logfile registeredMOBYServices.dat to record the services you have registered in MOBY Central.\n";
    my $C = MOBY::Client::Central->new();

    # ========  get configuration settings from
    # ========  the gbrowse/MobyServices/moby.conf
    # ========  file, as well as the 0X.DBNAME.conf
    # =============================================
    my $reference = $CONFIG->{'MOBY'}->{'Reference'};
    $reference = shift(@$reference); $reference ||='';

    my $authURI = $CONFIG->{'MOBY'}->{'authURI'};
    $authURI = shift(@$authURI); $authURI ||='unknown.org';

    my $contactEmail = $CONFIG->{'MOBY'}->{'contactEmail'};
    $contactEmail = shift(@$contactEmail);
    die "\nYou have not configured a valid contactEmail parameter in
    your config file!\n" unless ($contactEmail =~ /\S+\@\S+\.\S+/);

    my $cgiURL = $CONFIG->{'MOBY'}->{'CGI_URL'};
    $cgiURL = shift(@$cgiURL);
    die "\nYou have not configured a valid CGI_URL parameter in
    your config file!\n" unless ($cgiURL =~ "^http\://");

    my @sources = $CONFIG->sources;
    # =============================================
    # =============================================
    
    my $description = "Consumes base Object's in the $reference namespace and does a retrieval of that sequence record from the ".(join ",", @sources)." database(s), returning it as a FASTA sequence object.";
    my $success = TEST($C->registerService(
        serviceName  => "GbrowseGetReferenceFasta",  
        serviceType  => "Retrieval",
        authURI      => $authURI,      
        contactEmail => $contactEmail,      
        description => $description,
        category  =>  "moby",
        URL    => "$cgiURL/moby_server",
        input =>[
                ['', ['Object', [$reference]]],  # this will fail if the $reference namespace is not yet registered
                ],
        output =>[
                ['', ['FASTA', [$reference]]],
               ],
    ), 1, 1);
    unless ($success){
        close DONE;
        DEREGISTER_SERVICES();
        die "registered services have been deregistered pending successful completion of this routine\n  You will need to start again.\n";;
    } else {
        print DONE "$authURI\tGbrowseGetReferenceFasta\n";
    }
    
    $description = "Consumes base Object's in the $reference namespace and does a retrieval of that sequence record from the ".(join ",", @sources)." database(s), returning it as a GenericSequence object or better (i.e. DNASequence, RNASequence, or AminoAcidSequence).";
    $success = TEST($C->registerService(
        serviceName  => "GbrowseGetReferenceSeqObj",  
        serviceType  => "Retrieval",
        authURI      => $authURI,      
        contactEmail => $contactEmail,      
        description => $description,
        category  =>  "moby",
        URL    => "$cgiURL/moby_server",
        input =>[
                ['', ['Object', [$reference]]],  # this will fail if the $reference namespace is not yet registered
                ],
        output =>[
                ['', ['GenericSequence', [$reference]]],
               ],
    ), 1, 1);
    unless ($success){
        close DONE;
        DEREGISTER_SERVICES();
        die "registered services have been purged from MOBY Central pending successful completion of this routine\n  You will need to start again.\n";;
    } else {
        print DONE "$authURI\tGbrowseGetReferenceSeqObj\n";
    }


    $description = "Consumes base Object's in the $reference namespace and does a retrieval of GFF2-formatted text from the ".(join ",", @sources)." database(s), returning it as a GFF2 object.";
    $success = TEST($C->registerService(
        serviceName  => "GbrowseGetReferenceGFF2",  
        serviceType  => "Retrieval",
        authURI      => $authURI,      
        contactEmail => $contactEmail,      
        description => $description,
        category  =>  "moby",
        URL    => "$cgiURL/moby_server",
        input =>[
                ['', ['Object', [$reference]]],  # this will fail if the $reference namespace is not yet registered
                ],
        output =>[
                ['', ['GFF2', [$reference]]],
               ],
    ), 1, 1);
    unless ($success){
        close DONE;
        DEREGISTER_SERVICES();
        die "registered services have been purged from MOBY Central pending successful completion of this routine\n  You will need to start again.\n";;
    } else {
        print DONE "$authURI\tGbrowseGetReferenceSeqObj\n";
    }


    $description = "Consumes base Object's in the $reference namespace and does a retrieval of GFF3-formatted text plus FASTA from the ".(join ",", @sources)." database(s), returning it as a GFF3 object.";
    $success = TEST($C->registerService(
        serviceName  => "GbrowseGetReferenceGFF3",  
        serviceType  => "Retrieval",
        authURI      => $authURI,      
        contactEmail => $contactEmail,      
        description => $description,
        category  =>  "moby",
        URL    => "$cgiURL/moby_server",
        input =>[
                ['', ['Object', [$reference]]],  # this will fail if the $reference namespace is not yet registered
                ],
        output =>[
                ['', ['GFF3', [$reference]]],
               ],
    ), 1, 1);
    unless ($success){
        close DONE;
        DEREGISTER_SERVICES();
        die "registered services have been purged from MOBY Central pending successful completion of this routine\n  You will need to start again.\n";;
    } else {
        print DONE "$authURI\tGbrowseGetReferenceSeqObj\n";
    }


    return 1;
}

sub DEREGISTER_SERVICES {
    my $C = MOBY::Client::Central->new();
    open (DONE, "registeredMOBYServices.dat") || die "can't open the logfile registeredMOBYServices.dat to get a listing of the services you have registered in MOBY Central.\n";
    while (<DONE>){
        chomp;
        my ($auth, $name) = (($_=~/(\S+)\t(\S+)/) && ($1, $2));
        ($auth && $name) || die "\n\n********** CORRUPT registeredMOBYServices.dat file *************\n non-recoverable error.";
        my $success = TEST($C->deregisterService(
        serviceName  => $name,  
        authURI      => $auth,      
        ), 2, 1);
    }
    close DONE;
    open (DONE, ">registeredMOBYServices.dat") || die "can't open the logfile registeredMOBYServices.dat to purge list of registered services\n";
    close DONE;
}

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
    
    open (IN, "$CONF_DIR/MobyServices/moby.conf") || die "\n**** GbrowseServices.pm couldn't open configuration file $CONF_DIR/MOBY/moby.conf:  $!\n";
    while (<IN>){
        chomp; next unless $_; # filter out blank lines
        next if m/^#/;  # filter out comment lines
        my @res = shellwords($_);  # parse the tokens key = value1 value2 value3
        $CONFIG->{MOBY}->{$res[0]} = [@res[2..scalar(@res)]];  # add them to the existing config with a new tag MOBY in key = \@values format
    }
}

sub TEST {  # test of Registration object
    my ($reg, $test, $expect) = @_;
    die "\a\a\aREG OBJECT MALFORMED" unless $reg;
    if ($reg->success == $expect){
        print "test $test\t\t[PASS]\n";
        return 1;
    } else {
        print "test $test\t\t[FAIL]\n",$reg->message,"\n\n";
        return 0;
    }
    
}



#=======================================================================
!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
