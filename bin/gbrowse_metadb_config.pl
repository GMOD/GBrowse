#!/usr/bin/perl -w
# This script checks the schemas and required fields of the Users Database.
use strict;
use DBI;
use Bio::Graphics::Browser2 "open_globals";
use CGI::Session;
use Digest::MD5 qw(md5_hex);
use Getopt::Long;
use GBrowse::ConfigData;
use List::Util;
use File::Spec;

# First, collect all the flags - or output the correct usage, if none listed.
my ($dsn, $admin, $pprompt, $which_db);
GetOptions('dsn=s'         => \$dsn) or die <<EOF;
Usage: $0 [options] <optional path to GBrowse.conf>

Initializes an empty GBrowse user accounts and uploads metadata database.
Options:

   -dsn       Provide a custom DBI connection string, overriding what is
              set in Gbrowse.conf

Currently mysql and SQLite databases are supported. When creating a
mysql database you must provide the -admin option to specify a user
and password that has database create privileges on the server.

When creating a SQLite database, the script will use the -admin option
to set the user and group ID ownership of the created database in the
format "uid:gid". The web user must have read/write privileges to this
database. The user running this script must have "sudo" privileges for
this to work. Otherwise, you may set the ownership of the SQLite
database file manually after the fact.

Instead of providing the -dsn option, you may provide an optional path
to your installed GBrowse.conf file, in which case the value of
"user_account_db" will be used. If the config path and -dsn options
are both provided, then the latter overrides the former.
EOF
    ;

# Open the connections.
my $globals = Bio::Graphics::Browser2->open_globals;
$dsn ||= $globals->user_account_db;
if (!$dsn || ($dsn =~ /filesystem|memory/i) || !$globals->user_accounts) {
    print "No need to run database metadata configuration script, filesystem-backend will be used.";
    exit 0;
}

my $database = DBI->connect($dsn) or die "Error: Could not open users database, please check your credentials.\n" . DBI->errstr;
my $type = $database->{Driver}->{Name};

# Database schema. To change the schema, update/add the fields here, and run this script.
my $users_columns = {
    userid => "varchar(32) not null PRIMARY key",
    uploadsid => "varchar(32)",
    username => "varchar(32) not null UNIQUE",
    email => "varchar(64) not null UNIQUE",
    pass => "varchar(32) not null",
    remember => "boolean not null",
    openid_only => "boolean not null",
    confirmed => "boolean not null",
    cnfrm_code => "varchar(32) not null",
    last_login => "timestamp not null",
    created => "datetime not null"
};

my $openid_columns = {
    userid => "varchar(32) not null",
    username => "varchar(32) not null",
    openid_url => "varchar(128) not null PRIMARY key"
};

# Database schema. To change the schema, update/add tdatabasehe fields here, and run this script.
my $uploads_columns = {
    uploadid => "varchar(32) not null PRIMARY key",
    userid => "varchar(32) not null",
    path => "text",
    title => "text",
    description => "text",
    imported => "boolean not null",
    creation_date => "datetime not null",
    modification_date => "datetime",
    sharing_policy => "ENUM('private', 'public', 'group', 'casual') not null",
    users => "text",
    public_users => "text",
    public_count => "int",
    data_source => "text",
};

check_table("users", $users_columns);
check_table("openid_users", $openid_columns);
check_table("uploads", $uploads_columns);

fix_permissions();

check_uploads_ids();
check_all_files();
check_data_sources();

$database->disconnect;

print STDERR "Done!\n";

exit 0;


