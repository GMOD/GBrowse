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
	my $which = ($globals->user_accounts == 1)? "database" : "filesystem";
	
	if ($which =~ /filesystem/i) {
		return Bio::Graphics::Browser2::UserTracks::Filesystem->_new(@_);
	} elsif  ($which =~ /database/i) {
		return Bio::Graphics::Browser2::UserTracks::Database->_new(@_);
	} else {
		croak "Could not determine whether to user Filesystem or Database.";
	}
}

sub config   { shift->{config}    }
sub state    { shift->{state}     }    
sub language { shift->{language}  }

# Returns the path to a user's data folder. Uses userdata() from the DataSource object passed as $config to the constructor.
sub path {
    my $self = shift;
    my $uploadsid = $self->{uploadsid};
	return $self->config->userdata($uploadsid);
}

# Tracks - Returns an array of paths to a user's tracks.
sub tracks {
    my $self = shift;
    my $userdb = $self->{userdb};
    my $globals = $self->{globals};
	
	my @tracks;
	push (@tracks, $self->get_uploaded_files, $self->get_imported_files);
	if ($globals->user_accounts == 1) {
		push (@tracks, $self->get_added_public_files, $self->get_shared_files);
	}
	return @tracks;
}

sub is_mirrored {
    my $self  = shift;
    my $filename = $self->filename(shift);
    my $mirror_flag = $self->mirror_flag($filename);
    return unless -e $mirror_flag;
    open(my $i,$mirror_flag);
    my $url = <$i>;
    close $i;
    return $url;
}

sub set_mirrored {
    my $self = shift;
    my $filename = $self->filename(shift);
    my $url = shift;
    my $flagfile = $self->mirror_flag($filename);
    open my $i,">",$flagfile or warn "can't open mirror file: $!";
    print $i $url;
    close $i;
}

# Returns the path to a file's conf file location.
sub conf_files {
    my $self = shift;
    my $path = $self->path;
    my $filename = $self->filename(shift);
    return grep {-e $_} map {File::Spec->catfile($path, $filename, "$filename.conf")} $self->tracks;
}

# Returns path to the folder holding a track.
sub track_path {
    my $self  = shift;
    my $filename = $self->filename(shift);
    return File::Spec->catfile($self->path, $filename);
}

# Returns the full path to the track's data file.
sub data_path {
    my $self = shift;
	my $filename = $self->filename(shift);
    my $datafile = shift;
    return File::Spec->catfile($self->path, $filename, $self->sources_dir_name, $datafile);
}

# Returns the full path to the track's configuration file.
sub track_conf {
    my $self = shift;
    my $filename = $self->filename(shift);
    return File::Spec->catfile($self->path, $filename, "$filename.conf");
}

# Returns a file handle to a conf file.
sub conf_fh {
    my $self = shift;
    my $filename = $self->filename(shift);
    return Bio::Graphics::Browser2::UserConf->fh($self->track_conf($filename));
}

# Returns the location of the import flag file.
sub import_flag {
    my $self = shift;
    my $filename = $self->filename(shift);
    return File::Spec->catfile($self->path, $filename, $self->imported_file_name);
}

sub mirror_flag {
    my $self = shift;
    my $filename = $self->filename(shift);
    return File::Spec->catfile($self->path, $filename, $self->mirrored_file_name);
}

# Returns the modified time and size of a conf file.
sub conf_metadata {
    my $self = shift;
    my $filename = $self->filename(shift);
    my $conf = File::Spec->catfile($self->path, $filename, "$filename.conf");
    my $name = basename($conf);
    return ($name, (stat($conf))[9, 7]);
}

