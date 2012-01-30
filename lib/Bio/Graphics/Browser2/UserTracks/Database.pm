package Bio::Graphics::Browser2::UserTracks::Database;

# $Id: Database.pm 23607 2010-07-30 17:34:25Z cnvandev $
use strict;
use base 'Bio::Graphics::Browser2::UserTracks';
use Bio::Graphics::Browser2;
use Bio::Graphics::Browser2::UserDB;
use Bio::Graphics::Browser2::SendMail;
use DBI;
use Digest::MD5 qw(md5_hex);
use CGI qw(param url header());
use Carp qw(confess cluck);
use File::Path qw(rmtree);

sub _new {
    my $class = shift;
    my $self  = $class->SUPER::_new(@_);
    
    # Attempt to login to the database or die, and access the necessary tables or create them.
    my $globals     = $self->globals;
    my $credentials = $globals->user_account_db or warn "No credentials given to uploads DB in GBrowse.conf";
    my $uploadsdb   = DBI->connect($credentials);
    unless ($uploadsdb) {
        print header();
        print "Error: Could not open use account database.";
        die "Could not open user account database with $credentials";
    }
    $self->uploadsdb($uploadsdb);
    
    # Check to see if user accounts are enabled, set some commonly-used variables.
    if ($globals->user_accounts) {
	# BUG: Two copies of UserDB; one here and one in the Render object
        $self->{userdb}   = Bio::Graphics::Browser2::UserDB->new($globals);
        $self->{username} = $self->{userdb}->username_from_sessionid($self->sessionid);
        $self->{userid}   = $self->{userdb}->userid_from_sessionid($self->sessionid);
    }
    
    return $self;
}

sub uploadsdb {
    my $self = shift;
    my $d    = $self->{uploadsdb};
    $self->{uploadsdb} = shift if @_;
    $d;
}

sub userdb   { shift->{userdb}   }
sub userid   { shift->{userid}   }
sub username { shift->{username} }

# Path - Returns the path to a specified file's owner's (or just the logged-in user's) data folder.
sub path {
    my $self = shift;
    my $file = shift;
    my ($userid, $uploadsid);
    if (defined $file) {
        my $userdb = $self->{userdb};
        $userid    = $self->owner($file);
        $uploadsid = $userdb->get_uploads_id($userid);
    }

    $uploadsid ||= $self->uploadsid;
    if ($uploadsid eq $self->uploadsid) {
	return $self->SUPER::path();
    } else {
	return $self->data_source->userdata($uploadsid);
    }
}

# Get File ID (File ID [, Owner ID]) - Returns a file's validated ID from the database.
sub get_file_id {
    my $self = shift;
    my $filename = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $userid = $self->{userid};
    my $data_source = $self->{data_source};
    
    # First, check my files.
    my $uploads = $uploadsdb->selectrow_array("SELECT trackid FROM uploads WHERE path = ? AND userid = ? AND data_source = ?", undef, $filename, $userid, $data_source);
    return $uploads if $uploads;
    
    # Then, check files shared with me.
    my $shared = $uploadsdb->selectrow_array("SELECT DISTINCT uploads.trackid FROM uploads LEFT JOIN sharing ON uploads.trackid = sharing.trackid WHERE sharing.userid = ? AND uploads.path = ? AND (uploads.sharing_policy = ? OR uploads.sharing_policy = ?) AND data_source = ?", undef, $userid, $filename, "casual", "group", $data_source);
    return $shared if $shared;
    
    # Lastly, check public files.
    my $public = $uploadsdb->selectrow_array("SELECT trackid FROM uploads WHERE path = ? AND sharing_policy = ? AND data_source = ?", undef, $filename, "public", $data_source);
    return $public if $public;
}

# Filename (File ID) - Returns the filename of any given ID.
sub filename {
    my $self = shift;
    my $file = shift or return;
    return $self->field("path", $file);
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
    my $userid = $self->{userid};
    my $uploadsdb   = $self->{uploadsdb};
    my $data_source = $self->{data_source};
    my $rows = $uploadsdb->selectcol_arrayref("SELECT trackid FROM uploads WHERE userid = ? AND sharing_policy <> ? AND imported <> 1 AND data_source=? ORDER BY trackid", undef, $userid, "public", $data_source);
    return @$rows;
}

