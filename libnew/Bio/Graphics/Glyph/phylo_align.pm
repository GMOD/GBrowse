package Bio::Graphics::Glyph::phylo_align;

use strict;
use base qw(Bio::Graphics::Glyph::generic Bio::Graphics::Glyph::xyplot);
use Bio::TreeIO;
use POSIX qw(log10);

use Carp 'croak','cluck';
use Data::Dumper;

my %complement = (g=>'c',a=>'t',t=>'a',c=>'g',n=>'n',
		  G=>'C',A=>'T',T=>'A',C=>'G',N=>'N');


# turn off description
sub description { 0 }

# turn off label
# sub label { 1 }

sub height {
  my $self = shift;
  my $font = $self->font;
#  return ($self->extract_features + 1) * 2 * $font->height;
  #return $height if $height;
  
  
  
#  warn Dumper($self->option('tree_format'),$self->option('targ_color'),$self->option('do_gc'),$self->option('fgcolor'),$self->option('species_spacing_score'));
  
  #adjust the space to take if conservation scores are drawn instead
  if (! $self->dna_fits) {
#    warn"dna fits!";
    #print "<pre>".Dumper($self->factory->{'options'})."</pre>";
    my $species_spacing_score = $self->option('species_spacing_score') || 5;
    $self->factory->set_option('species_spacing', $species_spacing_score);
#    $self->factory->set_option('species_spacing') = $self->option('species_spacing_score');
#    $self->factory->{'options'}->{'species_spacing'} = $self->factory->get_option('species_spacing_score');
#    warn"new value is ".$self->option('species_spacing');
  }
  
  my $species_spacing = $self->option('species_spacing') || 1;
  
  #$height = ($self->draw_cladeo + 1) * 2 * $font->height;
  
  #Height = NumSpecies x Spacing/species x FontHeight
  my $height = ($self->known_species + $self->unknown_species + 1)
            * $species_spacing
            * $font->height;
  
  
  #use this if you want to show only those species that have alignments in the viewing window
  #$height = ($self->extract_features + 1) * 2 * $font->height;
  
  $self->factory->set_option('height', $height);
  
  
  return $height;
  
#  return $height || ($self->draw_cladeo + 1) * 2 * $font->height;
#  return $self->dna_fits ? ($self->extract_features + 1) * 2 * $font->height
#       : $self->do_gc    ? $self->SUPER::height
#       : 0;
}


# a bit of a hack accessing the data directly
sub extract_features {
  my $self = shift;
  #my $segment = $self->feature->{'factory'}->segment($self->feature->refseq,
  #						      $self->feature->start => $self->feature->stop);
  #my @match = $segment->features('submatch:pa'); 
  my @match = $self->feature->features('submatch:pa');
  
  my %alignments;
  for my $feature (@match) {
    #my $group = $species->group;
    #my $sourceseq = $group->sourceseq;
    my %attributes = $feature->attributes;
    my $species = $attributes{'species'};
    
    push @{$alignments{$species}}, $feature;
  }
  
  %alignments;
}

#known species (all those that are in the Phylo tree)
sub known_species {
  my $self = shift;
  
  my $tree = shift;
  
  if ($tree) {
  	my @leaves = $tree->get_leaf_nodes;
    my @allspecies = map {$_->id} @leaves;
    #print "<pre>".Dumper(@allspecies)."</pre>";
    return @allspecies
    
  } else {
  	
  	
    my $tree_file = $self->option('tree_file');
    
    open (FH, $tree_file);
    my $newick = <FH>;
    close FH;
    
    my @allspecies = $newick =~ /([a-zA-Z]\w*)/g;
    return @allspecies;
  }
}

sub unknown_species {
  my $self = shift;

  my %alignments;        #all species in viewing window
  my $refspecies;        #all species from cladeogram info
  my @current_species;   #all species in viewing window
  my @known_species;     #species in GFF but not in cladeo
  my @unknown_species;                                 #species in GFF but not in cladeo
  # current - known = unknown
  
  
  if (@_) {
    %alignments = %{$_[0]};
    $refspecies = $_[1];
    @current_species = @{$_[2]};
    @known_species = @{$_[3]};
    @unknown_species;
  } else {
    %alignments = $self->extract_features;
    $refspecies = $self->option('reference');
    @current_species =  keys %alignments;     #all species in viewing window
    @known_species = $self->known_species;  #all species from cladeogram info
    @unknown_species;                                 #species in GFF but not in cladeo
  } #would have combined the two cases into one line using || but Perl will treat the arrays as num of elem
  
  #do set subtraction to see which species in viewing range but not in tree
  my %seen;  # build lookup table
  @seen{@known_species} = ();
  foreach my $item (@current_species, $refspecies) {
    push(@unknown_species, $item) unless exists $seen{$item};
  }
  
  return @unknown_species;
  
}

