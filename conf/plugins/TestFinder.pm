package Bio::Graphics::Browser::Plugin::TestFinder;

use strict;
use warnings;
use base 'Bio::Graphics::Browser::Plugin';

sub name { 'TypeFinder'}

# return all objects of type 'motif'
sub find {
  my $self     = shift;
  my $db       = $self->database;
  my $query    = $self->page_settings->{name} or return;
  my @features = $db->features(-type=>$query);
  return \@features;
}

1;
