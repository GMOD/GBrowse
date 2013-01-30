#!/usr/bin/perl

use strict;
use warnings;
use Carp 'croak';
use GBrowse::ConfigData;
use DBI;
use Bio::DB::Fasta;
use LWP::Simple 'mirror','is_error','is_success';
use File::Basename 'dirname';
use Getopt::Long;

use constant HOST=>'genome-mysql.cse.ucsc.edu';
use constant USER=>'genome';

my $host = HOST;
my $dbh  = DBI->connect(
    "DBI:mysql::host=$host;mysql_use_result=1",
    USER,'',
    {PrintError=>0,RaiseError=>0}
    );

my $USAGE = <<END;
Usage: $0 [options] <UCSC genome build> [<Description>]

Example: $0 hg19 'Human genome (hg19)'

This creates a framework data source for one of the genomes known to
the UCSC Genome Browser. You can then modify the data source
configuration file, add your own data, and so forth. Provide the name
of a UCSC genome build and optionally a description to display in
GBrowse.

To get started, find the desired data source by going to
http://genome.ucsc.edu/cgi-bin/hgGateway and using the "clade" and
"genome" menus to navigate to the desired species and build
number. You will find the data source name in the blue box below the
navigation controls. Look for something like this:

 D. melanogaster Genome Browser – dm3 assembly (sequences)

The data source name appears before the word "assembly", in this case
"dm3".

To get a list of all sources recognized by UCSC appears type:

 $0 --list

Options:
  --remove-chr Remove the 'chr' prefix from all chromosome names
  --list       List data sources
END
    ;

my ($REMOVE_CHR,$LIST);

GetOptions(
    'remove-chr'    => \$REMOVE_CHR,
    'list'          => \$LIST,
    ) or die $USAGE;

if ($LIST) {
    print_sources($dbh);
    exit -1;
}

my $dsn         = shift;
my $description = shift || "Imported $dsn genome from UCSC";

unless ($dsn) 
{    
    print STDERR "usage: $0 <UCSC data source name>\n";
    print STDERR "Run $0 --help for details.\n";
    print STDERR "Run $0 --list for list of data sources.\n";
    exit -1;
} else {
    $dbh->do("use $dsn") or die "Could not access $dsn database. Run this script with --list to see valid database names.\n";
}

my $conf_dir = GBrowse::ConfigData->config('conf');
my $data_dir = GBrowse::ConfigData->config('databases');

print STDERR "** During database creation, you may be asked for your password in order to set file permissions correctly.\n\n";

my $dir       = create_database_dir($data_dir,$dsn);
my $scaffolds = create_scaffold_db($dir,$dsn);
my $genes     = create_gene_db($dir,$dsn);
create_conf_file($conf_dir,$dsn,$description,$scaffolds,$genes);
create_source($conf_dir,$dsn,$description);

print STDERR <<END;

** These files have been created for you:

 $scaffolds -- database of chromosome sizes and sequences
 $genes -- database of genes
 $conf_dir/${dsn}.conf -- track configuration file for these databases
 $conf_dir/GBrowse.conf -- updated data source configuration file
END
    ;

if (-x '/usr/sbin/service') {
    print STDERR "\n ** Restarting apache. You may be asked for your password.\n";
    system "sudo service apache2 restart";
} elsif (-x '/etc/init.d/apache2') {
    print STDERR "\n ** Restarting apache. You may be asked for your password.\n";
    system "sudo /etc/init.d/apache2 restart";
} else {
    print STDERR "\n** Please restart apache or other web server.\n";
}

1;

exit 0;

