#!/usr/bin/perl

use strict;
use warnings;
use Carp 'croak';
use GBrowse::ConfigData;
use DBI;
use Bio::DB::Fasta;
use LWP::Simple 'mirror','is_error','is_success';
use File::Basename 'dirname';

use constant HOST=>'genome-mysql.cse.ucsc.edu';
use constant USER=>'genome';
my $FEATURE_ID;

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

print STDERR "** During database creation, you may be asked for your password in order to set file permissions correctly.\n\n";

my $dir       = create_database_dir($data_dir,$dsn);
my $scaffolds = create_scaffold_db($dir,$dsn);
my $genes     = create_gene_db($dir,$dsn);
create_conf_file($conf_dir,$dsn,$scaffolds,$genes);
create_source($conf_dir,$dsn);

print STDERR <<END;

** These files have been created for you:

 $scaffolds -- database of chromosome sizes and sequences
 $genes -- database of genes
 $conf_dir/${dsn}.conf -- track configuration file for these databases
 $conf_dir/GBrowse.conf -- updated data source configuration file
END
    ;

print STDERR "\n** Please restart apache using 'sudo service apache2 restart' or 'sudo /etc/init.d/apache2 restart'\n";

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
	    if is_error($code);
    }
    print STDERR "done\n";
    print STDERR "Unpacking FASTA files...";
    for my $chr (sort @chroms) {
	system "gunzip -c $path/$chr.fa.gz > $path/$chr.fa"
	    unless -e "$path/$chr.fa" && -M "$path/$chr.fa" > -M "$path/$chr.fa.gz";
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

    my $src_path = "$path/genes.gff3";
    my $db_path = "$path/genes.sqlite";
    return $db_path if -e $db_path;

    open my $db,'>',$src_path or die "$path: $!";
    print $db <<END;
##gff-version 3

END
    print STDERR "Fetching genes...";
    my $query = $dbh->prepare('select * from refFlat')
	or die $dbh->errstr;
    $query->execute;
    $FEATURE_ID='f0000';
    while (my $row = $query->fetchrow_arrayref) {
	write_transcript($db,$row);
    }
    $query->finish;
    print STDERR "done\n";

    close $db;

    print STDERR "Indexing...";
    system "bp_seqfeature_load.pl -f -c -a DBI::SQLite -d $db_path $src_path";
    print STDERR "done\n";

    return $db_path;
}