sub set_tree {
  my $self = shift;
  
  #warn"My species are ".Dumper(@species);
  
  my $tree_file   = $self->option('tree_file');
  my $tree_format = $self->option('tree_format') || 'newick';
  
  my $treeio = new Bio::TreeIO(-file   => $tree_file,
                               -format => $tree_format);
  
  
  #while(my $tree = $treeio->next_tree ) {
  #  for my $node ( $tree->get_nodes ) {
  #    printf "id: %s bootstrap: %s\n", $node->id || '', $node->bootstrap || '', "\n";
  #    #print "id: ".$node->id." bootstrap: ".$node->bootstrap."\n";
  #  }
  #}
  
  #my @taxa = $treeio->next_tree->get_leaf_nodes;
  #warn"my taxa are @taxa";
  #print"my taxa are:\n".Dumper(@taxa);
  
  my $tree = $treeio->next_tree;
  my $root = $tree->get_root_node;
  
#  $tree->remove_Node('dog');
#  $tree->remove_Node('cat');
#  $tree->remove_Node('kangaroo');
#  $tree->remove_Node('mouse');
  #print "<pre>".Dumper($tree)."</pre>";
  #set the leaf x coodinate (make all evenly spaced)
  my @leaves = $tree->get_leaf_nodes;
  #map {print "<pre>".Dumper($_->id)."</pre>"} @leaves;
  for (my $i=0; $i<@leaves; $i++) {
    my $leaf = $leaves[$i];
  
    #note that leaves can use "description" functions while intermediate nodes cannot
    $leaf->description({'x'=>$i});
  
  }
  
  
  #set root height to 0
  $root->{'description'}{'y'} = 0;
  
  #set the x and y coordinates of all intermediate nodes
  get_n_set_next_treenode($root, 0);
  
  flip_xy($tree);

  
  $tree;
  
}

sub get_max_height {
  my $tree = shift;
  my $max_height;
  
  #get the max height
  for my $child ($tree->get_leaf_nodes) {
    my $x = $child->{'_description'}{'x'};
    $max_height = $x if $max_height < $x;
  }
  
  $max_height;
}


sub draw_cladeo {
  my $self = shift;
  my $tree = shift;
  my $gd = shift;
  my ($x1, $y1, $x2, $y2, $color, $xscale, $yscale, $xoffset, $yoffset, $start_x, $draw_cladeo_left) = @_;
  
  my @bounds = $gd->getBounds;
  
  #print"root is:\n".Dumper($root);
  
  #my $xscale = $self->font->height;
  #my $yscale = $self->font->height * 2;
  

  
  #my $x_shift = $x2 - $y_max;
  
  my $root = $tree->get_root_node;
  
  my @nodes = $root->get_all_Descendents;
  
  #draw bg for cladeogram
  my $cladeo_bg = $self->color('cladeo_bg') || $self->bgcolor;
  my @coords = (0, $y1, $start_x+$xoffset+$self->font->width-1, $y2+1);
  my @coords2 = ($x1, $y1, $start_x+$xoffset/2, $y2);
  if ($draw_cladeo_left) {
    $gd->filledRectangle(@coords, $cladeo_bg);
    $gd->filledRectangle(@coords2, $self->color('cladeo_bg'));
    #$gd->filledRectangle(0, $y1, $start_x+$xoffset+$self->font->width-1, $y2, $self->color('bg_color'));
    #$gd->filledRectangle($x1, $y1, $start_x+$xoffset/2, $y2, $self->color('cladeo_bg'));
    $gd->filledRectangle($x2, $x1, $bounds[0], $bounds[1], $self->color('bg_color')) if $self->dna_fits;
  } else {
    $gd->filledRectangle($bounds[0]-$coords[2], $coords[1], $bounds[0]-$coords[0], $coords[3],
  			 $self->color('bg_color'));
    $gd->filledRectangle($bounds[0]-$coords2[2], $coords2[1], $bounds[0]-$coords2[0], $coords2[3],
			 $cladeo_bg);  
    $gd->filledRectangle(0, $y1, $x1, $y2+1, $self->color('bg_color')) if $self->dna_fits;
  }

  
  
  #draw the lines of the tree
  for my $node ($root,@nodes) {
    next if $node->is_Leaf;
    my $x = $node->{'_description'}{'x'} * $xscale;
    #my $y = $node->{'_description'}{"y"} * $yscale;
    #print "$x , $y\n";
    
    
    #draw vertical line covering all children
    my $topx = $node->{'_description'}{'childmin'} * $yscale;
    my $botx = $node->{'_description'}{'childmax'} * $yscale;
    
    #print"$topx - $botx , $x\n";
    
    @coords = ($x+$xoffset, $topx+$yoffset, $x+$xoffset, $botx+$yoffset);
    if ($draw_cladeo_left) {
      $gd->line(@coords, $self->fgcolor);
    } else {
      $gd->line($bounds[0]-$coords[2], $coords[1], $bounds[0]-$coords[0], $coords[3], $self->fgcolor);
    }
    
    #draw a line connecting the bar to each child
    my @children = $node->each_Descendent;
    for my $child (@children) {
      my $cx = $child->{'_description'}{'x'} * $xscale;
      my $cy = $child->{'_description'}{'y'} * $yscale;
      $cx = $start_x if $child->is_Leaf;
      
      #print"($cx, $cy)";
      
      @coords = ($x+$xoffset, $cy+$yoffset, $cx+$xoffset, $cy+$yoffset);
      if ($draw_cladeo_left) {
        $gd->line(@coords, $self->fgcolor);
      } else {
          $gd->line($bounds[0]-$coords[2], $coords[1], $bounds[0]-$coords[0], $coords[3], $self->fgcolor);
      }
      
    }
    #for my $child_x (@{$node->{'_description'}{'child_pos'}}) {
    #  print"  > $child_x\n";
    #}
    
  }
  
  
  
  
  #print "root is:\n".Dumper($root);
  #my @children = $root->each_Descendent;
  #my @allchildren = $root->get_all_Descendents;
  #print "root is:\n".Dumper($root);
  #print "children are:\n".Dumper(@children);
  
  
  #print "all children are:\n".Dumper(@allchildren);
  #print"all children:";
  #for my $child (@allchildren) {
  #  print $child->id."\n";
  #}
  
  
  #my @nodes = $tree->get_nodes;
  #print "nodes are:\n".Dumper(@nodes);
  
  
  #my $tree = $treeio->next_tree;
  #my @nodes = grep { $_->bootstrap > 70 } $tree->get_nodes;
  #warn"my nodes are:\n".Dumper(@nodes);
  print"</pre>";
  
  $start_x + $xscale;
  
  }

