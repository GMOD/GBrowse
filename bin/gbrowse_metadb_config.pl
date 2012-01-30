#!/usr/bin/perl -w
# This script checks the schemas and required fields of the Users Database.
use strict;
use FindBin '$Bin';
use lib "$Bin/../blib/lib";
use Bio::Graphics::Browser2 "open_globals";
use CGI::Session;
use Digest::MD5 qw(md5_hex);
use Getopt::Long;
use GBrowse::ConfigData;
use List::Util;
use File::Spec;
use File::Basename 'dirname','basename';
use File::Path 'rmtree';
use File::Spec;
use POSIX 'strftime';

use constant SCHEMA_VERSION => 4;

# First, collect all the flags - or output the correct usage, if none listed.
my @argv = @ARGV;

my ($dsn, $admin);
GetOptions('dsn=s'         => \$dsn,
           'admin=s'       => \$admin) or die <<EOF;
Usage: $0 [options] <optional path to GBrowse.conf>

Initializes an empty GBrowse user accounts and uploads metadata database.
Options:

   -dsn       Provide a custom DBI connection string, overriding what is
              set in Gbrowse.conf. Note that if there are semicolons in the
              string (like most MySQL connection DSNs will), you WILL have
              to escape it with quotes.
   -admin     Provide an administrator username and password (in the form
              'user:pass') to skip the prompts if the database does not
              exist.

Currently mysql and SQLite databases are supported. When creating a
mysql database you must provide the -admin option to specify a user
and password that has database create privileges on the server.
EOF
    ;

my $www_user       = GBrowse::ConfigData->config('wwwuser');
my ($current_user) = getpwuid($<);

unless ($www_user eq $current_user or $< == 0) {
    print STDERR <<END;
For user account installation to work properly, this script must be able to
create directories owned by the Apache server account ($www_user).
This script will now invoke sudo to become the 'root' user temporarily.
You may be prompted for your login password now.
END
;
    exec 'sudo','-u','root',$0,@argv;
}

my $line_counter  = 0; # controls newlines

# Open the connections.
my $globals = Bio::Graphics::Browser2->open_globals;
$dsn ||= $globals->user_account_db;
if (!$dsn || ($dsn =~ /filesystem|memory/i) || !$globals->user_accounts) {
    print "No need to run database metadata configuration script, filesystem-backend will be used.";
    exit 0;
}

fix_sqlite_permissions()     if $dsn =~ /sqlite/i;
create_mysql_database()      if $dsn =~ /mysql/i;

eval "require DBI" or die "DBI module not installed. Cannot continue.";

my $database = DBI->connect($dsn) 
    or die "Error: Could not open users database, please check your credentials.\n" . DBI->errstr;
my $type = $database->{Driver}->{Name};

my $autoincrement = $type =~ /mysql/i  ? 'auto_increment'
                   :$type =~ /sqlite/i ? 'autoincrement'
                   :'';
my $last_id       = $type =~ /mysql/i  ? 'mysql_insertid'
                   :$type =~ /sqlite/i ? 'last_insert_rowid'
                   :'';

# Database schema. To change the schema, update/add the fields here, and run this script.
my $users_columns = {
    userid      => "integer PRIMARY KEY $autoincrement",
    email       => "varchar(64) not null UNIQUE",
    pass        => "varchar(44) not null",
    gecos       => "varchar(64)",
    remember    => "boolean not null",
    openid_only => "boolean not null",
    confirmed   => "boolean not null",
    cnfrm_code  => "varchar(32) not null",
    last_login  => "timestamp not null",
    created     => "datetime not null"
};

my $session_columns = {
    userid      => "integer PRIMARY KEY $autoincrement",
    username    => "varchar(32)",
    sessionid   => 'char(32) not null UNIQUE',
    uploadsid   => 'char(32) not null UNIQUE',
};

my $openid_columns = {
    userid     => "integer not null",
    openid_url => "varchar(128) PRIMARY KEY"
};

my $uploads_columns = {
    trackid           => "varchar(32) not null PRIMARY key",
    userid            => "integer not null",
    path              => "text",
    title             => "text",
    description       => "text",
    imported          => "boolean not null",
    creation_date     => "datetime not null",
    modification_date => "datetime",
    sharing_policy    => "ENUM('private', 'public', 'group', 'casual') not null",
    public_count      => "int",
    data_source       => "text",
};

