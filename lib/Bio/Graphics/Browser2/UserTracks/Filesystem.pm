package Bio::Graphics::Browser2::UserTracks::Filesystem;

# $Id: Filesystem.pm 23607 2010-07-30 17:34:25Z cnvandev $
use strict;
use base 'Bio::Graphics::Browser2::UserTracks';
use Bio::Graphics::Browser2::UserTracks;
use Bio::Graphics::Browser2;
use File::Spec;
use File::Path 'remove_tree';
use Cwd;
use Carp "cluck";

# Filesystem works on the basis of a file-based database with the following structure:
#    base      -- e.g. /var/tmp/gbrowse2/userdata
#    uploadid  -- e.g. dc39b67fb5278c0da0e44e9e174d0b40
#    source    -- e.g. volvox
#    concatenated path /var/tmp/gbrowse2/userdata/volvox/dc39b67fb5278c0da0e44e9e174d0b40

# The concatenated path contains a series of directories named after the track.
# Each directory has a .conf file that describes its contents and configuration.
# There will also be data files associated with the configuration.

sub _new {
	my $class = shift;
	my $VERSION = '0.3';
	my ($data_source, $globals, $uploadsid) = @_;
	
    return bless {
		config		=> $data_source,
		uploadsid	=> $uploadsid,
		globals		=> $globals
    }, ref $class || $class;
}

# Get Uploaded Files (User) - Returns an array of the paths of files owned by a user.
sub get_uploaded_files {
    my $self = shift;
    return unless $self->{uploadsid};
    my $path = $self->path;	
	my @result;
	opendir D, $path;
	while (my $dir = readdir(D)) {
		next if $dir =~ /^\.+$/;
		next if ($self->is_imported($dir) == 1);
		push @result, $dir;
	}
	return @result;
}

# Get Imported Files (User) - Returns an array of files imported by a user.
sub get_imported_files {
	my $self = shift;
	return unless $self->{uploadsid};
	my $path = $self->path;
	my @result;
	opendir D, $path;
	while (my $dir = readdir(D)) {
		next if $dir =~ /^\.+$/;
		next if ($self->is_imported($dir) == 0);
		push @result, $dir;
	}
	return @result;
}

# File Exists (Full Path[, Owner]) - Returns the number of results for a file, 0 if not found.
sub file_exists {
    my $self = shift;
    my $path = shift;
    return (-e $path);
}

# Add File - A placeholder function while UserTracks holds the file uploading bit.
sub add_file {
	my $self = shift;
	my $filename = shift;
	return $filename;
}

# Delete File - Pretty self-explanatory.
sub delete_file {
    my $self = shift;
    my $file  = shift;
    my $loader = Bio::Graphics::Browser2::DataLoader->new($file,
							  $self->track_path($file),
							  $self->track_conf($file),
							  $self->{config},
							  $self->{uploadsid});
    $loader->drop_databases($self->track_conf($file));
    remove_tree($self->track_path($file));
}

# Created (File) - Returns creation date of $track.
sub created {
    my $self  = shift;
    my $file = shift;
    my $path = $self->path;
    my $conf  = File::Spec->catfile($path, $file, "$file.conf");
    return (stat($conf))[10];
}

# Modified (File) - Returns date modified of $track.
sub modified {
    my $self  = shift;
    my $file = shift;
    return ($self->conf_metadata($file))[1];
}

# Description (File[, Description]) - Returns a file's description, or changes the current description if defined.
sub description {
    my $self  = shift;
    my $file = shift;
    my $path = $self->path;
    my $desc  = File::Spec->catfile($path, $file, "$file.desc");
    if (@_) {
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

# Is Imported (File) - Returns 1 if an already-added track is imported, 0 if not.
sub is_imported {
	my $self = shift;
	my $file = shift;
	return (-e File::Spec->catfile($self->track_path($file), $self->imported_file_name))? 1 : 0;
}

# File Type (File) - Returns the type of a specified track.
sub file_type {
	my $self = shift;
	my $file = shift;
	return ($self->is_imported($file) || $self->is_mirrored($file))? "imported" : "uploaded";
}

# Filename (File) - Returns the filename - is used basically in contrast with Database.pm's filename function, which is more involved.
sub filename {
	my $self = shift;
	my $file = shift;
	return $file;
}

# Is Mine (File) - Returns if a file belongs to the logged-in user. Since this only works with logged-in users, is always true.
sub is_mine {
	return 1;
}

# Owner (File) - Returns the owner of a file. It's basically used in contrast with Database.pm's owner function.
sub owner {
	return shift->{uploadsid};
}

# Title (File) - Returns the title of a file, which is the filename.
sub title {
    return shift->filename(shift);
}

# Get File ID (File) - Returns the ID of a file, which is the filename.
sub get_file_id {
    return shift->filename(shift);
}

1;