#tree is made with root on top but this will switch x and y coords so root is on left
sub flip_xy {
  my $tree = shift;
  my $root = $tree->get_root_node;
  
  my @nodes = $root->get_all_Descendents;
  
  for my $node ($root, @nodes) {
    if ($node->is_Leaf) {
      $node->{'_description'} = {
        'x'       => $node->{'_description'}{'y'},
        'y'       => $node->{'_description'}{'x'}
      }
    } else {
      $node->{'_description'} = {
        'x'         => $node->{'_description'}{'y'},
        'y'         => $node->{'_description'}{'x'},
        'child_pos' => $node->{'_description'}{'child_pos'},
        'childmin'  => $node->{'_description'}{'childmin'},
        'childmax'  => $node->{'_description'}{'childmax'}
      }
    }
  }
  
  
}


#recursive function that sets the x and y coordinates of tree nodes
sub get_n_set_next_treenode {
  my $node = shift;
  my $height = $node->{'_description'}{'y'};
  
  my @children = $node->each_Descendent;
  
  
  my $x = 0;
  my $min_child_x = -1;
  my $max_child_x = -1;
  
  #iterate through children to find the x's and set the y's
  for my $child (@children) {
    #set the y coordinate as parent's height + 1
    $child->{'_description'}{'y'} = $height + 1;
    get_n_set_next_treenode($child);
    
    #retrieve the child's x coordinate
    my $child_x = $child->{'_description'}{'x'} || 0;
    $x += $child_x;
    
    $min_child_x = $child_x if $min_child_x==-1 || $child_x < $min_child_x;
    $max_child_x = $child_x if $max_child_x==-1 || $max_child_x < $child_x;
    #$x += $child->discription->{'x'};  #cannot do this for intermediate nodes
    
    #store the x values of all children
    push @{$node->{'_description'}{'child_pos'}}, $child_x;
    
    
  }
  
  #print $node->id . " has combined with @children to get $x.  $max_child_x - $min_child_x\n";
  
  #set the current x coordinate as the average of all children's x's
  if (@children) {
    $x = $x / @children;
    $node->{'_description'}{'x'} = $x;
    $node->{'_description'}{'childmin'} = $min_child_x;
    $node->{'_description'}{'childmax'} = $max_child_x;

  }
  
  $node->{'_description'}{'y'} = $height;
   
}

sub get_legend_and_scale {
  my $yscale = shift;
  my $height = shift;
  
  if ($yscale < 2*$height - 1) {
    $height = 0;
  }
  
  #chage scale later so that the base can  be anything!!
  
#  my @order = (@_, 1);
  my @order = sort {$a <=> $b} (1, @_);
#    my @order = sort {$a <=> $b} (1, $min_score, 5.3e-487);
  my $graph_scale = - ($yscale - $height) / (log10($order[2]) - log10($order[0]));
  my $graph_legend = {1 => $graph_scale * (log10(1) - log10($order[2])),
  		   $order[0] => $graph_scale * (log10($order[0]) - log10($order[2])),
    		   $order[2] => 0};
    
  #print "order is @order and the yscale is $yscale and height is $height<br>";
#  print"<pre>".Dumper($graph_scale, $graph_legend)."</pre>";
  #$graph_scale 
  
  return ($graph_legend, $graph_scale);

}

