package Bio::Graphics::Glyph::phylo_align;

use strict;
use base qw(Bio::Graphics::Glyph::generic);
use Bio::TreeIO;

use Carp 'croak','cluck';
use Data::Dumper;

my %complement = (g=>'c',a=>'t',t=>'a',c=>'g',n=>'n',
		  G=>'C',A=>'T',T=>'A',C=>'G',N=>'N');

my $height;


# turn off description
sub description { 0 }

# turn off label
# sub label { 1 }

sub height {
  my $self = shift;
#warn"self is:\n".Data::Dumper::Dumper($self);
  my $font = $self->font;
#  return ($self->extract_features + 1) * 2 * $font->height;
  return $height if $height;
  
  
  #$height = ($self->draw_cladeo + 1) * 2 * $font->height;
  
  #Height = NumSpecies x Spacing/species x FontHeight
  $height = ($self->known_species + $self->unknown_species)
            * $self->factory->get_option('species_spacing') 
            * $font->height;
  
  
  #use this if you want to show only those species that have alignments in the viewing window
  #$height = ($self->extract_features + 1) * 2 * $font->height;
  
  
  return $height;
  
#  return $height || ($self->draw_cladeo + 1) * 2 * $font->height;
#  return $self->dna_fits ? ($self->extract_features + 1) * 2 * $font->height
#       : $self->do_gc    ? $self->SUPER::height
#       : 0;
}

