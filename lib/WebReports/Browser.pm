package WebReports::Browser;

#
# adapted from GMOD Browser, use Gadfly AnnotatedSeq instead GFF->segment
# multiple conf file under conf dir->browse multiple genomes (sources)
#
# to access GENERAL section value, use $self->settting('the_setting_name')
# to access sub section value, use $self->config('sub_section_name'=>'setting_name')
#
# problem or watchout:
# our obj type is not corresponding to section label in config
# so hacking in $sf->{_feature_type} to section label to make valid link
# use it to indicate which glyph is ruler ($sf->{_feature_type} eq 'ruler')
#
# don't use arrow glyph for feature with sub features
# panel pad_left causes key panel glyph has pad_left as well
#

use strict;
use File::Basename 'basename';
use Carp;
use GD;
use Text::Shellwords;
use Bio::Graphics::Panel;
use GxAdapters::ConnectionManager qw(:all);
use GxAdapters::GxAnalysis;
use GxAdapters::GxAnnotatedSeq;
use DbUtils::SqlWrapper qw(:all);

use constant DEFAULT_WIDTH => 800;
use constant THUMBNAILLABELFONT => gdTinyFont;
use constant OVERVIEWLABELFONT => gdMediumBoldFont;
use constant DETAIL_GENE_LABEL => 'Zoomin_Gene';
use constant RULER_LABEL => 'Ruler_Feature';

use vars '$VERSION';
$VERSION = '1.00';

sub new {
  my $class    = shift;
  my $conf_dir = shift;
  my $self = bless { },$class;
  $self->{conf}  = $self->read_configuration($conf_dir);
  $self->{width} = $self->setting('default width') || DEFAULT_WIDTH;
  $self;
}

sub sources {
  my $self = shift;
  my $conf = $self->{conf} or return;
  return keys %$conf;
}

# get/set current source
sub source {
  my $self = shift;
  my $d = $self->{source};
  if (@_) {
    my $source = shift;
    unless ($self->{conf}{$source}) {
      carp("invalid source: $source");
      return $d;
    }
    $self->{source} = $source;
    $d = $self->{source};
  }
  $d;
}

sub setting {
  my $self = shift;
  $self->config->setting('general',@_);
}

sub description {
  my $self = shift;
  my $source = shift;
  my $c = $self->{conf}{$source} || $self->config || return;
  my $n = $c->setting('general','description');
  $n =~ s/\#\w+//;
  my @w = shellwords($n);
  return "@w";
}

sub source_description {
  my $self = shift;
  my $source = shift;
  my $c = $self->{conf}{$source} || $self->config || return;
  my $n = ($c->setting('general','source description')
          || $c->setting('general','description'));
#  my $n = $self->config->setting('general'=>'source description');
  $n =~ s/\#\w+//;
  my @w = shellwords($n);
  return "@w";
}

sub config {
  my $self = shift;
  my $source = $self->source;
  $self->{conf}{$source};
}

sub default_labels {
  my $self = shift;
  $self->config->default_labels;
}
sub overview_landmarks {
  my $self = shift;
  $self->config->overview_landmarks;
}
sub hide_analysis_types {
  my $self = shift;
  $self->config->hide_analysis_types;
}
sub merge_analysis_types {
  my $self = shift;
  $self->config->merge_analysis_types;
}

sub analysis2label {
    my $self = shift;
    my $an_name = shift;
    my ($ap, $adb) = split /\:/, $an_name;
    my $conf = $self->config;
    my $the_label;
    foreach my $label ($conf->labels) {
        next unless ($conf->setting($label=>'gadfly_type') eq 'analysis');
        my @analyses = split /\s+/, $conf->setting($label=>'feature');
        foreach my $a (@analyses) {
            my ($p, $db) = split /\:/, $a;
            if (lc($p) eq lc($ap)) {
                foreach my $re (@{$self->analysis_regexes($ap)}) {
                    eval {$the_label = $label if ($adb =~ /$re/i)};
                    last if ($the_label);
                }
            }
            last if ($the_label);
        }
        last if ($the_label);
    }
    return $the_label;
}

sub analysislabels {
    my $self = shift;
    return grep { $_ ne 'overview'} $self->config->configured_types;
}

# for tier that use wild card for analysis db (blastx:aa_SPTR.*)
sub analysis_regexes {
    my $self = shift;
    my $program = shift;

    if ($self->{analysis_regexes}) {
        return $self->{analysis_regexes}->{$program};
    }

    my $conf = $self->config;
    my @analyses;
    my %regexes;
    foreach my $label ($self->analysislabels) {#, 'Your BLAST hit') {
        push @analyses, split /\s+/, $conf->setting($label=>'feature');
    }
    foreach my $a (@analyses) {
        $a =~ s/\.\*//;
        $a =~ s/\.\%//;
        $a =~ s/\*//;
        $a =~ s/\%//;
        if ($a =~ /(\w+):(\S+)/) {
            push @{$regexes{$1}}, qr/$2/;
        }
    }
    $self->{_analysis_regexes} = \%regexes;
    return $self->{_analysis_regexes}->{$program};
}

sub feature2label {
  my $self = shift;
  my $feature = shift;
  my $conf = $self->config;
#  my $type  = $feature->type;
  my $type = $feature->{_feature_type} || $feature->type;
  my $label = $conf->type2label($type) || $conf->type2label($feature->primary_tag) || $type;
  $label;
}

sub feature2target {
  my $self = shift;
  my $feature = shift;
  my $conf = $self->config;
  my $type = $feature->{_feature_type} || $feature->type;
  return $conf->setting($type, 'target');
}

