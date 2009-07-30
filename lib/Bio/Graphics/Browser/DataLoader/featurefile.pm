package Bio::Graphics::Browser::DataLoader::featurefile;

# $Id: featurefile.pm,v 1.1 2009-07-30 16:38:03 lstein Exp $
use strict;
use base 'Bio::Graphic::Browser::DataLoader';
use Bio::DB::SeqFeature::Store;

sub start_load {
    my $self = shift;
    my $conf = $self->conf_fh;
    my $track_name = $self->track_name;
    my $data_path  = $self->data_path;

    $self->{db} = Bio::DB::SeqFeature::Store->new(-adaptor=> 'berkeleydb',
						  -dsn    => $data_path,
						  -create => 1);
    $self->{state} = 'config';
}

sub load_line {
    my $self = shift;
    my $line = shift;
    
}

1;
