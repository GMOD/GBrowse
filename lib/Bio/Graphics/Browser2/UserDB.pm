package Bio::Graphics::Browser2::UserDB;

# $Id: UserDB.pm 23607 2010-07-30 17:34:25Z cnvandev $
use strict;
use Bio::Graphics::Browser2;
use CGI qw(:standard);
use DBI;
use Digest::SHA qw(sha1);
use JSON;
use LWP::UserAgent;
#use LWPx::ParanoidAgent; (Better, but currently broken)
use Net::SMTP;
use Text::ParseWords 'quotewords';
use Digest::MD5 qw(md5_hex);
use Carp qw(confess cluck croak);

use constant HAVE_OPENID => eval "require Net::OpenID::Consumer; 1" || 0;

# SOME CLARIFICATION ON TERMINOLOGY
# "userid"    -- internal dbm ID for a user; a short integer
# "sessionid" -- GBrowse's session ID, a long hexadecimal
# "uploadsid"  -- GBrowse's upload ID, a long hexadecimal

sub new {
  my $class   = shift;
  my $globals = shift;
  my $VERSION = '0.5';
  my $credentials  = $globals->user_account_db 
      || "DBI:mysql:gbrowse_login;user=gbrowse;password=gbrowse";
  
  my $login = DBI->connect($credentials);
  unless ($login) {
    print header();
    print "Error: Could not open login database. Please ensure your credentials are present and working in the GBrowse.conf file.";
    confess "Could not open login database $credentials";
  }
  
  my $self = bless {
      dbi => $login,
      globals => $globals,
      openid => HAVE_OPENID,
  }, ref $class || $class;

  return $self;
}

sub globals {shift->{globals} };
sub dbi     {shift->{dbi}     };
sub openid  {shift->{openid}  };

# Get Header - Returns the message found at the top of all confirmation e-mails.
sub get_header {
  my $self = shift;
  my $globals = $self->{globals};
  my $message  = "\nThank you for creating an account with " 
      . $globals->application_name 
      . ": " 
      . $globals->application_name_long . "\n\n";
  $message .= "The account information found below is for your reference only. ";
  $message .= "Please keep all account names and passwords in a safe location ";
  $message .= "and do not share your password with others.";
  return $message;
}

# Get Footer - Returns the message found at the bottom of all e-mails.
sub get_footer {
  my $self = shift;
  my $globals = $self->{globals};
  my $message  = "Courtesy of " . $globals->application_name . " Administration\n\n";
     $message .= "This message and any attachments may contain confidential and/or ";
     $message .= "privileged information for the sole use of the intended recipient. ";
     $message .= "Any review or distribution by anyone other than the person for whom ";
     $message .= "it was originally intended is strictly prohibited. If you have ";
     $message .= "received this message in error, please contact the sender and delete ";
     $message .= "all copies. Opinions, conclusions or other information contained in ";
     $message .= "this message may not be that of the organization.";
  return $message;
}

# Create Key - Generates a random string of a given length.
sub create_key {
  my $self = shift;
  my $val = shift;
  my $key;
  my @char=('a'..'z','A'..'Z','0'..'9','_');
  foreach (1..$val) {$key.=$char[rand @char];}
  return $key;
}

# Check E-mail - Returns true if an e-mail is in a valid format.
sub check_email {
  my $self = shift;
  if(shift =~ m/^(\w|\-|\_|\&|\+|\.)+\@((\w|\-|\_)+\.)+[a-zA-Z]{2,}$/) {
    return 1;
  } else {
    return 0;
  }
}

# Check User - Returns true if a username is in a valid format.
sub check_user {
  my $self = shift;
  if(shift =~ m/^([!-\[]|[\]-~])+$/) {
    return 1;
  } else {
    return 0;
  }
}

#Check Admin - Returns true if a user is an admin.
sub check_admin {
  my $self = shift;
  my $username = shift;
  my $globals = $self->{globals};
  my $admin_name = $globals->admin_account;
  return unless $admin_name;
  return $username eq $admin_name;
}

# Check Old Confirmations - Deletes any unconfirmed accounts more than 7 days old.
sub check_old_confirmations {
  my $self = shift;
  my $nowfun = $self->nowfun();
  my $userdb = $self->{dbi};
  
  my $delete = $userdb->prepare(
    "DELETE FROM users WHERE confirmed=0 AND ($nowfun - last_login) >= 7000000");
  $delete->execute()
    or (print "Error: ",DBI->errstr,"." and die "Error: ",DBI->errstr);
  return;
}

# Now Function - return the database-dependent function for determining current date & time
sub nowfun {
  my $self = shift;
  my $globals = $self->{globals};
  return $globals->user_account_db =~ /sqlite/i ? "datetime('now','localtime')" : 'now()';
}

