package Bio::Graphics::Browser2::UserTracks;

# $Id$
use strict;
use Bio::Graphics::Browser2::DataSource;
use Bio::Graphics::Browser2::DataLoader;
use File::Spec;
use File::Basename 'basename';
use File::Path 'mkpath','rmtree';
use IO::String;
use Carp 'croak';

# The intent of this is to provide a single unified interface for managing
# a user's uploaded and shared tracks.

# It works on the basis of a file-based database with the following structure:
#    base      -- e.g. /var/tmp/gbrowse2/userdata
#    uploadid  -- e.g. dc39b67fb5278c0da0e44e9e174d0b40
#    source    -- e.g. volvox
#    concatenated path /var/tmp/gbrowse2/userdata/volvox/dc39b67fb5278c0da0e44e9e174d0b40

# The concatenated path contains a series of directories named after the track.
# Each directory has a .conf file that describes its contents and configuration.
# There will also be data files associated with the configuration.

# class methods
sub busy_file_name     { 'BUSY'      }
sub status_file_name   { 'STATUS'    }
sub imported_file_name { 'IMPORTED'  }
sub sources_dir_name   { 'SOURCES'   }

sub new {
    my $self = shift;
    my ($config,$state,$lang) = @_;

    return bless {
	config   => $config,
	state    => $state,
	language => $lang,
    },ref $self || $self;
}

sub config   { shift->{config}    }
sub state    { shift->{state}     }    
sub language { shift->{language}  }

sub path {
    my $self   = shift;
    $self->config->userdata($self->state->{uploadid});
}

sub tracks {
    my $self = shift;
    my $path     = $self->path;
    my $imported = shift;

    my @result;
    opendir D,$path;
    while (my $dir = readdir(D)) {
	next if $dir =~ /^\.+$/;

	# my $is_busy       = (-e File::Spec->catfile($path,$dir,$self->busy_file_name))||0;
	# next if $is_busy;

	my $is_imported   = (-e File::Spec->catfile($path,$dir,$self->imported_file_name))||0;
	next if defined $imported && $imported != $is_imported;

	push @result,$dir;
    }
    return @result;
}

sub conf_files {
    my $self = shift;
    my $path = $self->path;
    return grep {-e $_} map {File::Spec->catfile($path,$_,"$_.conf")} $self->tracks;
}

sub track_path {
    my $self  = shift;
    my $track = shift;
    return File::Spec->catfile($self->path,$track);
}

sub data_path {
    my $self = shift;
    my ($track,$datafile) = @_;
    return File::Spec->catfile($self->path,$track,$self->sources_dir_name,$datafile);
}

sub track_conf {
    my $self  = shift;
    my $track = shift;
    return File::Spec->catfile($self->path,$track,"$track.conf");
}

sub conf_fh {
    my $self = shift;
    my $track = shift;
    return Bio::Graphics::Browser2::UserConf->fh($self->track_conf($track));
}

sub import_flag {
    my $self  = shift;
    my $track = shift;
    return File::Spec->catfile($self->path,
			       $track,
			       $self->imported_file_name);
}

sub created {
    my $self  = shift;
    my $track = shift;
    my $conf  = File::Spec->catfile($self->path,$track,"$track.conf");
    return (stat($conf))[10];
}

sub modified {
    my $self  = shift;
    my $track = shift;
    return ($self->conf_metadata($track))[1];
}

sub conf_metadata {
    my $self  = shift;
    my $track = shift;
    my $conf  = File::Spec->catfile($self->path,$track,"$track.conf");
    my $name  = basename($conf);
    return ($name,(stat($conf))[9,7]);
}

sub description {
    my $self  = shift;
    my $track = shift;
    my $desc  = File::Spec->catfile($self->path,$track,"$track.desc");
    if (@_) {
	warn "setting desc to @_";
	open my $f,">",$desc or return;
	print $f join("\n",@_);
	close $f;
	return 1;
    } else {
	open my $f,"<",$desc or return;
	my @lines = <$f>;
	return join '',@lines;
    }
}

