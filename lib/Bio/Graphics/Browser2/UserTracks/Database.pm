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
	my $VERSION = '0.4';
	
	# Database/Filesystem can be called with the data source and state, or just the render object.
	my ($data_source, $globals, $userid, $uploadsid);
	if (@_ == 1) {
		my $render = shift;
		$data_source = $render->data_source;
		$globals = $data_source->globals;
		$userid = $render->session->id;
		$uploadsid = $render->session->page_settings->{uploadid}; #Renamed to avoid confusion with the ID of an upload.
	} else {
		$data_source = shift;
		my $state = shift;
		$globals = $data_source->globals;
		$userid = $state->{userid};
		$uploadsid = $state->{uploadid}; #Renamed to avoid confusion with the ID of an upload.
	}
	
	# Attempt to login to the database or die, and access the necessary tables or create them.
    my $credentials = $globals->uploads_db or die "No credentials given to uploads DB in GBrowse.conf";
    my $uploadsdb = DBI->connect($credentials);
	unless ($uploadsdb) {
		print header();
		print "Error: Could not open uploads database.";
		die "Could not open uploads database with $credentials";
	}
	unless ($uploadsdb->do("SELECT * FROM uploads")) {
		my $creation_sql = "CREATE TABLE uploads (";
		$creation_sql   .= "uploadid	       	varchar(32) not null PRIMARY key,";
		$creation_sql   .= "userid				varchar(32) not null,";
		$creation_sql   .= "path					   text,";
		$creation_sql   .= "description				   text,";
		$creation_sql   .= "imported                boolean not null,";
		$creation_sql   .= "creation_date          datetime not null,";
		$creation_sql   .= "modification_date      datetime,";
		$creation_sql   .= "sharing_policy     " . (($credentials =~ /sqlite/i)? "ENUM('private', 'public', 'group', 'casual')" : "varchar(12)") . "not null,";
		$creation_sql   .= "users                      text";
		$creation_sql   .= ")" . (($credentials =~ /mysql/i)? " ENGINE=InnoDB;" : ";");
		$uploadsdb->do($creation_sql) or die "Could not create uploads database";
	}
	
	my $self = bless {
    	config	  => $data_source,
    	uploadsdb => $uploadsdb,
		userid	  => $userid,
		uploadsid => $uploadsid,
		globals	  => $globals,
    }, ref $class || $class;
    
    if ($globals->user_accounts) {
	    $self->{userdb} = Bio::Graphics::Browser2::UserDB->new;
    	$self->{username} = $self->{userdb}->get_username($self->{userid});
    }
    return $self;
}