sub do_gc {
  my $self = shift;
  my $do_gc = $self->option('do_gc');
  return  if defined($do_gc) && !$do_gc;
  return  1;
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
  	
  	
    my $tree_file = $self->factory->get_option('tree_file');
    
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
    $refspecies = $self->factory->get_option('reference');
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
  
  my $tree_file   = $self->factory->get_option('tree_file');
  my $tree_format = $self->factory->get_option('tree_format');
  
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
  my $cladeo_bg = $self->color('cladeo_bg');
  my @coords = (0, $y1, $start_x+$xoffset+$self->font->width-1, $y2+1);
  my @coords2 = ($x1, $y1, $start_x+$xoffset/2, $y2);
  if ($draw_cladeo_left) {
    $gd->filledRectangle(@coords, $self->color('bg_color'));
    $gd->filledRectangle(@coords2, $self->color('cladeo_bg'));
    #$gd->filledRectangle(0, $y1, $start_x+$xoffset+$self->font->width-1, $y2, $self->color('bg_color'));
    #$gd->filledRectangle($x1, $y1, $start_x+$xoffset/2, $y2, $self->color('cladeo_bg'));
    $gd->filledRectangle($x2, $x1, $bounds[0], $bounds[1], $self->color('bg_color'));
  } else {
    $gd->filledRectangle($bounds[0]-$coords[2], $coords[1], $bounds[0]-$coords[0], $coords[3],
  			 $self->color('bg_color'));
    $gd->filledRectangle($bounds[0]-$coords2[2], $coords2[1], $bounds[0]-$coords2[0], $coords2[3],
			 $self->color('cladeo_bg'));  
    $gd->filledRectangle(0, $y1, $x1, $y2+1, $self->color('bg_color'));
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
    #for my $child_x (@{$node->{'_description'}{'child_x'}}) {
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
        'x'        => $node->{'_description'}{'y'},
        'y'        => $node->{'_description'}{'x'},
        'child_y'  => $node->{'_description'}{'child_x'},
        'childmin' => $node->{'_description'}{'childmin'},
        'childmax' => $node->{'_description'}{'childmax'}
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
    push @{$node->{'_description'}{'child_x'}}, $child_x;
    
    
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
  
  ######### control by default setting and by coordinate
  my $draw_cladeo_left = $self->factory->get_option('draw_cladeo_left');
  
  
#$gd->rectangle($x1, $y1, $x2, $y2, $self->fgcolor); 

warn "DRAW::".$self->feature->start."-".$self->feature->stop.",".$self->feature->refseq." ; height $height"
	." ; scale:".$self->scale . " ; coords:($x1,$y1,$x2,$y2)";

#$gd->rectangle(($x1+$scale*(2000-$self->start)), 25, ($x1+$scale*(3000-$self->start)), 30, $self->fgcolor);
#warn ($x1+$scale*(2000-$self->start));

#warn"Search Results:\n".Dumper(@feats);


#  warn"featseq is".Dumper($feats[0]->seq->seq);

#warn"Being called here".$self->parts;
#fasdfasd "try this";
#  $self->SUPER::draw(@_);
  
  
  my $xscale = $self->font->width;
  my $yscale = $height * $self->factory->get_option('species_spacing');	

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
#print"alignments:\n".Dumper(%alignments);  
  
  
  my $refspecies = $self->factory->get_option('reference');
  
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






  
  
  #exit;
  
  
  my $y = $y1;
  
  
  #for my $species (keys %alignments) {
  for my $species (@known_species,@unknown_species) {
    
    #make label
    if ($self->factory->get_option('label_species')) {
      if ($draw_cladeo_left) {
      	$gd->string($self->font, $start_x + $xoffset + $self->font->width, $y, $species, $self->fgcolor);
      } else {
      	my $write_pos = $bounds[0] - ($start_x + $xoffset) - $self->font->width * (length($species)+1);
      	$gd->string($self->font, $write_pos, $y, $species, $self->fgcolor);
      }
    }
    			;
    
#    next unless $alignments{$species};
    
    
#    my ($fx1,$fy1) = ($x1, $y);
#    my ($fx2,$fy2) = ($x1,$y+$height);
    
    
    #process the reference sequence differently
    if ($species eq $refspecies) {
      #draw DNA alignments if zoomed close enough
        my ($fx1,$fy1) = ($x1, $y+$height);
      	my ($fx2,$fy2) = ($x2,$y+2*$height);
      

      if ($self->dna_fits) {
	my $dna = eval { $self->feature->seq };
        $dna    = $dna->seq if ref($dna) and $dna->can('seq'); # to catch Bio::PrimarySeqI objects
        my $bg_color = $self->color('ref_color');
	$self->_draw_dna($gd,$dna,$fx1,$fy1,$fx2,$fy2, $self->fgcolor, $bg_color);
	#print "draw the source $species with DNA:<br>$dna";
      } else {
      	$gd->line($fx1, $fy1+$height/2, $fx2, $fy1+$height/2, $self->fgcolor);
      }
      
      $y += $yscale;
      next;
    }
    
#warn"species proc right now: $species";
    
    
    
    unless ($alignments{$species}) {
      $y += $yscale;
      next;
    }

    
    my @features = @{$alignments{$species}};

    
    
    for my $feat (@features) {
      my ($start, $stop, %attributes) = ($feat->start, $feat->stop, $feat->attributes);
      #warn"-- $start to $stop ; ".Dumper(%attributes);
      
      my ($fx1,$fy1) = ($x1 + ($start-$self->start)*$scale, $y+$height);
      my ($fx2,$fy2) = ($x1 + ($stop-$self->start)*$scale,$y+2*$height);
      
      
      
      
      #draw DNA alignments if zoomed close enough
      if ($self->dna_fits) {
      	my $gapstr = $attributes{'Gap'} || return;
      	my @gapstr = split " ", $gapstr;
      	my @gaps;
      	for my $gap (@gapstr) {
      	  my ($type, $num) = $gap =~ /^(.)(\d+)/; 
#warn"$gap has $type and $num";
      	  push @gaps, [$type, $num+0];
      	}
#warn"gap is:".Dumper(@gaps);#@gaps";
	my $dna = $feat->seq->seq;
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
	$self->draw_dna($gd,$dna,$fx1,$fy1,$fx2,$fy2,\@gaps);
      } else {
      	$gd->line($fx1, $fy1+$height/2, $fx2, $fy1+$height/2, $self->fgcolor);
      }
    }
    $y += $yscale;
  }
  
    $self->draw_cladeo($tree, $gd, $x1, $y1, $x2, $y2, $self->fgcolor,
  		     $xscale, $yscale, $xoffset, $yoffset, $start_x, $draw_cladeo_left);
  

return;



  if (my @parts = $self->parts) {

warn"central";
    # invoke sorter if user wants to sort always and we haven't already sorted
    # during bumping.
    @parts = $self->layout_sort(@parts) if !$self->bump && $self->option('always_sort');

    my $x = $left;
    my $y = $top  + $self->top + $self->pad_top;

    $self->draw_connectors($gd,$x,$y) if $connector && $connector ne 'none';

    my $last_x;
    for (my $i=0; $i<@parts; $i++) {
      # lie just a little bit to avoid lines overlapping and make the picture prettier
      my $fake_x = $x;
      $fake_x-- if defined $last_x && $parts[$i]->left - $last_x == 1;
      $parts[$i]->draw($gd,$fake_x,$y,$i,scalar(@parts));
      $last_x = $parts[$i]->right;
    }
  }

  else {  # no part
    $self->draw_connectors($gd,$left,$top)
      if $connector && $connector ne 'none'; # && $self->{level} == 0;
    $self->draw_component($gd,$left,$top,$partno,$total_parts) unless $self->feature_has_subparts;
  }

}

sub draw_component {
  my $self = shift;
  my $gd = shift;
  my ($x1,$y1,$x2,$y2) = $self->bounds(@_);
#warn"self is:\n".Data::Dumper::Dumper($self);
#warn"feature dump:\n".Data::Dumper::Dumper($self->feature->seq);
#warn"feature is:".$self->feature;
  my $dna        = eval { $self->feature->seq };
  $dna           = $dna->seq if ref($dna) and $dna->can('seq'); # to catch Bio::PrimarySeqI objects
  $dna or return;

  # workaround for my misreading of interface -- LS
  $dna = $dna->seq if ref($dna) && $dna->can('seq');

  if ($self->dna_fits) {
    $self->draw_dna($gd,$dna,$x1,$y1,$x2,$y2);
#$self->draw_dna($gd,$dna,$x1,$y1+10,$x2,$y2-2);   #can make it draw dna based on the xy coordinate and seq!
  } elsif ($self->do_gc) {
    $self->draw_gc_content($gd,$dna,$x1,$y1,$x2,$y2);
  }
}

sub draw_dna {
  my $self = shift;
#print"<pre>".Data::Dumper::Dumper($self)."</pre>";
  my ($gd,$dna,$x1,$y1,$x2,$y2, $gaps) = @_;
  my $pixels_per_base = $self->scale;
  
  my $fontcolor = $self->fgcolor;
  my $bg_color = $self->color('targ_color') || $self->fgcolor;
  my $errcolor  = $self->color('errcolor');# || $fgcolor;
  #print"colors are: $fontcolor, $bg_color $errcolor black:".$self->fgcolor;
  
  #missing gap data, weird
  unless ($gaps) {
    warn"no gap data for DNA sequence $dna";
    $self->_draw_dna($gd, $dna, $x1, $y1, $x2, $y2);
    return;
  }
  
#  warn"gaps are:\n".Dumper($gaps);
  for my $tuple (@$gaps) {
    my ($type, $num) = @$tuple;
    
    #warn"$type and $num";
    if ($type eq "M") {
      my $dnaseg = substr($dna, 0, $num);
      $self->_draw_dna($gd,$dnaseg, $x1, $y1, $x2, $y2, $fontcolor, $bg_color);
      $dna = substr($dna, $num);
      $x1 += $num * $pixels_per_base;
    } elsif ($type eq "D") {
      my $dnaseg = '-' x $num;
      $self->_draw_dna($gd, $dnaseg, $x1, $y1, $x2, $y2, $fontcolor); 
      $gd->rectangle($x1, $y1-1, $x1+$num * $pixels_per_base, $y2+1, $errcolor);
      $x1 += $num * $pixels_per_base;
    } elsif ($type eq "I") {
      $dna = substr($dna, $num);
      $gd->line($x1-2, $y1-2, $x1+2, $y1-2, $errcolor);
      $gd->line($x1, $y1-1, $x1, $y2+1, $errcolor);
      $gd->line($x1-2, $y2+1, $x1+2, $y2+1, $errcolor);
    }
    

  }
  
  
}

sub _draw_dna {
  my $self = shift;
#print"<pre>".Data::Dumper::Dumper($self)."</pre>";
  my ($gd,$dna,$x1,$y1,$x2,$y2, $color, $bg_color) = @_;
  
  my $pixels_per_base = $self->scale;
  my $feature = $self->feature;
  
  $gd->filledRectangle($x1+1, $y1, $x2, $y2, $bg_color);
  

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

#print "bases are:<br>\n<pre>".Data::Dumper::Dumper(@bases)."</pre>";
  #$color |= $self->fgcolor;
  $color = $self->fgcolor unless $color;
  $bg_color = 0 unless $bg_color;
  my $font  = $self->font;
  my $lineheight = $font->height;
  $y1 -= $lineheight/2 - 3;
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
    $gd->char($font,$x+2,$y1,$bases[$i],$color)                                   if $forward;
#$gd->char($font,$x+2,$y1+10,$complement{$bases[$i]},$color)                       if $forward;
    $gd->char($font,$x+2,$y1+($forward ? $lineheight:0),
	      $complement{$bases[$i]}||$bases[$i],$color)                         if $reverse;
  }
#$gd->rectangle($x1,$y1,$x2,$y2,$self->fgcolor);
}

