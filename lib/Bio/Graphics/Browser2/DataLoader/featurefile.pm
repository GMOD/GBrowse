package Bio::Graphics::Browser2::DataLoader::featurefile;

# $Id$
use strict;
use base 'Bio::Graphics::Browser2::DataLoader::generic';

sub Loader {
#    return 'Bio::DB::SeqFeature::Store::FeatureFileLoader';
    return 'MyFeatureFileLoader';
}

sub do_fast {0}

package MyFeatureFileLoader;
use Text::ParseWords 'shellwords','quotewords';
use base 'Bio::DB::SeqFeature::Store::FeatureFileLoader';

# Fix a bioperl error. Fix this when a new release of Bioperl
# comes out.
sub handle_feature {
    my $self     = shift;
    local $_     = shift;

    my $ld       = $self->{load_data};

    # handle reference line
    if (/^reference\s*=\s*(.+)/) {
	$ld->{reference} = $1;
	return;
    }

    # parse data lines
    my @tokens = quotewords('\s+',1,$_);
    for (0..2) { # remove quotes from everything but last column
	next unless defined $tokens[$_];
	$tokens[$_] =~ s/^"//;
	$tokens[$_] =~ s/"$//;
    }

    if (@tokens < 3) {      # short line; assume a group identifier
	$self->store_current_feature();
	my $type               = shift @tokens;
	my $name               = shift @tokens;
	$ld->{CurrentGroup}    = $self->_make_indexed_feature($name,$type,'',{_ff_group=>1});
	$self->_indexit($name => 1);
	return;
    }

    my($type,$name,$strand,$bounds,$attributes);
    
    if ($tokens[2] =~ /^([+-.]|[+-]?[01])$/) { # old version
	($type,$name,$strand,$bounds,$attributes) = @tokens;
    } else {                                   # new version
	($type,$name,$bounds,$attributes) = @tokens;
    }

    # handle case of there only being one value in the last column,
    # in which case we treat it the same as Note="value"
    my $attr = $self->parse_attributes($attributes);

    # @parts is an array of ([ref,start,end],[ref,start,end],...)
    my @parts =
        map { [/ (?:([^:\s]+):)? (-?\d+) (?:-|\.\.) (-?\d+) /x ] }
        split /(?:,| )\s*/,
        $bounds;

    # deal with groups -- a group is ending if $type is defined
    # and CurrentGroup is set
    if ($type && $ld->{CurrentGroup}) {
	$self->_store_group();
    }
    
    $type   = '' unless defined $type;
    $name   = '' unless defined $name;
    $type ||= $ld->{CurrentGroup}->primary_tag if $ld->{CurrentGroup};
    
    my $reference = $ld->{reference} || 'ChrUN';
    foreach (@parts) {
	if (defined $_ && ref($_) eq 'ARRAY' 
	    && defined $_->[1] 
	    && defined $_->[2]) 
	{
	    $strand     ||= $_->[1] <= $_->[2] ? '+' : '-';
	    ($_->[1],$_->[2])   = ($_->[2],$_->[1]) if $_->[1] > $_->[2];
	}
	$reference = $_->[0] if defined $_->[0];
	$_ = [@{$_}[1,2]]; # strip off the reference.
    }
    
    # now @parts is an array of [start,end] and $reference contains the seqid
    
    # apply coordinate mapper
    if ($self->{coordinate_mapper} && $reference) {
	my @remapped = $self->{coordinate_mapper}->($reference,@parts);
	($reference,@parts) = @remapped if @remapped;
    }
    
    # either create a new feature or add a segment to it
    my $feature = $ld->{CurrentFeature};
    
    $ld->{OldPartType} = $ld->{PartType};
    if (exists $attr->{Type} || exists $attr->{type})  {
	$ld->{PartType}   = $attr->{Type}[0] || $attr->{type}[0];
    } else {
	$ld->{PartType}   = $type;
    }

    if ($feature) {
	local $^W = 0;  # avoid uninit warning when display_name() is called
	
	# if this is a different feature from what we have now, then we
	# store the current one, and create a new one
	if ($feature->display_name ne $name ||
	    $feature->method       ne $type) {
	    $self->store_current_feature;  # new feature, store old one
	    undef $feature;
	} else { # create a new multipart feature
	    $self->_multilevel_feature($feature,$ld->{OldPartType})
		unless $feature->get_SeqFeatures;
	    my $part = $self->_make_feature($name,
					    $ld->{PartType},
					    $strand,
					    $attr,
					    $reference,
					    @{$parts[0]});
	    $feature->add_SeqFeature($part);
	}
    }

    $feature ||= $self->_make_indexed_feature($name,
					      $type,   # side effect is to set CurrentFeature
					      $strand,
					      $attr,
					      $reference,
					      @{$parts[0]});

  # add more segments to the current feature
  if (@parts > 1) {
      for my $part (@parts) {
	  $type ||= $feature->primary_tag;
	  my $sp  = $self->_make_feature($name,
					 $ld->{PartType},
					 $strand,
					 $attr,
					 $reference,
					 @{$part});
      $feature->add_SeqFeature($sp);
      }
  }
}

1;