# Do Sendmail - Handles outgoing email using either Net::SMTP or Net::SMTP::SSL as required.
# The format of the smtp argument is:
#
#      smtp.server.com:port:encryption:username:password
#
# This has up to five fields. Only the first field is required.
# The port is assumed to be 25 unless ssl encryption is specified, in which case it defaults to 465.
# The protocol is either "plain" or "ssl", "plain" assumed.
# The username and password may be required by the SMTP server to send outgoing mail.
sub do_sendmail {
  my $self = shift;
  my $args = shift;
  my $globals = $self->{globals};

  eval {
	  $globals->smtp or die "No SMTP server found in globals";

	  my ($server, $port, $protocol, $username, $password) = split ':', $globals->smtp;
	  $protocol ||= 'plain';
	  $port     ||= $protocol eq 'plain' ? 25 : 465;
	  $protocol =~ /plain|ssl/ or die 'encryption must be either "plain" or "ssl"';
	
	  # At least some SMTP servers will refuse to accept mail
	  # unless From matches the authentication username.
	  my $smtp_from   = $username ? $username : $args->{from};

	  my $smtp_sender;
	  if ($protocol eq 'plain') {
      eval "require Net::SMTP" unless Net::SMTP->can('new');
      $smtp_sender = 'Net::SMTP';
	  } else {
      eval "require Net::SMTP::SSL" unless Net::SMTP::SSL->can('new');
      $smtp_sender = 'Net::SMTP::SSL';
	  }

	  my $smtp_obj = $smtp_sender->new(
	    $server,
      Port    => $port,
      Debug  => 0,
    )
    or die "Could not connect to outgoing mail server $server";

	  if ($username) {
      $smtp_obj->auth($username, $password) 
		  or die "Could not authenticate with outgoing mail server $server"
	  }

	  $smtp_obj->mail("$smtp_from\n")                    or die $smtp_obj->message;
	  $smtp_obj->to("$args->{to}\n")                     or die $smtp_obj->message;
	  $smtp_obj->data()                                  or die $smtp_obj->message;
	  $smtp_obj->datasend("From: \"$args->{from_title}\" <$args->{from}>\n")
	                                                     or die $smtp_obj->message;
	  $smtp_obj->datasend("To: $args->{to}\n")           or die $smtp_obj->message;
	  $smtp_obj->datasend("Reply-to: $args->{from}\n")   or die $smtp_obj->message;
	  $smtp_obj->datasend("Subject: $args->{subject}\n") or die $smtp_obj->message;
	  $smtp_obj->datasend("\n")                          or die $smtp_obj->message;
	  $smtp_obj->datasend($args->{msg})                  or die $smtp_obj->message;
	  $smtp_obj->datasend("\n")                          or die $smtp_obj->message;
	  $smtp_obj->dataend()                               or die $smtp_obj->message;
	  $smtp_obj->quit();
  };
  return (0, $@) if $@;
  return (1,'');
}

#################### N O N - O P E N I D   F U N C T I O N S #####################
# Get User ID (User) - Returns a confirmed user's ID
sub get_user_id {
    my $self = shift;
    my $search = shift;
    return $self->userid_from_username($search) || $self->userid_from_email($search);
}


sub userid_from_username {
    my $self     = shift;
    my $username = shift;

    my $userdb = $self->{dbi};
    my $user_id = 
	$userdb->selectrow_array(<<END,undef,$username);
SELECT userid
  FROM session as a
  WHERE a.username=?
  LIMIT 1
END
}

sub userid_from_email {
    my $self     = shift;
    my $email = shift;

    my $userdb = $self->{dbi};
    my $user_id = 
	$userdb->selectrow_array(<<END,undef,$email);
SELECT userid
  FROM users as a
  WHERE a.email=?
  LIMIT 1
END
}

sub userid_from_uploadsid {
    my $self      = shift;
    my $uploadsid = shift;

    my $userdb = $self->{dbi};
    my $user_id = 
	$userdb->selectrow_array(<<END,undef,$uploadsid);
SELECT userid
  FROM session as a
  WHERE a.uploadsid=?
  LIMIT 1
END
}

# Get Uploads ID (User ID) - Returns a user's Uploads ID.
sub get_uploads_id {
    my $self = shift;
    my $userid = shift;
    my $userdb = $self->{dbi};
    return $userdb->selectrow_array("SELECT uploadsid FROM session WHERE userid=?",
				    undef,$userid);
}

sub get_sessionid {
    my $self = shift;
    my $userid = shift;
    my $userdb = $self->{dbi};
    return $userdb->selectrow_array("SELECT sessionid FROM session WHERE userid=?",
				    undef,$userid);
}

# Get Username (User ID) - Returns a user's username, given their ID.
sub get_username {
    croak "you probably want to call username_from_sessionid";
}

sub username_from_sessionid {
    my $self = shift;
    my $sessionid = shift;
    my $userdb = $self->{dbi};

    return $userdb->selectrow_array(<<END,undef,$sessionid)||'an anonymous user';
SELECT username FROM session
 WHERE sessionid=?
END
}

