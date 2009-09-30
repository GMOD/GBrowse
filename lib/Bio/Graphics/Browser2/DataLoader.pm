package Bio::Graphics::Browser2::DataLoader;
# $Id: DataLoader.pm,v 1.3 2009-08-27 19:13:19 idavies Exp $

use strict;
use IO::File;
use Carp 'croak';

# for mysql to work, you must do something like this:
# grant create on `userdata_%`.* to www-data@localhost

sub new {
    my $class = shift;
    my ($track_name,$data_path,$conf_path,$settings,$userid) = @_;
    my $loadid = substr($userid,0,6).'_'.$track_name;
    warn "loadid = $loadid";
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
sub setting {
    my $self   = shift;
    my $option = shift;
    $self->settings->global_setting($option);
}
sub status_path {
    my $self = shift;
    return File::Spec->catfile($self->data_path,'STATUS');
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

sub open_conf {
    my $self = shift;
    $self->{conf_fh} ||= IO::File->new($self->conf_path,">");
    $self->{conf_fh} or die $self->conf_path,": $!";
    $self->{conf_fh};
}
sub close_conf {
    undef shift->{conf_fh};
}

sub load {
    my $self                = shift;
    my ($initial_lines,$fh) = @_;

    $self->set_status('starting load');
    sleep 1;
    $self->open_conf;
    $self->start_load;

    $self->set_status('load data');
    foreach (@$initial_lines) {
	$self->load_line($_);
    }

    my $count = @$initial_lines;
    while (<$fh>) {
	$self->load_line($_);
	$self->set_status("loaded $count lines") if $count++ % 1000;
    }
    $self->finish_load;
    $self->close_conf;
    $self->set_status("READY");
}

sub start_load  { }
sub finish_load { }

sub load_line {
    croak "virtual base class";
}

sub backend {
    my $self = shift;
    my $backend   = $self->setting('userdb_adaptor') || $self->guess_backend;
    return $backend;
}

sub guess_backend {
    my $self = shift;
    my %db_drivers = map {$_=>1} DBI->available_drivers(1);
    return 'DBI::SQLite' if $db_drivers{SQLite};
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

    warn "backend = $backend";

    if ($backend eq 'DBI::mysql') {
	my @components = split '/',$data_path;
	my $db_name    = 'userdata_'.join '_',@components[-3,-2,-1];
	$data_path     = $db_name;
	$self->dsn($db_name);
	my $db_host    = $self->setting('userdb_host') || 'localhost';
	my $db_user    = $self->setting('userdb_user') || '';
	my $db_pass    = $self->setting('userdb_pass') || '';
	eval "require DBI" unless DBI->can('connect');
	my $dsn        = 'dbi:mysql:';
	$dsn          .= 'host=$db_host' if $db_host;

	my $mysql_usage = <<END;
For mysql to work as a backend to stored user data, you must set up the server
so that the web server user (e.g. "www-data") has the privileges to create databases
named "userdata_*". The usual way to do this is with the mysql shell:

 mysql> grant create on `userdata_%`.* to www-data\@localhost
END

	my $dbh = DBI->connect($dsn)
	    or die DBI->errstr,'  ',$mysql_usage;
	$dbh->do("create database $data_path")
	    or die "Could not create $data_path:",DBI->errstr,'. ',$mysql_usage,;
		 
    } elsif ($backend eq 'DBI::SQLite') {
	$self->dsn(File::Spec->catfile($data_path,'SQLite'));
    } else {
	$self->dsn($data_path);
    }

    return Bio::DB::SeqFeature::Store->new(-adaptor=> $backend,
					   -dsn    => $self->dsn,
					   -create => 1);
}

1;
