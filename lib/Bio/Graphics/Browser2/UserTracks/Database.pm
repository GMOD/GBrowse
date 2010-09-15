package Bio::Graphics::Browser2::UserTracks::Database;

# $Id: Database.pm 23607 2010-07-30 17:34:25Z cnvandev $
use strict;
use base 'Bio::Graphics::Browser2::UserTracks';
use Bio::Graphics::Browser2;
use Bio::Graphics::Browser2::UserDB;
use DBI;
use Digest::MD5 qw(md5_hex);
use CGI qw(param url);
use Carp qw(confess cluck);

sub _new {
	my $class = shift;
	my $VERSION = '0.3';
	my ($config, $state, $lang) = @_;
	my $globals = $config->globals;
	my $session = $globals->session;

    my $credentials = $globals->user_account_db;
    my $login = DBI->connect($credentials);
	unless ($login) {
		print header();
		print "Error: Could not open login database.";
		die "Could not open login database $credentials";
	}
	
    return bless {
    	uploadsdb => $login,
		config	  => $config,
		state     => $state,
		language  => $lang,
		session	  => $session,
		userid	  => $state->{userid},
		uploadsid => $state->{uploadid}, #Renamed to avoid confusion with the ID of an upload.
		globals	  => $globals,
		userdb	  => Bio::Graphics::Browser2::UserDB->new()
    }, ref $class || $class;
}

# Get File ID (Filename[, Owner ID]) - Returns a file's validated ID from the local store if found, or the database if not.
sub get_file_id {
	my $self = shift;
	my $filename = shift;
	my $uploadsdb = $self->{uploadsdb};
	my $uploadsid = shift // $self->{uploadsid};										#/
	
	# First, check my files.
	my $uploads = $uploadsdb->selectrow_array("SELECT uploadid FROM uploads WHERE path = " . $uploadsdb->quote($filename) . " AND userid = " . $uploadsdb->quote($uploadsid));
	return $uploads if $uploads;
	
	# Then, check files shared with me.
	my $userid = $self->{userid};
	my $shared = $uploadsdb->selectrow_array("SELECT uploadid FROM uploads WHERE path = " . $uploadsdb->quote($filename) . " AND users LIKE " . $uploadsdb->quote("%" . $userid . "%"));
	return $shared if $shared;
	
	# Lastly, check public files.
	my $public = $uploadsdb->selectrow_array("SELECT uploadid FROM uploads WHERE path = " . $uploadsdb->quote($filename) . " AND sharing_policy = 'public'");
	return $public if $public;	
}

# Now Function - return the database-dependent function for determining current date & time
sub nowfun {
	my $self = shift;
	my $globals = $self->{globals};
	return $globals->user_account_db =~ /sqlite/i ? "datetime('now','localtime')" : 'now()';
}

# Get Uploaded Files () - Returns an array of the paths of files owned by the currently logged-in user. Can be publicly accessed.
sub get_uploaded_files {
    my $self = shift;
    my $uploadsid = $self->{uploadsid};# or confess "Need uploads ID for get_uploaded_files";
    my $uploadsdb = $self->{uploadsdb};
	my $rows = $uploadsdb->selectcol_arrayref("SELECT path FROM uploads WHERE userid = " . $uploadsdb->quote($uploadsid) . " AND sharing_policy <> 'public' AND imported <> 1 ORDER BY uploadid");
	return @$rows;
}

# Get Public Files ([User ID]) - Returns an array of available public files that the user hasn't added. Can be publicly accessed.
sub get_public_files {
    my $self = shift;
    my $uploadsid = $self->{uploadsid};# or confess "Need uploads ID for get_public_files";
    my $uploadsdb = $self->{uploadsdb};
    my $userid = shift // $self->{userid};												#/
    my $rows = $uploadsdb->selectcol_arrayref("SELECT path FROM uploads WHERE sharing_policy = 'public' AND (users IS NULL OR users NOT LIKE " . $uploadsdb->quote("%" . $userid . "%") . ") ORDER BY uploadid");
    return @$rows;
}

