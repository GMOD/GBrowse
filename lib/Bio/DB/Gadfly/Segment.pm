package Bio::DB::Gadfly::Segment;

# $Version$

use strict;
use Bio::Das::SegmentI;
use Bio::Root::Root;
use Bio::DB::GFF::Util::Rearrange;
use GxAdapters::ConnectionManager;

use vars '@ISA','$VERSION';
@ISA     = qw(Bio::Root::Root Bio::Das::SegmentI);
$VERSION = '0.01';

=head1 Bio::DB::Gadfly::Segment - Das::SegmentI adaptor for GadFly database

=head1 SYNOPSIS

=head1 METHODS

Methods follow

=cut

=head2 $s = Bio::DB::Gadfly::Segment->new($obj)

Create a segment object.  The passed object can be a
BioModel::SeqFeature object, a BioModel::Seq object, or a
BioModel::AnnotatedSeq.  We evaluate in a lazy way.

=cut

# INSTEAD OF LAZY EVALUATION, GIVE AS OPTION ALTERNATIVE IN WHICH CALL GET_ANNOTATEDSEQ() in new()
# store result and then grep for features of certain types

sub new {
  my $class = shift;
  my ($name,$start,$end,$gx,$other) = rearrange([qw(NAME START END GX)],@_);
  return bless {
		ref   => $name,
		start => $start,
		end   => $end,
		gx    => $gx,
	       },ref($class) || $class;
  my $self  = bless {},ref($class) || $class;
  $self->model($model);
}

=head2 $ref = $s->seq_id

Return the sequence ID, using the ID of the topmost sequence.

=cut

sub seq_id { shift->{name} }

=head2 $start = $s->start;

Return the start coordinate using bioperl conventions

=cut

sub start { shift->{start} }

=head2 $end = $s->end

Return the end coordinate using bioperl conventions

=cut

sub end { shift->{end} }

=head2 @features = $db->overlapping_features(@args);

Return a list of Bio::SeqFeatureI objects that overlap this segment.

=cut

# gadfly types
# annotation type space
#     biological names like "gene", "snRNA", etc
#     annotation:gene, annotation:snRNA
# analysis type space
#     "blastx against nonfly"...
#     analysis:blastx_against_nonfly
# scaffold type space
#     scaffold(:nothing)

# chris will implement a to_bioperl_feature() method in the
# genes, analyses and scaffolds

sub overlapping_features {
  my $self   = shift;
  my ($types,$rangetype,$attributes,$iterator);

  if ($_[0] !~ /^-/) {
    $types = [@_];
  } else {
    ($types,$rangetype,$attributes,$iterator,$callback)
      = rearrange([qw(TYPES RANGETYPE ATTRIBUTES ITERATOR CALLBACK)]);
  }

  $types ||= [];

  # turn the thing into an annotated segment
  my $segment = $self->_tosegment;

  # This is the nasty part: The following methods require special handling:
  #            transcript  -- find genes and turn into transcripts
  #            segment     -- find a segment - not sure what that is
  # everything else is handled as an analysis
  my %types          = map {$_=>1} @$types;
  my @gene_types     = grep {/^transcript(:|$ )/x} keys %types;
  my @scaffold_types = grep {/^scaffold(:|$ )/x} keys %types;
  my %special_types  = map {$_=>1} (@gene_types,@segment_types);
  my @analysis_types = grep {!$special_types{$_}} keys %types;

  my $all_types++ if !(@gene_types+@segment_types+@analysis_types);

  my @features;

  if ($all_types or @gene_types) {
    # to_bioperl_feature() requires new code from Chris
    push @features,map {$_->to_bioperl_feature} $self->_get_genes($segment,\@gene_types);
  }
  if ($all_types or @scaffold_types) {
    push @features,map {$_->to_bioperl_feature} $self->_get_scaffolds($segment,\@scaffold_types);
  }
  if ($all_types or @analysis_types) {
    push @features,map {$_->to_bioperl_feature} $self->_get_analyses($segment,\@analysis_types);
  }

  # iteration doesn't really help us with gadfly, but we support it because
  # it's part of the interface.
  if ($iterator) {
    return Bio::DB::Gadfly::SegmentIterator->new(\@features);
  }

  elsif ($callback) {
    foreach (@features) {
      my $result = $callback->($_);
      last unless $result;
    }
    return scalar @features;
  }

  else {
    return @features;
  }
}

#NOTE: the Bio::SeqIO::game class should be able to dump out GAME/XML
# from these objects by using the gx() method and the start/end position
# information.

=head2 $gx_adaptor = $db->gx([$new_adaptor])

Get or set the underlying GxAdapter (note spelling difference).

=cut

sub gx {
  my $self = shift;
  my $d    = $self->{gx};
  $self->{gx} = shift if @_;
  $d;
}

sub _get_genes {
  my $self = shift;
  my ($segments,$types) = @_;
  # $gx->lget_Genes() for lazy evaluation
  # $as->gene_list() for non-lazy evaluation
}

sub _get_scaffolds {
  # lazy:
  # @scaffolds = $gx->lget_ResultSet({constraints...,analysis_program=>'tiling_path'});
  # non-lazy:
  # $analysis = $as->get_analysis('tiling_path')
  # @scaffolds = $analysis->result_set_list()
  # @scaffolds are result sets
}

sub _get_analyses {
  # lazy:
  # (this requires a new version from Chris....)
  # @analyses = $gx->lget_ResultSet({constraints...,analysis_types=>['types'...]})
  # non-lazy
  # $all_analyses = $as->analysis_list()
  # foreach ($all_analyses) { next unless $_->get_property('type'); do something }
}

sub _tosegment {
  my $self = shift;
  return $self->{segment} if exists $self->{segment};
  $self->{segment} = $self->gx->get_AnnotatedSeq({range=>$self->_range})
}

sub _range {
  my $self = shift;
  return "$self->{name}:$self->{start}..$self->{end}"
}


1;

__END__

=head1 AUTHOR

Lincoln Stein, E<lt>lstein@cshl.orgE<gt>

=head1 SEE ALSO

L<Bio::DB::GFF>,
L<Bio::DasI>,
