#!/usr/bin/perl -w
#$Id: moby_server.cgi,v 1.2 2003-12-12 18:57:18 markwilkinson Exp $
# _________________________________________________________________
use SOAP::Transport::HTTP;
use MobyServices::GbrowseServices;
use strict;


my $x = new SOAP::Transport::HTTP::CGI;

$x->dispatch_with({
    'http://biomoby.org/#GbrowseGetSeqObj' =>  'MobyServices::GbrowseServices',
    'http://biomoby.org/#GbrowseGetFasta' =>  'MobyServices::GbrowseServices',
    });
$x->handle;