sub make_alt {
  my $self     = shift;
  my $sf  = shift;
  my $label = $self->feature2label($sf) or return;
  my $alt_text = $self->get_alt($label) or return;
  if (ref $alt_text eq 'CODE') {
      return $alt_text->($sf);
  }
  else {
      $alt_text =~ s/\$(\w+)/
        $1 eq 'name'   ? $sf->name
        : $1 eq 'info' ? $sf->info
        : $1 eq 'description' ? $sf->description
        : $1 eq 'homol_seq_description' ? $sf->homol_seq->description
        : $1 eq 'homol_seq_name' ? $sf->homol_seq->name
        : $1 eq 'start' ? $sf->coords_origin1->[0]
        : $1 eq 'end' ? $sf->coords_origin1->[1]
        : $1 eq 'symbol' ? $sf->symbol
        : $1 eq 'flybase_accession_no' ?
          ($sf->flybase_accession_no ? $sf->flybase_accession_no->acc_no : 'no_acc')
        : $1 eq 'homol_seq_flybase_accession_no' ?
          ($sf->homol_seq->flybase_accession_no ?
           $sf->homol_seq->flybase_accession_no->acc_no : 'no_acc')
        : $1
       /exg;
      return $alt_text;
  }
}

sub make_link {
  my $self     = shift;
  my $sf  = shift;
  my $label = $self->feature2label($sf) or return;
  my $link  = $self->get_link($label) or return;
  if (ref $link eq 'CODE') {
    return $link->($sf);
  }
  else {
      $link =~ s/\$(\w+)/
        $1 eq 'name'   ? $sf->name
        : $1 eq 'info' ? $sf->info
        : $1 eq 'homol_seq_name' ? $sf->homol_seq->name
        : $1 eq 'symbol' ? $sf->symbol
        : $1 eq 'flybase_accession_no' ?
          ($sf->flybase_accession_no ? $sf->flybase_accession_no->acc_no : 'no_acc')
        : $1 eq 'homol_seq_flybase_accession_no' ?
          ($sf->homol_seq->flybase_accession_no ?
           $sf->homol_seq->flybase_accession_no->acc_no : 'no_acc')
        : $1 eq 'source' ? $self->source
        : $1
       /exg;
      return $link;
  }
}