# this is used to autocomplete usernames, descriptions and filenames
sub prefix_search {
    my $self   = shift;
    my $prefix = shift;

    my (%results);
    if ($self->globals->user_accounts) {
	my $userdb = $self->{userdb};
	my $user_matches = $userdb->match_sharing_user($self->datasource_name,$prefix);
	foreach (@$user_matches) {
	    $results{$_} = "<i>$_</i>";
	}
    }
    my $upload_matches = $self->match_uploads($self->datasource_name,$prefix);
    foreach (@$upload_matches) {
	$results{$_} = "<b>$_</b>";
    }
    my @results = map {$results{$_}} sort {lc $a cmp lc $b} keys %results;
    return \@results;
}

sub user_search {
    my $self   = shift;
    my $prefix = shift;

    return unless $self->globals->user_accounts;
    my $userdb = $self->{userdb};
    my $results = $userdb->match_user($prefix);
    return $results;
}

# Get Public Files ([Search Term, Offset]) - Returns an array of available public files that the user hasn't added. Will filter results if the extra parameter is given.
sub get_public_files {
    my $self = shift;
    my $searchterm = shift;
    my $offset     = shift;

    my $globals = $self->{globals};
    my $count = $globals->public_files;
    my $data_source = $self->{data_source};
    
    my $search_id;
    if ($self->{globals}->user_accounts) {
        # If we find a user from the term (ID or username), we'll search by user.
        my $userdb = $self->{userdb};
        $search_id = $userdb->get_user_id($searchterm);
    }
    
    # Make sure we're not looking for files outside of the range.
    my $public_count = $self->public_count;
    $offset = ($offset > $public_count)? $public_count : $offset;
    
    my $uploadsdb = $self->{uploadsdb};
    my $userid    = $self->{userid};
    
    # Basic selection statement, limit to public tracks from this data set.
    my $ds = $uploadsdb->quote($data_source);
    my $sql =<<END;
SELECT u.trackid FROM uploads u
 WHERE u.sharing_policy='public'
   AND u.data_source=$ds
END
;
    $sql .=  "AND u.trackid NOT IN (SELECT trackid FROM sharing WHERE userid=$userid)"
	if $userid;
    
    # Search string - if we have a searched ID, use that as the userid. If not, match the searchterm to description, path or title.
    $sql .= $search_id? " AND (u.userid = "       . $uploadsdb->quote($search_id) . ")"
                      : " AND (description LIKE " . $uploadsdb->quote("%".$searchterm."%")
                      . " OR path LIKE "          . $uploadsdb->quote("%".$searchterm."%")
                      . " OR title LIKE "         . $uploadsdb->quote("%".$searchterm."%") . ")" if $searchterm;
    
    # Limit & offset as needed... 
    $sql .= " ORDER BY public_count DESC LIMIT $count";
    $sql .= " OFFSET $offset" if $offset;

    my $rows = $uploadsdb->selectcol_arrayref($sql);
    return @$rows;
}

# Public Count ([Search Term]) - Returns the total number of public files available to a user.  
# Will filter results if a search parameter is given.
sub public_count {
    my $self = shift;
    my $searchterm = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $userid = $self->{userid};
    my $data_source = $self->{data_source};
    
    my $search_id;
    if ($self->{globals}->user_accounts) {
        # If we find a user from the term (ID or username), we'll search by user.
        my $userdb = $self->{userdb} ;
        $search_id = $userdb->get_user_id($searchterm);
    }
    
    my $sql = "SELECT u.trackid FROM uploads u"
            . " LEFT JOIN (SELECT s.trackid FROM sharing s WHERE s.userid = " . $uploadsdb->quote($userid) . ") s"
            . " USING(trackid) WHERE s.trackid IS NULL"
            . " AND sharing_policy = " . $uploadsdb->quote("public")
            . " AND data_source = " . $uploadsdb->quote($data_source);
    
    $sql .= $search_id? " AND (u.userid = "   . $uploadsdb->quote($search_id) . ")"
                      : " AND (description LIKE "   . $uploadsdb->quote("%".$searchterm."%")
                      . " OR path LIKE "            . $uploadsdb->quote("%".$searchterm."%")
                      . " OR title LIKE "           . $uploadsdb->quote("%".$searchterm."%") . ")" if $searchterm;
    
    my $rows = $uploadsdb->selectcol_arrayref($sql);
    return @$rows;
}

