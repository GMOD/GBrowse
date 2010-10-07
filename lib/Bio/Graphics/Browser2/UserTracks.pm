package Bio::Graphics::Browser2::UserTracks;

# $Id$
use strict;
use Bio::Graphics::Browser2::DataSource;
use Bio::Graphics::Browser2::DataLoader;
use Bio::Graphics::Browser2::UserTracks::Filesystem;
use Bio::Graphics::Browser2::UserTracks::Database;
use File::Spec;
use File::Basename 'basename';
use File::Path 'mkpath','rmtree';
use IO::File;
use IO::String;
use File::Temp 'tempdir';
use POSIX ();
use Carp qw(croak cluck);
use CGI 'param';

use constant DEBUG => 0;
my $HASBIGWIG;

# The intent of this is to provide a single unified interface for managing a user's uploaded and shared tracks.

# class methods
sub busy_file_name     { 'BUSY'      }
sub status_file_name   { 'STATUS'    }
sub imported_file_name { 'IMPORTED'  }
sub mirrored_file_name { 'MIRRORED'  }
sub sources_dir_name   { 'SOURCES'   }

sub new {
	my $class = shift;
	my $globals = Bio::Graphics::Browser2->open_globals;
	if ($globals->uploads_db =~ /db/i) {
		return Bio::Graphics::Browser2::UserTracks::Database->_new(@_);
	} elsif ($globals->uploads_db =~ /(filesystem|memory)/i) {
		return Bio::Graphics::Browser2::UserTracks::Filesystem->_new(@_);
	} else {
		# Default to filesystem.
		return Bio::Graphics::Browser2::UserTracks::Filesystem->_new(@_);
	}
}

sub database { return (shift =~ /database/i) } # If this changes, also change the constructor.

# Path - Returns the path to a specified file's owner's (or just the logged-in user's) data folder.
sub path {
    my $self = shift;
    my $file = shift;
    my $uploadsid = ($file)? $self->owner($file) : $self->{uploadsid};
	return $self->{config}->userdata($uploadsid);
}

# Tracks - Returns an array of paths to a user's tracks.
sub tracks {
    my $self = shift;	
	my @tracks;
	push @tracks, $self->get_uploaded_files, $self->get_imported_files;
	push @tracks, $self->get_added_public_files, $self->get_shared_files if $self->database;
	return @tracks;
}

# Is Mirrored - Returns the URL if a specific file is mirrored.
sub is_mirrored {
    my $self  = shift;
    my $file = shift;
    my $filename = $self->filename($file);
    my $mirror_flag = $self->mirror_flag($file);
    return unless -e $mirror_flag;
    open(my $i,$mirror_flag);
    my $url = <$i>;
    close $i;
    return $url;
}

# Set Mirrored - Sets the mirror flag.
sub set_mirrored {
    my $self = shift;
    my $file = shift;
    my $filename = $self->filename($file);
    my $url = shift;
    my $flagfile = $self->mirror_flag($file);
    open my $i,">", $flagfile or warn "can't open mirror file: $!";
    print $i $url;
    close $i;
}

# Conf Files (File) - Returns the paths to all tracks' conf files.
sub conf_files {
    my $self = shift;
    my $file = shift;
    return grep {-e $_} map { $self->track_conf($file) } $self->tracks;
}

# Track Path (File) - Returns a verified path to the folder holding a track.
sub track_path {
    my $self  = shift;
    my $file = shift;
    my $filename = $self->filename($file);
    my $folder_name = $self->escape_url($filename);
    return File::Spec->catfile($self->path($file), $folder_name);
}

# Blind Track Path (Filename) - Blindly attaches the userdata path to whatever filename you give it.
sub blind_track_path {
	my $self = shift;
	my $filename = shift;
	return File::Spec->catfile($self->path, $filename);
}

# Data Path (File, Data File) - Returns the full path to a track's original data file.
sub data_path {
    my $self = shift;
	my $file = shift;
    my $filename = $self->filename($file);
    my $datafile = shift;
    return File::Spec->catfile($self->track_path($file), $self->sources_dir_name, $datafile);
}

# Track Conf (File) - Returns the full path to the track's configuration file.
sub track_conf {
    my $self = shift;
    my $file = shift;
    my $filename = $self->filename($file);
    my $conf_file = $self->escape_url($filename) . ".conf";
    return File::Spec->catfile($self->track_path($file), $conf_file);
}