sub userid_from_sessionid {
    my $self = shift;
    my $sessionid = shift;
    my $userdb = $self->{dbi};

    return $userdb->selectrow_array(<<END,undef,$sessionid);
SELECT userid FROM session
 WHERE sessionid=?
END
}

# Check Uploads ID (User ID, Uploads ID) - Makes sure a user's ID is in the database.
sub check_uploads_id {
    my $self = shift;
    croak "check_uploads_id() should no longer be necessary";
    my ($sessionid,$uploadsid) = @_;
    my $userdb = $self->{dbi};

    my $rows = $userdb->selectrow_array(<<END,undef,$sessionid,$uploadsid);
SELECT count(*) FROM session
   WHERE sessionid=? and uploadsid=?
END
    unless ($rows) {
        $userdb->do(<<END,undef,$sessionid,$uploadsid);
INSERT INTO session (sessionid,uploadsid)
     VALUES (?,?)
END
;
    }
    return $uploadsid;
}

# Change IDs (New User ID, New Uploads ID) - Changes the current user's user ID stored in the database to something new, in case the session expires.
sub change_ids {
    my $self = shift;
    my $old_uploadsid = shift;
    my $new_uploadsid = shift;
    my $old_userid = shift;
    my $new_userid = shift;
    $self->change_userid($old_userid, $new_userid);
    $self->change_uploadsid($old_uploadsid, $new_uploadsid);
}

# Change User ID (Old User ID, New User ID) - Changes the current user's user ID stored in the database to something new, in case the session expires.
sub change_userid {
    my $self = shift;
    my $old_userid = shift;
    my $new_userid = shift;
    my $userdb = $self->{dbi};
    $userdb->do("UPDATE users SET userid = ? WHERE userid = ?", undef, $new_userid, $old_userid);
    $userdb->do("UPDATE openid_users SET userid = ? WHERE userid = ?", undef, $new_userid, $old_userid);
}

# Change Uploads ID (Old Uploads ID, New Uploads ID) - Changes the current user's stored uploads ID to something new, in case the session expires.
sub change_uploadsid {
    my $self = shift;
    my $old_uploadsid = shift;
    my $new_uploadsid = shift;
    my $userdb = $self->{dbi};
    my $uploadsid_indb = $userdb->selectrow_array("SELECT uploadsid FROM users WHERE userid = ? LIMIT 1");
    $userdb->do("UPDATE users SET uploadsid = ? WHERE uploadsid = ?", undef, $new_uploadsid, $old_uploadsid);
}

sub add_named_session {
    my $self = shift;
    my ($sessionid,$username) = @_;

    my $userdb  = $self->dbi;

    my $session = $self->globals->session($sessionid);
    $session->id eq $sessionid or die "Sessionid unavailable";
    my $uploadsid = $session->uploadsid;

    my $insert_session  = $userdb->prepare(<<END);
REPLACE INTO session (username,sessionid,uploadsid)
     VALUES (?,?,?)
END
    ;
    
    $insert_session->execute($username,$sessionid,$uploadsid)
	or return;
    return $userdb->last_insert_id('','','','');
}

#####################################
# BUG!
# Everything below here supports the
# login.js script, which expects return
# values as various combinations of
# strings and JSON structures.
# This means API is strongly tied
# to database queries.
#####################################

# Validate - Ensures that a non-openid user's credentials are correct.
sub do_validate {
  my $self = shift;
  my ($user,$pass,$remember) = @_;
  
  my $userdb = $self->{dbi};
  my $update;

  if($self->check_user($user)==0) {
    print "Usernames cannot contain any backslashes, whitespace or non-ascii characters.";
    return;
  }

  my $userid = $self->userid_from_username($user);
  my $nowfun = $self->nowfun();
  if($remember != 2) {
    $update = $userdb->prepare(
      "UPDATE users SET last_login=$nowfun,remember=$remember WHERE userid=? AND pass=? AND confirmed=1");
  } else {
    $update = $userdb->prepare(
      "UPDATE users SET last_login=$nowfun WHERE userid=? AND pass=? AND confirmed=1");
  }

  # BUG: we should salt the password
  $pass = sha1($pass);
  $update->execute($userid,$pass)
    or (print "Error: ", DBI->errstr, "." and die "Error: ", DBI->errstr);

  my $rows = $update->rows;
  if($rows == 1) {
    $self->check_old_confirmations();
    if($remember != 2) {
      my $select = $userdb->prepare(
        "SELECT sessionid FROM users as a,session as b WHERE a.userid=b.userid and a.userid=? AND pass=? AND confirmed=1");
      $select->execute($userid,$pass)
        or (print "Error: ",DBI->errstr,"." and die "Error: ",DBI->errstr);
      # BUG: this is truly nasty -- the session id is found by string searching
      # in login.js!!!!
      my $result = "session".$select->fetchrow_array;
      print $result;
    } else {
      print "Success";
    }
  } elsif($rows == 0) {
    print "Invalid username or password provided, please try again.";
  } else {
    print "Error: $rows rows returned, please consult your service host.";
  }
  return;
}

