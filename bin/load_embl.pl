#!/usr/bin/perl

use strict;
use lib '/home/lstein/projects/bioperl-live';
use lib '../blib/lib';
use Bio::DB::GFF;
use Getopt::Long;

=head1 NAME

load_embl.pl - Load a Bio::DB::GFF database from EMBL files.

=head1 SYNOPSIS

  % load_embl.pl -d embl -f localfile.embl 
  % load_embl.pl -d embl -a AP003256

=head1 DESCRIPTION

This script loads a Bio::DB::GFF database with the features contained
in a either a local EMBL file or an accession that is fetched from
EMBL.  Various command-line options allow you to control which
database to load and whether to allow an existing database to be
overwritten.

This script currently only uses MySQL, though it is a proof-of-
principle and could easily be extended to work with other RDMS
that are supported by GFF through adaptors.

=head1 COMMAND-LINE OPTIONS

Command-line options can be abbreviated to single-letter options.
e.g. -d instead of --database.

   --dsn     <dsn>         Data source (default dbi:mysql:test)
   --user    <user>        Username for mysql authentication
   --pass    <password>    Password for mysql authentication
   --accesion <accession>  Accession number to retrieve from EMBL
   --file    <filename>    Local EMBL formatted file to load
   --proxy   <proxy>       Proxy server to use for remote access
   --create                Force creation and initialization of database

=head1 SEE ALSO

L<Bio::DB::GFF>, L<bulk_load_gff.pl>, L<load_gff.pl>

=head1 AUTHOR

Scott Cain, cain@cshl.org

Copyright (c) 2003 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut


my ($DSN,$ADAPTOR,$CREATE,$USER,$PASSWORD,$FASTA,$ACC,$FILE,$PROXY);

GetOptions ('dsn:s'       => \$DSN,
	    'user:s'      => \$USER,
	    'password:s'  => \$PASSWORD,
            'accesion:s'  => \$ACC,
            'file:s'      => \$FILE,
            'proxy:s'     => \$PROXY,
	    create        => \$CREATE) or die <<USAGE;
Usage: $0 [options] <gff file 1> <gff file 2> ...
Load a Bio::DB::GFF database from GFF files.

 Options:
   --dsn     <dsn>         Data source (default dbi:mysql:test)
   --user    <user>        Username for mysql authentication
   --pass    <password>    Password for mysql authentication
   --accesion <accession>  Accession number to retrieve from EMBL
   --file    <filename>    Local EMBL formatted file to load
   --proxy   <proxy>       Proxy server to use for remote access
   --create                Force creation and initialization of database

This script loads a Bio::DB::GFF database with the features contained
in a either a local EMBL file or an accession that is fetched from
EMBL.  Various command-line options allow you to control which
database to load and whether to allow an existing database to be
overwritten.
                                                                                                                                                       
This script currently only uses MySQL, though it is a proof-of-
principle and could easily be extended to work with other RDMS
that are supported by GFF through adaptors.

USAGE
;

# some local defaults
$DSN     ||= 'dbi:mysql:test';
$ADAPTOR = 'biofetch';

my @auth;
push @auth,(-user=>$USER)     if defined $USER;
push @auth,(-pass=>$PASSWORD) if defined $PASSWORD;
push @auth,(-proxy=>$PROXY)   if defined $PROXY;

my $db = Bio::DB::GFF->new(-adaptor=>$ADAPTOR,-dsn => $DSN,@auth)
  or die "Can't open database: ",Bio::DB::GFF->error,"\n";

if ($CREATE) {
  $db->initialize(1);
}

if ($ACC) {
  $db->load_from_embl('embl',$ACC);
} elsif ($FILE) {
  $db->load_from_file($FILE);
} else {
  die "you must specify either an accession to retrieve from\nembl or a local file containing data in embl format\n";
}
