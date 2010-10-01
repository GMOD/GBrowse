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
	my ($data_source, $globals, $userid, $uploadsid);
	if (@_ == 1) {
		warn "I'm being called with Render";
		my $render = shift;
		$data_source = $render->data_source;
		$globals = $data_source->globals;
		$userid = $render->session->id;
		$uploadsid = $render->session->page_settings->{uploadid}; #Renamed to avoid confusion with the ID of an upload.
	} else {
		warn "I'm being called with Data Source and State";
		$data_source = shift;
		my $state = shift;
		$globals = $data_source->globals;
		$userid = $state->{userid};
		$uploadsid = $state->{uploadid}; #Renamed to avoid confusion with the ID of an upload.
	}

    my $credentials = $globals->upload_db_adaptor or die "No credentials given to uploads DB in GBrowse.conf";
    if ($credentials =~ /^DBI:+mysql/) {
    	if ($globals->upload_db_host && $globals->upload_db_user) {
			$credentials = "DBI:mysql:gbrowse_login;host=".$globals->upload_db_host if $globals->upload_db_host;
			$credentials .= ";user=".$globals->upload_db_user if $globals->upload_db_user;
			$credentials .= ";password=".$globals->upload_db_pass if $globals->upload_db_pass;
		} else {
			$credentials = $globals->upload_db_adaptor;
		}
	}
    my $login = DBI->connect($credentials);
	unless ($login) {
		print header();
		print "Error: Could not open login database.";
		die "Could not open login database $credentials";
	}
	
    my $self = bless {
    	config	  => $data_source,
    	uploadsdb => $login,
		userid	  => $userid,
		uploadsid => $uploadsid,
		globals	  => $globals,
    }, ref $class || $class;
    
    $self->{userdb} = Bio::Graphics::Browser2::UserDB->new if $globals->user_accounts;
    return $self;
}

# Get File ID (Filename[, Owner ID]) - Returns a file's validated ID from the database.
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
	my $fileid = shift or confess "No file ID given to filename().";
	return $self->field("path", $fileid);
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

# Get Public Files ([User ID]) - Returns an array of available public files that the user hasn't added.
sub get_public_files {
    my $self = shift;
    my $searchterm = shift;
    my $uploadsid = $self->{uploadsid} or return;
    my $uploadsdb = $self->{uploadsdb};
    my $userid = $self->{userid};
    my $sql = "SELECT uploadid FROM uploads WHERE sharing_policy = 'public'";
    $sql .= "AND (users IS NULL OR users NOT LIKE " . $uploadsdb->quote("%" . $userid . "%") . ")" if $userid;
    $sql .= "AND (description LIKE " . $uploadsdb->quote("%" . $searchterm . "%") . " OR path LIKE " . $uploadsdb->quote("%" . $searchterm . "%") . ")" if $searchterm;
    $sql .= " ORDER BY uploadid";
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
	my $fileid = shift or confess "No input or invalid input given to share()";

	# If we've been passed a user ID, use that. If we've been passed a username, get the ID. If we haven't been passed anything, use the session user ID.
	my $userid;
	if ($self->{globals}->user_accounts) {
		my $userdb = $self->{userdb};
		$userid = $userdb->get_user_id(shift);
	} else {
		$userid = shift;
	}
	
	# Users can add themselves to the sharing lists of casual or public files; owners can add people to group lists but can't force anyone to have a public or casual file.
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
		warn "Share() attempted in an illegal situation on $fileid by " . ($self->{globals}->user_accounts? $self->{userdb}->get_username($userid) : $userid ) . ", a non-owner.";
	}
}

