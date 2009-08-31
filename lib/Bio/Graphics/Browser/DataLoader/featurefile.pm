package Bio::Graphics::Browser::DataLoader::featurefile;

# $Id: featurefile.pm,v 1.3 2009-08-31 19:46:38 lstein Exp $
use strict;
use base 'Bio::Graphic::Browser::DataLoader';
use Bio::DB::SeqFeature::Store::FeatureFileLoader;
use Bio::DB::SeqFeature::Store;

# for mysql to work, you must do something like this:
# grant create on `userdata_%`.* to www-data@myserver.org

sub start_load {
    my $self = shift;
    my $track_name = $self->track_name;
    my $data_path  = $self->data_path;

    my $db     = $self->create_database($data_path);
    my $loader = Bio::DB::SeqFeature::Store::FeatureFileLoader->new(-store=> $db,
								    -fast => 1);
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

    print $conf <<END;
[$trackname:database]
db_adaptor = Bio::DB::SeqFeature::Store
db_args    = -adaptor $backend
             -dsn     $dsn

END

    if (my @lines = @{$self->{conflines}}) {  # good! user has provided some config hints
	for my $line (@lines) {
	    print $conf $line;
	    if ($line =~ /\^[/) {
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
   needs more work
}

sub loader {shift->{loader}}
sub state {
    my $self = shift;
    my $d    = $self->{state};
    $self->{state} = shift if @_;
    $d;
}
sub dsn {
    my $self = shift;
    my $d    = $self->{dsn};
    $self->{dsn} = shift if @_;
    $d;
}

sub create_database {
    my $self      = shift;
    my $data_path = shift;

    my $backend   = $self->setting('userdb_adaptor') || 'berkeleydb';

    if ($backend eq 'DBI::mysql') {
	my @components = split '/',$data_path;
	my $db_name    = 'userdata_'.join '_',@components[-3,-2,-1];
	$data_path     = $db_name;
	$self->dsn($db_name);
	my $db_host    = $self->setting('userdb_host');
	my $db_user    = $self->setting('userdb_user');
	my $db_pass    = $self->setting('userdb_pass');
	eval "require DBI" unless DBI->can('connect');
	my $dsn        = 'dbi:mysql:';
	$dsn          .= 'host=$db_host' if $db_host;
	my $dbh = DBI->connect($dsn)
	    or die "Could not connect to mysql server: ",DBI->errstr;
	$dbh->do("create database $data_path")
	    or die "Could not create database $data_path: ",DBI->errstr;
		 
    }

    return Bio::DB::SeqFeature::Store->new(-adaptor=> $backend,
					   -dsn    => $data_path,
					   -create => 1);
}

sub load_line {
    my $self = shift;
    my $line = shift;

    my $old_state = $self->state;
    my $state     = $self->_state_transition($old_state,$line);

    if ($state eq 'data') {
	$self->loader->load($line);
    } elsif ($state eq 'config') {
	push @{$self->{conflines}},$line;
    }
    $self->state($state) if $state ne $old_state;
}

# shamelessly copied from Bio::Graphics:;FeatureFile.
sub _state_transition {
    my $self = shift;
    my ($current_state,$line) = @_;

    if ($current_state eq 'data') {
	return 'config' if $line =~ m/^\s*\[([^\]]+)\]/;  # start of a configuration section
    }

    elsif ($current_state eq 'config') {
	return 'data'   if $line =~ /^\#\#(\w+)/;     # GFF3 meta instruction
	return 'data'   if $line =~ /^reference\s*=/; # feature-file reference sequence directive
	
	return 'config' if $line =~ /^\s*$/;                             #empty line
	return 'config' if $line =~ m/^\[([^\]]+)\]/;                    # section beginning
	return 'config' if $line =~ m/^[\w\s]+=/ 
	    && $self->{current_config};                                  # configuration line
	return 'config' if $line =~ m/^\s+(.+)/
	    && $self->{current_tag};                                     # continuation section
	return 'config' if $line =~ /^\#/;                               # comment -not a meta
	return 'data';
    }
    return $current_state;
}
1;