# Conf FH (File) - Returns a file handle to a track's configuration file.
sub conf_fh {
    my $self = shift;
    my $file = shift;
    my $filename = $self->filename($file);
    return Bio::Graphics::Browser2::UserConf->fh($self->track_conf($file));
}

# Import Flag (File) - Returns a track's import flag file.
sub import_flag {
    my $self = shift;
    my $file = shift;
    my $filename = $self->filename($file);
    return File::Spec->catfile($self->track_path($file), $self->imported_file_name);
}

# Mirror Flag (File) - Returns the location of the mirror flag file.
sub mirror_flag {
    my $self = shift;
    my $file = shift;
    my $filename = $self->filename($file);
    return File::Spec->catfile($self->track_path($file), $self->mirrored_file_name);
}

# Conf Metadata (File) - Returns the modified time and size of a track's configuration file.
sub conf_metadata {
    my $self = shift;
    my $file = shift;
    my $filename = $self->filename($file);
    my $conf = File::Spec->catfile($self->track_path($file), "$filename.conf");
    my $name = basename($conf);
    return ($name, (stat($conf))[9, 7]);
}

# Source Files (File) - Returns an array of source files (with details) associated with a specified track.
sub source_files {
    my $self = shift;
    my $file = shift;
    my $filename = $self->filename($file);
    my $path = File::Spec->catfile($self->track_path($file), $self->sources_dir_name);
    
    my @files;
    if (opendir my $dir, $path) {
		while (my $f = readdir($dir)) {
			my $path = File::Spec->catfile($path, $f);
			next unless -f $path;
			my ($size, $mtime) = (stat(_))[7,9];
			push @files, [$f, $size, $mtime, $path];
		}
    }
    return @files;
}

# Escape URL (URL[, Uniquefy]) - Gets an escaped name from a given URL.
sub escape_url {
	my $self     = shift;
    my $url      = shift;
    my $uniquefy = shift;

	# Remove any illegal chars
    (my $filename = $url) =~ tr/a-zA-Z0-9_%^@.-/_/cs;
	
	# Cut the length at the maximum filename.
    if (length $filename > $self->max_filename) {
		$filename = substr($filename, 0, $self->max_filename);
    }
	
	# If the file isn't unique, add a number on the end.
    my $unique = 0;
    while ($uniquefy && !$unique) {
		my $path = $self->blind_track_path($filename);
		if (-e $path) {
			$filename .= "-0" unless $filename =~ /-\d+$/;
			$filename  =~ s/-(\d+)$/'-'.($1+1)/e; # add +1 to the trackname
		} else {
			$unique++;
		}
    }
    return $filename;
}

# Trackname from URL (URL[, Uniquefy]) - Gets a track name from a given URL and creates the folder to hold it.
sub trackname_from_url {
    my $self     = shift;
    my $url      = shift;
    my $uniquefy = shift;

    warn "trackname_from_url($url)" if DEBUG;
    
    my $filename = $self->escape_url($url, $uniquefy);
    my $path = $self->blind_track_path($filename);
    
    rmtree($path) if -e $path;  # only happens if uniquefy = 0
    mkpath $path;
    return $filename;
}

# Max filename () - Returns the maximum possible length for a file name.
sub max_filename {
    my $self = shift;
    my $length = POSIX::pathconf($self->path, &POSIX::_PC_NAME_MAX) || 255;
    return $length - 4; # give enough room for the suffix
}

