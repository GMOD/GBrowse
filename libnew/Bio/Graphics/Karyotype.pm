package Bio::Graphics::Karyotype;

# $Id: Karyotype.pm,v 1.2 2008-08-20 22:55:35 lstein Exp $
# Utility class to create a display of a karyotype and a series of "hits" on the individual chromosomes
# Used for searching


use strict;
use Bio::Graphics::Panel;
use GD 'gdSmallFont';
use CGI qw(img div b);
use Carp 'croak';

sub new {
  my $class = shift;
  my %args            = @_;
  my $source          = $args{source} or croak "source argument mandatory";
  return bless {
		source=> $source,
		},ref $class || $class;
}

sub db          { shift->source->open_database()    }
sub source      { shift->{source}     }

sub chrom_type  { 
    return shift->source->karyotype_setting('chromosome')   || 'chromosome';
}

sub chrom_width {
    return shift->source->karyotype_setting('chrom_width')  || 'auto';
}

sub chrom_height {
    return shift->source->karyotype_setting('chrom_height') || 100;
}

sub add_hits {
  my $self     = shift;
  my $features = shift;
  $self->{hits} ||= {};
  for my $f (@$features) {
    my $ref = $f->seq_id;
    push @{$self->{hits}{$ref}},$f;
  }
}

sub hits {
  my $self   = shift;
  my $seq_id = shift;
  my $list   = $self->{hits}{$seq_id} or return;
  return @$list;
}

# to sort chromosomes into their proper left->right order
sub sort_sub {
  my $self = shift;
  my $d    = $self->{sort_sub};
  $self->{sort_sub} = shift if @_;
  $d;
}

sub to_html {
  my $self     = shift;
  my $renderer = shift;   # this is some object that supports the generate_image($panel) method
  my $sort_sub = $self->sort_sub || \&by_chromosome_name;

  my $panels = $self->{panels} ||= $self->generate_panels or return;

  my $html;
  for my $seqid (sort {$sort_sub->($panels->{$a}{chromosome},
				   $panels->{$b}{chromosome}
			   )} 
		 keys %{$panels}) {

    my $panel  = $self->{panels}{$seqid}{panel};

    my $url    = $renderer->generate_image($panel->gd);
    my $margin = $self->chrom_height - $panel->gd->height;

    my $imagemap  = $self->image_map(scalar $panel->boxes,"${seqid}.");
    $html     .= 
	div(
	    {-style=>"float:left;margin-top:${margin}px;margin-left:0.5em;margin-right;0.5em"},
	    div({-style=>'position:relative'},
		img({-src=>$url,-border=>0}),
		$imagemap
	    ),
	    div({-align=>'center'},b($seqid))
	);
  }
  return $html;
}

# not really an imagemap, but actually a "rollover" map
sub image_map {
    my $self            = shift;
    my ($boxes,$prefix) = @_;

    my $chromosome = $self->chrom_type;

    $prefix ||= '';
    my $divs = '';

    for (my $i=0; $i<@$boxes; $i++) {
	next if $boxes->[$i][0]->type eq $chromosome;

	my ($left,$top,$right,$bottom) =  @{$boxes->[$i]}[1,2,3,4];
	$left     -= 2;
	$top      -= 2;
	my $width  = $right-$left+3;
	my $height = $bottom-$top+3;
	
	my $name = $boxes->[$i][0]->display_name || "feature id #".$boxes->[$i][0]->primary_id;
	my $id = "${prefix}${i}";
	$divs .= div({-class => 'nohilite',
		      -id    => "box_${id}",
		      -style => "top:${top}px; left:${left}px; width:${width}px; height:${height}px",
		      -title => $name,
		      -onMouseOver=>"k_hilite_feature('$id',true)",
		      -onMouseOut =>"k_unhilite_feature('$id')"
		     },''
	    )."\n";
    }
    return $divs;
}

sub by_chromosome_length ($$) {
  my ($a,$b) = @_;
  my $n1     = $a->length;
  my $n2     = $b->length;
  return $n1 <=> $n2;
}

sub by_chromosome_name ($$){
  my ($a,$b) = @_;
  my $n1     = $a->seq_id;
  my $n2     = $b->seq_id;

  if ($n1 =~ /^\w+\d+/ && $n2 =~ /^\w+\d+/) {
    $n1 =~ s/^\w+//;
    $n2 =~ s/^\w+//;
    return $n1 <=> $n2;
  } else {
    return $n1 cmp $n2;
  }
}

sub chromosomes {
  my $self        = shift;
  my $db          = $self->db;
  my $chrom_type  = $self->chrom_type;
  return $db->features($chrom_type);
}

sub generate_panels {
  my $self = shift;
  my $chrom_type  = $self->chrom_type;
  my $chrom_width = $self->chrom_width;

  my @features    = $self->chromosomes;
  return unless @features;

  my $minimal_width  = 0;
  my $maximal_length = 0;

  for my $f (@features) {
    my $name  = $f->seq_id;
    my $width = length($name) * gdSmallFont->width;
    $minimal_width  = $width if $chrom_width < $width;
    $maximal_length = $f->length if $maximal_length < $f->length;
  }
  $chrom_width = $minimal_width 
    if $chrom_width eq 'auto';
  my $pixels_per_base = $self->chrom_height / $maximal_length;

  # each becomes a panel
  my %results;
  for my $chrom (@features) {
    my $height = int($chrom->length * $pixels_per_base);
    my $panel  = Bio::Graphics::Panel->new(-width => $height,  # not an error, will rotate image later
					   -length=> $chrom->length,
					   -pad_top=>5,
					   -pad_bottom=>5,
	);

    if (my @hits  = $self->hits($chrom->seq_id)) {
      $panel->add_track(\@hits,
#			-glyph   => 'diamond',
			-glyph   => 'generic',
			-height  => 6,
			-bgcolor => 'red',
			-fgcolor => 'red');
    }

    $panel->add_track($chrom,
		      -glyph  => 'ideogram',                   # not an error, will rotate image later
		      -height => $chrom_width,
		      -bgcolor=> 'gneg:white gpos25:gray gpos75:darkgray gpos100:black gvar:var stalk:#666666',
		      -label  => 0,
		      -description => 0);

    $panel->rotate(1);
    $results{$chrom->seq_id}{chromosome} = $chrom;
    $results{$chrom->seq_id}{panel}      = $panel;
  }

  return \%results;
}


1;