sub source_files {
    my $self = shift;
    my $track = shift;
    my $path = File::Spec->catfile($self->track_path($track),
				   $self->sources_dir_name);
    my @files;
    if (opendir my $dir,$path) {
	while (my $f = readdir($dir)) {
	    next unless -f File::Spec->catfile($path,$f);
	    my ($size,$mtime) = (stat(_))[7,9];
	    push @files,[$f,$size,$mtime];
	}
    }
    return @files;
}

sub trackname_from_url {
    my $self     = shift;
    my $url      = shift;

    my $uniquefy = shift;

    (my $track_name = $url) =~ tr!a-zA-Z0-9_%^@.!_!cs;

    my $unique = 0;
    while ($uniquefy && !$unique) {
	my $path = $self->track_path($track_name);
	if (-e $path) {
	    $track_name .= "-0" unless $track_name =~ /-\d+$/;
	    $track_name  =~ s/-(\d+)$/'-'.($1+1)/e;
	} else {
	    $unique++;
	}
    }

    my $path = $self->track_path($track_name);
    rmtree($path) if -e $path;  # only happens if uniquefy = 0
    mkpath $path;
    return $track_name;
}

sub import_url {
    my $self = shift;

    my $url       = shift;
    my $overwrite = shift;

    my $key;
    if ($url =~ m!http://([^/]+).+/(\w+)/\?.*t=([^+;]+)!) {
	my @tracks = split /\+/,$3;
	$key = "Shared track from $1 (@tracks)";
    }
    else {$key  = "Shared track from $url";}

    my $track_name = $self->trackname_from_url($url,!$overwrite);

    my $conf = $self->track_conf($track_name);
    open my $f,">",$conf or croak "Couldn't open $conf: $!";
    print $f <<END;
>>>>>>>>>>>>>> cut here <<<<<<<<<<<<
[$track_name]
remote feature = $url
category = My Tracks:Remote Tracks
key      = $key
END
    ;
    close $f;
    open my $i,">",$self->import_flag($track_name);
    close $i;

    return (1,'',[$track_name]);
}

sub upload_data {
    my $self = shift;
    my ($file_name,$data,$overwrite) = @_;
    my $io = IO::String->new($data);
    $self->upload_file($file_name,$io,$overwrite);
}

sub upload_file {
    my $self = shift;
    my ($file_name,$fh,$overwrite) = @_;
    
    my $track_name = $self->trackname_from_url($file_name,!$overwrite);

    # guess the file type from the first non-blank line
    my ($type,$lines)   = $self->guess_upload_type($fh);
    my (@tracks,$fcgi);

    my $result= eval {
	local $SIG{TERM} = sub { die "cancelled" };
	croak "Could not guess the type of the file $file_name"
	    unless $type;

	my $loader = $self->get_loader($type);
	my $load   = $loader->new($track_name,
				  $self->track_path($track_name),
				  $self->track_conf($track_name),
				  $self->config,
				  $self->state->{uploadid},
	    );
	@tracks = $load->load($lines,$fh);
	1;
    };

    if ($@ =~ /cancelled/) {
	$self->delete_file($track_name);
	return (0,'Cancelled by user',[]);
    }

    my $msg = $@;
    warn $msg if $msg;
    $self->delete_file($track_name) unless $result;
    return ($result,"$msg",\@tracks);
}

sub delete_file {
    my $self = shift;
    my $track_name  = shift;
    rmtree($self->track_path($track_name));
}

