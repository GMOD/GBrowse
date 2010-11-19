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
use File::Path qw(rmtree);

sub _new {
    my $class = shift;
    my $VERSION = '0.5';
    my ($data_source, $globals, $uploadsid, $userid) = @_;
    
    # Attempt to login to the database or die, and access the necessary tables or create them.
    my $credentials = $globals->uploads_db or warn "No credentials given to uploads DB in GBrowse.conf";
    my $uploadsdb = DBI->connect($credentials);
    unless ($uploadsdb) {
        print header();
        print "Error: Could not open uploads database.";
        die "Could not open uploads database with $credentials";
    }
    
    my $self = bless {
        config      => $data_source,
        uploadsdb => $uploadsdb,
        userid      => $userid,
        uploadsid => $uploadsid,
        globals      => $globals,
    }, ref $class || $class;
    
    # Check to see if user accounts are enabled, set some globals just in case.
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
    return $globals->uploads_db =~ /sqlite/i ? "datetime('now','localtime')" : 'now()';
}

# Get Uploaded Files () - Returns an array of the paths of files owned by the currently logged-in user. Can be publicly accessed.
sub get_uploaded_files {
    my $self = shift;
    my $uploadsid = $self->{uploadsid};# or confess "Need uploads ID for get_uploaded_files";
    my $uploadsdb = $self->{uploadsdb};
    my $rows = $uploadsdb->selectcol_arrayref("SELECT uploadid FROM uploads WHERE userid = " . $uploadsdb->quote($uploadsid) . " AND sharing_policy <> 'public' AND imported <> 1 ORDER BY uploadid");
    return @$rows;
}

# Get Public Files ([Search Term, Offset]) - Returns an array of available public files that the user hasn't added. Will filter results if the extra parameter is given.
sub get_public_files {
    my $self = shift;
    my $searchterm = shift;
    my $offset = shift;
    my $uploadsid = $self->{uploadsid} or return;
    my $globals = $self->{globals};
    my $count = $globals->public_files;
    
    my $search_id;
    if ($self->{globals}->user_accounts) {
        # If we find a user from the term (ID or username), we'll search by user.
        my $userdb = $self->{userdb};
        $search_id = $userdb->get_uploads_id($userdb->get_user_id($searchterm));
    }
    
    # Make sure we're not looking for files outside of the range.
    my $public_count = $self->public_count;
    $offset = ($offset > $public_count)? $public_count : $offset;
    
    my $uploadsdb = $self->{uploadsdb};
    my $userid = $self->{userid};
    my $sql = "SELECT uploadid FROM uploads WHERE sharing_policy = " . $uploadsdb->quote("public");
    $sql .= " AND (public_users IS NULL OR public_users NOT LIKE " . $uploadsdb->quote("%" . $userid . "%") . ")" if $userid;
    $sql .= ($search_id)? " AND (userid = " . $uploadsdb->quote($search_id) . ")" : " AND (description LIKE " . $uploadsdb->quote("%" . $searchterm . "%") . " OR path LIKE " . $uploadsdb->quote("%" . $searchterm . "%") . "OR title LIKE " . $uploadsdb->quote("%" . $searchterm . "%") . ")" if $searchterm;
    $sql .= " ORDER BY public_count DESC LIMIT $count";
    $sql .= " OFFSET $offset" if $offset;
    my $rows = $uploadsdb->selectcol_arrayref($sql);
    return @$rows;
}

