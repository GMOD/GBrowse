package Bio::Graphics::Browser::CachedTrack;

# $Id: CachedTrack.pm,v 1.1 2008-04-11 14:32:51 lstein Exp $
# This package defines a Bio::Graphics::Browser::Track option that manages
# the caching of track images and imagemaps.

use strict;
use warnings;
use Carp;
use File::Spec;
use File::Path;
use Digest::MD5 'md5_hex';
use Storable qw(:DEFAULT freeze thaw);

# pending requests get 1 minute before they are considered likely to be defunct
use constant MAX_REQUEST_TIME => 60;

# constructor:
# Bio::Graphics::Browser::CachedTrack->new($cache_base_directory,$key_data)
# If $key_data is a scalar, then it is taken to be the literal key.
# Otherwise if it is an arrayref, it is an array of arguments that will be
# converted into the key.
sub new {
    my $self = shift;
    my $base = shift;   # path where our data will be cached
    -d $base && -w _ or croak "$base is not writable";

    # If next argument is a scalar, then it is our key to use.
    # Otherwise, it is the data to use to generate a key.
    my $key = shift;
    if (ref $key && ref $key eq 'ARRAY') {
	$key = $self->generate_cache_key(@{$key});
    }

    return bless { 
	base => $base ,
	key  => $key,
    },ref $self || $self;
}

sub base { shift->{base} }
sub key  { shift->{key}  }
sub max_time {
    my $self = shift;
    $self->{max_time} = shift if @_;
    return $self->{max_time} || MAX_REQUEST_TIME;
}
sub cachedir {
    my $self = shift;
    my $key  = $self->key;
    my @comp = $key =~ /(..)/g;
    my $path = File::Spec->catfile($self->base,@comp);
    mkpath ($path) unless -e $path;
    return $path;
}
sub dotfile {
    my $self = shift;
    return File::Spec->catfile($self->cachedir,'.lock');
}
sub datafile {
    my $self = shift;
    return File::Spec->catfile($self->cachedir,'data');
}

# given an arbitrary set of arguments, make a unique cache key
sub cache_key {
    my $self = shift;
    my @args = map {$_ || ''} grep {!ref($_)} @_;  # the map gets rid of uninit variable warnings
    return md5_hex(@args);
}

# lock the cache -- indicates that an update is in process
# we use simple dotfile locking
sub lock {
    my $self    = shift;
    my $dotfile = $self->dotfile;
    if (-e $dotfile) {  # if it exists, then either we are in process or something died
	return if $self->status eq 'PENDING';
    }
    open F,">$dotfile" or croak "Can't open $dotfile: $!";
    print F time();
    close F;
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
sub status {
    my $self     = shift;
    my $dir      = $self->cachedir;
    my $dotfile  = $self->dotfile;
    my $datafile = $self->datafile;

    # if a dotfile exists then either we are in the midst of updating the
    # contents of the directory, or something has gone wrong and we are
    # waiting forever.
    if (-e $dotfile) {  
	open F,$dotfile or croak "Couldn't open $dotfile: $!";
	my $timestamp = <F>;
	close F;
	return 'PENDING' if time()-$timestamp < $self->max_time;
	return 'DEFUNCT';
    } elsif (-e $datafile) {
	return 'AVAILABLE';
    } else {
	return 'EMPTY';
    }
}

1;
