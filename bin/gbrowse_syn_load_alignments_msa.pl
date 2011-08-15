#!/usr/bin/perl -w

=head1 NAME

gbrowse_syn_load_alignments_msa.pl - load syntenic alignments into a Bio::DB::Synteny::Store from a multiple sequence alignment.

=head1 USAGE

gbrowse_syn_load_alignments_msa.pl -a DBI::mysql -u user -p pass -d rice_synteny -c -v rice.aln

=head2 Options

=over 4

=item -a DBI::mysql

Adaptor backend.

=item -u username

=item -p password

=item -d dbi_dsn

=item -c

Create a new database, erasing any existing data.

=item -v

Turn verbose mode on.

=back

=head1 DESCRIPTION

This script will load the gbrowse_syn alignment database directly
from a multiple sequence alignment file. All Bio::AlignIO formats
are supported, however, each sequence *name* has to have the
following format: 'species-sequence(strand)/start-end'.

=cut

use strict;

use Pod::Usage;
use Getopt::Long;

use Bio::DB::Synteny::Store;
use Bio::DB::Synteny::Store::Loader::MSA;

my (
    $format,
    $create,
    $user,
    $pass,
    $dsn,
    $verbose,
    $nomap,
    $mapres,
    $adaptor,

    $hit_idx,
    $pidx,
    %map,
    );

GetOptions(
           'a|adaptor=s'   => \$adaptor,
	   'f|format=s'    => \$format,
           'u|user=s'      => \$user,
	   'p|pass=s'      => \$pass,
	   'd|dsn=s'       => \$dsn,
           'm|map=i'       => \$mapres,
	   'v|verbose'     => \$verbose,
	   'nomap'       => \$nomap,
	   'c|create'      => \$create
	   );

$dsn     || pod2usage('must provide -d option');

my $syn_store = Bio::DB::Synteny::Store->new(
    -adaptor => $adaptor || 'DBI::mysql',
    -dsn     => $dsn,
    -user    => $user,
    -pass    => $pass,
    -create  => $create,
   );

my $loader = Bio::DB::Synteny::Store::Loader::MSA->new(
    -store  => $syn_store,
    -format => $format || 'clustalw',
    -mapres => $mapres,
    );

$loader->load( @ARGV );
