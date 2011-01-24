=head1 NAME

Bio::DB::GFF::Aggregator::waba_alignment -- A WABA alignment

=head1 SYNOPSIS

  use Bio::DB::GFF;

  # Open the sequence database
  my $db      = Bio::DB::GFF->new( -adaptor => 'dbi:mysql',
                                   -dsn     => 'dbi:mysql:elegans42',
				   -aggregator => ['waba_alignment'],
				 );
  # fetch the synthetic feature type "waba_alignment"
  my @waba    = $db->features('waba_alignment');

 -------------------------------------------------------------------------------------
 Aggregator method: waba_alignment
 Main method:       -none
 Sub methods:       nucleotide_match:waba_weak nucleotide_match:waba_strong 
                    nucleotide_match::waba_coding
 -------------------------------------------------------------------------------------

=head1 DESCRIPTION

Bio::DB::GFF::Aggregator::waba_alignment handles the type of
alignments produced by Jim Kent's WABA program, and was written to be
compatible with the C elegans GFF files.  It aggregates the following
feature types into an aggregate type of "waba_alignment":

   nucleotide_match:waba_weak
   nucleotide_match:waba_strong
   nucleotide_match:waba_coding

=cut

package Bio::DB::GFF::Aggregator::waba_alignment;

use strict;
use Bio::DB::GFF::Aggregator;
use constant CONTINUITY_BIN => 5000;

use vars qw($VERSION @ISA);
@ISA = qw(Bio::DB::GFF::Aggregator);

$VERSION = '0.20';

=head2 method

 Title   : method
 Usage   : $aggregator->method
 Function: return the method for the composite object
 Returns : the string "waba_alignment"
 Args    : none
 Status  : Public

=cut

sub method { 'waba_alignment' }

=head2 part_names

 Title   : part_names
 Usage   : $aggregator->part_names
 Function: return the methods for the sub-parts
 Returns : the list "nucleotide_match:waba_weak", "nucleotide_match:waba_strong" and "nucleotide_match:waba_coding"
 Args    : none
 Status  : Public

=cut

sub part_names {
  return qw(
	  nucleotide_match:waba_weak
	  nucleotide_match:waba_strong
	  nucleotide_match:waba_coding
	   );
}

# we modify the aggregate method so that significant breaks in continuity
# result in distinct groups.  This is done by binning the absolute difference
# between the source and target coordinates.  Mostly contiguous 
sub aggregate {
  my $self = shift;
  my $features = shift;
  my $factory  = shift;

  my $meth        = $self->method;
  my $main_method = $self->get_main_name;
  my $matchsub    = $self->match_sub($factory) or return;
  my $passthru    = $self->passthru_sub($factory);

  my (%aggregates,@result);
  for my $feature (@$features) {
    if ($feature->group && $matchsub->($feature)) {
      my $bin = get_bin($feature);
      if ($main_method && lc $feature->method eq lc $main_method) {
	$aggregates{$feature->group,$feature->ref,$bin}{base} ||= $feature->clone;
      } else {
	push @{$aggregates{$feature->group,$feature->ref,$bin}{subparts}},$feature;
      }
      push @result,$feature if $passthru && $passthru->($feature);

    } else {
      push @result,$feature;
    }
  }

  # aggregate components
  my $pseudo_method        = $self->get_method;
  my $require_whole_object = $self->require_whole_object;
  foreach (keys %aggregates) {
    if ($require_whole_object && $self->components) {
      next unless $aggregates{$_}{base} && $aggregates{$_}{subparts};
    }
    my $base = $aggregates{$_}{base};
    unless ($base) { # no base, so create one
      my $first = $aggregates{$_}{subparts}[0];
      $base = $first->clone;     # to inherit parent coordinate system, etc
      $base->score(undef);
      $base->phase(undef);
    }
    $base->method($pseudo_method);
    $base->source('waba') if $pseudo_method eq $meth;
    $base->add_subfeature($_) foreach @{$aggregates{$_}{subparts}};
    $base->adjust_bounds;
    $base->compound(1);  # set the compound flag
    push @result,$base;
  }
  @$features = @result;
}

sub get_bin {
  my $feature = shift;
  my $target = $feature->target or return 0;
  my ($start,$end) = ($target->start,$target->end);
  my $distance = $end > $start ? $target->start-$feature->start : $target->start+$feature->start;
  return int(abs($distance)/CONTINUITY_BIN);
}

1;
__END__

=head1 BUGS

None reported.


=head1 SEE ALSO

L<Bio::DB::GFF>, L<Bio::DB::GFF::Aggregator>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2001 Cold Spring Harbor Laboratory.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

