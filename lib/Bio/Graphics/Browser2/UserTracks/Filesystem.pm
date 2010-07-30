package Bio::Graphics::Browser2::UserTracks::Filesystem;

use strict;
use Bio::Graphics::Browser2::UserTracks;
use Bio::Graphics::Browser2;
use File::Spec;
use File::Path;

use constant DEBUG => 0;

sub new {
	my $class = shift;
	my $self = {};
	my $VERSION = '0.1';
	my $config = shift;
	my $state = shift;
	my $usertracks = shift;
	my $globals = Bio::Graphics::Browser2->open_globals;

	return bless{
		globals => $globals,
		session => $globals->session,
		uuid => shift || $state->{uploadid},
		config => $config,
		state => $state,
		usertracks => $usertracks
	}, ref $class || $class;
}

# Get Owned Files (User) - Returns an array of the paths of files owned by a user.
sub get_owned_files {
    my $self = shift;
    my $path = shift;
	return unless $self->{uuid};
	
	my @result;
	opendir D, $path;
	while (my $dir = readdir(D)) {
		next if $dir =~ /^\.+$/;
		my $is_imported   = (-e File::Spec->catfile($path, $dir, $self->imported_file_name)) || 0;
		next if $is_imported == 1;
		push @result,$dir;
	}
	return @result;
}

# Get Imported Files (User) - Returns an array of files imported by a user.
sub get_imported_files {
	my $self = shift;
	my $path = $self->{usertracks}->path;
	return unless $self->{uuid};

	my @result;
	opendir D,$path;
	while (my $dir = readdir(D)) {
		next if $dir =~ /^\.+$/;
		my $is_imported   = (-e File::Spec->catfile($path, $dir, $self->imported_file_name)) || 0;
		next if $is_imported == 0;
		push @result,$dir;
	}
	return @result;
}

# File Exists (Full Path[, Owner]) - Returns the number of results for a file (and optional owner), 0 if not found.
sub file_exists {
    my $self = shift;
    my $path = shift;
    return (-e $path);
}

# Add File - A placeholder function while DataLoader holds the file uploading bit.
sub add_file {
	my $self = shift;
	return;
}

# Delete File - Also pretty self-explanatory, deletes a user's file as called by the AJAX upload system (on the Upload & Share Tracks tab).
sub delete_file {
    my $self = shift;
    my $track_name  = shift;
    my $files = $self->{files};
    my $username = $self->{username};
    my $userdb = $self->{userdb};
    my $usertracks = $self->{usertracks};
    my $loader = Bio::Graphics::Browser2::DataLoader->new($track_name,
							  $usertracks->track_path($track_name),
							  $usertracks->track_conf($track_name),
							  $self->{config},
							  $self->{state}->{uploadid});
    $loader->drop_databases($usertracks->track_conf($track_name));
    rmtree($usertracks->track_path($track_name));
}

# Created (Track) - Returns creation date of $track.
sub created {
    my $self  = shift;
    my $track = shift;
    my $path = $self->{usertracks}->path;
    my $conf  = File::Spec->catfile($path,$track,"$track.conf");
    return (stat($conf))[10];
}

# Modified (Track) - Returns date modified of $track.
sub modified {
    my $self  = shift;
    my $track = shift;
    return ($self->{usertracks}->conf_metadata($track))[1];
}

# Description (Track[, Description]) - Returns a file's description, or changes the current description if defined.
sub description {
    my $self  = shift;
    my $track = shift;
    my $path = $self->{usertracks}->path;
    my $desc  = File::Spec->catfile($path,$track,"$track.desc");
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

1;
