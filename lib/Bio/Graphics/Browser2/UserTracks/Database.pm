package Bio::Graphics::Browser2::UserTracks::Database;

# $Id: Database.pm 23607 2010-07-30 17:34:25Z cnvandev $
use strict;
use base 'Bio::Graphics::Browser2::UserTracks';
use Bio::Graphics::Browser2;
use Bio::Graphics::Browser2::UserDB;
use DBI;
use Digest::MD5 qw(md5_hex);
use CGI "param";
use Carp "cluck";

sub _new {
	my $class = shift;
	my $VERSION = '0.2';
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
		uploadsid => $state->{uploadid},
		globals	  => $globals,
		userdb	  => Bio::Graphics::Browser2::UserDB->new()
    }, ref $class || $class;
}

# Get File ID (Full Path) - Returns a file's ID from the database.
sub get_file {
    my $self = shift;
    my $potential_fileid = shift;
  	my $uploadsid = $self->{uploadsid};
    my $uploadsdb = $self->{uploadsdb};
	my $attempted_fileid = $uploadsdb->selectrow_array("SELECT uploadid FROM uploads WHERE userid = " . $uploadsdb->quote($uploadsid) . " AND path = " . $uploadsdb->quote($potential_fileid));
	my $file = ($attempted_fileid? $attempted_fileid : $potential_fileid);
	my $confirmed_files = $uploadsdb->selectcol_arrayref("SELECT uploadid FROM uploads");
    return $file if join(" ", @$confirmed_files) =~ $file;
}

# Now Function - return the database-dependent function for determining current date & time
sub nowfun {
	my $self = shift;
	my $globals = $self->{globals};
	return $globals->user_account_db =~ /sqlite/i ? "datetime('now','localtime')" : 'now()';
}

# Get Uploaded Files () - Returns an array of the paths of files owned by the currently logged-in user.
sub get_uploaded_files {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $uploadsid = $self->{uploadsid};
	my $rows = $uploadsdb->selectcol_arrayref("SELECT path FROM uploads WHERE userid = " . $uploadsdb->quote($uploadsid) . " AND sharing_policy <> 'public' AND imported <> 1 ORDER BY uploadid");
	return @$rows;
}

# Get Public Files ([User ID]) - Returns an array of available public files that the user hasn't added.
sub get_public_files {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $uploadsid = $self->{uploadsid};
    my $userid = shift // $self->{userid};												#/
    my $rows = $uploadsdb->selectcol_arrayref("SELECT path FROM uploads WHERE sharing_policy = 'public' AND (users IS NULL OR users NOT LIKE " . $uploadsdb->quote("%" . $userid . "%") . ") ORDER BY uploadid");
    return @$rows;
}

# Get Imported Files () - Returns an array of files imported by a user.
sub get_imported_files {
	my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $uploadsid = $self->{uploadsid};
	my $rows = $uploadsdb->selectcol_arrayref("SELECT path FROM uploads WHERE userid = " . $uploadsdb->quote($uploadsid) . " AND sharing_policy <> 'public' AND imported = 1 ORDER BY uploadid");
	return @$rows;
}

# Get Session Files () - Returns an array of public files added to a user's tracks.
sub get_added_public_files {
	my $self = shift;
	my $uploadsdb = $self->{uploadsdb};
    my $userid = $self->{userid};
    my $rows = $uploadsdb->selectcol_arrayref("SELECT path FROM uploads WHERE sharing_policy = 'public' AND users LIKE " . $uploadsdb->quote('%' . $userid . '%') . " ORDER BY uploadid");
    return @$rows;
}

# Get Shared Files () - Returns an array of files shared specifically to a user.
sub get_shared_files {
	my $self = shift;
	my $uploadsdb = $self->{uploadsdb};
    my $userid = $self->{userid};
    my $uploadsid = $self->{uploadsid};
    #Since upload IDs are all the same size, we don't have to worry about one ID repeated inside another so this next line is OK. Still, might be a good idea to secure this somehow?
    my $rows = $uploadsdb->selectcol_arrayref("SELECT path FROM uploads WHERE (sharing_policy = 'group' OR sharing_policy = 'casual') AND users LIKE " . $uploadsdb->quote('%' . $userid . '%') . " AND userid <> " . $uploadsdb->quote($uploadsid) . " ORDER BY uploadid");
    return @$rows;
}