# Check Table (Name, Columns) - Makes sure the named table is there and follows the schema needed.
sub check_table {
    my $name = shift or die "No table name given, please check the gbrowse_metadb_config.pl script.\n";
    my $columns = shift  or die "No table schema given, please check the gbrowse_metadb_config.pl script.\n";
    
    # If the database doesn't exist, create it.
    unless ($database->do("SELECT * FROM $name LIMIT 1")) {
        print STDERR ucfirst $name . " table didn't exist, creating...\n";
        my @column_descriptors = map { "$_ " . escape_enums($$columns{$_}) } keys %$columns; # This simply outputs %columns as "$key $value, ";
        my $creation_sql = "CREATE TABLE $name (" . (join ", ", @column_descriptors) . ")" . (($type =~ /mysql/i)? " ENGINE=InnoDB;" : ";");
        $database->do($creation_sql) or die "Could not create $name database.\n";

    }

    # If a required column doesn't exist, add it.
    my $sth = $database->prepare("SELECT * from $name LIMIT 1");
    $sth->execute;
    if (@{$sth->{NAME_lc}} != keys %$columns) {
        my @columns_to_create;
        my $run = 0;
        
        # SQLite doesn't support altering to add multiple columns or ENUMS, so it gets special treatment.
        if ($type =~ /sqlite/i) {
            # If we don't find a specific column, add its SQL to the columns_to_create array.
            foreach (keys %$columns) {
                $$columns{$_} = escape_enums($$columns{$_});
                
                # Now add each column individually
                unless ((join " ", @{$sth->{NAME_lc}}) =~ /$_/) {
                    my $alter_sql = "ALTER TABLE $name ADD COLUMN $_ " . $$columns{$_} . ";";
                    $database->do($alter_sql);
                }
            }
        } else {
            # If we don't find a specific column, add its SQL to the columns_to_create array.
            foreach (keys %$columns) {
                unless ((join " ", @{$sth->{NAME_lc}}) =~ /$_/) {
                    push @columns_to_create, "$_ " . $$columns{$_};
                    $run++;
                }
            }
            
            # Now add all the columns
            print STDERR ucfirst $name . " table schema is incorrect, adding " . @columns_to_create . " missing column" . ((@columns_to_create > 1)? "s." : ".");
            my $alter_sql .= "ALTER TABLE $name ADD (" . (join ", ", @columns_to_create) . ");";
            
            # Run the creation script.
            if ($run) {
                $database->do($alter_sql);
            }
        }
    }
    return $database;
}

# Check Uploads IDs () - Makes sure every user ID has an uploads ID corresponding to it.
sub check_uploads_ids {
    print STDERR "Checking uploads IDs in database...";
    my $ids_in_db = $database->selectcol_arrayref("SELECT userid, uploadsid FROM users", { Columns=>[1,2] });
    my %uploads_ids = @$ids_in_db;
    my $missing = 0;
    foreach my $userid (keys %uploads_ids) {
        unless ($uploads_ids{$userid}) {
            print STDERR "missing uploads ID found.\n" unless $missing;
            print STDERR "- Uploads ID not found for $userid, ";                
            my $session = CGI::Session->new($globals->session_driver, $userid, $globals->session_args);
            my $uploadsid = $session->param($globals->default_source)->{'page_settings'}->{'uploadid'};
            $database->do("UPDATE users SET uploadsid = ? WHERE userid = ?", undef, $uploadsid, $userid) or print STDERR "could not add to database.\n" . DBI->errstr;
            print STDERR "added to database.\n" unless DBI->errstr;
            $missing = 1;
        }
    }
    print STDERR "all uploads IDs are present.\n" unless $missing;
}

