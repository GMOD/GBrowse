package Bio::Graphics::Browser2::TrackDumper::RichSeqMaker;

use strict;
use Bio::Seq::RichSeq;
use Bio::PrimarySeq;
use Bio::SeqFeature::Generic;
use Bio::Location::Simple;
use Bio::Location::Split;
use Bio::Location::Fuzzy;
use POSIX qw(strftime);

sub stream_to_rich_seq {
    my $self   = shift;
    my ($segment,$stream) = @_;

    my $seq  = new Bio::Seq::RichSeq(-display_id       => $segment->display_id,
				     -desc             => $segment->desc,
				     -accession_number => $segment->accession_number,
				     -alphabet         => $segment->alphabet || 'dna',
	);
    $seq->add_date(strftime("%d-%b-%Y",localtime));
    my $ps = $segment->primary_seq;

    # not sure if the following workaround really necessary
    if ($ps->isa('Bio::PrimarySeq')) {
	$seq->primary_seq($ps);
    } elsif (ref $ps && $ps->can('seq')) {
	$seq->primary_seq($ps->seq)
    } else {
	$seq->primary_seq(Bio::PrimarySeq->new(-seq=>$ps));
    }

    $segment->absolute(1);
    my $offset     = $segment->start - 1;
    my $segmentend = $segment->length;

    while (my $feature = $stream->next_seq) {
	$self->_add_feature($seq,$feature,$offset,$segmentend);
    }
    return $seq;
}

sub _add_feature {
    my $self = shift;
    my ($seq,$feature,$offset,$length,$parent_type,$parent_id) = @_;

    my $score = $feature->score;
    $score    = ref $score eq 'HASH' ? $score->{sumData}/$score->{validCount} : $score;
    my $id    = $feature->display_name || eval {($feature->get_tag_values('load_id'))[0]}|| $feature->primary_id ;

    my $bsg    = Bio::SeqFeature::Generic->new(-primary_tag => $feature->primary_tag,
					       -source_tag  => $feature->source_tag,
					       -frame       => eval{$feature->phase}||eval{$feature->frame}||undef,
					       -score       => $score,
	);
    for my $tag ( $feature->get_all_tags ) {
	next if $tag =~ /^(load_id|parent_id)$/;
	my %seen;
	$bsg->add_tag_value($tag, grep { ! $seen{$_}++ } 
			    grep { defined } $feature->get_tag_values($tag));
    }
    if ($parent_type && $parent_id) {
	$bsg->add_tag_value($parent_type=>$parent_id) if $parent_id;
    }

    $bsg->add_tag_value('name',$id) if $id;

    my @subf      = $feature->get_SeqFeatures;
    my @loc;

    # this detects the case in which a feature is "parent" to its subparts,
    # such as CDS => CDS1..CDS2..CDS3
    my %subftypes = map {$_->primary_tag=>1} @subf;
    if (keys %subftypes == 1 && $subftypes{$feature->primary_tag}) {
	@loc  = $feature->each_Location;
	@subf = ();
    } else {
	@loc  = Bio::Location::Simple->new(-start=>$feature->start,
					   -end  =>$feature->end);
    }

    my $location = Bio::Location::Split->new;
    for my $sl (@loc) {
	my $start = $sl->start - $offset;
	my $end   = $sl->end   - $offset;
	next if $start < 1 && $end < 1;
	next if $start > length && $end > $length;
	my $fuzzy;
	if ($start < 1) {
	    $fuzzy++;
	    $start = "<1";
	}
	if ($end > $length) {
	    $fuzzy++;
	    $end = ">$length";
	}
	my $loc = $fuzzy ? Bio::Location::Fuzzy->new(-start   => $start,
						     -end     => $end,
						     -strand  => $feature->strand,
						     -location_type => '..')
	                 : Bio::Location::Simple->new(-start  => $start,
						      -end    => $end,
						      -strand => $feature->strand);
	$location->add_sub_Location($loc);
    }

    return unless $location->sub_Location;
    $bsg->location($location);
    $seq->add_SeqFeature($bsg);
    $self->_add_feature($seq,$_,$offset,$length,$feature->primary_tag,$id)
	foreach @subf;
}

1;