sub draw {
  my $self = shift;
#  my @feats = $self->extract_features;
  my $height = $self->font->height;
  my $scale = $self->scale;
  
#print"<pre>".Data::Dumper::Dumper($self)."</pre>";
  
  my $gd = shift;
  my ($left,$top,$partno,$total_parts) = @_;
  my ($x1,$y1,$x2,$y2) = $self->bounds($left, $top);
  
  
  my @bounds = $gd->getBounds;
#print "$x1,$y1,$x2,$y2 , $left,$top @bounds";  
  ######### control by default setting and by coordinate
  my $draw_cladeo_left = $self->option('draw_cladeo_left');
  
  
#$gd->rectangle($x1, $y1, $x2, $y2, $self->fgcolor); 


# The start / stop and other info using the warn command 
#warn "DRAW::".$self->feature->start."-".$self->feature->stop.",".$self->feature->refseq." ; height $height"
#	." ; scale:".$self->scale . " ; coords:($x1,$y1,$x2,$y2)";

#$gd->rectangle(($x1+$scale*(2000-$self->start)), 25, ($x1+$scale*(3000-$self->start)), 30, $self->fgcolor);
#warn ($x1+$scale*(2000-$self->start));

#warn"Search Results:\n".Dumper(@feats);


#  warn"featseq is".Dumper($feats[0]->seq->seq);

#warn"Being called here".$self->parts;
#fasdfasd "try this";
#  $self->SUPER::draw(@_);
  
  
  my $species_spacing = $self->option('species_spacing') || 1;
  
  my $xscale = $self->font->width;
  my $yscale = $height * $species_spacing;
  
  
  
  #method that reads the NEWICK formatted file to create the tree objects
  my $xoffset = $x1;
  my $yoffset = $y1 + 0.5*$self->font->height;
  
  
  
  my $tree = $self->set_tree;
  my $max_height = get_max_height($tree);
  my $start_x =($max_height-1) * $xscale +$xoffset;
  
  #print "start x is $start_x with scale $scale";
  
  
  my $connector = $self->connector;
  
  #all species having alignments in viewing window (key=name, val=feat obj)
  my %alignments = $self->extract_features;
#print"<pre>alignments:\n".Dumper(%alignments)."</pre>";
  
  my ($min_score, $max_score) = $self->get_score_bounds(%alignments);
#$max_score = 300000000000000000000000000000000;
  my ($graph_legend, $graph_scale) = get_legend_and_scale($yscale, $height, $min_score, $max_score);
#  print"<pre>".Dumper($graph_scale, $graph_legend, $min_score, $max_score, $graph_legend->{$min_score}, $graph_legend->{$max_score})."</pre>";
  
  
  
  my $refspecies = $self->option('reference');
  
  my @current_species = keys %alignments;    #all species in viewing window
  my @known_species = $self->known_species($tree);  #all species from cladeogram info
  my @unknown_species = $self->unknown_species(\%alignments, 
    						 $refspecies,
    						\@current_species,
    						\@known_species);
                                              #species in GFF but not in cladeo

  
  #print"my current are: @current_species<br>\n";
  #print"my known are:   @known_species<br>\n";
  #print"my unknown are: @unknown_species<br>\n";
  
  
  my @allfeats;
  for my $species (keys %alignments) {
    push @allfeats, @{$alignments{$species}};
  }
  #print"<pre>alignments:\n".Dumper(@allfeats)."</pre>";
  
  ##not really working right now
  #$self->draw_xy($gd,$left,$top,\@allfeats,$min_score, $max_score);
  
  
  
  #exit;
  
  
  my $y = $y1;
  
  ####$#%@#$%@#$%@#$%@#$%
  #demo?
  #http://localhost/cgi-bin.dev/gbrowse_run/volvox?start=1100;stop=11200;ref=ctgA;width=800;version=100;flip=;label=ExampleFeatures-PhyloAlignment-TransChip%3Aregion-Motifs%3Aoverview;grid=1
  #http://localhost/cgi-bin.dev/gbrowse_run/volvox?start=3550;stop=3650;ref=ctgA;width=800;version=100;flip=;label=ExampleFeatures-PhyloAlignment-TransChip%3Aregion-Motifs%3Aoverview;grid=1
  
  
  #http://localhost/cgi-bin.dev/gbrowse_run/volvox?start=1100;stop=11200;ref=ctgA;width=800;version=100;flip=;label=ExampleFeatures-EST-PhyloAlignment-TransChip%3Aregion-Motifs%3Aoverview;grid=1
  
  #http://localhost/cgi-bin.dev/gbrowse_run/volvox?start=1100;stop=11200;ref=ctgA;width=800;version=100;flip=;label=ExampleFeatures-EST-PhyloAlignment-TransChip%3Aregion-Motifs%3Aoverview;grid=1
  
  #for my $species (keys %alignments) {
  for my $species (@known_species,@unknown_species) {
    my $y_track_top = $y + $height;
#    $y_track_top += $height unless ($y_track_bottom - $y_track_top < $height);
    my $y_track_bottom = $y + $yscale;
    #$y_track_top += $height unless ($y_track_bottom - $y_track_top < 2*$height-1);
    
    
    if ($yscale < 2*$height-1) {
      #print "small scale";
      $y_track_top = $y;# + $height;
#      $y_track_top += $height unless ($y_track_bottom - $y_track_top < $height);
      my $y_track_bottom = $y + $height;
      #$y_track_top += $height unless ($y_track_bottom - $y_track_top < 2*$height-1);
    }
    
    #print"$y_track_top, $y_track_bottom  ,  $yscale, height $height<br>";
    
    
    
#    $gd->line(250,250,300,$y_track_top,$self->fgcolor);
#    print"height is $height<br>";
    
    
    
    
    
#    next unless $alignments{$species};
    
    
#    my ($fx1,$fy1) = ($x1, $y);
#    my ($fx2,$fy2) = ($x1,$y+$height);
    
    
    #process the reference sequence differently
    if ($species eq $refspecies) {
      #draw DNA alignments if zoomed close enough
        my ($fx1,$fy1) = ($x1, $y_track_top);
      	my ($fx2,$fy2) = ($x2,$y_track_bottom);
      	#my ($fx2,$fy2) = ($x2,$y+2*$height);
      	
      

      if ($self->dna_fits) {
	my $dna = eval { $self->feature->seq };
        $dna    = $dna->seq if ref($dna) and $dna->can('seq'); # to catch Bio::PrimarySeqI objects
        my $bg_color = $self->color('ref_color') || $self->bgcolor;
        
        $fy2 = $fy1 + $self->font->height || $y2;
  
        
	$self->_draw_dna($gd,$dna,$fx1,$fy1,$fx2,$fy2, $self->fgcolor, $bg_color);
	#print "draw the source $species with DNA:<br>$dna";
      } else {
      	#$self->pairwise_draw_graph($gd, $fx1, $fy1+$height/2, $fx2, $fy1+$height/2, $self->fgcolor);
      	##$gd->line($fx1, $fy1+$height/2, $fx2, $fy1+$height/2, $self->fgcolor);
      }
      
      my $x_label_start = $start_x + $xoffset + $self->font->width;
      $self->species_label($gd, $draw_cladeo_left, $x_label_start, $y, $species) unless ($self->option('hide_label'));
      
      $y += $yscale;
      next;
    }
    
#warn"species proc right now: $species";
    
    
    
    #skip if the there is no alignments for this species in this window
    unless ($alignments{$species}) {
      my $x_label_start = $start_x + $xoffset + $self->font->width;
      $self->species_label($gd, $draw_cladeo_left, $x_label_start, $y, $species) unless ($self->option('hide_label'));
      
      $y += $yscale;
      next;
    }
    
    
    
    my @features = @{$alignments{$species}};
    
    
    
    
    
    
    
    #draw the axis for the plots
    $self->draw_pairwisegraph_axis($gd,
    				    $graph_legend,
    				    $x1,
    				    $x2,
    				    $y_track_top,
    				    $y_track_bottom,
    				    $draw_cladeo_left,
    				    @bounds) unless $self->dna_fits;
      
    
    
    
    for my $feat (@features) {
      my ($start, $stop, %attributes) = ($feat->start, $feat->stop, $feat->attributes);
      #warn"-- $start to $stop ; ".Dumper(%attributes);
      
      my ($fx1,$fy1) = ($x1 + ($start-$self->start)*$scale, $y_track_top);
      my ($fx2,$fy2) = ($x1 + ($stop-$self->start)*$scale,$y_track_bottom);
      #my ($fx2,$fy2) = ($x1 + ($stop-$self->start)*$scale,$y+2*$height);
      
      my $gapstr = $attributes{'Gap'} || return;
      my @gapstr = split " ", $gapstr;
      my @gaps;
      for my $gap (@gapstr) {
        my ($type, $num) = $gap =~ /^(.)(\d+)/; 
#warn"$gap has $type and $num";
      	push @gaps, [$type, $num+0];
      }
#warn"gap is:".Dumper(@gaps);#@gaps";
      
      
#print "Species $species<br><pre>";
#for my $key (keys %{$feat->hit}) {
# next if $key eq "factory";
# print "$key : ".Dumper($feat->hit->{$key})
#}
#print"source seq: ".$feat->hit->seq->seq;
#print"==<br>";
#for my $key (keys %{$feat}) {
#  next if $key eq "factory";
#  print "$key : ".Dumper($feat->hit->{$key})
#}
#print "</pre>";
#print"-------------------------------<br>";
      
      
      #draw DNA alignments if zoomed close enough
      if ($self->dna_fits) {

	my $ref_dna = $feat->seq->seq;
	my $targ_dna = $feat->hit->seq->seq;
	
#$print"DNA!!:<br>$ref_dna<br>$targ_dna<p>";
	
	my $offset = $feat->start - $self->start;
#	if ($offset < 0) {
#	  $dna = substr($dna, -$offset);
#	  $fx1 = $left;
#	  for my $gap (@gaps) {
#	    my $diff = $offset + $gap->[1];
#	    if (0 <= $offset) {
#	      if $gap
#	      break;
#	    }
	     
#	  }
	  
#	}
#warn ($fx1+$scale*($feat->start-$self->start));
	#$self->draw_component($gd, $fx1, $fy1, $fx2, $fy2);
	$self->draw_dna($gd,$ref_dna, $targ_dna,$fx1,$fy1,$fx2,$fy2,\@gaps);
      } else {
      	$self->pairwise_draw_graph($gd, $feat, $x1, $scale, \@gaps, $graph_legend->{1}, $graph_scale, $fx1, $fy1, $fx2, $fy2);
      	#$self->pairwise_draw_graph($gd, $feat, $x1, $scale, \@gaps, $min_score, $max_score, $graph_legend->{1}, $graph_scale, $fx1, $fy1, $fx2, $fy2, $self->fgcolor);
#print"$fx1<pre>".Dumper($feat->score, $min_score, $max_score, $graph_legend->{1}, $graph_scale, $fx1, $fy1, $fx2, $fy2)."</pre>";
      	#$self->pairwise_draw_graph($gd, $fx1, $fy1+$height/2, $fx2, $fy1+$height/2, $self->fgcolor)
      	#$gd->line($fx1, $fy1+$height/2, $fx2, $fy1+$height/2, $self->fgcolor);
      }
    }
    
    
    #label the species in the cladeogram
    my $x_label_start = $start_x + $xoffset + $self->font->width;
    $self->species_label($gd, $draw_cladeo_left, $x_label_start, $y, $species) unless ($self->option('hide_label'));
    
    $y += $yscale;
  }
  
    $self->draw_cladeo($tree, $gd, $x1, $y1, $x2, $y2, $self->fgcolor,
  		     $xscale, $yscale, $xoffset, $yoffset, $start_x, $draw_cladeo_left);
  

}