# Unshare (File[, Username OR User ID]) - Removes an added public or shared track from a user's session. Can be publicly accessed.
sub unshare {
	my $self = shift;
	my $fileid = shift or confess "No input or invalid input given to unshare()";
	
	# If we've been passed a user ID, use that. If we've been passed a username, get the ID. If we haven't been passed anything, use the session user ID.
	my $userid;
	if ($self->{globals}->user_accounts) {
		my $userdb = $self->{userdb};
		$userid = $userdb->get_user_id(shift) || $self->{userid};
	} else {
		$userid = shift || $self->{userid};
	}
	
	# Users can remove themselves from the sharing lists of casual or public files; owners can remove people from casual or group items.
	my $sharing_policy = $self->permissions($fileid);
	if ((($sharing_policy =~ /(casual|public)/) && ($userid eq $self->{userid})) || ($self->is_mine($fileid) && ($sharing_policy =~ /(casual|group)/))) {
		# Get the current users.
		my $uploadsdb = $self->{uploadsdb};
		my $users = $uploadsdb->selectrow_array("SELECT users FROM uploads WHERE uploadid = " . $uploadsdb->quote($fileid));
	
		#If we find the user's ID, it's already been removed, just return that it worked.
		return 1 if ($users !~ $userid);
		$users =~ s/$userid(, )?//i;
		$users =~ s/(, $)//i; #Not sure if this is the best way to remove a trailing ", "...probably not.
	
		return $uploadsdb->do("UPDATE uploads SET users = " . $uploadsdb->quote($users) . " WHERE uploadid = " . $uploadsdb->quote($fileid));
	} else {
		warn "Unshare() attempted in an illegal situation on $fileid by " . ($self->{globals}->user_accounts? $self->{userdb}->get_username($userid) : $userid ) . ", a non-owner.";
	}
}

# Field (Field, File ID[, Value]) - Returns (or, if defined, sets to the new value) the specified field of a file.
sub field {
    my $self = shift;
    my $field = shift or confess "No field specified.";
    my $fileid = shift or confess "No input input given to field()";
    my $value = shift;
    my $uploadsid = $self->{uploadsid};
    my $uploadsdb = $self->{uploadsdb};
    
    if ($value) {
    	if ($self->is_mine($fileid)) {
			#Clean up the string
			$value =~ s/^\s+//;
			$value =~ s/\s+$//; 
			my $now = $self->nowfun;
			my $result = $uploadsdb->do("UPDATE uploads SET $field = " . $uploadsdb->quote($value) . " WHERE uploadid = " . $uploadsdb->quote($fileid));
			$self->update_modified($fileid);
			return $result;
		} else {
	    	warn "Field() was called to modify $field on " . $fileid . " by " . ($self->{globals}->user_accounts? $self->{userdb}->get_username($self->{userid}) : $self->{userid} ) . ", a non-owner.";
	    }
    } else {
    	return $uploadsdb->selectrow_array("SELECT $field FROM uploads WHERE uploadid = " . $uploadsdb->quote($fileid));
    }
}

# Update Modified (File ID[, UploadsID]) - Updates the modification date/time of the specified file to right now.
sub update_modified {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $fileid = shift or confess "No input or invalid input given to update_modified()";
    my $now = $self->nowfun;
    return $uploadsdb->do("UPDATE uploads SET modification_date = $now WHERE uploadid = " . $uploadsdb->quote($fileid));
}

# Created (File ID) - Returns creation date of $fileid, cannot be set.
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
	    	warn "Change Description requested on $file by " . ($self->{globals}->user_accounts? $self->{userdb}->get_username($self->{userid}) : $self->{userid}) . ", a non-owner.";
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
		$fileid = $uploadsdb->quote($fileid);
		return $uploadsdb->do("INSERT INTO uploads (uploadid, userid, path, description, imported, creation_date, modification_date, sharing_policy) VALUES ($fileid, $uploadsid, $filename, $description, $imported, $now, $now, $shared)");
    } else {
		warn ($self->{globals}->user_accounts? $self->{userdb}->get_username($self->{userid}) : $self->{userid}) . " has already uploaded $filename.";
    }
}