# Check Data Sources () - Checks to make sure the data sources are there for each file.
sub check_data_sources {
    print STDERR "Checking for any files with missing data sources...";
    my $missing = 0;
    
    # Since we can't access the Database.pm access without the data source, we'll have to go in the back door,
    # and manually get the uploads ID, file path, and data source from the userdata folder.
    my $userdata_folder = $globals->user_dir;
    my @data_sources;
	opendir U, $userdata_folder;
	while (my $dir = readdir(U)) {
		next if $dir =~ /^\.+$/;
		push @data_sources, $dir;
	}
	closedir(U);
	
	foreach my $data_source (@data_sources) {
	    # Within each data source, get a list of users with uploaded files.
	    my @users;
	    my $source_path = File::Spec->catfile($userdata_folder, $data_source);
	    opendir DS, $source_path;
	    while (my $folder = readdir(DS)) {
		    next if $folder =~ /^\.+$/;
		    my $user_path = File::Spec->catfile($userdata_folder, $data_source, $folder);
		    opendir USER, $user_path;
		    next unless readdir(USER);
		    push @users, $folder;
		    closedir(USER);
	    }
	    closedir(DS);
	    
	    foreach my $uploadsid (@users) {
	        # For each user, get the list of their files.
	        my @files;
            my $user_path = File::Spec->catfile($userdata_folder, $data_source, $uploadsid);
	        opendir FILE, $user_path;
	        while (my $file = readdir(FILE)) {
		        next if $file =~ /^\.+$/;
		        push @files, $file;
	        }
	        closedir(FILE);
	        
	        # For each file, we have the data source and user - make sure the data source is present.
	        foreach my $file (@files) {
	            my @data_source_in_db = $database->selectrow_array("SELECT data_source FROM uploads WHERE path = ? AND userid = ?", undef, $file, $uploadsid);
	            unless (@data_source_in_db) {
	                print STDERR "missing source found.\n" unless $missing;
                    print STDERR "- Data Source not found for $file (owned by $uploadsid), ";                
                    $database->do("UPDATE uploads SET data_source = ? WHERE path = ? AND userid = ?", undef, $data_source, $file, $uploadsid) or print STDERR "could not add to database.\n" . DBI->errstr;
                    print STDERR "added to database.\n" unless DBI->errstr;
                    $missing = 1;
                }
	        }
	    }
	}
    print STDERR "all data sources are present.\n" unless $missing;
}

# Check All Files () - Checks the integrity of the file data for every user.
sub check_all_files {
    print STDERR "Checking for any files not in the database...";
    # Get all data sources
    my $userdata_folder = $globals->user_dir;
    my @data_sources;
	opendir U, $userdata_folder;
	while (my $dir = readdir(U)) {
		next if $dir =~ /^\.+$/;
		push @data_sources, $dir;
	}
	closedir(U);
	
	my $all_ok = 1;
	foreach my $data_source (@data_sources) {
	    # Within each data source, get a list of users with uploaded files.
	    my @uploads_ids;
	    my $source_path = File::Spec->catfile($userdata_folder, $data_source);
	    opendir DS, $source_path;
	    while (my $folder = readdir(DS)) {
		    next if $folder =~ /^\.+$/;
		    my $user_path = File::Spec->catfile($userdata_folder, $data_source, $folder);
		    opendir USER, $user_path;
		    next unless readdir(USER);
		    push @uploads_ids, $folder;
		    closedir(USER);
	    }
	    closedir(DS);

        foreach my $uploadsid (@uploads_ids) {
            my $this_ok = check_files($uploadsid, $data_source);
            $all_ok = $this_ok if $all_ok;
        }
    }
    print STDERR "all files are accounted for.\n" if $all_ok;
}

# Check Files (Uploads ID, Data Source) - Makes sure a user's files are in the database, add them if not.
sub check_files {
    my $uploadsid = shift or die "No uploads ID given, please check the gbrowse_metadb_config.pl script.\n";
    my $data_source = shift or die "No data source given, please check the gbrowse_metadb_config.pl script.\n";
    
    # Get the files from the database.
    my $files_in_db = $database->selectcol_arrayref("SELECT path FROM uploads WHERE userid = ? AND data_source = ?", undef, $uploadsid, $data_source);
    my @files_in_db = @$files_in_db;
    
    # Get the files in the folder.
    my $path = $globals->user_dir($data_source, $uploadsid);
	my @files_in_folder;
	opendir D, $path;
	while (my $dir = readdir(D)) {
		next if $dir =~ /^\.+$/;
		push @files_in_folder, $dir;
	}
	closedir(D);
	
	my $all_ok = 1;
	foreach my $file (@files_in_folder) {
	    my $found = grep(/$file/, @files_in_db);
	    unless ($found) {
	        print STDERR "missing file(s) found.\n" if $all_ok;
	        add_file($file, $uploadsid, $data_source);
	        print STDERR "- File \"$file\" found in the \"$uploadsid\" folder without metadata, added to database.\n";
	        $all_ok = 0;
	    }
	}
	return $all_ok;
}