sub species_label {
  my $self = shift;
  my $gd = shift;
  my $draw_cladeo_left = shift;
  my $x_start = shift;
  my $y_start = shift;
  my $species = shift;
  
  $x_start += 2;
  my $text_width = $self->font->width * length($species);
  my $bgcolor = $self->color('bg_color');
  
  #make label
  if ($draw_cladeo_left) {
#    $gd->string($self->font, $start_x + $xoffset + $self->font->width, $y, $species, $self->fgcolor);
#print "$x_start, $y_start, $species<br>";
    
    $gd->filledRectangle($x_start-2, $y_start, $x_start + $text_width, $y_start+$self->font->height, $bgcolor);
    $gd->rectangle($x_start-2, $y_start, $x_start + $text_width, $y_start+$self->font->height, $self->fgcolor);
    $gd->string($self->font, $x_start, $y_start, $species, $self->fgcolor);
    
  } else {
    my ($x_max, $y_max) = $gd->getBounds;
    #my $write_pos = $x_max - $x_start - $self->font->width * length($species);
    my $write_pos = $x_max - $x_start - $text_width;
#print "$x_max - $y_max, $x_start, $write_pos, $y_start, $species<br>";
    
#    my $write_pos = $bounds[0] - ($start_x + $xoffset) - $self->font->width * (length($species)+1);
#    $gd->string($self->font, $write_pos, $y, $species, $self->fgcolor);
    
    $gd->filledRectangle($write_pos, $y_start, $write_pos + $text_width+2, $y_start+$self->font->height, $bgcolor);
    $gd->rectangle($write_pos, $y_start, $write_pos + $text_width+2, $y_start+$self->font->height, $self->fgcolor);
    $gd->string($self->font, $write_pos+2, $y_start, $species, $self->fgcolor);
    

  }
}


