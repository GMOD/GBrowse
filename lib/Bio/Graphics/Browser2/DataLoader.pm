package Bio::Graphics::Browser2::DataLoader;
# $Id$

use strict;
use IO::File;
use Carp 'croak';

# for mysql to work, you must do something like this:
# grant create on `userdata\_%`.* to 'www-data'@localhost
# NOTICE the backticks around `userdata\_%` !!

sub new {
    my $class = shift;
    my ($track_name,$data_path,$conf_path,$settings,$userid) = @_;
    my $loadid = substr($userid,0,6).'_'.$track_name;
    my $self = bless
    { name     => $track_name,
      data     => $data_path,
      conf     => $conf_path,
      settings => $settings,
      loadid   => $loadid,
    },ref $class || $class;
    return $self;
 }

sub track_name { shift->{name} }
sub data_path  { shift->{data} }
sub conf_path  { shift->{conf} }
sub conf_fh    { shift->{conf_fh}  }
sub settings   { shift->{settings} }
sub loadid     { shift->{loadid}   }
sub force_category {
    my $self = shift;
    my $d    = $self->{category};
    $self->{category} = shift if @_;
    return $d;
}
sub eol_char   {
    my $self = shift;
    my $d    = $self->{eol_char};
    $self->{eol_char} = shift if @_;
    return $d;
}
sub setting {
    my $self   = shift;
    my $option = shift;
    $self->settings->global_setting($option);
}
sub busy_path {
    my $self = shift;
    return File::Spec->catfile($self->data_path,
			       Bio::Graphics::Browser2::UserTracks->busy_file_name);
}
sub status_path {
    my $self = shift;
    return File::Spec->catfile($self->data_path,
			       Bio::Graphics::Browser2::UserTracks->status_file_name);
}
sub sources_path {
    my $self = shift;
    return File::Spec->catfile($self->data_path,
			       Bio::Graphics::Browser2::UserTracks->sources_dir_name);
}

sub set_status {
    my $self   = shift;
    my $msg    = shift;

    my $status = $self->status_path;
    open my $fh,">",$status;
    print $fh $msg;
    close $fh;
}

sub get_status {
    my $self = shift;
    my $status = $self->status_path;
    open my $fh,"<",$status;
    my $msg = <$fh>;
    close $fh;
    return $msg;
}

# the client depends on this status literally
# BUG: this will interfere with i18n
sub set_processing_complete {
    shift->set_status('processing complete');
}

sub open_conf {
    my $self = shift;
    $self->{conf_fh} ||= IO::File->new($self->conf_path,">");
    $self->{conf_fh} or die $self->conf_path,": $!";
    $self->{conf_fh};
}
sub close_conf {
    undef shift->{conf_fh};
}

sub source_file {
    my $self = shift;
    return File::Spec->catfile($self->sources_path,$self->track_name);
}

sub load {
    my $self                = shift;
    my ($initial_lines,$fh) = @_;

    $self->flag_busy(1);
    eval {
	$self->set_status('starting load');
	
	mkdir $self->sources_path or die $!;
	my $source_file = IO::File->new($self->source_file,'>');

	$self->open_conf;
	$self->start_load;

	$self->set_status('load data');

	my $eol   = $self->eol_char;
	{
	    local $/  = $eol if $eol;

	    foreach (@$initial_lines) {
		$source_file->print($_) if $source_file;
		$self->load_line($_);
	    }

	    my $count = @$initial_lines;
	    while (<$fh>) {
		$source_file->print($_) if $source_file;
		$self->load_line($_);
		$self->set_status("loaded $count lines") if $count++ % 1000;
	    }
	    $source_file->close;
	}

	$self->finish_load;
	$self->close_conf;
    };
    $self->flag_busy(0);

    die $@ if $@;
    $self->set_processing_complete;
    return $self->tracks;
}

sub start_load  { }
sub finish_load { }
sub flag_busy {
    my $self = shift;
    my $busy = shift;
    my $busy_file = $self->busy_path;

    if ($busy) {
	my $fh        = IO::File->new($busy_file,'>');
    } else {
	unlink $busy_file;
    }
}

sub busy {
    my $self = shift;
    my $busy_file = $self->busy_path;
    return -e $busy_file;
}

