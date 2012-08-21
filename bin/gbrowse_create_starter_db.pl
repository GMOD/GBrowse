#!/usr/bin/perl

use strict;
use warnings;
use Carp 'croak';
use GBrowse::ConfigData;
use DBI;
use Bio::DB::Fasta;
use LWP::Simple 'mirror','is_error','is_success';

use constant HOST=>'genome-mysql.cse.ucsc.edu';
use constant USER=>'genome';

my $host = HOST;
my $dbh  = DBI->connect(
    "DBI:mysql::host=$host;mysql_use_result=1",
    USER,'',
    {PrintError=>0,RaiseError=>0}
    );

my $dsn = shift;
unless ($dsn) {
    print STDERR "usage: $0 <UCSC data source name>\n";
    print STDERR "Available sources:\n";
    print_sources($dbh);
    exit -1;
} else {
    $dbh->do("use $dsn") or die "Could not access $dsn database. Run this script without arguments to see valid database names.\n";
}

my $conf_dir = GBrowse::ConfigData->config('conf');
my $data_dir = GBrowse::ConfigData->config('databases');

my $dir       = create_database_dir($data_dir,$dsn);
my $scaffolds = create_scaffold_db($dir,$dsn);
my $genes     = create_gene_db($dir,$dsn);
create_conf_file($conf_dir,$dsn,$scaffolds,$genes);
create_source($conf_dir,$dsn);

1;

exit 0;

sub print_sources {
    my $dbh = shift;
    my $s = $dbh->selectcol_arrayref('show databases');
    print STDERR join "\n",@$s;
}

