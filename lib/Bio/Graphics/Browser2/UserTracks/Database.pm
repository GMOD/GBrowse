package Bio::Graphics::Browser2::UserTracks::Database;

use strict;
use Bio::Graphics::Browser2;
use Bio::Graphics::Browser2::UserDB;
use Bio::Graphics::Browser2::UserTracks;
use Bio::Graphics::Browser2::UserTracks::Filesystem;
use DBI;
use Digest::MD5 qw(md5_hex);

sub new {
	my $class = shift;
	my $self = {};
	my $VERSION = '0.1';
	my $filesystem = shift;
	my $globals = Bio::Graphics::Browser2->open_globals;
	my $userdb = shift || Bio::Graphics::Browser2::UserDB->new();
	my $credentials  = shift || $globals->user_account_db;
	my $session = $globals->session;

	my $login = DBI->connect($credentials);
	unless ($login) {
		print header();
		print "Error: Could not open login database.";
		die "Could not open login database $credentials";
	}

	my $self = bless {
		dbi => $login,
		globals => $globals,
		session => $session,
		username => $session->username,
		userdb => $userdb,
		filesystem => $filesystem
	}, ref $class || $class;
	return $self;
}

# Get File ID (Full Path) - Returns a file's ID from the database.
sub get_file_id{
    my $self = shift;
    my $userdb = $self->{dbi};
    my $path = $userdb->quote(shift);
    my $userid = shift;
    
    my $if_user = $userid ? "ownerid = " . $userdb->quote($userid) . " AND " : "";
    return $userdb->selectrow_array("SELECT uploadid FROM uploads WHERE " . $if_user . "path = $path");
}

# Get Owned Files (User) - Returns an array of the paths of files owned by a user.
sub get_owned_files {
    my $self = shift;
    my $userdb = $self->{dbi};
    my $ownerid = $userdb->quote(shift);
    if ($ownerid eq "") {
		warn "No userid specified to get_owned_files";
    } else {
    	my $rows = $userdb->selectcol_arrayref("SELECT path FROM uploads WHERE ownerid = $ownerid AND path NOT LIKE '%\$%' ORDER BY uploadid");
		return @{$rows};
    }
}

# Get Public Files () - Returns an array of public or admin file paths.
sub get_public_files {
    my $self = shift;
    my $userdb = $self->{dbi};
    my $rows = $userdb->selectcol_arrayref("SELECT * FROM uploads WHERE sharing_policy = 'public' ORDER BY uploadid");
    return @{$rows};
}

# Get Imported Files (User) - Returns an array of files imported by a user.
sub get_imported_files {
	my $self = shift;
    my $userdb = $self->{dbi};
    my $ownerid = $userdb->quote(shift);
    if ($ownerid eq "") {
		warn "No userid specified to get_imported_files";
    } else {
    	my $rows = $userdb->selectcol_arrayref("SELECT path FROM uploads WHERE ownerid = $ownerid AND path LIKE '%\$%' ORDER BY uploadid");
		return @{$rows};
    }
}

# Field (Path, User ID, Field[, Value]) - Returns (or, if defined, sets to the new value) the specified field of a file.
sub field {
    my $self = shift;
    my $path = shift;
    my $userid = shift;
    my $field = shift;
    my $userdb = $self->{dbi};
    
    my $fileid = $self->get_file_id($path, $userid);
    
    if (@_) {
    	my $value = shift;
	    #Clean up the string
    	$value =~ s/^\s+//;
		$value =~ s/\s+$//; 
    	$value = $userdb->quote($value);
    	my $now = $self->nowfun();
	    return $userdb->do("UPDATE uploads SET $field = $value WHERE uploadid = '$fileid'");
	    $self->update_modified($fileid);
    } else {
    	return $userdb->selectrow_array("SELECT $field FROM uploads WHERE uploadid = '$fileid'");
    }
}

# Update Modified (Path, UserID) - Updates the modification date/time of the specified file to right now.
sub update_modified {
    my $self = shift;
    my $path = shift;
    my $userid = shift;
    my $userdb = $self->{dbi};
    
    my $fileid = $self->get_file_id($path, $userid);
    
    my $now = $self->nowfun();
    return $userdb->do("UPDATE uploads SET modification_date = $now WHERE uploadid = '$fileid'");
}

# Created (Track) - Returns creation date of $track.
sub created {
    my $self  = shift;
    my $track = shift;
    my $username = $self->{username};
    return $self->field($track, $username, "creation_date");
}

# Modified (Track) - Returns date modified of $track.
sub modified {
    my $self  = shift;
    my $track = shift;
    my $username = $self->{username};
   	return $self->field($track, $username, "modification_date");
}

# Description (Track[, Description]) - Returns a file's description, or changes the current description if defined.
sub description {
    my $self  = shift;
    my $track = shift;
    my $username = $self->{username};
    my $userdb = $self->{userdb};
    my $userid = $userdb->get_user_id($username);
    
    if (@_) {
		$self->field($track, $userid, "description", shift);
		return 1;
    } else {
		return $self->field($track, $userid, "description");
    }
}

# File Exists (Full Path[, Owner]) - Returns the number of results for a file (and optional owner) in the database, 0 if not found.
sub file_exists {
    my $self = shift;
    my $userdb = $self->{dbi};
    my ($path, $ownerid) = @_;
	
	foreach ($path, $ownerid) {
		$_ = $userdb->quote($_);
	}
    my $usersql = $ownerid? " AND ownerid = $ownerid" : "";
    my $sql = "SELECT * FROM uploads WHERE path LIKE $path" . $usersql;
    return $userdb->do($sql);
}

# Add File (Owner, Full Path, Description, Sharing Policy) - Adds $file to the database under $owner.
sub add_file {
    my $self = shift;
    my $userdb = $self->{dbi};
    my ($ownerid, $path, $description, $shared) = @_;
    warn "Shared: $shared";
    $shared ||= "private";
    warn "Shared 2: $shared";
    
    if ($self->file_exists($path, $ownerid) == 0) {
		my $fileid = md5_hex($ownerid.$path);
		my $now = $self->nowfun();
		foreach ($fileid, $ownerid, $path, $description, $shared) {
			$_ = $userdb->quote($_);
		}
		return $userdb->do("INSERT INTO uploads (uploadid, ownerid, path, description, creation_date, modification_date, sharing_policy) VALUES ($fileid, $ownerid, $path, $description, $now, $now, $shared)");
    } else {
		warn "$ownerid has already uploaded $path.";
    }
}

# Delete File (Path, UserID) - Deletes $file_id from the database.
sub delete_file {
	my $self = shift;
    my $userdb = $self->{dbi};
    my $path = shift;
    my $userid = shift;
    my $filesystem = $self->{filesystem};
    
    $filesystem->delete_file($path);
    my $fileid = $userdb->quote($self->get_file_id($path, $userid));
    if ($fileid) {
    	return $userdb->do("DELETE FROM uploads WHERE uploadid = $fileid");
    }
}

# Now Function - return the database-dependent function for determining current date & time
sub nowfun {
  my $self = shift;
  my $globals = $self->{globals};
  return $globals->user_account_db =~ /sqlite/i ? "datetime('now','localtime')" : 'now()';
}

1;