# Add User Check - Checks to see if the user has already been added.
sub do_add_user_check {
  my $self = shift;
  my ($user,$email,$pass,$userid) = @_;
  
  my $userdb = $self->{dbi};
  
  if($self->check_email($email)==0) {print "Invalid e-mail address (" . $email . ") provided.";return;}
  if($self->check_user($user)==0) {
    print "Usernames cannot contain any backslashes, whitespace or non-ascii characters.";return;
  }

  my $select = $userdb->prepare(
    "SELECT confirmed FROM users WHERE email=?");
  $select->execute($email)
    or (print "Error: ",DBI->errstr,"." and die "Error: ",DBI->errstr);

  my $confirmed = $select->fetchrow_array;
  if($select->rows == 0) {
    $self->do_add_user($user,$email,$pass,$userid);
  } elsif($confirmed == 1) {
    print "E-mail in use";
  } elsif($confirmed == 0) {
    print "Message Already Sent";
  }
  return;
}

# Add User - Adds a new non-openid user to the user database.
sub do_add_user {
  my $self = shift;
  my ($user,$email,$pass,$sessionid) = @_;
  
  my $userdb = $self->dbi;
  
  if($self->check_email($email)==0) {print "Invalid e-mail address provided.";return;}
  if($self->check_user($user)==0) {
    print "Usernames cannot contain any backslashes, whitespace or non-ascii characters.";
    return;
  }
  if($self->check_admin($user)) {
    print "Invalid username. Try a different one."; 
    return;
  }

  # see if this username is already taken
  if ($self->userid_from_username($user)) {
      	print "Username already in use, please try another.";
	return;
  }

  my $confirm = $self->create_key('32');
  my $nowfun = $self->nowfun();

  local $userdb->{AutoCommit} = 0;
  local $userdb->{RaiseError} = 1;
  eval {
      my $userid = $self->add_named_session($sessionid,$user) 
	  or die "Couldn't add named session: ",$userdb->errstr;

      my $insert_userinfo = $userdb->prepare (<<END);
INSERT INTO users (userid, email, pass, remember, openid_only, 
		   confirmed, cnfrm_code, last_login, created)
     VALUES (?,?,?,0,0,0,?,$nowfun,$nowfun)
END
;
      $pass = sha1($pass);
      $insert_userinfo->execute($userid,$email,$pass,$confirm)
	  or die "Couldn't insert information on user: ",$userdb->errstr;
      $userdb->commit();
  };
  if ($@) {
      warn "user account insertion failed due to $@. Rolling back.";
      eval {$userdb->rollback()};
      if(DBI->errstr =~ m/for key 1$/      || DBI->errstr =~ m/username is not unique/) {
	  print "Username already in use, please try another.";
      } elsif(DBI->errstr =~ m/for key 2$/ || DBI->errstr =~ m/email is not unique/) {
	  print "E-mail address already in use, please provide another.";
      } elsif(DBI->errstr =~ m/for key 3$/ || DBI->errstr =~ m/userid is not unique/) {
	  print "Session Error";
      } else {
	  print "Error: ", DBI->errstr, ".";
      }
  }
  
  else {
      $self->do_send_confirmation($email,$confirm,$user,$pass);
      print "Success";
  }

  return;
}

# Send Confirmation - Sends an e-mail when a user creates a new non-openid account to ensure that the user is valid and the e-mail exists.
sub do_send_confirmation {
  my $self = shift;
  my ($email,$confirm,$user,$pass) = @_;
  my $globals = $self->{globals};
  my $link = $globals->gbrowse_url()."?confirm=1;code=$confirm";

  my $message  = $self->get_header();
     $message .= "\n\n    Username: $user\n    Password: $pass\n    E-mail:   $email\n\n";
     $message .= "To activate your account and complete the sign up process, please click ";
     $message .= "on the following link:\n    $link\n\n\n";
     $message .= $self->get_footer();

  my ($status,$err) = $self->do_sendmail({
     from       => $globals->email_address,
     from_title => $globals->application_name,
     to         => $email,
     subject    => $globals->application_name . " Account Activation",
     msg        => $message
  });
  unless ($status) {
    print $err;
    die   "Error while sending outgoing email: $err";
  }
  return;
}

# Edit Confirmation - Deletes or resends unconfirmed information based on "option"
sub do_edit_confirmation {
  my $self = shift;
  my ($email,$option) = @_;
  
  my $userdb = $self->{dbi};

  my $select = $userdb->prepare(<<END);
SELECT b.username, a.userid,b.sessionid 
    FROM users as a,session as b 
    WHERE a.email=? AND a.userid=b.userid
END
  $select->execute($email)
    or (print "Error: ",DBI->errstr,"." and die "Error: ",DBI->errstr);
  my ($user,$userid,$sessionid) = $select->fetchrow_array();

  my $delete = $userdb->prepare(
    "DELETE FROM users WHERE userid=?");
  $delete->execute($userid)
    or (print "Error: ",DBI->errstr,"." and die "Error: ",DBI->errstr);
  my $delete2 = $userdb->prepare(
    "DELETE FROM openid_users WHERE userid=?");
  $delete2->execute($userid)
    or (print "Error: ",DBI->errstr,"." and die "Error: ",DBI->errstr);

  if ($option == 1) {
    my $pass = $self->create_key('23');
    $self->do_add_user($user,$email,$pass,$sessionid);
  } else {
    print "Your account has been successfully removed.";
  }
  return;
}

