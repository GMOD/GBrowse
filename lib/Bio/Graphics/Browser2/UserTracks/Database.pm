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
		uploadsid  => $state->{uploadid},
		globals	  => $globals,
		userdb	  => Bio::Graphics::Browser2::UserDB->new()
    }, ref $class || $class;
}

# Get File ID (Full Path[, userid]) - Returns a file's ID from the database.
sub get_file_id{
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $path = $uploadsdb->quote(shift);
    my $uploadsid = shift // $self->{uploadsid};												#/
    
    my $if_user = $uploadsid ? "userid = " . $uploadsdb->quote($uploadsid) . " AND " : "";
    return $uploadsdb->selectrow_array("SELECT uploadid FROM uploads WHERE " . $if_user . "path = $path");
}

# Get Owned Files () - Returns an array of the paths of files owned by the currently logged-in user.
sub get_owned_files {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $uploadsid = $self->{uploadsid};
    $uploadsid = $uploadsdb->quote($uploadsid);
	my $rows = $uploadsdb->selectcol_arrayref("SELECT path FROM uploads WHERE userid = $uploadsid AND path NOT LIKE '%\$%' ORDER BY uploadid");
	return @{$rows};
}

# Get Public Files () - Returns an array of public or admin file paths.
sub get_public_files {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $rows = $uploadsdb->selectcol_arrayref("SELECT * FROM uploads WHERE sharing_policy = 'public' ORDER BY uploadid");
    return @{$rows};
}

# Get Imported Files () - Returns an array of files imported by a user.
sub get_imported_files {
	my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $uploadsid = $self->{uploadsid};
    $uploadsid = $uploadsdb->quote($uploadsid);
	my $rows = $uploadsdb->selectcol_arrayref("SELECT path FROM uploads WHERE userid = $uploadsid AND path LIKE '%\$%' ORDER BY uploadid");
	return @{$rows};
}

# Field (Field, Path[, Value, User ID]) - Returns (or, if defined, sets to the new value) the specified field of a file.
sub field {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $field = shift;
    my $path = shift;
    my $value = shift;
    my $uploadsid = shift // $self->{uploadsid}; 												#/
    my $fileid = $self->get_file_id($path, $uploadsid);
    
    if ($value) {
	    #Clean up the string
    	$value =~ s/^\s+//;
		$value =~ s/\s+$//; 
    	$value = $uploadsdb->quote($value);
    	my $now = $self->nowfun();
    	my $sql = "UPDATE uploads SET $field = $value WHERE uploadid = '$fileid'";
    	warn $sql;
	    my $result = $uploadsdb->do($sql);
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

# Created (Track) - Returns creation date of $track, cannot be set.
sub created {
    my $self  = shift;
    my $track = shift;
    my $uploadsid = shift // $self->{uploadsid};												#/
    return $self->field("creation_date", $track);
}

# Modified (Track) - Returns date modified of $track, cannot be set (except by update_modified()).
sub modified {
    my $self  = shift;
    my $track = shift;
    my $uploadsid = shift // $self->{uploadsid};												#/
   	return $self->field("modification_date", $track);
}

# Description (Track[, Description, Value, UserID]) - Returns a file's description, or changes the current description if defined.
sub description {
    my $self  = shift;
    my $track = shift;
    my $value = shift;
    my $uploadsid = shift // $self->{uploadsid};												#/
    
    cluck "Args: $track, $uploadsid, $value";
	
	# If we're given a value, add it to the arguments.    
    my @args = ("description", $track);
    push(@args, $value) if ($value);
	return $self->field(@args);
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

# Add File (Full Path[, Description, Sharing Policy, UploadsID]) - Adds $file to the database under $owner.
sub add_file {
    my $self = shift;
    my $uploadsdb = $self->{uploadsdb};
    my $path = shift;
    my $description = $uploadsdb->quote(shift);
    my $uploadsid = shift // $self->{uploadsid};												#/
    my $shared = $uploadsdb->quote(shift // "private");											#/
    
    if ($self->file_exists($path) == 0) {
		my $fileid = md5_hex($uploadsid.$path);
		my $now = $self->nowfun();
		$path = $uploadsdb->quote($path);
		$uploadsid = $uploadsdb->quote($uploadsid);
		$fileid = $uploadsdb->quote($fileid);
		return $uploadsdb->do("INSERT INTO uploads (uploadid, userid, path, description, creation_date, modification_date, sharing_policy) VALUES ($fileid, $uploadsid, $path, $description, $now, $now, $shared)");
    } else {
		warn $self->{session}->{username} . " has already uploaded $path.";
    }
}

# Delete File (Path) - Deletes $file_id from the database.
sub delete_file {
	my $self = shift;
	my $uploadsdb = $self->{uploadsdb};
    my $path = shift;
    my $userid = $self->{userid};
    my $uploadsid = $self->{uploadsid};													#/
    
    # First delete from the database.
    my $fileid = $uploadsdb->quote($self->get_file_id($path, $uploadsid));
    if ($fileid) {
    	return $uploadsdb->do("DELETE FROM uploads WHERE uploadid = $fileid");
    }
    
    # Then remove the file - better to have a dangling file then a dangling reference to nothing.
    my $loader = Bio::Graphics::Browser2::DataLoader->new($path,
							  $self->track_path($path),
							  $self->track_conf($path),
							  $self->{config},
							  $userid);
    $loader->drop_databases($self->track_conf($path));
    rmtree($self->track_path($path));
}

# Now Function - return the database-dependent function for determining current date & time
sub nowfun {
	my $self = shift;
	my $globals = $self->{globals};
	return $globals->user_account_db =~ /sqlite/i ? "datetime('now','localtime')" : 'now()';
}

1;
