package Bio::Graphics::Browser2::Region;

# provide method for fetching and manipulating the current
# region or regions.

use strict;
use warnings;
use Bio::Graphics::Browser2::Shellwords;
use constant DEBUG=>0;

sub new {
    my $self  = shift;
    my $args  = shift;
    my ($source,$db,$state,$searchopts) 
	= @{$args}{'source','db','state','searchopts'};

    $searchopts ||= 'default';

    return bless {
	source     => $source,
	db         => $db,
	state      => $state,
	searchopts => $self->parse_searchopts($searchopts),
    },ref($self) || $self;
}

sub source     { shift->{source} }
sub state      { shift->{state}  }
sub db         { shift->{db}     }
sub searchopts { shift->{searchopts}  }

sub parse_searchopts {
    my $self      = shift;
    my $optstring = shift;

    my @default   = qw(exact wildcard stem fulltext heuristic);
    my %all       = map {$_=>1} qw(exact wildcard stem fulltext heuristic autocomplete);

    my %opts;
    my @tokens    = split /[\s,]+/,lc $optstring;
    @tokens = ('default') unless @tokens;

    for my $t (@tokens) {
	my ($sign,$token) = $t =~ /([+-]?)(\w+)/;

	if ($token eq 'all') {
	    $opts{$_}++ foreach keys %all;
	    next;
	}
	
	if ($token eq 'none') {
	    %opts = ();
	    next;
	}

	if ($token eq 'default') {
	    $opts{$_}++ foreach @default;
	    next;
	}
	
	next unless $all{$token};
	$opts{$token}++ if $sign eq '+' or !$sign;

	delete $opts{$token} if $sign eq '-';
    }

    return \%opts;
}

sub feature_count { 
    my $self = shift;
    my $features = $self->features;
    return 0 unless $features;
    return scalar @$features;
}

# get/set list of features that we are working on
sub features {
    my $self = shift;
    my $d    = $self->{features};
    $self->{features} = shift if @_;
    return $d;
}

# lazy retrieval of current segment(s) -- may transform features if needed
sub segments {
    my $self = shift;
    $self->{segments} ||= 
	$self->features2segments($self->features) if $self->features;
    return $self->{segments} || [];
}

# lazy retrieval of first segment
sub seg {
  my $self = shift;
  unless (exists $self->{segment}) {
      my $segments     = $self->segments;
      $self->{segment} = $segments->[0] if @$segments;
      if (my $seg = $self->{segment}) {
	  my $state = $self->state;
	  $state->{ref}   = $seg->seq_id;
	  $state->{start} = $seg->start;
	  $state->{stop}  = $seg->end;
      }
  }
  return $self->{segment};
}

# lazy retrieval of first whole segment
sub whole_seg {
  my $self = shift;
  unless (exists $self->{whole_segment}) {
      my $whole_seg = $self->get_whole_segment($self->seg);
      $self->{whole_segment} = $whole_seg;
      my $state         = $self->state;
      $state->{seg_min} = $whole_seg->start;
      $state->{seg_max} = $whole_seg->end;
  }
  return $self->{whole_segment};
}

sub set_features_by_region {
    my $self = shift;
    my ($ref,$start,$stop) = @_;
    my $divider  = $self->source->unit_divider;
    my $features = $self->lookup_features($ref,$start/$divider,$stop/$divider);
    $self->features($features);
    return $features;
}

# For backward compatibility, you can call search_features() either
# with a scalar string, in which case it will be treated as a search
# string to be parsed and search (for example "chrI:1000.2000") or
# call with a hashref containing the arguments to be passed to
# the db adaptor's features() method.
sub search_features {
  my $self         = shift;
  my $args         = shift;

  my $db    = $self->db;
  my $state = $self->state;

  $args   ||= { };
  unless (%$args) {
      return unless $state->{name};
      $args->{-search_term} = $state->{name};
  }

  warn "SEARCHING FOR ",join ' ',%$args," in $db" if DEBUG; 

  my $features = $self->search_db($args);

  warn "FOUND @$features " if $features && DEBUG;
  $self->features($features);
  return $features;
}