my $sharing_columns = {
    trackid => "varchar(32) not null",
    userid  => "integer not null",
    public  => "boolean",
};

my $dbinfo_columns = {
    schema_version    => 'int(10) not null UNIQUE'
};

my $old_users_columns = {
    userid      => "varchar(32) not null UNIQUE PRIMARY KEY",
    uploadsid   => "varchar(32) not null UNIQUE",
    username    => "varchar(32) not null UNIQUE",
    email       => "varchar(64) not null UNIQUE",
    pass        => "varchar(32) not null",
    remember    => "boolean not null",
    openid_only => "boolean not null",
    confirmed   => "boolean not null",
    cnfrm_code  => "varchar(32) not null",
    last_login  => "timestamp not null",
    created     => "datetime not null"
};

my $old_uploads_columns = {
    uploadid          => "varchar(32) not null PRIMARY key",
    userid            => "varchar(32) not null",
    path              => "text",
    title             => "text",
    description       => "text",
    imported          => "boolean not null",
    creation_date     => "datetime not null",
    modification_date => "datetime",
    sharing_policy    => "ENUM('private', 'public', 'group', 'casual') not null",
    users             => "text",
    public_users      => "text",
    public_count      => "int",
    data_source       => "text",
};

upgrade_schema(SCHEMA_VERSION);
check_table("users",            $users_columns);
check_table("session",          $session_columns);
check_table("openid_users",     $openid_columns);
check_table("uploads",          $uploads_columns);
check_table("sharing",          $sharing_columns);

check_sessions();
check_uploads_ids();
check_all_files();
check_data_sources();
fix_sqlite_permissions() if $type =~ /sqlite/i;

$database->disconnect;

print STDERR "Done!\n";

exit 0;


# Check Table (Name, Columns) - Makes sure the named table is there and follows the schema needed.
sub check_table {
    my $name    = shift or die "No table name given, please check the gbrowse_metadb_config.pl script.\n";
    my $columns = shift or die "No table schema given, please check the gbrowse_metadb_config.pl script.\n";
    
    # If the database doesn't exist, create it.
    local $database->{PrintError} = 0;
    unless (eval {$database->do("SELECT * FROM $name LIMIT 1")}) {
        $database->{PrintError} = 1;
        print STDERR ucfirst $name . " table didn't exist, creating...\n";
        my @column_descriptors = map { "$_ " . escape_enums($$columns{$_}) } 
	                         keys %$columns; # This simply outputs %columns as "$key $value, ";
        my $creation_sql = "CREATE TABLE $name (" 
	    . (join ", ", @column_descriptors) . ")" 
	    . (($type =~ /mysql/i)? " ENGINE=InnoDB;" : ";");
        $database->do($creation_sql) or die "Could not create $name database.\n";

    }

    my $sth = $database->prepare("SELECT * from $name LIMIT 1");
    $sth->execute;
    my %existing_columns  = map {$_=>1} @{$sth->{NAME_lc}};
    
    # If an extra column exists, drop it.
    my @columns_to_drop   = grep {!$columns->{$_}} keys %existing_columns;
    if (@columns_to_drop) {
	    print STDERR "Dropping the following columns from $name: ",join(',',@columns_to_drop),".\n";
	    if ($type !~ /sqlite/i) {
	        for my $c (@columns_to_drop) {
	            $database->do("ALTER TABLE $name DROP $c");
	        }
	    }
    }

    # If a required column doesn't exist, add it.
    my @columns_to_create = grep {!$existing_columns{$_}} keys %$columns;
    if (@columns_to_create) {
    print STDERR ucfirst $name . " table schema is incorrect, adding " 
		. @columns_to_create . " missing column" 
		. ((@columns_to_create > 1)? "s." : ".");
        
	# SQLite doesn't support altering to add multiple columns or ENUMS, 
	# so it gets special treatment.
	if ($type =~ /sqlite/i) {
	    # If we don't find a specific column, add its SQL to the columns_to_create array.
	    foreach (@columns_to_create) {
		$$columns{$_} = escape_enums($$columns{$_});
                
		# Now add each column individually
		my $alter_sql = "ALTER TABLE $name ADD COLUMN $_ " . $$columns{$_} . ";";
		$database->do($alter_sql) or die "While adding column $_ to $name: ",
		$database->errstr;
	    }
	} else {
	    @columns_to_create = map { "$_ " . $$columns{$_} } @columns_to_create;
            
	    # Now add all the columns
	    my $alter_sql;
		
	    if ($type =~ /mysql/) {
		$alter_sql .= "ALTER TABLE $name";
		$alter_sql .= " ADD COLUMN " . shift @columns_to_create;
		$alter_sql .= ", ADD COLUMN $_" foreach @columns_to_create;
	        $alter_sql .= ";";
	    } else {
    		$alter_sql = "ALTER TABLE $name ADD (" . (join ", ", @columns_to_create) . ");" ;
	    }
	    $database->do($alter_sql) or die $database->errstr;
	}
    }

    return $database;
}