# Get File ID (File ID [, Owner ID]) - Returns a file's validated ID from the database.
sub get_file_id {
	my $self = shift;
	my $filename = shift;
	my $uploadsdb = $self->{uploadsdb};
	my $uploadsid = shift || $self->{uploadsid};
	
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

# Filename (File ID) - Returns the filename of any given ID.
sub filename {
	my $self = shift;
	my $file = shift or confess "No file ID given to filename().";
	return $self->field("path", $file);
}

# Now Function - return the database-dependent function for determining current date & time
sub nowfun {
	my $self = shift;
	my $globals = $self->{globals};
	return $globals->upload_db_adaptor =~ /sqlite/i ? "datetime('now','localtime')" : 'now()';
}

# Get Uploaded Files () - Returns an array of the paths of files owned by the currently logged-in user. Can be publicly accessed.
sub get_uploaded_files {
    my $self = shift;
    my $uploadsid = $self->{uploadsid};# or confess "Need uploads ID for get_uploaded_files";
    my $uploadsdb = $self->{uploadsdb};
	my $rows = $uploadsdb->selectcol_arrayref("SELECT uploadid FROM uploads WHERE userid = " . $uploadsdb->quote($uploadsid) . " AND sharing_policy <> 'public' AND imported <> 1 ORDER BY uploadid");
	return @$rows;
}

# Get Public Files ([Search Term]) - Returns an array of available public files that the user hasn't added. Will filter results if the extra parameter is given.
sub get_public_files {
    my $self = shift;
    my $searchterm = shift;
    my $uploadsid = $self->{uploadsid} or return;
    
    # If we find a user from the term (ID or username), we'll search by user. Currently broken until I can either lookup a user's uploads ID, or just use the userids entirely.
    #my $userdb = $self->{userdb};
   	#my $search_id = $userdb->get_user_id($searchterm);
   	my $search_id = 0;
   	
    my $uploadsdb = $self->{uploadsdb};
    my $userid = $self->{userid};
    my $sql = "SELECT uploadid FROM uploads WHERE sharing_policy = 'public'";
    $sql .= " AND (users IS NULL OR users NOT LIKE " . $uploadsdb->quote("%" . $userid . "%") . ")" if $userid;
    $sql .= ($search_id)? " AND (userid = " . $uploadsdb->quote($search_id) . ")" : " AND (description LIKE " . $uploadsdb->quote("%" . $searchterm . "%") . " OR path LIKE " . $uploadsdb->quote("%" . $searchterm . "%") . ")";
    $sql .= " ORDER BY uploadid";
    cluck $sql;
    my $rows = $uploadsdb->selectcol_arrayref($sql);
    return @$rows;
}

# Get Imported Files () - Returns an array of files imported by a user.
sub get_imported_files {
	my $self = shift;
    my $uploadsid = $self->{uploadsid} or return;
    my $uploadsdb = $self->{uploadsdb};
	my $rows = $uploadsdb->selectcol_arrayref("SELECT uploadid FROM uploads WHERE userid = " . $uploadsdb->quote($uploadsid) . " AND sharing_policy <> 'public' AND imported = 1 ORDER BY uploadid");
	return @$rows;
}

# Get Added Public Files () - Returns an array of public files added to a user's tracks.
sub get_added_public_files {
	my $self = shift;
	my $userid = $self->{userid} or return;
	my $uploadsdb = $self->{uploadsdb};
    my $rows = $uploadsdb->selectcol_arrayref("SELECT uploadid FROM uploads WHERE sharing_policy = 'public' AND users LIKE " . $uploadsdb->quote('%' . $userid . '%') . " ORDER BY uploadid");
    return @$rows;
}

# Get Shared Files () - Returns an array of files shared specifically to a user.
sub get_shared_files {
	my $self = shift;
    my $userid = $self->{userid} or return;
    my $uploadsid = $self->{uploadsid};
    my $uploadsdb = $self->{uploadsdb};
    #Since upload IDs are all the same size, we don't have to worry about one ID repeated inside another so this next line is OK. Still, might be a good idea to secure this somehow?
    my $rows = $uploadsdb->selectcol_arrayref("SELECT uploadid FROM uploads WHERE (sharing_policy = 'group' OR sharing_policy = 'casual') AND users LIKE " . $uploadsdb->quote('%' . $userid . '%') . " AND userid <> " . $uploadsdb->quote($uploadsid) . " ORDER BY uploadid");
    return @$rows;
}

# Share (File[, Username OR User ID]) - Adds a public or shared track to a user's session.
sub share {
	my $self = shift;
	my $file = shift or confess "No input or invalid input given to share()";
	my $userid = shift || $self->{userid};
	
	# Users can add themselves to the sharing lists of casual or public files; owners can add people to group lists but can't force anyone to have a public or casual file.
	my $sharing_policy = $self->permissions($file);
	if ((($sharing_policy =~ /(casual|public)/) && ($userid eq $self->{userid})) || ($self->is_mine($file) && ($sharing_policy =~ /group/))) {
		# Get the current users.
		my $uploadsdb = $self->{uploadsdb};
		my $users = $uploadsdb->selectrow_array("SELECT users FROM uploads WHERE uploadid = " . $uploadsdb->quote($file));
	
		#If we find the user's ID, it's already been added, just return that it worked.
		return 1 if ($users =~ $userid);
		$users .= ", " if $users;
		return $uploadsdb->do("UPDATE uploads SET users = " . $uploadsdb->quote($users . $userid) . "  WHERE uploadid = " . $uploadsdb->quote($file));
	} else {
		warn "Share() attempted in an illegal situation on $file by " . ($self->{globals}->user_accounts? $self->{userdb}->get_username($userid) : $userid ) . ", a non-owner.";
	}
}

# Unshare (File[, Username OR User ID]) - Removes an added public or shared track from a user's session. Can be publicly accessed.
sub unshare {
	my $self = shift;
	my $file = shift or confess "No input or invalid input given to unshare()";
	my $userid = shift || $self->{userid};
	
	# Users can remove themselves from the sharing lists of casual or public files; owners can remove people from casual or group items.
	my $sharing_policy = $self->permissions($file);
	if ((($sharing_policy =~ /(casual|public)/) && ($userid eq $self->{userid})) || ($self->is_mine($file) && ($sharing_policy =~ /(casual|group)/))) {
		# Get the current users.
		my $uploadsdb = $self->{uploadsdb};
		my $users = $uploadsdb->selectrow_array("SELECT users FROM uploads WHERE uploadid = " . $uploadsdb->quote($file));
	
		#If we find the user's ID, it's already been removed, just return that it worked.
		return 1 if ($users !~ $userid);
		$users =~ s/$userid(, )?//i;
		$users =~ s/(, $)//i; #Not sure if this is the best way to remove a trailing ", "...probably not.
	
		return $uploadsdb->do("UPDATE uploads SET users = " . $uploadsdb->quote($users) . " WHERE uploadid = " . $uploadsdb->quote($file));
	} else {
		warn "Unshare() attempted in an illegal situation on $file by " . ($self->{globals}->user_accounts? $self->{userdb}->get_username($userid) : $userid ) . ", a non-owner.";
	}
}

# Field (Field, File ID[, Value]) - Returns (or, if defined, sets to the new value) the specified field of a file.
sub field {
    my $self = shift;
    my $field = shift or confess "No field specified.";
    my $file = shift or confess "No input input given to field()";
    my $value = shift;
    my $uploadsid = $self->{uploadsid};
    my $uploadsdb = $self->{uploadsdb};
    
    if ($value) {
    	if ($self->is_mine($file)) {
			#Clean up the string
			$value =~ s/^\s+//;
			$value =~ s/\s+$//; 
			my $now = $self->nowfun;
			my $result = $uploadsdb->do("UPDATE uploads SET $field = " . $uploadsdb->quote($value) . " WHERE uploadid = " . $uploadsdb->quote($file));
			$self->update_modified($file);
			return $result;
		} else {
	    	warn "Field() was called to modify $field on " . $file . " by " . ($self->{globals}->user_accounts? $self->{username} : $self->{userid} ) . ", a non-owner.";
	    }
    } else {
    	return $uploadsdb->selectrow_array("SELECT $field FROM uploads WHERE uploadid = " . $uploadsdb->quote($file));
    }
}

# Update Modified (File ID[, UploadsID]) - Updates the modification date/time of the specified file to right now.
sub update_modified {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $file = shift or confess "No input or invalid input given to update_modified()";
    my $now = $self->nowfun;
    return $uploadsdb->do("UPDATE uploads SET modification_date = $now WHERE uploadid = " . $uploadsdb->quote($file));
}

# Created (File ID) - Returns creation date of $file, cannot be set.
sub created {
    my $self  = shift;
    my $file = shift or confess "No input or invalid input given to created()";
    return $self->field("creation_date", $file);
}

# Modified (File ID) - Returns date modified of $file, cannot be set (except by update_modified()).
sub modified {
    my $self  = shift;
    my $file = shift or confess "No input or invalid input given to modified()";
   	return $self->field("modification_date", $file);
}

# Description (File ID[, Value]) - Returns a file's description, or changes the current description if defined.
sub description {
    my $self  = shift;
    my $file = shift or confess "No input or invalid input given to description()";
    my $value = shift;
    if ($value) {
    	if ($self->is_mine($file)) {
	    	return $self->field("description", $file, $value)
	    } else {
	    	warn "Change Description requested on $file by " . ($self->{globals}->user_accounts? $self->{username} : $self->{userid}) . ", a non-owner.";
	    }
    } else {
    	return $self->field("description", $file)
    }
}

# Add File (Full Path[, Description, Sharing Policy, Owner's Uploads ID]) - Adds $file to the database under the current (or specified) owner.
sub add_file {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $filename = shift;
    my $imported = shift || 0;
    my $description = $uploadsdb->quote(shift);
    my $uploadsid = shift || $self->{uploadsid};
    my $shared = $uploadsdb->quote(shift || "private");
    
    if ($self->get_file_id($filename) == 0) {
		my $fileid = md5_hex($uploadsid.$filename);
		my $now = $self->nowfun;
		$filename = $uploadsdb->quote($filename);
		$uploadsid = $uploadsdb->quote($uploadsid);
		$uploadsdb->do("INSERT INTO uploads (uploadid, userid, path, description, imported, creation_date, modification_date, sharing_policy) VALUES (" . $uploadsdb->quote($fileid) . ", $uploadsid, $filename, $description, $imported, $now, $now, $shared)");
		return $fileid;
    } else {
		warn (($self->{globals}->user_accounts)? $self->{username} : $self->{userid}), " has already uploaded $filename.";
    }
}

# Delete File (File ID) - Deletes $file_id from the database.
sub delete_file {
	my $self = shift;
    my $file = shift or confess "No file ID given to delete()";
    my $userid = $self->{userid};
    my $uploadsid = $self->{uploadsid};
    my $filename = $self->filename($file);
    
    if ($self->is_mine($file) || !$filename) {
		# First delete from the database.
		my $uploadsdb = $self->{uploadsdb};
		return $uploadsdb->do("DELETE FROM uploads WHERE uploadid = " . $uploadsdb->quote($file));
		
		# Then remove the file - better to have a dangling file then a dangling reference to nothing.
		my $loader = Bio::Graphics::Browser2::DataLoader->new($filename,
								  $self->track_path($file),
								  $self->track_conf($file),
								  $self->{config},
								  $userid);
		$loader->drop_databases($self->track_conf($file));
		chdir $self->path;
		rmtree($self->track_path($file));
    } else {
		warn "Delete of " . $filename . " requested by " . ($self->{globals}->user_accounts? $self->{username} : $self->{userid}) . ", a non-owner.";
	}
}

# Is Imported (File) - Returns 1 if an already-added track is imported, 0 if not.
sub is_imported {
	my $self = shift;
	my $file = shift or confess "No file ID given to is_imported()";
	my $uploadsdb = $self->{uploadsdb};
	return $uploadsdb->selectrow_array("SELECT imported FROM uploads WHERE uploadid = " . $uploadsdb->quote($file)) || 0;
}

# Permissions (File[, New Permissions]) - Return or change the permissions.
sub permissions {
	my $self = shift;
	my $file = shift or confess "No file ID given to permissions()";
	my $new_permissions = shift;
	if ($new_permissions) {
		if ($self->is_mine($file)) {
			$self->field("users", $file, $self->{userid}) if $new_permissions =~ /public/;
			return $self->field("sharing_policy", $file, $new_permissions);
		} else {
			warn "Permissions change on " . $file . "requested by " . ($self->{globals}->user_accounts? $self->{username} : $self->{userid}) . " a non-owner.";
		}
	} else {
		return $self->field("sharing_policy", $file);
	}
}

# Is Mine (Filename) - Returns 1 if a track is owned by the logged-in (or specified) user, 0 if not.
sub is_mine {
	my $self = shift;
	my $file = shift or confess "No file ID given to is_mine()";
	my $owner = $self->owner($file);
	return ($owner eq $self->{uploadsid})? 1 : 0;
}

# Owner (Filename) - Returns the owner of the specified file.
sub owner {
	my $self = shift;
	my $file = shift or return;
	my $uploadsdb = $self->{uploadsdb};
	return $uploadsdb->selectrow_array("SELECT userid FROM uploads WHERE uploadid = " . $uploadsdb->quote($file));
}

# Is Shared With Me (Filename) - Returns 1 if a track is shared with the logged-in (or specified) user, 0 if not.
sub is_shared_with_me {
	my $self = shift;
	my $file = shift or confess "No file ID given to is_shared_with_me()";
	my $uploadsdb = $self->{uploadsdb};
	my $results = $uploadsdb->selectcol_arrayref("SELECT uploadid FROM uploads WHERE path = " . $uploadsdb->quote($file) . " AND users LIKE " . $uploadsdb->quote("%" . $self->{userid} . "%"));
	return (@$results > 0);
}

# Sharing Link (File ID) - Generates the sharing link for a specific file.
sub sharing_link {
	my $self = shift;
	my $file = shift or confess "No file ID given to sharing_link()";
	return url(-full => 1, -path_info => 1) . "?share_link=" . $file;
}

# File Type (File ID) - Returns the type of a specified track, in relation to the user.
sub file_type {
	my $self = shift;
	my $file = shift or confess "No file ID given to file_type()";
	return "public" if ($self->permissions($file) =~ /public/);
	if ($self->is_mine($file)) {
		return $self->is_imported($file)? "imported" : "uploaded";
	} else { return "shared" };
}

# Shared With (File ID) - Returns an array of users a track is shared with.
sub shared_with {
	my $self = shift;
	my $file = shift or confess "No file ID given to shared_with()";
	my $users_string = $self->field("users", $file);
	return split(", ", $users_string);
}

1;