# Get Imported Files () - Returns an array of files imported by a user. Can be publicly accessed.
sub get_imported_files {
	my $self = shift;
    my $uploadsid = $self->{uploadsid};# or confess "Need uploads ID for get_imported_files";
    my $uploadsdb = $self->{uploadsdb};
	my $rows = $uploadsdb->selectcol_arrayref("SELECT path FROM uploads WHERE userid = " . $uploadsdb->quote($uploadsid) . " AND sharing_policy <> 'public' AND imported = 1 ORDER BY uploadid");
	return @$rows;
}

# Get Added Public Files () - Returns an array of public files added to a user's tracks. Can be publicly accessed.
sub get_added_public_files {
	my $self = shift;
	my $userid = $self->{userid};# or confess "Need user ID for get_added_public_files";
	my $uploadsdb = $self->{uploadsdb};
    my $rows = $uploadsdb->selectcol_arrayref("SELECT path FROM uploads WHERE sharing_policy = 'public' AND users LIKE " . $uploadsdb->quote('%' . $userid . '%') . " ORDER BY uploadid");
    return @$rows;
}

# Get Shared Files () - Returns an array of files shared specifically to a user. Can be publicly accessed.
sub get_shared_files {
	my $self = shift;
    my $userid = $self->{userid};
    my $uploadsid = $self->{uploadsid};
    my $uploadsdb = $self->{uploadsdb};
    #Since upload IDs are all the same size, we don't have to worry about one ID repeated inside another so this next line is OK. Still, might be a good idea to secure this somehow?
    my $rows = $uploadsdb->selectcol_arrayref("SELECT path FROM uploads WHERE (sharing_policy = 'group' OR sharing_policy = 'casual') AND users LIKE " . $uploadsdb->quote('%' . $userid . '%') . " AND userid <> " . $uploadsdb->quote($uploadsid) . " ORDER BY uploadid");
    return @$rows;
}

# Share (File[, Username OR User ID]) - Adds a public or shared track to a user's session. Can be publicly accessed.
sub share {
	my $self = shift;
	my $fileid = shift or confess "No input or invalid input given to share()";

	# If we've been passed a user ID, use that. If we've been passed a username, get the ID. If we haven't been passed anything, use the session user ID.
	my $userdb = $self->{userdb};
	my $potential_userid = shift;
	my $attempted_userid = $userdb->get_user_id($potential_userid) or return;
	my $userid = $attempted_userid || $potential_userid || $self->{userid};
	
	my $sharing_policy = $self->permissions($fileid);
	if ((($sharing_policy =~ /(casual|public)/) && ($userid eq $self->{userid})) || ($self->is_mine($fileid) && ($sharing_policy =~ /group/))) {
		# Get the current users.
		my $uploadsdb = $self->{uploadsdb};
		my $users = $uploadsdb->selectrow_array("SELECT users FROM uploads WHERE uploadid = " . $uploadsdb->quote($fileid));
	
		#If we find the user's ID, it's already been added, just return that it worked.
		return 1 if ($users =~ $userid);
		$users .= ", " if $users;
		return $uploadsdb->do("UPDATE uploads SET users = " . $uploadsdb->quote($users . $userid) . "  WHERE uploadid = " . $uploadsdb->quote($fileid));
	} else {
		warn "Share() attempted in an illegal situation on $fileid by " . $userdb->get_username($userid) . ", a non-owner.";
	}
}