# iterate through each session and make sure that there is a
# corresponding user in the session table
sub check_sessions {
    my $session_driver = $globals->session_driver;
    my $session_args   = $globals->session_args;
    my $users_updated  = 0;
    local $database->{PrintError} = 0;
    my $do_session_check = sub {
	my $session = shift;
	my $session_id  = $session->id;
	my $source      = $session->param('.source') or return;
	my $config_hash = $session->param($source)   or return;
	my $uploadsid   = $session->param('.uploadsid') ||
	                  $config_hash->{page_settings}{uploadid};
	$uploadsid or return;

	my $sql         = "SELECT count(*) FROM session WHERE sessionid=? AND uploadsid=?";
	my $rows        = $database->selectrow_array($sql,undef,$session_id,$uploadsid);
	return if $rows == 0;
	$sql       = "UPDATE session SET uploadsid=? WHERE sessionid=? AND uploadsid!=?";
	$rows      = $database->do($sql,undef,$uploadsid,$session_id,$uploadsid);
	$users_updated += $rows;
    };
    eval {
	CGI::Session->find($session_driver,$do_session_check,$session_args);
    };
    if ($users_updated) {
	print STDERR "$users_updated users had their session/upload IDs updated.\n";
    }
}


# Check Uploads IDs () - Makes sure every user ID has an uploads ID corresponding to it.
sub check_uploads_ids {
    print STDERR "Checking uploads IDs in database...";
    my $ids_in_db = $database->selectcol_arrayref("SELECT userid, uploadsid FROM session", { Columns=>[1,2] });
    my $missing = 0;
    if ($ids_in_db) {
	my %uploads_ids = @$ids_in_db;
	foreach my $userid (keys %uploads_ids) {
	    unless ($uploads_ids{$userid}) {
		print STDERR "missing uploads ID found.\n" unless $missing;
		print STDERR "- Uploads ID not found for $userid, ";                
		my $session = $globals->session($userid);
		my $settings= $session->page_settings;
		my $uploadsid = $session->param('.uploadsid') ||
		    $settings->{uploadid};
		$database->do("UPDATE session SET uploadsid = ? WHERE sessionid = ?", undef, $uploadsid, $userid) or print STDERR "could not add to database.\n" . DBI->errstr;
		print STDERR "added to database.\n" unless DBI->errstr;
		$missing = 1;
	    }
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
    unless (-e $userdata_folder) {
	print STDERR "No files, no checks needed.\n";
	return;
    }
    my @data_sources;
	opendir U, $userdata_folder;
	while (my $dir = readdir(U)) {
		next if $dir =~ /^\.+$/;
		next unless -d $dir;
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
		    next unless -d $folder;
		    my $user_path = File::Spec->catfile($userdata_folder, $data_source, $folder);
		    opendir USER, $user_path if -d $user_path;
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
		        next unless -d $file;
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
    $line_counter = 0;
    # Get all data sources
    my $userdata_folder = $globals->user_dir;
    unless (-e $userdata_folder) {
	print STDERR "no uploaded files to check.\n";
	return;
    }
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
	    my $userid  = check_uploadsid($source_path,$uploadsid) or next;
            my $this_ok = check_files($userid,$uploadsid, $data_source);
            $all_ok     = $this_ok if $all_ok;
        }
    }
    print STDERR "all files are accounted for.\n" if $all_ok;
}

# remove dangling upload directories
sub check_uploadsid {
    my ($source_path,$uploadsid) = @_;
    return if $uploadsid eq 'shared_remote_tracks';
    my ($userid)  = $database->selectrow_array('select (userid) from session where uploadsid=?',
					       undef,$uploadsid);

    unless ($userid) {
	print STDERR "\n" unless $line_counter++;
	print STDERR "Uploadsid $uploadsid has no corresponding user. Removing.\n";
	rmtree(File::Spec->catfile($source_path,$uploadsid));
	return;
    }
    return $userid;
}

# Check Files (Uploads ID, Data Source) - Makes sure a user's files are in the database, add them if not.
sub check_files {
    my $userid      = shift or die "No user ID given, please check the gbrowse_metadb_config.pl script.\n";
    my $uploadsid   = shift or die "No uploads ID given, please check the gbrowse_metadb_config.pl script.\n";
    my $data_source = shift or die "No data source given, please check the gbrowse_metadb_config.pl script.\n";
    
    # Get the files from the database.
    my $files_in_db = $database->selectcol_arrayref("SELECT path FROM uploads WHERE userid=? AND data_source=?", 
						    undef, $userid, $data_source);
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
	    print STDERR "\n" unless $line_counter++;
	    add_file($file, $userid, $uploadsid, $data_source, $file) &&
		print STDERR "- File \"$file\" found in the \"$data_source/$uploadsid\" folder without metadata, added to database.\n";
	    $all_ok = 0;
	}
    }
    return $all_ok;
}

