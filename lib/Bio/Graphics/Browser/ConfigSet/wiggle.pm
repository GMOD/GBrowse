package Bio::Graphics::Browser::ConfigSet::wiggle;
use strict;
use base 'Bio::Graphics::Browser::ConfigSet';

use constant OPTIONS => ( 
  glyph              => [qw/wiggle_xyplot wiggle_density/],
  fgcolor            => [qw/black red/],
  bgcolor            => [qw/black blue red green white/],
  smoothing          => [qw/mean max min median none/],
  'smoothing window' => [map {$_*10} 1..10,15,20,30,40,50],
  min_score          => undef,
  max_score          => undef,
  neg_color          => [qw/red blue/],
  scale_color        => [qw/red black blue/],
  clip               => [0,1],  
  #etc...
    );

sub new {
  my $class = shift;
  my $self = bless {}, ref $class || $class;
  $self->initialize();
  return $self;
}

# set initial options -- can be reset later
sub initialize {
  my $self = shift;
  my %options = OPTIONS;
  for my $option (keys %options) {
    $self->{$option} = $options{$option};
  }
}


1;


