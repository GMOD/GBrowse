package Bio::Graphics::Browser2::Render::Slave::Status;
# $Id$

# This module keeps track of when slaves were last contacted and their
# current status. If a slave is down and there are alternatives defined,
# then we will not try contacting it for a while using an exponential
# dropoff.

use strict;
use warnings;
use Fcntl qw(:flock O_RDWR O_CREAT);
use DB_File;
use constant INITIAL_DELAY => 30;   # initially recheck a down server after 30 sec
use constant MAX_DELAY     => 600;  # periodically recheck at 10 min intervals max
use constant DECAY         => 1.5;  # at each subsequent failure, increase recheck interval by this amount
use constant DEBUG         => 0;

sub new {
    my $class      = shift;
    my $path       = shift;
    my $has_dbfilelock = eval "require DB_File::Lock; 1";

    return bless { 
	path       => $path,
	canlock    => $has_dbfilelock,
    },ref $class || $class;
}

sub can_lock { shift->{dbfilelock} }

sub db {
    my $self  = shift;
    my $write = shift;

    return $self->{hash} ||= {} 
           unless $self->can_lock;

    my $locking    = $write ? 'write' : 'read';
    my $mode       = $write ? O_CREAT|O_RDWR : O_RDONLY;
    my $perms      = 0666;
    my $path       = $self->{path};

    my %h;
    tie (%h,'DB_File::Lock',$path,$mode,$perms,$DB_HASH,$locking);
    return \%h;
}

sub status {
    my $self   = shift;
    my $slave  = shift;
    my $db     = shift || $self->db(0);
    defined $db or return 'up';

    my $packed = $db->{$slave};
    return 'up' unless defined $packed;

    my ($status,$last_checked,$check_time) = unpack('CLL',$packed);
    return 'up'   if $status;
    return 'up'   if (time() - $last_checked) >= $check_time;

    warn "$slave is down" if DEBUG;
    return 'down';
}

sub mark_up {
    my $self   = shift;
    my $slave  = shift;
    warn "marking $slave up" if DEBUG;
    my $db     = $self->db(1) or return;

    my $packed = pack('CLL',1,time(),INITIAL_DELAY);
    $db->{$slave} = $packed;
}

sub mark_down {
    my $self   = shift;
    my $slave  = shift;

    warn "marking $slave down" if DEBUG;

    my $db     = $self->db(1) or return;

    unless (my $pack = $db->{$slave}) {
	$db->{$slave} = pack('CLL',0,time(),INITIAL_DELAY);
    } else {
	my ($status,$last_checked,$checktime) = unpack('CLL',$pack);
	my $new_checktime = $checktime * DECAY;
	$new_checktime    = MAX_DELAY if $new_checktime > MAX_DELAY;
	$db->{$slave} = $status ? pack('CLL',0,time(),INITIAL_DELAY)
                                : pack('CLL',0,time(),$checktime*DECAY);
    }

}

# randomly select the first slave that is marked "up"
sub select {
    my $self   = shift;
    my @slaves = @_;

    # open db handle once in order to prevent multiple reopenings
    # of the database
    my $db     = $self->db(0);
    my @up     = grep {$self->status($_,$db) eq 'up'} @slaves;

    warn "up slaves = @up" if DEBUG;

    return $up[rand @up];
}





1;