sub get_link {
  my $self = shift;
  my $label = shift;

  unless (exists $self->{_link}{$label}) {
    my $link = $self->{_link}{$label} = $self->config->label2link($label);
    if ($link =~ /^sub\s+\{/) { # a subroutine
      my $coderef = eval $link;
      warn $@ if $@;
      $self->{_link}{$label} = $coderef;
    }
  }

  return $self->{_link}{$label};
}

sub get_alt {
  my $self = shift;
  my $label = shift;

  unless (exists $self->{_alt}{$label}) {
    my $alt = $self->{_alt}{$label} = $self->config->label2alt($label);
    if ($alt =~ /^sub\s+\{/) { # a subroutine
      my $coderef = eval $alt;
      warn $@ if $@;
      $self->{_alt}{$label} = $coderef;
    }
  }

  return $self->{_alt}{$label};
}

sub labels {
  my $self = shift;
  $self->config->labels;
}

sub width {
  my $self = shift;
  my $d = $self->{width};
  $self->{width} = shift if @_;
  $d;
}

sub is_detail_gene_box {
  my $self = shift;
  my $box = shift;
  my $g_label = $self->setting('detail gene label') || DETAIL_GENE_LABEL;
  return ($box->[0]->{_feature_type} eq $g_label);
}

sub make_thumbnail_link {
  my $self = shift;
  my $sf = shift; #better be gene object
  my $link_label = shift;
  my $link = $self->setting($link_label);
  $link =~ s/\$(\w+)/
    $1 eq 'name'   ? $sf->name
    : $1 eq 'symbol' ? $sf->symbol
    : $1 eq 'flybase_accession_no' ?
      ($sf->flybase_accession_no ? $sf->flybase_accession_no->acc_no : 'no_acc')
    : $1 eq 'info' ? $sf->info
    : $1 eq 'source' ? $self->source
    : $1
    /exg;
  return $link;
}

sub make_detail_gene_link {
  my $self = shift;
  my $sf = shift;
  my $link  = $self->setting('detail gene link');

  $link =~ s/\$(\w+)/
    $1 eq 'name'   ? $sf->name
    : $1 eq 'symbol' ? $sf->symbol
    : $1 eq 'flybase_accession_no' ?
      ($sf->flybase_accession_no ? $sf->flybase_accession_no->acc_no : 'no_acc')
    : $1 eq 'info' ? $sf->info
    : $1 eq 'source' ? $self->source
    : $1
    /exg;
  return $link;
}

sub make_thumbnail_alt {
  my $self = shift;
  my $sf = shift || return;
  my $alt_label = shift;
  my $alt  = $self->setting($alt_label);

  $alt =~ s/\$(\w+)/
    $1 eq 'name'   ? $sf->name
    : $1 eq 'symbol' ? $sf->symbol
    : $1 eq 'flybase_accession_no' ?
      ($sf->flybase_accession_no ? $sf->flybase_accession_no->acc_no : 'no_acc')
    : $1 eq 'info' ? $sf->info
    : $1 eq 'start' ? $sf->start
    : $1 eq 'end' ? $sf->end
    : $1 eq 'stop' ? $sf->stop
    : $1
    /exg;
  return $alt;
}

sub seq_feature4thumbnail {
  my $self = shift;
  my $constr = shift || confess("constraint hash ref for getting a gene is required");# || {(name=>'CG11861')};
  my $dbh = shift;

  (ref($constr) eq 'HASH')
    ||  confess("constraint hash ref for getting a gene is required");

  my $extend = $self->setting('thumbnail extend by') || 50000;

  if (!$dbh) {
      $dbh = get_handle($self->setting('database'));
  }
  my $gene = $constr->{gene_obj};
  if (!$gene) {
      $gene = GxAdapters::GxGene->select_obj
          ($dbh, $constr, ["*", "transcript"]);
  }

  $gene || confess("No gene for the constraint $constr");

  my ($start, $end) = ($gene->range_low, $gene->range_high);
  my $middle = $start + int(($end - $start) / 2);
  $start = $middle - $extend;
  $end = $middle + $extend;
  ($start, $end) = ($gene->range_low - 2000, $gene->range_high + 3000)
    if ($gene->length > (abs($end-$start)));
  $start = 0 if ($start < 0);
  #make it plus strand (seg has to be plus strand)
  ($start, $end) = ($end, $start) if ($start > $end);

  my $seg = BioModel::Segment->new
    (-name=>"segment [".$start.",".$end."] on ".$gene->src_seq->name,
     -start=>$start,
     -end=>$end,
    );
  $seg->src_seq($gene->src_seq);
  $seg->info($seg->name);

  my $segments_h = {};

  my $arm_seqid = $gene->src_seq->id;

  my $cyto_h = select_hashlist
    ($dbh,
     ['seq_feature sf'],
     ['sf.type = '.sql_quote("cyto band"),
      'sf.src_seq_id = '.$arm_seqid,
      "((sf.start >= $start and ".
      "  sf.start <= $end) or ".
      " (sf.end >= $start and ".
      "  sf.end <= $end)  or ".
      " ($start >= sf.start and ".
      "  $start <= sf.end) or ".
      " ($start >= sf.end and ".
      "  $start <= sf.start)".
      ")",
     ],
     ['sf.name', 'sf.start', 'sf.end'] #need global start
    );
  foreach my $cyto (@{$cyto_h}) {
      my $segment = BioModel::Segment->new;
      my $name = $cyto->{name};
      $name =~ s/^band\-//i;
      next unless ($name =~ /^\d+\D.+/);
      $segment->name($name);
      $segment->info($segment->name);
      $segment->start($cyto->{start});
      $segment->end($cyto->{end});
      push @{$segments_h->{'Cyto Band'}}, $segment;
  }

  my $gene_l = GxAdapters::GxGene->select_objlist
    ($dbh, {intersects=>$seg}, ["*", "equiv"]);

  map{$_->info($_->symbol); push @{$segments_h->{'Gene'}}, $_}@$gene_l;
#  map{my $g = BioModel::Segment->new;
#      $g->name($_->name);
#      $g->start($_->start);
#      $g->end($_->end);
#      $g->info($_->symbol);
#      push @{$segments_h->{'Gene'}}, $g
#  }@$gene_l;

#  close_handle($dbh);

  #hard coded hash key
  return ($gene, $seg, $segments_h);
}


=head2 thumbnail_image_boxes

  -Usage   $conf->thumbnail_image_boxes($constraint)
  -Return  Gene, GD, Image_Map
  -Args
       $constraint--hash ref for construct a Gene obj (e.g. {name=>'CG1234'})

=cut


sub thumbnail_image_boxes {
  my $self = shift;
  my ($gene, $ruler_f, $feature_h) = $self->seq_feature4thumbnail(@_);

  #fixed: only cyto and gene in thumnail
  my @conf_labels;
  push @conf_labels, 'Cyto Band';
  push @conf_labels, 'Gene';

  my $conf  = $self->config;
  my $width = $self->setting('thumbnail width') || 200;
  my $d_gene_height = $self->setting('thumbnail detail gene height') || 10;
  my $gene_height = $self->setting('thumbnail gene height') || 6;
  my $zoomin_part_label = $self->setting('detail gene label') || DETAIL_GENE_LABEL;
  my $h_color = $conf->setting($conf_labels[1]=>'highlight_color') || 'red';
  my $f_color = $conf->setting($conf_labels[1]=>'fgcolor') || 'blue';
  my $bg = $conf->setting($conf_labels[1]=>'bgcolor') || 'blue';
  my $panel_bgcolor = $self->setting('thumbnail bgcolor') || 'wheat';

  # Create the tracks that we will need (pass in segment to scale with length)
  my $panel = Bio::Graphics::Panel->new
    (-segment => $ruler_f,
     -width   => $width,
     -bgcolor => $panel_bgcolor,
     -key_style => 'none',
     -pad_left => 10,
     -pad_right =>10,
     -grid => 0,
    );

  my %tracks;
  my $strand = 1;

  #setup tracks
  #cyto band track
  my $track = $panel->add_track
    (-glyph => 'anchored_arrow');
  $tracks{$conf_labels[0]}{$strand} = $track;
  #gene track
  my $track1 = $panel->add_track(-glyph => 'generic',
                                 $conf->style($conf_labels[1]),
                                );
  $tracks{$conf_labels[1]}{$strand} = $track1;

  #ruler
  $ruler_f->{_feature_type} = RULER_LABEL;
  $panel->add_track($ruler_f => 'arrow',
                    -double => 1,
                    -tick=>1,
                    -no_tick_label => 1,
                   );
  $strand = -1;
  #posssible minus strand gene track
  unless ($self->setting('mix strand')) {
      my $track = $panel->add_track
        (-glyph => 'generic',
         $conf->style($conf_labels[1]),
        );
      $tracks{$conf_labels[1]}{$strand} = $track;
  }

  #invisible for a spacer b/w expanded and feature_h
  my $invisible = BioModel::Segment->new
    (-name => '',
     -start => 1,
     -end => 2,
     );
  $invisible->{_feature_type} = "panel_spacer";

  $panel->add_track('segments'=>$invisible,
                    -label=>0,
                    -height=>3,
                    -fgcolor=>'white',
                    -bgcolor=>'white',
                   );

  #invisible track for drawing expanded gene transcript feature
  my $atrack = $panel->add_track
    (-glyph => 'segments',
     -label   => 0,
    );
  if ($self->setting('mix strand')) {
      $tracks{$zoomin_part_label}{1} = $atrack;
  } else {
      $tracks{$zoomin_part_label}{-1} = $atrack;
  }

  my %features;
  foreach my $f_label (keys %{$feature_h}) {
      foreach my $sf (@{$feature_h->{$f_label}}) {
          $sf->highlighting(1) if ($sf->name eq $gene->name);
          $sf->{_feature_type} = $f_label unless ($sf->{_feature_type});
          push @{$features{$f_label}{int($sf->strand)}}, $sf;
      }
  }

  #invisible feature for drawing expanded gene transcript
  my $invisible_f = BioModel::Segment->new
    (-name => '',
     -start => $ruler_f->start,
     -end => $ruler_f->end,
     );
  $invisible_f->{_feature_type} = $zoomin_part_label;
  push @{$features{$zoomin_part_label}{-1}}, $invisible_f;

  foreach my $f_type (keys %features) {
      foreach my $strand (1, -1) {
          my $feature = $features{$f_type}{$strand};
          next unless $feature;
          my $label = $f_type;
          my $track;
          my $strnd = $self->setting('mix strand') ? 1 : $strand;
          $track = $tracks{$label}{$strnd} or next;
          $track->add_feature(@{$feature});
      }
  }

  #configure the tracks based on their counts
  for my $label (keys %tracks) {
      for my $strand (keys %{$tracks{$label}}) {
          my $strnd = $self->setting('mix strand') ? 1 : $strand;
          my $track = $tracks{$label}{$strnd};
          if ($label =~ /cyto/i) {
              $track->configure
                (-bump => 0,
                 -label => 1,
                 -height => 5,
                 -labelfont => OVERVIEWLABELFONT,
                 -label_align => 'center',
                 -fgcolor => 'black',
                 -bgcolor => 'black',
                );
          }
          elsif ($label eq $zoomin_part_label) {
              #invisible track
              $track->configure
                (-bump => 0,
                 -label => 0,
                 -fgcolor => $panel_bgcolor,
                 -bgcolor => $panel_bgcolor,
                 -height => $d_gene_height,
                );
          }
          else {
              my $bg_color = 'blue';
              $track->configure
                (-glyph => 'segments',
                 -bump  => 1,
                 -label => 0,
                 -height => $gene_height,
                 -bgcolor => sub {
                     my $sf = shift;
                     my $hlight = $sf->{_highlighting};
                     return ($hlight ? ($hlight eq 1 ? $h_color : $hlight) : $bg_color);
                 },
#                 -fgcolor => sub {
#                     my $sf = shift;
#                     my $hlight = $sf->{_highlighting};
#                     return ($hlight ? ($hlight eq 1 ? $h_color : $hlight) : $f_color);
#                 },
            );
          }
      }
  }

  my $gd       = $panel->gd;
  my $boxes    = $panel->boxes;

  #draw expanded gene transcript
  my $d;
  my @coords;
  my $hl_box;
  my ($i, $spacer_index, $spacer) = (0, -1);
  foreach my $box (@$boxes) {
      if ($box->[0]->{_feature_type} eq $zoomin_part_label) {
          (undef, @coords) = @$box;
#          splice (@$box, 0, 1, $gene);
          $d = $box;
          $gene->{_feature_type} = $zoomin_part_label;
          $d->[0] = $gene;
          $box->[0] = $gene;
      }
      elsif ($box->[0]->{_highlighting}) {
          $hl_box = $box;
      }
      elsif ($box->[0]->{_feature_type} eq 'panel_spacer') {
          $spacer_index = $i;
          $spacer = $box;
      }
      $i++;
  }

  splice(@$boxes, $spacer_index, 1) if ($spacer_index > -1); #remove space feature box

  my $t_bgcolor = $self->setting('detail gene bgcolor') || "gray";
  #$fgcolor = gene fgcolor
  my ($fgcolor, $tr_bgcolor, $hl_color) =
    ($panel->translate_color($f_color),
     $panel->translate_color($t_bgcolor),
     $panel->translate_color($h_color));
  my $blue = $panel->translate_color($self->setting('thumbnail box color') || 'blue');
  my $y = $spacer->[2] + int(($spacer->[4] - $spacer->[2]) / 2);
  #expand deteail gene box a bit so all below separator line will be for detail gene
  # use detail gene box to anchor separator, for some reason, spacer track is not passed out
  # when used by Query.pm!
  $y = $coords[1] - 5;

  # make below separator line all detail gene area (for image map)
  $d->[1] = 0;
  $d->[2] = $y;
  $d->[3] = $panel->width;
  $d->[4] = $panel->height;

  $self->_draw_transcript($gd,\@coords,$gene,$hl_color, $tr_bgcolor);
  #draw bracket
  my $y2 = $hl_box->[4];
  $y2 = $hl_box->[2] if (($gene->strand < 0)); #minus strand
  $gd->line($coords[0]+2, $y,$hl_box->[1],$y2,$tr_bgcolor);
  $gd->line($coords[2]-2, $y,$hl_box->[3],$y2,$tr_bgcolor);
  #draw a line to separate genes/transcript (detail gene)
  $gd->line(1, $y, $panel->width-1,$y, $fgcolor);
  #draw outline box for whole image
  $gd->rectangle(1,0,$panel->width-1, $panel->height-1, $blue);
  return ($gene, $gd,$boxes);
}
sub _draw_expanded_gene {
    my $self = shift;
    $self->_draw_transcript(@_);
}

sub _draw_transcript {
  my $self = shift;
  my $gd = shift;
  my $box = shift;
  my $gene = shift;
  my $fg_color = shift;
  my $bg_color = shift;

  my ($x1, $y1, $x2, $y2) = @$box;
  my $width = $x2 - $x1;
  my $offset = $gene->start;
  my $length = $gene->length;
  my $scale;
  my ($dx, $dy) = ($x1, 0);
  my (@boxes,@skips);


  #draw arrow if gene glyph has arrow?
  my $tr;
  #pick longest tr
  foreach (@{$gene->transcript_list || []}) {
      $tr = $_ unless ($tr);
#      $tr = $_ if ($_->length > $tr->length);
      #exclude UTR
      $tr = $_ if (abs($_->last_exon->end - $_->first_exon->start)
                   > abs($tr->last_exon->end - $tr->first_exon->start));
  }
  return unless ($tr);
  my @segments = @{$tr->exon_list || []};
  @segments = sort {$a->start<=>$b->start} @segments;
  $scale = $width / abs($tr->last_exon->end - $tr->first_exon->start);
  $offset = ($segments[0]->start < $segments[0]->end) ?
    $segments[0]->start : $segments[0]->end;
  for (my $i=0; $i < @segments; $i++) {
      my ($start,$stop) = ($dx + ($segments[$i]->start - $offset) * $scale,
                           $dx + ($segments[$i]->stop - $offset) * $scale);
      ($start,$stop) = ($stop,$start) if $start > $stop;
      push @boxes, [$start, $stop];
       if (my $next_segment = $segments[$i+1]) {
          my ($next_start,$next_stop) = 
            ($dx + ($next_segment->start - $offset) * $scale,
             $dx + ($next_segment->end - $offset) * $scale);

          ($next_start,$next_stop) = 
            ($next_stop,$next_start) if $next_start > $next_stop;

          #fudge?
          if ($next_start - $stop < 2) {
              $boxes[-1][1] = $next_start;
          }

          my ($x1, $x2);
          if ($next_start >= $stop) {
              ($x1, $x2) = ($stop, $next_start);
          } else {#-strand and not sorted
              ($x1, $x2) = ($next_stop, $start);
          }
          next unless ($x2 - $x1 > 1);#too close to draw line b/w two boxes
          push @skips,[$x1+1,$x2-1];
      }
  }

  #draw boxes
  foreach my $e (@boxes) {
      my $poly = GD::Polygon->new;
      my ($x1, $y1, $x2, $y2) = ($e->[0], $y1, $e->[1], $y2);
      $poly->addPt($x1, $y1);
      $poly->addPt($x2, $y1);
      $poly->addPt($x2, $y2);
      $poly->addPt($x1, $y2);
      $gd->filledPolygon($poly, $bg_color);
      $gd->polygon($poly, $fg_color);
  }
  #draw connector (what about hat connector for gene?)
  my $center = $y1 + ($y2 - $y1) / 2;
  for my $i (@skips) {
      $gd->line($i->[0],$center,$i->[1],$center,$fg_color);
  }
}


=head2 feature_image_boxes

  -Usage   $conf->feature_image_boxes($ruler_f, $feature_h, [$option])
  -Return  (GD, Image_Map)
  -Args
       $ruler_f--main segment feature to draw ruler in a panel
       $feature_h--hash ref of features, keyed by feature label (item in []
                   in config file), each hash value is arr ref of features of
                   same kind
       $option--$option->{expand|collapse}=expand all tiers or collapse all tiers
                $option->{labelling}=label gene titer

  -notes    tier order specified in config file is the order away from
            center ruler

=cut

sub feature_image_boxes {
  my $self = shift;
  my ($ruler_f, $feature_h, $option) = @_;

  $option = {} unless ($option);

  my $labels = [keys %{$feature_h}];

  my %labels = map {$_=>1} @$labels;

  my $width = $self->width;
  my $conf  = $self->config;
  my $max_labels = $conf->setting(general=>'label density') || 10;
  my $max_bump   = $conf->setting(general=>'bump density')  || 50;

#  $seg->end($seg->length);
#  $seg->start(0);
  # Create the tracks that we will need (pass in segment to scale with length)
  $ruler_f->{_feature_type} = 'ruler';
  my $panel = Bio::Graphics::Panel->new
    (-segment => $ruler_f,
     -width   => $width,
     -key_color => $self->setting('key_color') || 'moccasin',
     -pad_left => $self->setting('pad_left') || 10,
     -pad_right => $self->setting('pad_right') || 10,
     -grid => 1,
    );

  my %tracks;
  # use labels() method in order to preserve order in .conf file
  #first item close to strand (arrow glyph) and no key for minus strand feature
  my $strand = 1;
  my @conf_labels = ($conf->tierlabels);
  for (my $i = @conf_labels - 1 ; $i >= 0; $i--) {
      my $label = $conf_labels[$i];
      next unless $labels{$label};#use arg_in $lable to control if to display it
      my $track = $panel->add_track(-glyph => 'generic',
                                    -key   => $label,
                                    $conf->style($label),
                                   );
      $track->configure
        (-key => '',
        );
      $tracks{$label}{$strand} = $track;
  }

  my $rglyph = $self->setting('ruler glyph') || 'ruler_arrow';
  $panel->add_track($ruler_f   => $rglyph,
                    -double => 1,
                    -tick=>1,
                    -label=>1,
                    -ruler=>1,
                    -both=>1,
                    -linewidth=>$self->setting('ruler linewidth') || 2,
                    -no_tick_label => 1,
                   );
  $strand = -1;
  unless ($self->setting('mix strand')) {
      for my $label (@conf_labels) {
          #use arg_in $lable to control if to display it
          next unless $labels{$label};
          my $track = $panel->add_track(-glyph => 'generic',
                                        $conf->style($label),
                                       );
          $tracks{$label}{$strand} = $track;
      }
  }

  my %features;
  my %hl_features;
  foreach my $f_label (keys %{$feature_h}) {
      foreach my $sf (@{$feature_h->{$f_label}}) {
          $sf->{_feature_type} = $f_label unless ($sf->{_feature_type});
          if ($sf->{_highlighting} eq 1) {
              push @{$hl_features{$f_label}{int($sf->strand)}}, $sf;
          } else {
              push @{$features{$f_label}{int($sf->strand)}}, $sf;
          }
      }
  }

  my %feature_count;
  foreach my $f_type (keys %features) {
      foreach my $strand (1, -1) {
          my $feature = $features{$f_type}{$strand};
          next unless $feature;
          my $label = $f_type;
          my $track;
          my $strnd = $self->setting('mix strand') ? 1 : $strand;
          $track = $tracks{$label}{$strnd} or next;
          $feature_count{$label} += scalar(@{$feature});
          $track->add_feature(@{$feature});
      }
  }
  # add highlighted feature last
  foreach my $f_type (keys %hl_features) {
      foreach my $strand (1, -1) {
          my $feature = $hl_features{$f_type}{$strand};
          next unless $feature;
          my $label = $f_type;
          my $track;
          my $strnd = $self->setting('mix strand') ? 1 : $strand;
          $track = $tracks{$label}{$strnd} or next;
          $feature_count{$label} += scalar(@{$feature});
          $track->add_feature(@{$feature});
      }
  }

  # last but not least, configure the tracks based on their counts
  for my $label (keys %tracks) {
      for my $strand (keys %{$tracks{$label}}) {
#          next unless $feature_count{$label};
          my $do_label = ($conf->setting($label=>'label') || 0)
            && $feature_count{$label} <= $max_labels;
          my $do_bump  = ($conf->setting($label=>'bump') || 0)
            && $feature_count{$label} <= $max_bump;
          #collapse tier->every thing one line per track!
          $do_bump = 0 if ($self->setting('collapse tier') ||
                           $option->{collapse});
          $do_label = 0 if ($self->setting('collapse tier') ||
                            $option->{collapse});
          $do_bump = 1 if ($option->{expand});
          #only allow labelling gene feature!
          if ($option->{labelling} && $label =~ /gene/i) {
              $do_label = 1;
              $do_bump = 1;
          }

          my $h_color = $conf->setting($label=>'highlight_color') || 'red';
          my $bg = $conf->setting($label=>'bgcolor');#fillcolor
          my $fg_color = $conf->setting($label=>'fgcolor');
          my $strnd = $self->setting('mix strand') ? 1 : $strand;
          $tracks{$label}{$strnd}->configure
            (-bump  => $do_bump,
             -label => $do_label,
             -bgcolor => sub {
                 my $sf = shift;
                 my $hlight = $sf->{_highlighting};
                 return ($hlight ? ($hlight eq 1 ? $h_color : $hlight) : $bg);
             },
             -fgcolor => sub {
                 my $sf = shift;
                 my $hlight = $sf->{_highlighting};
                 my $fg = $sf->{_fgcolor} || $fg_color;
#                 return ($fg ? $fg : $fg_color);
                 return ($hlight ? ($hlight eq 1 ? $h_color : $hlight) : $fg);
             },
            );
      }
  }

  my $boxes    = $panel->boxes;
  my $gd       = $panel->gd;
  return ($gd,$boxes);
}

# Generate the image and the box list, and return as a two-element list.
sub annot_seq_image_boxes {
  my $self = shift;
  my ($annot_seq, $labels, $option) = @_;

  $option = {} unless ($option);

#  my $annot_seq = $self->get_annotated_seq($seqn);#quicky for temp testing 

  $annot_seq->isa("BioModel::AnnotatedSeq") ||
    confess("must pass in a BioModel::AnnotatedSeq");

#  $labels = [($self->labels)] if (!defined($labels));
  $labels || confess("must pass in labels");

  my %labels = map {$_=>1} @$labels;

  my $conf  = $self->config;

  #transform now change annot_seq->segment
  my $seg = $annot_seq->segment->duplicate;

  my $segments = $annot_seq->segment->overlapping_segment_list || [];
  #make global coord based
  $annot_seq->transform_up($annot_seq->segment);

  $annot_seq->segment->name($seg->name);

  #annotSeq->annotation_list->gene->transcript_list
  #annotSeq->analysis_list->result_set_list
  my %features; #one tier for one feature or a group of features
  foreach my $feature (keys %labels) {
      my $type = $conf->setting($feature=>'gadfly_type');
      if ($type eq 'segment') {
          foreach my $seg (@{$segments}) {
              $seg->{_feature_type} = $feature;
              push @{$features{$feature}}, $seg;
          }
      } elsif ($type eq 'gene') {
          map {
              #in case want arrow glyph for gene
              my $seg = BioModel::Segment->new
                (-name => $_->gene->symbol,
                 -start => $_->gene->start,
                 -end => $_->gene->end,
                );
              $seg->info($_->gene->symbol);
              $seg->{_feature_type} = $feature;
              $seg->highlighting($_->gene->highlighting);
              push @{$features{$feature}}, $seg;
          } @{$annot_seq->annotation_list || []};
      }
      elsif ($type eq 'transcript') {
          foreach my $ann (@{$annot_seq->annotation_list || []}) {
              my @trs = @{$ann->gene->transcript_list || []};
              map {
                  $_->info($ann->gene->symbol);
                  $_->{alt_text} = $ann->gene->label;
                  $_->{_feature_type} = $feature;
              } @trs;
              push @{$features{$feature}}, @trs;
          }
      }
      elsif ($type eq 'analysis') {
          my @analyses = split /\s+/, $conf->setting($feature=>'feature');
          my %analysis_h;
          map {$_ =~ s/\.\*//; $_ =~ s/\.\%//;
               $_ =~ s/\*//; $_ =~ s/\%//;
               if ($_ =~ /(\w+):(\S+)/) {
                   my $db = $2;
                   push @{$analysis_h{$1}}, $2;
               }
           } @analyses;
          foreach my $analysis (@{$annot_seq->analysis_list || []}) {
              my $a_name = $analysis->name;
              my ($p, $db)= ($analysis->program, $analysis->database);
              $db = 'any' unless ($db);
              if (exists $analysis_h{$p}) { #check program
                #compile variable pattern as regex, run faster
                my @regexes = map{qr/$_/}@{$analysis_h{$p}};
                my $found_it = 0;
                foreach my $re (@regexes) { #check databases for the program
#                foreach my $re (@{$self->analysis_regexes($p) || []}) {
                    eval {
                    if ($db =~ /$re/i) {
                        $found_it = 1;
                        last;
                    }
                    };
                }
                if (!$found_it) {
                    print STDERR "CAN'T FIND $a_name ($p $db) - skip\n";
                }
                if ($found_it) {
#                    printf STDERR "What is analysis name: %s %s:%s %s\n",$a_name, $p, $db, $feature;
                  my @rsets = @{$analysis->result_set_list || []};
                  foreach my $rset (@rsets) {
                      if ($rset->has_mixed_seqs) {
                          my $str = join(";", map {$_->name} @{$rset->homol_seq_list});
                          $str = substr($str, 0, 30);
                          $rset->info($str);
                      }
                      else {
                          if ($rset->homol_seq) {
                              $rset->info($rset->homol_seq->name);
                          }
                          else {
                              my $desc = "";
                              if ($rset->description) {
                                  $desc = $rset->description;
                              }
                              else {
                                  $desc = $rset->name;
                              }
                              my $sps = $rset->result_span_list || [];
                              if (@$sps) {
                                  # for sets with single spans show the type
                                  my @types = map {$_->type} @$sps;
                                  if (grep {$types[0] eq $_ } @types) {
                                      # dont show unless consistent
                                      my $type = $types[0];
                                      $desc .= " " . $type unless grep {/$type/i} 
                                          qw(exon hsp alignment);
                                  }
                              }
                              $rset->info($desc);
                          }
                      }
                      my $score = "";
                      if ($analysis->program =~ /blast/) {
                          $score = $rset->get_score("expect");
                      }
                      else {
                          $score = $rset->get_score || "";
                      }
                      $rset->info($rset->info || "");
                      $rset->{alt_text} =
                        $rset->info." [".join(",",
                                              @{$rset->coords_origin1})."] ".$score;
                      #arrow glyph does not like sub features 
                      #do below only for arrow glyph feature or have unnec. tall arrow
                      if (@{$rset->result_span_list} == 1
                          && $conf->setting($feature=>'glyph') =~ /arrow/) {
                          my $tmp = $rset;
                          $rset = BioModel::Segment->new
                            (-name => $tmp->info,
                             -start => $tmp->start,
                             -end   => $tmp->end,
                            );
                          $rset->info($tmp->info);
                          $rset->highlighting($tmp->highlighting);
                      }
                      $rset->{_feature_type} = $feature;
                      if ($conf->setting($feature=>'secondary') =~ /$a_name/) {
                          my $secondary_bgcolor
                            = $conf->setting($feature=>'secondary_bgcolor');
                          $secondary_bgcolor = 0 if ($rset->highlighting);
                          $rset->highlighting($secondary_bgcolor)
                            if ($secondary_bgcolor);
                          my $secondary_fgcolor
                            = $conf->setting($feature=>'secondary_fgcolor');
                          if ($secondary_fgcolor) {
#                              if ($rset->highlighting == 1) {
#                                  my $h_color = $conf->setting($feature=>'highlight_color') || 'red';
#                                  $secondary_fgcolor = $h_color;
#                              }
                              $rset->{_fgcolor} = $secondary_fgcolor;
                              foreach (@{$rset->result_span_list || []}) {
                                  $_->{_fgcolor} = $secondary_fgcolor;
                              }
                          }
                      }
                      push @{$features{$feature}}, $rset; #as group?
                  } #end for each rset
                } #end if (found_it)
                else {
                    #printf STDERR "LABEL: no such analysis %s program %s db %s\n", $a_name, $p, $db;
                }
              } #end if exists
          } #end for each analysis
      } #end elsif feature type = analysis
  } #end for each feature (label)

#  my $gb_label;
#  map {
#      if ($conf->setting($_=>'gadfly_type') eq 'segment') {
#          $gb_label = $_;
#      }
#  } keys %labels;

##$self->setting('gb unit label') || 'GenBank unit';

#  if ($gb_label) {
#      foreach my $seg (@{$segments}) {
#          $seg->{_feature_type} = $gb_label;
#          push @{$features{$gb_label}}, $seg;
#      }
#  }
  return $self->feature_image_boxes($seg, \%features, $option);
}

# generate the overview and return it as a GD and length of part in focus
sub overview {
  my $self = shift;
  my ($arm_sf, $seg_h, $partial_segment) = @_;

#  my $sf = $self->get_arm_sf($arm); #for temp testing

  #partial_segment (=red box)

#  @{$sf->sub_seq_feature_list || []} ||
#    confess("must pass in seq feauture with sub seq features");

  my $landmark_lbl =
    sprintf " (bp, %s)", join(", ", keys %{$seg_h});
  #don't like seqFeature with sub_feature for arrow track!
  my $seg = BioModel::Segment->new
    (-name=>$arm_sf->name,
     -start=>$arm_sf->start,
     -end=>$arm_sf->end,
    );
  my $conf  = $self->config;
  my $width = $self->width;
  my $panel = Bio::Graphics::Panel->new
    (-segment => $seg,
     -width   => $width,
     -bgcolor => $self->setting('overview bgcolor') || 'wheat',
     -pad_right => $self->setting('overview pad_right') || 0,
    );
  $panel->add_track
    ($seg   => 'arrow',
     -double    => 1,
     -label     => "Overview of ".$arm_sf->name.$landmark_lbl,
     -labelfont => OVERVIEWLABELFONT,
     -units     => $self->setting('overview units'),
     -tick      => 2,
    );

  my %tracks;
  my $max_label   = $conf->setting(general=>'overview label density') || 50;
  my $landmarks = [$self->overview_landmarks] || [keys %{$seg_h}];
  #use overview landmarks to show track in the order they are specd in config
  foreach my $sf (@{$landmarks}) {
      next unless (exists $seg_h->{$sf});
      next unless (@{$seg_h->{$sf}});
      my $track = $panel->add_track(-glyph  => 'generic',
                                    -height  => 3,
                                    -fgcolor => 'black',
                                    -bgcolor => 'black',
                                    $conf->style('overview'),
                                   );
      $tracks{$sf} = $track;
      my $count = 0;
      foreach my $subsf (@{$seg_h->{$sf}}) {
          $track->add_feature($subsf);
          $count++;
      }
      my $bumping = 1;
      $bumping = 0 if ($sf =~ /cyto/i);
      my $labelling = $count <= $max_label;
      my $label_align;
      $label_align = 'center' if ($sf =~ /cyto/i);
      $track->configure(-bump  => $bumping,
                        -label => $labelling,
                        -label_align => $label_align,
                       );
  }

  my $gd = $panel->gd;
  my $red = $gd->colorClosest(255,0,0);
  my ($x1,$x2) = $panel->map_pt($partial_segment->start,$partial_segment->end);
  my ($y1,$y2) = (0,$panel->height-1);
  $x1 = $x2 if $x2-$x1 <= 1;
  $x2 = $panel->right-1 if $x2 >= $panel->right;
  $gd->rectangle($x1,$y1,$x2,$y2,$red);

  return ($gd,$seg->length);
}


#parsing config files, setting first as default source
sub read_configuration {
  my $self = shift;
  my $conf_dir = shift; #so we can have >1 release browsing with one browser script!
  die "$conf_dir: not a directory" unless -d $conf_dir;

  opendir(D,$conf_dir) or die "Couldn't open $conf_dir: $!";
  my @conf_files = map { "$conf_dir/$_" }readdir(D);
  close D;

  # try to work around a bug in Apache/mod_perl which appears when
  # running under linux/glibc 2.2.1
  unless (@conf_files) {
    @conf_files = glob("$conf_dir/*.conf");
  }
  my %config;
  foreach (sort {$b cmp $a} @conf_files) {
    next unless /\.conf$/;
    my $basename = basename($_,'.conf');
    my $config = WebReports::BrowserConfig->new(-file => $_) or next;
    $config{$basename} = $config;
    $self->{source} = $basename;
  }
  return \%config;
}



package WebReports::BrowserConfig;
use strict;
use Bio::Graphics::FeatureFile;
use Carp;
use Text::Shellwords;
#require 'shellwords.pl';

use vars '@ISA';
@ISA = 'Bio::Graphics::FeatureFile';

sub labels {
  my $self = shift;
  grep { $_ ne 'overview' && $_ ne 'Your BLAST hit'} $self->configured_types;
#  $self->configured_types;
}
sub tierlabels {
  my $self = shift;
  grep { $_ ne 'overview'} $self->configured_types;
}
sub label2type {
  my $self = shift;
  my $label = shift;
  return shellwords($self->setting($label,'feature'));
}

sub label2link {
  my $self = shift;
  my $label = shift;
#  $self->setting($label,'link') || $self->setting('general','link');
  $self->setting($label,'link') || "#";
}

sub label2alt {
  my $self = shift;
  my $label = shift;
  $self->setting($label,'alt') || $self->setting('general','alt');
}

sub type2label {
  my $self = shift;
  my $type = shift;
  $self->{_type2label} ||= $self->invert_types;
  $self->{_type2label}{$type};
}

sub invert_types {
  my $self = shift;
  my $config  = $self->{config} or return;
  my %inverted;
  for my $label (keys %{$config}) {
    next if $label eq 'overview';   # special case
    my $feature = $config->{$label}{feature} or next;
    foreach (shellwords($feature)) {
      $inverted{$_} = $label;
    }
  }
  \%inverted;
}

sub default_labels {
  my $self = shift;
  my $defaults = $self->setting('general'=>'default features');
  $defaults =~ s/ \#\w+//;
  return shellwords($defaults);
}

sub overview_landmarks {
  my $self = shift;
  my $landmarks = $self->setting('general'=>'overview landmarks');
  $landmarks =~ s/ \#\w+//;
  return shellwords($landmarks);
}

sub merge_analysis_types {
  my $self = shift;
  my $n = $self->setting('general'=>'merge analysis types');
  $n =~ s/ \#\w+//;
  return shellwords($n);
}

sub hide_analysis_types {
  my $self = shift;
  my $n = $self->setting('general'=>'hide analysis types');
  $n =~ s/ \#\w+//;
  return shellwords($n);
}

# return a hashref in which keys are the thresholds, and values are the list of
# labels that should be displayed
sub summary_mode {
  my $self = shift;
  my $summary = $self->setting(general=>'summary mode') or return {};
  my %pairs = $summary =~ /(\d+)\s+{([^\}]+?)}/g;
  foreach (keys %pairs) {
    my @l = shellwords($pairs{$_});
    $pairs{$_} = \@l
  }
  \%pairs;
}

sub autoparams { qw(bgcolor barcolor) }

use vars qw($AUTOLOAD);
sub AUTOLOAD {
    
    my $self = shift;
 
    my $name = $AUTOLOAD;
    $name =~ s/.*://;   # strip fully-qualified portion

    if ($name eq "DESTROY") {
	# we dont want to propagate this!!
	return;
    }

    confess unless ref($self);

    if ($self->can($name)) {
	confess("assertion error!");
    }
    if (grep {$_ eq $name} $self->autoparams()) {
        my $v = $self->setting('general'=>$name);
        $v =~ s/ \#\w+//;
        return shellwords($v);
    }
    else {
	confess("can't do $name on $self");
    }
    
}


1;

__END__

#below was used to test development
#sub get_arm_sf {
#    my $self = shift;
#    my $armn = shift;

#    my $dbh = get_handle($self->setting('database'));
#    my $armh = select_hash($dbh, ['seq'], 
#                           ['name = '.sql_quote($armn)], 
#                           ['id', 'length']);

#    confess("The arm has no sequence at all as length is 0")
#      if ($armh->{'length'} == 0);

#    my $arm = BioModel::SeqFeature->new;
#    $arm->start(0);
#    $arm->end($armh->{'length'});
#    $arm->name($armn);

#    my $arm_seqid = $armh->{id} || 0;
#    my $seg_h = select_hashlist($dbh,
#                                   ['seq_feature sf'],
#                                   ['src_seq_id = '.$arm_seqid,
#                                    'type = '.sql_quote('segment')],
#                                   ['sf.name', 'start', 'end']);
#    foreach my $seg (@{$seg_h}) {
#        my $sf = BioModel::SeqFeature->new;
#        $sf->name($seg->{name});
#        $sf->info($sf->name);
#        $sf->start($seg->{start});
#        $sf->end($seg->{end});
#        $arm->add_sub_seq_feature($sf);
#    }
#    return $arm;
#}

#sub get_annotated_seq {
#  my $self = shift;
#  my $seqn = shift;

#  my $config = $self->config;
#  my $dbh = get_handle($self->setting('database'));
#  my @selected_analyses;

#  for my $feature ($self->labels) {
#      if ($config->setting($feature=>'gadfly_type') eq 'analysis') {
#          push @selected_analyses, (split /\s+/, $config->setting($feature=>'feature'));
#      }
#  }

#  my $an_l =
#    GxAdapters::GxAnalysis->select_objlist($dbh,
#                                           {analysis_list=>\@selected_analyses});
#  my @an_ids = map {$_->id} @$an_l;

#  my $annseq = 
#    GxAdapters::GxAnnotatedSeq->select_obj($dbh,
#                                           {name=>$seqn,
#                                            analysis_ids=>\@an_ids},
#                                           ["visual"]);
#  $annseq->segment->db_adapter->get_segment($dbh, $annseq->segment);
#  return $annseq;
#}
