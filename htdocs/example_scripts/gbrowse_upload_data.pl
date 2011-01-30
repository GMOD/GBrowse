#!/usr/bin/perl

use strict;
use LWP::UserAgent;
use HTTP::Request::Common;
use File::Basename 'basename';
use JSON;

@ARGV || $ARGV[0]=~ /^-?-h/ or die <<END;
usage: $0 <gbrowse_url> [session_id]
The data to be uploaded into GBrowse as a
new track will be read from STDIN.
END
    ;
my $gbrowse = shift;
my $id      = shift;

print STDERR "Please enter data to be uploaded (BED, WIG, GFF3 format) on stdin: \n"
    if -t STDIN;

my $data = join ('',<>); # slurp all of stdin

my $agent    = LWP::UserAgent->new;
$agent->cookie_jar({file=>"$ENV{HOME}/.gbrowse_session",
		    autosave=>1
		   });
my $url = $gbrowse;
$url   .= '/' unless $url =~ m!/$/!;

my @id    = (id => $id) if $id;
my $request = POST($url,
		   Content_Type => 'form-data',
		   Content => [
		       action    => 'upload_file',
		       overwrite => 1,
		       data      => $data,
		       @id
		   ]
    );
my $response    = $agent->request($request);
die $response->status_line unless $response->is_success;
my $content     = $response->decoded_content;
my $cookie      = $response->header('Set-cookie');
my ($used_id)   = $cookie =~ /gbrowse_sess=([a-f0-9]+)/;

my $struct  = from_json($content);

if ($struct->{success}) {
    print <<END;
Tracks     : @{$struct->{tracks}}
uploadName : $struct->{uploadName}
sessionID  : $used_id
END
} else {
    die $struct->{error_msg};
}
