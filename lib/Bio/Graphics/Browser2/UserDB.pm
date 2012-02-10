package Bio::Graphics::Browser2::UserDB;

# $Id: UserDB.pm 23607 2010-07-30 17:34:25Z cnvandev $
use strict;
use Bio::Graphics::Browser2;
use Bio::Graphics::Browser2::SendMail;
use CGI qw(:standard);
use DBI;
use Digest::SHA qw(sha1_hex sha1);
use JSON;
use Text::ParseWords 'quotewords';
use Digest::MD5 qw(md5_hex);
use Carp qw(confess cluck croak);

use constant HAVE_OPENID => eval "require Net::OpenID::Consumer; require LWP::UserAgent; 1" || 0;
use constant HAVE_SMTP   => eval "require Net::SMTP;1" || 0;

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
      confess "Could not open login database $credentials";
  }

  my $self = bless {
      dbi      => $login,
      globals  => $globals,
      openid   => HAVE_OPENID,
      register => HAVE_SMTP,
  }, ref $class || $class;

  return $self;
}

sub globals  {shift->{globals} };
sub dbi      {shift->{dbi}     };
sub can_openid   {shift->{openid}  };
sub can_register {shift->{register}  };

sub generate_salted_digest {
    my $self     = shift;
    my $password = shift;
    my $salt     = $self->create_key(4);
    return $salt . sha1_hex($salt,$password);
}

sub salted_digest_match {
    my $self   = shift;
    my ($offered,$correct) = @_;
    my ($salt,$digest) = $correct =~ /^(.{4})(.+)/;
    return sha1_hex($salt,$offered) eq $digest;
}

sub is_salted {
    my $self    = shift;
    my $correct = shift;
    return $correct =~ /^[a-zA-Z0-9_]{4}[0-9a-f]{40}$/;
}

sub passwd_match {
    my $self = shift;
    my ($offered,$correct) = @_;
    return $self->is_salted($correct) ? $self->salted_digest_match($offered,$correct)
	                              : sha1($offered) eq $correct;
}

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

# Check Old Confirmations - Deletes any unconfirmed accounts more than 3 days old.
sub check_old_confirmations {
  my $self = shift;
  my $nowfun = $self->nowfun();
  my $userdb = $self->{dbi};

  my $days = $self->globals->user_account_db =~ /sqlite/i ? "julianday('now')-julianday(last_login)"
                                                          : 'datediff(now(),last_login)';
  local $userdb->{AutoCommit} = 0;
  local $userdb->{RaiseError} = 1;
  eval {
      my $ids = $userdb->selectcol_arrayref("SELECT userid FROM users WHERE confirmed=0 AND $days>3");
      for my $id (@$ids) {
	  $userdb->do('DELETE FROM users   WHERE userid=?',undef,$id);
	  $userdb->do('DELETE FROM session WHERE userid=?',undef,$id);
      }
      $userdb->commit();
  };
  if ($@) {
      warn "deletion of expired new accounts failed due to '$@'. Rolling back.";
      eval {$userdb->rollback()};
  }
  return;
}

# Now Function - return the database-dependent function for determining current date & time
sub nowfun {
  my $self = shift;
  my $globals = $self->{globals};
  return $globals->user_account_db =~ /sqlite/i ? "datetime('now','localtime')" : 'now()';
}

#################### N O N - O P E N I D   F U N C T I O N S #####################
# Get User ID (User) - Returns a confirmed user's ID
sub get_user_id {
    my $self = shift;
    my $search = shift;
    # inefficient use of three separate SQL statements
    return $self->userid_from_username($search) || $self->userid_from_email($search) || $self->userid_from_fullname($search);
}

sub match_user {
    my $self   = shift;
    my $search = shift;

    my $userdb = $self->dbi;
    my $select = $userdb->prepare(<<END) or die $userdb->errstr;
SELECT a.username,b.gecos,b.email 
  FROM session as a,users as b
 WHERE a.userid=b.userid
   AND (a.username LIKE ? OR
        b.gecos    LIKE ? OR
        b.email    LIKE ?)
END
;
    $search = quotemeta($search);
    my $db_search = "%$search%";
    $select->execute($db_search,$db_search,$db_search) or die $select->errstr;
    my @results;
    while (my @a = $select->fetchrow_array) {
	push @results, ($a[2] && $a[2] !~ /unused/i ? "$a[1] &lt;$a[2]&gt; ($a[0])" : "$a[1] ($a[0])");
    }
    $select->finish;
    return \@results;
}

 # similar to match_user() except that it only finds users who are sharing files
sub match_sharing_user {
    my $self   = shift;
    my ($source,$search) = @_;
    my $userdb = $self->dbi;
    my $select = $userdb->prepare(<<END) or die $userdb->errstr;
SELECT a.username,b.gecos,b.email 
  FROM session as a,users as b,uploads as c
 WHERE a.userid=b.userid
   AND a.userid=c.userid
   AND c.sharing_policy='public'
   AND c.data_source=?
   AND (a.username LIKE ? OR
        b.gecos    LIKE ? OR
        b.email    LIKE ?)
END
;
    $search = quotemeta($search);
    my $db_search = "%$search%";
    $select->execute($source,$db_search,$db_search,$db_search) or die $select->errstr;
    my @results;
    while (my @a = $select->fetchrow_array) {
	push @results,(grep /$search/i,@a);
    }
    $select->finish;
    return \@results;
}