# Unshare (File[, Username OR User ID]) - Removes an added public or shared track from a user's session. Can be publicly accessed.
sub unshare {
	my $self = shift;
	my $fileid = shift or confess "No input or invalid input given to unshare()";
	
	# If we've been passed a user ID, use that. If we've been passed a username, get the ID. If we haven't been passed anything, use the session user ID.
	my $userdb = $self->{userdb};
	my $potential_userid = shift;
	my $attempted_userid = $userdb->get_user_id($potential_userid);
	my $userid = ($attempted_userid? $attempted_userid : $potential_userid) // $self->{userid};	#/
	
	my $sharing_policy = $self->permissions($fileid);
	if ((($sharing_policy =~ /(casual|public)/) && ($userid eq $self->{userid})) || ($self->is_mine($fileid) && ($sharing_policy =~ /(group|public)/))) {
		# Get the current users.
		my $uploadsdb = $self->{uploadsdb};
		my $users = $uploadsdb->selectrow_array("SELECT users FROM uploads WHERE uploadid = " . $uploadsdb->quote($fileid));
	
		#If we find the user's ID, it's already been removed, just return that it worked.
		return 1 if ($users !~ $userid);
		$users =~ s/$userid(, )?//i;
		$users =~ s/(, $)//i; #Not sure if this is the best way to remove a trailing ", "...probably not.
	
		return $uploadsdb->do("UPDATE uploads SET users = " . $uploadsdb->quote($users) . " WHERE uploadid = " . $uploadsdb->quote($fileid));
	} else {
		warn "Unshare() attempted in an illegal situation on $fileid by " . $userdb->get_username($userid) . ", a non-owner.";
	}
}

# Field (Field, Path[, Value, User ID]) - Returns (or, if defined, sets to the new value) the specified field of a file.
sub field {
    my $self = shift;
    my $field = shift;
    my $fileid = shift or confess "No input or invalid input given to field()";
    my $value = shift;
    my $uploadsid = shift // $self->{uploadsid}; 												#/
    my $uploadsdb = $self->{uploadsdb};
    
    if ($value) {
    	if ($self->is_mine($fileid)) {
			#Clean up the string
			$value =~ s/^\s+//;
			$value =~ s/\s+$//; 
			my $now = $self->nowfun();
			my $result = $uploadsdb->do("UPDATE uploads SET $field = " . $uploadsdb->quote($value) . " WHERE uploadid = " . $uploadsdb->quote($fileid));
			$self->update_modified($fileid);
			return $result;
		} else {
			my $userdb = $self->{userdb};
	    	warn "Field() was called to modify $field on " . $fileid . " by " . $uploadsid . ", a non-owner.";
	    }
    } else {
    	return $uploadsdb->selectrow_array("SELECT $field FROM uploads WHERE uploadid = " . $uploadsdb->quote($fileid));
    }
}

# Update Modified (Path[, UploadsID]) - Updates the modification date/time of the specified file to right now.
sub update_modified {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $fileid = shift or confess "No input or invalid input given to update_modified()";
    my $now = $self->nowfun();
    return $uploadsdb->do("UPDATE uploads SET modification_date = $now WHERE uploadid = " . $uploadsdb->quote($fileid));
}

# Created (File) - Returns creation date of $fileid, cannot be set.
sub created {
    my $self  = shift;
    my $file = shift or confess "No input or invalid input given to created()";
    return $self->field("creation_date", $file);
}

# Modified (File) - Returns date modified of $file, cannot be set (except by update_modified()).
sub modified {
    my $self  = shift;
    my $file = shift or confess "No input or invalid input given to modified()";
   	return $self->field("modification_date", $file);
}

# Description (File[, Value]) - Returns a file's description, or changes the current description if defined.
sub description {
    my $self  = shift;
    my $file = shift or confess "No input or invalid input given to description()";
    my $value = shift;
    if ($value) {
    	if ($self->is_mine($file)) {
	    	return $self->field("description", $file, $value)
	    } else {
	    	warn "Change Description requested on $file by " . $self->{username} . ", a non-owner.";
	    }
    } else {
    	return $self->field("description", $file)
    }
}

