#!/usr/bin/perl

# $Id: gtf2gff3.pl,v 1.1 2009-06-16 15:26:37 lstein Exp $
# transform a GTF file into GFF3

use strict;
use warnings;
use Text::ParseWords 'shellwords';

my %GENES;

while (<>) {
    chomp;
    my ($seqid,$source,$method,$start,$end,$score,$strand,$phase,$tags) = split "\t";
    $tags    =~ s/note (.+)/Note "$1"/;
    my %tags = shellwords($tags);

    # figure out what the primary ID and parent are
    my $id     =  $method eq 'transcript'  ? $tags{transcript_id} : undef;
    my $parent =  $method eq 'transcript'  ? $tags{gene_id}
                 :$method eq 'CDS'         ? $tags{transcript_id}
                 :$method eq 'exon'        ? $tags{transcript_id}
                 :$method eq 'start_codon' ? $tags{transcript_id}
                 :$method eq 'stop_codon'  ? $tags{transcript_id}
                 :undef;
    my $name   =  $method eq 'transcript'  ? $tags{transcript_name} : undef;

    # implicit genes
    if ($method eq 'transcript') {
	my $gene_id = $tags{gene_id};
	$GENES{$gene_id}{seqid}      ||= $seqid;
	$GENES{$gene_id}{source}     ||= $source;
	$GENES{$gene_id}{method}     ||= 'gene';
	$GENES{$gene_id}{start}      = $start 
	    if !defined $GENES{$gene_id}{start} || $GENES{$gene_id}{start} > $start;
	$GENES{$gene_id}{end}        = $end 
	    if !defined $GENES{$gene_id}{end}   || $GENES{$gene_id}{end} < $end;
	$GENES{$gene_id}{score}    ||= $score;
	$GENES{$gene_id}{strand}   ||= $strand;
	$GENES{$gene_id}{phase}    ||= $phase;
	$GENES{$gene_id}{name}     ||= $tags{gene_name};

	$GENES{$gene_id}{attributes} ||= { map { /transcript/ ? () : ($_ => $tags{$_}) } keys %tags};
    }

    my %gff3_tags  = $method eq 'transcript' 
                             ? map { /transcript|level/ ? ($_ => $tags{$_}) : () } keys %tags 
                             : ();

    my $attributes;
    $attributes  .= "ID=$id;"         if defined $id;
    $attributes  .= "Parent=$parent;" if defined $parent;
    $attributes  .= "Name=$name;"     if defined $name;
    $attributes  .= join ';',map {"$_=$gff3_tags{$_}"} keys %gff3_tags;

    print join("\t",$seqid,$source,$method,$start,$end,$score,$strand,$phase,$attributes),"\n";
}

# now print the genes
for my $gene_id (sort keys %GENES) {
    my $gene = $GENES{$gene_id};
    my $tags = $gene->{attributes};
    my $attributes;
    $attributes .= "ID=$gene_id;";
    $attributes .= "Name=$gene->{name};" if defined $gene->{name};
    $attributes .= join ';',map {"$_=$tags->{$_}"} keys %$tags;
    print join("\t",
	       $gene->{seqid},
	       $gene->{source},
	       $gene->{method},
	       $gene->{start},
	       $gene->{end},
	       $gene->{score},
	       $gene->{strand},
	       $gene->{phase},
	       $attributes),"\n";
}


exit 0;
