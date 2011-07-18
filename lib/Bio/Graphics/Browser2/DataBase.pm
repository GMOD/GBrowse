package Bio::Graphics::Browser2::DataBase;

# This module maintains a cache of opened genome databases
# keyed by the database module name and the parameters
# passed to new(). It is intended to improve performance
# on in-memory databases and other databases that have
# a relatively slow startup time.

=head1 NAME

Bio::Graphics::Browser2::DataBase -- A simple cache for database handles

=head1 SYNOPSIS


=head1 DESCRIPTION

=head2 METHODS

=cut

use strict;
use warnings;
use Data::Dumper 'Dumper';
use constant DEBUG=>0;

# Cache this many databases in a LRU cache.
# If you are getting too many open files errors, then set this
# lower.
use constant CACHE_SIZE => 100;  

my $CACHE = LRUCache->new(CACHE_SIZE);

sub open_database {
  my $self  = shift;
  my ($adaptor,@argv) = @_;

  my $key   = Dumper($adaptor,@argv);
  my $db    = $CACHE->get($key);
  return $db if defined $db;

  my @caller = caller(1);
  warn "[$$] open database @argv from @caller" if DEBUG;
  $db = eval {$adaptor->new(@argv)};

  if (!$db && $@ =~ /too many open files/) {
      warn "Too many open databases. Clearing and trying again.\n";
      warn "You may wish to adjust the CACHE_SIZE constant in Bio/Graphics/Browser2/DataBase.pm";
      $CACHE->clear();  # last ditch attempt to free filehandles
      $db = eval {$adaptor->new(@argv)};
  }
  die "Could not open database: $@" unless $db;

  $db->strict_bounds_checking(1) if $db->can('strict_bounds_checking');
  $db->absolute(1)               if $db->can('absolute');
  $CACHE->set($key,$db);
  $db;
}

sub delete_database {
    my $self = shift;
    my $key  = Dumper(@_);
    $CACHE->delete($key);
}

=item Bio::Graphics::Browser2::DataBase->clone_databases()

Call this after a fork in the child process to make sure that all open
databases have had a chance to clone themselves if they need
to. Otherwise you will get random database failures.

=cut

sub clone_databases {
    my $self = shift;
    eval {$_->clone()} 
       foreach $CACHE->values();
}


package LRUCache;

sub new {
    my $self     = shift;
    my $maxopen  = shift || 20;
    return bless {maxopen   => $maxopen,
		  curopen   => 0,
		  cacheseq  => {},
		  cachedata => {},
    },ref $self || $self;
}

sub delete {
    my $self = shift;
    my $key  = shift;
    delete $self->{cachedata}{$key};
    delete $self->{cacheseq}{$key};
    $self->{curopen}--;
}

sub get {
    my $self = shift;
    my $key  = shift;
    my $obj  = $self->{cachedata}{$key};
    return unless $obj;
    $self->{cacheseq}{$key}++;
    return $obj;
}

sub set {
    my $self       = shift;
    my ($key,$obj) = @_;

    if (exists $self->{cachedata}{$key}) {
	$self->{cachedata}{$key} = $obj;
	$self->{cacheseq}{$key}  = 1;
	return;
    }

    if ($self->{curopen} >= $self->{maxopen}) {
	my @lru = sort {$self->{cacheseq}{$a} <=> $self->{cacheseq}{$b}} 
	     keys %{$self->{cachedata}};
	splice(@lru, $self->{maxopen} / 3);
	$self->{curopen} -= @lru;
	foreach (@lru) {
	    delete $self->{cachedata}{$_};
	    delete $self->{cacheseq}{$_};
	}

	warn "garbage collecting done, values = ",join ' ',$self->values 
	    if Bio::Graphics::Browser2::DataBase::DEBUG;
    }

    $self->{cacheseq}{$key}=1;
    $self->{curopen}++;
    $self->{cachedata}{$key} = $obj;
}

sub keys {
    my $self = shift;
    return keys %{$self->{cachedata}};
}

sub values {
    my $self = shift;
    return values %{$self->{cachedata}};
}

sub clear {
    my $self = shift;
    $self->{cacheseq}  = {};
    $self->{cachedata} = {};
}

1;