sub draw_gc_content {
  my $self     = shift;
  my $gd       = shift;
  my $dna      = shift;
  my ($x1,$y1,$x2,$y2) = @_;

# get the options that tell us how to draw the GC content

  my $bin_size = length($dna) / ($self->option('gc_bins') || 100);
  $bin_size = 10 if $bin_size < 10;
  my $gc_window = $self->option('gc_window');
  if ($gc_window && $gc_window eq 'auto' or $gc_window <= length($dna)) {
    $gc_window = length($dna)/100;
  }

# Calculate the GC content...

  my @bins;
  my @datapoints;
  my $maxgc = -1000;
  my $mingc = +1000;
  if ($gc_window)
  {

# ...using a sliding window...
    for (my $i=$gc_window/2; $i <= length($dna) - $gc_window/2; $i++)
      {
	my $subseq = substr($dna, $i-$gc_window/2, $gc_window);
	my $gc = $subseq =~ tr/gcGC/gcGC/;
	my $content = $gc / $gc_window;
	push @datapoints, $content;
	$maxgc = $content if ($content > $maxgc);
	$mingc = $content if ($content < $mingc);
      }
    push @datapoints, 0.5 unless @datapoints;

    my $scale = $maxgc - $mingc;
    foreach (my $i; $i < @datapoints; $i++)
      {
	$datapoints[$i] = ($datapoints[$i] - $mingc) / $scale;
      }
    $maxgc = int($maxgc * 100);
    $mingc = int($mingc * 100);
  }
  else
  {

# ...or a fixed number of bins.

    for (my $i = 0; $i < length($dna) - $bin_size; $i+= $bin_size) {
      my $subseq  = substr($dna,$i,$bin_size);
      my $gc      = $subseq =~ tr/gcGC/gcGC/;
      my $content = $gc/$bin_size;
      $maxgc = $content if ($content > $maxgc);
      $mingc = $content if ($content < $mingc);
      push @bins,$content;
    }

    my $scale = $maxgc - $mingc;
    foreach (my $i; $i < @bins; $i++)
      {
	$bins[$i] = ($bins[$i] - $mingc) / $scale;
      }
    $maxgc = int($maxgc * 100);
    $mingc = int($mingc * 100);

  }

# Calculate values that will be used in the layout
  
  push @bins,0.5 unless @bins;  # avoid div by zero
  my $bin_width  = ($x2-$x1)/@bins;
  my $bin_height = $y2-$y1;
  my $fgcolor    = $self->fgcolor;
  my $bgcolor    = $self->factory->translate_color($self->panel->gridcolor);
  my $axiscolor  = $self->color('axis_color') || $fgcolor;

# Draw the axes
  my $fontwidth = $self->font->width;
  $gd->line($x1,  $y1,        $x1,  $y2,        $axiscolor);
  $gd->line($x2-2,$y1,        $x2-2,$y2,        $axiscolor);
  $gd->line($x1,  $y1,        $x1+3,$y1,        $axiscolor);
  $gd->line($x1,  $y2,        $x1+3,$y2,        $axiscolor);
  $gd->line($x1,  ($y2+$y1)/2,$x1+3,($y2+$y1)/2,$axiscolor);
  $gd->line($x2-4,$y1,        $x2-1, $y1,       $axiscolor);
  $gd->line($x2-4,$y2,        $x2-1, $y2,       $axiscolor);
  $gd->line($x2-4,($y2+$y1)/2,$x2-1,($y2+$y1)/2,$axiscolor);
  $gd->line($x1+5,$y2,        $x2-5,$y2,        $bgcolor);
  $gd->line($x1+5,($y2+$y1)/2,$x2-5,($y2+$y1)/2,$bgcolor);
  $gd->line($x1+5,$y1,        $x2-5,$y1,        $bgcolor);
  $gd->string($self->font,$x1-length('% gc')*$fontwidth,$y1,'% gc',$axiscolor) if $bin_height > $self->font->height*2;

# If we are using a sliding window, the GC graph will be scaled to use the full
# height of the glyph, so label the right vertical axis to show the scaling that# is in effect

  $gd->string($self->font,$x2+3,$y1,"${maxgc}%",$axiscolor) 
    if $bin_height > $self->font->height*2.5;
  $gd->string($self->font,$x2+3,$y2-$self->font->height,"${mingc}%",$axiscolor) 
    if $bin_height > $self->font->height*2.5;

# Draw the GC content graph itself

  if ($gc_window)
  {
    my $graphwidth = $x2 - $x1;
    my $scale = $graphwidth / @datapoints;
    my $gc_window_width = $gc_window/2 * $self->panel->scale;
    for (my $i = 1; $i < @datapoints; $i++)
      {
	my $x = $i + $gc_window_width;
	my $xlo = $x1 + ($x - 1) * $scale;
	my $xhi = $x1 + $x * $scale;
	last if $xhi >= $self->panel->right-$gc_window_width;
	my $y = $y2 - ($bin_height*$datapoints[$i]);
	$gd->line($xlo, $y2 - ($bin_height*$datapoints[$i-1]), 
		  $xhi, $y, 
		  $fgcolor);
      }
  }
  else
  {
    for (my $i = 0; $i < @bins; $i++) 
      {
	  my $bin_start  = $x1+$i*$bin_width;
	  my $bin_stop   = $bin_start + $bin_width;
	  my $y          = $y2 - ($bin_height*$bins[$i]);
	  $gd->line($bin_start,$y,
		    $bin_stop,$y,
		    $fgcolor);
	  $gd->line($bin_stop,$y,
		    $bin_stop,$y2 - ($bin_height*$bins[$i+1]),
		    $fgcolor)
	      if $i < @bins-1;
      }
  }
}

