package Bio::Graphics::Browser::RemoteSet;
# API for handling a set of remote annotation sources

use strict;
use Bio::Graphics::Browser;
use Bio::Graphics::Browser::Util 'error';
use CGI 'cookie','param','unescape';
use Digest::MD5 'md5_hex';
use Text::Shellwords;

use constant URL_FETCH_TIMEOUT    => 5;  # five seconds max!
use constant URL_FETCH_MAX_SIZE   => 1_000_000;  # don't accept any files larger than 1 Meg

use constant DEBUG=>0;

my $UA;

sub new {
  my $package = shift;
  my $config        = shift;
  my $page_settings = shift;
  my $self = bless {
		    config        => $config,
		    page_settings => $page_settings,
		    sources       => {},
		   },ref $package || $package;
  for my $track (keys %{$page_settings->{features}}) {
    next unless $track =~ /^(http|ftp|das):/;
    $self->add_source($track);
  }
  $self;
}

sub config        { shift->{config}          }
sub page_settings { shift->{page_settings}   }
sub sources       { keys %{shift->{sources}} }

sub add_source {
  my $self   = shift;
  my $source = shift;
  $self->{sources}{$source}++;
}

sub delete_source {
  my $self   = shift;
  my $source = shift;
  delete $self->{sources}{$source};
}

sub set_sources {
  my $self     = shift;
  my $sources  = shift;

  my $settings = $self->page_settings;
  for (@$sources) {
    next if $_ eq '';
    $self->add_source($_);
    $settings->{features}{$_}{visible}++ unless exists $settings->{features}{$_};
  }

  # remove unused tracks
  my $adjusted;
  for my $track (keys %{$settings->{features}}) {
     next unless $track =~ /^(http|ftp|das):/;
     next if $self->{sources}{$track};
     delete $settings->{features}{$track};
     $adjusted++;
   }
}

sub feature_file {
  my $self = shift;
  my ($source,$segment,$rel2abs) = @_;

  my $config   = $self->config;
  my $settings = $self->page_settings;

  warn "get_remote_feature_data(): fetching $source" if DEBUG;
  my $proxy           = $config->setting('proxy') || '';
  my $http_proxy      = $config->setting('http proxy') || $proxy || '';
  my $ftp_proxy       = $config->setting('ftp proxy')  || $proxy || '';

  if ($source =~ m!^(http://.+/das)/([^/?]+)(?:\?(.+))?$!) { # DAS source!
    unless (eval "require Bio::Das; 1;") {
      error($config->tr('NO_DAS'));
      return;
    }

    my ($src,$dsn,$cgi_args) = ($1,$2,$3);
    my @aggregators = shellwords($config->setting('aggregators') ||'');
    my (@types,@categories);

    if ($cgi_args) {
      my @a = split /[;&]/,$cgi_args;
      foreach (@a) {
	my ($arg,$val) = split /=/;
	push @types,unescape($val)      if $arg eq 'type';
	push @categories,unescape($val) if $arg eq 'category';
      }
    }
    my @args = (-source     => $src,
		-dsn        => $dsn,
		-aggregators=> \@aggregators);
    push @args,(-types => \@types)           if @types;
    push @args,(-categories => \@categories) if @categories;
    my $das      =  Bio::Das->new(@args);

    return unless $das;

    # set up proxy
    $das->proxy($http_proxy) if $http_proxy && $http_proxy ne 'none';

    my $segment = $das->segment($segment->abs_ref,$segment->abs_start,$segment->abs_stop);
    # the next step gives the current segment the same name as the DAS source
    # and ensures that the DAS source appears in the list of external sources in the UI
    $segment->name($source);
    return $segment;
  }

  unless ($UA) {
    unless (eval "require LWP") {
      error($config->tr('NO_LWP'));
      return;
    }
    $UA = LWP::UserAgent->new(agent    => "Generic-Genome-Browser/$main::VERSION",
			      timeout  => URL_FETCH_TIMEOUT,
			      max_size => URL_FETCH_MAX_SIZE,
			     );
    $UA->proxy(http => $http_proxy) if $http_proxy && $http_proxy ne 'none';
    $UA->proxy(ftp => $http_proxy)  if $ftp_proxy  && $ftp_proxy  ne 'none';
  }
  my $id = md5_hex($source);     # turn into a filename
  $id =~ /^([0-9a-fA-F]+)$/;  # untaint operation
  $id = $1;

  my (undef,$tmpdir) = $config->tmpdir($config->source.'/external');
  my $response = $UA->mirror($source,"$tmpdir/$id");
  if ($response->is_error) {
    error($config->tr('Fetch_failed',$source,$response->message));
    return;
  }
  open (F,"<$tmpdir/$id") or return;
  my $feature_file = Bio::Graphics::FeatureFile->new(-file           => \*F,
						     -map_coords     => $rel2abs,
						     -smart_features =>1);
  $feature_file->name($source);
  warn "get_remote_feature_data(): got $feature_file" if DEBUG;
  return $feature_file;
}

sub annotate {
  my $self = shift;
  my $segment       = shift;
  my $feature_files     = shift || {};
  my $coordinate_mapper = shift;
  my $settings          = $self->page_settings;

  for my $url ($self->sources) {
    next unless $settings->{features}{$url}{visible};
    my $feature_file = $self->feature_file($url,$segment,$coordinate_mapper);
    $feature_files->{$url} = $feature_file;
  }
}

1;

__END__

=head1 NAME

Bio::Graphics::Browser::PluginSet -- A set of plugins

=head1 SYNOPSIS

None.  Used internally by gbrowse & gbrowse_img.

=head1 METHODS

=over 4

=item $plugin_set = Bio::Graphics::Browser::PluginSet->new($config,$page_settings,@search_path)

Initialize plugins according to the configuration, page settings and
the plugin search path.  Returns an object.

=item $plugin_set->configure($database)

Configure the plugins given the database.

=item $plugin_set->annotate($segment,$feature_files,$rel2abs)

Run plugin annotations on the $segment, adding the resulting feature
files to the hash ref in $feature_files ({track_name=>$feature_list}).
The $rel2abs argument holds a coordinate mapper callback, but is
currently unused.

=back

=head1 SEE ALSO

L<Bio::Graphics::Browser>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2005 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut

