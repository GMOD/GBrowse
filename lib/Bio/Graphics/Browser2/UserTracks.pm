package Bio::Graphics::Browser2::UserTracks;

# $Id$
use strict;
use Bio::Graphics::Browser2::DataSource;
use Bio::Graphics::Browser2::DataLoader;
use File::Spec;
use File::Basename 'basename';
use File::Path 'mkpath','rmtree';
use IO::File;
use IO::String;
use Carp 'croak';

use constant DEBUG => 0;

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
    my ($config,$state,$lang,$uuid) = @_;
    $uuid ||= $state->{uploadid};

    return bless {
	config   => $config,
	state    => $state,
	language => $lang,
	uuid     => $uuid,
    },ref $self || $self;
}

sub config   { shift->{config}    }
sub state    { shift->{state}     }    
sub language { shift->{language}  }

sub path {
    my $self   = shift;
    my $uploadid = $self->{uuid} || '';
    $self->config->userdata($uploadid);
}

sub tracks {
    my $self     = shift;
    my $path     = $self->path;
    my $imported = shift;

    my @result;
    opendir D,$path;
    while (my $dir = readdir(D)) {
	next if $dir =~ /^\.+$/;

	my $is_imported   = (-e File::Spec->catfile($path,
						    $dir,
						    $self->imported_file_name))||0;
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
	warn "setting desc to @_" if DEBUG;
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
	    my $path = File::Spec->catfile($path,$f);
	    next unless -f $path;
	    my ($size,$mtime) = (stat(_))[7,9];
	    push @files,[$f,$size,$mtime,$path];
	}
    }
    return @files;
}