sub merge_conf {
    my $self       = shift;
    my ($track_name,$new_data) = @_;

    my $path = $self->track_conf($track_name) or return;

    my @lines = split /\r\n|\r|\n/,$new_data;
    my (%stanzas,$current_stanza);
    for (@lines) {
	if (/^\[(.+)\]/) {
	    $current_stanza = $1;
	    $stanzas{$current_stanza} = '';
	} elsif ($current_stanza) {
	    $stanzas{$current_stanza} .= "$_\n";
	}
    }

    open my $fh,$path or croak "$path: $!";
    my $merged = '';
    my $database;
    # read header with the [database] definition
    while (<$fh>) {
	$merged .= $_;
	$database = $1 if /^\[(.+):database/;
	last if /cut here/;
    }

    $merged .= "\n";

    # read the rest
    while (<$fh>) {
	if (/^\[/) {
	    (my $stanza = $_) =~ s/\[(\w+?)_.+_(\d+)\]\s*\n/$1_$2/;
	    if (my $body = $stanzas{$stanza}) {
		$merged .= $_;
		$merged .= "database = $database\n";
		$merged .= $body;
	    }
	}
    }

    open $fh,'>',$path or croak "Can't open $path for writing: $!";
    print $fh $merged;
    close $fh;
}

sub labels {
    my $self       = shift;
    my $track_name = shift;
    my $conf       = $self->track_conf($track_name) or return;
    return grep {!/:database/} eval{Bio::Graphics::FeatureFile->new(-file=>$conf)->labels};
}

sub status {
    my $self     = shift;
    my $filename = shift;
    my $loader   = 'Bio::Graphics::Browser2::DataLoader';
    my $load   = $loader->new($filename,
			      $self->track_path($filename),
			      $self->track_conf($filename),
			      $self->config,
			      $self->state->{uploadid},
	);
    return $load->get_status();
}

sub get_loader {
    my $self   = shift;
    my $type   = shift;
    my $module = "Bio::Graphics::Browser2::DataLoader::$type";
    eval "require $module";
    die $@ if $@;
    return $module;
}

sub guess_upload_type {
    my $self = shift;
    my $fh   = shift;

    my @lines;
    while (my $line = <$fh>) {
	push @lines,$line;
	return ('featurefile',\@lines) if $line =~ /^reference/i;
	return ('featurefile',\@lines) if $line =~ /\w+:\d+\.\.\d+/i;
	return ('gff2',\@lines)        if $line =~ /^\#\#gff-version\s+2/;
	return ('gff3',\@lines)        if $line =~ /^\#\#gff-version\s+3/;
	return ('wiggle',\@lines)      if $line =~ /type=wiggle/;
	return ('bed',\@lines)         if $line =~ /^\w+\s+\d+\s+\d+/;
	return ('sam',\@lines)         if $line =~ /^\@[A-Z]{2}/;
	return ('sam',\@lines)         if $line =~ /^[^ \t\n\r]+\t[0-9]+\t[^ \t\n\r@=]+\t[0-9]+\t[0-9]+\t(?:[0-9]+[MIDNSHP])+|\*/;
	return ('bam',\@lines)         if substr($line,0,6) eq "\x1f\x8b\x08\x04\x00\x00";
    }

    return;
}

package Bio::Graphics::Browser2::UserConf;

use base 'Tie::Handle';
use Symbol;

sub fh {
    my $class = shift;
    my $path  = shift;
    my $g = gensym;
    tie(*$g,$class,$path);
    return $g;
}

sub TIEHANDLE {
    my $class = shift;
    my $path  = shift;
    open my $f,$path or die "$path:$!";
    return bless {
	fh       => $f,
	seen_cut => 0,
    },$class;
}

sub READLINE {
    my $self = shift;
    my $fh   = $self->{fh};
    while (my $line = <$fh>) {
	if ($line =~ /cut here/i) {
	    $self->{seen_cut}++;
	    next;
	}
	next unless $self->{seen_cut};
	next if $line =~ /^\s*database/;
	$line =~ s/\[(\w+?)_.+_(\d+)\]/[$1_$2]/;
	return $line;
    }
    return;
}

sub CLOSE { close shift->{fh} } 


1;
