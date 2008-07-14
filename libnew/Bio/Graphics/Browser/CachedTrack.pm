package Bio::Graphics::Browser::CachedTrack;

# $Id: CachedTrack.pm,v 1.5 2008-07-14 23:45:08 lstein Exp $
# This package defines a Bio::Graphics::Browser::Track option that manages
# the caching of track images and imagemaps.

use strict;
use warnings;
use Carp;
use Fcntl ':flock';
use File::Spec;
use File::Path;
use IO::File;
use Digest::MD5 'md5_hex';
use Storable qw(:DEFAULT freeze thaw);

# pending requests get 1 minute before they are considered likely to be defunct
use constant DEFAULT_REQUEST_TIME => 60;
use constant DEFAULT_CACHE_TIME   => 60*60; # 1 hour

# constructor:
# Bio::Graphics::Browser::CachedTrack->new($cache_base_directory,$key_data)
# If $key_data is a scalar, then it is taken to be the literal key.
# Otherwise if it is an arrayref, it is an array of arguments that will be
# converted into the key.
sub new {
    my $self = shift;
    my %args = @_;
    my $base       = $args{-base};
    my $panel_args = $args{-panel_args};
    my $track_args = $args{-track_args};
    my $extra_args = $args{-extra_args};
    my $key        = $args{-key};

    -d $base && -w _ or croak "$base is not writable";

    # If next argument is a scalar, then it is our key to use.
    # Otherwise, it is the data to use to generate a key.
    unless ($key) {
	$key = $self->generate_cache_key(@$panel_args,@$track_args,@$extra_args);
    }

    my $obj = bless { 
	base       => $base ,
	key        => $key,
	panel_args => $panel_args,
	track_args => $track_args,
	extra_args => $extra_args,
    },ref $self || $self;
    return $obj;
}

sub base { shift->{base} }
sub key  { shift->{key}  }
sub panel_args { shift->{panel_args} }
sub track_args { shift->{track_args} }
sub extra_args { shift->{extra_args} }
sub max_time {
    my $self = shift;
    $self->{max_time} = shift if @_;
    return $self->{max_time}   || DEFAULT_REQUEST_TIME;
}
sub cache_time {
    my $self = shift;
    $self->{cache_time} = shift if @_;
    return defined $self->{cache_time} ? $self->{cache_time} : DEFAULT_CACHE_TIME;
}
sub cachedir {
    my $self = shift;
    my $key  = $self->key;
    my @comp = $key =~ /(..)/g;
    my $path = File::Spec->catfile($self->base,@comp[0..2],$key);
    mkpath ($path) unless -e $path;
    die "Can't mkpath($path): $!" unless -d $path;
    return $path;
}
sub dotfile {
    my $self = shift;
    return File::Spec->catfile($self->cachedir,'.lock');
}
sub tsfile {
    my $self = shift;
    return File::Spec->catfile($self->cachedir,'.ts');
}
sub datafile {
    my $self = shift;
    return File::Spec->catfile($self->cachedir,'data');
}

# given an arbitrary set of arguments, make a unique cache key
sub generate_cache_key {
    my $self = shift;
    my @args = map {$_ || ''} grep {!ref($_)} @_;  # the map gets rid of uninit variable warnings
    return md5_hex(sort @args);
}

# lock the cache -- indicates that an update is in process
# we use simple dotfile locking
sub lock {
    my $self    = shift;
    my $dotfile = $self->dotfile;
    my $tsfile  = $self->tsfile;
    if (-e $dotfile) {  # if it exists, then either we are in process or something died
	return if $self->status eq 'PENDING';
    }
    my $f = IO::File->new(">$dotfile") or die "Can't open $dotfile for writing: $!";
    flock $f,LOCK_EX;
    $f->print(time());
    $f->close;
    return 1;
}

sub unlock {
    my $self     = shift;
    my $dotfile  = $self->dotfile;
    unlink $dotfile;
}

sub put_data {
    my $self            = shift;
    my ($gd,$map)       = @_;
    $self->{data}{gd}   = $gd;
    $self->{data}{map}  = $map;
    my $datafile        = $self->datafile;
    store $self->{data},$datafile;
    $self->unlock;
    return;
}

sub get_data {
    my $self      = shift;
    return $self->{data} if $self->{data};
    return unless $self->status eq 'AVAILABLE';

    my $datafile  = $self->datafile;
    $self->{data} = retrieve($datafile);
    return $self->{data};
}

sub gd {
    my $self = shift;
    my $data = $self->get_data or return;
    return $data->{gd};
}

sub map {
    my $self = shift;
    my $data = $self->get_data or return;
    return $data->{map};
}

sub width {
    my $self = shift;
    my $gd   = $self->gd or return;
    return $gd->width;
}

sub height {
    my $self = shift;
    my $gd   = $self->gd or return;
    return $gd->height;
}

# status returns one of four states
# 'EMPTY'     no data available and no requests are pending
# 'PENDING'   a request for the data is pending - current contents invalid
# 'AVAILABLE' data is available and no requests are pending
# 'DEFUNCT'   a request for the data has timed out - current contents invalid
# 'EXPIRED'   there is data, but it has expired
sub status {
    my $self     = shift;
    my $dir      = $self->cachedir;
    my $dotfile  = $self->dotfile;
    my $tsfile   = $self->tsfile;
    my $datafile = $self->datafile;

    # if a dotfile exists then either we are in the midst of updating the
    # contents of the directory, or something has gone wrong and we are
    # waiting forever.
    if (-e $dotfile) {
	-s _ or return 'PENDING';  # size zero means that dotfile has been created but not locked
	my $f = IO::File->new($dotfile) or die "Couldn't open $dotfile: $!";
	flock $f,LOCK_SH;
	my $timestamp = $f->getline();
	die "BAD TIMESTAMP" unless $timestamp;
	$f->close;
	return 'PENDING' if time()-$timestamp < $self->max_time;
	return 'DEFUNCT';
    } elsif (-e $datafile) {
	return $self->expired($datafile) ? 'EXPIRED' : 'AVAILABLE';
    } else {
	return 'EMPTY';
    }
}

sub needs_refresh {
    my $self   = shift;
    my $status = $self->status;
    return 1 if $status eq 'EMPTY';
    return 1 if $status eq 'EXPIRED';
    return 1 if $status eq 'DEFUNCT';
    return;
}

sub expired {
    my $self      = shift;
    my $datafile  = shift;
    my $cache_time= $self->cache_time;
    my $time      = time();

    my $mtime    = (stat($datafile))[9];
    my $elapsed  = $time-$mtime;

    return $elapsed > $cache_time;
}

1;