# Fix Permissions () - Grants the web user the required privileges on all databases.
sub fix_permissions {
    my (undef, $db_name) = $dsn =~ /.*:(database=)?([^;]+)/;
    $db_name ||= "gbrowse_login";
    
    if ($type =~ /mysql/i) {
	    my ($db_user) = $dsn =~ /user=([^;]+)/i;
	    my ($db_pass) = $dsn =~ /password=([^;]+)/i || ("");
	    $database->do("GRANT ALL PRIVILEGES on $db_name.* TO '$db_user'\@'%' IDENTIFIED BY '$db_pass' WITH GRANT OPTION") or die DBI->errstr;
    }
    if ($type =~ /sqlite/i) {
	    my ($path) = $dsn =~ /dbname=([^;]+)/i;
	    unless ($path) {
	        ($path) = $dsn =~ /DBI:SQLite:([^;]+)/i;
	    }
	    my $user  = GBrowse::ConfigData->config('wwwuser');
	    my $group = get_group_from_user($user);
	    unless ($group) {
	        print STDERR "Unable to look up group for $user. Will not change ownerships on $path.\n";
	        print STDERR "You should do this manually to give the Apache web server read/write access to $path.\n";
	    } else {
	        print STDERR "Using sudo to set ownership to $user:$group. You may be prompted for your login password now.\n";
	        die "Couldn't figure out location of database index from $dsn" unless $path;
	        system "sudo chown $user $path";
	        system "sudo chgrp $group $path";
	        print STDERR "Done.\n";
	    }
    }
}

# Add File (Full Path, Owner's Uploads ID, Data Source) - Adds $file to the database under a specified owner.
# Database.pm's add_file() is dependant too many outside variables, not enough time to re-structure.
sub add_file {    
    my $filename = shift;
    my $imported = ($filename =~ /^(ftp|http|das)_/)? 1 : 0;
    my $description = "";
    my $uploadsid = shift;
    my $shared = "private";
    my $data_source = shift;
    
    warn $data_source;
    
    my $fileid = md5_hex($uploadsid.$filename.$data_source);
    my $now = nowfun();
    $database->do("INSERT INTO uploads (uploadid, userid, path, description, imported, creation_date, modification_date, sharing_policy, data_source) VALUES (?, ?, ?, ?, ?, $now, $now, ?, ?)", undef, $fileid, $uploadsid, $filename, $description, $imported, $shared, $data_source);
    return $fileid;
}

# Now Function - return the database-dependent function for determining current date & time
sub nowfun {
    return ($type =~ /sqlite/i)? "datetime('now','localtime')" : 'NOW()';
}

# Escape Enums (type string) - If the string contains an ENUM, returns a compatible data type that works with SQLite.
sub escape_enums {
    my $string = shift;
    # SQLite doesn't support ENUMs, so convert to a varchar.
    if ($string =~ /^ENUM\(/i) {
        #Check for any suffixes - "NOT NULL" or whatever.
        my @options = ($string =~ m/^ENUM\('(.*)'\)/i);
        my @suffix = ($string =~ m/([^\)]+)$/);
        my @values = split /',\w*'/, $options[0];
        my $length = List::Util::max(map length $_, @values);
        $string = "varchar($length)" . $suffix[0];
    }
    return $string;
}

# Asks q question and sets a default - blatantly stolen (& modified) from Module::Build.
sub prompt {
  my $mess = shift
    or die "prompt() called without a prompt message";

  # use a list to distinguish a default of undef() from no default
  my @def;
  @def = (shift) if @_;
  # use dispdef for output
  my @dispdef = scalar(@def) ?
    ('[', (defined($def[0]) ? $def[0] : ''), '] ') :
    (' ', '');
    
  print STDERR "$mess ", @dispdef;

  my $ans = <STDIN>;
  chomp $ans if defined $ans;

  if ( !defined($ans)        # Ctrl-D or unattended
       or !length($ans) ) {  # User hit return
    print STDERR "$dispdef[1]\n";
    $ans = scalar(@def) ? $def[0] : '';
  }

  return $ans;
}

sub get_group_from_user {
    my $user = shift;
    my (undef,undef,undef,$gid) = getpwnam($user) or return;
    my $group = getgrgid($gid);
    return $group;
}
