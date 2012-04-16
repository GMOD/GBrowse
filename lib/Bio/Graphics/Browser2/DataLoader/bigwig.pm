package Bio::Graphics::Browser2::DataLoader::bigwig;

# $Id$
use strict;
use base 'Bio::Graphics::Browser2::DataLoader';
use Bio::DB::BigWig;
use File::Basename 'basename','dirname';

sub load {
    my $self                = shift;
    my ($initial_lines,$fh) = @_;

    $self->flag_busy(1);
    eval {
	$self->open_conf;
	$self->set_status('starting load');
	
	mkdir $self->sources_path or die $!;
	$self->{bigwig} = File::Spec->catfile($self->sources_path,$self->track_name);
	my $source_file = IO::File->new($self->{bigwig},'>');

	warn "sourcefile=$self->{bigwig}";

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
    my $bigwig     = $self->{bigwig} or die "no bigwig file defined";
    print $conf <<END;
[$dbid:database]
db_adaptor    = Bio::DB::BigWig
db_args       = -bigwig '$bigwig'

END
    ;
    print $conf "#>>>>>>>>>> cut here <<<<<<<<\n";
    my $options = {description=>''};
    $options->{name}       ||= $self->track_name;
    $options->{visibility} ||= 'full';
    $options->{maxHeightPixels} ||= $options->{visibility} eq 'full' ? 50 : 20;
    $options->{autoScale}  ||= 'off';
    my @options;
    push @options,"database = $dbid";
    push @options,"feature  = summary";
    push @options,"key      = $options->{name}";
    push @options,'glyph = '. ($options->{visibility} eq 'pack' 
	                               ? 'wiggle_density' 
				       : 'wiggle_whiskers' );
    push @options,'autoscale = '.($options->{autoScale}  eq 'on'   
	                               ? 'local' 
				       : 'chromosome');
    if (exists $options->{viewLimits} && 
	    (my ($low,$hi) = split ':',$options->{viewLimits})) {
	    push @options,"min_score = $low";
	    push @options,"max_score = $hi";
    }

    if (exists $options->{maxHeightPixels} &&
	    (my ($max,$default,$min) = split ':',$options->{maxHeightPixels})) {
	    $default ||= $max;
	    push @options,"height  = $default";
    }
    push @options,"description = $options->{description}";
    my $config_lines = join "\n",@options;
    print $conf <<END;
[$dbid]
$config_lines

END
}

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

1;