# Public Count ([Search Term]) - Returns the total number of public files available to a user.  Will filter results if a search parameter is given.
sub public_count {
    my $self = shift;
    my $searchterm = shift;
    my $uploadsid = $self->{uploadsid} or return;
    my $uploadsdb = $self->{uploadsdb};
    
    my $search_id;
    if ($self->{globals}->user_accounts) {
        # If we find a user from the term (ID or username), we'll search by user.
        my $userdb = $self->{userdb} ;
        $search_id = $userdb->get_uploads_id($userdb->get_user_id($searchterm));
    }
    
    my $userid = $self->{userid};
    my $sql = "SELECT count(*) FROM uploads WHERE sharing_policy = " . $uploadsdb->quote("public");
    $sql .= " AND (public_users IS NULL OR public_users NOT LIKE " . $uploadsdb->quote("%" . $userid . "%") . ")" if $userid;
    $sql .= $search_id? " AND (userid = " . $uploadsdb->quote($search_id) . ")" : " AND (description LIKE " . $uploadsdb->quote("%" . $searchterm . "%") . " OR path LIKE " . $uploadsdb->quote("%" . $searchterm . "%") . "OR title LIKE " . $uploadsdb->quote("%" . $searchterm . "%") . ")" if $searchterm;
    return $uploadsdb->selectrow_array($sql);
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
    my $rows = $uploadsdb->selectcol_arrayref("SELECT uploadid FROM uploads WHERE sharing_policy = 'public' AND public_users LIKE " . $uploadsdb->quote('%' . $userid . '%') . " ORDER BY uploadid");
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
    
    # If we've been passed a user ID, use that. If we've been passed a username, get the ID. If we haven't been passed anything, use the session user ID.
    my $userid;
    if ($self->{globals}->user_accounts) {
        my $userdb = $self->{userdb};
        $userid = $userdb->get_user_id(shift);
    } else {
        $userid = shift;
    }
    $userid ||= $self->{userid};

    my $sharing_policy = $self->permissions($file);
    return if $self->is_mine($file) and $sharing_policy =~ /group/ and $userid eq $self->{userid}; # No sense in adding yourself to a group. Also fixes a bug with nonsense users returning your ID and adding yourself instead of nothing.
    # Users can add themselves to the sharing lists of casual or public files; owners can add people to group lists but can't force anyone to have a public or casual file.
    if ((($sharing_policy =~ /(casual|public)/) && ($userid eq $self->{userid})) || ($self->is_mine($file) && ($sharing_policy =~ /group/))) {
        # Get the current users.
        my $users_field = ($sharing_policy =~ /public/)? "public_users" : "users";
        my $uploadsdb = $self->{uploadsdb};
        my @users = split ", ", $self->field($users_field, $file);

        #If we find the user's ID, it's already been added, just return that it worked.
        return 1 if grep { $_ eq $userid } @users;
        push @users, $userid;
        
        # Update the public count if needed.
        if ($sharing_policy =~ /public/) {
            my $public_count = @users;
            $self->field("public_count", $file, $public_count);
        }
        
        return $self->field($users_field, $file, join ", ", @users);
    } else {
        warn "Share() attempted in an illegal situation on a $sharing_policy file ($file) by " . ($self->{globals}->user_accounts? $self->{userdb}->get_username($userid) : $userid ) . ", a non-owner.";
    }
}

# Unshare (File[, Username OR User ID]) - Removes an added public or shared track from a user's session.
sub unshare {
    my $self = shift;
    my $file = shift or confess "No input or invalid input given to unshare()";
    my $userid = shift || $self->{userid};
    
    # Users can remove themselves from the sharing lists of casual or public files; owners can remove people from casual or group items.
    my $sharing_policy = $self->permissions($file);
    if ((($sharing_policy =~ /(casual|public)/) && ($userid eq $self->{userid})) || ($self->is_mine($file) && ($sharing_policy =~ /(casual|group)/))) {
        # Get the current users.
        my $users_field = ($sharing_policy =~ /public/)? "public_users" : "users";
        my $uploadsdb = $self->{uploadsdb};
        my @users = split ", ", $self->field($users_field, $file);
    
        #If we find the user's ID, it's already been removed, just return that it worked.
        return 1 unless grep { $_ eq $userid } @users;
        my ($index) = grep { $users[$_] eq $userid } 0 .. $#users;
        splice @users, $index;
        
        # Update the public count if needed.
        if ($sharing_policy =~ /public/) {
            my $public_count = @users;
            $self->field("public_count", $file, $public_count);
        }
        
        return $self->field($users_field, $file, join ", ", @users);
    } else {
        warn "Unshare() attempted in an illegal situation on a $sharing_policy file ($file) by " . ($self->{globals}->user_accounts? $self->{userdb}->get_username($userid) : $userid ) . ", a non-owner.";
    }
}