# Fix Permissions () - Grants the web user the required privileges on all databases.
sub fix_permissions {
    my (undef, $db_name) = $dsn =~ /.*:(database=)?([^;]+)/;
    $db_name ||= "gbrowse_login";
    ($type)    = $dsn =~ /^dbi:([^:]+)/i unless defined $type;

    if ($type =~ /mysql/i) {
	my ($db_user) = $dsn =~ /user=([^;]+)/i;
	my ($db_pass) = $dsn =~ /password=([^;]+)/i;
	$db_pass    ||= '';
	warn "GRANT ALL PRIVILEGES on $db_name.* TO '$db_user'\@'%' IDENTIFIED BY '$db_pass'";
	$database->do("GRANT ALL PRIVILEGES on $db_name.* TO '$db_user'\@'%' IDENTIFIED BY '$db_pass'")
	    or die DBI->errstr;
    }
}

sub fix_sqlite_permissions {
    my (undef, $db_name) = $dsn =~ /.*:(database=)?([^;]+)/;
    $db_name ||= "gbrowse_login";

    my ($path) = $dsn =~ /dbname=([^;]+)/i;
    ($path) = $dsn =~ /DBI:SQLite:([^;]+)/i unless $path;
    die "Couldn't figure out location of database index from $dsn" unless $path;

    my $user    = GBrowse::ConfigData->config('wwwuser');
    my $group   = get_group_from_user($user);

    my $dir = dirname($path);
    unless (-e $dir) {
	my $parent = dirname($dir);
	if (-w $parent) {
	    mkdir $parent;
	} else {
	    print STDERR "Using sudo to create $parent directory. You may be prompted for your login password now.\n";
	    system "sudo mkdir $parent";
	}
    }
    my $file_owner = -e $path ? getpwuid((stat($path))[4]) : '';
    my $dir_owner  = -e $dir  ? getpwuid((stat($dir))[4])  : '';

    # Check if we need to, to avoid unnecessary printing/sudos.
    unless ($group) {
	print STDERR "Unable to look up group for $user. Will not change ownerships on $path.\n";
	print STDERR "You should do this manually to give the Apache web server read/write access to $path.\n";
	return;
    }

    if (-e $path && $user ne $file_owner) {
	print STDERR "Using sudo to set $path ownership to $user:$group. You may be prompted for your login password now.\n";
	system "sudo chown $user $path" ;
	system "sudo chgrp $group $path";
	system "sudo chmod 0644 $path";
    }
    if (-e $dir && $user ne $dir_owner) {
	print STDERR "Using sudo to set $dir ownership to $user:$group. You may be prompted for your login password now.\n";
	system "sudo chown $user $dir";
	system "sudo chgrp $group $dir";
	system "sudo chmod 0755 $dir";
    }
}

