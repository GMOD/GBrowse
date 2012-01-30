package Bio::Graphics::Browser2::UserTracks::Filesystem;

# $Id: Filesystem.pm 23607 2010-07-30 17:34:25Z cnvandev $
use strict;
use base 'Bio::Graphics::Browser2::UserTracks';
use Bio::Graphics::Browser2::UserTracks;
use Bio::Graphics::Browser2;
use File::Spec;
use File::Path 'rmtree';
use Cwd;
use Carp "cluck",'croak';

# Filesystem works on the basis of a file-based database with the following structure:
#    base      -- e.g. /var/tmp/gbrowse2/userdata
#    uploadid  -- e.g. dc39b67fb5278c0da0e44e9e174d0b40
#    source    -- e.g. volvox
#    concatenated path /var/tmp/gbrowse2/userdata/volvox/dc39b67fb5278c0da0e44e9e174d0b40

# The concatenated path contains a series of directories named after the track.
# Each directory has a .conf file that describes its contents and configuration.
# There will also be data files associated with the configuration.

# Get Uploaded Files (User) - Returns an array of the paths of files owned by a user.
sub get_uploaded_files {
    my $self = shift;
    return unless $self->{uploadsid};
    my $path = $self->path;
    return unless -e $path;
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
	return unless -e $path;
	my @result;
	opendir D, $path;
	while (my $dir = readdir(D)) {
		next if $dir =~ /^\.+$/;
		next if ($self->is_imported($dir) == 0);
		push @result, $dir;
	}
	return @result;
}

sub get_track_upload_id {
    my $self = shift;
    my $uploadsid = $self->{uploadsid};
    my $id        = $self->SUPER::get_track_upload_id(@_);
    return "$uploadsid:$id";
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
	
    my %track_lookup = $self->track_lookup;
    $track_lookup{$_} = $filename foreach $self->labels($filename);
	
    return $filename;
}

sub share_link {
    my $self = shift;
    my $file = shift or die "No input or invalid input given to share()";
    return $self->share($file);
}

sub share {
    my $self = shift;
    my $fileid = shift;
    my ($uploadsid,$filename) = split ':',$fileid,2;
    my %track_lookup          = $self->track_lookup;
    my $label = 'track_'.substr($uploadsid,0,6).'_'.$filename;
    $track_lookup{$label} = "$uploadsid/$filename";

    # add to user's session
    my $page_settings = $self->page_settings;
    $page_settings->{shared_files}{$label} = $track_lookup{$label};
    $self->session->flush;
}

sub unshare {
    my $self = shift;
    my $file = shift or croak "No input or invalid input given to unshare()";
    my $page_settings = $self->page_settings;
    delete $page_settings->{shared_files}{$file};
    $self->session->flush;
}

# Delete File - Pretty self-explanatory.
sub delete_file {
    my $self = shift;
    my $file  = shift;
    
    my %track_lookup = $self->track_lookup;
    delete $track_lookup{$_} foreach $self->labels($file);
    
    my $loader = Bio::Graphics::Browser2::DataLoader->new($file,
							  $self->track_path($file),
							  $self->track_conf($file),
							  $self->{config},
							  $self->{uploadsid});
    $loader->drop_databases($self->track_conf($file));
    rmtree($self->track_path($file));
}
sub clone_database() { } # do nothing
sub get_added_public_files { return }
sub get_shared_files {
    my $self = shift;
    my $settings = $self->page_settings;
    my $shared_files = $settings->{shared_files} or return;
    return keys %$shared_files;
}

# Created (File) - Returns creation date of $track.
sub created {
    my $self  = shift;
    my $file = shift;
    my $conf = $self->track_conf($file);
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
    my $filename = $self->escape_url($file);
    my $desc  = File::Spec->catfile($self->track_path($file), "$filename.desc");
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
    return !$self->is_mine($file)     ? 'shared'
	:$self->is_imported($file)    ? 'imported'
	:$self->is_mirrored($file)    ? 'imported'
	:'uploaded';
}

# Filename (File) - Returns the filename - is used basically in contrast with Database.pm's filename function, which is more involved.
sub filename {
    my $self = shift;
    my $file = shift;
    if (my $shared_files = $self->page_settings->{shared_files}) {
	return $shared_files->{$file} || $file;
    } else {
	return $file;
    }
}

# Is Mine (File) - Returns if a file belongs to the logged-in user. Since this only works with logged-in users, is always true.
sub is_mine {
    my $self = shift;
    my $file = shift;
    return !exists $self->page_settings->{shared_files}{$file};
}

# Owner (File) - Returns the owner of a file. It's basically used in contrast with Database.pm's owner function.
sub owner {
    return shift->{uploadsid};
}

# Title (File) - Returns the title of a file, which is the filename.
sub title {
    my $self = shift;
    my $filename = $self->filename(shift);
    $filename    =~ s!^[a-f0-9]{32}/!!;
    return $filename;
}

# Get File ID (File) - Returns the ID of a file, which is the filename.
sub get_file_id {
    return shift->filename(shift);
}

sub owner_name {
    return "you";
}

1;