# draws the legends on the conservation scale
sub draw_pairwisegraph_axis {
  my $self = shift;
  my ($gd, $graph_legend, $x1, $x2, $y_track_top, $y_track_bottom, $draw_cladeo_left, @bounds) = @_;
  
  
  my $axis_color = $self->color('axis_color') || $self->fgcolor;
  my $mid_axis_color = $self->color('mid_axis_color') || $axis_color;
#print"$x1,$y,$x2,$y <br>";
  
  for my $label (keys %$graph_legend) {
    my $y_label = $graph_legend->{$label} + $y_track_top;


#  print "$y_track_top , $y_track_bottom  currently $y_label<br>";
    
    my $col = $axis_color;
    $col = $mid_axis_color if ($y_label != $y_track_top && $y_label != $y_track_bottom);
    $gd->line($x1,$y_label,$x2,$y_label,$col);
    
    my @coords = (0, $y_label, $x1, $y_label);
    
    
    if ($draw_cladeo_left) {
      #draw the legend on the right
      $coords[0] = $bounds[0] - $coords[0];
      $coords[2] = $bounds[0] - $coords[2];
      
      my $x_text_offset = length($label) * $self->font->width;
      
      $gd->string($self->font, $coords[0]-$x_text_offset, $coords[1], $label, $self->fgcolor);
      $gd->line(@coords, $self->fgcolor);
      
      $gd->line($x2,$y_track_top,$x2,$y_track_bottom,$self->fgcolor);
    } else {
      #draw the legned on the left
      $gd->string($self->font, @coords[0..1], $label, $self->fgcolor);
      $gd->line(@coords, $self->fgcolor);
      
      $gd->line($x1,$y_track_top,$x1,$y_track_bottom,$self->fgcolor);
    }
  
  }
  
  #draw the top and bottom axis
  #$gd->line($x1,$y_track_top,$x2,$y_track_top,$axis_color);
  #$gd->line($x1,$y_track_bottom,$x2,$y_track_bottom,$axis_color);
}



sub get_score_bounds {
  my $self = shift;
  my %alignments = @_;
  
  my $min = -1;
  my $max = -1;
  
  for my $species (keys %alignments) {
    for my $feature (@{$alignments{$species}}) {
      my $score = $feature->score;
      $min = $score if $min == -1 || $score < $min;
      $max = $score if $max == -1 || $max < $score;
    }
  }
  
  
  my @parts = $self->parts;
  #print "<pre>Parts are:\n".Dumper(@parts)."</pre>";
  
  return ($min, $max)
}



sub pairwise_draw_graph {
  my $self = shift;
  my $gd = shift;
  my $feat = shift;		# current feature object
  my $x_edge = shift;		# x start position of the track
  my $scale = shift;		# pixels / bp
  my $gaps = shift;		# gap data for insertions, deletions and matches
#  my $min_score = shift;
#  my $max_score = shift;
  my $zero_y = shift;		# y coordinate of 0 position
  my $graph_scale = shift;	# scale for the graph. y_coord = graph_scale x log(score)
  
  my ($x1,$y1,$x2,$y2) = @_;
  my $fgcolor = $self->fgcolor;
  my $errcolor  = $self->color('errcolor') || $fgcolor;
  
  my $score = $feat->score;
  my %attributes = $feat->attributes;
  
  
  #print"AAAA<pre>".Data::Dumper::Dumper($gaps)."</pre>BBBBB<br>scale is $xscale";
  
  
  my $log_y = log10($score);
  my $y_bottom = log10($score) * $graph_scale + $zero_y + $y1;
  my $y_top = $zero_y+$y1;
  
  my @y = sort {$a <=> $b} ($y_bottom, $y_top);
  
  
  
  #missing gap data
  unless ($gaps) {
    $x1 = $x_edge if $x1 < $x_edge;
    return if $x2 < $x_edge;
    #$gd->filledRectangle($x1,$y[0],$x2,$y[1],$fgcolor);
    return;
  }
  
  my $bp = 0;
  
#  warn"gaps are:\n".Dumper($gaps);
  for my $tuple (@$gaps) {
    my ($type, $num) = @$tuple;
    
    #warn"$type and $num";
    if ($type eq "M") {
      my $x_left  = $x1 + ($bp*$scale);
      my $x_right = $x_left + $num*$scale;
      
      $bp += $num;
      
      $x_left = $x_edge if $x_left < $x_edge;
      next if $x_right < $x_edge;
      $gd->filledRectangle($x_left,$y[0],$x_right,$y[1],$fgcolor);
    } elsif ($type eq "D") {
      #$bp += $num;
      
      #my $x_left  = $x1 + ($bp*$xscale);
      #my $x_right = $x_left + $num*$xscale;
      
      #warn"Deletion: $bp + $num => $x_left - $x_right";
      
      $bp += $num;
      
      #$x_left = $x_edge if $x_left < $x_edge;
      #next if $x_right < $x_edge;
      #$gd->filledRectangle($x_left,$y[0]+20,$x_right,$y[0]+25,$fgcolor);
      
      
    } elsif ($type eq "I") {
      my $x_left  = $x1 + ($bp*$scale);
      $gd->line($x_left-2, $y1-4, $x_left, $y1, $errcolor);
      $gd->line($x_left, $y1, $x_left+2, $y1-4, $errcolor);
    }
    

  }
  
  
  
  #  print "My feat with score $score from [$min_score , $max_score] at pos $x1,$y1,$x2,$y2\t y pos: $zero_y to $y with log of $log_y and scale $graph_scale<br>";
  
  #$x1 = $x_edge if $x1 < $x_edge;
  #return if $x2 < $x_edge;
  #$gd->filledRectangle($x1,$y[0],$x2,$y[1],$fgcolor);
  #$gd->filledRectangle($x1,$zero_y+$y1,$x2,$y,$fgcolor);
  
  
  
#  $gd->line($x1,$y1,$x2,$y1,$fgcolor);
#  $gd->line($x1,$y2,$x2,$y2,$fgcolor);
  
  #$gd->rectangle($x1,$y1,$x2,$y2, $fgcolor);
  
}