sub print_sources {
    my $dbh = shift;
    my $s = $dbh->selectcol_arrayref('show databases');
    print STDERR join("\n",grep {!/information_schema/} @$s),"\n";
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

    my $query = $dbh->prepare('select chrom,size from chromInfo order by size')
	or die $dbh->errstr;
    $query->execute;
    my @chroms;
    while (my($chrom,$size) = $query->fetchrow_array) {
	$chrom =~ s/^chr// if $REMOVE_CHR;
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
    $ENV{FTP_PASSIVE}=1 unless exists $ENV{FTP_PASSIVE};
    my $prefix = $REMOVE_CHR ? 'chr' : '';
    for my $chr (sort @chroms) {
	my $url  = "ftp://hgdownload.cse.ucsc.edu/goldenPath/$dsn/chromosomes/$prefix$chr.fa.gz";
	my $file = "$path/$prefix$chr.fa.gz";
	print STDERR "$chr...";
	my $code = mirror($url=>$file);
	warn "Fetch of $url returned error code $code\n"
	    if is_error($code);
    }
    print STDERR "done\n";
    print STDERR "Unpacking FASTA files...";
    unlink "$path/chromosomes.fa";
    for my $chr (sort @chroms) {
	my $command = $REMOVE_CHR ? "gunzip -c $path/$prefix$chr.fa.gz | perl -p -e 's/^>chr/>/' >> $path/chromosomes.fa"
	                          : "gunzip -c $path/$prefix$chr.fa.gz >> $path/chromosomes.fa"
	    unless -e "$path/$chr.fa" && -M "$path/chromosomes.fa" > -M "$path/$prefix$chr.fa.gz";
	system $command;
    }
    print STDERR "done\n";

    print STDERR "Creating FASTA index...";
    my $index = Bio::DB::Fasta->new($path) or die "Couldn't create index";
    print "done\n";

    my $wwwuser = GBrowse::ConfigData->config('wwwuser');
    system "sudo chown -R $wwwuser $path";
    return $path;
}

sub create_gene_db {
    my ($dir,$dsn) = @_;
    my $path = "$dir/refGenes";
    mkdir $path unless -e $path;

    my $src_path = "$path/genes.gff3";
    my $db_path = "$path/genes.sqlite";

    open my $db,'>',$src_path or die "$path: $!";
    print $db <<END;
##gff-version 3

END
    print STDERR "Fetching genes...";
    my $query;
    eval {
	$query = $dbh->prepare('select * from refFlat order by geneName') or die $dbh->errstr;
	$query->execute or die $dbh->errorstr;
    } || eval {
	$query = $dbh->prepare('select name2,name,chrom,strand,txStart,txEnd,cdsStart,cdsEnd,exonCount,exonStarts,exonEnds from ensGene order by name2') or die $dbh->errstr;
	$query->execute or die $dbh->errorstr;
    };
    die $@ if $@;
    my $writer = GFFWriter->new($db,$dsn);
    while (my $row = $query->fetchrow_arrayref) {
	$writer->write_transcript($row);
    }
    $query->finish;
    $writer->finish;
    print STDERR "done\n";

    close $db;

    print STDERR "Indexing...";
    system "bp_seqfeature_load.pl -f -c -a DBI::SQLite -d $db_path $src_path";
    print STDERR "done\n";

    return $db_path;
}

sub log10 { log(shift())/log(10)}

sub create_conf_file {
    my ($conf_dir,$dsn,$description,$scaffolds,$genes) = @_;
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
    for (my $i=6; $i<=$log; $i++) {
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
description   = $description
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
feature      = gene
glyph        = gene
bgcolor      = sub {shift->strand > 0 ? 'red' : 'blue'}
label_transcripts = 1
label        = sub { my \$f = shift;
                     my \$name = \$f->display_name;
                     my \@aliases = sort \$f->attributes('Alias');
                     \$name .= " (\@aliases)" if \@aliases;
		     \$name;
  } 
height       = 10
description  = 0
key          = Known Genes

[Genes:200000]
glyph        = box
stranded     = 1

[Genes:500000]
glyph        = box
bump         = 0

[ncRNA]
database     = genes
feature       = noncoding_transcript
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

[CDS:200000]
glyph        = box
stranded     = 1

[Translation]
glyph        = translation
global feature = 1
database     = scaffolds
height       = 40
fgcolor      = purple
strand       = +1
translation  = 6frame
key          = 6-frame translation

[Translation:1000000]
hide = 1

[TranslationF]
glyph        = translation
global feature = 1
database     = scaffolds
height       = 20
fgcolor      = purple
strand       = +1
translation  = 3frame
key          = 3-frame translation (forward)

[TranslationF:1000000]
hide = 1

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

[DNA/GC Content:1000000]
hide = 1

[TranslationR]
glyph        = translation
global feature = 1
database     = scaffolds
height       = 20
fgcolor      = blue
strand       = -1
translation  = 3frame
key          = 3-frame translation (reverse)

[TranslationR:1000000]
hide = 1

END
    close $fh3;
}

sub create_source {
    my ($conf_dir,$dsn,$description) = @_;
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
description = $description
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

package GFFWriter;

sub new {
    my $class = shift;
    my ($fh,$dsn)  = @_;
    return bless {
	fh => $fh,
	dsn => $dsn,
	gene_id        => 'g000000',
	transcript_id  => 't00000',
	last_gene_name => '',
	last_gene_id   => '',
	last_gene      => {},
    },ref $class || $class;
}

# This subroutine is amazingly long and complicated looking, but probably correct
sub write_transcript {
    my $self = shift;
    my $fields = shift;

    my ($gene_name,$accession,$chrom,$strand,$txStart,$txEnd,$cdsStart,$cdsEnd,$exons,$exonStarts,$exonEnds) = @$fields;
    my ($utr5_start,$utr5_end,$utr3_start,$utr3_end,$gid,$tid);
    $gene_name ||= $accession;
    $chrom =~ s/^chr// if $REMOVE_CHR;

    if ($self->{last_gene_name} ne $gene_name
	||
	$self->{last_gene}{chr} ne $chrom                      # avoid some gene name collisions
	||
	abs($self->{last_gene}{start} - $txStart) > 6_000_000  # avoid some gene name collisions
	||
	$self->{last_gene}{strand} ne $strand) 
    {
	$self->write_last_gene;
	$self->{last_gene}           = {};
	$self->{last_gene_name}      = '';
	$gid = $self->{last_gene_id} = $self->{gene_id}++;
    } elsif ($self->{last_gene_id}) {
	$gid = $self->{last_gene_id};
    } else {
	$gid = $self->{last_gene_id} = $self->{gene_id}++;
    }

    $tid = $self->{transcript_id}++;

    my $ORIGIN = 1;
    my $SRC    = $self->{dsn};
    my $fh     = $self->{fh};

    # adjust for Jim's 0-based coordinates
    $txStart++;
    $cdsStart++;

    $txStart  -= $ORIGIN;
    $txEnd    -= $ORIGIN;
    $cdsStart -= $ORIGIN;
    $cdsEnd   -= $ORIGIN;

    # this is how noncoding genes are expressed (?!!!)
    my $is_noncoding = $cdsStart >= $cdsEnd;

    unless ($is_noncoding) {
	$self->{last_gene_name}     ||= $gene_name;
	$self->{last_gene}{chr}     ||= $chrom;
	$self->{last_gene}{strand}  ||= $strand;
	$self->{last_gene}{start}     = $txStart if !$self->{last_gene}{start} || $self->{last_gene}{start} > $txStart;
	$self->{last_gene}{end}       = $txEnd   if !$self->{last_gene}{end}   || $self->{last_gene}{end}   < $txEnd;
    }

    # print the transcript
    my $id = $is_noncoding ? "ID=$tid;Name=$gene_name;Alias=$accession" : "ID=$tid;Name=$accession;Parent=$gid";
    print $fh join
	("\t",$chrom,$SRC,($is_noncoding ? 'noncoding_transcript' : 'mRNA'),$txStart,$txEnd,'.',$strand,'.',$id),"\n";

    # now handle the CDS entries -- the tricky part is the need to keep
    # track of phase
    my $phase = 0;
    my @exon_starts = map {$_-$ORIGIN} split ',',$exonStarts;
    my @exon_ends   = map {$_-$ORIGIN} split ',',$exonEnds;

    if ($is_noncoding) {
	for (my $i=0;$i<@exon_starts;$i++) {  # for each exon start
	    print $fh join("\t",
			   $chrom,$SRC,'exon',$exon_starts[$i],$exon_ends[$i],'.',$strand,'.',"Parent=$tid"
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
			("\t",$chrom,$SRC,"five_prime_UTR",$utr_start[$i],$utr_end[$i],'.',$strand,'.',"Parent=$tid"),"\n"	
		} # end of if	    
	    } # end of foreach
	    
	    if (defined $cds_start && $cds_start <= $cds_end) {
		print $fh join
		    ("\t",$chrom,$SRC,'CDS',$cds_start,$cds_end,'.',$strand,$phase,"Parent=$tid"),"\n";
		$phase = (($cds_end-$cds_start+1-$phase)) % 3;
	    }
	    
	    for (my $i=0;$i<@utr_start;$i++) {  # for each utr start
		if (defined $utr_start[$i] && $utr_start[$i] <= $utr_end[$i] &&
		    $utr_start[$i] > $cdsEnd) {
		    print $fh join ("\t",$chrom,$SRC,"three_prime_UTR",,$utr_start[$i],
				$utr_end[$i],'.',$strand,'.',"Parent=$tid"),"\n"	
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
			("\t",$chrom,$SRC,"five_prime_UTR",,$utr_start[$i],$utr_end[$i],'.',$strand,'.',"Parent=$tid"),"\n"	
		}
	    } # end of for

	    if (defined $cds_start && $cds_start <= $cds_end) {
		unshift @lines,join
		    ("\t",$chrom,$SRC,'CDS',$cds_start,$cds_end,'.',$strand,$phase,"Parent=$tid"),"\n";
		$phase = (($cds_end-$cds_start+1-$phase)) % 3;
	    }
	    
	    for (my $i=0;$i<@utr_start;$i++) {  # for each utr start
		if (defined $utr_start[$i] && $utr_start[$i] <= $utr_end[$i] &&
		    $utr_end[$i] < $cdsStart) {
		    unshift @lines,join
			("\t",$chrom,$SRC,"three_prime_UTR",$utr_start[$i],$utr_end[$i],'.',$strand,'.',"Parent=$tid"),"\n"	
		}
	    } # end for
	}
	print $fh @lines;
    }
}


sub write_last_gene {
    my $self = shift;
    my $name   = $self->{last_gene_name} or return;
    my $chr    = $self->{last_gene}{chr};
    my $start  = $self->{last_gene}{start};
    my $end    = $self->{last_gene}{end};
    my $strand = $self->{last_gene}{strand};
    my $id     = $self->{last_gene_id};
    my $fh     = $self->{fh};
    print $fh join("\t",
		   $chr,
		   $self->{dsn},
		   'gene',
		   $start,
		   $end,
		   '.',
		   $strand,
		   '.',
		   "ID=$id;Name=$name"),"\n";
    $self->{last_gene_name} = ''; 
}

sub finish { 
    my $self = shift;
    $self->write_last_gene if defined fileno($self->{fh});
}
sub DESTROY { shift->finish         }