# Confirm Account - Activates a new account when the user follows the mailed link.
sub do_confirm_account {
  my $self = shift;
  my ($user,$confirm) = @_;
  my $userdb = $self->{dbi};

  # BUG: we should salt the password
  my $new_confirm = sha1($confirm);

  my ($rows) = $userdb->selectrow_array(
    "SELECT count(*) FROM users WHERE cnfrm_code=? AND confirmed=0",
    undef,
    $confirm);
  if($rows != 1) {print "Already Active"; return;}

  my $userid = $self->userid_from_username($user);

  my $update = $userdb->prepare(
    "UPDATE users SET confirmed=1,cnfrm_code=? WHERE userid=? AND cnfrm_code=? AND confirmed=0");
  $update->execute($new_confirm,$userid,$confirm)
    or (print "Error: ",DBI->errstr,"." and die "Error: ",DBI->errstr);
  $rows = $update->rows;
  if($rows == 1) {
    my $query = $userdb->prepare(
      "SELECT b.sessionid FROM users as a,session as b WHERE b.username=? AND a.userid=b.userid AND cnfrm_code=? AND confirmed=1");
    $query->execute($user,$new_confirm)
      or (print "Error: ",DBI->errstr,"." and die "Error: ",DBI->errstr);
    print $query->fetchrow_array();
  } elsif($rows == 0) {
    print "Error: Incorrect username provided, please check your spelling and try again.";
  } else {
    print "Error: $rows rows returned, please consult your service host.";
  }
  return;
}

# Edit Details - Updates the user's e-mail or password depending on the "column"
sub do_edit_details {
  my $self = shift;
  my ($user,$column,$old,$new) = @_;
  my $userdb = $self->{dbi};

  if($column eq 'email') {
    if($self->check_email($new) == 0) {
      print "New e-mail address is invalid, please try another.";return;}
  }

  # BUG: we should salt the password
  $old = sha1($old) if($column eq 'pass');
  $new = sha1($new) if($column eq 'pass');

  my $querystring  = "UPDATE users       ";
     $querystring .= "   SET $column  = ?";
     $querystring .= " WHERE userid   = ?";
     $querystring .= "   AND $column  = ?";

  my $update = $userdb->prepare($querystring);
  my $userid = $self->userid_from_username($user);
  unless($update->execute($new,$userid,$old)) {
    if($column eq 'email') {
      print "New e-mail already in use, please try another.";
      die "Error: ",DBI->errstr;
    } else {
      print "Error: ",DBI->errstr,".";
      die "Error: ",DBI->errstr;
    }
  }

  if(DBI->errstr =~ m/for key 3$/) {
    print "New e-mail already in use, please try another.";}

  my $rows = $update->rows;
  if($rows == 1) {
    print "Success";
  } elsif($rows == 0) {
    print "Incorrect password provided, please check your spelling." if($column eq 'pass');
    print "Incorrect e-mail provided, please check your spelling."   if($column eq 'email');
  } else {
    if(($column eq 'email') and ($rows == -1)) {
      print "New e-mail already in use, please try another.";
    } else {
      print "Error: $rows rows returned, please consult your service host.";
    }
  }
  return;
}

# E-mail Info - Sends an e-mail when a user has forgotten their password.
sub do_email_info {
  my $self = shift;
  my $email = shift;
  my $globals = $self->{globals};
  my $userdb = $self->{dbi};
  
  if($self->check_email($email)==0) {print "Invalid e-mail address provided.";return;}

  my ($user,$rows,$openid_ref) = $self->do_retrieve_user($email);
  my @openids = @$openid_ref;
  my $openid  = "";
  
  if($rows != 1) {print $user; return;}

  if(@openids) {foreach(@openids) {$openid .= "$_\n             ";}}
  else {$openid = "None\n";}

  my $pass = $self->create_key('23');
  my $message  = "\nYour password has been reset to the one seen below. To fix this,";
     $message .= " select \"My Account\" from the log in menu and log in with the";
     $message .= " credentials found below.\n\n    Username: $user\n    ";
     $message .= "Password: $pass\n\n    OpenIDs: $openid\n\n";
     $message .= $self->get_footer();

  my ($status,$err) = $self->do_sendmail({
			     from       => $globals->email_address,
			     from_title => $globals->application_name,
			     to         => $email,
			     subject    => $globals->application_name . " Account Information",
			     msg        => $message
			    });

  if(!$status) {
    print "Error: ",$err;
    die "Error while sending outgoing email: ",$err;
  }

  # BUG: we should salt the password
  my $secret = sha1($pass);
  my $update = $userdb->prepare(
    "UPDATE users SET pass=? WHERE userid=? AND email=? AND confirmed=1");
  my $userid = $self->userid_from_username($user);
  $update->execute($secret,$userid,$email)
    or (print "Error: ",DBI->errstr,"." and die "Error: ",DBI->errstr);

  print "Success";
  return;
}