# Field (Field, File ID[, Value]) - Returns (or, if defined, sets to the new value) the specified field of a file.
# This function is dangerous as it has direct access to the database and doesn't do any permissions checks (that's done at the individual field functions like title() and description().
# Make sure you set your permissions at the function level, and never put this into Action.pm or you'll be able to corrupt your database from a URL request!
sub field {
    my $self = shift;
    my $field = shift or confess "No field specified.";
    my $file = shift or confess "No input input given to field()";
    my $value = shift;
    my $uploadsid = $self->{uploadsid};
    my $uploadsdb = $self->{uploadsdb};
    
    if (defined $value) {
        #Clean up the string
        $value =~ s/^\s+//;
        $value =~ s/\s+$//; 
        my $now = $self->nowfun;
        my $result = $uploadsdb->do("UPDATE uploads SET $field = " . $uploadsdb->quote($value) . " WHERE uploadid = " . $uploadsdb->quote($file));
        $self->update_modified($file);
        return $result;
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
    # Do not swap out this line for a field() call, since it's used inside field().
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

# Title (File ID[, Value]) - Returns a file's title, or changes the current title if defined.
sub title {
    my $self  = shift;
    my $file = shift or confess "No input or invalid input given to title()";
    my $value = shift;
    if ($value) {
        if ($self->is_mine($file)) {
            return $self->field("title", $file, $value)
        } else {
            warn "Change title requested on $file by " . ($self->{globals}->user_accounts? $self->{username} : $self->{userid}) . ", a non-owner.";
        }
    } else {
        return $self->field("title", $file) || $self->field("path", $file);
    }
}

# Add File (Full Path[, Imported, Description, Sharing Policy, Owner's Uploads ID]) - Adds $file to the database under the current (or specified) owner.
sub add_file {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $filename = shift;
    my $imported = shift || 0;
    my $description = $uploadsdb->quote(shift);
    my $uploadsid = shift || $self->{uploadsid};
    my $shared = $uploadsdb->quote(shift || ($self =~ /admin/)? "public" : "private");
    
    my $fileid = md5_hex($uploadsid.$filename);
    my $now = $self->nowfun;
    $filename = $uploadsdb->quote($filename);
    $uploadsid = $uploadsdb->quote($uploadsid);
    $uploadsdb->do("INSERT INTO uploads (uploadid, userid, path, description, imported, creation_date, modification_date, sharing_policy) VALUES (" . $uploadsdb->quote($fileid) . ", $uploadsid, $filename, $description, $imported, $now, $now, $shared)");
    return $fileid;
}

# Delete File (File ID) - Deletes $file_id from the database.
sub delete_file {
    my $self = shift;
    my $file = shift or confess "No file ID given to delete()";
    my $userid = $self->{userid};
    my $uploadsid = $self->{uploadsid};
    my $filename = $self->filename($file);
    
    if ($self->is_mine($file) || !$filename) {
        my $path = $self->track_path($file);
        
        if ($filename) {
            # First delete from the database - better to have a dangling file then a dangling reference to nothing.
            my $uploadsdb = $self->{uploadsdb};
            $uploadsdb->do("DELETE FROM uploads WHERE uploadid = " . $uploadsdb->quote($file));
        }
        
        # Now remove the backend database.
        my $loader = Bio::Graphics::Browser2::DataLoader->new($filename,
                                  $path,
                                  $self->track_conf($file),
                                  $self->{config},
                                  $userid);
        $loader->drop_databases($self->track_conf($file));
        
        # Then remove the file if it exists.
        rmtree($path) or warn "Could not delete $path: $!" if -e $path;
    } else {
        warn "Delete of " . $filename . " requested by " . ($self->{globals}->user_accounts? $self->{username} : $self->{userid}) . ", a non-owner.";
    }
}

# Is Imported (File) - Returns 1 if an already-added track is imported, 0 if not.
sub is_imported {
    my $self = shift;
    my $file = shift or confess "No file ID given to is_imported()";
    my $uploadsdb = $self->{uploadsdb};
    return $self->field("imported", $file) || 0;
}

# Permissions (File[, New Permissions]) - Return or change the permissions.
sub permissions {
    my $self = shift;
    my $file = shift or confess "No file ID given to permissions()";
    my $new_permissions = shift;
    if ($new_permissions) {
        if ($self->is_mine($file)) {
            my $result = $self->field("sharing_policy", $file, $new_permissions);
            $self->share($file, $self->{userid}) if $new_permissions =~ /public/; # If we're switching to public permissions, share with the user so it doesn't disappear.
            return $result;
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
    return $self->field("userid", $file);
}

# Is Shared With Me (Filename) - Returns 1 if a track is shared with the logged-in (or specified) user, 0 if not.
sub is_shared_with_me {
    my $self = shift;
    my $file = shift or confess "No file ID given to is_shared_with_me()";
    my $uploadsdb = $self->{uploadsdb};
    my $results = $uploadsdb->selectcol_arrayref("SELECT uploadid FROM uploads WHERE uploadid = " . $uploadsdb->quote($file) . " AND users LIKE " . $uploadsdb->quote("%" . $self->{userid} . "%") . "OR public_users LIKE " . $uploadsdb->quote("%" . $self->{userid} . "%"));
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
    return unless $self->permissions($file) =~ /(casual|group)/;
    my $users_string = $self->field("users", $file);
    return split(", ", $users_string);
}

# Public Users (File ID) - Returns an array of users of a public track.
sub public_users {
    my $self = shift;
    my $file = shift or confess "No file ID given to public_users()";
    return unless $self->permissions($file) =~ /public/;
    my $users_string = $self->field("public_users", $file);
    return split(", ", $users_string);
}

1;