# Create Database() - Creates the database specified (or the default gbrowse_login database).
sub create_mysql_database {
    my (undef, $db_name) = $dsn =~ /.*:(database=)?([^;]+)/;
    $db_name ||= "gbrowse_login";
    unless (DBI->connect($dsn)) {
        if ($dsn =~ /mysql/i) {
            print STDERR "Could not log into $db_name database, creating and/or fixing login permissions...\n";
            
            my ($admin_user, $admin_pass);
            if ($admin) {
                ($admin_user) = $admin =~ /^(.*):/;
                ($admin_pass) = $admin =~ /:(.*)$/;
            }
            
            $admin_user ||= prompt("Please enter the MySQL administrator user", "root");
            $admin_pass ||= prompt("Please enter the MySQL administrator password", "",1);

	    my ($db_user) = $dsn =~ /user=([^;]+)/i;
	    my ($db_pass) = $dsn =~ /password=([^;]+)/i;
	    $db_pass    ||= '';

            my $test_dbi = DBI->connect("DBI:mysql:database=mysql;user=$admin_user;password=$admin_pass;");
            $test_dbi->do("CREATE DATABASE IF NOT EXISTS $db_name");
	    $test_dbi->do("GRANT ALL PRIVILEGES on $db_name.* TO '$db_user'\@'%' IDENTIFIED BY '$db_pass'");
	    print STDERR "Database created!\n" unless DBI->errstr;
        }
    }
    # SQLite will create the file/database upon first connection.
}

# Add File (Full Path, Owner's Uploads ID, Data Source) - Adds $file to the database under a specified owner.
# Database.pm's add_file() is dependant too many outside variables, not enough time to re-structure.
sub add_file {    
    my $filename    = shift;
    my $userid      = shift;
    my $uploadsid   = shift;
    my $data_source = shift;
    my $full_path   = shift;

    my $imported = ($filename =~ /^(ftp|http|das)_/)? 1 : 0;
    my $description = "";
    my $shared = "private";

    my $trackid = md5_hex($uploadsid.$filename.$data_source);
    my $now = nowfun();
    $database->do("INSERT INTO uploads (trackid, userid, path, description, imported, creation_date, modification_date, sharing_policy, data_source) VALUES (?, ?, ?, ?, ?, $now, $now, ?, ?)", undef, $trackid, $userid, $filename, $description, $imported, $shared, $data_source);
    return $trackid;
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
  my ($default,$hide) = @_;

  print STDERR "$mess [$default] ";
  my $ans;
  if ($hide) {
      eval {
	  use Term::ReadKey;
	  ReadMode('noecho');
	  $ans = ReadLine(0);
	  ReadMode('normal');
	  print STDERR "\n";
      };
  }
  $ans ||= <STDIN>;
  chomp $ans if defined $ans;

  if (!defined($ans) || !length($ans)) {
      print STDERR "$default\n";
      $ans = $default;
  }
  return $ans;
}

sub get_group_from_user {
    my $user = shift;
    my (undef,undef,undef,$gid) = $user =~ /^\d+$/ ? getpwuid($user) 
                                                   : getpwnam($user);
    $gid or return;
    my $group = getgrgid($gid);
    return $group;
}

sub upgrade_schema {
    my $new_version   = shift;

    # probe whether this is a completely empty database
    {
	local $database->{PrintWarn}  = 0;
	local $database->{PrintError} = 0;
	my ($count) = $database->selectrow_array('select count(*) from users');
	if (!defined $count) {
	    check_table('dbinfo',$dbinfo_columns);
	    set_schema_version('dbinfo',$new_version);
	    return;
	}
    }

    my ($old_version) = $database->selectrow_array('SELECT MAX(schema_version) FROM dbinfo LIMIT 1');
    unless ($old_version) {
	# table is missing, so add it
	check_table('dbinfo',$dbinfo_columns);
	$old_version = 0;
    }
    backup_database() unless $old_version == $new_version;
    for (my $i=$old_version;$i<$new_version;$i++) {
	my $function = "upgrade_from_${i}_to_".($i+1);
	eval "$function();1" or die "Can't upgrade from version $i to version ",$i+1;
    }
    set_schema_version('dbinfo',$new_version);
}

