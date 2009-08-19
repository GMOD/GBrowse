package Bio::Graphics::Browser::DataLoader::featurefile;

# $Id: featurefile.pm,v 1.2 2009-08-19 19:17:58 lstein Exp $
use strict;
use base 'Bio::Graphic::Browser::DataLoader';
use Bio::DB::SeqFeature::Store;

# for mysql to work, you must do something like this:
# grant create on `userdata_%`.* to www-data@myserver.org

sub start_load {
    my $self = shift;
    my $conf = $self->conf_fh;
    my $track_name = $self->track_name;
    my $data_path  = $self->data_path;

    $self->{db} = $self->create_database;

    $self->{state} = 'config';
}

sub create_database {
    my $self = shift;
    my $backend = $self->setting('userdb_adaptor') || 'berkeleydb';

    if ($backend eq 'DBI::mysql') {
	my @components = split '/',$data_path;
	my $db_name    = 'userdata_'.join '_',@components[-3,-2,-1];
	$data_path     = $db_name;
	
    }

    return Bio::DB::SeqFeature::Store->new(-adaptor=> $backend,
					   -dsn    => $data_path,
					   -create => 1);
}

sub load_line {
    my $self = shift;
    my $line = shift;
    
}

1;