# Import URL (URL, Overwrite[, Privacy Policy]) - Imports a URL for use in the database.
sub import_url {
    my $self = shift;
    my $url       = shift;
    my $overwrite = shift;
    my $privacy_policy = shift || "private";
    my $username = $self->{username};

    my $key;
    if ($url =~ m!http://([^/]+).+/(\w+)/\?.*t=([^+;]+)!) {
		my @tracks = split /\+/,$3;
		$key = "Shared track from $1 (@tracks)";
    } else {
    	$key  = "Shared track from $url";
    }

    my $filename = $self->trackname_from_url($url, !$overwrite);
    my $file = $self->add_file($filename, 1);
    
    my $loader = Bio::Graphics::Browser2::DataLoader->new($filename,
							  $self->track_path($file),
							  $self->track_conf($file),
							  $self->{config},
							  $self->{uploadsid});
    $loader->strip_prefix($self->{config}->seqid_prefix);
    $loader->set_status('starting import');

    my $conf = $self->track_conf($file);
    open (my $f, "+>", $conf) or croak "Couldn't open $conf: $!";
    my @data = $f;

    if ($url =~ /\.bam$/) {
		print $f $self->remote_bam_conf($file, $url, $key);
    } 
    elsif ($url =~ /\.bw$/) {
		print $f $self->remote_bigwig_conf($file, $url, $key);
    }
    else {
		print $f $self->remote_mirror_conf($file, $url, $key);
    }

    close $f;
    open my $i, ">", $self->import_flag($file);
    close $i;

    $loader->set_processing_complete;
	
    return (1, '', [$filename]);
}

# Reload File (File) - Attempts to reload a file into the database.
sub reload_file {
    my $self = shift;
    my $file = shift;
    my $filename = $self->filename($file);
    my @sources = $self->source_files($file);
    for my $s (@sources) {
		my ($name, $size, $mtime, $path) = @$s;
		rename $path, "$path.bak" or next;
		my $io = IO::File->new("$path.bak") or next;
		my ($result) = $self->upload_file($name, $io,'',1);
		if ($result) {
			unlink "$path.bak";
		} else {
			rename "$path.bak", $path;
		}
    }
}

# Mirror URL (Filename, URL, Overwrite?) - Attempts to "mirror" a file on a URL, to avoid fetching it every time.
sub mirror_url {
    my $self = shift;
    my $filename = shift;
    my $url = shift;
    my $overwrite = shift;

    warn "mirroring..." if DEBUG;

    if ($url =~ /\.(bam|bw)$/ or $url =~ /\b(gbgff|das)\b/) {
		return $self->import_url($url, $overwrite);
    }

    # first we do a HEAD to validate that the thing exists
    eval "require LWP::UserAgent" unless LWP::UserAgent->can('new');
    my $agent  = LWP::UserAgent->new();
    my $result = $agent->head($url);
    unless ($result->is_success) {
		my $msg = $url.': '.$result->status_line;
		warn $msg if DEBUG;
		return (0,$msg,[]);
    }

    # fetch in one process, process in another
    eval "use IO::Pipe" unless IO::Pipe->can('new');
    my $fh  = IO::Pipe->new;
    my $child = Bio::Graphics::Browser2::Render->fork();
    die "Couldn't fork" unless defined $child;

    unless ($child) {
		warn "printing from child..." if DEBUG;
		$fh->writer();
		$self->_print_url($agent, $url, $fh);
		CORE::exit 0;
    }
    $fh->reader;
    my @result = $self->upload_file($filename, $fh, $result->header('Content-Type') || 'text/plain', $overwrite);
    my $file = $self->get_file_id($filename);
    $self->set_mirrored($file, $url);
    return @result;
}

# Upload Data (Filename, Data, Content Type, Overwrite?) - Uploads a string of data entered as text (on the Upload & Share Tracks tab).
sub upload_data {
    my $self = shift;
    my ($file_name, $data, $content_type, $overwrite) = @_;
    my $io = IO::String->new($data);
    $self->upload_file($file_name, $io, $content_type, $overwrite);
}

# Upload URL (URL) - Uploads a file at a specified URL to the database.
sub upload_url {
    my $self  = shift;
    my $url   = shift;
    my $dir   = tempdir(CLEANUP=>1);
    my $path  = File::Spec->catfile($dir, basename($url));
    eval "require LWP::UserAgent" unless LWP::UserAgent->can('new');
    my $agent = LWP::UserAgent->new();
    my $response = $agent->mirror($url, $path);
    $response->is_success or die $response->status_line;
    my $mime = $response->header('Content-type');
    open my $fh,"<",$path;
    my @args = $self->upload_file(basename($url),$fh,$mime,1);
    unlink $path;
    File::Temp::cleanup();
    return @args;
}