sub features2segments {
  my $self     = shift;
  my $features = shift;
  my $refclass = $self->source->global_setting('reference class') || '';
  my $db       = $self->db;
  my %seenit;
  my @segments = 
      map {
	  my $version = $_->can('version') ? $_->version : undef;
	  $db->segment(-class    => $refclass,
		       -seq_id   => $_->seq_id,
		       -name     => $_->seq_id,  # to avoid breakage due to sloppy API
		       -start    => $_->start||0,
		       -end      => $_->end  ||0,
		       -stop     => $_->end  ||0, # to avoid breakage due to sloppy API
		       -absolute => 1,
		       defined $version ? (-version => $version) : ())
  } grep {
      !$seenit{$_->seq_id,$_->start,$_->end}++} 
    @$features;
  return \@segments;
}

sub get_whole_segment {
  my $self    = shift;
  my $segment = shift;

  my $factory = $self->source->open_database();

  # the segment class has been deprecated, but we still must support it
  my $class   = eval {$segment->seq_id->class} || eval{$factory->refclass};

  my ($whole_segment) = $factory->segment(-class=>$class,
					  -name=>$segment->seq_id);
  $whole_segment   ||= $segment;  # just paranoia
  $whole_segment;
}


sub search_db {
  my $self = shift;
  my $args = shift;
  my ($features);
  if (my $name = $args->{-search_term}) {
      $name =~ tr/a-zA-Z0-9|.'"_*?: ;+-\/\#\[\]//cd;  # remove rude/naughty characters
      my ($ref,$start,$stop,$class,$id) = $self->parse_feature_name($name);
      $features =  $self->lookup_features($ref,$start,$stop,$class,$name,$id);
  }
  elsif ($args->{-name} && $args->{-name}=~/^id:(.+)/) {
      $features =  $self->lookup_features(undef,undef,undef,undef,undef,$1);
  }
  else {
      my @features = $self->db->features(%$args);
      $features    = \@features;
  }
  return wantarray ? @$features : $features;
}

sub lookup_features {
  my $self  = shift;
  my ($name,$start,$stop,$class,$literal_name,$id) = @_;
  my $source = $self->source;

  my $refclass = $source->global_setting('reference class') || 'Sequence';

  my $db      = $self->db;

  my $divisor = $source->unit_divider;
  $start *= $divisor if defined $start;
  $stop  *= $divisor if defined $stop;

  # automatic classes to try
  my @classes = $class ? ($class) 
                       : (split /\s+/,$source->global_setting('automatic classes')||'');

  if (defined $id && $db->can('get_feature_by_id')) { # this overrides everything else
      my $f = $db->get_feature_by_id($id);
      return $f ? [$f] : [];
  }

  my $features = [];

  my $searchopts = $self->searchopts;

 SEARCHING:
  {

      warn "searchopts = ",join ',',%$searchopts if DEBUG;
      unless (%$searchopts) {
	  warn "segment(-name => $name,-start=>$start,-end=>$stop)" if DEBUG;
	  my @f = $db->segment(-name => $name,-start=>$start,-end=>$stop);
	  $features = \@f;
	  last SEARCHING;
      }

      for my $n ([$name,$start,$stop],
		 [$literal_name,undef,undef]) {

	  my ($name_to_try,$start_to_try,$stop_to_try) = @$n;

	  $name_to_try =~ s/([*?])/\\$1/g 
	      unless $searchopts->{wildcard};

	  if ($searchopts->{exact}) {

	      # first try the non-heuristic search
	      for my $class ($class,$refclass,@classes) {
		  $features  = $self->_feature_get($db,
						   $name_to_try,$class,
						   $start_to_try,$stop_to_try);
		  last SEARCHING if @$features;
	      }
	  }

	  # heuristic fetch. Try various abbreviations and wildcards
	  my @sloppy_names = ();

	  if ($searchopts->{heuristic}) {
	      my $seqid_prefix = $source->seqid_prefix;
	      if ($name_to_try =~ /^([\dIVXA-F]+)$/) {
		  my %seenit;
		  my $id = $1;
		  foreach (qw(CHROMOSOME_ Chr chr),$seqid_prefix) {
		      next unless $_;
		      next if $seenit{$_}++;
		      my $n = "${_}${id}";
		      push @sloppy_names,$n;
		  }
	      }

	      # try to remove the chr CHROMOSOME_I
	      if ((my $chr = $name_to_try) =~ s/^(chromosome_?|chr)//i) {
		  push @sloppy_names,$chr;
	      }

	      if ($seqid_prefix && (my $chr = $name_to_try) =~ s/^$seqid_prefix//) {
		  push @sloppy_names,$chr;
	      }
	  }

	  if ($searchopts->{stem}) {
	      push @sloppy_names,"$name_to_try*" 
		  if length $name_to_try >= 3 and $name_to_try !~ /\*$/;
	  }

	  for my $n (@sloppy_names) {
	      for my $c ('',@classes) {
		  $features = $self->_feature_get($db,$n,$c,$start_to_try,$stop_to_try);
		  last SEARCHING if @$features;
	      }
	  }
	  
      }
  }

  if (!@$features && $searchopts->{fulltext}) {
      warn "try a keyword search for $literal_name" if DEBUG;
      $features = $self->_feature_keyword_search($literal_name);
  }

  if ($class) {
      my $regex = quotemeta($class);
      my @f;
      foreach (@$features) {
	  my $c = eval {$_->class};
	  push @f,$_ if ($c && $c =~ /^$regex/i) or $_->primary_tag =~ /^$regex/i;
      }
      $features = \@f;
  }
  
  return $features;
}

