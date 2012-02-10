#!/usr/bin/perl

=head1 NAME

axt2phy.pl - convert AXT pairwise alignment files to GFF, Fasta and wig files

=head1 SYNOPSYS

  % axt2phy.pl -species speciesname -axtin AXTinputfile

=head1 DESCRIPTION

This program reads an AXT pairwise alignment file and creates
the GFF, Fasta and binary wig files to be used for the phylogenetic
glyph for the Generic Genome Browser.

AXT alignment files are used by UCSC Genome Broser.  A description
of the AXT files can be found at:

http://genome.ucsc.edu/goldenPath/help/axt.html

=head2 NOTES

The GFF entries make use of the GFF3 CIGAR format which creates gap entries
as specified by:

http://www.sequenceontology.org/gff3.shtml

=head1 COMMAND-LINE OPTIONS

=head2 Required

    -species           Name or label of aligning species
    -axtin             Filename of axt file
    
=head2 Optional

    -fa_width          Width of Fasta entries
                         Default = 80
    wigpath            Path of output wig file
                         Default = "."
    wigout             Output wig file
                         Default = axtin_<timestamp>.wig
    gffout             Output GFF file
                         Default = axtin_<timestamp>.gff
    fastaout           Output Fasta file
                         Default = axtin_<timestamp>.fa
    append             Option to append GFF and Fasta entries to file
                         Default = 0
    start              Minimum coordinate for entries to be considered
                         Default = 0
    stop               Maximum coordinate for entries to be considered
                         Default = 0 (off)
    chr                Chromosome of reference sequences to be considered
                         Default = "" (off)

Many options have aliases and can be abbreviated.

=head1 SEE ALSO

L<Bio::Graphics::Wiggle>,
L<Bio::Graphics::Glyph::phylo_align>,
L<Bio::Graphics::Glyph::wiggle_xyplot>,
L<Bio::Graphics::Glyph::wiggle_density>,
L<Bio::Graphics::Panel>,
L<Bio::Graphics::Glyph>,
L<Bio::Graphics::Feature>,
L<Bio::Graphics::FeatureFile>

=head1 AUTHOR

H. Mark Okada E<lt>hmokada@hotmail.comE<gt>.

Copyright (c) 2008

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut




use lib '/Users/mokada/development/gsoc/getWiggle/Generic-Genome-Browser/lib';
use Bio::Graphics::Wiggle;
use Data::Dumper;
use Getopt::Long;

use strict;


#todo
#add getopt: http://aplawrence.com/Unix/perlgetopts.html


my $fa_width = 80; #use constant FA_WIDTH => 80;





#params from input (later)
my $species;
my $chr;
my $axtin = "/Users/mokada/development/gsoc/files/sample_data/pairwise_human_rat/ctgAsubset.net.axt";


my ($min_coord, $max_coord) = (0,0);		#will select alignments within this range, 0 turns off


#params
#my $axtin = "/Users/mokada/development/gsoc/files/sample_data/pairwisealign_elegans_briggsae/chrI.ce4.cb3.net.axt";
#my $wigpath = "/Users/mokada/development/gsoc/files/random_code/wigtest";
my $wigpath = ".";
my $wigout;
my $gffout;
my $fastaout;
my $append = 0;




GetOptions ('species|organism=s'	=> \$species,
			'axtin|input|i=s'		=> \$axtin,
			#optional parameters
			'fa_width=i'			=> \$fa_width,
			'wigpath|p=s'				=> \$wigpath,
			'wigout|w=s'			=> \$wigout,
			'gffout|g=s'			=> \$gffout,
			'fastaout|f=s'			=> \$fastaout,
			'append|a'				=> \$append,
			'start=i'				=> \$min_coord,
			'stop|end=i'			=> \$max_coord,
			'chr|c=s'				=> \$chr
			) or (system('pod2text',$0), exit -1);


#for testing###########################################################
$species = "dog";
$chr = "ctgA";
$wigout   = "chr21axt.wig";
$gffout   = "chr21axt.gff";
$fastaout = "chr21axt.fa";



if (!$species or !$axtin) {
	print "Usage axttobin [-species speciesname] [-axtin AXTinputfile]\n";
	exit -1;
}

if (!$wigout or !$gffout or !$fastaout) {
	my ($file) = $axtin =~ /([^\/]+)$/;
	my $ts = time();
	
	$wigout   = "${file}_$ts.wig" if !$wigout;
	$gffout   = "${file}_$ts.gff" if !$gffout;
	$fastaout = "${file}_$ts.fa"  if !$fastaout;
	
#	print $file,"\n";
}


#exit;

if ($append) {
#	$wigout = ">$wigout";
	$gffout = ">$gffout";
	$fastaout = ">$fastaout";
}



#read Axt-Net file
#(http://genome.ucsc.edu/goldenPath/help/axt.html)


my ($start_coord, $stop_coord) = (0,0);		#get min and max coords for the wig entry last


#set up wigfile
my $wig = Bio::Graphics::Wiggle->new($wigout,
									1,
									
									{
									min => -50000,
									max => 50000
									}
									
#									{seqid => 1,
#									step  => 1,
#									min   => 0,
#									max   => 1}
									);
open (FA_OUT, ">$fastaout");
open (GFF_OUT, ">$gffout");



