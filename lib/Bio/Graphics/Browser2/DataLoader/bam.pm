package Bio::Graphics::Browser2::DataLoader::bam;

# $Id$
use strict;
use base 'Bio::Graphics::Browser2::DataLoader';

my $HASBIGWIG;

sub create_conf_file {
    my $self     = shift;
    my $bam_file   = shift;
    my $has_bigwig = shift;

    my $conf = $self->conf_fh;

    my $data_path  = $self->data_path;
    my $loadid     = $self->loadid;
    my $tracklabel = $self->new_track_label;
    my $filename   = $self->track_name;

    # find a fasta file to use
    my $fasta  = $self->get_fasta_file || '';
    my $category = $self->category;

    my $sam_db =<<END;
[$loadid:database]
db_adaptor = Bio::DB::Sam
db_args    = -bam    "$bam_file"
             -fasta  "$fasta"
	     -split_splices 1
search options = none
END

    (my $bigwig = $bam_file) =~ s/\.bam$/.bw/;

    my $bigwig_db = $has_bigwig ? <<BIGWIG : '';
[${loadid}_bw:database]
db_adaptor = Bio::DB::BigWig
db_args    = -bigwig "$bigwig"
BIGWIG

    my $sam_track =<<END;
[$tracklabel]
feature       = match
glyph         = segments
draw_target   = 1
show_mismatch = 1
mismatch_color = red
database       = $loadid
bgcolor        = blue
fgcolor        = blue
height         = 3
label          = $filename
category       = $category
label density = 50
bump          = fast
key           = $filename
END

    my $semantic_track = $has_bigwig ? <<BIGWIG : <<ORDINARY;
[$tracklabel:499]
database = ${loadid}_bw
feature  = summary
glyph    = wiggle_whiskers
max_color = lightgrey
min_color = lightgrey
mean_color = black
stdev_color = grey
stdev_color_neg = grey
height   = 20
BIGWIG
[$tracklabel:499]
database  = $loadid
feature   = coverage:2000
min_score = 0
glyph     = wiggle_xyplot
height    = 20
fgcolor   = blue
bgcolor   = blue
autoscale = local
key       = $filename
ORDINARY


    print $conf <<END;
$sam_db

$bigwig_db

#>>>>>>>>>> cut here <<<<<<<<

$semantic_track

$sam_track
END

}

# slightly different behavior -- never return the .fai file - only the first .fa file
sub get_fasta_file {
    my $self = shift;
    my @fasta      = $self->get_fasta_files;
    warn "FASTA (before filtering) = @fasta";
    my $fasta      = (grep {!/\.fai$/} @fasta)[0];
    return $fasta;
}

sub load {
    my $self                = shift;
    my ($initial_lines,$fh) = @_;

    $self->flag_busy(1);
    eval {
	$self->open_conf;
	$self->set_status('starting load');
	
	mkdir $self->sources_path or die $!;
	my $source_file = IO::File->new(
	    File::Spec->catfile($self->sources_path,$self->track_name),'>');

	warn "sourcefile=",File::Spec->catfile($self->sources_path,$self->track_name);

	$self->start_load;

	$self->set_status('load data');
	my $bytes_loaded = 0;
	foreach (@$initial_lines) {
	    $source_file->print($_);
	    $bytes_loaded += length $_;
	}

	my $buffer;
	while ((my $bytes = read($fh,$buffer,8192) > 0)) {
	    $source_file->print($buffer);
	    $bytes_loaded += length $ buffer;
	    $self->set_status("loaded $bytes_loaded bytes") if $bytes++ % 10000;
	}
	$source_file->close();

	$self->finish_load;
	$self->close_conf;
	$self->set_processing_complete;
    };

    $self->flag_busy(0);
    die $@ if $@;
    return $self->tracks;
}

sub finish_load {
    my $self = shift;
    eval "require Bio::DB::Sam; 1" or return;

    # keep original copy in sources directory. Create new sorted and indexed
    # copy in main level
    my $source  = File::Spec->catfile($self->sources_path,$self->track_name);
    my $dest    = File::Spec->catfile($self->data_path,$self->track_name);
    $dest      =~ s/\.[bs]am$//i; # sorting will add the .bam extension

    $self->set_status('sorting BAM file');
    Bio::DB::Bam->sort_core(0,$source,$dest);
    
    $self->set_status('indexing BAM file');

    $dest     .= '.bam';
    Bio::DB::Bam->index_build($dest);

    my $bigwig_exists = 0;

    if ($self->has_bigwig) {
	$self->set_status('creating BigWig coverage file');
	$bigwig_exists = $self->create_big_wig();
    }

    $self->set_status('creating conf file');
    $self->create_conf_file($dest,$bigwig_exists);
}

sub has_bigwig {
    my $self = shift;
    return $HASBIGWIG if defined $HASBIGWIG;
    my $result = eval "require Bio::DB::Sam::SamToGBrowse;1";
    $result  &&= eval "require Bio::DB::BigWig; 1";
    warn "hasbigwig = $result";
    return $HASBIGWIG = $result;
}

sub create_big_wig {
    my $self   = shift;
    my $dir    = $self->data_path;
    my $fasta  = $self->get_fasta_file or return;
    my $wigout = Bio::DB::Sam::SamToGBrowse->new($dir,$fasta,0);
    warn "start bam_to_wig()";
    $wigout->bam_to_wig($self->chrom_sizes);  # this creates the wig files
    warn "end bam_to_wig";
    die $wigout->last_error if $wigout->last_error;
    1;
}

1;
