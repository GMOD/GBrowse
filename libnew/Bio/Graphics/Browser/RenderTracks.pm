package Bio::Graphics::Browser::RenderTracks;

use strict;
use warnings;

use Bio::Graphics;

# when we load, we set a global indicating the LWP::Parallel::UserAgent is available
my $LPU_AVAILABLE;
my $STO_AVAILABLE;

sub new {
  my $class = shift;
  my ($data_source,$page_settings) = @_;

  my $self  = bless {},ref $class || $class;
  $self->source($data_source);
  $self->settings($page_settings);
  return $self;
}

sub source {
  my $self = shift;
  my $d = $self->{source};
  $self->{source} = shift if @_;
  return $d;
}

sub settings {
  my $self = shift;
  my $d = $self->{settings};
  $self->{settings} = shift if @_;
  return $d;
}

# This renders the named tracks and returns the images and image maps
# input:
#   options hash: { tracks         => [array of track names],
#                   third_party    => [third party annotations (Bio::DasI objects)],
#                 }
# output:
# a hash of 
# { $track_name => { gd   => $gd_object,
#                   map  => $image_map }
# }
#
sub render_tracks {
  my $self    = shift;
  my $options = shift;

  my $source   = $self->source;
  my $settings = $self->settings;

  my @tracks                  = @{$options->{tracks}};
  my @third_party             = @{$options->{third_party}};

  my $results = {};

  # if the "renderfarm" option is set, then we scatter the requests across multiple remote URLs
  my $renderfarm;
  if ($source->global_setting('renderfarm')) {
    $LPU_AVAILABLE = eval { require LWP::Parallel::UserAgent; } unless defined $LPU_AVAILABLE;
    $STO_AVAILABLE = eval { require Storable; 1; }              unless defined $STO_AVAILABLEL;
    if ($LPU_AVAILABLE && $STO_AVAILABLE) {
      $renderfarm = 1;
    } else {
      warn "The renderfarm setting requires the LWP::Parallel::UserAgent and Storable modules, but one or both are missing. Reverting to local rendering.\n";
    }
  }

  if ($renderfarm) {
    my %remote;

    for my $track (@tracks) {
      my $host  = $source->semantic_setting($track => 'remote renderer');
      $host   ||= $self->local_renderer_url;
      $remote{$host}{$track}++;
    }

    $results    = $self->render_remotely(renderers   => \%remote,
					 source      => $source,
					 settings    => $settings,
					);
  }

  else {
    for my $track_label (@tracks) {
      my ($gd,$map) = $self->render_local(track => $track_label,
					  source   => $source,
					  settings => $settings);
      $results->{$track_label}{gd}  = $gd;
      $results->{$track_label}{map} = $map;
    }
  }

  # add third-party data (currently always handled locally and serialized)
  for my $third_party (@third_party) {
    my $name = $third_party->name or next;  # every third party feature has to have a name now
    $results->{$name} = $self->render_third_party(feature_file => $third_party,
						  source       => $source,
						  settings     => $settings);
  }

  # oh, ouch, we've got to do something with the plugins... or maybe they're handled by the third party hash?

  return $results;
}

# This routine is called to hand off the rendering to a remote renderer. The remote processor does not have to
# have a copy of the config file installed; the entire DataSource object is sent to it in serialized form via
# POST. It returns a serialized hash consisting of the GD object and the imagemap.
# INPUT
#    {renderers => {$remote_url}{$track},
#     source    => $datasource
#     settings  => $page_settings }
#
# RETURN
#    hash of { $track_label => { gd => $gd object, map => $imagemap } }
#
#
# POST outgoing arguments:
#    datasource => serialized Bio::Graphics::Browser::DataSource
#    settings   => serialized state hash (from the session)
#    tracks     => serialized list of track names to render
#
# POST incoming arguments
#    [[$track,$gd,$imagemap],[$track,$gd,$imagemap],...]
#
# reminder: segment can be found in the settings as $settings->{ref,start,stop,flip}
sub render_remotely {
  my $self    = shift;
  my $options = shift;

  eval { require 'HTTP::Request::Common' } unless HTTP::Request::Common->can('POST');

  my $renderers= $options->{renderers};  # format: {$remote_url}{$track}
  my $dsn      = $options->{source};
  my $settings = $options->{settings};

  # serialize the data source and settings
  my $s_dsn = Storable::freeze($dsn);
  my $s_set = Storable::freeze($settings);

  my $ua = LWP::Parallel::UserAgent->new;
  $ua->in_order(0);
  $ua->nonblock(1);

  for my $url (keys %$renderers) {
    my @tracks  = keys %{$renderers->{$url}};
    my $s_track  = Storable::freeze(\@tracks);
    my $request = POST($url,
		       [tracks     => $s_track,
			settings   => $s_set
			datasource => $s_dsn]);
    my $error = $ua->register($request);
    if ($error) { warn "Could not send request to $url: ",$error->as_string }
  }

  my $timeout = $dsn->global_setting('timeout') || 20;
  my $results = $ua->wait($timeout);

  my %track_results;
  foreach (keys %$results) {
    my $response = $results->{$_}->response;
    unless ($response->is_success) {
      warn $results->request->uri,"; fetch failed: ",$response->status_line;
      next;
    }
    my $content = $response->content;
    my $tracks = Storable::thaw($content);
    for my $track_tuple (@$tracks) {
      my ($track_name,$gd,$imagemap) = @$track_tuple;
      $track_results{$track_name} = [$gd,$imagemap];
    }
  }
  return \%track_results;
}

sub local_renderer_url {
  my $self     = shift;
  my $self_uri = CGI::url(-absolute=>1);
  $self_uri    =~ s/[^\/]+$/gbrowse_render/;  # BUG? hard-coded renderer name here - maybe not a great idea
  return $self_uri;
}

sub render_local {
  my $self = shift;
  my $track_renderer = 
}

1;