# Retrieve User - Gets the username associated with a given e-mail.
sub do_retrieve_user {
  my $self = shift;
  my $email = shift;
  
  my $userdb = $self->{dbi};
  
  my @openids;

  my $users = $userdb->selectcol_arrayref(
    "SELECT username FROM users as a,session as b WHERE a.userid=b.userid AND email=? AND confirmed=1",
  	undef,
  	$email)
  or (print "Error: ",DBI->errstr,"." and die "Error: ",DBI->errstr);

  my $rows = @$users;
  if ($rows == 1) {
    my $user  = $users->[0];
    my $query = $userdb->prepare(
      "SELECT openid_url FROM openid_users WHERE username=?");
    $query->execute($user)
      or (print "Error: ",DBI->errstr,"." and die "Error: ",DBI->errstr);

    while (my $openid = $query->fetchrow_array) {
      push (@openids,$openid);
    }

    return ($user,$rows,\@openids);
  } elsif($rows == 0) {
    return ("Sorry, an account does not exist for the e-mail provided.",$rows,\@openids);
  } else {
    return ("Error: $rows accounts match your e-mail, please consult your service host.",$rows,\@openids);
  }
}

# Delete User - Removes a user from the database.
sub do_delete_user {
  my $self = shift;
  my ($user, $pass) = @_;
  
  my $userdb = $self->{dbi};
  my $unseqpass = $pass;

  # BUG we should salt the password
  $pass = sha1($pass);
  my $userid = $self->userid_from_username($user);
  unless ($userid) {
      print "Error: unknown user $user";
      return;
  }

  my $sessionid = $self->get_sessionid($userid);
  $userdb->do('DELETE FROM session where userid=?',undef,$userid);
  my $session = $self->globals->session($sessionid);
  $session->delete;
  $session->flush;

  $userdb->do('DELETE FROM users WHERE userid=?',undef,$userid);

  my $query = $userdb->prepare(
    "DELETE FROM openid_users WHERE username=?");
  if ($query->execute($user)) {
    print "Success";
  } else {
    print "Error: ",DBI->errstr,".";
  }
  return;
}

######################## O P E N I D   F U N C T I O N S #########################
# Check OpenID - Sends a user to their openid host for confirmation.

# BUG: ALL THE OPENID FUNCTIONS NEED TO BE REVISED
sub do_check_openid {
    my $self = shift;
    my $globals = $self->{globals};
    my ($openid, $sessionid, $option) = @_;
    warn "do_check_openid($openid,$sessionid,$option)";
    my $return_to  = $globals->gbrowse_url()."?openid_confirm=1;page=$option;s=$sessionid;";
       $return_to .= "id=logout;" if $option ne "openid-add";
       #id=logout needed in case another user is already signed in
    
    my $csr = Net::OpenID::Consumer->new(
        ua              => LWP::UserAgent->new,
        args            => CGI->new,
        consumer_secret => Bio::Graphics::Browser2->openid_secret,
        required_root   => "http://$ENV{'HTTP_HOST'}/"
    );

    my $claimed_identity = $csr->claimed_identity($openid)
        or print "The URL provided is not a valid OpenID, please check your spelling and try again."
        and die $csr->err;

    my $check_url = $claimed_identity->check_url(
        return_to  => $return_to,
        trust_root => "http://$ENV{'HTTP_HOST'}/",
        delayed_return => 1
    );

    print "Location: $check_url";
    return;
}

# Confirm OpenID - Checks that the returned credentials are valid.
sub do_confirm_openid {
    my $self = shift;
    my ($callback, $sessionid, $option) = @_;
    warn "do_confirm_openid($callback,$sessionid,$option)";
    
    my $userdb = $self->{dbi};
    
    my ($error, @results, $select, $user, $only);

    my $csr = Net::OpenID::Consumer->new(
        ua              => LWP::UserAgent->new,
        args            => $callback,
        consumer_secret => Bio::Graphics::Browser2->openid_secret,
        required_root   => "http://$ENV{'HTTP_HOST'}/"
    );

    if ($option eq "openid-add") {
        ($user, $only) = $userdb->selectrow_array(
	    "SELECT b.username,a.openid_only FROM users as a,session as b WHERE b.sessionid=? AND a.userid=b.userid",
	    undef,
	    $sessionid)
            or ($error = DBI->errstr and push @results,{error=>"Error: $error."}
		and print JSON::to_json(\@results) and return);
	warn "user=$user";
        unless (defined $user) {
            push @results,{error=>"Error: Wrong session ID provided, please try again."};
            print JSON::to_json(\@results);
            return;
        }
    }

    $csr->handle_server_response(
        not_openid => sub {
            push @results,{user=>$user,only=>$only,error=>"Invalid OpenID provided, please check your spelling."};
            print JSON::to_json(\@results);
        },
        setup_required => sub {
            push @results,{user=>$user,only=>$only,error=>"Error: Your OpenID requires setup."};
            print JSON::to_json(\@results);
        },
        cancelled => sub {
            push @results,{user=>$user,only=>$only,error=>"OpenID verification cancelled."};
            print JSON::to_json(\@results);
        },
        verified => sub {
            my $vident = shift;
            if($option eq "openid-add") {
                print JSON::to_json($self->do_add_openid_to_account($sessionid, $user, $vident->url, $only));
            } else {
                print JSON::to_json($self->do_get_openid($vident->url));
            }
        },
        error => sub {
            $error = $csr->err;
            push @results,{user=>$user,only=>$only,error=>"Error validating identity: $error."};
            print JSON::to_json(\@results);
        }
    );
    return;
}

