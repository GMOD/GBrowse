package CGI::Session::ID::salted_md5;

# $Id: salted_md5.pm,v 1.1.2.1 2005-11-07 20:52:54 lstein Exp $

use strict;
use Carp;
use Fcntl qw(LOCK_EX O_RDWR O_CREAT);
use Digest::MD5;
use base 'CGI::Session::ID::md5';

our $VERSION = '1.0';

sub generate_id {
  my ($self, $args) = @_;
  my $IDFile = $args->{IDFile} or croak "Don't know where to store the id";
  my $salt   = $args->{IDSalt};
  return $self->SUPER::generate_id() unless defined $salt;

  my $md5 = Digest::MD5->new();
  $md5->add($salt);
  $md5->add($self->SUPER::generate_id)  unless -e $IDFile;

  sysopen(FH, $IDFile, O_RDWR|O_CREAT, 0666) or return $self->set_error("Couldn't open IDFile=>$IDFile: $!");
  flock(FH, LOCK_EX) or return $self->set_error("Couldn't lock IDFile=>$IDFile: $!");
  binmode FH;
  eval {$md5->addfile(\*FH)};
  seek(FH, 0, 0)  or return $self->set_error("Couldn't seek IDFile=>$IDFile: $!");
  truncate(FH, 0) or return $self->set_error("Couldn't truncate IDFile=>$IDFile: $!");
  print FH $md5->clone->digest;
  close(FH) or return $self->set_error("Couldn't close IDFile=>$IDFile: $!");
  return $md5->hexdigest();

}

1;

=pod

=head1 NAME

CGI::Session::ID::salted_md5 - more secure CGI::Session ID generator

=head1 SYNOPSIS

    use CGI::Session;
    $s = new CGI::Session("id:md5", undef,{
                                            IDFile => '/tmp/cgisession.id',
                                            IDSalt => 'secret password'
                                          }
    );

=head1 DESCRIPTION

CGI::Session::ID::salted_md5 generates MD5 encoded hexadecimal random
IDs using a salt to make it very difficult to guess the series.

You must pass arguments of IDFile and IDSalt in order for this ID
generator to work properly. The first specifies a path to a writable
file where the current session ID will be stored. The second specifies
the salt to use to generate the ID. The salt should be kept secret.

Note that the default md5 session generator is already pretty good,
but it generates the MD5 from the process ID, the system clock and the
perl random generator. In principle, these can be guessed by a process
of brute force, allowing a determined individual to take over another
user's session.

=head1 LICENSING

For support and licensing see L<CGI::Session|CGI::Session>

=cut
