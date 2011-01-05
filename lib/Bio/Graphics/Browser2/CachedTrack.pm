package Bio::Graphics::Browser2::CachedTrack;

# $Id$
# This package defines a Bio::Graphics::Browser2::Track option that manages
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
# Bio::Graphics::Browser2::CachedTrack->new($cache_base_directory,$key_data)
# If $key_data is a scalar, then it is taken to be the literal key.
# Otherwise if it is an arrayref, it is an array of arguments that will be
# converted into the key.
sub new {
    my $self = shift;
    my %args = @_;
    my $cache_base = $args{-cache_base};
    my $panel_args = $args{-panel_args};
    my $track_args = $args{-track_args};
    my $extra_args = $args{-extra_args};
    my $cache_time = $args{-cache_time};
    my $key        = $args{-key};

    -d $cache_base && -w _ or croak "$cache_base is not writable";

    # If next argument is a scalar, then it is our key to use.
    # Otherwise, it is the data to use to generate a key.
    unless ($key) {
	$key = $self->generate_cache_key(@$panel_args,@$track_args,@$extra_args);
    }

    my $obj = bless { 
	cache_base => $cache_base ,
	key        => $key,
	panel_args => $panel_args,
	track_args => $track_args,
	extra_args => $extra_args,
	cache_time => defined $cache_time ? $cache_time : DEFAULT_CACHE_TIME,
    },ref $self || $self;
    return $obj;
}

sub cache_base { shift->{cache_base} }
sub lock_base  { shift->{lock_base} }
sub key        { shift->{key}  }
sub panel_args { shift->{panel_args} }
sub track_args { shift->{track_args} }
sub extra_args { shift->{extra_args} }
sub max_time {
    my $self = shift;
    $self->{max_time} = shift if @_;
    return $self->{max_time} || DEFAULT_REQUEST_TIME;
}
sub cache_time {
    my $self = shift;
    my $d    = $self->{cache_time};
    $self->{cache_time} = shift if @_;
    return $d;
}
sub cachedir {
    my $self = shift;
    my $key  = $self->key;
    my @comp = $key =~ /(..)/g;
    my $path = File::Spec->catfile($self->cache_base,@comp[0..2],$key);
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

sub errorfile {
    my $self = shift;
    return File::Spec->catfile($self->cachedir,'error');
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
    $f->print($$,' ',time());     # PID<sp>timestamp
    $f->close;
    return 1;
}

sub unlock {
    my $self     = shift;
    my $dotfile  = $self->dotfile;
    unlink $dotfile;
}

sub flag_error {
    my $self = shift;
    my $msg  = shift;
    my $errorfile = $self->errorfile;
    open my $fh,'>',$errorfile or die;
    print $fh $msg;
    close $fh;
    $self->unlock;
}

sub errstr {
    my $self = shift;
    my $errorfile = $self->errorfile;
    open my $fh,'<',$errorfile or return;
    while (my $msg = <$fh>) {
	chomp $msg;
	next if $msg =~ /EXCEPTION/; # bioperl error header
	$msg =~ s/MSG://;            # more bioperl cruft
	return $msg if $msg;
    }
    return 'unknown';
}

sub put_data {
    my $self              = shift;
    my ($gd,$map,$titles) = @_;
    $self->{data}{gd}     = $gd->can('gd2') ? $gd->gd2 : $gd;
    $self->{data}{map}    = $map;
    $self->{data}{titles} = $titles;
    my $datafile          = $self->datafile;
    store $self->{data},$datafile;
    $self->unlock;
    unlink $self->errorfile if -e $self->errorfile;
    return;
}

sub get_data {
    my $self           = shift;
    my $ignore_expires = shift;
    return $self->{data} if $self->{data};

    my $status = $self->status;
    if ( ($status eq 'AVAILABLE') or 
	 ($status eq 'EXPIRED' && $ignore_expires)) {
	return $self->_get_data();
    } else {
	return;
    }
}

sub _get_data {
    my $self = shift;
    my $datafile  = $self->datafile;
    $self->{data} = retrieve($datafile);
    return $self->{data};
}

sub gd {
    my $self = shift;
    my $data = $self->get_data or return;

    # The ? statement here accomodates the storage of GD::SVG objects,
    # which do not support the call to newFromPngData.
    my $gd = (ref($data->{gd}) 
	    && ref($data->{gd})=~/^GD/)
	? $data->{gd}
        : GD::Image->newFromGd2Data($data->{gd});
    return $gd;
}

sub map {
    my $self = shift;
    my $data = $self->get_data or return;
    return $data->{map};
}

sub titles {
    my $self = shift;
    my $data = $self->get_data or return;
    return $data->{titles};
}

sub width {
    my $self = shift;
    my $gd   = $self->gd or return;
    return ($gd->getBounds)[0];
}

sub height {
    my $self = shift;
    my $gd   = $self->gd or return;
    return ($gd->getBounds)[1];
}

# status returns one of four states
# 'EMPTY'     no data available and no requests are pending
# 'PENDING'   a request for the data is pending - current contents invalid
# 'AVAILABLE' data is available and no requests are pending
# 'DEFUNCT'   a request for the data has timed out - current contents invalid
# 'EXPIRED'   there is data, but it has expired
# 'ERROR'     an error occurred, and data will never be available
sub status {
    my $self      = shift;
    my $dir       = $self->cachedir;
    my $dotfile   = $self->dotfile;
    my $tsfile    = $self->tsfile;
    my $datafile  = $self->datafile;
    my $errorfile = $self->errorfile;

    # if a dotfile exists then either we are in the midst of updating the
    # contents of the directory, or something has gone wrong and we are
    # waiting forever.
    if (-e $dotfile) {
	-s _ or return 'PENDING';  # size zero means that dotfile has been created but not locked
	my $f = IO::File->new($dotfile) 
	    or return 'AVAILABLE'; # dotfile disappeared, so data has just become available
	flock $f,LOCK_SH;
	my ($pid,$timestamp) = split /\s+/,$f->getline();
	$f->close;
	return 'DEFUNCT' unless $timestamp;
	unless (kill 0=>$pid) {
	    $self->flag_error('the rendering process crashed');
	    return 'ERROR';
	}
	return 'PENDING' if time()-$timestamp < $self->max_time;
	$self->flag_error('timeout; try viewing a smaller region');
	return 'ERROR';
    } elsif (-e $datafile) {
	return $self->expired($datafile) ? 'EXPIRED' : 'AVAILABLE';
    } elsif (-e $errorfile) {
	return 'ERROR';
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
    return 0 if ( $mtime and not $cache_time);
    return $elapsed > $cache_time;
}

1;
