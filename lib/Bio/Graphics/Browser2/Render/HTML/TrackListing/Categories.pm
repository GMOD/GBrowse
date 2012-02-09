package Bio::Graphics::Browser2::Render::HTML::TrackListing::Categories;

use strict;
use warnings;
use base 'Bio::Graphics::Browser2::Render::HTML::TrackListing';

use Bio::Graphics::Browser2::Shellwords;
use CGI qw(:standard);
use Carp 'croak';
use constant DEBUG => 0;

sub render_track_listing {
    my $self = shift;

    my $settings = $self->settings;
    my $source   = $self->source;
    my $render   = $self->render;

    # read category table information
    my $category_table_labels = $self->category_table();
    my @labels = $render->potential_tracks;
    
    warn "favorites = {$settings->{show_favorites}} " if DEBUG;
    warn "active    = {$settings->{active_only}} "    if DEBUG;

    if( $settings->{show_favorites}){
	warn "favorites = @labels = $settings->{show_favorites}" if DEBUG;	
	@labels= grep {$settings->{favorites}{$_}} @labels;
    }

    if ($settings->{active_only}) {
	@labels = grep {$settings->{features}{$_}{visible}} @labels;
    }

    warn "label = @labels" if DEBUG;

    my ($filter_active,@hilite);
    if (my $filter = $render->track_filter_plugin) {
	my $tracks = @labels;
	eval {@labels    = $filter->filter_tracks(\@labels,$source)};
	warn $@ if $@;
	eval {@hilite    = $filter->hilite_terms};
	warn $@ if $@;
	$filter_active = @labels<$tracks;  # mark filter active if the filter has changed the track count
    }

    $filter_active++ if $settings->{active_only} || $settings->{show_favorites};

    # for unknown reasons, replacing the below loop with "map" 
    # causes lots of undefined variable warnings.
    my (%labels,%label_sort);
    for my $l (@labels) {
	$labels{$l}      = $self->render_one_track($l,\@hilite);
	$label_sort{$l}  = $render->label2key($l);
    }

    my @defaults   = grep {$settings->{features}{$_}{visible}        } @labels;
    
    # Sort the tracks into categories:
    # Overview tracks
    # Region tracks
    # Regular tracks (which may be further categorized by user)
    # Plugin tracks
    # External tracks
    my %track_groups;
    foreach (@labels) {
	my $category = $self->categorize_track($_);
	push @{$track_groups{$category}},$_;
    }

    autoEscape(0);

    # Get the list of all the categories needed.
    my %exclude = map {$_=>1} map {$render->translate($_)} qw(OVERVIEW REGION ANALYSIS EXTERNAL);

    (my $usertrack_cat = $render->translate('UPLOADED_TRACKS_CATEGORY')||'') =~ s/:.+$//;
    $usertrack_cat    ||= '';
    my @user_tracks    = grep {/^$usertrack_cat/i} keys %track_groups;
    $exclude{$_}++ foreach @user_tracks;

    my @user_keys = grep {!$exclude{$_}} sort keys %track_groups;

    my $all_on  = $render->translate('ALL_ON');
    my $all_off = $render->translate('ALL_OFF');

    my (%seenit,%section_contents);

    my @categories = (@user_keys,
		      $render->translate('OVERVIEW'),
		      $render->translate('REGION'),
		      $render->translate('ANALYSIS'),
	);
    unshift @categories,@user_tracks if @user_tracks;

    my $c_default = $source->category_default;

    my @titles; # for sorting
    
    # For each category, create the appropriately-nested node. "My Tracks" node positions comes from the track's config file.
    my $usertracks = $render->user_tracks;
    foreach my $category (@categories) {
	next if $seenit{$category}++;
	my $id = "${category}_section";
	my $category_title   = (split m/(?<!\\):/,$category)[-1];
	$category_title      =~ s!($_)!<span style="background-color:yellow">$1</span>!gi foreach @hilite;    

	my $file_id;

	if ($category eq $render->translate('REGION')  && !$render->setting('region segment')) {
	    next;
	}

	elsif  (exists $track_groups{$category}) {
	    my @track_labels = @{$track_groups{$category}};

	    $settings->{sk} ||= 'sorted'; # get rid of annoying warning

	    # if these tracks are in a grid, then don't sort them
	  BLOCK: {
	      no warnings;  # kill annoying uninit warnings under modperl
	      @track_labels = sort {lc ($label_sort{$a}) cmp lc ($label_sort{$b})} @track_labels
		  if $settings->{sk} eq 'sorted' && !defined $category_table_labels->{$category};
	    }

	    my $visible =  $filter_active                            ? 1
		         : exists $settings->{section_visible}{$id}  ? $settings->{section_visible}{$id} 
	                 : $c_default;
	    
	    my @entries = map {$labels{$_}} @track_labels;
	    my $table   = $self->tableize(\@entries,$category,\@track_labels);

	    # Get the content for this track.
	    my ($control,$section)=$render->toggle_section({on=>$visible,nodiv => 1},
							   $id,
							   b(ucfirst $category_title),
							   div({-style=>'padding-left:1em'},
							       span({-id=>$id},$table)));
	    $control .= '&nbsp;'.i({-class=>'nojs'},
				   checkbox(-id=>"${id}_a",-name=>"${id}_a",
					    -label=>$all_on,-onClick=>"gbCheck(this,1);"),
				   checkbox(-id=>"${id}_n",-name=>"${id}_n",
					    -label=>$all_off,-onClick=>"gbCheck(this,0);")
		)."&nbsp;".span({-class => "list",
				 -id => "${id}_list",
				 -style => "display: " . ($visible? "none" : "inline") . ";"},"")
		.br();
	    $section_contents{$category} = div({-class=>'track_section'},$control.$section);
	    
	}
	else {
	    next;
	}
    }

    autoEscape(1);
    my $slice_and_dice = $self->indent_categories(\%section_contents,\@categories,$filter_active);

    my $expand_all = '&nbsp;' .img({-class  =>  'clickable expand_all range_expand',
				    -src    => $source->globals->button_url .'/open_open.png',
				    -onClick => "gbExpandAll(this,'range',event)"});
    return join( "\n",
		 start_form(-name=>'trackform',
			    -id=>'trackform'),
		 div({-class=>'searchbody',-id=> 'range', -style=>'padding-left:1em'},$expand_all,br(),$slice_and_dice),
		 end_form);
}