# Upload File (Filename, File Handle, Content Type, Overwrite?) - Uploads a user's file, as called by the AJAX upload system (on the Upload & Share Tracks tab) via Action.pm.
sub upload_file {
    my $self = shift;
    my ($file_name, $fh, $content_type, $overwrite) = @_;

    warn "$file_name: OVERWRITE = $overwrite" if DEBUG;

    my $filename = $self->trackname_from_url($file_name, !$overwrite);
    
    $content_type ||= '';

    if ($content_type eq 'application/gzip' or $file_name =~ /\.gz$/) {
		$fh = $self->install_filter($fh,'gunzip -c');
    } elsif ($content_type eq 'application/bzip2' or $file_name =~ /\.bz2$/) {
		$fh = $self->install_filter($fh,'bunzip2 -c');
    }
    
    my $file = $self->add_file($filename);
    
    # guess the file type from the first non-blank line
    my ($type, $lines, $eol) = $self->guess_upload_type($file, $fh);
    $lines ||= [];
    my (@tracks, $fcgi);

    my $result = eval {
		local $SIG{TERM} = sub { die "cancelled" };
		croak "Could not guess the type of the file $file_name"	unless $type;

		my $load = $self->get_loader($type, $file);
		$load->eol_char($eol);
		@tracks = $load->load($lines, $fh);
		1;
    };

    if ($@ =~ /cancelled/) {
		$self->delete_file($file);
		return (0,'Cancelled by user',[]);
    }

    my $msg = $@;
    warn "UPLOAD ERROR: ", $msg if $msg;
    $self->delete_file($file) unless $result;
    return ($result, $msg, \@tracks);
}

