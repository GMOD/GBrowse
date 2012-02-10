package Bio::Graphics::Browser2::SubtrackTable;
use strict;
use warnings;
use Carp 'croak';
use Bio::SeqFeatureI;
use Bio::Graphics::Browser2::Shellwords;
use CGI ':standard';

sub new {
    my $class = shift;
    my %args  = @_;

    # List of dimensions with instructions on how to pull them out of features.
    # [['Antibody','name'],['Confirmed','has_tag','confirmed'],['Stage','tag_value','stage']...]
    my $selectors = $args{-columns} or croak "-columns argument required";  

    # List of valid combinations of features.
    # [['H3K4me3' ,1,'E0-4h',23],['H3K4me3', 1, 'E4-48', 26],....]
    my $rows      = $args{-rows}    or croak "-rows argument required";

    # track label.
    my $label     = $args{-label}   or croak "-label argument required";

    # track key
    my $key       = $args{-key};

    # human-readable versions of feature attributes
    my $label_aliases   = $args{-aliases};

    return bless {
	selectors => $selectors,
	rows      => $rows,
	label     => $label,
	key       => $key,
	aliases   => $label_aliases,
	comment   => $args{-comment},
    },ref $class || $class;
}

sub track_label       { shift->{label} }
sub track_key         { shift->{key}   }
sub track_comment     { shift->{comment} || ''}
sub subtrack_aliases  { shift->{aliases} || {}}

sub selectors {
    my $self = shift;
    return @{$self->{selectors}};
}

sub rows {
    my $self = shift;
    return $self->{rows};
}

# turn the unparsed rows into parsed elements
# data structure = id => { index     => #sort position,
#                          selected  => boolean,
#                          fields    => [field1,field2,field3...] }
sub elements {
    my $self = shift;
    return $self->{_elements} if exists $self->{_elements};
    my $index = 1;  # not zero
    my (%elements,$at_least_one_selected);

    my $rows  = $self->rows;
    for my $r (@$rows) {
	my @data   = @$r;
	my @fields      = grep {!/^[=*:]/}        @data;
	my ($id)        = grep {length} map {/^=([\d\w]+)/ && $1 } @data;
	my ($label)     = grep {length} map {/^:(.+)/      && $1 } @data;
	my ($selected)  = grep {$_ eq '*'}       @data;
	$id           ||= join ';',map {/^~(.+)/ ? $1 : $_} @fields;
	$elements{$id} = { index    => $index++,
			   selected => $selected,
			   label    => $label || '',
			   fields   => \@fields };
	$at_least_one_selected++ if $selected;
    }
    unless ($at_least_one_selected) {
	$elements{$_}{selected}++ foreach keys %elements;
    }
	
    return $self->{_elements}=\%elements;
}

# flag indicates that subtracks are overlapping
sub overlap {
    my $self = shift;
    my $d = $self->{_overlap};
    $self->{_overlap} = shift if @_;
    return $d;
}

# return two element list consisting of # selected/# total
sub counts {
    my $self = shift;
    my $elements    = $self->elements;
    my $total       = keys %$elements;
    my $selected    = grep {$elements->{$_}{selected}} keys %$elements;
    return ($selected,$total);
}