# Get Imported Files () - Returns an array of files imported by a user.
sub get_imported_files {
    my $self = shift;
    my $userid = $self->{userid};
    my $uploadsdb = $self->{uploadsdb};
    my $data_source = $self->{data_source};
    my $rows = $uploadsdb->selectcol_arrayref("SELECT trackid FROM uploads WHERE sharing_policy <> 'public' AND imported = 1 AND data_source = ? AND userid = ? ORDER BY trackid", undef, $data_source, $userid);
    return @$rows;
}

# Get Added Public Files () - Returns an array of public files added to a user's tracks.
sub get_added_public_files {
    my $self = shift;
    my $userid = $self->{userid};
    my $uploadsdb = $self->{uploadsdb};
    my $data_source = $self->{data_source};
    my $sql = "SELECT DISTINCT uploads.trackid FROM uploads LEFT JOIN sharing ON uploads.trackid = sharing.trackid WHERE sharing.userid = ? AND uploads.sharing_policy = ? AND sharing.public = 1 AND uploads.data_source = ?";
    my $rows = $uploadsdb->selectcol_arrayref($sql, undef, $userid, "public", $data_source);
    return @$rows;
}

sub match_uploads {
    my $self = shift;
    my ($source,$prefix) = @_;

    my $sql =<<END;
SELECT a.title
  FROM uploads as a,sharing as b
 WHERE a.userid=b.userid
   AND a.sharing_policy='public'
   AND a.title LIKE ?
END
    ;
    my $userid    = $self->{userid};
    $sql .=  "AND a.trackid NOT IN (SELECT trackid FROM sharing WHERE userid=$userid)"
	if $userid;

    my $uploadsdb = $self->{uploadsdb};
    my $search = $uploadsdb->quote($prefix);
    $search =~ s/^'//;
    $search =~ s/'$//;
    $search = "$search%";
    my $select = $uploadsdb->prepare($sql)  or die $uploadsdb->errstr;
    $select->execute($search)  or die $uploadsdb->errstr;
    $prefix = quotemeta($prefix);

    my @results;
    while (my @a = $select->fetchrow_array) {
	warn @a;
	push @results,(grep /^$prefix/i,@a);
    }
    $select->finish;
    return \@results;
}

# Get Shared Files () - Returns an array of files shared specifically to a user.
sub get_shared_files {
    my $self = shift;
    my $userid = $self->{userid};
    my $uploadsdb = $self->{uploadsdb};
    my $data_source = $self->{data_source};
    #Since upload IDs are all the same size, we don't have to worry about one ID repeated inside another so this next line is OK. Still, might be a good idea to secure this somehow?
    my $rows = $uploadsdb->selectcol_arrayref("SELECT DISTINCT uploads.trackid FROM uploads LEFT JOIN sharing ON uploads.trackid = sharing.trackid WHERE sharing.userid = ? AND sharing.public = 0 AND (uploads.sharing_policy = ? OR uploads.sharing_policy = ?) AND uploads.userid <> ? AND uploads.data_source = ? ORDER BY uploads.trackid", undef, $userid, "group", "casual", $userid, $data_source);
    return @$rows;
}

sub share_link {
    my $self = shift;
    my $file = shift or confess "No input or invalid input given to share()";
    my $permissions = $self->permissions($file);
    return $self->share($file) 
	if ($permissions eq "public" || $permissions eq "casual"); # Can't hijack group files with a link, public are OK.
}

