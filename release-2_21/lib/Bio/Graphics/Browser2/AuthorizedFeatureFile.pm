package Bio::Graphics::Browser2::AuthorizedFeatureFile;

use strict;
use warnings;
use base 'Bio::Graphics::FeatureFile';

use Socket 'AF_INET','inet_aton';  # for inet_aton() call
use Carp 'croak','cluck';
use CGI();

=head1 NAME

Bio::Graphics::Browser2::AuthorizedFeatureFile -- Add HTTP authorization features to FeatureFile

=head1 SYNOPSIS

GBrowse internal module.

=head1 DESCRIPTION

GBrowse internal module.

=head2 METHODS

=over 4

=cut

# override setting to default to 'general'
sub setting {
  my $self = shift;
  my ($label,$option,@rest) = @_ >= 2 ? @_ : ('general',@_);
  $label = 'general' if lc $label eq 'general';  # buglet
  $self->SUPER::setting($label,$option,@rest);
}

sub label_options {
    my $self  = shift;
    my $label = shift;
    return $self->SUPER::_setting($label);
}

# get or set the authenticator used to map usernames onto groups
sub set_authenticator { 
    my $self = shift;
    $self->{'.authenticator'} = shift;
}
sub authenticator     { 
    shift->{'.authenticator'};             
}

# get or set the username used in authentication processes
sub set_username { 
    my $self = shift;
    my $username = shift;
    $self->{'.authenticated_username'} = $username;
}
sub username     { 
    my $self = shift;
    return $self->{'.authenticated_username'} || CGI->remote_user;
}

# implement the "restrict" option
sub authorized {
  my $self  = shift;
  my $label = shift;
  
  my $restrict = $self->code_setting($label=>'restrict')
    || ($label ne 'general' && $self->code_setting('TRACK DEFAULTS' => 'restrict'));
  return 1 unless $restrict;

  my $host     = CGI->remote_host;
  my $addr     = CGI->remote_addr;
  my $user     = $self->username;

  undef $host if $host eq $addr;
  return $restrict->($host,$addr,$user) if ref $restrict eq 'CODE';
  my @tokens = split /\s*(satisfy|order|allow from|deny from|require user|require group|require valid-user)\s*/i,$restrict;
  shift @tokens unless $tokens[0] =~ /\S/;
  my $mode    = 'allow,deny';
  my $satisfy = 'all';
  my $user_directive;

  my (@allow,@deny,%users);
  while (@tokens) {
    my ($directive,$value) = splice(@tokens,0,2);
    $directive = lc $directive;
    $value ||= '';
    if ($directive eq 'order') {
      $mode = $value;
      next;
    }
    my @values = split /[^\w.@-]/,$value;

    if ($directive eq 'allow from') {
      push @allow,@values;
      next;
    }
    if ($directive eq 'deny from') {
      push @deny,@values;
      next;
    }
    if ($directive eq 'satisfy') {
      $satisfy = $value;
      next;
    }
    if ($directive eq 'require user') {
      $user_directive++;
      foreach (@values) {
	if ($_ eq 'valid-user' && defined $user) {
	  $users{$user}++;  # ensures that this user will match
	} else {
	  $users{$_}++;
	}
      }
      next;
    }
    if ($directive eq 'require valid-user') {
      $user_directive++;
      $users{$user}++ if defined $user;
    }
    if ($directive eq 'require group' && defined $user) {
	$user_directive++;
	if (my $auth_plugin = $self->authenticator) {
	    for my $grp (@values) {
		$users{$user} ||= $auth_plugin->user_in_group($user,$grp);
	    }
	} else {
	   warn "To use the 'require group' limit you must load an authentication plugin. Otherwise use a subroutine to implement role-based authentication.";
	}
    }
  }

  my $allow = $mode eq  'allow,deny' ? match_host(\@allow,$host,$addr) && !match_host(\@deny,$host,$addr)
                      : 'deny,allow' ? !match_host(\@deny,$host,$addr) ||  match_host(\@allow,$host,$addr)
		      : croak "$mode is not a valid authorization mode";
  return $allow unless $user_directive;
  $satisfy = 'any'  if !@allow && !@deny;  # no host restrictions

  # prevent unint variable warnings
  $user         ||= '';
  $allow        ||= '';
  $users{$user} ||= '';

  return $satisfy eq 'any' ? $allow || $users{$user}
                           : $allow && $users{$user};
}

sub match_host {
  my ($matches,$host,$addr) = @_;
  my $ok;
  for my $candidate (@$matches) {
    if ($candidate eq 'all') {
      $ok ||= 1;
    } elsif ($candidate =~ /^[\d.]+$/) { # ip match
      $addr      .= '.' unless $addr      =~ /\.$/;  # these lines ensure subnets match correctly
      $candidate .= '.' unless $candidate =~ /\.$/;
      $ok ||= $addr =~ /^\Q$candidate\E/;
    } else {
      $host ||= gethostbyaddr(inet_aton($addr),AF_INET);
      next unless $host;
      $candidate = ".$candidate" unless $candidate =~ /^\./; # these lines ensure domains match correctly
      $host      = ".$host"      unless $host      =~ /^\./;
      $ok ||= $host =~ /\Q$candidate\E$/;
    }
    return 1 if $ok;
  }
  $ok;
}

1;

