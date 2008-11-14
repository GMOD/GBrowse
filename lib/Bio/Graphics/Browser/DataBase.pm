package Bio::Graphics::Browser::DataBase;

# This module maintains a cache of opened genome databases
# keyed by the database module name and the parameters
# passed to new(). It is intended to improve performance
# on in-memory databases and other databases that have
# a relatively slow startup time.

=head1 NAME

Bio::Graphics::Browser::DataBase -- A simple cache for database handles

=head1 SYNOPSIS


=head1 DESCRIPTION

=head2 METHODS

=cut

use strict;
use warnings;
use Data::Dumper 'Dumper';

my %DB;  #this is the cache

sub open_database {
  my $self  = shift;
  my ($adaptor,@argv) = @_;

  my $key   = Dumper($adaptor,@argv);
  return $DB{$key} if exists $DB{$key};

  $DB{$key} = eval {$adaptor->new(@argv)} or warn $@;
  die "Could not open database: $@" unless $DB{$key};

  $DB{$key}->strict_bounds_checking(1) if $DB{$key}->can('strict_bounds_checking');
  $DB{$key}->absolute(1)               if $DB{$key}->can('absolute');
  $DB{$key};
}

1;
