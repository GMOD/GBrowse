package Bio::Graphics::Browser::RegionSearch;

use strict;
use warnings;
use Bio::Graphics::Browser::Region;
use LWP::Parallel::UserAgent;
use Storable 'nfreeze','thaw';

use constant DEBUG => 0;

# search multiple databases using crazy heuristics

=head1 NAME

Bio::Graphics::Browser::RegionSearch -- Search through multiple databases for feature matches.

=head1 SYNOPSIS

  my $dbs = Bio::Graphics::Browser::RegionSearch->new(
              { source => $data_source, 
                state  => $session_state
              });
  $dbs->init_databases();
  my $features = $dbs->search_features('sma-3');
  

=head1 DESCRIPTION

This implements a feature search based on the heuristics in
Bio::Graphics::Browser::Region. The search is distributed across all
local and remote databases as specified in the data source.

=head1 METHODS

The remainder of this document describes the methods available to the
programmer.

=cut

=head2 $db = Bio::Graphics::Browser::RegionSearch->new({opts})

Create a new RegionSearch object. Required parameters are:

        Parameter     Description

        source        The Bio::Graphics::Browser::DataSource
                      object describing the local and remote
                      databases for this source.

        state         The page_settings document describing the
                      current state of the user session (for
                      looking up search options and the like in the
                      future).

=cut

sub new {
    my $self = shift;
    my $args = shift;
    my ($source,$state) = @{$args}{'source','state'};
    return bless {
	source => $source,
	state  => $state,
    },ref($self) || $self;
}

=head2 $db->init_databases(\@labels)

This method will initialize all the databases in preparation for a
search. Pass it a list of track labels to search only in the databases
defined by those tracks. Otherwise it will sort all tracks into local
and remote ones.

=cut

sub init_databases {
    my $self         = shift;
    my $track_labels = shift;

    $self->{local_dbs}  = {};
    $self->{remote_dbs} = {};

    my $source = $self->source;
    my $labels = $track_labels || [$source->labels];

    for my $l (@$labels) {

	if (!$track_labels &&
	    (my $remote = $source->setting($l => 'remote renderer'))) {
	    $self->{remote_dbs}{$remote}{$l}++;
	} else {
	    my $db = $source->open_database($l);
	    $self->{local_dbs}{$db} ||= 
		Bio::Graphics::Browser::Region->new(
		    { source  => $source,
		      state   => $self->state,
		      db      => $db}
		);
	}
    }
}


=head2 $source = source()

Return the data source.

=cut

sub source           { shift->{source} }

=head2 state()

=cut

sub state            { shift->{state}  }

=head2 remote_dbs()

=cut

sub remote_dbs       { shift->{remote_dbs} }

=head2 local_dbs()

=cut

sub local_dbs        { shift->{local_dbs} }

=head2 $found = $db->search_features('search term')

This method will search all the databases for features matching the
search term and will return the results as an array ref of
Bio::SeqFeatureI objects.

If no search term is provided, then it is taken from the "name" field
of the settings object.

=cut

sub search_features {
    my $self        = shift;
    my $search_term = shift;

    $search_term   ||= $self->state->{name};  
    defined $search_term or return;

    my $local  = $self->search_features_locally($search_term);
    my $remote = $self->search_features_remotely($search_term);

    my @found;
    push @found,@$local  if $local  && @$local;
    push @found,@$remote if $remote && @$remote;

    # uniqueify features of the same type and name
    my %seenit;

    @found = grep {defined $_ && !$seenit{$_->name,
					  $_->type,
					  $_->seq_id,
					  $_->start,
					  $_->end,
					  $_->strand}++} @found;
    return \@found;
}

=head2 $found = $db->search_features_locally('search term')

Search only the local databases for the term.

=cut


sub search_features_locally {
    my $self        = shift;
    my $search_term = shift;
    defined $search_term or return;
    my $state       = $self->state;

    warn "search_features_locally()" if DEBUG;
    
    my @found;

    # each local db gets a chance to search
    my $local_dbs = $self->local_dbs;
    return unless $local_dbs;

    my @dbs = $state->{dbid} ? $self->source->open_database($state->{dbid})
	                     : keys %{$local_dbs};

    for my $db (@dbs) {
	# allow explicit db_id to override cached list of local dbs
	my $region   = $local_dbs->{$db} || 
	    Bio::Graphics::Browser::Region->new(
						{ source  => $self->source,
						  state   => $self->state,
						  db      => $db,
						  }
						); 
	my $features = $region->search_features($search_term);
	next unless $features && @$features;
	$self->add_dbid_to_features($db,$features);
	push @found,@$features if $features;
    }

    return \@found;
}

=head2 $found = $db->search_features_remotely('search term')

Search only the remote databases for the term.

=cut


sub search_features_remotely {
    my $self        = shift;
    my $search_term = shift;
    defined $search_term or return;

    # each remote renderer gets a chance to search;
    # we kick off these searches before we do local
    # searches in order to take advantage of
    # parallelism
    my $remote_dbs = $self->remote_dbs;
    return unless %$remote_dbs;

    warn "pid = $$: KICKING OFF A REMOTE SEARCH" if DEBUG;

    eval { use LWP::Parallel::UserAgent;} unless LWP::Parallel::UserAgent->can('new');
    eval { use HTTP::Request::Common;   } unless HTTP::Request::Common->can('POST');

    my $ua = eval{LWP::Parallel::UserAgent->new};
    unless ($ua) {
	warn $@;
	return [];
    }

    $Storable::Deparse ||= 1;
    $ua->in_order(0);
    $ua->nonblock(0);
    $ua->remember_failures(1);
    my $s_dsn	= nfreeze($self->source);
    my $s_set	= nfreeze($self->state);
    my %env     = map {$_=>$ENV{$_}} grep /^GBROWSE/,keys %ENV;

    for my $url (keys %$remote_dbs) {
	my @tracks  = keys %{$remote_dbs->{$url}};
	my $request = POST ($url,
			    [ operation  => 'search_features',
			      settings   => $s_set,
			      datasource => $s_dsn,
			      tracks     => nfreeze(\@tracks),
			      env        => nfreeze(\%env),
			      searchterm => $search_term,
			    ]);
	my $error = $ua->register($request);
	if ($error) { warn "Could not send request to $url: ",$error->as_string }
    }

    my $timeout = $self->source->global_setting('timeout') || 20;
    my $results = $ua->wait($timeout);

    my @found;

    for my $url (keys %$results) {
	my $response = $results->{$url}->response;
	unless ($response->is_success) {
	    warn $results->{$url}->request->uri,
	         "; fetch failed: ",
	         $response->status_line;
	    next;
	}
	my $contents = thaw $response->content;
	push @found,@$contents if $contents;
    }

    return \@found;
}

=head2 $db->add_dbid_to_features($db,$features)

Add a gbrowse_dbid() method to each of the features in the list.

=cut

sub add_dbid_to_features {
    my $self           = shift;
    my ($db,$features) = @_;
    return unless $features;
    my $source = $self->source;
    my $dbid   = $source->db2id($db);
    $source->add_dbid_to_feature($_,$dbid) foreach @$features;
}

1;

__END__


=head1 SEE ALSO

L<Bio::Graphics::Browser::Region>,
L<Bio::Graphics::Browser>,
L<Bio::Graphics::Feature>,

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2008 Cold Spring Harbor Laboratory & Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

