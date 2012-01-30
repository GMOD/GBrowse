#!/usr/bin/perl

use strict;
use LWP::UserAgent;

my $gbrowse = shift or die "usage: $0 <gbrowse_url>";

my $agent    = LWP::UserAgent->new;
$agent->cookie_jar({file=>"$ENV{HOME}/.cookies.txt",
		    autosave=>1
		   });
my $response = $agent->head($gbrowse);
die $response->status_line unless $response->is_success;

my $cookie = $response->header('Set-cookie');
my ($id)   = $cookie =~ /gbrowse_sess=([a-f0-9]+)/;
print $id,"\n";