# Get OpenID - Check to see if the provided openid is unused
sub do_get_openid {
    my $self = shift;
    my $openid = shift;

    my $userdb = $self->{dbi};
    
    my ($error,@results);

    my $from = <<END;
FROM users as A, openid_users as B, session as C
 WHERE A.userid     = B.userid
   AND A.userid     = C.userid
   AND A.confirmed  = 1
   AND B.openid_url = ?
END
;
    my ($rows) = $userdb->selectrow_array(
	"select count(*) $from",
	undef,
	$openid)
	or ($error = DBI->errstr and push @results,{error=>"Error: $error."}
	    and return \@results);
    
    if($rows != 1) {
        if($rows != 0) {
            $error  = "Error: $rows rows returned, please consult your service host.";
        } else {
            $error  = "The OpenID provided has not been used before. ";
            $error .= "Please create an account first before trying to edit your information.";
        }
        push @results,{error=>$error,openid=>$openid};
        return \@results;
    }

    my $select = $userdb->prepare("SELECT C.username, C.sessionid, A.remember, A.openid_only, A.userid $from");
    $select->execute($openid)
        or ($error = DBI->errstr and push @results,{error=>"Error: $error."}
        and return \@results);

    my @info = $select->fetchrow_array;

    my $nowfun = $self->nowfun();
    my $update = $userdb->prepare(
        "UPDATE users SET last_login=$nowfun WHERE userid=? AND confirmed=1");
    $update->execute($info[4])
        or ($error = DBI->errstr and push @results,{error=>"Error: $error."}
        and return \@results);

    push @results,{user=>$info[0],session=>$info[1],remember=>$info[2],only=>$info[3]};
    return \@results;
}

# Change OpenID - Add or removes an openid from an account based on "option"
sub do_change_openid {
    my $self = shift;
    my ($user, $pass, $openid, $option) = @_;
    
    my $userdb = $self->{dbi};
    my $unseqpass = $pass;

    # BUG: we should salt the password
    $pass = sha1($pass);

    my ($sql,@bind);
    if ($unseqpass eq "") {
        $sql  = "SELECT a.userid FROM users as a,session as b WHERE b.username=? AND a.userid=b.userid AND a.openid_only=1";
        @bind = $user;
    } else {
        $sql  = "SELECT a.userid FROM users as a,session as b WHERE b.username=? AND a.userid=b.userid AND a.pass=?";
        @bind = ($user, $pass);
    }

    my $users = $userdb->selectrow_arrayref($sql,undef,@bind)
        or (print "Error: ",DBI->errstr,"." and die "Error: ",DBI->errstr);
    my $rows = @$users;

    if($rows != 1) {
        if($rows != 0) {
            print "Error: $rows rows returned, please consult your service host.";
        } else {
            print "Incorrect password provided, please check your spelling and try again.";
        }
        return;
    }

    if ($option eq "add") {
        $self->do_check_openid($openid, $users->[0],"openid-add");
        return;
    }

    my $delete = $userdb->prepare(<<END);
DELETE FROM openid_users
      WHERE openid_url=?
        AND userid IN (
                   SELECT a.userid
                     FROM openid_users as a,session as b
                    WHERE a.userid=b.userid
                      AND b.username=?
            )
END
;
    if ($delete->execute($openid,$user)) {
        print "Success";
    } else {
        if(DBI->errstr =~ m/for key 1$/) {
            print "The OpenID provided is already in use, please try another.";
        } else {
            print "Error: ",DBI->errstr,".";
        }
    }
    return;
}

