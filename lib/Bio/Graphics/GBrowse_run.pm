package Bio::Graphics::GBrowse_run;

use strict;
use base qw(Exporter); #temporary
use Term::ANSIColor;
use Bio::Graphics::Browser::Constants;
use Bio::Graphics::Browser::Options;
use Bio::Graphics::Browser::Util;
use CGI qw(Delete_all cookie param url);
use Carp qw(croak cluck);
use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use vars qw($VERSION @EXPORT_OK); #temporary

@EXPORT_OK = qw(param); #this is a temporary scaffold to clean param() calls from gbrowse.PLS

no warnings 'redefine';
sub param { print(STDERR (caller())[0]."+".(caller())[2]." called param() with: ".join(' ',map {"'$_'"} @_)."\n"); return CGI::param(@_) } #temporary

my $singleton = undef;

sub new {
  return shift->get_instance(@_);
}

sub get_instance {
  my($class,%arg) = @_;

  if(!$singleton){
    $singleton = bless {}, $class;

    $singleton->init(%arg);
  }

  return $singleton;
}

sub init {
  my($self,%arg) = @_;
  foreach my $m (keys %arg){
    $self->$m($arg{$m}) if $self->can($m);
  }

  open_database() or croak "Can't open database defined by source ".$self->config->source;

  $self->options(Bio::Graphics::Browser::Options->new());

  #read VIEW section of config file first
warn "***** read view";
  $self->read_view();
warn "***** display instructions: ".$self->options->display_instructions();
warn "***** display tracks      : ".$self->options->display_tracks();
  #then mask with cookie
warn "***** read cookie";
  $self->read_cookie();
warn "***** display instructions: ".$self->options->display_instructions();
warn "***** display tracks      : ".$self->options->display_tracks();
  #then mask with GET/POST parameters
warn "***** read params";
  $self->read_params();
warn "***** display instructions: ".$self->options->display_instructions();
warn "***** display tracks      : ".$self->options->display_tracks();

  #now store the masked results to the cookie for next time.
  #this will be available via the ->cookie() accessor.
warn "***** make cookie";
  $self->make_cookie();
}