sub make_key_feature {
  my $self = shift;
  my @gatc = qw(g a t c);
  my $offset = $self->panel->offset;
  my $scale = 1/$self->scale;  # base pairs/pixel

  my $start = $offset+1;
  my $stop  = $offset+100*$scale;
  my $feature =
    Bio::Graphics::Feature->new(-start=> $start,
				-stop => $stop,
				-seq  => join('',map{$gatc[rand 4]} (1..500)),
				-name => $self->option('key'),
				-strand => '+1',
			       );
  $feature;
}

1;

__END__

=head1 NAME

Bio::Graphics::Glyph::dna - The "dna" glyph

=head1 SYNOPSIS

  See L<Bio::Graphics::Panel> and L<Bio::Graphics::Glyph>.

=head1 DESCRIPTION

This glyph draws DNA sequences.  At high magnifications, this glyph
will draw the actual base pairs of the sequence (both strands).  At
low magnifications, the glyph will plot the GC content.  By default,
the GC calculation will use non-overlapping bins, but this can be
changed by specifying the gc_window option, in which case, a 
sliding window calculation will be used.

For this glyph to work, the feature must return a DNA sequence string
in response to the dna() method.

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

  -do_gc      Whether to draw the GC      true
              graph at low mags

  -gc_window  Size of the sliding window  E<lt>noneE<gt>
  	      to use in the GC content 
	      calculation.  If this is 
	      not defined, non-
	      overlapping bins will be 
	      used. If this is set to
              "auto", then the glyph will
              choose a window equal to
              1% of the interval.

  -gc_bins    Fixed number of intervals   100
              to sample across the
              panel.

  -axis_color Color of the vertical axes  fgcolor
              in the GC content graph

  -strand      Show both forward and      auto
              reverse strand, one of
              "forward", "reverse",
              "both" or "auto".
              In "auto" mode,
              +1 strand features will
              show the plus strand
              -1 strand features will
              show the reverse complement
              and strandless features will
              show both

NOTE: -gc_window=E<gt>'auto' gives nice results and is recommended for
drawing GC content. The GC content axes draw slightly outside the
panel, so you may wish to add some extra padding on the right and
left.

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

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Sliding window GC calculation added by Peter Ashton E<lt>pda@sanger.ac.ukE<gt>.

Copyright (c) 2001 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut
