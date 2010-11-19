These are the files (or the data) that were used to run the phylo_alignment glyph used in my simple demonstration.


phyloalign.fa:
These contain sequences that can be used in the alignments when zoomed in.
(These are actually just taken from the volvox EST data, and renamed)
-> this can be named anything or can be appended to any fasta recognisable file

volvox_phyloalign.gff:
These contain the actual alignment information in the GFF 3 (CIGAR) format.  Every feature represents an alignment of the current species.  When zoomed out, the score (6th column) is what is drawn in the histogram and when zoomed in, the gaps are drawn as specified by the CIGAR format.
-> this can be named anything or can be appended to any gff3 recognisable file

species.tre:
This is a tree file that is used to draw and order the cladogram for the alignment glyph.  It makes use of Bio::TreeIO and so it should theoretically read any file type that TreeIO can handle.
Any species that is used in the alignment, but not found in this tree file will still have their alignments drawn in the glyph but will not be connected in the tree.
-> this file must be mentioned in the .conf file, as well as it's format (eg. newick)


volvox_alignment.conf:
This is what is necessary in the gbrowse.conf to display the phylo_alignment glyph.  It is a bit bloated and can be trimmed (especially with the colours)
-> must be included in the gbrowse.conf file



The entire glyph was coded rather quickly and there are many foreseeable improvements that can be implemented.  It might be quicker to just recode the thing.  2007/10/10