# Delete File (File ID) - Deletes $file_id from the database.
sub delete_file {
	my $self = shift;
    my $fileid = shift or confess "No file ID given to delete()";
    my $userid = $self->{userid};
    my $uploadsid = $self->{uploadsid};
    my $filename = $self->filename($fileid);
    
    if ($self->is_mine($fileid) || !$filename) {
		# First delete from the database.
		my $uploadsdb = $self->{uploadsdb};
		return $uploadsdb->do("DELETE FROM uploads WHERE uploadid = " . $uploadsdb->quote($fileid));
		
		# Then remove the file - better to have a dangling file then a dangling reference to nothing.
		my $loader = Bio::Graphics::Browser2::DataLoader->new($filename,
								  $self->track_path($fileid),
								  $self->track_conf($fileid),
								  $self->{config},
								  $userid);
		$loader->drop_databases($self->track_conf($fileid));
		chdir $self->path;
		rmtree($self->track_path($fileid));
    } else {
		warn "Delete of " . $filename . " requested by " . ($self->{globals}->user_accounts? $self->{userdb}->get_username($self->{userid}) : $self->{userid}) . ", a non-owner.";
	}
}

# Is Imported (File) - Returns 1 if an already-added track is imported, 0 if not.
sub is_imported {
	my $self = shift;
	my $fileid = shift or confess "No file ID given to is_imported()";
	my $uploadsdb = $self->{uploadsdb};
	return $uploadsdb->selectrow_array("SELECT imported FROM uploads WHERE uploadid = " . $uploadsdb->quote($fileid)) || 0;
}

# Permissions (File[, New Permissions]) - Return or change the permissions.
sub permissions {
	my $self = shift;
	my $fileid = shift or confess "No file ID given to permissions()";
	my $new_permissions = shift;
	if ($new_permissions) {
		if ($self->is_mine($fileid)) {
			$self->field("users", $fileid, $self->{userid}) if $new_permissions =~ /public/;
			return $self->field("sharing_policy", $fileid, $new_permissions);
		} else {
			warn "Permissions change on " . $fileid . "requested by " . ($self->{globals}->user_accounts? $self->{userdb}->get_username($self->{userid}) : $self->{userid}) . " a non-owner.";
		}
	} else {
		return $self->field("sharing_policy", $fileid);
	}
}

# Is Mine (Filename) - Returns 1 if a track is owned by the logged-in (or specified) user, 0 if not.
sub is_mine {
	my $self = shift;
	my $fileid = shift or confess "No file ID given to is_mine()";
	my $owner = $self->owner($fileid);
	return ($owner eq $self->{uploadsid})? 1 : 0;
}

# Owner (Filename) - Returns the owner of the specified file.
sub owner {
	my $self = shift;
	my $fileid = shift or confess "No file ID given to owner()";
	my $uploadsdb = $self->{uploadsdb};
	return $uploadsdb->selectrow_array("SELECT userid FROM uploads WHERE uploadid = " . $uploadsdb->quote($fileid));
}

# Is Shared With Me (Filename) - Returns 1 if a track is shared with the logged-in (or specified) user, 0 if not.
sub is_shared_with_me {
	my $self = shift;
	my $uploadsdb = $self->{uploadsdb};
	my $fileid = shift or confess "No file ID given to is_shared_with_me()";
	my $results = $uploadsdb->selectcol_arrayref("SELECT uploadid FROM uploads WHERE path = " . $uploadsdb->quote($fileid) . " AND users LIKE " . $uploadsdb->quote("%" . $self->{userid} . "%"));
	return (@$results > 0);
}

# Sharing Link (File ID) - Generates the sharing link for a specific file.
sub sharing_link {
	my $self = shift;
	my $fileid = shift or confess "No file ID given to sharing_link()";
	return url(-full => 1, -path_info => 1) . "?share_link=" . $fileid;
}

# File Type (File ID) - Returns the type of a specified track, in relation to the user.
sub file_type {
	my $self = shift;
	my $fileid = shift or confess "No file ID given to file_type()";
	return "public" if ($self->permissions($fileid) =~ /public/);
	if ($self->is_mine($fileid)) {
		return $self->is_imported($fileid)? "imported" : "uploaded";
	} else { return "shared" };
}

# Shared With (File ID) - Returns an array of users a track is shared with.
sub shared_with {
	my $self = shift;
	my $fileid = shift or confess "No file ID given to shared_with()";
	my $users_string = $self->field("users", $fileid);
	return split(", ", $users_string);
}

1;
