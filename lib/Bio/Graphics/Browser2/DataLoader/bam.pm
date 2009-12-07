package Bio::Graphics::Browser2::DataLoader::bam;

# $Id$
use strict;
use base 'Bio::Graphic::Browser2::DataLoader';

sub start_load {
    my $self = shift;
    my $conf = $self->conf_fh;
    my $track_name = $self->track_name;
    my $data_path  = $self->data_path;
    my $loadid     = $self->loadid;
    my $trackname  = $self->new_track_label;

    print $conf <<END;
[$loadid:database]
db_adaptor = Bio::DB::Sam
db_args    = -bam "$data_path/$track_name.bam"
search options = none

#>>>>>>>>>> cut here <<<<<<<<

[$trackname:499]
feature   = coverage:2000
min_score = 0
glyph     = wiggle_xyplot
database  = $loadid
height    = 50
fgcolor   = blue
bgcolor   = blue
autoscale = local
key       = $track_name

[$trackname]
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
key           = $track_name


END
}

sub load {
    my $self                = shift;
    my ($initial_lines,$fh) = @_;

    $self->open_conf;
    $self->start_load;

    my $bamfile = File::Spec->catfile($self->data_path,$self->track_name.".bam");
    $self->status('copying data into your directory');

    my $out = IO::File->new($bamfile,">");
    print $out $_ foreach @$initial_lines;
    my $buffer;
    while ($fh->read($buffer,8192) > 0) {
	print $out $_;
    }
    $out->close;

    $self->finish_load;
    $self->close_conf;
    $self->status('READY');
}

sub finish_load {
    my $self = shift;
    # attempt to open BAM file to sort and index it
    my $bamfile = File::Spec->catfile($self->data_path,$self->track_name.".bam");
    require "Bio::DB::Sam; 1" or return;

    $self->status('indexing BAM file');
    my $f = Bio::DB::Sam->new(-bam => $bamfile);
}

1;
