#!/usr/bin/perl -w 

=head1 NAME

auto_install_databases.pl - Download and install GFF data sets

=head1 SYNOPSYS

  % auto_install_databases.pl --rdms pg --user scott

=head1 DESCRIPTION

This program queries a web server to determine what data sets are
available and presents the user with a list to choose from, with the
option of getting several data sets at once.  The chosen data sets 
are downloaded and they are used as inputs for the bulk loader of the
specified relational database management system (either MySQL or 
PostgreSQL) to initialize and load the GFF and optionally fasta
data.

=head2 NOTES

This program uses the bulk loader for its database (bp_bulk_load_gff.pl
for mysql, bp_pg_bulk_load_gff.pl for postgres); read the documentation
for those programs for caveats with their use.
                                                                                 
Like the bulk loaders, this program uses \$TMPDIR to transiently store
downloaded data, therefore, \$TMPDIR must have enough free space to store
all of the raw data and the processed files for importation to the database.
                                                                                 
To create your own web server data source, carefully copy the syntax and
file structure of the default data source, as this program is very
inflexible with regard to the obtaining information from the web server.
                                                                                 
Since the data is being downloaded uncompressed from web server, it may
take a very long time for the download and database load to complete.
An hour or more is not out of the question for a large data set like
wormbase.

=head1 COMMAND-LINE OPTIONS

Options can be abbreviated.  For example, you can use -s for --server.

    --server           URL of web server to obtain datasets
                         Default = 'http://brie4.cshl.org:8000/'
    --rdms             RDMS to use (mysql or pg (Postgres))
                         Default = 'mysql'
    --user             Username to log into database server as
                         Default = ''
    --password         Password associated with username
                         Default = ''

=head1 SEE ALSO

L<Bio::DB::GFF>, L<bp_bulk_load_gff.pl>, L<bp_pg_bulk_load_gff.pl>

=head1 AUTHOR

Scott Cain, cain@cshl.org

Copyright (c) 2003 Cold Spring Harbor Laboratory
                                                                                
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut

use strict;

use LWP::UserAgent;
use Getopt::Long;

my $bWINDOWS = ($^O =~ /MSWin32/i) ? 1 : 0;
my ($USER,$PASS,$RDMS,$SERVER);

GetOptions ('server:s'      => \$SERVER,
            'rdms:s'        => \$RDMS,
            'user:s'        => \$USER,
            'password:s'    => \$PASS) or die <<USAGE;
Usage: $0 [options]
Retrieve data sets and bulk-load multiple Bio::DB::GFF databases from GFF files.

 Options:
    --server           URL of web server to obtain datasets
                         Default = 'http://brie4.cshl.org:8000/'
    --rdms             RDMS to use (mysql or pg (Postgres))
                         Default = 'mysql'
    --user             Username to log into database server as
                         Default = ''
    --password         Password associated with username
                         Default = ''

Options can be abbreviated.  For example, you can use -s for --server.

This program uses the bulk loader for its database (bp_bulk_load_gff.pl
for mysql, bp_pg_bulk_load_gff.pl for postgres); read the documentation 
for those programs for caveats with their use.

Like the bulk loaders, this program uses \$TMPDIR to transiently store
downloaded data, therefore, \$TMPDIR must have enough free space to store
all of the raw data and the processed files for importation to the database.

To create your own web server data source, carefully copy the syntax and 
file structure of the default data source, as this program is very
inflexible with regard to the obtaining information from the web server.

Since the data is being downloaded uncompressed from web server, it may 
take a very long time for the download and database load to complete. 
An hour or more is not out of the question for a large data set like
wormbase.

USAGE
;

$RDMS   ||= 'mysql';
$SERVER ||= 'http://brie4.cshl.org:8000/';

my $bulkloader = ($RDMS =~ /mysql/i) ? 'bp_bulk_load_gff.pl'
                                     : 'bp_pg_bulk_load_gff.pl';

my $tmpdir = $ENV{TMP} || $ENV{TMPDIR} || '/usr/tmp';
$tmpdir =~ s!\\!\\\\!g if $bWINDOWS; #eliminates backslash mis-interpretation

my $ua = LWP::UserAgent->new;
my $req = HTTP::Request->new(GET => $SERVER);
my $res = $ua->request($req);

die "Failed to connect to gbrowse data source server $SERVER\n" unless ($res->is_success);
 
my $result = $res->content;
my @result = split /\n/, $result;
my %available_data;

# note that since I control both the page being retrieved and
# this script, I can parse the html "by hand".  Were that not
# the case, I would certainly use HTML::Parser (or something
# like that).

foreach (@result) {
  if (/<li>.*href=\"(.*)\">(.*)<.*<\/li>/) {
    $available_data{$2} = $1;
  }
}

my $i = 0;
my @keys;
$keys[0] = '';

foreach my $key (reverse sort keys %available_data) {
  $i++;
  push @keys, $key;
  print "[$i] $key\n";
}
print "Choose data sets to install (comma delimited list) [0]:";
my $answer;
chomp($answer = <STDIN>);

die "OK, won't install anything\n" unless $answer;
my @data_sets = split /\,\s*/, $answer;

print "\nInstall these datasets?\n";
foreach my $set (@data_sets) {
  print "$keys[$set]\n";
}
print "answer yes to confirm, no to quit [y]?";
chomp($answer = <STDIN>);

die "ok, nothing will be installed\n" if ($answer =~ /^n/i);

#do arg building and error checking here

my @args;
push @args, $bulkloader;
push @args, '--create';
if (defined $USER) {
  push @args, "--user";
  push @args, $USER;
  if (defined $PASS) {
    push @args, "--password";
    push @args, $PASS;
  }
}

#figure out which data sets, and if they include fastas
#don't allow loading fasta without gff

#this loop is really taking advantage of my control of the download site
#it assumes that for every gff file there is a fasta, and than they are named
#with the same prefix (eg, yeast_), and that the gff file comes second 
#alphabetically (ie, first when reverse sorted).
warn "retrieving data (this could take a while) ...\n";
for ($i=0;$i < scalar @data_sets;$i++) {
  my $set = $data_sets[$i];
  if ($set % 2 == 0) {
    warn "Importing of fasta without gff is not permitted from this interface\n";
    unlink "$tmpdir/$keys[$set].$$";
    next;
  }   
  
  if (defined $data_sets[$i+1] && $set + 1 == $data_sets[$i+1]) {
        # fasta is to be imported too
    my $gff      = "$tmpdir/$keys[$set].$$";
    my $fasta    = "$tmpdir/$keys[$set+1].$$";

    download_data($keys[$set]);
    download_data($keys[$set+1]);

    $keys[$set] =~ /^(.+)_/;
    my $db       = $1;

    push @args, "--fasta";
    push @args, $fasta;
    push @args, "--database";
    push @args, $db;
    push @args, $gff;

    warn "executing @args\n";

    system (@args);

    unlink $gff;
    unlink $fasta;
    $i++;
  } else {  # don't import fasta
    my $gff     = "$tmpdir/$keys[$set].$$";

    download_data($keys[$set]);

    $keys[$set] =~ /^(.+)_/;
    my $db      = $1;

    push @args, "--database";
    push @args, $db;
    push @args, $gff;
       
    warn "executing @args\n";
                                        
    system (@args);

    unlink $gff;
  } 
}

sub download_data {
  my $set = shift;
  warn "getting $set ...\n";
  $req = HTTP::Request->new(GET => $available_data{$set});
  $res = $ua->request($req,"$tmpdir/$set.$$" );
}

__END__
