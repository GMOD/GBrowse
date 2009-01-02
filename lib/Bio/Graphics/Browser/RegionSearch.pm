package Bio::Graphics::Browser::RegionSearch;

use strict;
use warnings;
use Bio::Graphics::GBrowseFeature;
use Bio::Graphics::Browser::Region;
use Bio::Graphics::Browser::RenderPanels;
use Bio::Graphics::Browser::Util 'shellwords';
use Bio::Graphics::Browser::Render::Slave::Status;
use LWP::UserAgent;
use HTTP::Request::Common 'POST';
use Storable 'nfreeze','thaw';

use constant DEBUG => 0;

#local $SIG{CHLD} = 'IGNORE';

# search multiple databases using crazy heuristics

=head1 NAME

Bio::Graphics::Browser::RegionSearch -- Search through multiple databases for feature matches.

=head1 SYNOPSIS

  my $dbs = Bio::Graphics::Browser::RegionSearch->new(
              { source => $data_source, 
                state  => $session_state
              });
  $dbs->init_databases();
  my $features = $dbs->search_features({-search_term=>'sma-3'});
  

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
    my $local_only   = shift;

    $self->{local_dbs}  = {};
    $self->{remote_dbs} = {};

    my %dbs;

    my $source = $self->source;
    my $labels = $track_labels || [$source->labels];

    my $renderfarm = $self->source->global_setting('renderfarm');

    my $slave_status = Bio::Graphics::Browser::Render::Slave::Status->new(
	$source->globals->slave_status_path
	);

    for my $l (@$labels) {
	next if $l =~ /^(_scale|builtin)/;

	my $remote         = $local_only || !$renderfarm 
                               ? undef 
                               : $source->fallback_setting($l => 'remote renderer');
	if ($remote) {
	    my @remotes  = shellwords($remote);
	    $remote = $slave_status->select(@remotes);
	}
	my ($dbid)         = $source->db_settings($l);
	my $search_options = $source->setting($dbid => 'search options') || '';

	next if $search_options eq 'none';  # ignore this in the search
	$dbs{$dbid}{options} ||= $search_options;
	$dbs{$dbid}{remotes}{$remote}++ if $remote;
    }

    # try to spread the work out as much as possible among the remote renderers
    my %remotes;
    for my $dbid (keys %dbs) {
	if (my @remote = keys %{$dbs{$dbid}{remotes}}) {
	    my ($least_used) = sort {($remotes{$a}||0) <=> ($remotes{$b}||0)} @remote;
	    $self->{remote_dbs}{$least_used}{$dbid}++;
	    $remotes{$least_used}++;
	}
	else {
	    my $db = $source->open_database($dbid);
	    $self->{local_dbs}{$db} ||= 
		Bio::Graphics::Browser::Region->new(
		    { source     => $source,
		      state      => $self->state,
		      db         => $db,
		      searchopts => $dbs{$dbid}{options},
		    }
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

=head2 @features = $db->features(@args)

Pass @args to the underlying db adaptors' features() methods and return all
matching features. Example:

   @features = $db->features(-type=>'CDS')

=cut

sub features {
    my $self = shift;

    my %args;
    if (@_ == 0) {
	%args = ();
    }
    elsif ($_[0] !~/^-/) {
	my @types = @_;
	%args = (-type=>\@types);
    }
    else {
	%args = @_;
    }
    return $self->search_features(\%args);
}

=head2 $meta_segment = $db->segment($segment)

Given an existing segment, return a
Bio::Graphics::Browser::MetaSegment object, which behaves more or less
like a regular Bio::Das::SegmentI object, but searches multiple
databases. Both iterative and non-iterative feature fetching is
supported.

(The class definitions for Bio::Graphics::Browser::MetaSegment are
located in the Bio/Graphics/Browser/RegionSearch.pm file.)

=cut

sub segment {
    my $self    = shift;
    my $segment = shift;
    return Bio::Graphics::Browser::MetaSegment->new($self,$segment);
}

=head2 $found = $db->search_features($args)

This method will search all the databases for features matching the
search term and will return the results as an array ref of
Bio::SeqFeatureI objects. The arguments are a hash ref containing the
various options passed to the db adaptors' features() method
(e.g. "-type"), or a hashref with the key "-search", in which case the
search term is parsed as any of gbrowse's heuristic keyword searches.

If no search term is provided, then it is taken from the "name" field
of the settings object.

=cut

sub search_features {
    my $self        = shift;
    my $args        = shift;
    my $state       = $self->state;

    $args          ||= {};
    unless (%$args) {
	return unless $state->{name};
	$args->{-search_term} = $state->{name}
    }

    my $local  = $self->search_features_locally($args);
    my $remote = $self->search_features_remotely($args);

    my @found;
    push @found,@$local  if $local  && @$local;
    push @found,@$remote if $remote && @$remote;

    # uniqueify features of the same type and name
    my %seenit;

    @found = grep {
	defined $_ 
	    && !$seenit{($_->name||''),
			$_->type,
			$_->seq_id,
			$_->start,
			$_->end,
			$_->strand}++} @found;
    return wantarray ? @found : \@found;
}

=head2 $found = $db->search_features_locally($args)

Search only the local databases for the term.

=cut


sub search_features_locally {
    my $self        = shift;
    my $args        = shift;
    ref $args && %$args or return;

    my $state       = $self->state;

    my @found;

    # each local db gets a chance to search
    my $local_dbs = $self->local_dbs;
    return unless $local_dbs;

    my @dbs = keys %{$local_dbs};

    for my $db (@dbs) {
	warn "searching in $db: ",$self->source->db2id($db) if DEBUG;
	# allow explicit db_id to override cached list of local dbs
	my $region   = $local_dbs->{$db} || 
	    Bio::Graphics::Browser::Region->new(
						{ source  => $self->source,
						  state   => $self->state,
						  db      => $db,
						  }
						); 
	my $features = $region->search_features($args);
	next unless $features && @$features;
	$self->add_dbid_to_features($db,$features);
	push @found,@$features if $features;
    }

    return \@found;
}

=head2 $found = $db->search_features_remotely($args)

Search only the remote databases for the term.

=cut


sub search_features_remotely {
    my $self        = shift;
    my $args        = shift;
    ref $args && %$args or return;

    # each remote renderer gets a chance to search;
    # we kick off these searches before we do local
    # searches in order to take advantage of
    # parallelism
    my $remote_dbs = $self->remote_dbs;
    return unless %$remote_dbs;

    warn "pid = $$: KICKING OFF A REMOTE SEARCH" if DEBUG;

    eval "require IO::Pipe;1;"   unless IO::Pipe->can('new');
    eval "require IO::Select;1;" unless IO::Select->can('new');

    $SIG{CHLD} = 'IGNORE';  # for some reason local() does not work!

    my $select = IO::Select->new();

    for my $url (keys %$remote_dbs) {

	my $pipe  = IO::Pipe->new();
	Bio::Graphics::Browser::Render->prepare_modperl_for_fork();
	Bio::Graphics::Browser::Render->prepare_fcgi_for_fork('starting');
	my $child = CORE::fork();
	print STDERR "forked $child" if DEBUG;
	die "Couldn't fork: $!" unless defined $child;
	if ($child) { # parent
	    Bio::Graphics::Browser::Render->prepare_fcgi_for_fork('parent');
	    $pipe->reader();
	    $select->add($pipe);
	}
	else { # child
	    Bio::Graphics::Browser::Render->prepare_fcgi_for_fork('child');
	    $pipe->writer();
	    $self->fetch_remote_features($args,$url,$pipe);
	    CORE::exit 0;  # CORE::exit prevents modperl from running cleanup, etc
	}
    }

    my @found;
    while ($select->count > 0) {
	my @ready = $select->can_read(5);

	unless (@ready) { warn "timeout\n"; next; }

      HANDLE:
	for my $r (@ready) {
	    my $data;
	    my $bytes = $r->sysread($data,4);
	    unless ($bytes) {  # eof
		$select->remove($r);
		$r->close;
		next HANDLE;
	    }

	    # This is not maximally efficient because we keep reading from the handle
	    # until we have gotten all the data. It would be more efficient to do a
	    # nonblocking read so that reads are interleaved, but it is MUCH harder
	    # to do.
	    my $data_len = unpack('N',$data);
	    $data = '';
	    while (length $data < $data_len) {
		$bytes     = $r->sysread($data,4096,length $data);
		if ($bytes == 0) {
		    warn "premature EOF while reading search results: $!";
		    $select->remove($r);
		    $r->close;
		    next HANDLE;
		}
	    }

	    my $objects = thaw($data);
	    push @found,@$objects;
	}
    }

    eval {Bio::Graphics::Browser->fcgi_request()->Flush};

    return \@found;
}

sub fetch_remote_features {
    my $self = shift;
    my ($args,$url,$outfh) = @_;

    $Storable::Deparse ||= 1;
    my $s_dsn	= nfreeze($self->source);
    my $s_set	= nfreeze($self->state);
    my $s_args	= nfreeze($args);
    my %env     = map {$_=>$ENV{$_}} grep /^GBROWSE/,keys %ENV;

    my @tracks  = keys %{$self->remote_dbs->{$url}};
    my $request = POST ($url,
			[ operation  => 'search_features',
			  settings   => $s_set,
			  datasource => $s_dsn,
			  tracks     => nfreeze(\@tracks),
			  env        => nfreeze(\%env),
			  searchargs => $s_args,
			]);

    my $ua      = LWP::UserAgent->new();
    my $timeout = $self->source->global_setting('slave_timeout') 
	|| $self->source->global_setting('global_timeout') || 30;
    $ua->timeout($timeout);


    $request->uri($url);
    my $response = $ua->request($request);

    if ($response->is_success) {
	my $content = $response->content;
	$outfh->print(pack('N',length $content));
	my $bytes = $outfh->print($content) or warn "write failed: $!";
    } else {
	my $uri = $request->uri;
	warn "$uri; search failed: ",$response->status_line;
	$outfh->close;
    }
    $outfh->close;
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

##################################################################33
# META SEGMENT DEFINITIONS
##################################################################33
package Bio::Graphics::Browser::MetaSegment;

our $AUTOLOAD;
use overload 
  '""'     => \&as_string,
  fallback => 1;

sub new {
    my $class = shift;
    my ($region_search,$segment) = @_;
    return bless {db      => $region_search,
		  segment => $segment},ref $class || $class;
}

sub AUTOLOAD {
  my($pack,$func_name) = $AUTOLOAD=~/(.+)::([^:]+)$/;
  return if $func_name eq 'DESTROY';
  my $self = shift or die;
  $self->segment->$func_name(@_);
}

sub db      { shift->{db}      }
sub segment { shift->{segment} }
sub as_string {
    my $segment = shift->segment;
    return $segment->seq_id.':'.$segment->start.'..'.$segment->end;
}

sub features {
    my $self    = shift;
    my $segment = $self->segment;
    $self->db->features(-seq_id => $segment->seq_id,
			-start  => $segment->start,
			-end    => $segment->end,
			-class  => eval {$segment->class} || 'Sequence',
			@_
	);
}

sub get_seq_stream {
    my $self = shift;
    my $features = $self->features(@_);
    return Bio::Graphics::Browser::MetaSegment::Iterator->new($features);
}

package Bio::Graphics::Browser::MetaSegment::Iterator;

sub new {
    my $class    = shift;
    my $features = shift;
    return bless {f=>$features},ref $class || $class;
}

sub next_seq {
    my $f = shift->{f};
    return shift @$f;
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