sub backup_database {
    my $temp = File::Spec->tmpdir;
    if ($type =~ /sqlite/i) {
	my ($src) = $dsn =~ /dbname=([^;]+)/i;
	unless ($src) {
	    ($src) = $dsn =~ /DBI:SQLite:([^;]+)/i;
	}
	my $time = localtime;
	my $basename = basename($src);
	my $dest = strftime("$temp/${basename}_%d%b%Y.%H:%M",localtime);
	warn "backing up existing users database to $dest";
	system ('cp',$src,$dest);
    } elsif ($type =~ /mysql/i) {
	my $dest = strftime("$temp/gbrowse_users_%d%b%Y.%H:%M",localtime);
	warn "backing up existing users database to ./$dest";
	my ($src) = $dsn =~ /dbname=([^;]+)/i;
	unless ($src) {
	    (undef, $src) = $dsn =~ /.*:(database=)?([^;]+)/i;
	}
	
	my ($db_user) = $dsn =~ /user=([^;]+)/i;
	my ($db_pass) = $dsn =~ /password=([^;]+)/i;
	$db_pass    ||= '';
	no warnings;
	open SAVEOUT,">&STDOUT";
	open STDOUT,">$dest" or die "$dest: $!";
	system('mysqldump',"--user=$db_user","--password=$db_pass",$src);
	open STDOUT,">&SAVEOUT";
    } else {
	die "Don't know how to backup this driver";
    }
}

sub set_schema_version {
    my ($table,$version) = @_;
    local $database->{AutoCommit} = 0;
    local $database->{RaiseError} = 1;
    eval {
	$database->do("delete from $table");
	$database->do("insert into $table (schema_version) values ($version)");
	$database->commit();
    };
    if ($@) {
	warn "update failed due to $@. Rolling back";
	eval {$database->rollback()};
	die "Can't continue";
    }
}

############################## one function to upgrade each level
sub upgrade_from_0_to_1 {

    # create dbinfo table
    check_table("dbinfo",           $dbinfo_columns);

    local $database->{AutoCommit} = 0;
    local $database->{RaiseError} = 1;
    eval {
	# this upgrades the original users table to the last version
	# before the session table was added
	check_table('users',$old_users_columns);

	# this creates the new session table
	check_table("session",  $session_columns);
	check_table("users_new",        $users_columns);

	# query to pull old data out of original users table
	my $select = $database->prepare(<<END ) or die $database->errstr;
SELECT userid,uploadsid,username,email,pass,remember,openid_only,
       confirmed,cnfrm_code,last_login,created
FROM   users
END
    ;
	
	# query to insert data into new session table
	my $insert_session = $database->prepare(<<END ) or die $database->errstr;
REPLACE INTO session (username,sessionid,uploadsid)
        VALUES (?,?,?)
END
    ;

	# query to insert data into new users table
	my $insert_user = $database->prepare(<<END ) or die $database->errstr;
REPLACE INTO users_new (userid,      email,      pass,       remember, 
		        openid_only, confirmed, cnfrm_code, last_login, created)
        VALUES (?,?,?,?,?,?,?,?,?)
END
;
	$select->execute() or die $database->errstr;
	my %uploadsid_to_userid;

	while (my ($sessionid,$uploadsid,$username,@rest) = $select->fetchrow_array()) {
	    $insert_session->execute($username,$sessionid,$uploadsid)
		or die $database->errstr;
	    my $userid = $database->last_insert_id('','','','') or die "Didn't get an autoincrement ID!";
	    $insert_user->execute($userid,@rest) or die $database->errstr;
	    $uploadsid_to_userid{$uploadsid}=$userid;
	}
	$select->finish;
	$insert_session->finish;
	$insert_user->finish;
	# rename the current users table
	$database->do('drop table users')
	    or die "Couldn't drop old users table";
	$database->do('alter table users_new rename to users')
	    or die "Couldn't rename new users table";
	$database->do('create index index_session on session(username)')
	    or die "Couldn't index sessions table";

	# now do the uploads table
	# this upgrades to latest version 0
	check_table('uploads',      $old_uploads_columns);
	check_table("uploads_new",  $uploads_columns);

	$select = $database->prepare(<<END ) or die $database->errstr;
SELECT uploadid,userid,path,title,description,imported,
       creation_date,modification_date,sharing_policy,users,
       public_users,public_count,data_source
FROM   uploads
END
    ;
	my $insert = $database->prepare(<<END ) or die $database->errstr;
REPLACE INTO uploads_new (trackid,userid,path,title,description,imported,
			 creation_date,modification_date,sharing_policy,users,
			 public_users,public_count,data_source)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
END
    ;
    
    $select->execute();
	while (my ($trackid,$uploadsid,@rest) = $select->fetchrow_array()) {
	    my $uid = $uploadsid_to_userid{$uploadsid};
	    unless ($uid) {
		print STDERR "Found an upload from uploadsid=$uploadsid, but there is no corresponding user. Skipping...\n";
		next;
	    }
	    $insert->execute($trackid,$uid,@rest)
		or die $database->errstr;
	}
	$select->finish();
	$insert->finish();

	$database->do('drop table uploads')
	    or die "Couldn't drop old uploads table";
	$database->do('alter table uploads_new rename to uploads')
	    or die "Couldn't rename new uploads table";

	# now do the openid_users table
	# this creates the new one
	check_table('openid_users', $openid_columns);
	check_table('openid_users_new', $openid_columns);
	$select = $database->prepare(<<END ) or die $database->errstr;
SELECT b.sessionid,a.openid_url,b.userid
  FROM openid_users as a,session as b
 WHERE a.userid=b.userid
END
    ;
	$insert = $database->prepare(<<END ) or die $database->errstr;
REPLACE INTO openid_users_new(userid,openid_url) VALUES (?,?)
END
    ;

	$select->execute() or die $select->errstr;
	while (my ($sessionid,$url,$userid) = $select->fetchrow_array()) {
	    $insert->execute($userid,$url) or die $insert->errstr;
	}

	$select->finish();
	$insert->finish();
	$database->do('drop table openid_users')
	    or die "Couldn't drop old openid_users table: ",$database->errstr;
	$database->do('alter table openid_users_new rename to openid_users')
	    or die "Couldn't rename new openid_users table: ",$database->errstr;

	$database->commit();
    };
    if ($@) {
	warn "upgrade failed due to $@. Rolling back";
	eval {$database->rollback()};
	die "Can't continue";
    } else {
	print STDERR "Successfully upgraded schema from 0 to 1.\n";
    }
}