sub _feature_get {
  my $self = shift;
  my ($db,$name,$class,$start,$stop) = @_;

  my $refclass = $self->source->global_setting('reference class') || 'Sequence';

  my @argv = (-name  => $name);
  push @argv,(-class => $class) if defined $class;
  push @argv,(-start => $start) if defined $start;
  push @argv,(-end   => $stop)  if defined $stop;

  my @features;
  @features  = grep {$_->length} $db->get_feature_by_name(@argv)   #misnomer -- should be get_features_by_name!
      if !defined($start) && !defined($stop);

  warn "get_feature_by_name(@argv) => @features" if DEBUG;

  @features  = grep {$_->length} $db->get_features_by_alias(@argv) 
      if !@features
      && !defined($start) 
      && !defined($stop) 
      && $db->can('get_features_by_alias');

  warn "get_features_by_alias(@argv) => @features" if DEBUG;

  @features  = grep {$_->length} $db->segment(@argv)               
      if !@features && $name !~ /[*?]/;
  return [] unless @features;

  warn "segment => @features" if DEBUG;

  # Deal with multiple hits.  Winnow down to just those that
  # were mentioned in the config file.
  $class     ||= '';  # to get rid of uninit variable warnings
  my $types = $self->source->_all_types($db);
  my @filtered = grep {
    my $type    = $_->primary_tag;
    my $method  = eval {$_->method} || '';
    my $fclass  = eval {$_->class}  || '';
    $type eq 'Segment'      # ugly stuff accomodates loss of "class" concept in GFF3
      || $type eq 'region'
	|| $types->{$type}
	  || $types->{$method}
	    || !$fclass
	      || $fclass eq $refclass
		|| $fclass eq $class;
  } @features;

  # remove duplicate features -- same name, source, method and position
  warn "before duplicate removal features = @features" if DEBUG;

  my %seenit;
  @features = grep {
      my $key = eval{$_->gff_string} || join (':',$_->type,$_->seq_id,$_->start,$_->end);
      !$seenit{$key}++;
  } @features;

  warn "after duplicate removal features = @features" if DEBUG;

  return \@features;
}

