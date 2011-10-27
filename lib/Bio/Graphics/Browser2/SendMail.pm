package Bio::Graphics::Browser2::SendMail;

# $Id: UserDB.pm 23607 2010-07-30 17:34:25Z cnvandev $
use strict;
use Bio::Graphics::Browser2;
use CGI qw(:standard);
use DBI;
use Digest::SHA qw(sha1_hex sha1);
use JSON;
use Text::ParseWords 'quotewords';
use Digest::MD5 qw(md5_hex);
use Carp qw(confess cluck croak);

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
  my $globals = shift;

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
	      Debug   => 1,
	      )
	      or die "Could not connect to outgoing mail server $server";
	  
	  if ($username) {
	      $smtp_obj->auth($username, $password) 
		  or die "Could not authenticate with outgoing mail server $server: ",$smtp_obj->message
	  }
	  
	  $smtp_obj->mail("$smtp_from\n")                    or die $smtp_obj->message;
	  $smtp_obj->to("$args->{to}\n")                     or die $smtp_obj->message;
	  $smtp_obj->data()                                  or die $smtp_obj->message;
	  $smtp_obj->datasend("From: \"$args->{from_title}\" <$args->{from}>\n")
	                                                     or die $smtp_obj->message;
	  $smtp_obj->datasend("To: $args->{to}\n")           or die $smtp_obj->message;
	  $smtp_obj->datasend("Reply-to: $args->{from}\n")   or die $smtp_obj->message;
	  $smtp_obj->datasend("Subject: $args->{subject}\n") or die $smtp_obj->message;
	  $smtp_obj->datasend("Content-type: text/html; charset=ISO-8859-1\n") 
	                                                     or die $smtp_obj->message
							     if $args->{HTML};
	  $smtp_obj->datasend("\n")                          or die $smtp_obj->message;
	  $smtp_obj->datasend($args->{msg})                  or die $smtp_obj->message;
	  $smtp_obj->datasend("\n")                          or die $smtp_obj->message;
	  $smtp_obj->dataend()                               or die $smtp_obj->message;
	  $smtp_obj->quit();
  };
  warn $@ if $@;
  return (0, $@) if $@;
  return (1,'');
}

1;

__END__
