package Bio::Graphics::Karyotype;

# $Id$
# Utility class to create a display of a karyotype and a series of "hits" on the individual chromosomes
# Used for searching


use strict;
use Bio::Graphics::Panel;
use GD 'gdSmallFont';
use CGI qw(img div span b url table TR th td b escapeHTML a br);
use Carp 'croak';

# there is a bug in the ideogram glyph that causes a core dump when
# drawing small chromosomes - this "fixes" the problem
use constant SUPPRESS_SMALL_CHROMOSOMES => 50;  # suppress chromosomes smaller than 50 pixels

sub new {
  my $class = shift;
  my %args            = @_;
  my $source          = $args{source}   or croak "source argument mandatory";
  my $lang            = $args{language};
  return bless {
		source   => $source,
		language => $lang,
		},ref $class || $class;
}

sub db             { shift->data_source->open_database()    }
sub data_source    { shift->{source}     }
sub language       { shift->{language}   }

sub trans       { 
  my $self = shift;
  my $lang = $self->language or return '';
  return $lang->tr(@_);
}

sub chrom_type  { 
    return shift->data_source->karyotype_setting('chromosome')   || 'chromosome';
}

sub chrom_width {
    return shift->data_source->karyotype_setting('chrom_width')  || 16;
}

sub chrom_height {
    return shift->data_source->karyotype_setting('chrom_height') || 140;
}

sub chrom_background {
    my $band_colors     = shift->data_source->karyotype_setting('bgcolor')
	|| 'gneg:white gpos25:gray gpos75:darkgray gpos100:black gvar:var stalk:#666666';
}

sub chrom_background_fallback {
    my $band_colors     = shift->data_source->karyotype_setting('bgfallback')
	|| 'yellow';
}

sub add_hits {
  my $self     = shift;
  my $features = shift;
  $self->{hits} ||= {};

  for my $f (@$features) {
    my $ref = $f->seq_id;
    push @{$self->{hits}{$ref}},$f;
    $self->{hit_count}++;
  }

}

sub hit_count { shift->{hit_count} }

sub seqid_order {
    my $self = shift;
    return $self->{seqid_order} if exists $self->{seqid_order};

    my @chromosomes   = $self->chromosomes;
    my $sort_sub      = $self->sort_sub || \&by_chromosome_name;
    my @sorted_chroms = sort $sort_sub @chromosomes;
    my $i             = 0;
    my %order         = map {$_->seq_id => $i++} @sorted_chroms;

    return $self->{seqid_order} = \%order;
}

sub hits {
  my $self   = shift;
  my $seq_id = shift;

  my $hits = $self->{hits} or return;
  defined $seq_id          or return map {@$_} values %{$hits};

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
  my $self        = shift;
  my $terms2hilite = shift;

  my $sort_order = $self->seqid_order;  # returns a hash of {seqid=>index}

  my $source     = $self->data_source;
  my $panels     = $self->{panels} ||= $self->generate_panels or return;

  my $html;

  my $hit_count = $self->hit_count;
  my $message   = $self->language->tr('HIT_COUNT',$hit_count);
  $html        .= CGI::h2($message);

  for my $seqid (
      sort {$sort_order->{$a} <=> $sort_order->{$b}} keys %$panels
      ) {

    my $panel  = $self->{panels}{$seqid}{panel};
    # workaround bug/coredump in ideogram glyph
    next if $panel->height < SUPPRESS_SMALL_CHROMOSOMES;

    my $url    = $source->generate_image($panel->gd);

    my $margin = Bio::Graphics::Panel->can('rotate') 
	         ? $self->chrom_height - $panel->gd->height
                 : 5;

    my $imagemap  = $self->image_map(scalar $panel->boxes,"${seqid}.");
    $html     .= 
	div(
	    {-style=>"cursor:default;float:left;margin-top:${margin}px;margin-left:0.5em;margin-right;0.5em"},
	    div({-style=>'position:relative'},
		img({-src=>$url,-border=>0}),
		$imagemap
	    ),
	    div({-align=>'center'},b($seqid))
	);
  }

  my $table = $self->hits_table($terms2hilite);

  return $html.br({-clear=>'all'}).$table;
}