sub tableize {
    my $self = shift;
    my ($keys,$category,$labels) = @_;
    
    my $categorytable = $self->category_table();
    my (@row_labels,@column_labels);
    if (defined $category and exists $categorytable->{$category} ) {
	@row_labels    = @{$categorytable->{$category}{col_labels}};
	@column_labels = @{$categorytable->{$category}{row_labels}};
	return $self->render->tableize($keys,undef,$labels,\@row_labels,\@column_labels);
    } else {
	return $self->render->tableize($keys,undef,$labels);
    }

}

sub categorize_track {
    my $self   = shift;
    my $label  = shift;

    my $render      = $self->render;
    my $user_labels = $render->get_usertrack_labels;

    return $render->translate('OVERVIEW') if $label =~ /:overview$/;
    return $render->translate('REGION')   if $label =~ /:region$/;
    return $render->translate('EXTERNAL') if $label =~ /^(http|ftp|file):/;
    return $render->translate('ANALYSIS') if $label =~ /^plugin:/;

    if ($user_labels->{$label}) {
	my $cat = $render->user_tracks->is_mine($user_labels->{$label}) 
	    ? $render->translate('UPLOADED_TRACKS_CATEGORY')
	    : $render->translate('SHARED_WITH_ME_CATEGORY');
	return "$cat:".$render->user_tracks->title($user_labels->{$label});
    }
    
    my $category;
    for my $l ($render->language->language) {
	$category      ||= $render->setting($label=>"category:$l");
    }
    $category        ||= $render->setting($label => 'category');
    $category        ||= '';  # prevent uninit variable warnings
    $category         =~ s/^["']//;  # get rid of leading quotes
    $category         =~ s/["']$//;  # get rid of trailing quotes
    return $category ||= $render->translate('GENERAL');
}

# Category Table - This returns the hash of the category table.
sub category_table {
    my $self   = shift;
    my $source = $self->source;

    my $tabledata  = $source->setting('category tables');
    my @tabledata  = shellwords($tabledata||'');
    my %categorytable=();
    while (@tabledata) {
	    my $category  =  shift(@tabledata);
	    my $rows      =  shift(@tabledata);
	    my @rows      =  split(/\s+/,$rows);
	    my $cols      =  shift(@tabledata);
	    my @cols      =  split(/\s+/,$cols);
	    $categorytable{$category}{row_labels}=\@rows;
	    $categorytable{$category}{col_labels}=\@cols;
    }
    
    return \%categorytable; 
}

sub indent_categories {
    my $self = shift;
    my ($contents,$categories,$force_open) = @_;

    my $category_hash = {};
    my %sort_order;
    my $sort_index = 0;

    for my $category (@$categories) {
	my $cont   = $contents->{$category} || '';
	
	my @parts  = map {s/\\//g; $_} split m/(?<!\\):/,$category;
	$sort_order{$_} = $sort_index++ foreach @parts;

	my $i      = $category_hash;

	# we need to add phony __next__ and __contents__ keys to avoid
	# the case in which the track sections are placed at different
	# levels of the tree, for instance 
	# "category=level1:level2" and "category=level1"
	for my $index (0..$#parts) {
	    $i = $i->{__next__}{$parts[$index]} ||= {};
	    $i->{__contents__}                    = $cont if $index == $#parts;
	}
    }
    my $i               = 1;
    my $nested_sections =  $self->nest_toggles($category_hash,\%sort_order,$force_open);
}

# Nest Toggles - This turns the nested category/subcategory hashes into a prettily-indented tracks table.
sub nest_toggles {
    my $self         = shift;
    my ($hash,$sort,$force_open) = @_;

    my $settings = $self->settings;
    my $source   = $self->source;
    my $render   = $self->render;

    my $result = '';
    my $default = $source->category_default;

    for my $key (sort { 
	           ($sort->{$a}||0)<=>($sort->{$b}||0) || $a cmp $b
		      }  keys %$hash) {
	if ($key eq '__contents__') {
	    $result .= $hash->{$key}."\n";
	} elsif ($key eq '__next__') {
	    $result .= $self->nest_toggles($hash->{$key},$sort,$force_open);
	} elsif ($hash->{$key}{__next__}) {
	    my $id =  "${key}_section";
	    my $ea = '&nbsp;' . img({-class  =>  "clickable expand_all ${id}_expand",
				     -src    => $source->globals->button_url .'/open_open.png',
				     -onClick => "gbExpandAll(this,'$id',event)"});
	    $settings->{section_visible}{$id} = $default unless exists $settings->{section_visible}{$id};
	    $result .= $render->toggle_section({on=>$force_open||$settings->{section_visible}{$id}},
					       $id,
					       b($key).
					       $ea.
					       span({-class   => "list",
						     -id      => "${id}_list"},''),
					       div({-style=>'margin-left:1.5em;margin-right:1em'},
						   $self->nest_toggles($hash->{$key},$sort,$force_open)));
	} else {
	    $result .= $self->nest_toggles($hash->{$key},$sort,$force_open);
	}
    }
    return $result;
}

1;
