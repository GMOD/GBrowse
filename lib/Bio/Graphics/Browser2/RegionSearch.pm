package Bio::Graphics::Browser2::RegionSearch;

use strict;
use warnings;
use Bio::Graphics::GBrowseFeature;
use Bio::Graphics::Browser2::Region;
use Bio::Graphics::Browser2::RenderPanels;
use Bio::Graphics::Browser2::Util 'shellwords';
use Bio::Graphics::Browser2::Render::Slave::Status;
use LWP::UserAgent;
use HTTP::Request::Common 'POST';
use Carp 'cluck','croak';
use Storable 'nfreeze','thaw';

use constant DEBUG => 0;

# search multiple databases using crazy heuristics

=head1 NAME

Bio::Graphics::Browser2::RegionSearch -- Search through multiple databases for feature matches.

=head1 SYNOPSIS

  my $dbs = Bio::Graphics::Browser2::RegionSearch->new(
              { source => $data_source, 
                state  => $session_state
              });
  $dbs->init_databases();
  my $features = $dbs->search_features({-search_term=>'sma-3'});
  

=head1 DESCRIPTION

This implements a feature search based on the heuristics in
Bio::Graphics::Browser2::Region. The search is distributed across all
local and remote databases as specified in the data source.

=head1 METHODS

The remainder of this document describes the methods available to the
programmer.

=cut

=head2 $db = Bio::Graphics::Browser2::RegionSearch->new({opts})

