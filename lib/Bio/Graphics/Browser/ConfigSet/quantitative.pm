package Bio::Graphics::Browser::ConfigSet::quantitative;

use strict;
use base 'Bio::Graphics::Browser::ConfigSet';

use constant OPTIONS => ( 
  fgcolor         => [qw/black red/],
  bgcolor         => [qw/black blue red green white/],
  glyphs          => [qw/xyplot whisker_plot graded_segments heat_map/],
  height          => [5..20],
  scale           => [0..1],
  linewidth       => [1..3],
  connector       => [0..2],
  connector_color => [qw/black blue green red/],
  max_score       => undef,
  min_score       => undef,
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

