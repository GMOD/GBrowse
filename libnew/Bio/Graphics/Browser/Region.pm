package Bio::Graphics::Browser::Region;

# provide method for fetching and manipulating the current
# region or regions.

use strict;
use warnings;
use Bio::Graphics::Browser::Shellwords;

sub new {
    my $self  = shift;
    my $args  = shift;
    my ($source,$db,$state) = @{$args}{'source','db','state'};

    return bless {
	source => $source,
	db     => $db,
	state  => $state,
    },ref($self) || $self;
}

sub source { shift->{source} }
sub state  { shift->{state}  }
sub db     { shift->{db}     }

sub feature_count { 
    my $self = shift;
    my $features = $self->features;
    return unless $features;
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
      my $segments = $self->segments;
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

sub search_features {
  my $self         = shift;
  my $search_term  = shift;

  my $db    = $self->db;
  my $state = $self->state;
  $search_term ||= $state->{name};
  defined $search_term or return;

  my $features = $self->search_db($search_term);
  $self->features($features);
  return $features;
}

sub features2segments {
  my $self     = shift;
  my $features = shift;
  my $refclass = $self->source->global_setting('reference class');
  my $db       = $self->db;
  my @segments = map {
    my $version = $_->isa('Bio::SeqFeatureI') ? undef : $_->version;
    $db->segment(-class => $refclass,
		 -name  => $_->ref,
		 -start => $_->start,
		 -stop  => $_->end,
		 -absolute => 1,
		 defined $version ? (-version => $version) : ())
    } @$features;
  return \@segments;
}

sub get_whole_segment {
  my $self = shift;

  my $segment = shift;
  my $factory = $segment->factory;

  # the segment class has been deprecated, but we still must support it
  my $class   = eval {$segment->seq_id->class} || eval{$factory->refclass};

  my ($whole_segment) = $factory->segment(-class=>$class,
					  -name=>$segment->seq_id);
  $whole_segment   ||= $segment;  # just paranoia
  $whole_segment;
}

sub search_db {
  my $self = shift;
  my $name = shift;

  my $db    = $self->db;

  my ($ref,$start,$stop,$class) = $self->parse_feature_name($name);

  my $features = $self->lookup_features($ref,$start,$stop,$class,$name);
  return $features;
}

sub lookup_features {
  my $self  = shift;
  my ($name,$start,$stop,$class,$literal_name) = @_;
  my $source = $self->source;

  my $refclass = $source->global_setting('reference class') || 'Sequence';

  my $db      = $self->db;
  my $divisor = $source->global_setting('unit_divider') || 1;
  $start *= $divisor if defined $start;
  $stop  *= $divisor if defined $stop;

  # automatic classes to try
  my @classes = $class ? ($class) : (split /\s+/,$source->global_setting('automatic classes')||'');

  my $features;

 SEARCHING:
  for my $n ([$name,$class,$start,$stop],[$literal_name,$refclass,undef,undef]) {

    my ($name_to_try,$class_to_try,$start_to_try,$stop_to_try) = @$n;

    # first try the non-heuristic search
    $features  = $self->_feature_get($db,$name_to_try,$class_to_try,$start_to_try,$stop_to_try);
    last SEARCHING if @$features;

    # heuristic fetch. Try various abbreviations and wildcards
    my @sloppy_names = $name_to_try;
    if ($name_to_try =~ /^([\dIVXA-F]+)$/) {
      my $id = $1;
      foreach (qw(CHROMOSOME_ Chr chr)) {
	my $n = "${_}${id}";
	push @sloppy_names,$n;
      }
    }

    # try to remove the chr CHROMOSOME_I
    if ($name_to_try =~ /^(chromosome_?|chr)/i) {
      (my $chr = $name_to_try) =~ s/^(chromosome_?|chr)//i;
      push @sloppy_names,$chr;
    }

    # try the wildcard  version, but only if the name is of 
    # significant length;

    # IMPORTANT CHANGE: we used to put stars at the beginning 
    # and end, but this killed performance!
    push @sloppy_names,"$name_to_try*" if length $name_to_try > 3 and $name_to_try !~ /\*$/;

    for my $n (@sloppy_names) {
      for my $c (@classes) {
	$features = $self->_feature_get($db,$n,$c,$start_to_try,$stop_to_try);
	last SEARCHING if @$features;
      }
    }

  }

  unless (@$features) {
    # if we get here, try the keyword search
    $features = $self->_feature_keyword_search($literal_name);
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
  @features  = grep {$_->length} $db->get_feature_by_name(@argv)   if !defined($start) && !defined($stop);
  @features  = grep {$_->length} $db->get_features_by_alias(@argv) if !@features &&
    !defined($start) &&
      !defined($stop) &&
	$db->can('get_features_by_alias');

  @features  = grep {$_->length} $db->segment(@argv)               if !@features && $name !~ /[*?]/;
  return [] unless @features;

  # Deal with multiple hits.  Winnow down to just those that
  # were mentioned in the config file.
  my $types = $self->source->_all_types($db);
  my @filtered = grep {
    my $type    = $_->type;
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

  # consolidate features that have same name and same reference sequence
  # and take the largest one.
  my %longest;
  foreach (@filtered) {
    my $n = $_->display_name.$_->abs_ref.(eval{$_->version}||'').(eval{$_->class}||'');
    $longest{$n} = $_ if !defined($longest{$n}) || $_->length > $longest{$n}->length;
  }

  return [values %longest];
}

sub _feature_keyword_search {
  my $self       = shift;
  my $searchterm = shift;
  my $source     = $self->source;

  # if they wanted something specific, don't give them non-specific results.
  return if $searchterm =~ /^[\w._-]+:/;

  # Need to untaint the searchterm.  We are very lenient about
  # what is accepted here because we wil be quote-metaing it later.
  $searchterm =~ /([\w .,~!@\#$%^&*()-+=<>?\/]+)/;
  $searchterm = $1;

  my $db = $self->db;
  my $max_keywords = $source->global_setting('max keyword results');
  my @matches;
  if ($db->can('search_attributes')) {
    my @attribute_names = shellwords ($source->global_setting('search attributes'));
    @attribute_names = ('Note') unless @attribute_names;
    @matches = $db->search_attributes($searchterm,\@attribute_names,$max_keywords);
  } elsif ($db->can('search_notes')) {
    @matches = $db->search_notes($searchterm,$max_keywords);
  }

  my @results;
  for my $r (@matches) {
    my ($name,$description,$score) = @$r;
    my ($seg) = $db->segment($name) or next;
    push @results,Bio::Graphics::Feature->new(-name   => $name,
					      -class  => $name->class,
					      -type   => $description,
					      -score  => $score,
					      -ref    => $seg->abs_ref,
					      -start  => $seg->abs_start,
					      -end    => $seg->abs_end,
					      -factory=> $db);

  }
  return \@results;
}

sub parse_feature_name {
  my $self = shift;
  my $name = shift;

  my ($class,$ref,$start,$stop);
  if ( ($name !~ /\.\./ and $name =~ /([\w._\/-]+):(-?[-e\d.]+),(-?[-e\d.]+)$/) or
      $name =~ /([\w._\/-]+):(-?[-e\d,.]+?)(?:-|\.\.)(-?[-e\d,.]+)$/) {
    $ref  = $1;
    $start = $2;
    $stop  = $3;
    $start =~ s/,//g; # get rid of commas
    $stop  =~ s/,//g;
  }

  elsif ($name =~ /^(\w+):(.+)$/) {
    $class = $1;
    $ref   = $2;
  }

  else {
    $ref = $name;
  }
  return ($ref,$start,$stop,$class);
}



1;
