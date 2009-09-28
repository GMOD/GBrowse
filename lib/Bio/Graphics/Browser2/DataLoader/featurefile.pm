package Bio::Graphics::Browser2::DataLoader::featurefile;

# $Id: featurefile.pm,v 1.3 2009/08/31 19:46:38 lstein Exp $
use strict;
use Bio::DB::SeqFeature::Store::FeatureFileLoader;
use Bio::DB::SeqFeature::Store;
use base 'Bio::Graphics::Browser2::DataLoader';

sub start_load {
    my $self = shift;
    my $track_name = $self->track_name;
    my $data_path  = $self->data_path;

    my $db     = $self->create_database($data_path);
    warn "db = $db";
    my $loader = Bio::DB::SeqFeature::Store::FeatureFileLoader->new(-store=> $db,
								    -fast => 0);
    warn "starting load";
    $loader->start_load();
    $self->{loader}    = $loader;
    $self->{conflines} = [];
    $self->state('config');
}

sub finish_load {
    my $self = shift;

    $self->loader->finish_load();
    my $db        = $self->loader->store;
    my $conf      = $self->conf_fh;
    my $trackname = $self->track_name;
    my $dsn       = $self->dsn;
    my $backend   = $self->backend;

    print $conf <<END;
[$trackname:database]
db_adaptor = Bio::DB::SeqFeature::Store
db_args    = -adaptor $backend
             -dsn     $dsn

END

    if (my @lines = @{$self->{conflines}}) {  # good! user has provided some config hints
	for my $line (@lines) {
	    print $conf $line;
	    if ($line =~ /\^\[/) {
		print $conf "database = ",$self->track_name,"\n" ;
		print $conf "category = My Tracks:Uploaded Tracks:",$self->track_name,"\n";
	    }

	}
    } else {  # make something up
	my @types = $db->types;
	for my $t (@types) {
	    print $conf "[$t]\n";
	    print $conf "database = ",$self->track_name,"\n";
	    print $conf "category = My Tracks:Uploaded Tracks:",$self->track_name,"\n";
	    print $conf "glyph = generic\n";
	    print $conf "key   = ",$self->track_name," ($t)\n";
	    print $conf "\n";
	}
    }
    # BUG:  LS needs more work here, but don't remember what I planned to do
}

sub loader {shift->{loader}}
sub state {
    my $self = shift;
    my $d    = $self->{state};
    $self->{state} = shift if @_;
    $d;
}
sub load_line {
    my $self = shift;
    my $line = shift;

    my $old_state = $self->state;
    my $state     = $self->_state_transition($old_state,$line);

    warn "old_state=$old_state, new_state=$state, data=$line";

    if ($state eq 'data') {
	$self->loader->load_line($line);
    } elsif ($state eq 'config') {
	push @{$self->{conflines}},$line;
    }
    $self->state($state) if $state ne $old_state;
}

# shamelessly copied from Bio::Graphics:;FeatureFile.
sub _state_transition {
    my $self = shift;
    my ($current_state,$line) = @_;

    warn "current_state=$current_state,line=$line";

    if ($current_state eq 'data') {
	return 'config' if $line =~ m/^\s*\[([^\]]+)\]/;  # start of a configuration section
    }

    elsif ($current_state eq 'config') {
	return 'data'   if $line =~ /^\#\#(\w+)/;     # GFF3 meta instruction
	return 'data'   if $line =~ /^reference\s*=/; # feature-file reference sequence directive
	
	return 'config' if $line =~ /^\s*$/;                             #empty line
	return 'config' if $line =~ m/^\[([^\]]+)\]/;                    # section beginning
	return 'config' if $line =~ m/^[\w\s]+=/; 
	return 'config' if $line =~ m/^\s+(.+)/;
	return 'config' if $line =~ /^\#/;                               # comment -not a meta
	return 'data';
    }
    return $current_state;
}
1;