# Share (File[, Username OR User ID]) - Adds a public or shared track to a user's session
sub share {
	my $self = shift;
	my $file = $self->get_file(shift);
	my $sharing_policy = $self->field("sharing_policy", $file);

	# If we've been passed a user ID, use that. If we've been passed a username, get the ID. If we haven't been passed anything, use the session user ID.
	my $userdb = $self->{userdb};
	my $potential_userid = shift;
	my $attempted_userid = $userdb->get_user_id($potential_userid) or return;
	my $userid = $attempted_userid || $potential_userid || $self->{userid};
	
	if ((($sharing_policy =~ /(casual|public)/) && ($userid eq $self->{userid})) || ($self->is_mine($file) && ($sharing_policy =~ /group/))) {
		# Get the current users.
		my $uploadsdb = $self->{uploadsdb};
		my $users = $uploadsdb->selectrow_array("SELECT users FROM uploads WHERE uploadid = " . $uploadsdb->quote($file));
	
		#If we find the user's ID, it's already been added, just return that it worked.
		return 1 if ($users =~ $userid);
		$users .= ", " if $users;
		return $uploadsdb->do("UPDATE uploads SET users = " . $uploadsdb->quote($users . $userid) . "  WHERE uploadid = " . $uploadsdb->quote($file));
	} else {
		warn "Share() attempted in an illegal situation on $file by " . $userid;
	}
}

# Unshare (File[, Username OR User ID]) - Removes an added public or shared track from a user's session
sub unshare {
	my $self = shift;
	my $file = $self->get_file(shift);
	my $sharing_policy = $self->field("sharing_policy", $file);
	
	# If we've been passed a user ID, use that. If we've been passed a username, get the ID. If we haven't been passed anything, use the session user ID.
	my $userdb = $self->{userdb};
	my $potential_userid = shift;
	my $attempted_userid = $userdb->get_user_id($potential_userid);
	my $userid = ($attempted_userid? $attempted_userid : $potential_userid) // $self->{userid};	#/
	
	if ((($sharing_policy =~ /(casual|public)/) && ($userid eq $self->{userid})) || ($self->is_mine($file) && ($sharing_policy =~ /group/))) {
		# Get the current users.
		my $uploadsdb = $self->{uploadsdb};
		my $users = $uploadsdb->selectrow_array("SELECT users FROM uploads WHERE uploadid = " . $uploadsdb->quote($file));
	
		#If we find the user's ID, it's already been removed, just return that it worked.
		return 1 if ($users !~ $userid);
		$users =~ s/$userid(, )?//i;
		$users =~ s/(, $)//i; #Not sure if this is the best way to remove a trailing ", "...probably not.
	
		return $uploadsdb->do("UPDATE uploads SET users = " . $uploadsdb->quote($users) . " WHERE uploadid = " . $uploadsdb->quote($file));
	} else {
		warn "Unshare() attempted in an illegal situation on $file by " . $userid;
	}
}

# Field (Field, Path[, Value, User ID]) - Returns (or, if defined, sets to the new value) the specified field of a file.
sub field {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $field = shift;
    my $file = $self->get_file(shift);
    my $value = shift;
    my $uploadsid = shift // $self->{uploadsid}; 												#/
    
    if ($value) {
    	if ($self->is_mine($file)) {
			#Clean up the string
			$value =~ s/^\s+//;
			$value =~ s/\s+$//; 
			my $now = $self->nowfun();
			my $result = $uploadsdb->do("UPDATE uploads SET $field = " . $uploadsdb->quote($value) . " WHERE uploadid = " . $uploadsdb->quote($file));
			$self->update_modified($file);
			return $result;
		} else {
	    	warn "Field() was called to modify $field on " . $file . " by " . $self->{username} . ", a non-owner.";
	    }
    } else {
    	return $uploadsdb->selectrow_array("SELECT $field FROM uploads WHERE uploadid = '$file'");
    }
}

# Update Modified (Path[, UploadsID]) - Updates the modification date/time of the specified file to right now.
sub update_modified {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $file = $self->get_file(shift);
    my $now = $self->nowfun();
    return $uploadsdb->do("UPDATE uploads SET modification_date = $now WHERE uploadid = " . $uploadsdb->quote($file));
}

# Created (File) - Returns creation date of $file, cannot be set.
sub created {
    my $self  = shift;
    my $file = $self->get_file(shift);
    return $self->field("creation_date", $file);
}

# Modified (File) - Returns date modified of $file, cannot be set (except by update_modified()).
sub modified {
    my $self  = shift;
    my $file = $self->get_file(shift);
   	return $self->field("modification_date", $file);
}

# Description (File[, Value]) - Returns a file's description, or changes the current description if defined.
sub description {
    my $self  = shift;
    my $file = $self->get_file(shift);
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

# File Exists (Full Path[, UploadsID]) - Returns the number of results for a file (and optional owner) in the database, 0 if not found.
sub file_exists {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $path = shift;
    my $uploadsid = shift;
	
    my $usersql = $uploadsid? " AND userid = " . $uploadsdb->quote($uploadsid) : "";
    return $uploadsdb->do("SELECT * FROM uploads WHERE path LIKE " . $uploadsdb->quote("%" . $path . "%") . $usersql);
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
		my $file = md5_hex($uploadsid.$path);
		my $now = $self->nowfun();
		$path = $uploadsdb->quote($path);
		$uploadsid = $uploadsdb->quote($uploadsid);
		$file = $uploadsdb->quote($file);
		return $uploadsdb->do("INSERT INTO uploads (uploadid, userid, path, description, imported, creation_date, modification_date, sharing_policy) VALUES ($file, $uploadsid, $path, $description, $imported, $now, $now, $shared)");
    } else {
		warn $self->{session}->{username} . " has already uploaded $path.";
    }
}

# Delete File (File) - Deletes $file_id from the database.
sub delete_file {
	my $self = shift;
    my $file = shift;
    my $file = $self->get_file($file);
    my $userid = $self->{userid};
    my $uploadsid = $self->{uploadsid};
    
    if ($self->is_mine($file)) {
		# First delete from the database.
		my $uploadsdb = $self->{uploadsdb};
		return $uploadsdb->do("DELETE FROM uploads WHERE uploadid = " . $uploadsdb->quote($file));
		
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
	my $file = $self->get_file(shift);
	my $uploadsdb = $self->{uploadsdb};
	return $uploadsdb->selectrow_array("SELECT imported FROM uploads WHERE uploadid = " . $uploadsdb->quote($file)) || 0;
}

# Permissions (File[, New Permissions]) - Return or change the permissions.
sub permissions {
	my $self = shift;
	my $file = $self->get_file(shift);
	my $new_permissions = shift;
	if ($new_permissions) {
		if ($self->is_mine($file)) {
			$self->field("users", $file, $self->{userid}) if $new_permissions =~ /public/;
			return $self->field("sharing_policy", $file, $new_permissions);
		} else {
			warn "Permissions change on " . $file . "requested by " . $self->{username} . " a non-owner.";
		}
	} else {
		return $self->field("sharing_policy", $file);
	}
}

# Is Mine (File) - Returns 1 if a track is owned by the logged-in (or specified) user, 0 if not.
sub is_mine {
	my $self = shift;
	my $file = $self->get_file(shift);
	my $owner = $self->owner($file);
	return ($owner eq $self->{uploadsid})? 1 : 0;
}

# Owner (File) - Returns the owner of the specified file.
sub owner {
	my $self = shift;
	my $uploadsdb = $self->{uploadsdb};
	my $file = $self->get_file(shift);
	return $uploadsdb->selectrow_array("SELECT userid FROM uploads WHERE uploadid = " . $uploadsdb->quote($file));
}

# Is Shared With Me (File[, Uploads ID]) - Returns 1 if a track is shared with the logged-in (or specified) user, 0 if not.
sub is_shared_with_me {
	my $self = shift;
	my $uploadsdb = $self->{uploadsdb};
	my $file = $self->get_file(shift);
	my $uploadsid = $uploadsdb->quote("%" . (shift // $self->{userid}) . "%");					#/
	my $results = $uploadsdb->selectcol_arrayref("SELECT uploadid FROM uploads WHERE path = " . $uploadsdb->quote($file) . " AND users LIKE $uploadsid");
	return (@$results > 0)? 1 : 0;
}

# Shared With (File) - Returns an array of users a track is shared with.
sub shared_with {
	my $self = shift;
	my $file = $self->get_file(shift);
	my $uploadsdb = $self->{uploadsdb};
	my $users_string = $uploadsdb->selectrow_array("SELECT users FROM uploads WHERE uploadid = " . $uploadsdb->quote($file));
	return split(", ", $users_string);
}

# Track Type (File) - Returns the type of a specified track, in relation to the user.
sub file_type {
	my $self = shift;
	my $file = $self->get_file(shift);
	return "public" if ($self->permissions($file) =~ /public/);
	if ($self->is_mine($file)) {
		return $self->is_imported($file)? "imported" : "uploaded";
	} else { return "shared" };
}

1;
