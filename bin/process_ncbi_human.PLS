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

=head1 NAME

process_ncbi_human.pl - Massage NCBI chromosome annotation into GFF-format suitable for Bio::DB::GFF

=head1 VERSION (CVS-info)

 $RCSfile: process_ncbi_human.PLS,v $
 $Revision: 1.1 $
 $Author: lstein $
 $Date: 2002-07-05 13:08:29 $


=head2 SYNOPSIS

   perl process_ncbi_human.pl [options] /path/to/gzipped/datafile(s)

=head2 DESCRIPTION

This script massages the chromosome annotation files located at

  ftp://ftp.ncbi.nih.gov/genomes/H_sapiens/maps/mapview/chromosome_order/

into the GFF-format recognized by Bio::DB::GFF. If the resulting
GFF-files are loaded into a Bio::DB:GFF database using the utilities
described below, the annotation can be viewed in the Generic Genome
Browser (http://www.gmod.org/ggb/) and interfaced with using the
Bio::DB:GFF libraries.  (NB these NCBI-datafiles are dumps from their
own mapviewer database backend, according to their READMEs)

To produce the GFF-files, download all the chr*sequence.gz files from
the FTP-directory above. While in that same directory, run the
following example command (see also help clause by running script with
no arguments):

process_ncbi_human.pl --locuslink [path to LL.out_hs.gz] chr*sequence.gz This
will unzip all the files on the fly and open an output file with the
name chrom[$chrom]_ncbiannotation.gff for each, read the LocusLink
records into an in-memory hash and then read through the NCBI feature
lines, lookup 'locus' features in the LocusLink hash for details on
'locus' features and print to the proper GFF files.  LL.out_hs.gz is
accessible here at the time of writing:

  ftp://ftp.ncbi.nih.gov/refseq/LocusLink/LL.out_hs.gz

Note that several of the NCBI features are skipped from the
reformatting, either because their nature is not fully known at this
time (TAG,GS_TRAN) or their sheer volume stands in the way of them
being accessibly in Bio::DB::GFF at this time (EST similarities). You
can easily change this by modifying the $SKIP variable to your liking
to add or remove features, but if you add then you will have to add
handling for those new features.

To bulk-import the GFF-files into a Bio::DB::GFF database, use the
bulk_load_gff.pl utility provided with Bio::DB::GFF

=head2 AUTHOR

Gudmundur Arni Thorisson E<lt>mummi@cshl.orgE<gt>

Copyright (c) 2002 Cold Spring Harbor Laboratory

       This code is free software; you can redistribute it
       and/or modify it under the same terms as Perl itself.

=cut

use strict;
use Getopt::Long;
use IO::File;
use File::Basename;

my $self = basename($0);
my ($doTSCSNP,$doLocuslink);
my $opt = &GetOptions ('locuslink=s'  => \$doLocuslink,
		       'tscsnp=s'     => \$doTSCSNP
		       );
die <<USAGE if(!defined($opt) || @ARGV == 0);
Usage: $self [options] <GFF filename or wildcard pattern>

Massage NCBI chromosome annotation datafiles into GFF-format suitable
for importing into Bio::DB::GFF database. Note that the program
handles both unzipped datafiles and gzipped, bzipped or compressed
ones, so do not bother with unzipping big downloads before running.

  See 'perldoc $self' for more info
Options:
   --locuslink Path to zipped LocusLink file, currently located at
               ftp://ftp.ncbi.nih.gov/refseq/LocusLink/LL.out_hs.gz
               used to lookup gene description and official symbols
   --tscsnp    DSN string to TSC MySQL database to use for auxiliary
               SNP feature attributes (CSHL internal use)

  Options can be abbreviated.  For example, you can use -l for --locuslink.

Author: Gudmundur Arni Thorisson <mummi\@cshl.org>

Copyright (c) 2002 Cold Spring Harbor Laboratory
       This library is free software; you can redistribute it
       and/or modify it under the same terms as Perl itself.

USAGE
;

#If TSC SNP processing is to be performed, connect to db
my $dbh;
if($doTSCSNP)
{
    $dbh = &dbConnect($doTSCSNP); #using the given dsn-string
}

#If Locuslink-processing is to be performed, Read 
#previously cached data structure from disk
my $llData;


if($doLocuslink)
{
    $doLocuslink = "gunzip -c $doLocuslink |" if $doLocuslink =~ /\.gz$/;
    $doLocuslink = "uncompress -c $doLocuslink |" if $doLocuslink =~ /\.Z$/;
    $doLocuslink = "bunzip -c $doLocuslink |" if $doLocuslink =~ /\.bz$/;
    open LL,$doLocuslink || die $!;
    my $l = 0;
    while(<LL>)
    {
	$l++;
	print "\r--$l LocusLink records loaded" if $l % 100 ==0;
	my ($id,$osym,$isym,$mim,$chrom,$loc,$desc,$taxid,$db) = split /\t/;
	my $name = $osym || $isym;
	#print "  Loading in Locuslink id='$id',osym='$osym',isym='$isym',name='$name',desc='$desc'\n";
	$llData->{$name}->{id} = $id;
	$llData->{$name}->{isym} = $isym;
	$llData->{$name}->{mim}  = $mim;
	$llData->{$name}->{chrom}= $chrom;
	$llData->{$name}->{loc}  = $loc;
	$llData->{$name}->{desc} = $desc;
	$llData->{$name}->{taxid}= $taxid;
	$llData->{$name}->{db}   = $db;
    }
    close LL;
}

my %methods = (EST_Human  => 'similarity',
	       EST_Mouse  => 'similarity',
	       EST_       => 'similarity',
	       );


my %DBs     = (snp        => 'dbSNP',
	       sts        => 'dbSTS',
	       locus      => 'LocusLink',
	       transcript => 'RefSeq',
	       component  => 'Genbank',
	       contig     => 'RefSeq',
	       GS_TRAN    => 'GS_TRAN',
	       clone      => 'CloneRegistry',
	       );
my %classes = (component    => 'Sequence',
	       sts          => 'STS',
	       snp          => 'SNP',
	       locus        => 'Locus',
	       transcript   => 'Transcript',
	       contig       => 'Contig',
	       clone        => 'Clone',
	       );

my %subcomponents = (transcript => 'exon',
		     locus      => 'exon',		     
		     component  => 'subcomponent',
		     );

my %groups = ();
my $max = 0;

#Prepare decompression streams for input files, if necessary
my %FH;
print "Preparing input and output streams:\n";
foreach (@ARGV) {
    my ($chrom) = /chr0?(\w+)\_sequence/;
    $FH{'Chr'.$chrom} = IO::File->new("chrom$chrom\_ncbiannotation.gff",">") or die $_,": $!";
    $_ = "gunzip -c $_ |" if /\.gz$/;
    $_ = "uncompress -c $_ |" if /\.Z$/;
    $_ = "bunzip2 -c $_ |" if /\.bz2$/;
}

#And now process all incoming data streams
my $i = 0;
my %maxCoords;
my $SKIP = q/^EST|^TAG|^GS_TRAN/;
while(<>)
{
    chomp;
    next if /^\#/;      
    my ($type,$objId,$name,$chromctg,$start,$stop,$strand) = split "\t";
    next if $type =~ /$SKIP/;
    $i++;
    my ($chrom,$ctg) = split /\|/,$chromctg;
    $chrom = "Chr$chrom";
    $max = $stop if $stop > $max;
    my $source = 'NCBI';
    my $class;
    unless($class  = $classes{$type})
    {
	print "need class for type '$type': '$_' (OR add type to \$SKIP pattern\n";
	next;
    }
    my $method = $methods{$type} || $type;
    my $db = $DBs{$type};
    my $attributes = qq/$class "$name"; Name "$name"/;

    #Deduce start/stop for certain parent features to be printed
    #to output file AFTER we've processed everything. This is 
    #necessary because NCBI only gives start/stop values for the child
    #features, like exons in a gene, but not the whole parent feature
    if($type =~ /transcript|locus/)
    {
	$groups{$type}->{$name}->{$chrom}->{start} ||= 9999999999999;
	$groups{$type}->{$name}->{$chrom}->{stop} ||= 0;
	$groups{$type}->{$name}->{$chrom}->{start} = $start 
	    if  $start < $groups{$type}->{$name}->{$chrom}->{start};
	$groups{$type}->{$name}->{$chrom}->{stop} = $stop 
	    if $stop > $groups{$type}->{$name}->{$chrom}->{stop}; 
	$groups{$type}->{$name}->{$chrom}->{source} = $source;
	$groups{$type}->{$name}->{$chrom}->{strand} = $strand;
	$groups{$type}->{$name}->{$chrom}->{method} = $method;
	$groups{$type}->{$name}->{$chrom}->{db} = $db;
	$groups{$type}->{$name}->{$chrom}->{class} = $class;
	$method  = $subcomponents{$type};
	next if  $type eq 'locus';
    }
    #This is for internal CSHL usage
    elsif($type =~ /snp/ && $doTSCSNP)
    {
	#print "  -got refSNP ID: $name, let's do TSC lookup\n";
	if(my $tscAttributes = &queryTSCdb($dbh,$name))
	{
	    $attributes .= qq/; IsTSC "1"/;
	    $FH{$chrom}->print(qq/$chrom\tTSC\tsnp\t$start\t$stop\t.\t$strand\t.\t$tscAttributes\n/);
	}
    }

    #Trying to work around the contig pile-up at the start of a chromosome 
    if($method eq 'contig' && $stop == 0)
    {
	print STDERR "SKIPPING, contig '$name' as stop = $stop and start = $start.\n";
    }

    #And finally print to the proper output stream
    $FH{$chrom}->print(qq/$chrom\t$source\t$method\t$start\t$stop\t.\t$strand\t.\t$attributes\n/);

    #Collect max coordinates, to deduce chromosome sizes
    $maxCoords{$chrom} ||= 0;
    $maxCoords{$chrom} = $stop if $stop > $maxCoords{$chrom};
    
    #Progress indicator
    if ( $i % 1000 == 0) 
    {
	print STDERR "$i features parsed...";
	print STDERR -t STDOUT && !$ENV{EMACS} ? "\r" : "\n";
    }
}#MAIN LOOP ENDS


#Print out group features like transcripts and genes that 
#were collected before and print to the proper output streams
foreach my $type(keys %groups)
{
    foreach my $name (keys %{$groups{$type}})
    {
	#print "\$name='$name'\n";
	foreach my $chrom(keys %{$groups{$type}->{$name}})
	{
	    my $start   = $groups{$type}->{$name}->{$chrom}->{start};
	    my $stop    = $groups{$type}->{$name}->{$chrom}->{stop};
	    my $db      = $groups{$type}->{$name}->{$chrom}->{db};
	    my $strand  = $groups{$type}->{$name}->{$chrom}->{strand};
	    my $method  = $groups{$type}->{$name}->{$chrom}->{method};
	    my $class   = $groups{$type}->{$name}->{$chrom}->{class};
	    my $source  = $groups{$type}->{$name}->{$chrom}->{source};
	    if($type eq 'locus' && $doLocuslink)
	    {
		my $llInfo = '';
		my $ll = $llData->{$name};
		my $id    = $ll->{id};
		my $note  = $ll->{desc} ? qq/Note "$ll->{desc}"/ : ' ';
		$note =~ s/;/\\;/g;
		$FH{$chrom}->print( qq/$chrom\t$source\t$method\t$start\t$stop\t.\t$strand\t.\tLocus "$name"; Name "$name"; $note\n/);
	    }
	    else
	    {
		$FH{$chrom}->print(qq/$chrom\t$source\t$method\t$start\t$stop\t.\t$strand\t.\t$class "$name"; Name "$name"\n/);
	    }
	}
    }
}

#Print a line for the reference sequences themselves
while(my ($chrom,$max) = each %maxCoords)
{
    $FH{$chrom}->print(qq/$chrom\tassembly\tchromosome\t1\t$max\t.\t+\t.\tSequence \"$chrom\"\n/);
}

print "DONE. $i features parsed\n\n";

exit 0;

#------------------------------------------------
# Subroutines
#------------------------------------------------

#For internal CSHL use. Queries our inhouse MySQL database with 
#SNP Consortium data for various auxiliary data on some SNPs
sub queryTSCdb
{
    my $dbh   = shift;
    my $rs_id = shift;
    my $attributes;
    $rs_id  =~ s/rs//;
    my $query = qq/SELECT td.*,a.snp_id,a.variation,a.institute_id,a.dbsnp_id,af.pop_type,i.institute_code from TBL_SNP_ALL a, tbl_tscid_2_dbsnpids td,TBL_INSTITUTE_INFO i  LEFT JOIN tbl_allele_freq af on af.snp_id=a.snp_id WHERE a.snp_id = td.tsc_id and td.rs_id=$rs_id and i.institute_id=a.institute_id limit 1/;
    my $tscInfo = $dbh->selectrow_hashref($query) || return undef;
    my $tsc_id = sprintf("TSC%7.7d", $tscInfo->{snp_id});
    my $var = $tscInfo->{variation};
    my $lab = $tscInfo->{institute_code};
    my $dbsnp_id = $tscInfo->{dbsnp_id};
    $attributes .= qq/SNP "$tsc_id"; Name "$tsc_id"/;
    $attributes .= qq/; Variation "$var"/ if $var;
    $attributes .= qq/; Laboratory "$lab"/ if $lab;
    $attributes .= qq/; DBSNP_ID "$dbsnp_id"/ if $dbsnp_id;
    $attributes .= qq/; IsAFP "1"/ if $tscInfo->{pop_type};
    #while(my($key,$val) = each %$tscInfo){print "  $key=>'$val'\n";}
    return  $attributes;
}

sub dbConnect
{
    my $dsn = shift;
    my $dbh;
    use DBI;
    eval{$dbh = DBI->connect($dsn,
			     {
				 RaiseError => 1,
				 FetchHashKeyName => 'NAME_lc',
			     }
                             )
         };
    if($@ || !$dbh)
    {
        print STDERR "ERROR, cannot connect to DB! $@\n";
        die $DBI::errstr;
    }
    return $dbh;
}

!NO!SUBS!
close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;