# Merge Conf (File, New Data) - Merges new data into a track's configuration file.
sub merge_conf {
    my $self = shift;
    my $file = shift;
    my $filename = $self->filename($file);
    my $new_data = shift;

    my $path = $self->track_conf($file) or return;

    my @lines = split /\r\n|\r|\n/,$new_data;
    my (%stanzas, $current_stanza);
    for (@lines) {
		if (/^\[(.+)\]/) {
			$current_stanza = $1;
			$stanzas{$current_stanza} = '';
		} elsif ($current_stanza) {
			$stanzas{$current_stanza} .= "$_\n";
		}
    }

    open my $fh, $path or croak "$path: $!";
    my $merged = '';
    my @database;
    # read header with the [database] definition
    while (<$fh>) {
		$merged .= $_;
		push @database,$1 if /^\[(.+):database/;
		last if /cut here/;
    }

    $merged .= "\n";

    # read the rest
    while (<$fh>) {
	if (/^\[/) {
	    (my $stanza = $_) =~ s/\[(\w+?)_.+_(\d+)(:\d+)?\]\s*\n/$1_$2$3/;
	    $stanza =~ s/^\[//; # just in case
	    $stanza =~ s/\]\n//;
	    if (my $body = $stanzas{$stanza}) {
		$merged .= $_;
		$merged .= $body;
		delete $stanzas{$stanza};
	    }
	}
    }

    # anything that's left (new stuff)
    for my $stanza (keys %stanzas) {
	$merged .= "\n[$stanza]\n";
	$merged .= $stanzas{$stanza};
    }

    $merged =~ s/database_(\d+).+/$database[$1]/g;

    open $fh,'>',$path or croak "Can't open $path for writing: $!";
    print $fh $merged;
    close $fh;
}

#Labels (File) - Returns the track labels for a specified uploaded file.
sub labels {
    my $self = shift;
    my $file = shift;
    my $filename = $self->filename($file);
    my $conf = $self->track_conf($file) or return;
    return grep {!/:(database|\d+)/} eval{ Bio::Graphics::FeatureFile->new(-file=>$conf)->labels };
}

# Status (File) - Returns the status of a DataLoader object for a specific file.
sub status {
    my $self = shift;
    my $file = shift;
    my $filename = $self->filename($file);
    my $loader = 'Bio::Graphics::Browser2::DataLoader';
    my $load = $loader->new($filename,
			      $self->track_path($file),
			      $self->track_conf($file),
			      $self->{config},
			      $self->{uploadsid},
	);
    return $load->get_status();
}

# Get Loader (Type, File) - Returns the loader of the appropriate DataLoader package type for a specific file.
sub get_loader {
    my $self = shift;
    my $type = shift;
    my $file = shift;
    my $filename = $self->filename($file);
	
    my $module = "Bio::Graphics::Browser2::DataLoader::$type";
    eval "require $module";
    die $@ if $@;
    
    my $loader = $module->new($filename,
			      $self->track_path($file),
			      $self->track_conf($file),
			      $self->{config},
			      $self->{uploadsid},
	);
    $loader->strip_prefix($self->{config}->seqid_prefix);
    return $loader;
}

# guess the file type and eol based on its name and the first 1024 bytes
# of the file. The @$lines will contain the lines that were consumed
# during this operation so that the info isn't lost.
sub guess_upload_type {
    my $self = shift;
    my ($type, $lines, $eol) = $self->_guess_upload_type(@_);
    $type = 'bigwig' if $type eq 'wiggle' && $self->has_bigwig;
    return ($type, $lines, $eol);
}

sub _guess_upload_type {
    my $self = shift;
    my $file = shift;
    my $filename = $self->filename($file);
    my $fh = shift;

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
	if ($i <= $#lines) {
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

sub has_bigwig {
    my $self = shift;
    return $HASBIGWIG if defined $HASBIGWIG;
    return $HASBIGWIG = 1 if Bio::DB::BigWig->can('new');
    my $result = eval "require Bio::DB::BigWig; 1";
    return $HASBIGWIG = $result || 0;
}

# Install Filter (File Handle, Command) - Attaches a filter (such as GUNZIP or BUNZIP2) to a file handle.
sub install_filter {
    my $self = shift;
    my ($in_fh, $command) = @_;

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
    CORE::exit 0;
}

sub remote_mirror_conf {
    my $self = shift;
    my $file = shift;
    my $filename = $self->filename($file);
    my ($url, $key) = @_;

    return <<END;
>>>>>>>>>>>>>> cut here <<<<<<<<<<<<
[$filename]
remote feature = $url
category = My Tracks:Remote Tracks
key      = $key
END
    ;
}

sub remote_bam_conf {
    my $self = shift;
    my $file = shift;
    my $filename = $self->filename($file);
    my ($url, $key) = @_;

    my $id = rand(1000);
    my $dbname = "remotebam_$id";
    my $track_id = $filename;# . "_1";

    eval "require Bio::Graphics::Browser2::DataLoader::bam"
	unless Bio::Graphics::Browser2::DataLoader::bam->can('new');
    my $loader = Bio::Graphics::Browser2::DataLoader::bam->new(
	$filename,
	$self->track_path($file),
	$self->track_conf($file),
	$self->{config},
	$self->{uploadsid});
    my $fasta  = $loader->get_fasta_file;

    return <<END;
[$dbname:database]
db_adaptor = Bio::DB::Sam
db_args    = -bam           $url
             -split_splices 1
             -fasta         $fasta
search options = none

>>>>>>>>>>>>>> cut here <<<<<<<<<<<<

[$track_id:2001]
feature   = coverage:2000
min_score    = 0
glyph        = wiggle_xyplot
height       = 50
fgcolor      = black
bgcolor      = black
autoscale    = local


[$track_id]
database     = $dbname
feature      = read_pair
glyph        = segments
draw_target  = 1
show_mismatch = 1
mismatch_color = red
bgcolor      = blue
fgcolor      = blue
height       = 3
label        = 1
label density = 50
bump         = fast
key          = $key
END
    ;
}

sub remote_bigwig_conf {
    my $self = shift;
    my $file = shift;
    my $filename = $self->filename($file);
    my ($url, $key) = @_;
    my $id = rand(1000);
    my $dbname = "remotebw_$id";
    my $track_id = $filename;
    warn "remote_bigwig_conf";
    return <<END;
[$dbname:database]
db_adaptor = Bio::DB::BigWig
db_args    = -bigwig $url
search options = none

>>>>>>>>>>>>>> cut here <<<<<<<<<<<<
[$track_id]
database        = $dbname
feature         = summary
glyph           = wiggle_whiskers
max_color       = lightgrey
min_color       = lightgrey
mean_color      = black
stdev_color     = grey
stdev_color_neg = grey
height          = 20

END
}

sub _print_url {
    my $self = shift;
    my ($agent, $url, $fh) = @_;
    $agent->get($url,':content_cb' => sub { print $fh shift; });
}

# These methods are replaced by methods in Filesystem.pm and Database.pm
# Many of these functions are called asynchronously, if you want to connect an AJAX call to one of these functions add a hook in Action.pm
sub get_file_id { warn "get_file_id() has been called, without properly inheriting subclass Datbase.pm"; }
sub filename { warn "filename() has been called, without properly inheriting a subclass (like Filesystem.pm or Datbase.pm)"; }
sub nowfun { warn "nowfun() has been called, without properly inheriting subclass Datbase.pm"; }
sub get_uploaded_files { warn "get_uploaded_files() has been called, without properly inheriting a subclass (like Filesystem.pm or Datbase.pm)"; }
sub get_public_files { warn "get_public_files() has been called, without properly inheriting subclass Datbase.pm"; }
sub get_imported_files { warn "get_imported_files() has been called, without properly inheriting a subclass (like Filesystem.pm or Datbase.pm)"; }
sub get_shared_files { warn "get_shared_files() has been called, without properly inheriting subclass Datbase.pm"; }
sub share { warn "share() has been called, without properly inheriting subclass Datbase.pm"; }
sub unshare { warn "unshare() has been called, without properly inheriting subclass Datbase.pm"; }
sub field { warn "field() has been called, without properly inheriting subclass Datbase.pm"; }
sub update_modified { warn "update_modified() has been called, without properly inheriting subclass Datbase.pm"; }
sub created { warn "created() has been called, without properly inheriting a subclass (like Filesystem.pm or Datbase.pm)"; }
sub modified { warn "modified() has been called, without properly inheriting a subclass (like Filesystem.pm or Datbase.pm)"; }
sub description { warn "description() has been called, without properly inheriting a subclass (like Filesystem.pm or Datbase.pm)"; }
sub add_file { warn "add_file() has been called, without properly inheriting a subclass (like Filesystem.pm or Datbase.pm)"; }
sub delete_file { warn "delete_file() has been called, without properly inheriting a subclass (like Filesystem.pm or Datbase.pm)"; }
sub is_imported { warn "is_imported() has been called, without properly inheriting a subclass (like Filesystem.pm or Datbase.pm)"; }
sub permissions { warn "permissions() has been called, without properly inheriting subclass Datbase.pm"; }
sub is_mine { warn "is_mine() has been called, without properly inheriting a subclass (like Filesystem.pm or Datbase.pm)"; }
sub owner { warn "owner() has been called, without properly inheriting a subclass (like Filesystem.pm or Datbase.pm)"; }
sub is_shared_with_me { warn "is_shared_with_me() has been called, without properly inheriting subclass Datbase.pm"; }
sub sharing_link { warn "sharing_link() has been called, without properly inheriting subclass Datbase.pm"; }
sub file_type { warn "file_type() has been called, without properly inheriting a subclass (like Filesystem.pm or Datbase.pm)"; }
sub shared_with { warn "shared_with() has been called, without properly inheriting subclass Datbase.pm"; }
sub file_exists { warn "file_exists() has been called, without properly inheriting subclass Filesystem.pm"; }

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
	_db      => {},  # remember db names
	-didx    => 0,   # db indexes
    },$class;
}

sub READLINE {
    my $self = shift;
    my $fh   = $self->{fh};

    while (my $line = <$fh>) {
	$self->{_db}{$1} = $self->{_didx}++ if $line =~ /^\[(.+):database/;
	if ($line =~ /cut here/i) {
	    $self->{seen_cut}++;
	    next;
	}
	next unless $self->{seen_cut};
	$line =~ s/database\s*=\s*(.+)/database = database_$self->{_db}{$1} # do not change this!/;
	$line =~ s/\[(\w+?)_.+_(\d+)(:\d+)?\]/[$1_$2$3]/;
	return $line;
    }
    return;
}

sub CLOSE { close shift->{fh} } 

# this is for the administrator-uploaded tracks.
# we simply change the location of the uploads
package Bio::Graphics::Browser2::AdminTracks;
use base 'Bio::Graphics::Browser2::UserTracks';

sub path {
    my $self    = shift;
    my $globals   = $self->{globals};
    my $admin_dbs = $globals->admin_dbs 
	or return $self->SUPER::path;
    my $source    = $self->{config}->name;
    my $path      = File::Spec->catfile($admin_dbs,$source);
    return $path;
}

sub get_loader {
    my $self = shift;
    my $loader = $self->SUPER::get_loader(@_);
    $loader->force_category('General');
    return $loader;
}

1;