# not really an imagemap, but actually a "rollover" map
sub image_map {
    my $self            = shift;
    my $boxes           = shift;

    my $chromosome = $self->chrom_type;

    my $divs = '';

    for (my $i=0; $i<@$boxes; $i++) {
	next if $boxes->[$i][0]->primary_tag eq $chromosome;

	my ($left,$top,$right,$bottom) =  @{$boxes->[$i]}[1,2,3,4];
	$left     -= 2;
	$top      -= 2;
	my $width  = $right-$left+3;
	my $height = $bottom-$top+3;
	
	my $name = $boxes->[$i][0]->display_name || "feature id #".$boxes->[$i][0]->primary_id;
	my $id   = $self->feature2id($boxes->[$i][0]);
	my $link = $self->feature2link($boxes->[$i][0]);
	$divs .= div({-class => 'nohilite',
		      -id    => "box_${id}",
		      -style => "z-index:10; top:${top}px; left:${left}px; width:${width}px; height:${height}px",
		      -title => $name,
		      -onMouseOver=>"k_hilite_feature(this,true)",
		      -onMouseOut =>"k_unhilite_feature(this)",
		      -onMouseDown=>"location.href='$link'",
		     },'&nbsp;'
	    )."\n";
    }
    return $divs;
}

sub feature2link {
    my $self    = shift;
    my $feature = shift;
    my $url      = url(-absolute=>1,-path_info=>1)."?name=";
    my $match_id = eval {$feature->primary_id};
    my $class    = eval {$feature->class};
    my $name     = $feature->display_name || '';
    my $fid      =  $match_id 
 	                && $match_id !~ /\w+:\w+\(/   # work around a bioperl bug
                               ? "id:$match_id"
 	           : $class    ? "$class:$name" 
 		   : $name;
    my $dbid  = $feature->gbrowse_dbid if $feature && $feature->can('gbrowse_dbid');
    $dbid   ||= '';
    return "$url$fid;dbid=$dbid";
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

  if ($n1 =~ /^\d+$/    && $n2 =~ /^\d+$/) {
      return $n1 <=> $n2;
  }
  elsif ($n1 =~ /^\w+\d+$/ && $n2 =~ /^\w+\d+$/) {
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
  my @chroms      = $db->features($chrom_type);
  
  # if no chromosomes defined, then generate from seqids
  unless (@chroms) {
      my @seq_ids = keys %{$self->{hits}};
      @chroms     = map {
	  Bio::Graphics::Feature->new(
	      -name   => $_->display_name,
	      -seq_id => $_->seq_id,
	      -start  => 1,
	      -end    => $_->length,
	      -type   => 'chromosome')
      } map {$db->segment(-name=>$_)} @seq_ids;
  }
  return @chroms;
}

sub generate_panels {
  my $self   = shift;
  my $format = shift || 'GD';

  my $image_class = $format;
  $image_class   .= '::Image' unless $image_class =~ /::Image/;
  eval "require $image_class" unless $image_class->can('new');

  my $chrom_type  = $self->chrom_type;
  my $chrom_width = $self->chrom_width;

  my @features    = grep {$self->hits($_->seq_id)} $self->chromosomes;
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
  my $band_colors     = $self->chrom_background;
  my $fallback_color  = $self->chrom_background_fallback;

  # each becomes a panel
  my %results;
  for my $chrom (@features) {
    my $height = int($chrom->length * $pixels_per_base);
    $height    = 20 if $height < 20;  # prevent tiny tiny chromosomes
    my $panel  = Bio::Graphics::Panel->new(-width => $height,  # not an error, will rotate image later
					   -length=> $chrom->length,
					   -pad_top   =>10,
					   -pad_bottom=>10,
					   -pad_right => 0,
					   -bgcolor   => $self->data_source->global_setting('overview bgcolor')
					    || 'wheat:0.5',
					   -image_class => $format,
	);

    my @hits  = $self->hits($chrom->seq_id);
    $panel->add_track(\@hits,
		      -glyph   => sub {
			  my $feature = shift;
			  return $feature->length/$chrom->length > 0.05
			      ? 'generic'
			      : 'diamond';
		      },
		      -glyph => 'generic',
		      -maxdepth => 0,
		      -height  => 6,
		      -bgcolor => 'red',
		      -fgcolor => 'red',
		      -bump    => -1,
	);

    my $rotate = $panel->can('rotate') && $image_class->can('copyRotate90');

    my $method = $rotate ? 'add_track' : 'unshift_track';

    $panel->$method($chrom,
		    -glyph      => 'ideogram',                   # not an error, will rotate image later
		    -height     => $chrom_width,
		    -bgcolor    => $band_colors,
		    -bgfallback => $fallback_color,
		    -label    => 0,
		    -description => 0);

    $panel->rotate(1) if $rotate;      # need bioperl-live from 20 August 2008 for this to work
    $results{$chrom->seq_id}{chromosome} = $chrom;
    $results{$chrom->seq_id}{panel}      = $panel;
  }

  return \%results;
}

sub feature2id {
    my $self              = shift;
    my $feature           = shift;
    return overload::StrVal($feature);
}

sub hits_table {
    my $self                  = shift;
    my $term2hilite           = shift;

    local $^W = 0; # quash uninit variable warnings

    my @hits = $self->hits;

    my $regexp = join '|',($term2hilite =~ /(\w+)/g) 
	if defined $term2hilite;

    my $na   = $self->trans('NOT_APPLICABLE') || '-';

    my $sort_order = $self->seqid_order;
    my $url  = url(-absolute=>1,-path_info=>1)."?name=";

    # a way long map call here
    my @rows      = map {
	my $name  = $_->display_name || '';
	my $link  = $self->feature2link($_);
	my $id    = $self->feature2id($_);             # as an internal <div> id for hilighting
	my $pos   = $_->seq_id.':'.$_->start.'..'.$_->end;
	my $desc  = escapeHTML(Bio::Graphics::Glyph::generic->get_description($_));
	$desc =~ s/($regexp)/<b class="keyword">$1<\/b>/ig if $regexp;
	$desc =~ s/(\S{60})/$1 /g;  # wrap way long lines
	    
	TR({-class=>'nohilite',
	    -id=>"feature_${id}",
	    -onMouseOver=>"k_hilite_feature(this)",
	    -onMouseOut =>"k_unhilite_feature(this)",
	   },
	   th({-align=>'left'},a({-href=>$link},$name)),
	   td(eval{$_->method} || 'region'),
	   td($desc),
	   td(a({-href=>"$url$pos"},$pos)),
	   td($_->score || $na)
	    )
    } sort {
	($b->score||0)    <=>  ($a->score||0)
	    || $sort_order->{$a->seq_id} <=> $sort_order->{$b->seq_id}
	|| $a->start <=> $b->start
	    || $a->end   <=> $b->end
    } @hits;

    my $count = $self->language ? b($self->trans('HIT_COUNT',scalar @hits)) : '';

    return 
	b($count),
	div({-id=>'scrolling_table',-style=>'cursor:default'},
	    table({-class=>'searchbody',-style=>'width:95%'}, #firefox display problems
		  TR(
		      th({-align=>'left'},
			 [$self->trans('NAME'),
			  $self->trans('Type'),
			  $self->trans('Description'),
			  $self->trans('Position'),
			  $self->trans('score')
			 ])
		  ),
		  @rows)
	);
}


1;
