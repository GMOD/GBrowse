package Bio::Graphics::Browser::Render::Slave::Status;
# $Id: Status.pm,v 1.1 2008-12-17 19:56:56 lstein Exp $

# This module keeps track of when slaves were last contacted and their
# current status. If a slave is down and there are alternatives defined,
# then we will not try contacting it for a while using an exponential
# dropoff.

use strict;
use warnings;

use constant INITIAL_DELAY => 5;  # initially recheck server after 5s
use constant DECAY         => 1.5;

sub new {
    my $class      = shift;
    my %args       = @_;
    my $path       = $args{dir};
}

sub status {
    my $self   = shift;
    my $slave  = shift;
    my $db     = $self->db;
    my $packed = $db->{$slave};
    return 'ok' unless defined $packed;

    my ($status,$last_checked,$check_time) = unpack('CLL',$packed);
    return 'up'   if $status;
    return 'down' if time() - $last_checked < $check_time;
    return 'down';
}

sub mark_up {
    my $self   = shift;
    my $slave  = shift;
    my $db     = $self->db;
    my $packed = pack('CLL',1,time(),INITIAL_DELAY);
    $db->{$slave} = $packed;
}

sub mark_down {
    my $self   = shift;
    my $slave  = shift;
    my $db     = shift;

    unless (my $pack = $db->{$slave}) {
	$db->{$slave} = pack('CLL',0,time(),INITIAL_DELAY);
    } else {
	my ($status,$last_checked,$checktime) = unpack('CLL',$pack);
	$db->{$slave} = $status ? pack('CLL',0,time(),INITIAL_DELAY)
                                : pack('CLL',0,time(),$checktime*DECAY);
    }
}





1;
