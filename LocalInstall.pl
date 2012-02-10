#!/usr/bin/perl

use strict;
use lib './lib';
use Bio::Graphics::Browser2;
my $version = $Bio::Graphics::Browser2::VERSION;
my $prefix  = "$ENV{HOME}/gbrowse/$version";
my @args =('--conf'      =>  "$prefix/conf",
           '--htdocs'    =>  "$prefix/html",
           '--tmp'       =>  "$prefix/tmp",
           '--persistent'=>  "$prefix/persistent",
           '--databases' =>  "$prefix/databases",
           '--cgibin'    =>  "$prefix/cgi",
           '--wwwuser'   =>  $ENV{USER},
           '--installconf' => 'n',
           '--installetc'  => 'n');

warn join ' ','perl','./Build.PL',@args,"\n";
exec 'perl','./Build.PL',@args;

