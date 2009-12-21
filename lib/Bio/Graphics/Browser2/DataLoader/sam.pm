package Bio::Graphics::Browser2::DataLoader::sam;

# $Id: bam.pm 22336 2009-12-07 22:18:43Z lstein $

use strict;
use base 'Bio::Graphics::Browser2::DataLoader::bam';

# go back to line-at-a-time loading
sub load {
    my $self                = shift;
    $self->Bio::Graphics::Browser2::DataLoader::load(@_);
}

# We do nothing here; the base class
# makes a copy of the data file in SOURCES
sub load_line { }

sub finish_load {
    my $self = shift;
    my $source_file = File::Spec->catfile($self->sources_path,$self->track_name);

    # sort out the file names
    my $track_name = $self->track_name;
    $track_name    =~ s/\..+$//;  # get rid of any extension

    my $base       = File::Spec->catfile($self->data_path,$track_name);
    my $bam        = $base . '.bam';
    my $sorted     = $base . '_sorted';

    # turn SAM file into a BAM file
    $self->set_status('converting SAM to BAM');
    $self->sam2bam($source_file,$bam);

    # sort it
    $self->set_status('sorting BAM file');
    Bio::DB::Bam->sort_core(0,$bam,$sorted);

    # no need to keep sorted and unsorted copies
    rename "$sorted.bam",$bam;

    $self->set_status('indexing BAM file');

    Bio::DB::Bam->index_build($bam);

    $self->set_status('creating conf file');
    $self->create_conf_file($bam);
}

sub sam2bam {
    my $self = shift;
    my ($sampath,$bampath) = @_;

    my $fasta      = $self->get_fasta_file;
    $fasta 
	or die "Could not find a suitable reference FASTA file for indexing this SAM file";
    
    # This is to create the .fai file. Do this in a block so that handle
    # goes out of scope when not needed.
    {
	my $fai = Bio::DB::Sam::Fai->load($fasta)
	    or die "Could not load reference FASTA file for indexing this SAM file: $!";
    }

    my $tam = Bio::DB::Tam->open($sampath)
	or die "Could not open SAM file for reading: $!";

    my $header = $tam->header_read2($fasta.".fai");

    my $bam = Bio::DB::Bam->open($bampath,'w')
	or die "Could not open BAM file for writing: $!";

    $bam->header_write($header);
    my $alignment = Bio::DB::Bam::Alignment->new();
    my $lines = 0;

    while ($tam->read1($header,$alignment) > 0) {
	$bam->write1($alignment);
	$self->set_status("converted $lines lines...") if $lines++%1000 == 0;
    }
    
    undef $tam;
    undef $bam;
}

1;