sub userid_from_username {
    my $self     = shift;
    my $username = shift;

    my $userdb = $self->{dbi};
    my ($user_id) = 
	$userdb->selectrow_array(<<END ,undef,$username);
SELECT userid
  FROM session as a
  WHERE a.username=?
  LIMIT 1
END
return $user_id;
}

sub userid_from_email {
    my $self     = shift;
    my $email = shift;

    my $userdb = $self->{dbi};
    my ($user_id) = 
	$userdb->selectrow_array(<<END ,undef,$email);
SELECT userid
  FROM users as a
  WHERE a.email=?
  LIMIT 1
END
;
    return $user_id;
}

sub userid_from_fullname {
    my $self     = shift;
    my $email = shift;

    my $userdb = $self->{dbi};
    my ($user_id) = 
	$userdb->selectrow_array(<<END ,undef,$email);
SELECT userid
  FROM users as a
  WHERE a.gecos=?
  LIMIT 1
END
;
    return $user_id;
}

sub userid_from_uploadsid {
    my $self      = shift;
    my $uploadsid = shift;

    my $userdb = $self->{dbi};
    my $user_id = 
	$userdb->selectrow_array(<<END ,undef,$uploadsid);
SELECT userid
  FROM session as a
  WHERE a.uploadsid=?
  LIMIT 1
END
}

sub set_fullname_from_username {
    my $self = shift;
    my ($username,$fullname,$email) = @_;
    my $userdb = $self->dbi;

    my $userid = $self->userid_from_username($username) or return;

    local $userdb->{AutoCommit} = 0;
    local $userdb->{RaiseError} = 1;
    eval {
	my ($rows) = $userdb->selectrow_array(<<END,undef,$userid);
SELECT count(*) FROM users WHERE userid=?
END
;
	if ($rows > 0) {
	    $userdb->do('UPDATE users SET gecos=?,email=? WHERE userid=?',undef,$fullname,$email||'',$userid);
	} else {
	    my $nowfun = $self->nowfun();
	    my $email  = $email || ('unused_'.$self->create_key(32).'@nowhere.net');
	    $userdb->do(<<END,undef,$userid,$fullname,$email);
INSERT INTO users(userid,gecos,email,pass,remember,openid_only,confirmed,cnfrm_code,last_login,created)
VALUES (?,?,?,'x',1,1,1,'x',$nowfun,$nowfun)
END
;
	}
	$userdb->commit();
    };
    if ($@) {
	warn "Setting fullname for $username failed due to $@. Rolling back.";
	eval {$userdb->rollback()};
    }
}

sub sessionid_from_username {
    my $self = shift;
    my $username = shift;
    my $userdb   = $self->{dbi};
    my $sessionid = $userdb->selectrow_array(<<END ,undef,$username);
SELECT sessionid
  FROM session as a
  WHERE a.username=?
  LIMIT 1
END
;
    return $sessionid;
}