sub _feature_keyword_search {
  my $self       = shift;
  my $searchterm = shift;
  my $source     = $self->source;

  # if they wanted something specific, don't give them non-specific results.
  return if $searchterm =~ /^[\w._-]+:/;

  # Need to untaint the searchterm.  We are very lenient about
  # what is accepted here because we wil be quote-metaing it later.
  $searchterm =~ /([\w .,~!@\#$%^&*()-+=<>?:;\/]+)/;
  $searchterm = $1;

  my $db = $self->db;
  my $max_keywords = $source->global_setting('max keyword results');
  my @matches;
  if ($db->can('search_attributes')) {
    my @attribute_names = shellwords ($source->global_setting('search attributes')||'');
    @attribute_names = ('Note') unless @attribute_names;
    @matches = $db->search_attributes($searchterm,\@attribute_names,$max_keywords);
  } elsif ($db->can('search_notes')) {
    @matches = $db->search_notes($searchterm,$max_keywords);
  }

  my @results;
  for my $r (@matches) {
    my ($name,$description,$score,$type,$id) = @$r;
    my ($seg) = $db->segment($name) or next;
    push @results,Bio::Graphics::Feature->new(-name   => $name,
					      -class  => eval{$name->class} || undef,
					      -desc   => $description,
					      -score  => $score,
					      -ref    => $seg->abs_ref,
					      -start  => $seg->abs_start,
					      -end    => $seg->abs_end,
					      -type   => $type   || 'feature',
					      -primary_id => $id || undef,
					      -factory=> $db);

  }
  return \@results;
}

sub parse_feature_name {
  my $self = shift;
  my $name = shift;

  if ($name =~ /^id:(.+)/) {
      return (undef,undef,undef,undef,$1);
  }

  my ($class,$ref,$start,$stop);
  if (my @a = $self->is_chromosome_region($name)) {
      ($ref,$start,$stop) = @a;
  }

  elsif ($name =~ /^(\w+):([^:]+)$/) {
    $class = $1;
    $ref   = $2;
  }

  else {
    $ref = $name;
  }
  return ($ref,$start,$stop,$class);
}

sub is_chromosome_region {
    my $self = shift;
    my $name = shift;
    if ( ($name !~ /\.\./ and $name =~ /([\w._\/-]+):\s*(-?[-e\d.]+)\s*,\s*(-?[-e\d.]+)\s*$/) or
	 $name =~ /([\w._\/-]+):\s*(-?[-e\d,.]+?)\s*(?:-|\.\.)\s*(-?[-e\d,.]+)\s*$/) {
	my $ref  = $1;
	my $start = $2;
	my $stop  = $3;
	$start =~ s/,//g; # get rid of commas
	$stop  =~ s/,//g;
	return ($ref,$start,$stop);
    }
    return;
}

=head2 $whole = $db->whole_segment ($segment,$settings);

Given a detail segment, return the whole seq_id that contains it

=cut

sub whole_segment {
    my $self    = shift;
    my $segment = shift || $self->seg;
    return unless $segment;
    my $db      = $segment->factory;
    my $class   = eval {$segment->seq_id->class} || eval{$db->refclass} || 'Sequence';
    my ($whole) = $db->segment(-class=>$class,
			       -name=>$segment->seq_id);
    return $whole;
}

=head2 $region = $db->region_segment ($segment,$settings [,$whole]);

Given a detail segment and the current settings, return the region
centered on the segment. The whole segment can be passed if desired --
this will avoid a redundant lookup.

=cut

sub region_segment {
    my $self     = shift;
    my $segment  = shift || $self->seg;
    my $settings = shift;
    my $whole    = shift;

    $whole     ||= $self->whole_segment($segment) or return;

    my $regionview_length = $settings->{region_size}||0;
    my $detail_start      = $segment->start;
    my $detail_end        = $segment->end;
    my $whole_start       = $whole->start;
    my $whole_end         = $whole->end;

   # region can't be smaller than detail
    if ($detail_end - $detail_start + 1 > $regionview_length) { 
	$regionview_length = 3*($detail_end - $detail_start + 1);
    }

    my $midpoint = ($detail_end + $detail_start) / 2;
    my $regionview_start = int($midpoint - $regionview_length/2 + 1);
    my $regionview_end = int($midpoint + $regionview_length/2);

    if ($regionview_length > $whole->length) {
	$regionview_length = $whole->length;
    }

    if ($regionview_start < $whole_start) {
	$regionview_start = 1;
	$regionview_end   = $regionview_length;
    }

    if ($regionview_end > $whole_end) {
	$regionview_start = $whole_end - $regionview_length + 1;
	$regionview_end   = $whole_end;
    }

    my $db       = eval {$segment->factory};
    my $class    = eval {$segment->seq_id->class} || eval{$db->refclass};

    my ($region_segment) = $db ? $db->segment(-class => $class,
					      -name  => $segment->seq_id,
					      -seq_id=>$segment->seq_id,
					      -start => $regionview_start,
					      -end   => $regionview_end)
                              :Bio::Graphics::Feature->new(-name  => $segment->seq_id,
							   -seq_id => $segment->seq_id,
							   -start => $regionview_start,
							   -end   => $regionview_end);
    return $region_segment;
}




1;