# Add OpenID to Account (UserID, Username, OpenID, Only(?)) - Adds a confirmed openid to an account.
sub do_add_openid_to_account {
    my $self = shift;
    my ($sessionid, $user, $openid, $only) = @_;
    
    my $userdb = $self->{dbi};
    
    my ($error,@results);

    my $userid = $self->userid_from_sessionid($sessionid);
    unless ($userid) {
	print "Error: No userid associated with the current session";
	return;
    }

    my $insert = $userdb->prepare("INSERT INTO openid_users (userid,openid_url) VALUES (?,?)");
    if($insert->execute($userid, $openid)) {
        $error = "Success";
    } else {
        if(DBI->errstr =~ m/for key 1$/) {
            $error = "The OpenID provided is already in use, please try another.";
        } else {
            $error = "Error: ".DBI->errstr.".";
        }
    }
    push @results,{user=>$user,only=>$only,error=>$error};
    return \@results;
}

# Add OpenID User (Username, OpenID, UserID, Remember?) - Adds a new openid user to the user database.
sub do_add_openid_user {
    my $self = shift;
    my ($user, $openid, $sessionid, $remember) = @_;
    
    my $userdb = $self->{dbi};

    if($self->check_user($user)==0) {
        print "Usernames cannot contain any backslashes, whitespace or non-ascii characters.";return;
    }

    my $confirm = sha1($self->create_key('32'));
    my $pass    = sha1($self->create_key('32'));
    my $email   = $self->create_key('64');

    my $nowfun  = $self->nowfun();

    local $userdb->{AutoCommit} = 0;
    local $userdb->{RaiseError} = 1;
    eval {
	my $userid  = $self->add_named_session($sessionid,$user)
	    or die "Couldn't add named session: ",$userdb->errstr;
	    
	my $query  = $userdb->prepare(<<END);
INSERT INTO users (userid,email,pass,remember,openid_only,confirmed,cnfrm_code,last_login,created) 
     VALUES (?,?,?,?,1,1,?, $nowfun, $nowfun)
END
;

	# BUG: we should salt the password
	$pass = sha1($pass);
	$query->execute($userid, $email, $pass, $remember, $confirm)
	    or die "Couldn't insert openid_user into users table: ",$query->errstr;

	my $insert = $userdb->prepare("INSERT INTO openid_users (userid,openid_url) VALUES (?,?)");
	$insert->execute($userid, $openid) or die "Couldn't insert url into openid_users table: ",$insert->errstr;

	$userdb->commit();
    };

    if ($@) {
	warn "openid user account insertion failed due to $@. Rolling back.";
	eval {$userdb->rollback()};

	if(DBI->errstr =~ m/for key 1$/) {
	    print "The OpenID provided is already in use, please try another.";
	}
	elsif (DBI->errstr =~ m/for key 1$/ || DBI->errstr =~ m/for key 3$/) {
            #If the e-mail happens to match another, this will still be called.
            print "Username already in use, please try another.";
        } elsif(DBI->errstr =~ m/for key 2$/) {
            print "Session Error";
        } else {
            print "Error: ",DBI->errstr,".";
        }
    }
    else {
	print "Success";
    }
    return;
}

# List OpenID (User) - Generates a list of openids associated with a user's account.
sub do_list_openid {
    my $self = shift;
    my $user = shift;
    my ($error,@openids);
    my $userdb = $self->{dbi};

    my $select = $userdb->prepare(
        "SELECT a.openid_url FROM openid_users as a,session as b WHERE b.username=? AND a.userid=b.userid");
    $select->execute($user)
        or ($error = DBI->errstr and push @openids,{error=>"Error: $error."}
        and print JSON::to_json(\@openids) and die "Error: ",DBI->errstr);

    while (my $openid = $select->fetchrow_array) {
        push @openids,{name=>$openid};
    }

    unless (@openids) {
        push @openids,{error=>"There are no OpenIDs currently associated with this account."}
    }

    my @results = sort {$a->{name} cmp $b->{name}} @openids;
    print JSON::to_json(\@results);
}

1;

__END__
CREATE TABLE dbinfo (
    schema_version int(10) not null UNIQUE
);

CREATE TABLE session (
    userid integer PRIMARY KEY autoincrement, 
    username varchar(32),
    sessionid char(32) not null UNIQUE
    uploadsid char(32) not null UNIQUE, 
);
CREATE INDEX index_session on session(username);

CREATE TABLE "users" (
    userid integer PRIMARY KEY autoincrement, 
    username varchar(32) not null UNIQUE, 
    pass varchar(32) not null, 
    last_login timestamp not null, 
    remember boolean not null, 
    created datetime not null, 
    email varchar(64) not null UNIQUE, 
    openid_only boolean not null, 
    confirmed boolean not null, 
    cnfrm_code varchar(32) not null
);

CREATE TABLE openid_users (
    openid_url varchar(128) not null PRIMARY key, 
    userid varchar(32) not null, 
    username varchar(32) not null
);

CREATE TABLE "uploads" (
    trackid varchar(32) not null PRIMARY key, 
    userid integer not null UNIQUE, 
    public_users text, 
    sharing_policy varchar(36) not null, 
    users text, 
    path text, 
    description text, 
    data_source text, 
    modification_date datetime, 
    creation_date datetime not null, 
    public_count int, 
    title text, 
    imported boolean not null
);

