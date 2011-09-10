#!/usr/bin/env perl

# PSGI configuration file for GBrowse.
# Author: Todd Harris (todd@wormbase.org)

use strict;
use warnings;

use Plack::App::CGIBin;
#use Plack::App::WrapCGI;
#use Plack::App::Proxy;
use Plack::Builder;

# Variable substitution during Build
$ENV{GBROWSE_CGIBIN}       ||= '$CGIBIN';  # Full path to our CGI installation directory.
$ENV{GBROWSE_CONF}         ||= '$CONF';    # Full path to the configuration directory.
$ENV{GBROWSE_HTDOCS}       ||= '$HTDOCS';  # Full path to the gbrowse static files.
$ENV{GBROWSE_DEVELOPMENT}  ||= '';         # Optional. Set to "true" to enable debugging panels.
$ENV{PERL5LIB}             = "$PERL5LIB";


# 1. Via CGIBin
my $gbrowse = Plack::App::CGIBin->new( root => $ENV{GBROWSE_CGIBIN}, )->to_app;

# 2. Or via WrapCGI
#my $gb2 = Plack::App::WrapCGI->new(script => "$ENV{GBROWSE_HTDOCS}/cgi/gbrowse")->to_app;

# 3. OR just by proxy
#my $remote_gbrowse        = Plack::App::Proxy->new(remote => "http://206.108.125.173:8000/tools/genome")->to_app;
#my $remote_gbrowse_static = Plack::App::Proxy->new(remote => "http://206.108.125.173:8000/gbrowse2")->to_app;

builder {
    
    # Typically running behind reverse proxy.
    # enable "Plack::Middleware::ReverseProxy";
    
    # Add debug panels if we are a development environment.
    if ($ENV{GBROWSE_DEVELOPMENT}) {
	enable 'Debug', panels => [ qw(Environment Memory ModuleVersions Timer PerlConfig Parameters Response Session TrackObjects DBITrace) ];
    }

    # Mount GBrowse at root. This is probably NOT what you want to do.
    mount '/'         => $gbrowse;

    # Static files, controlled by the url/ parameters in GBrowse.conf.
    mount "/gbrowse2" => Plack::App::File->new(root => $ENV{GBROWSE_HTDOCS});

    # Mounting GBrowse as an app
    # mount '/gb'  => $gbrowse;
    # mount '/cgi' => $gbrowse;

    # Plack proxying GBrowse
    # mount '/tools/genome' => $remote_gbrowse;
    # mount '/gbrowse2' => $remote_gbrowse_static;
};