=head2 config()

 Usage   : $obj->config($newval)
 Function: 
 Example : 
 Returns : value of config (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub config {
  my($self,$val) = @_;
  $self->{'config'} = $val if defined($val);
  return $self->{'config'};
}

=head2 cookie()

 Usage   : $obj->cookie($newval)
 Function: 
 Example : 
 Returns : value of cookie (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub cookie {
  my($self,$val) = @_;
  $self->{'cookie'} = $val if defined($val);
  return $self->{'cookie'};
}


=head2 options()

 Usage   : $obj->options($newval)
 Function: 
 Example : 
 Returns : A Bio::Graphics::Browser::Options object
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub options {
  my($self,$val) = @_;
  $self->{'options'} = $val if defined($val);
  return $self->{'options'};
}

sub translate {
  my $self = shift;
  my $tag  = shift;
  my @args = @_;
  return $self->config->tr($tag,@args);
}

=head2 read_cookie()

 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub read_cookie {
  my ($self) = @_;

  my %cookie = CGI::cookie("gbrowse_".$self->config->source());
  #warn Dumper(%cookie);

  my $ok = 1;
  if(%cookie){
  BLOCK: {
      $ok &&= $cookie{v} == $VERSION;
      warn "ok 0 = $ok" if DEBUG;
      last unless $ok;

      foreach my $k (keys %cookie){
        if( $self->options->can($k) ){
          $self->options->$k($cookie{$k});
        } else {
          warn "found option $k in cookie, can't handle it yet";
        }
      }


      $ok &&= defined $cookie{width} && $cookie{width} > 100 && $cookie{width} < 5000;
      $self->options->width($cookie{width});
      warn "ok 1 = $ok" if DEBUG;

      my %ok_sources = map {$_=>1} $self->config->sources;
      $ok &&= $ok_sources{$cookie{source}};
      $self->options->source($cookie{source});
      warn "ok 2 = $ok" if DEBUG;

      # the single "tracks" key of the cookie gets mapped to the
      # "track" and "features" key of the page cookie
      my @features = split $;,$cookie{tracks} if $ok && defined $cookie{tracks};
      my @tracks = ();
      $cookie{features}  = {};
      foreach (@features) {
        warn "feature = $_" if DEBUG;
        my ($label,$visible,$option,$limit) = m!^(.+)/(\d+)/(\d+)/(\d+)$!;
        warn "label = $label, visible = $visible, option = $option, limit = $limit" if DEBUG;
        unless ($label) {   # corrupt cookie; purge it.
          undef $ok;
          last;
        }
        push @tracks,$label;
        $self->options->feature($label,
                                {visible => $visible,
                                 options => $option,
                                 limit   => $limit
                                },
                               );
      }
      warn "ok 3 = $ok" if DEBUG;

      $ok &&= scalar(@tracks) > 0;
      $self->options->tracks(@tracks);
      warn "ok 4 = $ok" if DEBUG;
    }
  }

  #unusable cookie.  use default settings
  if(!$ok){
    $self->options->version(100);
    $self->options->width($self->config->setting('default width'));
    $self->options->source($self->config->source);
    $self->options->head(1);
    $self->options->ks('between');
    $self->options->sk('sorted');
    $self->options->id(md5_hex(rand)); # new identity

    my @labels = $self->config->labels;
    $self->options->tracks(@labels);
    warn "order = @labels" if DEBUG;
    my %default = map {$_=>1} $self->config->default_labels();
    foreach my $label (@labels) {
      my $visible = $default{$label} ? 1 : 0;
      $self->options->feature($_,{visible=>$visible,options=>0,limit=>0});
    }
  }
}

=head2 make_cookie()

 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub make_cookie {
  my ($self) = @_;

#I guess this is ->options() ??
#   my %settings = %$settings;

  my %settings = %{ $self->options() };
  $settings{v} = $VERSION;

  local $^W = 0;

  for my $key (keys %settings) {
    next if $key =~ /^(tracks|features)$/;  # handled specially
    if (ref($settings{$key}) eq 'ARRAY') {
      $settings{$key} = join $;,@{$settings{$key}};
    }
  }

  # the "features" and "track" key map to a single array
  # contained in the "tracks" key of the settings
  my @array = map {join("/",
			$_,
			$settings{features}{$_}{visible},
			$settings{features}{$_}{options},
			$settings{features}{$_}{limit})} @{$settings{tracks}};
  $settings{tracks} = join $;,@array;
  delete $settings{features};
  delete $settings{flip};  # obnoxious for this to persist

  warn "cookie => ",join ' ',%settings,"\n" if DEBUG;

  my @cookies;
  my $source = $self->config->source;
  push @cookies,CGI::cookie(-name    => "gbrowse_$source",
                            -value   => \%settings,
                            -path    => url(-absolute=>1,-path=>1),
                            -expires => REMEMBER_SETTINGS_TIME,
                           );
  push @cookies,CGI::cookie(-name    => 'gbrowse_source',
		       -value   => $source,
		       -expires => REMEMBER_SOURCE_TIME);

  warn "cookies = @cookies" if DEBUG;
  $self->cookie(\@cookies);
}


=head2 read_params()

 Usage   :
 Function: This is called to change the values of the options
           by examining GET/POST parameters
 Example :
 Returns : 
 Args    :


=cut

sub read_params {
  my $self = shift;

  my $options = $self->options();

  if ( CGI::param('label') ) {
    my @selected = map {/^(http|ftp|das)/ ? $_ : split /[+-]/} CGI::param('label');

    #set all visibility to zero (off)
    foreach my $featuretag ($options->feature()){
      my $feature = $options->feature($featuretag);
      $feature->{visible} = 0;
      $options->feature($featuretag,$feature);
    }

    #make selected on (visible)
    foreach my $featuretag (@selected){
      my $feature = $options->feature($featuretag);
      $feature->{visible} = 1;
      $options->feature($featuretag,$feature);
    }
  }

  foreach my $k ( CGI::param() ) {
    if( $self->options->can($k) ){
#      warn "set $k to ".CGI::param($k);
      $self->options->$k(CGI::param($k));
    } else {
      warn "found option $k in GET or POST params, can't handle it yet";
    }
  }

  #
  # these are designed to have a universal set of parameters for file, track, and plugin
  # manipulation.  the base param name (file,track,plugin) indicates the target of the operation,
  # while the action_ param name indicates the action to be performed on the target
  #
  $options->action_file(  CGI::param('action_file'))   if CGI::param('action_file');
  $options->action_track( CGI::param('action_track'))  if CGI::param('action_track');
  $options->action_plugin(CGI::param('action_plugin')) if CGI::param('action_plugin');
  $options->file(  CGI::param('file'))   if CGI::param('file');
  $options->track( CGI::param('track'))  if CGI::param('track');
  $options->plugin(CGI::param('plugin')) if CGI::param('plugin');


  $options->width(CGI::param('width')) if CGI::param('width');
  $options->id(CGI::param('id'))       if CGI::param('id');

  local $^W = 0;  # kill uninitialized variable warning
  if ( CGI::param('ref') && (CGI::param('name') eq CGI::param('prevname') || grep {/zoom|nav|overview/} CGI::param()) ) {
    $options->version(CGI::param('version') || '') unless $options->version();
    $options->ref(CGI::param('ref'));
    $options->start(CGI::param('start')) if CGI::param('start') =~ /^[\d-]+/;
    $options->stop(CGI::param('stop'))   if CGI::param('stop')  =~ /^[\d-]+/;
    $options->stop(CGI::param('end'))    if CGI::param('end')   =~ /^[\d-]+/ && !defined($options->stop());
    $options->flip(CGI::param('flip'));

#FIXME    zoomnav($settings);
    $options->name(sprintf("%s:%s..%s",$options->ref(),$options->start,$options->stop));
  }

  foreach (qw(name source plugin stp head ks sk version h_feat h_type)) {
    $options->$_(CGI::param($_)) if defined CGI::param($_);
  }

  #strip leading/trailing whitespace
  my $name = $options->name();
  $name =~ s/^\s*(.*)\s*$/$1/;
  $options->name($name);

  if (my @external = CGI::param('eurl')) {
    my %external = map {$_=>1} @external;
    foreach (@external) {
      warn "eurl = $_" if DEBUG_EXTERNAL;
      next if $options->feature($_);
      $options->feature($_,{visible=>1,options=>0,limit=>0});
      $options->tracks($options->tracks(),$_);
    }
    # remove any URLs that aren't on the list
    foreach ($options->feature()) {
      next unless /^(http|ftp):/;
      $options->remove_feature($_) unless exists $external{$_};
    }
  }

   # the "q" request overrides name, ref, h_feat and h_type
  if (my @q = CGI::param('q')) {
    $options->unset($_) foreach qw(name ref h_feat h_type);
    $options->q( [map {split /[+-]/} @q] );
  }

  if (CGI::param('revert')) {
    warn "resetting defaults..." if DEBUG;
    #FIXME was this ported??? set_default_tracks($settings);
  } elsif (CGI::param('reset')) {
    $options->unset($_) foreach keys %{ $options }; #yeah, yeah, this is bad OOP.  add a slots() accessor to Options if you really care.
    Delete_all();
    #FIXME was this ported??? default_settings($settings);
  } elsif (CGI::param($self->translate('adjust_order')) && !CGI::param($self->translate('cancel'))) {
    #FIXME adjust_track_options($settings);
    #FIXME adjust_track_order($settings);
  }
}

sub read_view {
  my($self) = shift;

  ###FIXME there is certainly a better way to get this data, but i'm in a hurry right now.
  if( $self->config()->{conf}{$self->config()->source()}{data}{config}{VIEW} ){
    my %o = %{ $self->config()->{conf}{$self->config()->source()}{data}{config}{VIEW} };
    #foreach potential view parameter
    foreach my $k (keys %o){
      if( $self->options->can($k) ) {
#        warn "setting view option $k to $o{$k}";
        $self->options->$k($o{$k});
      } else {
        warn "found option $k in config file VIEW section, can't handle it yet";
      }
    }
  }
}


#NOT YET PORTED OUT OF gbrowse.PLS
# # reorder @labels based on settings in the 'track.XXX' parameters
# sub adjust_track_order {
#   my $settings = shift;

#   my @labels  = $BROWSER->options->tracks();
#   warn "adjust_track_order(): labels = @labels" if DEBUG;

#   my %seen_it_already;
#   foreach (grep {/^track\./} CGI::param()) {
#     warn "$_ =>",CGI::param($_) if DEBUG;
#     next unless /^track\.(\d+)/;
#     my $track = $1;
#     my $label   = CGI::param($_);
#     next unless length $label > 0;
#     next if $seen_it_already{$label}++;
#     warn "$label => track $track" if DEBUG;

#     # figure out where features currently are
#     my $i = 0;
#     my %order = map {$_=>$i++} @labels;

#     # remove feature from wherever it is now
#     my $current_position = $order{$label};
#     warn "current position of $label = $current_position" if DEBUG;
#     splice(@labels,$current_position,1);

#     warn "new position of $label = $track" if DEBUG;
#     # insert feature into desired position
#     splice(@labels,$track,0,$label);
#   }
#   $BROWSER->options->tracks(@labels);
# }

# sub adjust_track_options {
#   my $settings = shift;
#   foreach (grep {/^option\./} CGI::param()) {
#     my ($track)   = /(\d+)/;
#     my $feature   = $BROWSER->options->{tracks}[$track];
#     my $option    = CGI::param($_);
#     $BROWSER->options->{features}{$feature}{options} = $option;
#   }
#   foreach (grep {/^limit\./} CGI::param()) {
#     my ($track)   = /(\d+)/;
#     my $feature   = $BROWSER->options->{tracks}[$track];
#     my $option    = CGI::param($_);
#     $BROWSER->options->{features}{$feature}{limit} = $option;
#   }
#   foreach (@{$BROWSER->options->{tracks}}) {
#     $BROWSER->options->{features}{$_}{visible} = 0;
#   }

#   foreach (CGI::param('track.label')) {
#     $BROWSER->options->{features}{$_}{visible} = 1;
#   }
# }

1;