# This subroutine is amazingly long and complicated looking.
# It can't be correct... can it?
sub write_transcript {
    my ($fh,$fields) = @_;

    my ($name1,$name2,$chrom,$strand,$txStart,$txEnd,$cdsStart,$cdsEnd,$exons,$exonStarts,$exonEnds) = @$fields;
    my ($utr5_start,$utr5_end,$utr3_start,$utr3_end);
    my $id = $FEATURE_ID++;

    # adjust for Jim's 0-based coordinates
    my $ORIGIN = 1;
    my $SRC    = $dsn;

    $txStart++;
    $cdsStart++;

    $txStart  -= $ORIGIN;
    $txEnd    -= $ORIGIN;
    $cdsStart -= $ORIGIN;
    $cdsEnd   -= $ORIGIN;

    # this is how noncoding genes are expressed (?!!!)
    my $is_noncoding = $cdsStart >= $cdsEnd;

    # print the transcript
    print $fh join
	("\t",$chrom,$SRC,($is_noncoding ? 'ncRNA' : 'mRNA'),$txStart,$txEnd,'.',$strand,'.',"ID=$id;Name=$name1;Alias=$name2"),"\n";

    # now handle the CDS entries -- the tricky part is the need to keep
    # track of phase
    my $phase = 0;
    my @exon_starts = map {$_-$ORIGIN} split ',',$exonStarts;
    my @exon_ends   = map {$_-$ORIGIN} split ',',$exonEnds;

    if ($is_noncoding) {
	for (my $i=0;$i<@exon_starts;$i++) {  # for each exon start
	    print $fh join("\t",
			   $chrom,$SRC,'exon',$exon_starts[$i],$exon_ends[$i],'.',$strand,'.',"Parent=$id"
		),"\n";
	}
    }

    elsif ($strand eq '+') {
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
	    if ($utr_start[0] && $utr_end[0] && 
		$utr_start[0] < $cdsStart && 
		$utr_end[0] > $cdsEnd) 
	    {
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
    
    elsif ($strand eq '-') {
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
	    if ($utr_start[0] && 
		$utr_end[0]   && 
		$utr_start[0] < $cdsStart && 
		$utr_end[0] > $cdsEnd) 
	    {
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

sub log10 { log(shift())/log(10)}

sub create_conf_file {
    my ($conf_dir,$dsn,$scaffolds,$genes) = @_;
    my $conf_path = "$conf_dir/${dsn}.conf";
    create_writable_file($conf_path);

    # figure size of chromosomes
    open my $fh1,"$scaffolds/chrom_sizes.gff3" or die "$scaffolds/chrom_sizes.gff3: $!";
    my $max_chrom = 0;
    my ($first_chrom,$first_size);
    while (<$fh1>) {
	my ($chr,undef,undef,undef,$size) = split /\s+/;
	next unless $size;
	$max_chrom = $size if $max_chrom < $size;
	$first_chrom ||= $chr;
	$first_size  ||= $size;
    }
    close $fh1;

    # from the max chromosome, figure out reasonable default sizes and zoom levels
    my $log             = int log10($max_chrom);
    my $max_segment     = $max_chrom;
    my $default_segment = 10**($log-3);
    my $region_segment  = $default_segment*10;
    my @zoom_levels     = qw(100 200 1000 2000 5000 10000 20000 50000 100000 200000 500000);
    for (my $i=6; $i<$log; $i++) {
	push @zoom_levels,10**$i;
    }
    my @region_sizes    = @zoom_levels;
    my $default_region  = $default_segment * 10;
    my $summary_boundary= $default_segment * 100;

    my $start = int(rand($first_size));
    my $end   = $start + $default_segment -1;
    my $initial_landmark = "$first_chrom:$start..$end";

    # pick some random examples from the gff3 file
    my @names;
    my $dir = dirname($genes);
    open my $fh2,"$dir/genes.gff3" or die "$dir/genes.gff3: $!";
    while (<$fh2>) {
	my ($name) = /Name=([^;]+)/ or next;
	for (0..3) {
	    $names[$_] = $name if rand($.) < 4;
	}
    }
    close $fh2;
    my $examples = "@names";

    open my $fh3,'>',$conf_path or die "$conf_path: $!";
    print $fh3 <<END;
[GENERAL]
description   = Starter genome from UCSC $dsn
database      = scaffolds

initial landmark = $initial_landmark
plugins       = FilterTest RestrictionAnnotator TrackDumper FastaDumper
autocomplete  = 1

default tracks = Genes ncRNA

# examples to show in the introduction
examples = $examples

# "automatic" classes to try when an unqualified identifier is given
automatic classes = Gene

# Limits on genomic regions (can be overridden in datasource config files)
region segment         = $region_segment
max segment            = $max_segment
default segment        = $default_segment
default region         = $default_region
zoom levels            = @zoom_levels
region sizes           = @region_sizes

#################################
# database definitions
#################################

[scaffolds:database]
db_adaptor    = Bio::DB::SeqFeature::Store
db_args       = -adaptor memory
                -dir    $scaffolds
search options = default +autocomplete

[genes:database]
db_adaptor    = Bio::DB::SeqFeature::Store
db_args       = -adaptor DBI::SQLite
                -dsn    $genes
search options = default +autocomplete

# Default glyph settings
[TRACK DEFAULTS]
glyph       = generic
database    = scaffolds
height      = 8
bgcolor     = green
fgcolor     = black
label density = 25
bump density  = 100
show summary  = $summary_boundary

### TRACK CONFIGURATION ####
# the remainder of the sections configure individual tracks

[Genes]
database     = genes
feature      = mRNA
glyph        = gene
bgcolor      = blue
forwardcolor = red
reversecolor = blue
label        = sub { my \$f = shift;
                     my \$name = \$f->display_name;
                     my \@aliases = sort \$f->attributes('Alias');
                     \$name .= " (\@aliases)" if \@aliases;
		     \$name;
  } 
height       = 8
description  = 0
key          = Known Genes

[ncRNA]
database     = genes
feature       = ncRNA
fgcolor       = orange
glyph         = generic
description   = 1
key           = Noncoding RNAs

[CDS]
database     = genes
feature      = mRNA
glyph        = cds
description  = 0
height       = 26
sixframe     = 1
label        = sub {shift->name . " reading frame"}
key          = CDS
citation     = This track shows CDS reading frames.

[Translation]
glyph        = translation
global feature = 1
database     = scaffolds
height       = 40
fgcolor      = purple
strand       = +1
translation  = 6frame
key          = 6-frame translation

[TranslationF]
glyph        = translation
global feature = 1
database     = scaffolds
height       = 20
fgcolor      = purple
strand       = +1
translation  = 3frame
key          = 3-frame translation (forward)

[DNA/GC Content]
glyph        = dna
global feature = 1
database     = scaffolds
height       = 40
do_gc        = 1
gc_window    = auto
strand       = both
fgcolor      = red
axis_color   = blue

[TranslationR]
glyph        = translation
global feature = 1
database     = scaffolds
height       = 20
fgcolor      = blue
strand       = -1
translation  = 3frame
key          = 3-frame translation (reverse)

END
    close $fh3;
}

sub create_source {
    my ($conf_dir,$dsn) = @_;
    my $path = "$conf_dir/GBrowse.conf";
    open my $fh,$path or die "$path: $!";
    my $foundit;
    while (<$fh>) {
	$foundit++ if /\[$dsn\]/;
    }
    close $fh;
    return if $foundit;

    create_writable_file($path);
    open my $fh2,'>>',$path or die "$path: $!";
    print $fh2 "\n";
    print $fh2 <<END;
[$dsn]
description = Starter genome from UCSC $dsn
path        = $conf_dir/${dsn}.conf
END
    ;
    close $fh2;
}

sub create_writable_file {
    my $file = shift;
    return if -e $file && -w $file;

    my $uid   = $<;
    my ($gid) = $( =~ /^(\d+)/;
    system "sudo touch $file";
    system "sudo chown $uid $file";
    system "sudo chgrp $gid $file";
    system "chmod +w $file";
}
