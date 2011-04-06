package Bio::Graphics::Browser2::DataLoader;
# $Id$

use strict;
use IO::File;
use File::Basename 'basename','dirname';
use Fcntl ':flock';
use Carp 'croak', 'cluck';
use Digest::MD5 'md5_hex';

# for mysql to work, you must do something like this:
# grant create on `userdata\_%`.* to 'www-data'@localhost
# NOTICE the backticks around `userdata\_%` !!

sub new {
    my $class = shift;
    my ($track_name, $data_path, $conf_path, $settings, $userid) = @_;
    my $loadid = substr($userid,0,6).'_'.$track_name;
    my $self = bless
    { name     => $track_name,
      data     => $data_path,
      conf     => $conf_path,
      settings => $settings,
      loadid   => $loadid,
    }, ref $class || $class;
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
sub globals { shift->settings->globals }
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

sub strip_prefix {
    my $self = shift;
    my $d = $self->{strip_prefix};
    $self->{strip_prefix} = shift if @_;
    return $d;
}

sub set_status {
    my $self   = shift;
    my $msg    = shift;

    my $status = $self->status_path;
    open my $fh,">",$status;
    flock($fh,LOCK_EX);
    seek($fh,0,0);
    print $fh $msg,"\n";
    close $fh;
}

sub get_status {
    my $self = shift;
    undef $!;
    my $status = $self->status_path;
    open my $fh,"<",$status or return;
    flock($fh,LOCK_SH);
    seek($fh,0,0);
    my $msg = <$fh>;
    close $fh;
    chomp($msg);
    return $msg;
}

sub get_fasta_files {
    my $self = shift;
    my $source = $self->settings;
    my (@fastai,@fasta);

    my @dbs    = $source->databases;
    my %seenit;

    for my $db (@dbs) {
	my ($dbid,$adaptor,%args) = $source->db2args($db);
	my $fasta = $args{-fasta} || $args{-dsn};
	next if $seenit{$fasta}++;
	next unless -e $fasta;
	if (-d _) {
	    push @fastai, glob("$fasta/*.fai");
	    push @fasta,  glob("$fasta/*.{fa,FA,fasta,FASTA}");
	} else {
	    push @fastai,$fasta if -e "$fasta.fai";     # points at an indexed fasta file
	    push @fasta, $fasta if $fasta =~ /\.(fa|fasta)$/i;
	}
    }
    return (@fastai,@fasta);
}

sub get_fasta_file {
    my @fa = shift->get_fasta_files or return;
    return $fa[0];
}

# try to generate a chrom sizes file
sub chrom_sizes {
    my $self    = shift;
    my $source  = $self->settings;
    my $globals = $source->globals;

    my $mtime   = $source->mtime;
    my $name    = $source->name;

    my $sizes  = File::Spec->catfile($globals->tmpdir('chrom_sizes'),"$name.sizes");
    if (-e $sizes && (stat(_))[9] >= $mtime) {
	return $sizes;
    }
    $self->generate_chrom_sizes($sizes) or return;
    return $sizes;
}

sub generate_chrom_sizes {
    my $self  = shift;
    my $sizes = shift;

    my $source = $self->settings;
    my $build   = $source->build_id;
    my $species = $source->taxon_id;

    open my $s,'>',$sizes or die "Can't open $sizes for writing: $!";

    print $s "##species http://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?id=$species\n"
	if $species;
    print $s "##genome-build $build\n" if $build;
    
    my $db      = $source->open_database;

    # Bio::DB::SeqFeature has a seq_ids method.
    # First, try to query the default database for the
    # seq_ids it knows about.

  TRY: {
      my @seqids  = eval {$db->seq_ids}    or last TRY;
      my $result = eval {
	  for (@seqids) {
	      my ($segment) = $db->segment($_) or die "Can't find chromosome $_ in default database";
	      print $s "$_\t",$segment->length,"\n";
	  }
	  close $s;
	  return 1;
      };
      return 1 if $result;
      warn $@;
      unlink $sizes;
      last TRY;
    }

    # Bio::DasI objects have an entry_points method
    if (my @segs = eval {$db->entry_points}) {
	for (@segs) {
	    print $s $_,"\t",$_->length,"\n";
	}
	close $s;
	return 1;
    }

    # Otherwise we search for databases with associated fasta files
    # or indexed fasta (fai) files.
    my $fasta = $self->get_fasta_file or return;
    my $fai   = "$fasta.fai";

    if (!-e $fai && -f $fasta && eval "require Bio::DB::Sam;1") {
	Bio::DB::Sam::Fai->load($fasta) or return;
    }

    if (-e $fai) { # fai file -- copy to sizes
	open my $f,$fai or die "Can't open $fasta: $!";
	while (<$f>) {
	    my ($seqid,$length) = split /\s+/;
	    print $s "$seqid\t$length\n";
	}
	close $f;
	return 1;
    } elsif (eval "require Bio::DB::Fasta; 1") {
	my $fa = Bio::DB::Fasta->new($fasta);
	my @ids = $fa->ids;
	open my $s,'>',$sizes or die "Can't open $sizes for writing: $!";
	for my $i (@ids) {
	    print $s $i,"\t",$fa->length($i),"\n";
	}
	undef $fa;
	return 1;
    }

    unlink $sizes;
    return;
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
    return File::Spec->catfile($self->sources_path, $self->track_name);
}

sub load {
    my $self                = shift;
    my ($initial_lines, $fh) = @_;
    
    $self->flag_busy(1);
    eval {
	    $self->set_status('starting load');
	
	    mkdir $self->sources_path or die "Couldn't make ",$self->sources_path," directory: $!";
	    my $source_file = IO::File->new($self->source_file, '>');

	    $self->open_conf;
	    $self->start_load;

	    $self->set_status('load data');

	    my $count = 0;
	    my $eol   = $self->eol_char;
	    {
	        local $/  = $eol if $eol;
	        foreach (@$initial_lines) {
		        $source_file->print($_) if $source_file;
		        $self->load_line($_);
	        }

	        $count = @$initial_lines;
	        while (<$fh>) {
		        $source_file->print($_) if $source_file;
		        $self->load_line($_);
		        $self->set_status("loaded $count lines") if $count++ % 1000 == 0;
	        }
	        $source_file->close;
	    }

	    $self->finish_load($count);
	    $self->close_conf;
    };
    $self->flag_busy(0);

    die $@ if $@;
    $self->set_processing_complete;
    my @tracks = $self->tracks;
    return @tracks;
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
    return $self->force_category || (Bio::Graphics::Browser2::Util->translate('UPLOADED_TRACKS')||'').':'.$self->track_name;
}

sub backend {
    my $self = shift;
    my $backend = $self->globals->upload_db_adaptor;
    $backend = $self->guess_backend if $backend && $backend eq 'auto';
    unless ($backend) {
	$backend = $self->guess_backend;
	warn "No upload_db_adaptor option set in GBrowse.conf. Will try to use $backend.";
    }
    return $backend;
}

sub guess_backend {
    my $self = shift;
    my %db_drivers = map {$_=>1} DBI->available_drivers(1);
    return 'DBI::SQLite' if $db_drivers{SQLite} && eval "require Bio::DB::SeqFeature::Store::DBI::SQLite; 1";
    return 'berkeleydb'  if                        eval "require Bio::DB::SeqFeature::Store::berkeleydb; 1";
    return 'DBI::mysql'  if $db_drivers{mysql};
    return 'memory';
}

sub dsn {
    my $self = shift;
    my $d    = $self->{dsn};
    $self->{dsn} = shift if @_;
    $d;
}

# Create a new database to hold a user's uploaded file.
sub create_database {
    my $self      = shift;
    my $data_path = shift;

    my $backend   = $self->backend;

    if ($backend =~ /DBI:+mysql/) {
		my $globals    = $self->settings->globals;
		my $db_name    = 'userdata_'.md5_hex($data_path);
		$data_path     = $db_name;
		$db_name      .= ";host=".$globals->upload_db_host;
		$db_name      .= ";user=".$globals->upload_db_user;
		$db_name      .= ";password=".$globals->upload_db_pass;
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
	    or die "Could not create $data_path:",DBI->errstr,".\n",$mysql_usage;
    } elsif ($backend eq 'DBI::SQLite') {
		$self->dsn(File::Spec->catfile($data_path,'index.SQLite'));
    } else {
		$self->dsn($data_path);
    }

    return Bio::DB::SeqFeature::Store->new(
                       -adaptor => $backend,
					   -dsn     => $self->dsn,
					   -create  => 1);
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
	$dsn =~ s/;.+$//;
	$dbh->do("drop database `$dsn`")
	    or die "Could not drop $dsn:",DBI->errstr;
    }
}

# MySQL Admin - Returns the string which defines the custom uploads DB MySQL connection details.
sub mysql_admin {
    my $self = shift;
    my $globals    = $self->globals;
    my $db_host    = $globals->upload_db_host;
    my $db_user    = $globals->upload_db_user;
    my $db_pass    = $globals->upload_db_pass;
    eval "require DBI" unless DBI->can('connect');
    my $dsn        = 'DBI:mysql:gbrowse_login;';
    my @options;
    push @options,"host=$db_host"     if $db_host;
    push @options,"user=$db_user"     if $db_user;
    push @options,"password=$db_pass" if $db_pass;
    return $dsn . join ';',@options;
}

1;