sub create_database_dir {
    my ($data_dir,$dsn) = @_;
    my $uid   = $<;
    my ($gid) = $( =~ /^(\d+)/;
    my $dir = "$data_dir/$dsn";
    unless (-d $dir) {
	print STDERR "Creating database directory for $dsn. You may be prompted for your password.\n";
	system "sudo mkdir -p $dir";
    }
    unless (-w $dir) {
	system "sudo chown $uid $dir";
	system "sudo chgrp $gid $dir";
    }
    return $dir;
}

sub create_scaffold_db {
    my ($dir,$dsn) = @_;
    my $path = "$dir/chromosomes";
    mkdir $path unless -e $path;
    open my $db,">$path/chrom_sizes.gff3" or die "$path: $!";
    print $db <<END;
##gff-version 3

END

    print STDERR "Fetching chromosome sizes...\n";

    my $query = $dbh->prepare('select chrom,size from chromInfo')
	or die $dbh->errstr;
    $query->execute;
    my @chroms;
    while (my($chrom,$size) = $query->fetchrow_array) {
	print $db join("\t",
		      $chrom,
		      $dsn,
		      'chromosome',
		      1,
		      $size,
		      '.','.','.',
		      "ID=$chrom;Name=$chrom"),"\n";
	push @chroms,$chrom;
    }
    $query->finish;
    close $db;

    print STDERR "Fetching FASTA files...";
    for my $chr (@chroms) {
	my $url  = "ftp://hgdownload.cse.ucsc.edu/goldenPath/$dsn/chromosomes/$chr.fa.gz";
	my $file = "$path/$chr.fa.gz";
	print STDERR "$chr...";
	my $code = mirror($url=>$file);
	warn "Fetch of $url returned error code $code\n"
	    unless is_success($code);
    }
    print STDERR "done\n";
    print STDERR "Unpacking FASTA files...";
    for my $chr (sort @chroms) {
	system "gunzip -f $path/$chr.fa.gz";
    }

    print STDERR "done\n";
    print STDERR "Creating FASTA index...";
    my $index = Bio::DB::Fasta->new($path) or die "Couldn't create index";
    print "done\n";

    return $path;
}

sub create_gene_db {
    my ($dir,$dsn) = @_;
    my $path = "$dir/refGenes";
    mkdir $path unless -e $path;
    open my $db,">$path/genes.gff3" or die "$path: $!";
    print $db <<END;
##gff-version 3

END
    print STDERR "Fetching genes...";
    my $query = $dbh->prepare('select * from refFlat')
	or die $dbh->errstr;
    $query->execute;
    while (my $row = $query->fetchrow_arrayref) {
	write_transcript($db,$row);
    }
    $query->finish;
    print STDERR "done\n";

    close $db;
}

sub write_transcript {
    my ($fh,$fields) = @_;

    my ($name,$id,$chrom,$strand,$txStart,$txEnd,$cdsStart,$cdsEnd,$exons,$exonStarts,$exonEnds) = @$fields;
    my ($utr5_start,$utr5_end,$utr3_start,$utr3_end);

    # adjust for Jim's 0-based coordinates
    my $ORIGIN = 1;
    my $SRC    = $dsn;

    $txStart++;
    $cdsStart++;

    $txStart  -= $ORIGIN;
    $txEnd    -= $ORIGIN;
    $cdsStart -= $ORIGIN;
    $cdsEnd   -= $ORIGIN;

    # print the transcript
    print $fh join
	("\t",$chrom,$SRC,'mRNA',$txStart,$txEnd,'.',$strand,'.',"ID=$id;Name=$name"),"\n";

    # now handle the CDS entries -- the tricky part is the need to keep
    # track of phase
    my $phase = 0;
    my @exon_starts = map {$_-$ORIGIN} split ',',$exonStarts;
    my @exon_ends   = map {$_-$ORIGIN} split ',',$exonEnds;

    if ($strand eq '+') {
	for (my $i=0;$i<@exon_starts;$i++) {  # for each exon start
	    my $exon_start = $exon_starts[$i] + 1;
	    my $exon_end   = $exon_ends[$i];
	    my (@utr_start,@utr_end,$cds_start,$cds_end);
	    
	    if ($exon_start < $cdsStart) { # in a 5' UTR
		push (@utr_start, $exon_start);
	    } elsif ($exon_start > $cdsEnd) { 
		push (@utr_start, $exon_start);
	    } else {
		$cds_start = $exon_start;
	    }
	    
	    if ($exon_end < $cdsStart) {
		push (@utr_end, $exon_end);
	    } elsif ($exon_end > $cdsEnd) {
		push (@utr_end, $exon_end);
	    } else {
		$cds_end = $exon_end;
	    }
	    
	    if ($utr_start[0] && !$utr_end[0]) { # half in half out on 5' end
		$utr_end[0]= $cdsStart - 1;
		$cds_start = $cdsStart;
		$cds_end   = $exon_end;
	    }

	    if ($utr_end[0] && !$utr_start[0]) { # half in half out on 3' end
		$utr_start[0]= $cdsEnd + 1;
		$cds_end     = $cdsEnd;
		$cds_start   = $exon_start;
	    }

	    # If the CDS is within the exon
	    if (defined $utr_start[0] == defined $utr_end[0] && 
		$utr_start[0] < $cdsStart && $utr_end[0] > $cdsEnd) {
		$utr_end[0]= $cdsStart - 1;
		$cds_start = $cdsStart;
		$cds_end   = $cdsEnd;
	
		push (@utr_start, $cdsEnd + 1);
		push (@utr_end,   $exon_end);
	    }

	    die "programmer error, not an even number of utr_starts and utr_ends"
		unless $#utr_start == $#utr_end;
	    die "programmer error, cds_start and no cds_end" 
		unless defined $cds_start == defined $cds_end;

	    for (my $i=0;$i<@utr_start;$i++) {  # for each utr start
		if (defined $utr_start[$i] && $utr_start[$i] <= $utr_end[$i] &&
		    $utr_start[$i] < $cdsStart) {
		    print $fh join
			("\t",$chrom,$SRC,"five_prime_UTR",$utr_start[$i],$utr_end[$i],'.',$strand,'.',"Parent=$id"),"\n"	
		} # end of if	    
	    } # end of foreach
	    
	    if (defined $cds_start && $cds_start <= $cds_end) {
		print $fh join
		    ("\t",$chrom,$SRC,'CDS',$cds_start,$cds_end,'.',$strand,$phase,"Parent=$id"),"\n";
		$phase = (($cds_end-$cds_start+1-$phase)) % 3;
	    }
	    
	    for (my $i=0;$i<@utr_start;$i++) {  # for each utr start
		if (defined $utr_start[$i] && $utr_start[$i] <= $utr_end[$i] &&
		    $utr_start[$i] > $cdsEnd) {
		    print $fh join ("\t",$chrom,$SRC,"three_prime_UTR",,$utr_start[$i],
				$utr_end[$i],'.',$strand,'.',"Parent=$id"),"\n"	
		}
	    }
	} # end of for each exon
    } # matches if strand = +
    
    if ($strand eq '-') {
	my @lines;
	for (my $i=@exon_starts-1; $i>=0; $i--) { # count backwards
	    my $exon_start = $exon_starts[$i] + 1;
	    my $exon_end   = $exon_ends[$i];
	    my (@utr_start,@utr_end,$cds_start,$cds_end);
	    
	    if ($exon_end > $cdsEnd) { # in a 5' UTR
		push (@utr_end,  $exon_end);
	    } elsif ($exon_end < $cdsStart) {
		push (@utr_end,  $exon_end);
	    } else {
		$cds_end = $exon_end;
	    }

	    if ($exon_start > $cdsEnd) {
		push (@utr_start, $exon_start);
	    } elsif ($exon_start < $cdsStart) {
		push (@utr_start, $exon_start);
	    } else {
		$cds_start = $exon_start;
	    }

	    if ($utr_start[0] && !$utr_end[0]) { # half in half out on 3' end
		$utr_end[0]   = $cdsStart - 1;
		$cds_start = $cdsStart;
		$cds_end   = $exon_end;
	    }

	    if ($utr_end[0] && !$utr_start[0]) { # half in half out on 5' end
		$utr_start[0] = $cdsEnd + 1;
		$cds_end   = $cdsEnd;
		$cds_start = $exon_start;
	    }

	    # If the CDS is within the exon  
	    if (defined $utr_start[0] == defined $utr_end[0] && 
		$utr_start[0] < $cdsStart && $utr_end[0] > $cdsEnd) {
		$utr_end[0]= $cdsStart - 1;
		$cds_start = $cdsStart;
		$cds_end   = $cdsEnd;
	
		push (@utr_start, $cdsEnd + 1);
		push (@utr_end, $exon_end);
	    }
	    
	    die "programmer error, not an even number of utr_starts and utr_ends"
		unless $#utr_start == $#utr_end;

	    die "programmer error, cds_start and no cds_end" unless defined
		$cds_start == defined $cds_end;
	    
	    for (my $i=0;$i<@utr_start;$i++) {  # for each utr start
		if (defined $utr_start[$i] && $utr_start[$i] <= $utr_end[$i] &&
		    $utr_start[$i] > $cdsEnd) {
		    unshift @lines,join
			("\t",$chrom,$SRC,"five_prime_UTR",,$utr_start[$i],$utr_end[$i],'.',$strand,'.',"Parent=$id"),"\n"	
		}
	    } # end of for

	    if (defined $cds_start && $cds_start <= $cds_end) {
		unshift @lines,join
		    ("\t",$chrom,$SRC,'CDS',$cds_start,$cds_end,'.',$strand,$phase,"Parent=$id"),"\n";
		$phase = (($cds_end-$cds_start+1-$phase)) % 3;
	    }
	    
	    for (my $i=0;$i<@utr_start;$i++) {  # for each utr start
		if (defined $utr_start[$i] && $utr_start[$i] <= $utr_end[$i] &&
		    $utr_end[$i] < $cdsStart) {
		    unshift @lines,join
			("\t",$chrom,$SRC,"three_prime_UTR",$utr_start[$i],$utr_end[$i],'.',$strand,'.',"Parent=$id"),"\n"	
		}
	    } # end for
	}
	print $fh @lines;
    }
}