sub add_track {
    my $self  = shift;
    my $label = shift;

    $self->{_tracks} ||= {};
    $self->{_tracks}{$label}++;
}
sub tracks {
    my $self = shift;
    return unless $self->{_tracks};
    return keys %{$self->{_tracks}};
}

sub new_track_label {
    my $self   = shift;
    my $type   = shift;
    $type    ||= 'track';
    $type    =~ tr/a-zA-Z0-9_/_/c;

    my $loadid = $self->loadid;
    $self->{_trackno}{$type} ||= 1;

    my $label  = $type."_${loadid}_$self->{_trackno}{$type}";
    $self->{_trackno}{$type}++;
    $self->add_track($label);
    return $label;
}

sub load_line {
    croak "virtual base class";
}

sub category {
    my $self = shift;
    return $self->force_category || "My Tracks:Uploaded Tracks:".$self->track_name;
}

sub backend {
    my $self = shift;
    my $backend   = $self->setting('userdb_adaptor') || $self->guess_backend;
    return $backend;
}

sub guess_backend {
    my $self = shift;
    my %db_drivers = map {$_=>1} DBI->available_drivers(1);
    return 'DBI::SQLite' if $db_drivers{SQLite} && eval "require Bio::DB::SeqFeature::Store::DBI::SQLite";
    return 'berkeleydb'  if eval "require Bio::DB::SeqFeature::Store::berkeleydb; 1";
    return 'DBI::mysql'  if $db_drivers{mysql};
    return 'memory';
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

    my $backend   = $self->backend;

    if ($backend eq 'DBI::mysql') {
	my @components = split '/',$data_path;
	my $db_name    = 'userdata_'.join '_',@components[-3,-2,-1];
	$db_name       =~ s/[^a-zA-Z0-9_-]/_/g;
	$data_path     = $db_name;
	$self->dsn($db_name);
	my $mysql_admin = $self->mysql_admin;

	my $mysql_usage = <<END;
For mysql to work as a backend to stored user data, you must set up the server
so that the web server user (e.g. "www-data") has the privileges to create databases
named "userdata_*". The usual way to do this is with the mysql shell:

 mysql> grant create on `userdata\_%`.* to www-data\@localhost
END

	my $dbh = DBI->connect($mysql_admin)
	    or die DBI->errstr,".\n",$mysql_usage;
	$dbh->do("drop database if exists `$data_path`");
	$dbh->do("create database `$data_path`")
	    or die "Could not create $data_path:",DBI->errstr,".\n",$mysql_usage,;
		 
    } elsif ($backend eq 'DBI::SQLite') {
	$self->dsn(File::Spec->catfile($data_path,'index.SQLite'));
    } else {
	$self->dsn($data_path);
    }

    return Bio::DB::SeqFeature::Store->new(-adaptor=> $backend,
					   -dsn    => $self->dsn,
					   -create => 1);
}

sub drop_databases {
    my $self = shift;
    my $conf_path = shift;
    # hacky job here - just drop anything that looks like a mysql database
    my (@dsns,$using_mysql);
    open my $f,$conf_path or (warn "Couldn't open $conf_path: $!" && return);
    while (<$f>) {
	if (/-adaptor/) {
	    $using_mysql = /DBI::mysql/;
	}
	push @dsns,$1 if /-dsn\s+(.+)/i && $using_mysql;
    }
    close $f;
    
    for my $dsn (@dsns) {
	eval "require DBI" unless DBI->can('connect');
	my $mysql_admin  = $self->mysql_admin;
	my $dbh = DBI->connect($mysql_admin)
	    or die DBI->errstr;
	$dbh->do("drop database `$dsn`")
	    or die "Could not drop $dsn:",DBI->errstr;
    }
}

sub mysql_admin {
    my $self = shift;
    my $db_host    = $self->setting('userdb_host') || 'localhost';
    my $db_user    = $self->setting('userdb_user') || '';
    my $db_pass    = $self->setting('userdb_pass') || '';
    eval "require DBI" unless DBI->can('connect');
    my $dsn        = 'DBI:mysql:';
    my @options;
    push @options,"host=$db_host"     if $db_host;
    push @options,"user=$db_user"     if $db_user;
    push @options,"password=$db_pass" if $db_pass;
    return $dsn . join ';',@options;
}

1;