Create a new RegionSearch object. Required parameters are:

        Parameter     Description

        source        The Bio::Graphics::Browser2::DataSource
                      object describing the local and remote
                      databases for this source.

        state         The page_settings document describing the
                      current state of the user session (for
                      looking up search_options and the like in the
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

    my $state        = $self->state;

    $self->{local_dbs}  = {};
    $self->{remote_dbs} = {};

    my %dbs;

    my $source = $self->source;
    my $labels = $track_labels || [$source->labels];

    my $renderfarm = $self->source->global_setting('renderfarm');

    my $slave_status = Bio::Graphics::Browser2::Render::Slave::Status->new(
	$source->globals->slave_status_path
	);

    my %seenit;
    for my $l (@$labels) {
	next if $l =~ /^(_scale|builtin)/;
	my ($dbid)         = $source->db_settings($l) or next;
	next if $seenit{$dbid}++;

	my $remote         = $local_only || !$renderfarm 
                               ? undef 
                               : $source->fallback_setting($l => 'remote renderer');
	if ($remote) {
	    my @remotes  = shellwords($remote);
	    $remote = $slave_status->select(@remotes);
	}

	my $search_options = $source->search_options($dbid);

	$dbs{$dbid}{options} ||= $search_options;
	$dbs{$dbid}{remotes}{$remote}++ if $remote;
    }

    # slightly roundabout way to get the default dbid, but this allows you
    # to handle anonymous (unnamed) databases consistently.
    my $default_dbid = $self->source->default_dbid;

    # try to spread the work out as much as possible among the remote renderers
    my %remotes;
    for my $dbid ($default_dbid,keys %dbs) {

	my $can_remote  = keys %{$dbs{$dbid}{remotes}} && ($dbid ne $default_dbid);

	if ($can_remote) {
	    my @remote = keys %{$dbs{$dbid}{remotes}};
	    my ($least_used) = sort {($remotes{$a}||0) <=> ($remotes{$b}||0)} @remote;
	    $self->{remote_dbs}{$least_used}{$dbid}++;
	    $remotes{$least_used}++;
	}
	
	if (!$can_remote || $dbs{$dbid}{options} =~ /(?<!-)autocomplete/) {
	    $self->{local_dbs}{$dbid}++;
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
Bio::Graphics::Browser2::MetaSegment object, which behaves more or
less like a regular Bio::Das::SegmentI object, but searches multiple
databases. Both iterative and non-iterative feature fetching is
supported.

(The class definitions for Bio::Graphics::Browser2::MetaSegment are
located in the Bio/Graphics/Browser/RegionSearch.pm file.)

=cut

sub segment {
    my $self    = shift;
    my $segment = shift;
    return Bio::Graphics::Browser2::MetaSegment->new($self,$segment);
}

=head2 $segment = $db->feature2segment($feature)

Converts a feature into a segment in the database that the feature
corresponds to.

=cut

sub feature2segment {
    my $self             = shift;
    my ($feature,$dbid)  = @_;

    my $source   = $self->source;
    $dbid      ||= $feature->gbrowse_dbid;
    my $db       = $source->open_database($dbid);

    my $region   = Bio::Graphics::Browser2::Region->new(
 	{ source     => $source,
 	  state      => {},
 	  db         => $db,
	  searchopts => $source->search_options($dbid),
	}
 	);
    $region->features([$feature]);
    return $region->seg;
}

=head2 @segments = $db->features2segments($feature)

As above, but takes an arrayref of features and returns an array of
segments.

=cut

sub features2segments {
    my $self             = shift;
    my ($features,$dbid)  = @_;

    my $source   = $self->source;
    my $db       = $source->open_database($dbid);

    my $region   = Bio::Graphics::Browser2::Region->new(
 	{ source     => $source,
 	  state      => {},
 	  db         => $db,
	  searchopts => $source->search_options($dbid),
	}
 	);
    my $s = $region->features2segments($features);
    return unless $s;
    return @$s;
}


=head2 $found = $db->search_features($args)

This method will search all the databases for features matching the
search term and will return the results as an array ref of
Bio::SeqFeatureI objects. The arguments are a hash ref containing the
various options passed to the db adaptors' features() method
(e.g. "-type"), or a hashref with the key "-search_term", in which
case the search term is parsed as any of gbrowse's heuristic keyword
searches. 

If no args are provided, then the search term is taken from the "name"
field of the settings object.

=cut

sub search_features {
    my $self        = shift;
    my $args        = shift;
    my $state       = $self->state;
    $args         ||= {};

    if ($args && !ref($args)) {
	$args = {-search_term=>$args};  #adjust for changed API
    }

    unless (%$args) {
	return unless $state->{name};
	$args->{-search_term} = $state->{name}
    }

    local $self->{shortcircuit} = 0;
    my $local   = $self->search_features_locally($args);  # if default db has a hit, then we short circuit
    my $remote  = $self->search_features_remotely($args) unless $self->{shortcircuit};

    my @found;
    push @found,@$local    if $local    && @$local;
    push @found,@$remote   if $remote   && @$remote;

    # uniqueify features of the same type and name
    my %seenit;

    @found = grep {
	defined $_ 
	    && !$seenit{
		(($state->{name} && 
		  lc $_->seq_id eq $state->{name}) # this hack gives special privileges to matches to seq_ids
		 ? 'region' 
		 : $_->primary_tag),
		 $_->seq_id,
		 $_->start,
		 $_->end,
		 $_->strand}++} @found;
    return wantarray ? @found : \@found;
}

=head2 $found = $db->search_features_locally($args)

Search only the local databases for the term.

$Args is a hashref:

   Key             Value
   ---             -----
   -search_term    term to search for
   -shortcircuit   stop searching if term is found in default db

If -shortcircuit is not provided, it defaults to true.

=cut

sub search_features_locally {
    my $self = shift;
    
    my $timeout         = $self->source->global_setting('search_timeout') || 10;

    my $result;

    warn "[$$] searching..." if DEBUG;

    # My oh my. block eval is not working as expected here. Sometimes the die is not caught.
    my $status = eval <<'END';
	local $SIG{ALRM} = sub { warn "alarm clock" ; die "The search timed out; try a more specific search\n"; die; };
	alarm($timeout);
	$result = $self->_search_features_locally(@_);
	1;
END
    alarm(0);
    warn "[$$] search done..." if DEBUG;

    unless ($status) {
	warn $@;
	return;
    }
    return $result;
}

sub _search_features_locally {
    my $self        = shift;
    my $args        = shift;
    ref $args && %$args or return;

    my $shortcircuit = $args->{-shortcircuit};
    $shortcircuit    = 1 unless defined $shortcircuit;

    my $state       = $self->state;
    my $source      = $self->source;

    my @found;

    # each local db gets a chance to search
    my $local_dbs = $self->local_dbs;
    return unless $local_dbs;

    warn "local dbs = ",join ' ',keys %{$local_dbs} if DEBUG;

    my @dbids = $state->{dbid} ? $state->{dbid} 
	                       : keys %{$local_dbs};

    # the default database is treated slightly differently - it is searched
    # first, and finding a hit in it short-circuits other hits
    my $default_dbid = $self->source->default_dbid;

    @dbids = sort {$a eq $default_dbid ? -1 
                  :$b eq $default_dbid ? +1
                  :0} @dbids;

    warn "dbs = @dbids" if DEBUG;
    my %seenit;

    for my $dbid (@dbids) {
	my $opts = $self->source->search_options($dbid);
	next if $opts =~ /none/i && ($args->{-name}||'') !~ /^id:/;
	warn "searching in ",$dbid if DEBUG;
	my $db = $self->source->open_database($dbid);
	next if $seenit{$db}++;
	my $region   = Bio::Graphics::Browser2::Region->new(
	    { source     => $self->source,
	      state      => $self->state,
	      db         => $db,
	      searchopts => $opts,
	    }
	    ); 
	my $features = $region->search_features($args);
	warn $features && @$features ? "[$$] got @$features" : "[$$] got no features" if DEBUG;
	next unless $features && @$features;
	$features = $self->filter_features($dbid,$features);
	$self->add_dbid_to_features($dbid,$features);
	push @found,@$features;
	
	if ($dbid eq $default_dbid && $shortcircuit) {
	    warn "hit @found in the default database, so short-circuiting" if DEBUG;
	    last;
	}
	    
    }

    return \@found;		
}

# remove any features in the database's "exclude types" list
sub filter_features {
    my $self = shift;
    my ($dbid,$features) = @_;
    my %exclude = map {lc $_=> 1} $self->source->exclude_types($dbid);
    return $features unless %exclude;
    my @f = grep {!$exclude{lc $_->primary_tag}} @$features;
    return \@f;
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

    my $select = IO::Select->new();

    for my $url (keys %$remote_dbs) {

	my $pipe  = IO::Pipe->new();
	my $child = Bio::Graphics::Browser2::Render->fork();
	if ($child) { # parent
	    $pipe->reader();
	    $select->add($pipe);
	}
	else { # child
	    $pipe->writer();
	    $self->fetch_remote_features($args,$url,$pipe);
	    {
		no warnings;
		# bug workaround: prevent Session destroy method from
		# flushing incomplete state!
		*CGI::Session::DESTROY = sub { }; 
             }
	    CORE::exit 0;  # CORE::exit prevents modperl from running cleanup, etc
	}
    }

    my @found;
    while ($select->count > 0) {

	my @ready = $select->can_read(5) or next;

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

    if (my $fcgi = Bio::Graphics::Browser2::Render->fcgi_request()) {
	$fcgi->Flush;
    }

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
    my $self             = shift;
    my ($dbid,$features) = @_;
    return unless $features;
    my $source = $self->source;
    cluck "$dbid is not a dbid" if ref $dbid;
    $source->add_dbid_to_feature($_,$dbid) foreach @$features;
}

=head2 $mapper = $search->coordinate_mapper($segment,$optimize)

Create a Bio::Graphics coordinator mapper on the current segment. If
optimize set to true, then features that map outside the current
segment's seqid and region are nulled.

=cut

sub coordinate_mapper {
    my $self            = shift;
    my $current_segment = shift;
    my $optimize        = shift;

    my $db = $current_segment->factory;

    my ( $ref, $start, $stop ) = (
        $current_segment->seq_id, 
	$current_segment->start,
        $current_segment->end
    );
    my %segments;

    my $closure = sub {
        my ( $refname, @ranges ) = @_;

        unless ( exists $segments{$refname} ) {
            $segments{$refname} = $self->search_features({-search_term => $refname})->[0];
        }
        my $mapper  = $segments{$refname} || return;
        my $absref  = $mapper->abs_ref;
        my $cur_ref = eval { $current_segment->abs_ref }
            || eval { $current_segment->ref }; # account for api changes in Bio::SeqI
        return unless $absref eq $cur_ref;

        my @abs_segs;
        if ( $absref eq $refname) {           # doesn't need remapping
            @abs_segs = @ranges;
        }
        elsif ($mapper->can('rel2abs')) {
            @abs_segs
                = map { [ $mapper->rel2abs( $_->[0], $_->[1] ) ] } @ranges;
        } else {
	    my $map_start  = $mapper->start;
	    my $map_strand = $mapper->strand;
	    if ($map_strand >= 0) {
		@abs_segs = map {[$_->[0]+$map_start-1,$_->[1]+$map_start-1]} @ranges;
	    } else {
		@abs_segs = map {[$map_start-$_->[0]+1,$map_start-$_->[1]+1]} @ranges;
		$absref   = $mapper->seq_id;
	    }
	}

        # this inhibits mapping outside the displayed region
        if ($optimize) {
            my $in_window;
            foreach (@abs_segs) {
                next unless defined $_->[0] && defined $_->[1];
		my ($left,$right) = sort {$a<=>$b} @$_;
                $in_window ||= $_->[0] <= $right && $_->[1] >= $left;
            }
            return $in_window ? ( $absref, @abs_segs ) : ();
        }
        else {
            return ( $absref, @abs_segs );
        }
    };
    return $closure;
}

sub features_by_prefix {
    my $self  = shift;
    my $match = shift;
    my $limit = shift;

    # do name search for autocomplete...
    # only local databases for now
    my $local_dbs = $self->local_dbs;
    my (@f,$count);
    my $source = $self->source;
    for my $dbid (keys %{$local_dbs}) {
	my $options = 
	    Bio::Graphics::Browser2::Region->parse_searchopts($source->search_options($dbid));
	next unless $options && $options->{autocomplete};

	my $db = $source->open_database($dbid);
	eval {
	    my $i = $db->get_seq_stream(-name=>"${match}*",
					-aliases=>1);
	    while (my $f = $i->next_seq) {
		push @f,$f;
		last if $limit && $count++ > $limit;
	    }
	};
    }
    return \@f;
}

sub get_seq_stream {
    my $self = shift;

    my @search_args = @_;
    my $local_dbs = $self->local_dbs;
    my @dbs       = map {$self->source->open_database($_)}keys %$local_dbs;
    return Bio::Graphics::Browser2::MetaDB->new(\@search_args,\@dbs);
}

##################################################################33
# META SEGMENT DEFINITIONS
##################################################################33
package Bio::Graphics::Browser2::MetaSegment;

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
#			-class  => eval {$segment->class} || 'Sequence',
			@_
	);
}

sub get_seq_stream {
    my $self = shift;
    my $features = $self->features(@_);
    return Bio::Graphics::Browser2::MetaSegment::Iterator->new($features);
}

package Bio::Graphics::Browser2::MetaSegment::Iterator;

sub new {
    my $class    = shift;
    my $features = shift;
    return bless {f=>$features},ref $class || $class;
}

sub next_seq {
    my $f = shift->{f};
    return shift @$f;
}

package Bio::Graphics::Browser2::MetaDB;

sub new {
    my $self = shift;
    my ($search_args,$dbs) = @_;
    return bless {
	dbs     => $dbs,
	args    => $search_args,
	current => undef
    },ref $self || $self;
}

sub next_seq {
    my $self = shift;
    while (1) {
	if (my $iterator = $self->{current}) {
	    my $f = $iterator->next_seq;
	    return $f if defined $f;
	}

	my $next_db = shift @{$self->{dbs}} or return;
	$self->{current} = $next_db->get_seq_stream(@{$self->{args}});
    }
}

1;

__END__


=head1 SEE ALSO

L<Bio::Graphics::Browser2::Region>,
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