sub draw_dna {
  my $self = shift;
#print"<pre>".Data::Dumper::Dumper($self)."</pre>";
  my ($gd,$ref_dna, $dna,$x1,$y1,$x2,$y2, $gaps) = @_;
  my $pixels_per_base = $self->scale;
  
  my $fgcolor = $self->fgcolor;
  my $bg_color = $self->color('targ_color') || $self->bgcolor;
  my $errcolor  = $self->color('errcolor') || $fgcolor;
  #print"colors are: $fontcolor, $bg_color $errcolor black:".$self->fgcolor;
  
  
  $y2 = $y1 + $self->font->height || $y2;
  
#print"$dna<br>$ref_dna<br>".Dumper($gaps)."<br>";
  
  
  #missing gap data, draw as is
  unless ($gaps) {
    warn"no gap data for DNA sequence $dna";
    $self->_draw_dna($gd, $dna, $x1, $y1, $x2, $y2);
    return;
  }
  
#  warn"gaps are:\n".Dumper($gaps);
  #parse the DNA segments by the gaps
  for my $tuple (@$gaps) {
    my ($type, $num) = @$tuple;
    
    #warn"$type and $num";
    if ($type eq "M") {
      my $dnaseg = substr($dna, 0, $num);
      my $ref_dnaseg = substr($ref_dna, 0, $num);
#print"$dnaseg<br>$ref_dnaseg<br>";
      $self->_draw_dna($gd,$dnaseg, $x1, $y1, $x2, $y2, $fgcolor, $bg_color,$ref_dnaseg);
      $dna = substr($dna, $num);
      $ref_dna = substr($ref_dna, $num);
      $x1 += $num * $pixels_per_base;
    } elsif ($type eq "D") {
      my $dnaseg = '-' x $num;
      $self->_draw_dna($gd, $dnaseg, $x1, $y1, $x2, $y2, $fgcolor); 
      $gd->rectangle($x1, $y1-1, $x1+$num * $pixels_per_base, $y2+1, $errcolor);
      $ref_dna = substr($ref_dna, $num);
      $x1 += $num * $pixels_per_base;
    } elsif ($type eq "I") {
      $dna = substr($dna, $num);
      $gd->line($x1-2, $y1-2, $x1+2, $y1-2, $errcolor);
      $gd->line($x1, $y1-1, $x1, $y2+1, $errcolor);
      $gd->line($x1-2, $y2+1, $x1+2, $y2+1, $errcolor);
    }
    
#print"$type - $num<br>$dna<br>$ref_dna<br>";

  }
#  print"<p>";
  
  
}

sub _draw_dna {
  my $self = shift;

#print"<pre>".Data::Dumper::Dumper($self)."</pre>";
  #the last argument is optional.  If the reference seq is given, it will check it
  my ($gd,$dna,$x1,$y1,$x2,$y2, $color, $bg_color, $ref_dna) = @_;
  
  my $pixels_per_base = $self->scale;
  my $feature = $self->feature;
  
  unless ($ref_dna) {
    $gd->filledRectangle($x1+1, $y1, $x2, $y2, $bg_color);
  }
  

my $feature = $self->feature;
#my ($ref,$class,$start,$stop,$strand) 
#    = @{$self}{qw(sourceseq class start stop strand)};
#warn "$ref,$class,$start,$stop,$strand";
#warn"($x1,$y1,$x2,$y2)";
#warn"feature name is :".$feature->name;
#warn"feature refseq is :".$feature->refseq;
#warn"feature start is :".$feature->start;
#warn"feature features is :".$feature->features;
#warn"feature end is :".$feature->end;
##warn"feature method is :".$feature->method;
#warn"feature strand is :".$feature->strand;
#warn"feature length is :".$feature->length;
##warn"feature attributes is:\n".Dumper(\%{$feature->attributes});
#warn"---------------------------";



#print "Sequence is _${dna}_<br>\n";
  my $strand = $feature->strand || 1;
  $strand *= -1 if $self->{flip};

  my @bases = split '',$strand >= 0 ? $dna : $self->reversec($dna);
  my @refbases = split '',$strand >= 0 ? $ref_dna : $self->reversec($ref_dna);
  
#print "<pre>@bases\n@refbases</pre><p>";
  
  
#print "bases are:<br>\n<pre>".Data::Dumper::Dumper(@bases)."</pre>";
  #$color |= $self->fgcolor;
  $color = $self->fgcolor unless $color;
  $bg_color = 0 unless $bg_color;
  my $font  = $self->font;
  my $lineheight = $font->height;
#  $y1 -= $lineheight/2 - 3;          ##################NOT SURE WHY THIS WAS HERE BEFORE
  my $strands = $self->option('strand') || 'auto';

  my ($forward,$reverse);
  if ($strands eq 'auto') {
    $forward = $feature->strand >= 0;
    $reverse = $feature->strand <= 0;
  } elsif ($strands eq 'both') {
    $forward = $reverse = 1;
  } elsif ($strands eq 'reverse') {
    $reverse = 1;
  } else {
    $forward = 1;
  }
  # minus strand features align right, not left
  $x1 += $pixels_per_base - $font->width - 1 if $strand < 0;
  for (my $i=0;$i<@bases;$i++) {
    my $x = $x1 + $i * $pixels_per_base;
    
    my $x_next = $x + $pixels_per_base;

#print "pixels per base $pixels_per_base<br>";    
#    print "$bases[$i]=$refbases[$i]<br>" if $bases[$i] eq $refbases[$i];
    
    #draw background if DNA base aligns with reference (if ref given)
    $gd->filledRectangle($x+1, $y1, $x_next, $y2, $bg_color) 
    			if ( ($forward && $bases[$i] eq $refbases[$i]) ||
    			     ($reverse && $complement{$bases[$i]} eq $refbases[$i]) );
    
    $gd->char($font,$x+2,$y1,$bases[$i],$color)                                   if $forward;
    $gd->char($font,$x+2,$y1+($forward ? $lineheight:0),
	      $complement{$bases[$i]}||$bases[$i],$color)                         if $reverse;
  }
#$gd->rectangle($x1,$y1,$x2,$y2,$self->fgcolor);
}


