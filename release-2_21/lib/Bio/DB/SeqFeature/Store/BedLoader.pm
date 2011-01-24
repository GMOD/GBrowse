package Bio::DB::SeqFeature::Store::BedLoader;

use strict;
use Carp 'croak';
use Text::ParseWords 'shellwords';
use Bio::DB::SeqFeature::Store::LoadHelper;

use base 'Bio::DB::SeqFeature::Store::GFF3Loader';

sub create_load_data { #overridden
  my $self = shift;
  $self->SUPER::create_load_data;
  $self->{load_data}{IndexSubfeatures}    = $self->index_subfeatures();
  $self->{load_data}{TemporaryLoadID} ||= "F0000";
  $self->{load_data}{track_conf}{name}||= 'Feature0000';
  $self->{load_data}{LoadedTypes}       = {};
    

  $self->{load_data}{Helper}           = 
      Bio::DB::SeqFeature::Store::LoadHelper->new($self->{tmpdir});
}

sub load_line {
    my $self = shift;
    my $line = shift;
    chomp $line;

    # make sure these are always defined
    if ($line =~ /^track/) {
	$self->handle_track_conf($line);
    } elsif ($line) {
	$self->handle_feature($line);
    }
}

sub handle_track_conf {
    my $self = shift;
    my $line = shift;
    my $load_data  = $self->{load_data};
    my %attributes = $self->parse_track_line($line);
    $load_data->{track_conf}  = \%attributes;
}

sub parse_track_line {
    my $self = shift;
    my $line = shift;
    my @tokens = shellwords($line);
    shift @tokens;
    return map {split '='} @tokens;
}

sub handle_feature {
    my $self = shift;
    my $line = shift;
    my ($chrom,$chromStart,$chromEnd, # mandatory
	$name,$score,$Strand,
	$thickStart,$thickEnd,$itemRGB,
	$blockCount,$blockSizes,$blockStarts) = split /\s+/,$line;

    my $ld       = $self->{load_data};
    my $load_id  = $ld->{TemporaryLoadID}++;

    # status reporting
    if (++$ld->{count} % 1000 == 0) {
	my $now = $self->time();
	my $nl = -t STDOUT && !$ENV{EMACS} ? "\r" : "\n";
	local $^W = 0; # kill uninit variable warning
	$self->msg(sprintf("%d features loaded in %5.2fs (%5.2fs/1000 features)...%s$nl",
			   $ld->{count},$now - $ld->{start_time},
			   $now - $ld->{millenium_time},
			   ' ' x 80
		   ));
	$ld->{millenium_time} = $now;
    }


    my $isGene = $thickStart || $blockCount;
    my $method = $isGene ? 'mRNA' : 'region';
    my $source = $ld->{track_conf}{name};  # bogus, but works

    $ld->{LoadedTypes}{"$method:$source"}++;

    my $strand = $Strand && $Strand eq '-' ? -1 : +1;
    my $start  = $chromStart+1;
    my $end    = $chromEnd;

    my %attributes;
    %attributes = (RGB => $itemRGB) if $itemRGB && $itemRGB;

    # create parent feature
    my @args = (-display_name => $name,
		-seq_id       => $chrom,
		-start        => $start,
		-end          => $end,
		-strand       => $strand,
		-score        => $score,
		-primary_tag  => $method,
		-source       => $source,
		-tag          => \%attributes,
		-attributes   => \%attributes,
	);

    my $feature = $self->sfclass->new(@args);    
    $feature->object_store($self->store) if $feature->can('object_store');  # for lazy table features
    
    $ld->{CurrentFeature}    = $feature;
    $ld->{CurrentID}         = $load_id;

    my $helper = $ld->{Helper};
    $helper->indexit($load_id=>1);   # index toplevel features
    $helper->toplevel($load_id=>1) if !$self->{fast};

    $self->store_current_feature();  # this will clear out CurrentFeature and CurrentID

    if ($isGene) {
	my @children;

	# parts is an array of [start,end,method]
	my ($parts) = $self->split_gene_bits($chromStart,$chromEnd,
					     $thickStart,$thickEnd,
					     $blockCount,$blockSizes,$blockStarts);
	for my $u (@$parts) {
	    my $f = $self->sfclass->new(-seq_id => $chrom,
					-start  => $u->[0],
					-end    => $u->[1],
					-strand => $strand,
					-source => $source,
					-score  => $score,
					-primary_tag => $u->[2],
					-attributes  => \%attributes,
		);
	    my $id = $ld->{TemporaryLoadID}++;
	    $ld->{CurrentFeature} = $f;
	    $ld->{CurrentID}      = $id;
	    $self->store_current_feature();
	    push @children,$id;
	}

	# remember parentage using the helper
	for my $child_id (@children) {
	    $helper->add_children($load_id=>$child_id);
	}
    }
}

sub split_gene_bits {
    my $self = shift;
    my ($chromStart,$chromEnd,
	$thickStart,$thickEnd,
	$numBlocks,$blockSizes,$blockStarts) = @_;

    # no internal structure, so just create UTRs and one CDS in the middle
    # remember that BED format uses 0-based indexing, hence the +1s
    unless ($blockSizes) {  
	my @bits = ([$chromStart+1,$thickStart,'UTR'],
		    [$thickStart+1,$thickEnd,'CDS'],
		    [$thickEnd+1,$chromEnd,'UTR']);
	return \@bits;
    }

    # harder -- we have internal exons
    my @block_sizes  = split ',',$blockSizes;
    my @block_starts = split ',',$blockStarts;
    croak "Invalid BED file: blockSizes != blockStarts"
	unless @block_sizes == @block_starts && @block_sizes == $numBlocks;

    my @bits;
    for (my $i=0;$i<@block_starts;$i++) {
	my $start = $chromStart + $block_starts[$i];	
	my $end   = $chromStart + $block_starts[$i] + $block_sizes[$i];

	if ($start < $thickStart) {
	    if ($end < $thickStart) {          # UTR wholly contained in an exon
		push @bits,[$start+1,$end,'UTR'];
	    }
	    elsif ($end >= $thickStart) {      # UTR partially contained in an exon
		push @bits,[$start+1,$thickStart,'UTR'];
		push @bits,[$thickStart+1,$end,'CDS'];
	    }
	}

	elsif ($start < $thickEnd) {
	    if ($end <= $thickEnd) {           # CDS wholly contained in an exon
		push @bits,[$start+1,$end,'CDS'];
	    }
	    elsif ($end > $thickEnd) {         # CDS partially contained in an exon
		push @bits,[$start+1,$thickEnd,'CDS'];
		push @bits,[$thickEnd+1,$end,'UTR'];
	    }
	}

	elsif ($start > $thickEnd) {
	    push @bits,[$start+1,$end,'UTR'];  # UTR wholly contained in an exon
	}

	elsif ($start == $thickEnd) {
	    push @bits,[$start+1,$end,'UTR'];  # non-coding gene ?!
	}
	else {
	    croak "Programmer error when calculating UTR bounds";
	}

    }

    return \@bits;
}

sub loaded_types {
    my $self = shift;
    my $ld   = $self->{load_data};
    return keys %{$ld->{LoadedTypes}};
}

1;
