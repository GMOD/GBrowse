package Bio::Graphics::Browser::Options;

use strict;
use Bio::Graphics::Browser::Util;

sub new {
  my($class, %arg) = @_;
  my $self = bless {}, $class;
  $self->init(%arg);
  return $self;
}

sub init {
  my($self,%arg) = @_;
  foreach my $m (keys %arg){
    $self->$m($arg{$m}) if $self->can($m);
  }

  open_database();
  return 1;
}

=head2 feature()

 Usage   : $obj->feature($newval)
 Function: hash ref which has one element for each feature type.
           Its values are hashrefs with subkeys {visible} and {options}.
           A true value in {visible} indicates that the feature is active.
           The values of {options} are integers with the following meaning:
           0=auto, 1=force no bump, 2=force bump, 3=force label.
 Example : 
 Returns : a hash or undef
 Args    : FIXME


=cut

sub feature {
  my($self,$tag,$val) = @_;

  if(!defined($tag)){
    return undef
  } elsif(!defined($val) && defined($self->{'feature'}{$tag})){
    return %{ $self->{'feature'}{$tag} };
  } elsif(defined($val) and ref($val) eq 'HASH') {
    $self->{'feature'}{$tag} = $val;
  } else {
    return undef;
  }
}

=head2 h_feat()

 Usage   : $obj->h_feat($newval)
 Function: search term for hiliting
 Example : 
 Returns : value of h_feat (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub h_feat {
  my($self,$val) = @_;
  $self->{'h_feat'} = $val if defined($val);
  return $self->{'h_feat'};
}

=head2 h_type()

 Usage   : $obj->h_type($newval)
 Function: search type for hiliting
 Example : 
 Returns : value of h_type (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub h_type {
  my($self,$val) = @_;
  $self->{'h_type'} = $val if defined($val);
  return $self->{'h_type'};
}

=head2 head()

 Usage   : $obj->head($newval)
 Function: show header and footer
 Example : 
 Returns : value of head (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub head {
  my($self,$val) = @_;
  $self->{'head'} = $val if defined($val);
  return $self->{'head'};
}

=head2 id()

 Usage   : $obj->id($newval)
 Function: unique cookie-based ID for this user
 Example : 
 Returns : value of id (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub id {
  my($self,$val) = @_;
  $self->{'id'} = $val if defined($val);
  return $self->{'id'};
}

=head2 ins()

 Usage   : $obj->ins($newval)
 Function: show instructions
 Example : 
 Returns : value of ins (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub ins {
  my($self,$val) = @_;
  $self->{'ins'} = $val if defined($val);
  return $self->{'ins'};
}

=head2 ks()

 Usage   : $obj->ks($newval)
 Function: position of key (beneath or between)
 Example : 
 Returns : value of ks (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub ks {
  my($self,$val) = @_;
  $self->{'ks'} = $val if defined($val);
  return $self->{'ks'};
}

=head2 name()

 Usage   : $obj->name($newval)
 Function: name of a landmark to search for (e.g. keyword search)
 Example : 
 Returns : value of name (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub name {
  my($self,$val) = @_;
  $self->{'name'} = $val if defined($val);
  return $self->{'name'};
}

=head2 plugin()

 Usage   : $obj->plugin($newval)
 Function: last accessed plugin
 Example : 
 Returns : value of plugin (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub plugin {
  my($self,$val) = @_;
  $self->{'plugin'} = $val if defined($val);
  return $self->{'plugin'};
}

=head2 q()

 Usage   : $obj->q($newval)
 Function: A search term passed in the URL -- there may be multiple ones
 Example : 
 Returns : value of q (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub q {
  my($self,$val) = @_;
  $self->{'q'} = $val if defined($val);
  return $self->{'q'};
}

=head2 ref()

 Usage   : $obj->ref($newval)
 Function: sequence landmark reference ID (once found)
 Example : 
 Returns : value of ref (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub ref {
  my($self,$val) = @_;
  $self->{'ref'} = $val if defined($val);
  return $self->{'ref'};
}

=head2 sk()

 Usage   : $obj->sk($newval)
 Function: 
 Example : 
 Returns : value of sk (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub sk {
  my($self,$val) = @_;
  $self->{'sk'} = $val if defined($val);
  return $self->{'sk'};
}

=head2 source()

 Usage   : $obj->source($newval)
 Function: symbolic name of database/configuration to use
 Example : 
 Returns : value of source (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub source {
  my($self,$val) = @_;
  $self->{'source'} = $val if defined($val);
  return $self->{'source'};
}

=head2 start()

 Usage   : $obj->start($newval)
 Function: start of range relative to ref
 Example : 
 Returns : value of start (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub start {
  my($self,$val) = @_;
  $self->{'start'} = $val if defined($val);
  return $self->{'start'};
}

=head2 stop()

 Usage   : $obj->stop($newval)
 Function: stop of range relative to ref
 Example : 
 Returns : value of stop (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub stop {
  my($self,$val) = @_;
  $self->{'stop'} = $val if defined($val);
  return $self->{'stop'};
}

=head2 stp()

 Usage   : $obj->stp($newval)
 Function: 
 Example : 
 Returns : value of stp (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub stp {
  my($self,$val) = @_;
  $self->{'stp'} = $val if defined($val);
  return $self->{'stp'};
}

=head2 tracks()

 Usage   : $obj->tracks($newval1,$newval2)
 Function: array which has one element for each track on the
           display.  The value of each element indicates what
           track to display in that position using the configuration
           key code.  For example: [HMM,BAB,GB]
           means display the "HMM", "BAB" and "GB" features in that
           order.  Uploaded feature data is named "UPLOAD",
           External URL tracks are indicated using the URL of the data.
 Example : 
 Returns : value of tracks (a list)
 Args    : on set, new values (a list or undef, optional)


=cut

sub tracks {
  my($self,@val) = @_;
  @{ $self->{'tracks'} } = @val if defined(@val);
  return defined $self->{'tracks'} ? @{ $self->{'tracks'} } : ();
}

=head2 version()

 Usage   : $obj->version($newval)
 Function: 
 Example : 
 Returns : value of version (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub version {
  my($self,$val) = @_;
  $self->{'version'} = $val if defined($val);
  return $self->{'version'};
}

=head2 width()

 Usage   : $obj->width($newval)
 Function: 
 Example : 
 Returns : value of width (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub width {
  my($self,$val) = @_;
  $self->{'width'} = $val if defined($val);
  return $self->{'width'};
}

1;