# Username From UploadsID (Uploads ID) - Returns a user's name.
sub username_from_uploadsid {
    my $self      = shift;
    my $uploadsid = shift;

    my $userdb = $self->{dbi};
    my $user_id = 
	$userdb->selectrow_array(<<END ,undef,$uploadsid);
SELECT username
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

sub accountinfo_from_username {
    my $self     = shift;
    my $username = shift;
    my $userdb = $self->dbi;
    return $userdb->selectrow_array('SELECT a.gecos,a.email FROM users as a,session as b WHERE a.userid=b.userid AND b.username=?',
				    undef,$username);
}

# Get Username (User ID) - Returns a user's username, given their ID.
sub get_username {
    croak "you probably want to call username_from_sessionid";
}

sub username_from_userid {
    my $self = shift;
    my $userid = shift;
    my $userdb = $self->{dbi};
    return $userdb->selectrow_array("SELECT username FROM session WHERE userid=?", undef, $userid) || 'an anonymous user';
}

sub username_from_sessionid {
    my $self = shift;
    my $sessionid = shift;
    my $userdb = $self->{dbi};

    return $userdb->selectrow_array(<<END ,undef,$sessionid)||'an anonymous user';
SELECT username FROM session
 WHERE sessionid=?
END
}

sub fullname_from_sessionid {
    my $self = shift;
    my $sessionid = shift;
    my $userdb = $self->{dbi};

    my ($fullname,$username) = $userdb->selectrow_array(<<END ,undef,$sessionid);
SELECT b.gecos,a.username 
  FROM session as a,users as b
 WHERE a.userid=b.userid
   AND a.sessionid=?
END
;
    return $fullname || $username; # fallback to username if fullname not available
}

sub email_from_sessionid {
    my $self = shift;
    my $sessionid = shift;
    my $userdb = $self->{dbi};

    my ($email) = $userdb->selectrow_array(<<END ,undef,$sessionid);
SELECT b.email
  FROM session as a,users as b
 WHERE a.userid=b.userid
   AND a.sessionid=?
END
;
    return $email;
}

sub userid_from_sessionid {
    my $self = shift;
    my $sessionid = shift;
    my $userdb = $self->{dbi};

    my ($userid) = $userdb->selectrow_array(<<END ,undef,$sessionid);
SELECT userid FROM session
 WHERE sessionid=?
END
    ;
    return $userid;
}

sub set_confirmed_from_username {
    my $self = shift;
    my $username = shift;
    my $userdb = $self->dbi;
    my $userid = $self->userid_from_username($username) or return;
    return $userdb->do('UPDATE users SET confirmed=1 WHERE userid=?',undef,$userid);
}

# Check Uploads ID (User ID, Uploads ID) - Makes sure a user's ID is in the database.
sub check_uploads_id {
    my $self = shift;
    croak "check_uploads_id() should no longer be necessary";
    my ($sessionid,$uploadsid) = @_;
    my $userdb = $self->{dbi};

    my $rows = $userdb->selectrow_array(<<END ,undef,$sessionid,$uploadsid);
SELECT count(*) FROM session
   WHERE sessionid=? and uploadsid=?
END
    unless ($rows) {
        $userdb->do(<<END ,undef,$sessionid,$uploadsid);
INSERT INTO session (sessionid,uploadsid)
     VALUES (?,?)
END
;
    }
    return $uploadsid;
}

sub check_or_add_named_session {
    my $self = shift;
    my ($sessionid,$username) = @_;
    if (my $old_session = $self->sessionid_from_username($username)) {
	return $old_session;
    } else {
	$self->add_named_session($sessionid,$username);
	return $sessionid;
    }
}

sub add_named_session {
    my $self = shift;
    my ($sessionid,$username) = @_;

    my $userdb  = $self->dbi;

    my $session = $self->globals->session($sessionid);
    $session->id eq $sessionid or die "Sessionid unavailable";
    my $uploadsid = $session->uploadsid;

    my $insert_session  = $userdb->prepare(<<END );
REPLACE INTO session (username,sessionid,uploadsid)
     VALUES (?,?,?)
END
    ;
    
    $insert_session->execute($username,$sessionid,$uploadsid)
	or return;
    return $userdb->last_insert_id('','','','');
}

sub set_session_and_uploadsid {
    my $self = shift;
    my ($userid,$sessionid,$uploadsid) = @_;

    my $userdb = $self->dbi;
    $userdb->do('UPDATE session SET sessionid=?,uploadsid=? WHERE userid=?',
		undef,
		$sessionid,$uploadsid,$userid) or die $userdb->errstr;
}

sub delete_user_by_username {
    my $self = shift;
    my $username = shift;
    my $userdb = $self->dbi;
    my $userid = $self->userid_from_username($username) or return;
    local $userdb->{AutoCommit} = 0;
    local $userdb->{RaiseError} = 1;
    eval {
	$userdb->do('DELETE FROM users        WHERE userid=?',undef,$userid);
	$userdb->do('DELETE FROM session      WHERE userid=?',undef,$userid);
	$userdb->do('DELETE FROM openid_users WHERE userid=?',undef,$userid);
	$userdb->do('DELETE FROM uploads      WHERE userid=?',undef,$userid);
	$userdb->do('DELETE FROM sharing      WHERE userid=?',undef,$userid);
	$userdb->commit();
    };
    if ($@) {
	warn "Account deletion failed due to $@. Rolling back.";
	eval {$userdb->rollback()};
    }
    1;
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

  # remove dangling unconfirmed accounts here
  $self->check_old_confirmations();

#  return $self->string_result('Usernames cannot contain any backslashes, whitespace or non-ascii characters.')
  return $self->code_result('INVALID_NAME'=>'Usernames cannot contain any backslashes, whitespace or non-ascii characters.')
      unless $self->check_user($user);

  my $userid = $self->userid_from_username($user);
  my $nowfun = $self->nowfun();

  # WARNING: bad design here
  # EXPLANATION: a remember value of "2" means to update last_login
  # but not to retrieve session ID. This seems to be requested during account
  # editing/updating.
  if($remember == 2) {
      $update = $userdb->prepare(
	  "UPDATE users SET last_login=$nowfun WHERE userid=? AND confirmed=1");
  } else {
      $update = $userdb->prepare(
	  "UPDATE users SET last_login=$nowfun,remember=$remember WHERE userid=? AND confirmed=1");
  }

  my $select = $userdb->prepare(
      "SELECT sessionid,email,confirmed,pass FROM users as a,session as b WHERE a.userid=b.userid and a.userid=?");
  $select->execute($userid)
      or return $self->dbi_err;

  # BUG: this is truly nasty -- the session id is found by string searching in login.js!!!!
  my ($session,$email,$confirmed,$correct_pass) = $select->fetchrow_array;

  if ($session && $self->passwd_match($pass,$correct_pass)) {
      if ($confirmed) {
	  my $result = $remember == 2 ? 'Success' : "session".$session;
	  return $self->string_result($result);
      } else {
	  return $self->string_result("unconfirmed${email}");
      }
  } else {
      return $self->string_result('Invalid username or password provided, please try again.'); 
  }

  # update time login now
  $update->execute($userid)
      or return $self->dbi_err;
}

# Add User Check - Checks to see if the user has already been added.
sub do_add_user_check {
  my $self = shift;
  my ($user,$email,$fullname,$pass,$userid) = @_;
  
  my $userdb = $self->dbi;
  
  return $self->string_result('Invalid e-mail address (',$email,') provided.')
      unless $self->check_email($email);
  
  return $self->string_result("Usernames cannot contain any backslashes, whitespace or non-ascii characters.")
      unless $self->check_user($user);

  my $select = $userdb->prepare(
    "SELECT confirmed FROM users WHERE email=?");
  $select->execute($email)
      or return $self->dbi_err;

  my $confirmed = $select->fetchrow_array;
  if($select->rows == 0) {
      return $self->do_add_user($user,$email,$fullname,$pass,$userid);
  } elsif($confirmed == 1) {
      return $self->string_result('E-mail in use');
  } elsif($confirmed == 0) {
      return $self->string_result('Message Already Sent');
  }

  return $self->programmer_error;
}

# Add User - Adds a new non-openid user to the user database.
sub do_add_user {
  my $self = shift;
  my ($user,$email,$fullname,$pass,$sessionid,$allow_admin) = @_;

  # for debugging front end, uncomment as needed
#  return $self->string_result('Session Error');
#  return $self->string_result('Username already in use, please try another.');
#    return $self->string_result("Invalid e-mail address (",$email,") provided.");
#  return $self->string_result('Success');
  
  my $userdb = $self->dbi;
  
  return $self->string_result("Invalid e-mail address (",$email,") provided.")
      unless $self->check_email($email);

  return $self->string_result('Usernames cannot contain any backslashes, whitespace or non-ascii characters.')
      unless $self->check_user($user);
		  
  return $self->string_result("Invalid username. Try a different one.")
      if !$allow_admin && $self->check_admin($user);

  # see if this username is already taken
  return (200,'text/plain','Username already in use, please try another.')
      if $self->userid_from_username($user);

  my $confirm = $self->create_key('32');
  my $nowfun = $self->nowfun();

  local $userdb->{AutoCommit} = 0;
  local $userdb->{RaiseError} = 1;
  eval {
      my $userid = $self->add_named_session($sessionid,$user) 
	  or return $self->dbi_err;

      my $insert_userinfo = $userdb->prepare (<<END );
INSERT INTO users (userid, gecos, email, pass, remember, openid_only, 
		   confirmed, cnfrm_code, last_login, created)
     VALUES (?,?,?,?,0,0,0,?,$nowfun,$nowfun)
END
;
      my $sha_pass = $self->generate_salted_digest($pass);
      $insert_userinfo->execute($userid,$fullname,$email,$sha_pass,$confirm)
	  or return $self->dbi_err;
      $userdb->commit();
  };
  if ($@) {
      warn "user account insertion failed due to $@. Rolling back.";
      eval {$userdb->rollback()};
      if(DBI->errstr =~ m/for key 1$/      || DBI->errstr =~ m/username is not unique/) {
	  return $self->string_result("Username already in use, please try another.");
      } elsif(DBI->errstr =~ m/for key 2$/ || DBI->errstr =~ m/email is not unique/) {
	  return $self->string_result("E-mail address already in use, please provide another.");
      } elsif(DBI->errstr =~ m/for key 3$/ || DBI->errstr =~ m/userid is not unique/) {
	  return $self->string_result("Session Error");
      } else {
	  return $self->dbi_err;
      }
  }
  
  else {
      return $self->do_send_confirmation($email,$confirm,$user,$pass);
  }

    return $self->programmer_error;
}

# Send Confirmation - Sends an e-mail when a user creates a new non-openid account to ensure that the user is valid and the e-mail exists.
sub do_send_confirmation {
  my $self = shift;
  my ($email,$confirm,$user,$pass) = @_;

  my $globals = $self->{globals};
  my $link = $globals->gbrowse_url()."/?confirm=1&code=$confirm";

  my $message  = '<HTML><BODY>'.$self->get_header();
  $message    .= <<END;
  <p>
  <table>
      <tr><th align="right">Username</th><td>$user</td></tr>
      <tr><th align="right">Password</th><td>$pass</td></tr>
      <tr><th align="right">Email</th><td>$email</td></tr>
   </table>
   </p>
   <p>
   To activate your account and complete the sign up process, please click
   on the following link: <a href="$link">$link</a>
   </p>
END
     $message .= '<p style="font-size:small">'.$self->get_footer().'</p></BODY></HTML>';

  my ($status,$err) = $self->Bio::Graphics::Browser2::SendMail::do_sendmail({
     from       => $globals->email_address,
     from_title => $globals->application_name,
     to         => $email,
     subject    => $globals->application_name . " Account Activation",
     msg        => $message,
     HTML       => 1,
  },$globals);
  unless ($status) {
      warn $err;
       return $self->string_result('Mail Error');
  }
  return $self->string_result('Success');
}

# Edit Confirmation - Deletes or resends unconfirmed information based on "option"
sub do_edit_confirmation {
  my $self = shift;
  my ($email,$option) = @_;
  
  my $userdb = $self->{dbi};

  my $select = $userdb->prepare(<<END );
SELECT b.username, a.userid, b.sessionid, a.gecos, a.cnfrm_code
    FROM users as a,session as b 
    WHERE a.email=? AND a.userid=b.userid
END
  $select->execute($email)
    or return $self->dbi_err;
  my ($username,$userid,$sessionid,$fullname, $confirm) = $select->fetchrow_array();

  if ($option == 0) { # delete account!
      eval {
	  local $userdb->{AutoCommit} = 0;
	  local $userdb->{RaiseError} = 1;
	  $userdb->do("DELETE FROM users        WHERE userid=?",undef,$userid);
	  $userdb->do("DELETE FROM openid_users WHERE userid=?",undef,$userid);
	  $userdb->do("DELETE FROM session      WHERE userid=?",undef,$userid);
	  $userdb->commit();
      };
      if ($@) {
	  eval {$userdb->rollback()};
	  return $self->string_result($@);
      } else {
	  return $self->string_result("Your account has been successfully removed.");
      }
  }

  elsif ($option == 1) {
      my $pass = '******';
      return $self->do_send_confirmation($email,$confirm,$username,$pass);
      # return $self->string_result("Success");
  }

  return $self->programmer_error;
}

# Confirm Account - Activates a new account when the user follows the mailed link.
sub do_confirm_account {
  my $self = shift;
  my ($user,$confirm) = @_;
  my $userdb = $self->{dbi};

  my $new_confirm = sha1_hex($confirm);

  my ($rows) = $userdb->selectrow_array(
    "SELECT count(*) FROM users WHERE cnfrm_code=? AND confirmed=0",
    undef,
    $confirm);

  return $self->string_result('Already Active') unless $rows == 1;

  my $userid = $self->userid_from_username($user);

  my $update = $userdb->prepare(
    "UPDATE users SET confirmed=1,cnfrm_code=? WHERE userid=? AND cnfrm_code=? AND confirmed=0");
  $update->execute($new_confirm,$userid,$confirm)
    or return $self->dbi_err;

  $rows = $update->rows;
  if ($rows == 1) {
    my $query = $userdb->prepare(
      "SELECT b.sessionid FROM users as a,session as b WHERE b.username=? AND a.userid=b.userid AND cnfrm_code=? AND confirmed=1");

    $query->execute($user,$new_confirm)
      or return $self->dbi_err;

    return $self->string_result($query->fetchrow_array());
  } elsif($rows == 0) {
      return $self->string_result("Error: Incorrect username provided, please check your spelling and try again.");
  } else {
      return $self->string_result("Error: $rows rows returned, please consult your service host.");
  }
  return;
}

# Edit Details - Updates the user's e-mail or password depending on the "column"
sub do_edit_details {
    my $self = shift;
    my ($user,$column,$old,$new,$session) = @_;
    my $userdb = $self->dbi;
    my $userid = $self->userid_from_username($user)
	or return $self->string_result("Error: unkown user $user");

    $session->private && $session->username eq $user
	or return $self->string_result('Error: Apparent attempt to change details for another user');
    
    if($column eq 'email') {
	return $self->string_result("New e-mail address is invalid, please try another.")
	    unless $self->check_email($new);
    }

    if ($column eq 'pass') {
	my ($pass) = $userdb->selectrow_array('SELECT pass FROM users WHERE userid=?',undef,$userid);
	unless ($self->passwd_match($old,$pass)) {
	    return $self->string_result("Incorrect password provided, please check your spelling.");
	}
	$new = $self->generate_salted_digest($new);
	$old = $pass;
    }

    my $querystring  = "UPDATE users       ";
    $querystring .= "   SET $column  = ?";
    $querystring .= " WHERE userid   = ?";

    my $update = $userdb->prepare($querystring);
    unless($update->execute($new,$userid)) {
	if ($column eq 'email') {
	    return $self->string_result("New e-mail already in use, please try another.");
	} else {
	    return $self->dbi_err;
	}
    }

    if (DBI->errstr =~ m/for key 3$/) {
	return $self->string_result("New e-mail already in use, please try another.");
    }

    my $rows = $update->rows;
    if($rows == 1) {
	return $self->string_result("Success");
    } elsif ($rows == 0) {
	my $explanation = $column eq 'pass'  ? 'password' 
	                 :$column eq 'email' ? 'email address'
			 :'information';
	return $self->string_result("Incorrect $explanation provided, please check your spelling.");
    } else {
	if(($column eq 'email') and ($rows == -1)) {
	    return $self->string_result("New e-mail already in use, please try another.");
	} else {
	    return $self->string_result("Error: $rows rows returned, please consult your service host.");
	}
    }
    return $self->programmer_error;
}
  
# E-mail Info - Sends an e-mail when a user has forgotten their password.
sub do_email_info {
  my $self = shift;
  my $email = shift;
  my $globals = $self->{globals};
  my $userdb = $self->{dbi};
  
  return $self->string_result("Invalid e-mail address provided.")
      unless $self->check_email($email);

  my ($user,$rows,$openid_ref) = $self->do_retrieve_user($email);
  my @openids = @$openid_ref;
  my $openid  = "";
  
  return $self->string_result($user) unless $rows == 1;

  if (@openids) {foreach(@openids) {$openid .= "$_\n             ";}}
  else {$openid = "None\n";}

  my $pass = $self->create_key('8');
  my $message  = "\nYour password has been reset to the one seen below. To fix this,";
     $message .= " select \"My Account\" from the log in menu and log in with the";
     $message .= " credentials found below.\n\n    Username: $user\n    ";
     $message .= "Password: $pass\n\n    OpenIDs: $openid\n\n";
     $message .= $self->get_footer();

  my ($status,$err) = $self->Bio::Graphics::Browser2::SendMail::do_sendmail({
			     from       => $globals->email_address,
			     from_title => $globals->application_name,
			     to         => $email,
			     subject    => $globals->application_name . " Account Information",
			     msg        => $message
			    },$globals);
  return $self->string_result($err) unless $status;

  my $secret = $self->generate_salted_digest($pass);
  my $update = $userdb->prepare(
    "UPDATE users SET pass=? WHERE userid=? AND email=? AND confirmed=1");
  my $userid = $self->userid_from_username($user);
  $update->execute($secret,$userid,$email)
    or return $self->dbi_err;

  return $self->string_result('Success');
}

sub set_password {
    my $self = shift;
    my ($userid,$password) = @_;
    my $userdb   = $self->dbi;
    my $secret = $self->generate_salted_digest($password);
    my $update = $userdb->prepare(
	"UPDATE users SET pass=? WHERE userid=?") or die $userdb->errstr;
    my $status = $update->execute($secret,$userid) or die $userdb->errstr;
    return $status;
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
  or return $self->dbi_err;

  my $rows = @$users;
  if ($rows == 1) {
    my $user  = $users->[0];
    my $query = $userdb->prepare(
      "SELECT openid_url FROM openid_users,session WHERE openid_users.userid=session.userid and session.username=?");
    $query->execute($user)
      or return $self->dbi_err;

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
  
  my $userdb = $self->dbi;
  my $userid = $self->userid_from_username($user);
  return $self->string_result("Error: unknown user $user") unless $userid;

  my $sessionid = $self->get_sessionid($userid);
  $userdb->do('DELETE FROM session where userid=?',undef,$userid);
  my $session = $self->globals->session($sessionid);
  $session->delete;
  $session->flush;

  $userdb->do('DELETE FROM users WHERE userid=?',undef,$userid);

  my $query = $userdb->prepare(
    "DELETE FROM openid_users WHERE userid=?");
  if ($query->execute($userid)) {
      return $self->string_result('Success');
  } else {
      return $self->dbi_err;
  }
  return;
}

######################## O P E N I D   F U N C T I O N S #########################
# Check OpenID - Sends a user to their openid host for confirmation.

# BUG: ALL THE OPENID FUNCTIONS NEED TO BE REVISED
sub do_check_openid {
    my $self = shift;
    my $globals = $self->{globals};
    my ($openid, $sessionid, $source, $option) = @_;
    
    my $return_to  = $globals->gbrowse_url($source)."/?openid_confirm=1;page=$option;s=$sessionid";

    my $csr = Net::OpenID::Consumer->new(
        ua              => LWP::UserAgent->new,
        args            => CGI->new,
        consumer_secret => Bio::Graphics::Browser2->openid_secret,
        required_root   => "http://$ENV{'HTTP_HOST'}/"
    );

    my $claimed_identity = $csr->claimed_identity($openid)
        or return $self->string_result("The URL provided is not a valid OpenID, please check your spelling and try again.");
    
    my $check_url = $claimed_identity->check_url(
        return_to  => $return_to,
        trust_root => "http://$ENV{'HTTP_HOST'}/",
        delayed_return => 1
    );
    # request information about email address and full name
    $check_url .= "&openid.ns.ax=http://openid.net/srv/ax/1.0&openid.ax.mode=fetch_request&openid.ax.required=email,firstname,lastname&openid.ax.type.email=http://axschema.org/contact/email&openid.ax.type.firstname=http://axschema.org/namePerson/first&openid.ax.type.lastname=http://axschema.org/namePerson/last";

    # this shouldn't work, but oddly it does.
    # it has something to do with prototype ajax and the Location: string
    return (200,'text/html',"Location: $check_url"); # shouldn't work?

    # this should work, but oddly it doesn't
    # return (302,undef,$check_url);

}

# Confirm OpenID - Checks that the returned credentials are valid.
sub do_confirm_openid {
    my $self = shift;
    my ($callbacks, $sessionid, $option,$email,$fullname) = @_;
    
    my $userdb = $self->{dbi};
    
    my ($error, @results, $select, $user, $only);

    my $csr = Net::OpenID::Consumer->new(
        ua              => LWP::UserAgent->new,
        args            => $callbacks,
        consumer_secret => Bio::Graphics::Browser2->openid_secret,
        required_root   => "http://$ENV{'HTTP_HOST'}/"
    );

    if ($option eq "openid-add") {
        ($user, $only) = $userdb->selectrow_array(
	    "SELECT b.username,a.openid_only FROM users as a,session as b WHERE b.sessionid=? AND a.userid=b.userid",
	    undef,
	    $sessionid)
	    or return(200,'application/json',[{error=>'Error: '.$userdb->errstr.'.'}]);
        unless (defined $user) {
            push @results,{error=>"Error: Wrong session ID provided, please try again."};
            return (200,'application/json',\@results);
        }
    }

    $csr->handle_server_response(
        not_openid => sub {
            push @results,{user=>$user,only=>$only,error=>"Invalid OpenID provided, please check your spelling."};
        },
        setup_required => sub {
            push @results,{user=>$user,only=>$only,error=>"Error: Your OpenID requires setup."};
        },
        cancelled => sub {
            push @results,{user=>$user,only=>$only,error=>"OpenID verification cancelled."};
        },
        verified => sub {
            my $vident = shift;
            if($option eq "openid-add") {
		push @results,$self->do_add_openid_to_account($sessionid, $user, $vident->url, $only)
            } else {
		push @results,$self->do_get_openid($vident->url,$email,$fullname);
            }
        },
        error => sub {
            $error = $csr->err;
            push @results,{user=>$user,only=>$only,error=>"Error validating identity: $error."};
        }
    );
    return (200,'application/json',\@results);
}

sub do_get_gecos {
    my $self = shift;
    my $user = shift;
    my $sessionid = $self->sessionid_from_username($user) or return '';
    my $fullname = $self->fullname_from_sessionid($sessionid);
    return $self->string_result($fullname);
}

sub do_get_email {
    my $self = shift;
    my $user = shift;
    my $sessionid = $self->sessionid_from_username($user) or return '';
    my $fullname = $self->email_from_sessionid($sessionid);
    return $self->string_result($fullname);
}

# Get OpenID - Check to see if the provided openid is unused
sub do_get_openid {
    my $self   = shift;
    my ($openid,$email,$fullname) = @_;

    my $userdb = $self->{dbi};
    
    my $error;

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
	or return {error=>'Error: '.$userdb->errstr.'.'};

    if($rows != 1) {
        if($rows == 0) {
            $error  = "The OpenID provided has not been used before. ";
            $error .= "Please create an account first before trying to edit your information.";
        } else {
            $error  = "Error: $rows rows returned, please consult your service host.";
        }
        return {error=>$error,openid=>$openid,email=>$email,fullname=>$fullname};
    }

    my $select = $userdb->prepare("SELECT C.username, C.sessionid, A.remember, A.openid_only, A.userid $from");
    $select->execute($openid)
	or return {error=>'Error: '.$select->errstr.'.'};

    my @info = $select->fetchrow_array;

    my $nowfun = $self->nowfun();
    my $update = $userdb->prepare(
        "UPDATE users SET last_login=$nowfun WHERE userid=? AND confirmed=1");
    $update->execute($info[4])
	or return {error=>'Error: '.$update->errstr.'.'};

    return {user=>$info[0],session=>$info[1],remember=>$info[2],only=>$info[3]};
}

# Change OpenID - Add or removes an openid from an account based on "option"
sub do_change_openid {
    my $self = shift;
    my ($user, $pass, $openid, $option) = @_;

    my $userdb = $self->dbi;
    my $users = $userdb->selectrow_arrayref('SELECT a.userid FROM users as a,session as b WHERE b.username=? AND a.userid=b.userid',
					    undef,$user)
        or return $self->dbi_err;
    my $rows = @$users;

    return $self->string_result("Error: unknown user $user.") unless $rows == 1;

    if ($option eq "add") {
        return $self->do_check_openid($openid, $users->[0],"openid-add");
    }

    # if we get here, we are deleting
    my ($correct_pass) = $userdb->selectrow_array('SELECT a.pass FROM users as a WHERE a.userid=?',undef,$users->[0])
	or return $self->dbi_err;
    
    $self->passwd_match($pass,$correct_pass)
	or return $self->string_result('Invalid password. Please try again.');

    my $delete = $userdb->prepare(<<END );
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
	return $self->string_result('Success');
    } else {
        if(DBI->errstr =~ m/for key 1$/) {
	    return $self->string_result("The OpenID provided is already in use, please try another.");
        } else {
	    return $self->dbi_err;
        }
    }
    return $self->programmer_error;
}

# Add OpenID to Account (UserID, Username, OpenID, Only(?)) - Adds a confirmed openid to an account.
sub do_add_openid_to_account {
    my $self = shift;
    my ($sessionid, $user, $openid, $only) = @_;
    
    my $userdb = $self->{dbi};
    my $error;

    my $userid = $self->userid_from_sessionid($sessionid)
	or return {user=>$user,only=>$only,error=>"Error: No userid associated with the current session"};
    
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
    return {user=>$user,only=>$only,error=>$error};
}

# Add OpenID User (Username, Email, Gecos(fullname), OpenID, UserID, Remember?) - Adds a new openid user to the user database.
sub do_add_openid_user {
    my $self = shift;
    my ($user, $email, $gecos, $openid, $sessionid, $remember) = @_;

    my $userdb = $self->{dbi};

    return $self->string_result("Usernames cannot contain any backslashes, whitespace or non-ascii characters.")
	unless $self->check_user($user);

    my $confirm = sha1_hex($self->create_key('32'));
    my $pass    = $self->generate_salted_digest($self->create_key('32'));

    my $nowfun  = $self->nowfun();

    local $userdb->{AutoCommit} = 0;
    local $userdb->{RaiseError} = 1;
    eval {
	my $userid  = $self->add_named_session($sessionid,$user)
	    or return $self->dbi_err;
	    
	my $query  = $userdb->prepare(<<END );
INSERT INTO users (userid,email,gecos,pass,remember,openid_only,confirmed,cnfrm_code,last_login,created) 
     VALUES (?,?,?,?,?,1,1,?, $nowfun, $nowfun)
END
;

	$query->execute($userid, $email, $gecos, $pass, $remember, $confirm)
	    or return $self->dbi_err;

	my $insert = $userdb->prepare("INSERT INTO openid_users (userid,openid_url) VALUES (?,?)");
	$insert->execute($userid, $openid) or die "Couldn't insert url into openid_users table: ",$insert->errstr;

	$userdb->commit();
    };

    if ($@) {
	warn "openid user account insertion failed due to $@. Rolling back.";
	my $err = $@;
	eval {$userdb->rollback()};

	if($err =~ m/for key 1$/) {
	    return $self->string_result("The OpenID provided is already in use, please try another.");
	}
	elsif ($err =~ m/for key 1$/ || DBI->errstr =~ m/for key 3$/) {
            #If the e-mail happens to match another, this will still be called.
	    return $self->string_result("Username already in use, please try another.");
        } elsif($err =~ m/for key 2$/) {
	    return $self->string_result("Session Error");
        } else {
	    return $self->dbi_err($err);
        }
    }
    else {
	return $self->string_result('Success');
    }
    return $self->programmer_error;
}

# List OpenID (User) - Generates a list of openids associated with a user's account.
sub do_list_openid {
    my $self = shift;
    my $user = shift;
    my ($error,@openids);
    my $userdb = $self->{dbi};

    my $select = $userdb->prepare(
        "SELECT a.openid_url FROM openid_users as a,session as b WHERE b.username=? AND a.userid=b.userid");
    $select->execute($user) or return (200,'application/json',[{error=>'Error: '.$userdb->errstr.'.'}]);

    while (my $openid = $select->fetchrow_array) {
        push @openids,{name=>$openid};
    }

    unless (@openids) {
        push @openids,{error=>"There are no OpenIDs currently associated with this account."}
    }

    my @results = sort {$a->{name} cmp $b->{name}} @openids;
    return(200,'application/json',\@results);
}

# convenience methods
sub dbi_err {
    my $self = shift;
    my $err  = shift;
    my $error = $err || DBI->errstr;
    $error    =~ s/at.+line \d+//;
    return (200,'text/plain',"Error: $error");
}

sub code_result {
    my $self = shift;
    my ($code,@msg) = @_;
    return (200,'application/json',{code=>$code,message=>join('',@msg)});
}
sub string_result {
    my $self = shift;
    my @msg  = @_;
    return (200,'text/plain',join('',@msg));
}

sub programmer_error {
    my $self = shift;
    return (500,'text/plain','programmer error?');
}

# Remember (User) - Get's a user's remember flag.
sub remember {
    my $self = shift;
    my $userid = shift;
    my $userdb = $self->{dbi};
    return $userdb->selectrow_array("SELECT remember FROM users WHERE userid = ?", undef, $userid);
}

# Remember (User) - Get's if a user is using OpenID login.
sub using_openid {
    my $self = shift;
    my $userid = shift;
    my $userdb = $self->{dbi};
    return $userdb->selectrow_array("SELECT userid FROM openid_users WHERE userid = ?", undef, $userid)? "true" : "false";
}

sub clone_database {
    my $self = shift;
    $self->{dbi}{InactiveDestroy} = 1;
    $self->{dbi} = $self->{dbi}->clone
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
