#!perl
use Config;
use File::Basename qw(&basename &dirname);
use Cwd;

$origdir = cwd;
chdir dirname($0);
$file = basename($0, '.PL','.PLS');
$file .= $^O eq 'VMS' ? '.com' : '.pl';

open OUT,">$file" or die "Can't create $file: $!";

print "Extracting $file (with variable substitutions)\n";

print OUT <<"!GROK!THIS!";
$Config{startperl}
!GROK!THIS!

# In the following, perl variables are not expanded during extraction.

print OUT <<'!NO!SUBS!';
use strict;
use Bio::DB::GFF;
use Getopt::Long;

=head1 NAME

load_genbank.pl - Load a Bio::DB::GFF database from GENBANK files.

=head1 SYNOPSIS

  % load_genbank.pl -d genbank -f localfile.gb
  % load_genbank.pl -d genbank -a AP003256

=head1 DESCRIPTION

This script loads a Bio::DB::GFF database with the features contained
in a either a local genbank file or an accession that is fetched from
genbank.  Various command-line options allow you to control which
database to load and whether to allow an existing database to be
overwritten.

This script currently only uses MySQL, though it is a proof-of-
principle and could easily be extended to work with other RDMS
that are supported by GFF through adaptors.

=head1 COMMAND-LINE OPTIONS

Command-line options can be abbreviated to single-letter options.
e.g. -d instead of --database.

   --create                  Force creation and initialization of database
   --dsn       <dsn>         Data source (default dbi:mysql:test)
   --user      <user>        Username for mysql authentication
   --pass      <password>    Password for mysql authentication
   --proxy     <proxy>       Proxy server to use for remote access
   --file                    Arguments that follow are Genbank/EMBL file names (default)
   --accession               Arguments that follow are genbank accession numbers

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
            'accession'   => \$ACC,
            'file'        => \$FILE,
            'proxy:s'     => \$PROXY,
	    create        => \$CREATE) or die <<USAGE;
Usage: $0 [options] <gff file 1> <gff file 2> ...
Load a Bio::DB::GFF database from GFF files.

 Options:
   --create                  Force creation and initialization of database
   --dsn       <dsn>         Data source (default dbi:mysql:test)
   --user      <user>        Username for mysql authentication
   --pass      <password>    Password for mysql authentication
   --proxy     <proxy>       Proxy server to use for remote access
   --file                    Arguments that follow are Genbank/EMBL file names (default)
   --accession               Arguments that follow are genbank accession numbers

This script loads a Bio::DB::GFF database with the features contained
in a either a local genbank file or an accession that is fetched from
genbank.  Various command-line options allow you to control which
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

die "you must specify either an accession to retrieve from\nembl or a local file containing data in embl format\n" 
  unless @ARGV;

if ($ACC && !$FILE) {
  while ($_ = shift) {
    print STDERR "Loading $_...";
    my $result = $db->load_from_embl(/^NC_/?'refseq':'embl' => $_);
    print STDERR $result ? "ok\n" : "failed\n";
  }
} else {
  while ($_ = shift) {
    print STDERR "Loading $_...\n";
    my $result = $db->load_from_file($_);
    print STDERR $result ? "ok\n" : "failed\n";
  }
}

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;