1;

__END__

=head1 NAME

Bio::Graphics::Glyph::phylo_align - The "phylogenetic alignment" glyph

=head1 SYNOPSIS

  See L<Bio::Graphics::Panel> and L<Bio::Graphics::Glyph>.

=head1 DESCRIPTION


This glyph draws a cladogram for any set of species along with their
alignment data in relation to the reference species.  At high
magnification, base pair alignements will be displayed.  At lower
magnification, a conservation score plot will be drawn.  Gaps as
specified by CIGAR are supported.  Currently the scores are drawn to
a log plot with the restriction that the score will be the same
across all base pairs within an alignment.  It is hoped that this
restriction can be addressed in the future.

For this glyph to work, the feature must return a DNA sequence string
in response to the dna() method.  Also, a valid tree file must be
available in a format readable by the Bio::Tree library.

=head2 OPTIONS

The following options are standard among all Glyphs.  See
L<Bio::Graphics::Glyph> for a full explanation.

  Option      Description                      Default
  ------      -----------                      -------

  -fgcolor      Foreground color	       black

  -outlinecolor	Synonym for -fgcolor

  -bgcolor      Background color               turquoise

  -fillcolor    Synonym for -bgcolor

  -linewidth    Line width                     1

  -height       Height of glyph		       10

  -font         Glyph font		       gdSmallFont

  -connector    Connector type                 0 (false)

  -connector_color
                Connector color                black

  -label        Whether to draw a label	       0 (false)

  -description  Whether to draw a description  0 (false)

  -hilite       Highlight color                undef (no color)

In addition to the common options, the following glyph-specific
options are recognized:

  Option      Description               Default
  ------      -----------               -------

  -draw_cladeo_left
              Draws the Cladogram on left 0

  -species_spacing
              Spacing of species in DNA   1
              mode in units of font height

  -species_spacing_score
              Spacing of spcies in        5
              conservation view in units
              of font height

  -hide_label Whether to label spcies     0

  -tree_file  Path of file containing     undef
              cladogram tree information
  -tree_format Format of tree file	   newick

  -axis_color Color of the vertical axes  fgcolor
              in the GC content graph

  -errcolor   Color of all misalignment   fgcolor
              indicators

  -mid_axis_color
              Color of the middle axis of
              the conservation score graph axis_color

  -cladeo_bg  Color of the clado bg       bgcolor
              indicators

  -ref_color  Color of base pair bg for   bgcolor
              the reference sequence

  -targ_color Color of base pair bg for   bgcolor
              all base pairs that match
              reference



=head1 BUGS

Please report them.

=head1 SEE ALSO

L<Bio::Graphics::Panel>,
L<Bio::Graphics::Glyph>,
L<Bio::Graphics::Glyph::arrow>,
L<Bio::Graphics::Glyph::cds>,
L<Bio::Graphics::Glyph::crossbox>,
L<Bio::Graphics::Glyph::diamond>,
L<Bio::Graphics::Glyph::dna>,
L<Bio::Graphics::Glyph::dot>,
L<Bio::Graphics::Glyph::ellipse>,
L<Bio::Graphics::Glyph::extending_arrow>,
L<Bio::Graphics::Glyph::generic>,
L<Bio::Graphics::Glyph::graded_segments>,
L<Bio::Graphics::Glyph::heterogeneous_segments>,
L<Bio::Graphics::Glyph::line>,
L<Bio::Graphics::Glyph::pinsertion>,
L<Bio::Graphics::Glyph::primers>,
L<Bio::Graphics::Glyph::rndrect>,
L<Bio::Graphics::Glyph::segments>,
L<Bio::Graphics::Glyph::ruler_arrow>,
L<Bio::Graphics::Glyph::toomany>,
L<Bio::Graphics::Glyph::transcript>,
L<Bio::Graphics::Glyph::transcript2>,
L<Bio::Graphics::Glyph::translation>,
L<Bio::Graphics::Glyph::triangle>,
L<Bio::DB::GFF>,
L<Bio::SeqI>,
L<Bio::SeqFeatureI>,
L<Bio::Das>,
L<GD>

=head1 AUTHORS

Hisanaga Mark Okada
Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2001 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut
