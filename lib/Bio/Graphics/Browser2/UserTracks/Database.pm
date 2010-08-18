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

# Get File ID (Full Path[, userid]) - Returns a file's ID from the database.
sub get_file_id{
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $path = $uploadsdb->quote(shift);
    my $uploadsid = shift;
    
    my $if_user = $uploadsid? "userid = " . $uploadsdb->quote($uploadsid) . " AND " : "";
    return $uploadsdb->selectrow_array("SELECT uploadid FROM uploads WHERE " . $if_user . "path = $path");
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
    $uploadsid = $uploadsdb->quote($uploadsid);
	my $rows = $uploadsdb->selectcol_arrayref("SELECT path FROM uploads WHERE userid = $uploadsid AND sharing_policy <> 'public' AND imported <> 1 ORDER BY uploadid");
	return @$rows;
}

# Get Public Files ([User ID, all]) - Returns an array of public or admin file paths, excluding the ones the user requested (unless the "all" flag is set).
sub get_public_files {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $all = shift;
    
    my $sql = "SELECT path FROM uploads WHERE sharing_policy = 'public'";
    if (!$all) {
    	my $uploadsid = shift // $self->{uploadsid};											#/
	    $sql .= " AND (users IS NULL OR users NOT LIKE " . $uploadsdb->quote("%" . $uploadsid . "%") . ")";
	}
    $sql .= " ORDER BY uploadid";
    
    my $rows = $uploadsdb->selectcol_arrayref($sql);
    return @$rows;
}

# Get Imported Files () - Returns an array of files imported by a user.
sub get_imported_files {
	my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $uploadsid = $self->{uploadsid};
    $uploadsid = $uploadsdb->quote($uploadsid);
	my $rows = $uploadsdb->selectcol_arrayref("SELECT path FROM uploads WHERE userid = $uploadsid AND sharing_policy <> 'public' AND imported = 1 ORDER BY uploadid");
	return @$rows;
}

# Get Session Files () - Returns an array of public files added to a user's tracks.
sub get_added_public_files {
	my $self = shift;
	my $uploadsdb = $self->{uploadsdb};
    my $uploadsid = $self->{uploadsid};
    my $rows = $uploadsdb->selectcol_arrayref("SELECT path FROM uploads WHERE sharing_policy = 'public' AND users LIKE " . $uploadsdb->quote('%' . $uploadsid . '%') . " AND userid <> " . $uploadsdb->quote($uploadsid) . " ORDER BY uploadid");
    return @$rows;
}

# Get Shared Files () - Returns an array of files shared specifically to a user.
sub get_shared_files {
	my $self = shift;
	my $uploadsdb = $self->{uploadsdb};
    my $uploadsid = $self->{uploadsid};
    #Since upload IDs are all the same size, we don't have to worry about one ID repeated in another so this next line is OK. Still, might be a good idea to secure this somehow?
    $uploadsid = $uploadsdb->quote('%' . $uploadsid . '%');
    my $rows = $uploadsdb->selectcol_arrayref("SELECT path FROM uploads WHERE sharing_policy = 'group' OR sharing_policy = 'casual' AND users LIKE $uploadsid ORDER BY uploadid");
    return @$rows;
}

# Add Shared File (File[, User ID) - Adds a public or shared track to a user's session
sub add_shared_file {
	my $self = shift;
	my $uploadsid = shift // $self->{uploadsid};												#/
	my $uploadsdb = $self->{uploadsdb};
	my $file = $uploadsdb->quote(shift);
	my $fileid = $self->get_file_id($file);
	my $users = $uploadsdb->selectrow_array("SELECT users FROM uploads WHERE uploadid = '$fileid'");
	#If we find the user's ID, it's already been added, just return that it worked.
	return 1 if ($users =~ $uploadsid);
	$users .= ", " if (($users) && ($users != ""));
	return $uploadsdb->do("UPDATE uploads SET users = '$users" . $uploadsid . "'  WHERE uploadid = '$fileid'");
}

# Remove Shared File (File[, User ID]) - Removes an added public or shared track from a user's session
sub remove_shared_file {
	my $self = shift;
	my $uploadsid = shift // $self->{uploadsid};												#/
	my $uploadsdb = $self->{uploadsdb};
	my $file = $uploadsdb->quote(shift);
	my $fileid = $self->get_file_id($file);
	my $users = $uploadsdb->selectrow_array("SELECT users FROM uploads WHERE uploadid = '$fileid'");
	#If we find the user's ID, it's already been added, just return that it worked.
	return 1 if ($users !~ $uploadsid);
	$users =~ s/$uploadsid(, )?//i;
	$users =~ s/(, $)//i; #Not sure if this is the best way...probably not.
	return $uploadsdb->do("UPDATE uploads SET users = '$users'  WHERE uploadid = '$fileid'");
}

# Field (Field, Path[, Value, User ID]) - Returns (or, if defined, sets to the new value) the specified field of a file.
sub field {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $field = shift;
    my $path = shift;
    my $value = shift;
    my $uploadsid = shift // $self->{uploadsid}; 												#/
    my $fileid = $self->get_file_id($path);
    
    if ($value) {
	    #Clean up the string
    	$value =~ s/^\s+//;
		$value =~ s/\s+$//; 
    	$value = $uploadsdb->quote($value);
    	my $now = $self->nowfun();
	    my $result = $uploadsdb->do("UPDATE uploads SET $field = $value WHERE uploadid = '$fileid'");
	    $self->update_modified($fileid);
	    return $result;
    } else {
    	return $uploadsdb->selectrow_array("SELECT $field FROM uploads WHERE uploadid = '$fileid'");
    }
}

# Update Modified (Path[, UploadsID]) - Updates the modification date/time of the specified file to right now.
sub update_modified {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $path = shift;
    my $uploadsid = shift // $self->{uploadsid};												#/
    
    my $fileid = $self->get_file_id($path);
    my $now = $self->nowfun();
    return $uploadsdb->do("UPDATE uploads SET modification_date = $now WHERE uploadid = '$fileid'");
}

# Created (File) - Returns creation date of $file, cannot be set.
sub created {
    my $self  = shift;
    my $file = shift;
    return $self->field("creation_date", $file);
}

# Modified (File) - Returns date modified of $file, cannot be set (except by update_modified()).
sub modified {
    my $self  = shift;
    my $file = shift;
   	return $self->field("modification_date", $file);
}

# Description (File[, Value]) - Returns a file's description, or changes the current description if defined.
sub description {
    my $self  = shift;
    my $file = shift;
    my $value = shift;
	return $value? $self->field("description", $file, $value) : $self->field("description", $file);
}

# File Exists (Full Path[, UploadsID]) - Returns the number of results for a file (and optional owner) in the database, 0 if not found.
sub file_exists {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $path = $uploadsdb->quote(shift);
    my $uploadsid = $uploadsdb->quote(shift);
	
    my $usersql = $uploadsid? " AND userid = $uploadsid" : "";
    return $uploadsdb->do("SELECT * FROM uploads WHERE path LIKE $path" . $usersql);
}

# Add File (Full Path[, Description, Sharing Policy, Uploads ID]) - Adds $file to the database under $owner.
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
		my $now = $self->nowfun();
		$path = $uploadsdb->quote($path);
		$uploadsid = $uploadsdb->quote($uploadsid);
		$fileid = $uploadsdb->quote($fileid);
		return $uploadsdb->do("INSERT INTO uploads (uploadid, userid, path, description, imported, creation_date, modification_date, sharing_policy) VALUES ($fileid, $uploadsid, $path, $description, $imported, $now, $now, $shared)");
    } else {
		warn $self->{session}->{username} . " has already uploaded $path.";
    }
}

# Delete File (File) - Deletes $file_id from the database.
sub delete_file {
	my $self = shift;
	my $uploadsdb = $self->{uploadsdb};
    my $file = shift;
    my $userid = $self->{userid};
    my $uploadsid = $self->{uploadsid};
    
    # First delete from the database.
    my $fileid = $uploadsdb->quote($self->get_file_id($file, $uploadsid));
    if ($fileid) {
    	return $uploadsdb->do("DELETE FROM uploads WHERE uploadid = $fileid");
    }
    
    # Then remove the file - better to have a dangling file then a dangling reference to nothing.
    my $loader = Bio::Graphics::Browser2::DataLoader->new($file,
							  $self->track_path($file),
							  $self->track_conf($file),
							  $self->{config},
							  $userid);
    $loader->drop_databases($self->track_conf($file));
    rmtree($self->track_path($file));
}

# Is Imported (File) - Returns 1 if an already-added track is imported, 0 if not.
sub is_imported {
	my $self = shift;
	my $file = shift;
	my $uploadsdb = $self->{uploadsdb};
	my $fileid = $self->get_file_id($file);
	return $uploadsdb->selectrow_array("SELECT imported FROM uploads WHERE uploadid = '$fileid'") || 0;
}

# Permissions (File[, New Permissions]) - Return or change the permissions.
sub permissions {
	my $self = shift;
	my $file = shift;
	my $new_permissions = shift;
	if ($new_permissions) {
		return $self->field("sharing_policy", $file, $new_permissions);
	} else {
		return $self->field("sharing_policy", $file);
	}
}

# Is Mine (File[, Uploads ID]) - Returns 1 if a track is owned by the logged-in (or specified) user), 0 if not.
sub is_mine {
	my $self = shift;
	my $uploadsdb = $self->{uploadsdb};
	my $file = $uploadsdb->quote(shift);
	my $uploadsid = $uploadsdb->quote(shift // $self->{uploadsid});								#/
	my $results = $uploadsdb->selectcol_arrayref("SELECT uploadid FROM uploads WHERE path = $file AND userid = $uploadsid");
	return (@$results > 0);
}

# Shared With (File) - Returns an array of users a track is shared with.
sub shared_with {
	my $self = shift;
	my $file = shift;
	my $uploadsdb = $self->{uploadsdb};
	my $fileid = $self->get_file_id($file);
	my $users_string = $uploadsdb->selectrow_array("SELECT users FROM uploads WHERE uploadid = '$fileid'");
	return split(", ", $users_string);
}

# Track Type (File[, User]) - Returns the type of a specified track, in relation to the (optionally specified) user.
sub file_type {
	my $self = shift;
	my $file = shift;
	my $uploadsid = shift // $self->{uploadsid};												#/
	
	if ($self->is_mine($file)) {
		return $self->is_imported($file)? "imported" : "uploaded";
	} else {
		return ($self->permissions($file) =~ /public/)? "public" : "shared";
	}
}

1;
