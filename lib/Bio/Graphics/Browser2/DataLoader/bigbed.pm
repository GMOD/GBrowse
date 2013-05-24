package Bio::Graphics::Browser2::DataLoader::bigbed;

# $Id$
use strict;
use base 'Bio::Graphics::Browser2::DataLoader';
use Bio::DB::BigBed;
use File::Basename 'basename','dirname';
my @COLORS = qw(blue red orange brown mauve peach 
                green cyan yellow coral);

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    $self->{default_track_name} = 'track000';
    $self;
}

sub default_track_name {
    my $self = shift;
    return $self->{default_track_name}++;
}

sub load {
    my $self                = shift;
    my ($initial_lines,$fh) = @_;

    $self->flag_busy(1);
    eval {
	$self->open_conf;
	$self->set_status('starting load');
	
	mkdir $self->sources_path or die $!;
	$self->{bigbed} = File::Spec->catfile($self->sources_path,$self->track_name);
	my $source_file = IO::File->new($self->{bigbed},'>');

	warn "sourcefile=$self->{bigbed}";

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

    my $loadid     = $self->loadid;

    $self->set_status('creating configuration');
    my $conf       = $self->conf_fh;
    my $dbid       = $self->new_track_label;
    my $bigbed     = $self->{bigbed} or die "no bigbed file defined";
    print $conf <<END;
[$dbid:database]
db_adaptor    = Bio::DB::BigBed
db_args       = -bigbed '$bigbed'

END
    ;
    print $conf "#>>>>>>>>>> cut here <<<<<<<<\n";
    my $color = $COLORS[rand @COLORS];
    my $name = $self->track_name;
    
    print $conf <<END
[$dbid]
database = $dbid
feature  = region
glyph    = segments
label density = 50
feature_limit = 500
bump     = fast
stranded = 1
height   = 4
bgcolor  = $color
fgcolor  = $color
key      = $name segments
description = 

[$dbid\_coverage]
database = $dbid
feature  = summary
glyph    = wiggle_whiskers
fgcolor  = black
height   = 50
autoscale = chromosome
key      = $name coverage
description = 

END
;
# We are defining two separate tracks rather than using semantic zoom 
# because of the flexible nature of the bigBed format. It can be used 
# as a Bam substitute where coverage is the best glyph, or it can be used 
# for sparse intervals of interest where segments is the best glyph. 
# Onus is on the user to select the most appropriate one.
}

1;