# Source Files - Returns an array of source files (with details) associated with a specified track.
sub source_files {
    my $self = shift;
    my $fileid = shift;
    my $filename = $self->filename($fileid);
    my $path = File::Spec->catfile($self->track_path($fileid), $self->sources_dir_name);
    
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

# Trackname from URL - Gets a track name from a given URL
sub trackname_from_url {
    my $self     = shift;
    my $url      = $self->filename(shift);
    my $uniquefy = shift;

    warn "trackname_from_url($url)" if DEBUG;

    (my $filename = $url) =~ tr/a-zA-Z0-9_%^@.-/_/cs;

    if (length $filename > $self->max_filename) {
		$filename = substr($filename, 0, $self->max_filename);
    }

    my $unique = 0;
    while ($uniquefy && !$unique) {
		my $path = $self->track_path($filename);
		if (-e $path) {
			$filename .= "-0" unless $filename =~ /-\d+$/;
			$filename  =~ s/-(\d+)$/'-'.($1+1)/e; # add +1 to the trackname
		} else {
			$unique++;
		}
    }

    my $path = $self->track_path($filename);
    rmtree($path) if -e $path;  # only happens if uniquefy = 0
    mkpath $path;
    return $filename;
}

# Max filename - Returns the maximum possible length for a file name.
sub max_filename {
    my $self = shift;
    my $length = POSIX::pathconf($self->path, &POSIX::_PC_NAME_MAX) || 255;
    return $length - 4; # give enough room for the suffix
}

# Import URL - Imports a URL for use in the database.
sub import_url {
    my $self = shift;
    my $url       = shift;
    my $overwrite = shift;
    my $privacy_policy = shift // "private";													#/
    my $username = $self->{username};
    my $userdb = $self->{userdb};
    my $userid = $self->{uploadid};

    my $key;
    if ($url =~ m!http://([^/]+).+/(\w+)/\?.*t=([^+;]+)!) {
		my @tracks = split /\+/,$3;
		$key = "Shared track from $1 (@tracks)";
    } else {
    	$key  = "Shared track from $url";
    }

    my $filename = $self->trackname_from_url($url, !$overwrite);
    my $loader = Bio::Graphics::Browser2::DataLoader->new($filename,
							  $self->track_path($filename),
							  $self->track_conf($filename),
							  $self->config,
							  $self->state->{uploadid});
    $loader->strip_prefix($self->config->seqid_prefix);
    $loader->set_status('starting import');

    my $conf = $self->track_conf($filename);
    open (my $f, "+>", $conf) or croak "Couldn't open $conf: $!";
    my @data = $f;

    if ($url =~ /\.bam$/) {
		print $f $self->remote_bam_conf($filename, $url, $key);
    } 
    elsif ($url =~ /\.bw$/) {
		print $f $self->remote_bigwig_conf($filename, $url, $key);
    }
    else {
		print $f $self->remote_mirror_conf($filename, $url, $key);
    }

    close $f;
    open my $i, ">", $self->import_flag($filename);
    close $i;

    $loader->set_processing_complete;
    $self->add_file($url, 1);

    return (1,'',[$filename]);
}

# Attempts to reload a file into the database.
sub reload_file {
    my $self = shift;
    my $filename = $self->filename(shift);
    my @sources = $self->source_files($filename);
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

sub mirror_url {
    my $self = shift;
    my $name = $self->filename(shift);
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
    my @result = $self->upload_file($name, $fh, $result->header('Content-Type') || 'text/plain', $overwrite);
    $self->set_mirrored($name, $url);
    return @result;
}

# Upload Data - Uploads a string of data entered as text (on the Upload & Share Tracks tab).
sub upload_data {
    my $self = shift;
    my ($file_name, $data, $content_type, $overwrite) = @_;
    my $io = IO::String->new($data);
    $self->upload_file($file_name, $io, $content_type, $overwrite);
}

sub upload_url {
    my $self  = shift;
    my $url   = shift;
    my $dir   = tempdir(CLEANUP=>1);
    my $path  = File::Spec->catfile($dir,basename($url));
    eval "require LWP::UserAgent" unless LWP::UserAgent->can('new');
    my $agent = LWP::UserAgent->new();
    my $response = $agent->mirror($url,$path);
    $response->is_success or die $response->status_line;
    my $mime = $response->header('Content-type');
    open my $fh,"<",$path;
    my @args = $self->upload_file(basename($url),$fh,$mime,1);
    unlink $path;
    File::Temp::cleanup();
    return @args;
}

# Upload File - Uploads a user's file, as called by the AJAX upload system (on the Upload & Share Tracks tab).
sub upload_file {
    my $self = shift;
    my ($file_name, $fh, $content_type, $overwrite) = @_;

    warn "$file_name: OVERWRITE = $overwrite" if DEBUG;

    my $filename = $self->trackname_from_url($file_name,!$overwrite);
    my $userid = $self->{userid};
    my $userdb = $self->{userdb};
    
    $content_type ||= '';

    if ($content_type eq 'application/gzip' or $file_name =~ /\.gz$/) {
		$fh = $self->install_filter($fh,'gunzip -c');
    } elsif ($content_type eq 'application/bzip2' or $file_name =~ /\.bz2$/) {
		$fh = $self->install_filter($fh,'bunzip2 -c');
    }
    
    # guess the file type from the first non-blank line
    my ($type,$lines,$eol)   = $self->guess_upload_type($file_name, $fh);
    $lines                 ||= [];
    my (@tracks,$fcgi);

    my $result = eval {
		local $SIG{TERM} = sub { die "cancelled" };
		croak "Could not guess the type of the file $file_name"
			unless $type;

		my $load = $self->get_loader($type, $file_name);
		$load->eol_char($eol);
		@tracks = $load->load($lines, $fh);
		1;
    };
    
    $self->add_file($file_name, 0);

    if ($@ =~ /cancelled/) {
		$self->delete_file($file_name);
		return (0,'Cancelled by user',[]);
    }

    my $msg = $@;
    warn "UPLOAD ERROR: ",$msg if $msg;
    $self->delete_file($file_name) unless $result;
    return ($result,$msg,\@tracks);
}

sub merge_conf {
    my $self = shift;
    my $filename = $self->filename(shift);
    my $new_data = shift;

    my $path = $self->track_conf($filename) or return;

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

sub labels {
    my $self = shift;
    my $filename = $self->filename(shift);
    my $conf = $self->track_conf($filename) or return;
    return grep {!/:(database|\d+)/} eval{ Bio::Graphics::FeatureFile->new(-file=>$conf)->labels };
}

# Status - Returns the status of a DataLoader object for a specific file.
sub status {
    my $self = shift;
    my $filename = $self->filename(shift);
    my $loader = 'Bio::Graphics::Browser2::DataLoader';
    my $load = $loader->new($filename,
			      $self->track_path($filename),
			      $self->track_conf($filename),
			      $self->config,
			      $self->state->{uploadid},
	);
    return $load->get_status();
}

# Get Loader - Returns the loader of the appropriate DataLoader package type for a specific file.
sub get_loader {
    my $self = shift;
    my $type = shift;
    my $filename = $self->filename(shift);
	
    my $module = "Bio::Graphics::Browser2::DataLoader::$type";
    eval "require $module";
    die $@ if $@;
    my $loader = $module->new($filename,
			      $self->track_path($filename),
			      $self->track_conf($filename),
			      $self->config,
			      $self->state->{uploadid},
	);
    $loader->strip_prefix($self->config->seqid_prefix);
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

# Install Filter - Attaches a filter (such as GUNZIP or BUNZIP2) to a file handle.
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
    CORE::exit 0;
}

sub remote_mirror_conf {
    my $self = shift;
    my ($filename,$url,$key) = @_;

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
    my ($filename,$url,$key) = @_;

    my $id = rand(1000);
    my $dbname = "remotebam_$id";
    my $track_id = $filename;# . "_1";

    eval "require Bio::Graphics::Browser2::DataLoader::bam"
	unless Bio::Graphics::Browser2::DataLoader::bam->can('new');
    my $loader = Bio::Graphics::Browser2::DataLoader::bam->new(
	$filename,
	$self->track_path($filename),
	$self->track_conf($filename),
	$self->config,
	$self->state->{uploadid});
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
    my ($filename,$url,$key) = @_;
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
    my ($agent,$url,$fh) = @_;
    $agent->get($url,':content_cb' => sub { print $fh shift; });
}

# These methods are replaced by methods in Filesystem.pm and Database.pm
# Many of these functions are called asynchronously, if you want to connect an AJAX call to one of these functions add a hook in Action.pm
sub modified { warn "modified() has been called without properly inheriting Filesystem.pm or Datbase.pm"; }
# Fill in more once this is all done.

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
    my $globals   = $self->config->globals;
    my $admin_dbs = $globals->admin_dbs 
	or return $self->SUPER::path;
    my $source    = $self->config->name;
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
