package Bio::DB::Das::BioSQL::Iterator;

sub new {
  my $package  = shift;
  my $features = shift;
  return bless $features,$package;
}

sub next_seq {
  my $self = shift;
  return unless @$self;
  return shift @$self;
}

1;