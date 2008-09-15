package Bio::Graphics::Browser::RemoteSet;
# API for handling a set of remote annotation sources

use strict;
use base 'Bio::Graphics::Browser::RemoteDataBase';

use Bio::Graphics::Browser::Util 'error','shellwords';
use IO::File;
use CGI 'cookie','param','unescape';
use Digest::MD5 'md5_hex';
use File::Spec;

use constant URL_FETCH_TIMEOUT    => 5;  # five seconds max!
use constant URL_FETCH_MAX_SIZE   => 50_000_000;  # don't accept any files larger than 50 Meg

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
    if ($track =~ /^(http|ftp|das):/) {
      $self->add_source($track,$track);
      next;
    }
    my $remote_url = $config->setting($track=>'remote feature') or next;
    warn "adding remote_url = $remote_url" if DEBUG;
    $self->add_source($track,$remote_url);
  }
  $self;
}

sub sources       { keys %{shift->{sources}} }
sub source2url    { shift->{sources}{shift()}  }

sub add_source {
  my $self   = shift;
  my ($label,$source) = @_;
  $self->{sources}{$label}=$source;
}

sub delete_source {
  my $self   = shift;
  my $label = shift;
  delete $self->{sources}{$label};
}

sub set_sources {
  my $self     = shift;
  my $sources  = shift;

  my $settings = $self->page_settings;
  for (@$sources) {
    next if $_ eq '';
    $self->add_source($_,$_);
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
  my ($label,$segment,$rel2abs,$slow_mapper) = @_;

  my $config   = $self->config;
  my $settings = $self->page_settings;

  warn "feature_file(): fetching $label" if DEBUG;

  # DAS handling
  my $url = $self->source2url($label);
  my $feature_file;

  if ($url =~ m!^(http://.+/das)/([^?]+)(?:\?(.+))?$!) { # DAS source!
    warn "getting DAS segment for $url" if DEBUG;
    $feature_file = $self->get_das_segment($1,$2,$3,$segment);
  }
  else {
    warn "getting featurefile for $url" if DEBUG;
    $feature_file = $self->get_remote_upload($url,$rel2abs,$slow_mapper,$segment,$label);
  }
  return unless $feature_file;

  # Tell the feature file what its name is, so that it can be formatted
  # nicely in the user interface.
  my $name = $feature_file->setting('name') if $feature_file->can('setting');
  $feature_file->name($name||$url) if $feature_file->can('name');

  return $feature_file;
}

sub transform_url {
    my $self = shift;
    my ($url,$segment) = @_;

    my ($seqid,$start,$end) = ref $segment 
	                          ? ($segment->seq_id,$segment->start,$segment->end)
                                  : $segment =~ /^([^:]+):(.+)(?:\.\.|,)(.+)$/;

    # do certain substitutions on the URL

    # for DAS
    $url =~ s!(http:.+/das/\w+)(?:\?(.+))?$!$1/features?segment=$seqid:$start..$end;$2!;

    # for gbgff and the like
    $url =~ s/\$segment/$seqid:$start..$end/g;
    $url =~ s/\$ref/$seqid/g;
    $url =~ s/\$start/$start/e;
    $url =~ s/\$end/$end/e;
 
    return $url;
}

sub get_remote_upload {
  my $self = shift;
  my ($url,$rel2abs,$slow_mapper,$segment,$label) = @_;
  my $config = $self->config;

  # do certain substitutions on the URL
  $url = $self->transform_url($url,$segment);

  my $id = md5_hex($url);     # turn into a filename
  $id =~ /^([0-9a-fA-F]+)$/;  # untaint operation
  $id = $1;

  my (undef,$tmpdir) = $config->tmpdir(File::Spec->catfile($config->source,'external'));
  my $filename = File::Spec->catfile($tmpdir,$id);
  my $response = $self->mirror($url,$filename);
  if ($response->is_error) {
    error($config->tr('Fetch_failed',$url,$response->message));
    return;
  }
  my $fh = IO::File->new("<$filename") or return;
  my $in_overview    = $rel2abs ne $slow_mapper && $self->probe_for_overview_sections($fh);
  my $feature_file   =
    Bio::Graphics::FeatureFile->new(-file           => $fh,
				    -map_coords     => $in_overview ? $slow_mapper : $rel2abs,
				    -smart_features => 1,
				    -safe_world     => $self->config->setting('allow remote callbacks')||0,
    );
  warn "get_remote_feature_data(): got $feature_file" if DEBUG;
 
  # let proximal configuration override remote
  if ($config->setting($label => 'remote feature')) {

    # local track name may not correspond to the
    # FeatureFile types
    my ($types) = $url =~ /type=([^;&]+)/;
    my @types = split(/\+|\s+/, $types);

    for my $option ($config->config->_setting($label)) {
      my $val = $config->setting($label => $option);
      for my $type (@types) {
	$feature_file->set($type,$option,$val);
      }
    }
  }

  return $feature_file;
}


sub get_das_segment {
  my $self = shift;
  my ($src,$dsn,$cgi_args,
      $segment) = @_;
  my $config   = $self->config;

  unless (eval "require Bio::Das; 1;") {
    error($config->tr('NO_DAS'));
    return;
  }

  my @aggregators = shellwords($config->setting('aggregators') ||'');
  my (@types,@categories);

  if ($cgi_args) {
    my @a = split /[;&]/,$cgi_args;
    foreach (@a) {
      my ($arg,$val) = split '=';
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
  my $http_proxy = $self->http_proxy;
  $das->proxy($http_proxy) if $http_proxy && $http_proxy ne 'none';

  my $seg = $das->segment($segment->abs_ref,
			  $segment->abs_start,$segment->abs_end);

  return $seg;
}

sub mirror {
  my $self            = shift;
  my ($url,$filename) = @_;

  my $config = $self->config;

  # Uploaded feature handling
  unless ($UA) {
    unless (eval "require LWP") {
      error($config->tr('NO_LWP'));
      return;
    }
    $UA = LWP::UserAgent->new(agent    => "Generic-Genome-Browser/$main::VERSION",
			      timeout  => URL_FETCH_TIMEOUT,
			      max_size => URL_FETCH_MAX_SIZE,
			     );
    my $http_proxy = $self->http_proxy;
    my $ftp_proxy  = $self->ftp_proxy;

    $UA->proxy(http => $http_proxy) if $http_proxy && $http_proxy ne 'none';
    $UA->proxy(ftp => $http_proxy)  if $ftp_proxy  && $ftp_proxy  ne 'none';
  }

  my $request = HTTP::Request->new(GET => $url);
  if (-e $filename) {
    my($mtime) = (stat($filename))[9];
    if($mtime) {
      $request->header('If-Modified-Since' =>
		       HTTP::Date::time2str($mtime));
    }
  }

  my ($volume,$dirs,$file) = File::Spec->splitpath($filename);
  $file = "$file-$$";
  my $tmpfile  = File::Spec->catfile($volume,$dirs,$file);
  my $response = $UA->request($request,$tmpfile);

  if ($response->is_success) {  # we got a new file, so need to process it
      my $fh     = IO::File->new($tmpfile);

      # handle possible un-gzipping
      my $dummy_name = $url;
      $dummy_name   .= ".gz" if $response->header('Content-Type') =~ /gzip/;

      my $infh       = $self->maybe_unzip($dummy_name,$fh) || $fh;
      $infh or die "Couldn't open $tmpfile: $!";
      my $outfh  = IO::File->new(">$filename") or die "Couldn't open $filename: $!";
      $self->process_uploaded_file($infh,$outfh);
      if (my $lm = $response->last_modified) {
	  utime($lm,$lm,$filename);
      }
  }
  unlink $tmpfile;  # either way, this file is no longer needed
  return $response;
}

sub annotate {
  my $self = shift;
  my $segment                = shift;
  my $feature_files          = shift || {};
  my $restricted_mapper      = shift;
  my $unrestricted_mapper    = shift;
  my $settings          = $self->page_settings;

  for my $url ($self->sources) {
      next unless $settings->{features}{$url}{visible};
      
      # check to see whether URL includes the magic $segment and/or $ref 
      # parameters. If so, then it is safe to use the coordinate remapper
      # which remaps all coordinates. Otherwise, this is probably just a GFF
      # file and we need to filter out features that are outside the range of
      # the current segment.
      my $mapper             = $url =~ m!(\$segment|\$ref)!
                                     ? $unrestricted_mapper
                                     : $restricted_mapper;
      my $feature_file       = $self->feature_file($url,$segment,$mapper,$unrestricted_mapper);
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

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