# Share (File[, Username OR User ID]) - Adds a public or shared track to a user's session.
sub share {
    my $self = shift;
    my $file = shift or confess "No input or invalid input given to share()";
    my $name_or_id = shift;

    # If we've been passed a user ID, use that. If we've been passed a username, get the ID. 
    # If we haven't been passed anything, use the session user ID.
    my $userid;

    if ($self->{globals}->user_accounts) {
        my $userdb = $self->{userdb};
        $userid = $userdb->get_user_id($name_or_id);
        $self->{userid} ||= $userdb->add_named_session($self->sessionid, "an anonymous user");
    } else {
        $userid = $name_or_id;
    }
    $userid ||= $self->{userid};

    my $sharing_policy = $self->permissions($file);
    # No sense in adding yourself to a group. Also fixes a bug with nonsense users
    # returning your ID and adding yourself instead of nothing.
    # Users can add themselves to the sharing lists of casual or public files; 
    # Owners can add people to group lists but can't force anyone to have a public or casual file.
    return if $self->is_mine($file) and 
	$sharing_policy =~ /(group|casual)/ and 
	$userid eq $self->{userid}; 
    if ((($sharing_policy =~ /(casual|public)/) && 
	 ($userid eq $self->{userid})) || 
	($self->is_mine($file) && ($sharing_policy =~ /group/))) {
        my $public_flag = ($sharing_policy=~ /public/) ? 1 : 0;
        my $uploadsdb = $self->{uploadsdb};

        # Get the current users.
        return if $uploadsdb->selectrow_array("SELECT trackid FROM sharing WHERE trackid = ? AND userid = ? AND public = ?", 
					      undef, $file, $userid, $public_flag);

        # Add the file's tracks to the track lookup hash.
        if ($userid eq $self->{userid}) {
            my %track_lookup = $self->track_lookup;
	    $track_lookup{$_} = $file foreach $self->labels($file);
	} else {
	    $self->email_sharee($file,$userid);
	}
	    
        return $uploadsdb->do("INSERT INTO sharing (trackid, userid, public) VALUES (?, ?, ?)", 
			      undef, $file, $userid, $public_flag);
    } else {
        warn "Share() attempted in an illegal situation on a $sharing_policy file ($file) by user #$userid, a non-owner.";
    }
}

# Unshare (File[, Username OR User ID]) - Removes an added public or shared track from a user's session.
sub unshare {
    my $self = shift;
    my $file = shift or confess "No input or invalid input given to unshare()";
    my $userid = shift || $self->{userid};
    
    # Users can remove themselves from the sharing lists of group, casual or public files; 
    # owners can remove people from casual or group items.
    my $sharing_policy = $self->permissions($file);
    if ((($sharing_policy =~ /(casual|public|group)/) 
	 && ($userid eq $self->{userid})) 
	|| ($self->is_mine($file) && ($sharing_policy =~ /(casual|group)/))) {
        my $public_flag = ($sharing_policy=~ /public/)? 1 : 0;
        my $uploadsdb = $self->{uploadsdb};
        
        # Get the current users.
        return unless $uploadsdb->selectrow_array("SELECT trackid FROM sharing WHERE trackid = ? AND userid = ? AND public = ?", 
						  undef, 
						  $file, $userid, $public_flag);

	# Remove the file's tracks from the track lookup hash.
        if ($userid eq $self->{userid}) {
            my %track_lookup = $self->track_lookup;
        	delete $track_lookup{$_} foreach $self->labels($file);;
	    }
	    
	    return $uploadsdb->do("DELETE FROM sharing WHERE trackid = ? AND userid = ? AND public = ?", undef, $file, $userid, $public_flag);
    } else {
        warn "Unshare() attempted in an illegal situation on a $sharing_policy file ($file) by user #$userid, a non-owner.";
    }
}

sub email_sharee {
    my $self = shift;
    my ($file,$recipient) = @_;
    my $userdb     = $self->userdb;
    my $globals    = $self->globals;

    my $description = $self->description($file);
    my $title       = $self->title($file);
    my $upload_name = $self->filename($file);
    my @labels      = $self->labels($file);
    my ($from_fullname,$from_email) = $userdb->accountinfo_from_username($self->username);
    $from_fullname                ||= $self->username;
    $from_fullname               .= " ($from_email)" if $from_email;
    my ($to_fullname,$to_email)     = $self->userdb->accountinfo_from_username($self->userdb->username_from_userid($recipient));
    return unless $to_email;

    my $gbrowse_link       = $globals->gbrowse_url.'/';
    my $gbrowse_show_link  = $gbrowse_link."?show=".Bio::Graphics::Browser2::Render->join_tracks(\@labels);
    my $gbrowse_readd_link = $gbrowse_link."?share_link=$file";

    my $source   = $self->data_source;

    my $subject  = Bio::Graphics::Browser2::Util->translate('SHARE_GROUP_EMAIL_SUBJECT',$source->description);
    my $contents = Bio::Graphics::Browser2::Util->translate('SHARE_GROUP_EMAIL',
							    $from_fullname,
							    $gbrowse_link,
							    $gbrowse_show_link,
							    $title,
							    $description,
							    join(',',map {$source->setting($_=>'key')||$_} @labels),
							    $gbrowse_readd_link);
    $contents = CGI::unescapeHTML($contents);
    $subject = CGI::unescapeHTML($subject);
    $self->Bio::Graphics::Browser2::SendMail::do_sendmail({
	from       => $globals->email_address,
	from_title => $globals->application_name,
	to         => $to_email,
	subject    => $subject,
	msg        => $contents},$globals);
}

# Field (Field, File ID[, Value]) - Returns (or, if defined, sets to the new value) the specified field of a file.
# This function is dangerous as it has direct access to the database and doesn't do any permissions checks (that's done at the individual field functions like title() and description().
# Make sure you set your permissions at the function level, and never put this into Action.pm or you'll be able to corrupt your database from a URL request!
sub field {
    my $self = shift;
    my $field = shift or return;
    my $file = shift or return;
    my $value = shift;
    my $uploadsdb = $self->{uploadsdb};
    
    if (defined $value) {
        #Clean up the string
        $value =~ s/^\s+//;
        $value =~ s/\s+$//; 
        my $result = $uploadsdb->do("UPDATE uploads SET $field = ? WHERE trackid = ?", undef, $value, $file);
        $self->update_modified($file);
        return $result;
    } else {
        return $uploadsdb->selectrow_array("SELECT $field FROM uploads WHERE trackid = ?", undef, $file);
    }
}

# Update Modified (File ID[, User ID]) - Updates the modification date/time of the specified file to right now.
sub update_modified {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $file = shift or return;
    my $now = $self->nowfun;
    # Do not swap out this line for a field() call, since it's used inside field().
    return $uploadsdb->do("UPDATE uploads SET modification_date = $now WHERE trackid = " . $uploadsdb->quote($file));
}

# Created (File ID) - Returns creation date of $file, cannot be set.
sub created {
    my $self  = shift;
    my $file = shift or return;
    return $self->field("creation_date", $file);
}

# Modified (File ID) - Returns date modified of $file, cannot be set (except by update_modified()).
sub modified {
    my $self  = shift;
    my $file = shift or return;
       return $self->field("modification_date", $file);
}

# Description (File ID[, Value]) - Returns a file's description, or changes the current description if defined.
sub description {
    my $self  = shift;
    my $file = shift or return;
    my $value = shift;
    my $userid = $self->{userid};
    if ($value) {
        if ($self->is_mine($file)) {
            return $self->field("description", $file, $value)
        } else {
            warn "Change Description requested on $file by user #$userid, a non-owner.";
        }
    } else {
        return $self->field("description", $file)
    }
}

