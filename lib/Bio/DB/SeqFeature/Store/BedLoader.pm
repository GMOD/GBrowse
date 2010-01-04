package Bio::DB::SeqFeature::Store::BedLoader;

use strict;
use Carp 'croak';
use File::Spec;
use Text::ParseWords 'shellwords','quotewords';


use base 'Bio::DB::SeqFeature::Store::Loader';

sub load_line {
    my $self = shift;
    my $line = shift;
    if ($line =~ /^track/) {
	$self->handle_track_conf($line);
    } else {
	$self->handle_feature($line);
    }
}

sub handle_track_conf {
    my $self = shift;
    my $line = shift;
    warn "to be implemented";
}

sub handle_feature {
    my $self = shift;
    my $line = shift;
    warn "to be implemented";
}

1;
