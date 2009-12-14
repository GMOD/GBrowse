package Bio::Graphics::Browser2::DataLoader::bam;

# $Id$
use strict;
use base 'Bio::Graphics::Browser2::DataLoader';
use File::Basename 'basename','dirname';

sub create_conf_file {
    my $self     = shift;
    my $bam_file = shift;

    my $conf = $self->conf_fh;

    my $data_path  = $self->data_path;
    my $loadid     = $self->loadid;
    my $tracklabel = $self->new_track_label;
    my $filename   = $self->track_name;

    # find a fasta file to use
    my $fasta  = $self->get_fasta_file || '';

    print $conf <<END;
[$loadid:database]
db_adaptor = Bio::DB::Sam
db_args    = -bam    "$bam_file"
             -fasta  "$fasta"
search options = none

#>>>>>>>>>> cut here <<<<<<<<

[$tracklabel:499]
feature   = coverage:2000
min_score = 0
glyph     = wiggle_xyplot
database  = $loadid
height    = 50
fgcolor   = blue
bgcolor   = blue
autoscale = local
key       = $filename

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
label          = sub {shift->display_name}
category       = My Tracks:Uploaded Tracks
label density = 50
bump          = fast
key           = $filename


END
}

sub get_fasta_file {
    my $self = shift;

    my $source = $self->settings;
    my @dbs    = $source->databases;
    for my $db (@dbs) {
	my ($dbid,$adaptor,%args) = $source->db2args($db);
	my $fasta = $args{-fasta} or next;
	return $fasta if -e "$fasta.fai";                  # points at an indexed fasta file
	return $fasta if -e $fasta && -w dirname($fasta);  # fasta file exists and can create index
    }
    return;
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

    $self->set_status('creating conf file');
    $self->create_conf_file($dest);
}

1;