# Add File (Full Path[, Description, Sharing Policy, Uploads ID]) - Adds $file to the database under the current (or specified) owner.
sub add_file {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $path = shift;
    my $imported = shift // 0;																	#/
    my $description = $uploadsdb->quote(shift);
    my $uploadsid = shift // $self->{uploadsid};												#/
    my $shared = $uploadsdb->quote(shift // "private");											#/
    
    if ($self->file_exists($path) == 0) {
		my $fileid = md5_hex($uploadsid.$path);
		my $publicid = md5_hex($fileid.$uploadsid);
		my $now = $self->nowfun();
		$path = $uploadsdb->quote($path);
		$uploadsid = $uploadsdb->quote($uploadsid);
		$fileid = $uploadsdb->quote($fileid);
		return $uploadsdb->do("INSERT INTO uploads (uploadid, publicid, userid, path, description, imported, creation_date, modification_date, sharing_policy) VALUES ($fileid, $publicid, $uploadsid, $path, $description, $imported, $now, $now, $shared)");
    } else {
		warn $self->{session}->{username} . " has already uploaded $path.";
    }
}

# Delete File (File) - Deletes $file_id from the database.
sub delete_file {
	my $self = shift;
    my $file = shift;
    my $fileid = $self->get_file_id($file) or confess "No input or invalid input given to delete()";
    my $userid = $self->{userid};
    my $uploadsid = $self->{uploadsid};
    
    if ($self->is_mine($fileid)) {
		# First delete from the database.
		my $uploadsdb = $self->{uploadsdb};
		return $uploadsdb->do("DELETE FROM uploads WHERE uploadid = " . $uploadsdb->quote($fileid));
		
		# Then remove the file - better to have a dangling file then a dangling reference to nothing.
		my $loader = Bio::Graphics::Browser2::DataLoader->new($file,
								  $self->track_path($file),
								  $self->track_conf($file),
								  $self->{config},
								  $userid);
		$loader->drop_databases($self->track_conf($file));
		rmtree($self->track_path($file));
    } else {
		warn "Delete change on " . $file . "requested by " . $self->{username} . " a non-owner.";
	}
}

# Is Imported (File) - Returns 1 if an already-added track is imported, 0 if not.
sub is_imported {
	my $self = shift;
	my $fileid = shift or confess "No input or invalid input given to is_imported()";
	my $uploadsdb = $self->{uploadsdb};
	return $uploadsdb->selectrow_array("SELECT imported FROM uploads WHERE uploadid = " . $uploadsdb->quote($fileid)) || 0;
}

# Permissions (File[, New Permissions]) - Return or change the permissions. Can be publicly accessed.
sub permissions {
	my $self = shift;
	my $fileid = shift or confess "No input or invalid input given to permissions()";
	my $new_permissions = shift;
	if ($new_permissions) {
		if ($self->is_mine($fileid)) {
			$self->field("users", $fileid, $self->{userid}) if $new_permissions =~ /public/;
			return $self->field("sharing_policy", $fileid, $new_permissions);
		} else {
			warn "Permissions change on " . $fileid . "requested by " . $self->{username} . " a non-owner.";
		}
	} else {
		return $self->field("sharing_policy", $fileid);
	}
}

# Is Mine (Filename) - Returns 1 if a track is owned by the logged-in (or specified) user, 0 if not. Can be publicly accessed.
sub is_mine {
	my $self = shift;
	my $fileid = shift or confess "No input or invalid input given to is_mine()";
	my $owner = $self->owner($fileid);
	return ($owner eq $self->{uploadsid})? 1 : 0;
}

# Owner (Filename) - Returns the owner of the specified file. Can be publicly accessed.
sub owner {
	my $self = shift;
	my $fileid = shift or confess "No input or invalid input given to owner()";
	my $uploadsdb = $self->{uploadsdb};
	return $uploadsdb->selectrow_array("SELECT userid FROM uploads WHERE uploadid = " . $uploadsdb->quote($fileid));
}

# Is Shared With Me (Filename) - Returns 1 if a track is shared with the logged-in (or specified) user, 0 if not. Can be publicly accessed.
sub is_shared_with_me {
	my $self = shift;
	my $uploadsdb = $self->{uploadsdb};
	my $fileid = shift or confess "No input given to is_shared_with_me()";
	my $uploadsid = $uploadsdb->quote("%" . (shift // $self->{userid}) . "%");					#/
	my $results = $uploadsdb->selectcol_arrayref("SELECT uploadid FROM uploads WHERE path = " . $uploadsdb->quote($fileid) . " AND users LIKE $uploadsid");
	return (@$results > 0)? 1 : 0;
}

# Get Public ID (Filename, Owner) - Returns the public ID of a file.
sub get_public_id {
	my $self = shift;
	my $file = shift;
	my $uploadsid = shift // $self->{uploadsid};												#/
	my $fileid = $self->get_file_id($file, $uploadsid);
	return $self->field("publicid", $fileid);
}

# Public File Lookup (Public File ID)
sub public_file_lookup {
	my $self = shift;
	my $public_id = shift;
	my $uploadsdb = $self->{uploadsdb};
	return $uploadsdb->selectrow_array("SELECT uploadid FROM uploads WHERE publicid = " . $uploadsdb->quote($public_id));
}

#################### PUBLIC FUNCTIONS ####################
# These functions are meant to be publicly accessible. No others are, and will screw up if you call them externally to this module. Maybe some of them should be added as conditionals to the existing getter/setter functions?

# Public Sharing Link (Public File ID) - Generates the sharing link for a specific file. Can be publicly accessed.
sub public_sharing_link {
	my $self = shift;
	my $file = $self->public_file_lookup(shift) or confess "Invalid file to public_sharing_link()";
	return url(-full => 1, -path_info => 1) . "?share_link=" . $file;
}

# Public File Type (Public File ID) - Returns the type of a specified track, in relation to the user. Can be publicly accessed.
sub public_file_type {
	my $self = shift;
	my $fileid = $self->public_file_lookup(shift) or confess "Invalid file to public_file_type()";
	return "public" if ($self->permissions($fileid) =~ /public/);
	if ($self->is_mine($fileid)) {
		return $self->is_imported($fileid)? "imported" : "uploaded";
	} else { return "shared" };
}

# Public Is Mine (Public File ID) - Returns true if an upload belongs to the logged-in user, false if not.
sub public_is_mine {
	my $self = shift;
	my $fileid = $self->public_file_lookup(shift) or confess "Invalid file to public_is_mine()";
	return $self->is_mine($fileid);
}

# Public Shared With (Public File ID) - Returns an array of users a track is shared with. Can be publicly accessed.
sub public_shared_with {
	my $self = shift;
	my $fileid = $self->public_file_lookup(shift) or confess "Invalid file to public_shared_with()";
	my $users_string = $self->field("users", $fileid);
	return split(", ", $users_string);
}

# Public Description (Public File ID) - Returns the plaintext description of an upload.
sub public_description {
	my $self = shift;
	my $fileid = $self->public_file_lookup(shift) or confess "Invalid file to public_description()";
	return $self->description($fileid);
}

# Public Sharing Policy (Public File ID) - Returns the sharing policy of an upload as a string of (private|casual|group|public).
sub public_sharing_policy {
	my $self = shift;
	my $fileid = $self->public_file_lookup(shift) or confess "Invalid file to public_sharing_policy()";
	return $self->permissions($fileid);
}

# Public Modification Date (Public File ID) - Returns the date and time of the last modification of an object.
sub public_modification_date {
	my $self = shift;
	my $fileid = $self->public_file_lookup(shift) or confess "Invalid file to public_modification_date()";
	return $self->modified($fileid);
}

# Public Creation Date (Public File ID) - Returns the date and time of the original upload.
sub public_creation_date {
	my $self = shift;
	my $fileid = $self->public_file_lookup(shift) or confess "Invalid file to public_filename()";
	return $self->created($fileid);
}

# Public File Name (Public File ID) - Returns the filename or URL as stored in the database.
sub public_filename {
	my $self = shift;
	my $fileid = $self->public_file_lookup(shift) or confess "Invalid file to public_shared_with()";
	return $self->field("path", $fileid);
}

1;