sub trackname_from_url {
    my $self     = shift;
    my $url      = shift;

    my $uniquefy = shift;
    (my $track_name=$url) =~ tr!a-zA-Z0-9_%^@.!_!cs;

    my $unique = 0;
    while ($uniquefy && !$unique) {
	my $path = $self->track_path($track_name);
	if (-e $path) {
	    $track_name .= "-0" unless $track_name =~ /-\d+$/;
	    $track_name  =~ s/-(\d+)$/'-'.($1+1)/e; # add +1 to the trackname
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
    my ($file_name,$data,$content_type,$overwrite) = @_;
    my $io = IO::String->new($data);
    $self->upload_file($file_name,$io,$content_type,$overwrite);
}

sub upload_file {
    my $self = shift;
    my ($file_name,$fh,$content_type,$overwrite) = @_;
    
    my $track_name = $self->trackname_from_url($file_name,!$overwrite);
    $content_type ||= '';

    if ($content_type eq 'application/gzip' or $file_name =~ /\.gz$/) {
	$fh = $self->install_filter($fh,'gunzip -c');
    } elsif ($content_type eq 'application/bzip2' or $file_name =~ /\.bz2$/) {
	$fh = $self->install_filter($fh,'bunzip2 -c');
    }
    
    # guess the file type from the first non-blank line
    my ($type,$lines,$eol)   = $self->guess_upload_type($file_name,$fh);
    $lines                 ||= [];
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
	$load->eol_char($eol);
	@tracks = $load->load($lines,$fh);
	1;
    };

    if ($@ =~ /cancelled/) {
	$self->delete_file($track_name);
	return (0,'Cancelled by user',[]);
    }

    my $msg = $@;
    warn "UPLOAD ERROR: ",$msg if $msg;
    $self->delete_file($track_name) unless $result;
    return ($result,$msg,\@tracks);
}

sub delete_file {
    my $self = shift;
    my $track_name  = shift;
    my $loader = Bio::Graphics::Browser2::DataLoader->new($track_name,
							  $self->track_path($track_name),
							  $self->track_conf($track_name),
							  $self->config,
							  $self->state->{uploadid});
    $loader->drop_databases($self->track_conf($track_name));
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
	    (my $stanza = $_) =~ s/\[(\w+?)_.+_(\d+)(:\d+)?\]\s*\n/$1_$2$3/;
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

# guess the file type and eol based on its name and the first 1024 bytes
# of the file. The @$lines will contain the lines that were consumed
# during this operation so that the info isn't lost.
sub guess_upload_type {
    my $self = shift;
    my ($filename,$fh) = @_;

    my $buffer;
    read($fh,$buffer,1024);
    
    # first check for binary upload; currently only BAM
    return ('bam',[$buffer],undef)
	if substr($buffer,0,6) eq "\x1f\x8b\x08\x04\x00\x00";
    
    # everything else is text (for now)
    my $eol = $buffer =~ /\015\012/ ? "\015\012"  # MS-DOS
	     :$buffer =~ /\015/     ? "\015"      # Macintosh
	     :$buffer =~ /\012/     ? "\012"      # Unix
	     :"\012";  # default to Unix

    local $/ = $eol;
    my @lines     = map {$_.$eol} split $eol,$buffer;
    $lines[-1]    =~ s/$eol$// unless $buffer =~ /$eol$/;
    my $remainder = <$fh>;
    $remainder   ||= '';
    $lines[-1]   .= $remainder;

    # first guess based on file names
    my $ftype = $filename =~ /\.gff(\.(gz|bz2|Z))?$/i  ? 'gff'
	       :$filename =~ /\.gff3(\.(gz|bz2|Z))?$/i ? 'gff3'
	       :$filename =~ /\.bed(\.(gz|bz2|Z))?$/i  ? 'bed'
	       :$filename =~ /\.wig(\.(gz|bz2|Z))?$/i  ? 'wiggle'
	       :$filename =~ /\.fff(\.(gz|bz2|Z))?$/i  ? 'featurefile'
	       :$filename =~ /\.bam(\.gz)?$/i          ? 'bam'
	       :$filename =~ /\.sam(\.gz)?$/i          ? 'sam'
	       :undef;
    
    return ($ftype,\@lines,$eol) if $ftype;

    # otherwise scan the thing until we find a pattern we know about
    # or hit the end of the file. Extra lines that we read are 
    # accumulated into the @lines array.
    my $i = 0;
    while (1) {
	my $line;
	if ($i < $#lines) {
	    $line = $lines[$i++];
	} else {
	    my $line = <$fh>;
	    last unless $line;
	    push @lines,$line;
	}
	return ('featurefile',\@lines,$eol) if $line =~ /^reference/i;
	return ('featurefile',\@lines,$eol) if $line =~ /\w+:\d+\.\.\d+/i;
	return ('gff2',\@lines,$eol)        if $line =~ /^\#\#gff-version\s+2/;
	return ('gff3',\@lines,$eol)        if $line =~ /^\#\#gff-version\s+3/;
	return ('wiggle',\@lines,$eol)      if $line =~ /type=wiggle/;
	return ('bed',\@lines,$eol)         if $line =~ /^\w+\s+\d+\s+\d+/;
	return ('sam',\@lines,$eol)         if $line =~ /^\@[A-Z]{2}/;
	return ('sam',\@lines,$eol)         if $line =~ /^[^ \t\n\r]+\t[0-9]+\t[^ \t\n\r@=]+\t[0-9]+\t[0-9]+\t(?:[0-9]+[MIDNSHP])+|\*/;
    }
    return;
}

sub install_filter {
    my $self = shift;
    my ($in_fh,$command) = @_;

    my $child = open(my $out_fh,"-|");
    defined $child or die "Couldn't fork for pipe: $!";
    return $out_fh if $child;

    # we are in child now
    my $unzip = IO::File->new("| $command") or die "Can't open $command: $!";
    my $buffer;
    while ((my $bytes = read($in_fh,$buffer,8192))>0) {
	$unzip->print($buffer);
    }
    close $unzip;
    exit 0;
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
	$line =~ s/\[(\w+?)_.+_(\d+)(:\d+)?\]/[$1_$2$3]/;
	return $line;
    }
    return;
}

sub CLOSE { close shift->{fh} } 

1;
