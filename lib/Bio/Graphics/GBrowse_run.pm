package Bio::Graphics::GBrowse_run;

use strict;
use Bio::Graphics::Browser::Options;
use Bio::Graphics::Browser::Util;
use CGI qw(cookie);
use Carp qw(croak);
use Digest::MD5 qw(md5_hex);
use vars qw($VERSION);
use constant DEBUG => 0;

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
  $self->read_cookie();
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

=head2 options()

 Usage   : $obj->options($newval)
 Function: 
 Example : 
 Returns : value of options (a scalar)
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

  my %cookie = cookie("gbrowse_".$self->config->source());
  my $ok = 1;
  if(%cookie){
  BLOCK: {
      $ok &&= $cookie{v} == $VERSION;
      warn "ok 0 = $ok" if DEBUG;
      last unless $ok;

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

      foreach my $k (keys %cookie){
        if($self->options->can($k) and !defined($self->options->$k)){
          $self->options->$k($cookie{$k});
        } else {
          warn "found option $k in cookie, can't handle it yet";
        }
      }
    }
  }

  #unusable cookie.  use default settings
  if(!$ok){
    $self->options->version(100);
    $self->options->width($self->config->setting('default width'));
    $self->options->source($self->config->source);
    $self->options->stp(1);
    $self->options->ins(1);
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

=head2 write_cookie()

 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub write_cookie {
  my ($self,@args) = @_;

# # this is called to flatten the settings into an HTTP cookie
# sub settings2cookie {
#   my $settings = shift;
#   my %settings = %$settings;
#   local $^W = 0;
#   for my $key (keys %settings) {
#     next if $key =~ /^(tracks|features)$/;  # handled specially
#     if (ref($settings{$key}) eq 'ARRAY') {
#       $settings{$key} = join $;,@{$settings{$key}};
#     }
#   }

#   # the "features" and "track" key map to a single array
#   # contained in the "tracks" key of the settings
#   my @array = map {join("/",
# 			$_,
# 			$settings{features}{$_}{visible},
# 			$settings{features}{$_}{options},
# 			$settings{features}{$_}{limit})} @{$settings{tracks}};
#   $settings{tracks} = join $;,@array;
#   delete $settings{features};
#   delete $settings{flip};  # obnoxious for this to persist

#   warn "cookie => ",join ' ',%settings,"\n" if DEBUG;

#   my @cookies;
#   my $source = $CONFIG->source;
#   push @cookies,cookie(-name    => "gbrowse_$source",
# 		       -value   => \%settings,
# 		       -path    => url(-absolute=>1,-path=>1),
# 		       -expires => REMEMBER_SETTINGS_TIME);
#   push @cookies,cookie(-name    => 'gbrowse_source',
# 		       -value   => $source,
# 		       -expires => REMEMBER_SOURCE_TIME);
#   warn "cookies = @cookies" if DEBUG;
#   return \@cookies;
# }

}


#taken from gbrowse.PLS
# # This is called to change the values of the settings
# sub adjust_settings {
#   my $settings = shift;

#   if ( param('label') ) {
#     my @selected = map {/^(http|ftp|das)/ ? $_ : split /[+-]/} param('label');
#     $settings->{features}{$_}{visible} = 0 foreach keys %{$settings->{features}};
#     $settings->{features}{$_}{visible} = 1 foreach @selected;
#   }

#   $settings->{width}  = param('width')   if param('width');
#   # support programmatic upload
#   $settings->{id} = param('id')          if param('id');

#   local $^W = 0;  # kill uninitialized variable warning
#   if (param('ref') &&
#       ( #request_method() eq 'GET'
# 	# || 
#        param('name') eq param('prevname')
# 	|| grep {/zoom|nav|overview/} param())
#      )
#     {
#       $settings->{version} ||= param('version') || '';
#       $settings->{ref}   = param('ref');
#       $settings->{start} = param('start') if param('start') =~ /^[\d-]+/;
#       $settings->{stop}  = param('stop')  if param('stop')  =~ /^[\d-]+/;
#       $settings->{stop}||= param('end')   if param('end')   =~ /^[\d-]+/;
#       $settings->{flip}  = param('flip');
#       zoomnav($settings);
#       $settings->{name} = "$settings->{ref}:$settings->{start}..$settings->{stop}";
#       param(name => $settings->{name});
#     }

#   foreach (qw(name source plugin stp ins head
#               ks sk version h_feat h_type)) {
#     $settings->{$_} = param($_) if defined param($_);
#   }
#   $settings->{name} =~ s/^\s+//; # strip leading
#   $settings->{name} =~ s/\s+$//; # and trailing whitespace

#   if (my @external = param('eurl')) {
#     my %external = map {$_=>1} @external;
#     foreach (@external) {
#       warn "eurl = $_" if DEBUG_EXTERNAL;
#       next if exists $settings->{features}{$_};
#       $settings->{features}{$_} = {visible=>1,options=>0,limit=>0};
#       push @{$settings->{tracks}},$_;
#     }
#     # remove any URLs that aren't on the list
#     foreach (keys %{$settings->{features}}) {
#       next unless /^(http|ftp):/;
#       delete $settings->{features}{$_} unless exists $external{$_};
#     }
#   }

#   # the "q" request overrides name, ref, h_feat and h_type
#   if (my @q = param('q')) {
#     delete $settings->{$_} foreach qw(name ref h_feat h_type);
#     $settings->{q} = [map {split /[+-]/} @q];
#   }

#   if (param('revert')) {
#     warn "resetting defaults..." if DEBUG;
#     set_default_tracks($settings);
#   }

#   elsif (param('reset')) {
#     %$settings = ();
#     Delete_all();
#     default_settings($settings);
#   }

#   elsif (param($CONFIG->tr('Adjust_Order')) && !param($CONFIG->tr('Cancel'))) {
#     adjust_track_options($settings);
#     adjust_track_order($settings);
#   }

# }

1;