sub upgrade_from_1_to_2 {
    # Create sharing table.
    check_table("sharing", $sharing_columns);

    local $database->{AutoCommit} = 0;
    local $database->{RaiseError} = 1;
    eval {

	# Upgrade sharing table from 
	my $select = $database->prepare("SELECT trackid, users, public_users FROM uploads") or die $database->errstr;
	$select->execute();
	my $run = 0;
	while (my ($trackid, $users, $public_users) = $select->fetchrow_array()) {
	    my @users = split ", ", $users if $users;
	    my @public_users = split ", ", $public_users if $public_users;
	    
	    $database->do("INSERT INTO sharing (trackid, userid, public) VALUES (?, ?, ?)", undef, $trackid, $_, 0) foreach @users;
	    $database->do("INSERT INTO sharing (trackid, userid, public) VALUES (?, ?, ?)", undef, $trackid, $_, 1) foreach @public_users;
	    $run = 1 if ($users || $public_users);
	}
    
	# Now delete the users & public_users columns from the database.
	check_table("uploads", $uploads_columns);
    
	$select->finish();
	$database->commit() if $run;
    };

    if ($@) {
	warn "upgrade failed due to $@. Rolling back";
	eval {$database->rollback()};
	die "Can't continue";
    } else {
	print STDERR "Successfully upgraded schema from 1 to 2.\n";
    }
}

sub upgrade_from_2_to_3 {
    # add the gecos field
    check_table('users',$users_columns);
}

sub upgrade_from_3_to_4 {
    # change the size of the password table in the users table
    local $database->{AutoCommit} = 0;
    local $database->{RaiseError} = 1;
    eval {
	check_table("users_new",$users_columns);
	my $select = $database->prepare(<<END ) or die $database->errstr;
SELECT userid,email,pass,gecos,remember,openid_only,confirmed,cnfrm_code,last_login,created
FROM   users
END
    ;
    	# query to insert data into new users table
	my $insert = $database->prepare(<<END ) or die $database->errstr;
REPLACE INTO users_new (userid,email,pass,gecos,remember,openid_only,confirmed,cnfrm_code,last_login,created)
        VALUES (?,?,?,?,?,?,?,?,?,?)
END
;
	$select->execute();
	while (my @cols = $select->fetchrow_array) {
	    $insert->execute(@cols);
	}
	$select->finish;
	$insert->finish;
	$database->do('drop table users')
	    or die "Couldn't drop old users table";

	$database->do('alter table users_new rename to users')
	    or die "Couldn't rename new users table";
	$database->commit();
    };
    
    if ($@) {
	warn "upgrade failed due to $@. Rolling back";
	eval {$database->rollback()};
	die "Can't continue";
    } else {
	print STDERR "Successfully upgraded schema from 3 to 4.\n";
    }
}


__END__

