#!/usr/bin/perl -w
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