open (AXT, $axtin);
while (<AXT>) {
	chomp;
	next if /^#/;
	next if $_ eq "";
	
	my @args = /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/;
	next if (@args != 9);
	next if ($chr && $chr ne $args[1]);
	next if ($max_coord && $max_coord < $args[2]);
	next if ($min_coord && $args[3] < $min_coord);
	
	
	#process lines
	my $prim_assemb = <AXT>;
	my $align_assemb = <AXT>;
	
	
	
	#get gap alignment data
	my $gap = "";
	my $seq = "";
#	print length($prim_assemb),"-",length($align_assemb),"\n";
	my ($del, $ins, $match) = (0,0,0);
	my $curr = "";
	my $bp = 0;
	
	#extract match, deletion, insertion data
	for (0..length($prim_assemb)) {
		my $pbase = substr($prim_assemb,$_,1); #primary seq
		my $abase = substr($align_assemb,$_,1); #aligning seq
		if ($pbase eq "-") {
			#insertion
			if ($curr eq "I") {
				$bp++;
			} else {
				$gap .= "$curr$bp " if $bp;
				$curr = "I";
				$bp = 1;
			}
			
		} elsif ($abase eq "-") {
			#deletion
			if ($curr eq "D") {
				$bp++;
			} else {
				$gap .= "$curr$bp " if $bp;
				$curr = "D";
				$bp = 1;
			}
			
			#$seq .= $abase;
			
		} else {
			#match
			if ($curr eq "M") {
				$bp++;
			} else {
				$gap .= "$curr$bp " if $bp;
				$curr = "M";
				$bp = 1;
			}
			
			$seq .= $abase;
		}
		
	}
	$gap .= "$curr$bp " if $bp;
	chop $gap;
	
	
#	print "1234567890        20        30        40        50        60        70        80\n";
#	print "$align_assemb-----\n${prim_assemb}-----\n";
#	print "$gap\n$seq\n\n";
	
	
#	for (0..length($prim_assemb)) {
#		if (substr($prim_assemb,$_,1) eq "-") {
#			if (0 < $ins) {
#				$gap += " I$del";
#				$del = 0;
#			} elsif (0 < $match) {
#				gap += " M$match";
#				$match = 0;
#			}
#			#print "dash";
#			
#		} elsif (substr($prim_assemb,$_,1) eq "-") {
#			print "dash";
#		} else {
#			#match
#		}
#	}
	
	
	
	
	
	
	
	
	
	
	$align_assemb = $seq;
	
	
	
	
	
	
	
	
	
	chomp $prim_assemb;
	chomp $align_assemb;
	
#	print "@args[0..7] : $args[8] > $prim_assemb\n$align_assemb\n\n";
	
	#FASTA entry name
	my $target = "${species}_${args[4]}_${args[5]}_${args[6]}";
	my $target_len = $args[6] - $args[5];
	
	#GFF: match, submatch
	print GFF_OUT join("\t",
						($args[1],
						"pa",
						"match",
						$args[2],
						$args [3],
						".",
						$args[7],
						".",
						"ID=Match_$args[0];species=$species;Target=$target 1 $target_len",
						)),"\n";
	print GFF_OUT join("\t",
						($args[1],
						"pa",
						"submatch",
						$args[2],		#start , stop
						$args[3],
						0,#$args[8],	#score
						$args[7],		#strand
						".",
						"ID=Match_$args[0];species=$species;Target=$target 1 $target_len;Gap=$gap",
						)),"\n";
	
	#FASTA output
	#header
	print FA_OUT ">",join("_",$species,$args[4],$args[5],$args[6]),"\n";
	
	my $diff = length($align_assemb);
#	my $diff = $args[3] - $args[2];
	for (0..int($diff/$fa_width)-1) {
		my $start = $_*$fa_width;
		#print FA_OUT $start," - ", $start+$fa_width-1, "\n";
		print FA_OUT substr($align_assemb,$start,$fa_width),"\n";
	}
	my $extra = $diff % $fa_width;
	if ($extra) {
		#print FA_OUT $diff - $extra, " - ", $diff, "\n";
		print FA_OUT substr($align_assemb,$diff - $extra), "\n";
	}
#	my $start = 0;
#	my $stop = $fa_width - 1;
#	do {
#		$stop = $diff if ($diff < $stop);
#		print FA_OUT "$start  - $stop\n";
#		$start+= $fa_width;
#		$stop += $fa_width;
#	} while ($start < $diff);
	#print FA_OUT $fa_width,"\n";
	
	
	
	
	#get min and max values
	$start_coord = $args[2] if !$start_coord || $args[2] < $start_coord;
	$stop_coord = $args[3] if !$stop_coord || $stop_coord < $args[3];
	
	
	
	#set score in wig file
	$wig->set_range($args[2]=>$args[3],$args[8]);
	
	
}




#GFF: match, submatch
print GFF_OUT join("\t",
					($chr,
					"pa",
					"match",
					$start_coord,
					$stop_coord,
					".",
					"+",
					"ID=Match_Wig_${species};species=$species;wigfile=$wigpath=$wigout",
					)),"\n";


close AXT;


close GFF_OUT;
close FA_OUT;



1;


__END__
