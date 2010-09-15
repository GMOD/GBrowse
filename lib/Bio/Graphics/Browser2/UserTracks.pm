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
use POSIX ();
use Carp qw(croak cluck);
use CGI 'param';

use constant DEBUG => 0;
my $HASBIGWIG;

# The intent of this is to provide a single unified interface for managing a user's uploaded and shared tracks.

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

# class methods
sub busy_file_name     { 'BUSY'      }
sub status_file_name   { 'STATUS'    }
sub imported_file_name { 'IMPORTED'  }
sub sources_dir_name   { 'SOURCES'   }

# Source Files - Returns an array of source files (with details) associated with a specified track.
sub source_files {
    my $self = shift;
    my $track = shift;
    my $path = File::Spec->catfile($self->track_path($track), $self->sources_dir_name);
    $path = $self->trackname_from_url($path, 0) if ($self->is_imported($track) == 1);
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

# Returns the path to a user's data folder. Uses userdata() from the DataSource object passed as $config to the constructor.
sub path {
    my $self = shift;
    my $uploadid = $self->{uploadsid};
	return $self->{config}->userdata($uploadid);
}

# Returns the path to the conf files associated with all tracks.
sub conf_files {
    my $self = shift;
    my $path = $self->path;
    return grep {-e $_} map {File::Spec->catfile($path, $_, "$_.conf")} $self->tracks;
}

# Returns path to a file holding a track.
sub track_path {
    my $self  = shift;
    my $track = shift;
    my $path = $self->path;
    return File::Spec->catfile($path, $track);
}

# Returns the full path to the track's data file.
sub data_path {
    my $self = shift;
    my ($track,$datafile) = @_;
    my $path = $self->path;
    return File::Spec->catfile($path, $track, $self->sources_dir_name, $datafile);
}

# Returns the full path to the track's configuration file.
sub track_conf {
    my $self  = shift;
    my $track = shift;
    my $path = $self->path;
	return File::Spec->catfile($path, $track, "$track.conf");
}

# Returns the location of the import flag file..
sub import_flag {
    my $self  = shift;
    my $track = shift;
    my $path = $self->path;
    return File::Spec->catfile($path, $track, $self->imported_file_name);
}

# Returns the modified time and size of a conf file.
sub conf_metadata {
    my $self  = shift;
    my $track = shift;
    my $conf  = File::Spec->catfile($self->path, $track, "$track.conf");
    my $name  = basename($conf);
    return ($name,(stat($conf))[9,7]);
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

# Max filename - Returns the maximum possible length for a file name.
sub max_filename {
    my $self = shift;
    my $path = $self->path;
    my $length = POSIX::pathconf($path, &POSIX::_PC_NAME_MAX) || 255;
    return $length - 4; # give enough room for the suffix
}

# Trackname from URL - Gets a track name from a given URL
sub trackname_from_url {
    my $self     = shift;
    my $url      = shift;
    my $uniquefy = shift;

    (my $track_name=$url) =~ tr!a-zA-Z0-9_%^@.-!_!cs;

    if (length $track_name > $self->max_filename) {
		$track_name = substr($track_name, 0, $self->max_filename);
    }

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

# Upload Data - Uploads a string of data entered as text (on the Upload & Share Tracks tab).
sub upload_data {
    my $self = shift;
    my ($file_name,$data,$content_type,$overwrite) = @_;
    
    my $io = IO::String->new($data);
    $self->upload_file($file_name,$io,$content_type,$overwrite);
}

# Upload File - Uploads a user's file, as called by the AJAX upload system (on the Upload & Share Tracks tab).
sub upload_file {
    my $self = shift;
    my ($file_name, $fh, $content_type, $overwrite) = @_;
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

    my $track_name = $self->trackname_from_url($url,!$overwrite);
    my $loader = Bio::Graphics::Browser2::DataLoader->new($track_name,
							  $self->track_path($track_name),
							  $self->track_conf($track_name),
							  $self->{config},
							  $userid);
    $loader->set_status('starting import');

    my $conf = $self->track_conf($track_name);
    open (my $f, "+>", $conf) or croak "Couldn't open $conf: $!";
    my @data = $f;

    if ($url =~ /\.bam$/) {
		print $f $self->remote_bam_conf($track_name, $url, $key);
    } 
    elsif ($url =~ /\.bw$/) {
		print $f $self->remote_bigwig_conf($track_name, $url, $key);
    }
    else {
		print $f $self->remote_mirror_conf($track_name, $url, $key);
    }
    close $f;
    open my $i, ">", $self->import_flag($track_name);
    close $i;

    $loader->set_processing_complete;
    $self->add_file($url, 1);

    return (1,'',[$track_name]);
}

# Attempts to reload a file into the database.
sub reload_file {
    my $self = shift;
    my $track = shift;
    my @sources = $self->source_files($track);
    for my $s (@sources) {
		my ($name,$size,$mtime,$path) = @$s;
		rename $path,"$path.bak"            or next;
		my $io = IO::File->new("$path.bak") or next;
		my ($result) = $self->upload_file($name,$io,'',1);
		if ($result) {
			unlink "$path.bak";
		} else {
			rename "$path.bak",$path;
		}
    }
}

# Returns a file handle to a conf file.
sub conf_fh {
    my $self = shift;
    my $track = shift;
    my $path = $self->path;
    $track = $self->trackname_from_url($track) if ($self->is_imported($track) == 1);
    return Bio::Graphics::Browser2::UserConf->fh($self->track_conf($track));
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
    my $self       = shift;
    my $track_name = shift;
    my $conf       = $self->track_conf($track_name) or return;
    return grep {!/:(database|\d+)/} eval{Bio::Graphics::FeatureFile->new(-file=>$conf)->labels};
}

# Status - Returns the status of a DataLoader object for a specific file.
sub status {
    my $self     = shift;
    my $filename = shift;

    my $loader   = 'Bio::Graphics::Browser2::DataLoader';
    my $load   = $loader->new($filename,
			      $self->track_path($filename),
			      $self->track_conf($filename),
			      $self->{config},
			      $self->{uploadid},
	);
    return $load->get_status();
}

# Get Loader - Returns the loader of the appropriate DataLoader package type for a specific file.
sub get_loader {
    my $self   = shift;
    my ($type,$track_name) = @_;
    
    my $module = "Bio::Graphics::Browser2::DataLoader::$type";
    eval "require $module";
    die $@ if $@;
    return $module->new($track_name,
			$self->track_path($track_name),
			$self->track_conf($track_name),
			$self->{config},
			$self->{uploadid},
	);
}

# guess the file type and eol based on its name and the first 1024 bytes
# of the file. The @$lines will contain the lines that were consumed
# during this operation so that the info isn't lost.
sub guess_upload_type {
    my $self = shift;
    my ($type,$lines,$eol) = $self->_guess_upload_type(@_);
    $type = 'bigwig' if $type eq 'wiggle' && $self->has_bigwig;
    return ($type,$lines,$eol);
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
    my ($track_name,$url,$key) = @_;

    return <<END;
>>>>>>>>>>>>>> cut here <<<<<<<<<<<<
[$track_name]
remote feature = $url
category = My Tracks:Remote Tracks
key      = $key
END
    ;
}

sub remote_bam_conf {
    my $self = shift;
    my ($track_name,$url,$key) = @_;

    my $id = rand(1000);
    my $dbname = "remotebam_$id";
    my $track_id = $track_name;# . "_1";

    eval "require Bio::Graphics::Browser2::DataLoader::bam"
	unless Bio::Graphics::Browser2::DataLoader::bam->can('new');
    my $loader = Bio::Graphics::Browser2::DataLoader::bam->new(
	$track_name,
	$self->track_path($track_name),
	$self->track_conf($track_name),
	$self->{config},
	$self->{uploadid});
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
    my ($track_name,$url,$key) = @_;
    my $id = rand(1000);
    my $dbname = "remotebw_$id";
    my $track_id = $track_name;
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

# These methods are replaced by methods in Filesystem.pm and Database.pm
# Many of these functions are called asynchronously, if you want to connect an AJAX call to one of these functions add a hook in Action.pm
sub modified { warn "modified() has been called without properly inheriting Filesystem.pm or Datbase.pm"; }
sub created { warn "created() has been called without properly inheriting Filesystem.pm or Datbase.pm"; }
sub description { warn "description() File::Spechas been called without properly inheriting Filesystem.pm or Datbase.pm"; }
sub add_file { warn "add_file() has been called without properly inheriting Filesystem.pm or Datbase.pm"; }
sub delete_file { warn "delete_file() has been called without properly inheriting Filesystem.pm or Datbase.pm"; }
sub get_uploaded_files { warn "get_uploaded_files() has been called without properly inheriting Filesystem.pm or Datbase.pm"; }
sub get_imported_files { warn "get_imported_files() has been called without properly inheriting Filesystem.pm or Datbase.pm"; }

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
    my $globals   = $self->{config}->globals;
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