# Title (File ID[, Value]) - Returns a file's title, or changes the current title if defined.
sub title {
    my $self  = shift;
    my $file  = shift or return;
    my $value = shift;
    my $userid = $self->{userid};
    if ($value) {
        if ($self->is_mine($file)) {
            return $self->field("title", $file, $value)
        } else {
            warn "Change title requested on $file by user #$userid, a non-owner.";
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
    my $description = shift;
    
    my $userdb = $self->{userdb};
    $self->{userid} ||= $userdb->add_named_session($self->sessionid, "an anonymous user");
    
    my $userid = shift || $self->{userid};
    my $shared = shift || ($self =~ /admin/)? "public" : "private";
    my $data_source = $self->{data_source};
    
    # Add the file's tracks to the track lookup hash.
    my %track_lookup = $self->track_lookup;
	$track_lookup{$_} = $filename foreach $self->labels($filename);
    
    my $fileid = md5_hex($userid.$filename.$data_source);
    my $now = $self->nowfun;
    my $result = $uploadsdb->do("DELETE FROM uploads WHERE trackid='$fileid'");
    $uploadsdb->do("INSERT INTO uploads (trackid, userid, path, description, imported, creation_date, modification_date, sharing_policy, data_source ) VALUES (?, ?, ?, ?, ?, $now, $now, ?, ?)", undef, $fileid, $userid, $filename, $description, $imported, $shared, $data_source);
    return $fileid;
}

# Delete File (File ID) - Deletes $file_id from the database.
sub delete_file {
    my $self = shift;
    my $file = shift or return;

    my $userid = $self->{userid};
    my $uploadsid = $self->uploadsid;
    my $filename = $self->filename($file);
                                 # If the file doesn't exist, don't throw an error, just return.
    if ($self->is_mine($file) || !$filename) {
        if ($filename) {
            # Get this information before the record is deleted from the database.
            my $path = $self->track_path($file);
            my $conf = $self->track_conf($file);
        
            # First delete from the database - better to have a dangling file then a dangling reference to nothing.
            my $uploadsdb = $self->{uploadsdb};
            $uploadsdb->do("DELETE FROM uploads WHERE trackid = ?", undef, $file);
            $uploadsdb->do("DELETE FROM sharing WHERE trackid = ?", undef, $file);
            
            # Remove the file's tracks from the track lookup hash.
            my %track_lookup = $self->track_lookup;
        	delete $track_lookup{$_} foreach $self->labels($filename);
        
            # Now remove the backend database.
            my $loader = Bio::Graphics::Browser2::DataLoader->new($filename,
                                      $path,
                                      $conf,
                                      $self->{config},
                                      $uploadsid);
            $loader->drop_databases($conf);
            
            # Then remove the file if it exists.
            rmtree($path) or warn "Could not delete $path: $!" if -e $path;
        }
    } else {
        warn "Delete of " . $filename . " requested by user #$userid, a non-owner.";
    }
}

# Is Imported (File) - Returns 1 if an already-added track is imported, 0 if not.
sub is_imported {
    my $self = shift;
    my $file = shift or return;
    my $uploadsdb = $self->{uploadsdb};
    return $self->field("imported", $file) || 0;
}

# Permissions (File[, New Permissions]) - Return or change the permissions.
sub permissions {
    my $self = shift;
    my $file = shift or return;
    my $new_permissions = shift;
    if ($new_permissions) {
        my $userid = $self->{userid};
        if ($self->is_mine($file)) {
            my $old_permissions = $self->field("sharing_policy", $file);
            my $result = $self->field("sharing_policy", $file, $new_permissions);
			if ((($old_permissions =~ /(casual|group)/) && ($new_permissions eq "public"))) {
                my @old_users = ($old_permissions eq "public")? $self->shared_with($file) : $self->public_users($file);
                $self->share($file, $_) foreach @old_users;
            }
            $self->share($file, $userid) if $new_permissions =~ /public/; # If we're switching to public permissions, share with the user so it doesn't disappear.
            return $result;
        } else {
            warn "Permissions change on " . $file . "requested by user #$userid a non-owner.";
        }
    } else {
        return $self->field("sharing_policy", $file);
    }
}

# Is Mine (Filename) - Returns 1 if a track is owned by the logged-in (or specified) user, 0 if not.
sub is_mine {
    my $self = shift;
    my $file = shift or return;
    my $owner = $self->owner($file);
    return ($owner eq $self->{userid})? 1 : 0;
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
    my $file = shift or return 0;
    my $userid = $self->{userid};
    my $uploadsdb = $self->{uploadsdb};
    my $results = $uploadsdb->selectcol_arrayref("SELECT trackid FROM sharing WHERE trackid = ? AND userid = ?", undef, $file, $userid);
    return (@$results > 0);
}

# File Type (File ID) - Returns the type of a specified track, in relation to the user.
sub file_type {
    my $self = shift;
    my $file = shift or return;
    return "public" if ($self->permissions($file) =~ /public/);
    if ($self->is_mine($file)) {
        return $self->is_imported($file)? "imported" : "uploaded";
    } else { return "shared" };
}

# Shared With (File ID) - Returns an array of users a track is shared with.
sub shared_with {
    my $self = shift;
    my $file = shift;
    return unless $self->permissions($file) =~ /(casual|group)/;
    return $self->get_users($file, 0);
}

# Public Users (File ID) - Returns an array of users of a public track.
sub public_users {
    my $self = shift;
    my $file = shift;
    return unless $self->permissions($file) =~ /public/;
    return $self->get_users($file, 1);
}

# Public Users (File ID) - Returns an array of users of a public/shared track.
sub get_users {
    my $self = shift;
    my $file = shift;
    my $public = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $usersref = $uploadsdb->selectcol_arrayref("SELECT userid FROM sharing WHERE trackid = ? AND public = ? ORDER BY userid", undef, $file, $public);
    return @$usersref;
}

# Public Users (File ID) - Returns the username of the owner of a track.
sub owner_name {
    my $self = shift;
    my $file = shift;
    my $userdb = $self->{userdb};
    my $owner_id = $self->owner($file);
    return ($owner_id eq $self->{userid})? "you" : $userdb->username_from_userid($owner_id);
}

sub clone_database {
    my $self = shift;
    $self->userdb->clone_database;
    $self->{uploadsdb}{InactiveDestroy} = 1;
    $self->{uploadsdb} = $self->{uploadsdb}->clone
}

1;