sub set_selected {
    my $self          = shift;
    my $selected      = shift;

    my $elements    = $self->elements;
    my %all_ids     = map {$_=>1} keys %$elements;
    my @ordered_ids = sort {$elements->{$a}{index}<=>$elements->{$b}{index}} keys %all_ids;

    my $idx = 0;
    my %seenit;
    
    foreach my $el (keys %$elements) {
     map{if($el =~ /\;\d+$/ && $selected->[$_] eq $`){$selected->[$_] = $el}} (0..@$selected-1);
    }

    # reorder the elements that are named on the list
    for my $e (@$selected) {
	next unless $elements->{$e};  # uh oh
	$elements->{$e}{index} = $idx++;
	$elements->{$e}{selected} = 1;
	$seenit{$e}++;
    }

    # everything else keeps the default order from the config file
    for my $e (@ordered_ids) {
	next if $seenit{$e};
	$elements->{$e}{index}    = $idx++;
	$elements->{$e}{selected} = 0;
    }
}

sub selection_table {
    my $self   = shift;
    my $render = shift;

    my $label     = $self->track_label;
    my $key       = $self->track_key || $label;
    my $aliases   = $self->subtrack_aliases;
    my @selectors = $self->selectors;
    my $elements  = $self->elements;
    my $overlap   = $self->overlap;
    my (@popups,@sort_type,@boolean);

    my $tbody_id = "${label}_subtrack_id";

    # create the filter popups
    # by getting possible values for each selector
    for (my $i=0;$i<@selectors;$i++) {
	my %seenit;
	my @v       = sort grep {!$seenit{$_}++} map {$elements->{$_}{fields}[$i]} keys %$elements;

	my $is_numeric = 1;
	for my $v (@v) {
	    $is_numeric &&= $v =~ /^[\d+.Ee-]$/;
	    $v=~ s/^\~//;
	}
	my $is_boolean = $selectors[$i][1] eq 'has_tag';
	if ($is_boolean) {
	    @v = map {$_ ? 'Yes' : 'No'} @v;
	}

	unshift @v,'';
	@v = map { $aliases->{$_}||$_ } @v;

	$popups[$i] = popup_menu(-onChange => 'Table.filter(this,this)',
				 -name     => "$selectors[$i][0]-select",
				 -values   => \@v,
				 -labels   => {''=>'All'});

	$boolean[$i]   = $is_boolean;

	$sort_type[$i] = $is_numeric && !$is_boolean ? 'table-sortable:numeric'
	                                             : 'table-sortable:default';
	
    }
    my $comment      = $self->track_comment;
    my $instructions = $render->tr('SUBTRACK_INSTRUCTIONS');

    # it is possible for there to be more fields in the data table than among
    # the selectors, so we create additional dummy columns in the header
    my $cols = 0;
    for (keys %$elements) {
        my $c = @{$elements->{$_}{fields}};
        $cols = $c if $cols < $c;
    }
    my $extra = $cols - @selectors;
    $extra    = 0 if $extra < 0;
    my @extra = ('&nbsp;') x $extra;

    my @table_rows;
    push @table_rows,TR(td({-class=>'datatitle',-colspan=>$#selectors+$extra+2},b($comment)))
        if $comment;
    push @table_rows,TR(td({-class=>'datatitle',-colspan=>$#selectors+$extra+2},i($instructions)))
        if $instructions;
    push @table_rows,TR(th({-colspan=>$#selectors+$extra+2},"<i>$key</i> Subtracks"));
    push @table_rows,TR(     th({-class=>'table-sortable:numericdesc'},'Select'),
                             (map {th({-class=>"filterable $sort_type[$_]"},$selectors[$_][0])} (0..$#selectors)),
                                  th(\@extra)
                             );

    push @table_rows,TR(th(span({-class => 'clickable',
                                 -onClick => 'Table.checkAll(this,false)'},'All off'),
                           span({-class   => 'clickable',
                                 -onClick => 'Table.checkAll(this,true)'}, 'All on')),
                        th(\@popups),
                        th(\@extra)
                        );

    my $thead = thead(@table_rows);

    @table_rows = ();

    for my $e (sort {$elements->{$a}{index}<=>$elements->{$b}{index}} keys %$elements) {
	my $r = $elements->{$e}{fields};
	my @row_class   = $elements->{$e}{selected} ? (-class=> "selected") 
	                                            : (-class=>'unselected');
	push @table_rows,
	       TR({@row_class,-id=>"track_select_$e"},
		   th(checkbox( -value    => +1,
				-class   => 'rowSelect',
				-checked => $elements->{$e}{selected},
				-onChange=> 'Table.checkSelect(this)')
		  ),
		   td([
		       map {$boolean[$_]             ? $r->[$_] ?'Yes':'No'
			    : $r->[$_] =~ /^~(.+)/   ? $1
			    : $aliases->{$r->[$_]}||$r->[$_]
		       }(0..$#$r)
		]));
    }
    my $tbody = tbody({-id=>$tbody_id,-class=>'sortable'},@table_rows);

    my $tbottom = div(
	checkbox(-id=>'overlap_track',
		 -label    => $render->tr('OVERLAP'),
		 -checked  => $overlap,
	),
	button(-name=>$render->tr('Cancel'),
	       -onClick => 'Balloon.prototype.hideTooltip(1)'),
	button(-name    => $render->tr('Change'),
	       -onclick => "Table.sendTableState('$label',\$('$tbody_id'));Controller.toggle_subtrack_overlapping('$label',\$('overlap_track').checked);ShowHideTrack('$label',true);Controller.rerender_track('$label',false,true);Controller.update_sections(new Array(track_listing_id));Balloon.prototype.hideTooltip(1);"));


    my $table_id = "${label}_subtrack_table";

    my $script = script({-type=>'text/javascript'},<<END);
Position.includeScrollOffsets = true;
Sortable.create('$tbody_id',
                {tag:     'tr',
                 scroll:   'subtrack_table_scroller',
		 onUpdate:function(a){Table.stripe(a,'alternate')}
                });
Table.auto();
END

    my @style   = keys %$elements > 10 ? (-style => 'height:300px') : ();

    my $width = (1+@selectors) *150;
    $width    = 600 if $width > 600;

    return div({-class=>'subtrack_table',
		-id=>'subtrack_table_scroller'},
	    table({-width=>'98%',
		   -class => "subtrack-table table-autosort table-autostripe table-stripeclass:alternate",
		   -style => CGI->user_agent =~ /KHTML/ ? "border-collapse:collapse" 
		                                        : "border-collapse:separate",
                   -id    => $table_id,
		   @style},
		  $thead,$tbody)).$tbottom.$script;
}

sub track_args {
    my $self = shift;
    return $self->overlap ? (-bump => 'overlap',-opacity=>0.25) : ();
}

# summarize rows that are active vs inactive
sub preview_table {
    my $self   = shift;
    my $render = shift;

    my @selectors = $self->selectors;
    my @boolean   = map {$selectors[$_][1] eq 'has_tag'} (0..$#selectors);
    my $elements  = $self->elements;
 
    my $key       = $self->track_key || $self->track_label;
    my $aliases   = $self->subtrack_aliases;
    my @rows = TR(th({-class=>'settingstitle',-colspan=>$#selectors+2},"<i>$key</i> Subtracks"));
    push @rows,TR(th([map {$_->[0]}@selectors]));

    for my $e (sort {$elements->{$a}{index}<=>$elements->{$b}{index}} keys %$elements) {
	my $selected = $elements->{$e}{selected};
	my $style    = !$selected ? {-style=>'color:lightgray'}:{};
	my $r        = $elements->{$e}{fields};
	push @rows,TR($style,
		      td(
			 [
			  map {$boolean[$_]                 ? $r->[$_] ?'Yes':'No'
				   : $r->[$_] =~ /^~(.+)/   ? $1
				   : $aliases->{$r->[$_]}||$r->[$_]
			  }(0..$#$r)
			 ]));
    }
    my $caption = $render->tr('SUBTRACKS_SHOWN');

    my @style   = keys %$elements > 10 ? (-style => 'height:300px') : ();
    push @style,@selectors < 2 ? (-style => 'max-width:100px') : ();

    return p($caption).
	div(table({-class=>'subtrack-table',@style},tbody(@rows)));
}

sub feature_to_id_sub {
    my $self = shift;
    return $self->{_feature2id} if exists $self->{_feature2id};

    my @selectors = $self->selectors();
    my $elements  = $self->elements;

    my $sub = "sub {no warnings; my \$f = shift;\nmy \$found;\n";
    $sub   .= "if (\$f->type eq 'group') { \n";
    $sub   .= "\$f = (\$f->get_SeqFeatures)[0] || return \$f->primary_id; }\n";

    for my $e (sort {$elements->{$a}{index} <=> $elements->{$b}{index}} keys %$elements) {
	my $r = $elements->{$e}{fields};

	$sub .= "\$found=1;\n";
	for my $i (0..$#selectors) {
	    my ($name,$op,$operand) = @{$selectors[$i]};
	    my $val               = $r->[$i];
	    if ($op eq 'has_tag') {
		my $bang = $val ? '' : '!';
		$sub .= "\$found &&= $bang\$f->has_tag('$operand');\n";
	    } else {
		my $operation = $val eq ''                                ? undef
		               : $val =~ /^~(.+)/                         ? "=~ m[$1]i" 
                               : $val =~ /^[+-]?\d*(\.\d+)?([eE]-?\d+)?$/ ? "== $val"
                               : "eq '$val'";
		if (!defined $operation) {
		    $sub .= "\$found &&= length((\$f->get_tag_values('$operand'))[0])==0;\n";
		} elsif ($op eq 'tag_value') {
		    $sub .= "\$found &&= \$f->has_tag('$operand');\n";
		    $sub .= "\$found &&= (\$f->get_tag_values('$operand'))[0] $operation;\n";
		} else {
		    $sub .= "\$found &&= \$f->$op() $operation;\n";
		}
	    }
	}
	$sub .= "return '$e' if \$found;\n";
    }
    $sub .= "return;\n}";
    my $as =  eval $sub;
    warn "subtrack filter failed: ",$@ unless $as;
    return $self->{_feature2id} = $as;
}

sub id2label {
    my $self = shift;
    my $element_id = shift;
    my $e = $self->elements;
    return $e->{$element_id}{label} || $element_id;
}

sub selected_ids {
    my $self = shift;
    my $elements = $self->elements;
    my %selected = map {$_=>$elements->{$_}{index}} 
                   grep {$elements->{$_}{selected}} keys %$elements;
    return wantarray ? keys %selected : \%selected;
}


sub filter_feature_sub {
    my $self = shift;
    my $selected = $self->selected_ids;
    my $to_id    = $self->feature_to_id_sub or return;
    return sub {
	my $feature = shift;
	my $id      = $to_id->($feature);
	return      unless defined $id;
	return      exists $selected->{$id};
    }
}

sub sort_feature_sub {
    my $self = shift;
    my $selected  = $self->selected_ids;
    my $transform = $self->feature_to_id_sub or return;
    return sub ($$) {
	my ($g1,$g2) = @_;
	my ($f1,$f2) = ($g1->feature,$g2->feature);
	return $selected->{$transform->($f1)} <=> $selected->{$transform->($f2)};
    };
}

sub infer_settings_from_source {
    my $package          = shift;
    my ($source,$label)  = @_;

    my $bump = $source->setting($label=>'bump');

# use this to test prototype overlap functionality
#    return if defined $bump && ($bump eq 'overlap' || $bump == 0);

    my (@dimensions,@rows);
  TRY: {

      if (my @facets = shellwords $source->setting($label=>'subtrack facets')) {
	  @dimensions = map {[$_,'tag_value',$_]} @facets;
	  @rows       = $package->get_facet_values($source,$label,@facets);
	  last TRY;
      }
      
      if ((my $d = $source->setting($label => 'subtrack select')) &&
	  (my $r = $source->setting($label => 'subtrack table'))) {
	  @dimensions     = map {[shellwords($_)]}  split ';',$d;
	  @rows           = map {[shellwords($_)]}  split ';',$r;
	last TRY;  
      }
      
      if (my $s = $source->setting($label=>'select')) {
	  my %defaults = map {$_=>1} shellwords($source->setting($label=>'select default'));
	  
	  if ($s =~ /;/) { # new syntax
	      my @lines = split ';',$s;
	      my ($method) = shellwords (shift @lines);
	      push @dimensions,[ucfirst($method),$method];
	      for my $l (@lines) {
		  my @values = shellwords($l);
		  splice(@values,1,1,()) if @values > 1 && $values[1] !~ /^=/; # sorry
		  push @values,'*' if $defaults{$values[0]};
		  $values[0] = "~$values[0]"; # always a regexp match for legacy reasons
		  push @rows,\@values;
	      }
	  } else {
	      my ($method,@values) = grep {!/^#/} shellwords $source->setting($label=>'select') 
		  or last TRY;
	      foreach    (@values) {s/#.+$//}  # get rid of comments
	      push @dimensions,[ucfirst($method),$method];
	      push @rows,map {["~$_"]} @values;
	  }
	  last TRY;
      }

      my (undef,$adaptor) = $source->db_settings($label);

      my $db   = $source->open_database($label) or last TRY;
      $db->can('metadata') or last TRY;
      my $meta = $db->metadata;

      # get all the tags that are consistently used
      my %tags;
      my @keys       = map {keys %$_} values %$meta;
      for my $k (@keys) {
	  $tags{$k}++;
      }
      my $count = keys %$meta;
      
      my @tags    = sort grep {defined $_ && $_ ne 'dbid' && $tags{$_}==$count} keys %tags;
      @dimensions = map {[ucfirst($_),'tag_value',$_]} @tags;
      @rows       = $package->get_facet_values($source,$label,@tags);
      
    }

    return unless @dimensions && @rows;
    
    # apply "facet labels" setting on top of dimensions
    if (my %facet_dimensions = shellwords($source->setting(general=>'facet labels'))) {
	for my $d (@dimensions) {
	    $d->[0] = $facet_dimensions{$d->[0]} || $d->[0];
	}
    }
    
    my %facet_values = shellwords($source->setting(general=>'facet values'));
    my $aliases     = $source->setting($label=>'subtrack select labels') 
	||$source->setting($label=>'subtrack labels') ; # deprecated API
    my %aliases    = map {shellwords($_)} split ';',$aliases if $aliases;
    %aliases       = (%facet_values,%aliases);
    return (\@dimensions,\@rows,\%aliases);
}

sub get_facet_values {
    my $self = shift;
    my ($source,$label,@facets) = @_;

    my @types       = shellwords $source->setting($label=>'feature');
    my $match       = join '|',map {$_="$_:?" unless /:/} @types;

    my @rows;
    my (undef,$adaptor) = $source->db_settings($label);
    my $db   = $source->open_database($label) or return;
    my $meta = eval {$db->metadata}           or return;

    for my $id (sort {$a<=>$b} keys %$meta) {
	my $method = $meta->{$id}{method} || eval {$db->feature_type} || 'feature';
	my $source = $meta->{$id}{source} || '';
	my $type = $meta->{$id}{type} || "$method:$source";

	next unless $type =~ /$match/;
	my @vals = map {$_||''} @{$meta->{$id}}{@facets};
	push @vals,"=$id";
	push @rows,\@vals;
    }

    push @{$rows[0]},'*';
    return @rows;
}

1;

