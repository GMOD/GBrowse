package Bio::Graphics::Browser2::Render::TrackConfig;
use strict;
use warnings;
use CGI qw(:standard);
use Bio::Graphics::Browser2::Shellwords 'shellwords';
use constant MIN=>0;
use constant MAX=>999999999;

sub new {
    my $class  = shift;
    my $render = shift;
    return bless {render=>$render},ref $class || $class;
}

sub render { shift->{render} }

sub config_dialog {
    my $self               = shift;
    my ($label,$revert_to_defaults) = @_;
    my $render = $self->render;

    my $state       = $render->state();
    my $data_source = $render->data_source();
    my $seg      = $label =~ /:overview$/ ? $render->thin_whole_segment
	          :$label =~ /:region$/   ? $render->thin_region_segment
                  :$render->thin_segment;
    my $length = eval{$seg->length}||0;

    eval 'require Bio::Graphics::Browser2::OptionPick; 1'
        unless Bio::Graphics::Browser2::OptionPick->can('new');

    my $picker = Bio::Graphics::Browser2::OptionPick->new($render);

    # summary options
    my $can_summarize = $data_source->can_summarize($label);
    my $summary_mode  = $data_source->show_summary($label,$length);

    my $slabel           = $summary_mode ? $label : $data_source->semantic_label($label,$length);

    if ($revert_to_defaults) {
	$state->{features}{$label}{summary_override}  = {} if $summary_mode;
	$state->{features}{$label}{semantic_override} = {} unless $summary_mode;
	delete $state->{features}{$label}{summary_mode_len};
    }

    my $scaled_length  = $length/$render->details_mult;
    my $semantic_override = $render->find_override_region($state->{features}{$label}{semantic_override},$length);
    $semantic_override   ||= 0;

    my ($semantic_level)   = $slabel =~ /(\d+)$/;
    $semantic_level      ||= 0;
    my @level              = map {
	scalar $render->data_source->unit_label($_/$render->details_mult)
    } split ':',($semantic_override || $semantic_level);
    my $level              = join '..',@level;

    my $key = $render->label2key($label);
    $key .= $summary_mode      ? " (".$render->translate('FEATURE_SUMMARY').')'
           :$level             ? " ($level)"
	   :'';

    my $override = $summary_mode 
	? $state->{features}{$label}{summary_override}                      ||= {}
        : $state->{features}{$label}{semantic_override}{$semantic_override} ||= {};

    my $return_html = start_html();

    my $showing = $render->data_source->unit_label($scaled_length);
    my $title   = div({-class=>'config-title'},$key,br(),div({-style=>'font-size:9pt'},$render->translate('Currently_Showing',$showing)));
    my $dynamic = $render->translate('DYNAMIC_VALUE');

    my $height        = $self->setting( $label => 'height' ,        $length, $summary_mode)    || 10;
    my $width         = $self->setting( $label => 'linewidth',      $length, $summary_mode )   || 1;
    my $glyph         = $self->setting( $label => 'glyph',          $length, $summary_mode )   || 'box';
    my $stranded      = $self->setting( $label => 'stranded',       $length, $summary_mode);
    my $variance_band = $self->setting( $label => 'variance_band',  $length, $summary_mode);
    my $color_series  = $self->setting( $label => 'color_series',   $length, $summary_mode);
    my $limit         = $self->setting( $label => 'feature_limit' , $length, $summary_mode)    || 0;
    my $summary_length= $self->setting( $label => 'show summary' , $length, $summary_mode) || 0;
    my $opacity       = $override->{'opacity'} || $self->setting($label => 'opacity',$length,$summary_mode) || 0.3;

    # options for wiggle & xy plots
    my $min_score= $self->setting( $label => 'min_score' ,     $length, $summary_mode);
    my $max_score= $self->setting( $label => 'max_score' ,     $length, $summary_mode);
    $min_score = -1 unless defined $min_score;
    $max_score = +1 unless defined $max_score;
    my $autoscale = $self->setting( $label => 'autoscale' ,     $length, $summary_mode);
    $autoscale  ||= 'local';

    my $sd_fold   = $self->setting( $label => 'z_score_bound' ,     $length, $summary_mode);
    $sd_fold    ||= 8;

    my $bicolor_pivot = $self->setting( $label => 'bicolor_pivot' ,  $length, $summary_mode);
    my $graph_type    = $self->setting( $label => 'graph_type' ,     $length, $summary_mode);
    my $glyph_subtype = $self->setting( $label => 'glyph_subtype' ,  $length, $summary_mode);

    # options for wiggle_whiskers
    my $max_color   = $self->setting( $label => 'max_color' ,   $length, $summary_mode);
    my $mean_color  = $self->setting( $label => 'mean_color' ,  $length, $summary_mode);
    my $stdev_color = $self->setting( $label => 'stdev_color' , $length, $summary_mode);

    # packing images
    my $buttons     = $data_source->globals->button_url;
    my $red_peaks   = "$buttons/red_peaks.png";
    my $blue_peaks  = "$buttons/blue_peaks.png";
    my $opacity_thumb  = "$buttons/opacity_thumb.png";

    my @glyph_select = shellwords(
	    $self->setting( $label => 'glyph select', $length, $summary_mode )
	);
    unshift @glyph_select,$dynamic if ref $data_source->fallback_setting($label=>'glyph') eq 'CODE';

    my $db           = $data_source->open_database($label,$length);
    my $quantitative = $glyph =~ /wiggle|vista|xy|density/ || ref($db) =~ /bigwig/i;
    my $can_whisker  = $quantitative && ref($db) =~ /bigwig/i;
    my $vista        = $glyph =~ /vista/;

    unless (@glyph_select) { # reasonable defaults
	@glyph_select = $can_whisker  ? qw(wiggle_xyplot wiggle_density wiggle_whiskers)
		       :$vista        ? 'vista_plot'
                       :$quantitative ? qw(wiggle_xyplot wiggle_density)
	                              : qw(arrow anchored_arrow box crossbox dashed_line diamond 
                                         dna dot dumbbell ellipse gene line primers saw_teeth segments 
                                         span site transcript triangle
                                         two_bolts wave);
    }

    my $auto_packing_label = $quantitative ? $render->translate('Expand_Label') : $render->translate('Auto');
    my %glyphs       = map { $_ => 1 } ( $glyph, @glyph_select );
    my @all_glyphs   = sort keys %glyphs;
    my $g = $override->{'glyph'} || $glyph;

    my $url = url( -absolute => 1, -path => 1 );
    my $mode = $summary_mode ? 'summary' : 'normal';
    my $reset_js = <<END;
new Ajax.Request('$url',
                  { method: 'get',
                    asynchronous: false,
                    parameters: 'action=configure_track&track=$label&track_defaults=1;mode=$mode',
                    onSuccess: function(t) { document.getElementById('contents').innerHTML=t.responseText;
					     t.responseText.evalScripts();
		                           },
                    onFailure: function(t) { alert('AJAX Failure! '+t.statusText)}
                  }
                );
END

    my $self_url  = url( -absolute => 1, -path => 1 );
    my $form_name = 'track_config_form';
    my $form      = start_form(
        -name => $form_name,
        -id   => $form_name,
    );

    # NOTE: the -class option determines which form elements are shown for
    # which track types. See htdocs/js/track_config.js
    my @rows;
    push @rows, TR({-class=>'general'},
		   td( {-colspan => 2}, $title));

    push @rows,TR( {-class => 'general',
		    -id    => 'packing'},
		   th( { -align => 'right' }, $render->translate('Packing') ),
		   td( popup_menu(
			   -name     => 'format_option',
			   -id       => 'format_option',
			   -values   => ($quantitative ? [0,4] : [ 0..4 ]),
			   -override => 1,
			   -default  => $state->{features}{$label}{options},
			   -labels   => {
			       0 => $auto_packing_label,
			       1 => $render->translate('Compact'),
			       2 => $render->translate('Expand'),
			       3 => $render->translate('Expand_Label'),
			       4 => $render->translate('Overlap'),
			   }
		       )
		   )
        );

    push @rows,TR( {-class => 'general',
		    -id    => 'opacity'},
		   th( {-align => 'right' }, 'Opacity'),
		   td( input({-type  => 'text',
			      -name => 'conf_opacity',
			      -id    => 'opacity_value',
			      -style => "display:inline-block;position:relative;top:-4",
			      -value => '0.00',
			      -size  => 2,
			      -maxlength => 4}),
		       div({-id=>'opacity_box',
			    -style => 'display:inline-block;position:relative;background:beige;width:100px;height:16px;border:inset 1px',
			   },
			   img({-id=>'opacity_thumb',
				-style=>'position:absolute;left:0',
				-src  => $opacity_thumb})),
		       div({-style=>'display:inline-block;position:relative;width:20px;height:20px'},
			   img({-class=>'opacity',
				-src  => $red_peaks,
				-style => 'position:absolute;left:2px;top:0px'}),
			   img({-class=>'opacity',
				-src  => $blue_peaks,
				-style => 'position:absolute;left:0px;top:5px'}),
		       )));

    push @rows,TR( {-class=>'general'},
		   th( { -align => 'right' }, $render->translate('GLYPH') ),
		   td($picker->popup_menu(
			  -name    => 'conf_glyph',
			  -values  => \@all_glyphs,
			  -default => ref $glyph eq 'CODE' ? $dynamic : $glyph,
			  -current => $override->{'glyph'},
			  -scripts => {-id=>'glyph_picker_id',-onChange => 'track_configure.glyph_select($(\'config_table\'),this)'}
		      )
		   )
	);

    for my $glyph (@all_glyphs) {
	my $class = "Bio\:\:Graphics\:\:Glyph\:\:$glyph";
	eval "require $class" unless $class->can('new');
	if (my $subtypes = eval{$class->options->{glyph_subtype}}) {
	    my $options  = $subtypes->[0];
	    next unless ref $options eq 'ARRAY';
	    push @rows,(TR {-class => $glyph,
			    -id    => "conf_${glyph}_subtype"},
			th({-align => 'right'}, $glyph,$render->tr('Subtype')),
			td($picker->popup_menu(
			       -values   => $options,
			       -name     => "conf_${glyph}_subtype",
			       -override => 1,
			       -default => ref $glyph_subtype eq 'CODE' ? $dynamic : $glyph_subtype,
			       -scripts => { -id => "conf_${glyph}_subtype_id",
					     -onChange => 'track_configure.glyph_select($(\'config_table\'),$(\'glyph_picker_id\'))'},
			       -current  => $override->{'glyph_subtype'})));
	}
	if (my $subgraphs = eval{$class->options->{graph_type}}) {
	    my $options  = $subgraphs->[0];
	    $graph_type ||= $subgraphs->[1];
	    next unless ref $options eq 'ARRAY';
	    push @rows,(TR {-class => "$glyph graphtype",
			    -id    => "conf_${glyph}_graphtype"},
			th({-align => 'right'}, $render->tr('XYplot_type')),
			td($picker->popup_menu(
			       -name     => "conf_${glyph}_graphtype",
			       -values   => $options,
			       -override => 1,
			       -default => ref $graph_type eq 'CODE' ? $dynamic : $graph_type,
			       -scripts => { -id => "conf_${glyph}_graphtype_id",
					     -onChange => 'track_configure.glyph_select($(\'config_table\'),$(\'glyph_picker_id\'))'},
			       -current  => $override->{'graph_type'})));
	}
    }

    #######################
    # cycling colors
    #######################
    push @rows,TR({
	-id   => 'color_series',
	-class=> 'general'
		  },
		  th ( { -align=>'right' }, $render->tr('AUTO_COLORS') ),
		  td(hidden(-name => 'conf_color_series',-value=>0),
		     checkbox(-name => 'conf_color_series',
			      -id   => 'conf_color_series',
			      -override=> 1,
			      -value   => 1,
			      -checked => defined $override->{'color_series'} 
			                  ? $override->{'color_series'} 
			                  : $color_series,
			      -label   => '')));

    #######################
    # bicolor pivot stuff
    #######################
    my $p = $override->{bicolor_pivot} || $bicolor_pivot || 'none';
    my $has_pivot = $g =~ /wiggle_xyplot|wiggle_density|xyplot/;

    push @rows,TR( {-class=>'xyplot density color_picker',
		     -id   =>'bicolor_pivot_id'},
                   th( { -align => 'right'}, $render->translate('BICOLOR_PIVOT')),
		   td( $picker->popup_menu(
			   -class   => 'color_picker',
			   -name    => 'conf_bicolor_pivot',
			   -values  => [qw(none zero mean 1SD 2SD 3SD value)],
			   -labels  => {value => 'value entered below',
					'1SD' => 'mean + 1 standard deviation',
					'2SD' => 'mean + 2 standard deviations',
					'3SD' => 'mean + 3 standard deviations',
			   },
			   -default => $bicolor_pivot,
			   -current => $p =~ /^-?[\d.eE]+(?:SD)?$/i ? 'value' : $p,
			   -scripts => {-onChange => 'track_configure.pivot_select(this)',
					-id       => 'conf_bicolor_pivot'}
		       )
		   )
        );

    my $pv    = $p =~ /^[\d.-eE]+$/ ? $p : 0.0;
    push @rows,TR({-class =>'xyplot density color_picker',
		   -id=>'switch_point_other'},
		  th( {-align => 'right' },$render->translate('BICOLOR_PIVOT_VALUE')),
                  td( textfield(-name  => 'bicolor_pivot_value',
				-value => $pv)));
    

    push @rows,TR({-class=>'switch_point_color xyplot density color_picker'}, 
		  th( { -align => 'right' }, $render->translate('BICOLOR_PIVOT_POS_COLOR')),
		   td( $picker->color_pick(
			   'conf_pos_color',
			   $self->setting( $label => 'pos_color', $length, $summary_mode ),
			   $override->{'pos_color'}
		       )
		   )
        );

    push @rows,TR( {-class=>'switch_point_color xyplot density color color_picker'}, 
		   th( { -align => 'right' }, $render->translate('BICOLOR_PIVOT_NEG_COLOR') ),
		   td( $picker->color_pick(
			   'conf_neg_color',
			   $self->setting( $label => 'neg_color', $length, $summary_mode ),
			   $override->{'neg_color'}
		       )
		   )
        );

    push @rows,TR( { -id    => 'bgcolor_picker',
		     -class => 'xyplot density features peaks color_picker',
		   },
		   th( { -align => 'right' }, $render->translate('BACKGROUND_COLOR') ),
		   td( $picker->color_pick(
			   'conf_bgcolor',
			   $self->setting( $label => 'bgcolor', $length, $summary_mode ),
			   $override->{'bgcolor'},
		       )
		   )
        );
    push @rows,TR( { -id    => 'startcolor_picker',
		     -class => 'peaks color_picker',
		   },
		   th( { -align => 'right' }, 'Peak gradient start'),
		   td( $picker->color_pick(
			   'conf_start_color',
			    $self->setting( $label => 'start_color', $length, $summary_mode ),
			   $override->{'start_color'}
		       )
		   )
        );
    push @rows,TR( { -id    => 'endcolor_picker',
		     -class => 'peaks color_picker',
		   },
		   th( { -align => 'right' }, 'Peak gradient end'),
		   td( $picker->color_pick(
			   'conf_end_color',
			    $self->setting( $label => 'end_color', $length, $summary_mode ),
			   $override->{'end_color'}
		       )
		   )
        );
    push @rows,TR( {-class=>'xyplot features peaks color_picker'},
		   th( { -align => 'right' }, $render->translate('FG_COLOR') ),
		   td( $picker->color_pick(
			   'conf_fgcolor',
			   $self->setting( $label => 'fgcolor', $length, $summary_mode ),
			   $override->{'fgcolor'}
		       )
		   )
        );


    #######################
    # wiggle colors
    #######################
    push @rows,TR( {-class=>'whiskers color_picker'}, 
		   th( { -align => 'right' }, $render->translate('WHISKER_MEAN_COLOR')),
		   td( $picker->color_pick(
			   'conf_mean_color',
			   $mean_color || 'black',
			   $override->{'mean_color'}
		       )
		   )
        );

    push @rows,TR( {-class=>'whiskers color_picker'}, 
		   th( { -align => 'right' }, $render->translate('WHISKER_STDEV_COLOR') ),
		   td( $picker->color_pick(
			   'conf_stdev_color',
			   $stdev_color || 'grey',
			   $override->{'stdev_color'}
		       )
		   )
        );

    push @rows,TR( {-class=>'whiskers color_picker'}, 
		   th( { -align => 'right' }, $render->translate('WHISKER_MAX_COLOR') ),
		   td( $picker->color_pick(
			   'conf_max_color',
			   $max_color || 'lightgrey',
			   $override->{'max_color'}
		       )
		   )
        );

    push @rows,TR({-class=>'xyplot autoscale',
                   -id  => "xyplot_autoscale"
		  },
		    th( { -align => 'right' },$render->tr('AUTOSCALING')),
		    td( $picker->popup_menu(
			    -name    => "conf_xyplot_autoscale",
			    -values  => [qw(none local)],
			    -labels  => {none=>'fixed',local=>'scale to view'},
			    -default => $autoscale,
			    -current => $override->{autoscale},
			    -scripts => {-onChange => 'track_configure.autoscale_select(this,$(\'glyph_picker_id\'))',
					 -id  => "conf_xyplot_autoscale"
			    }
			)));

    push @rows,TR({-class=>'wiggle vista_plot autoscale',
		   -id   => 'wiggle_autoscale'},
		    th( { -align => 'right' },$render->translate('AUTOSCALING')),
		    td( $picker->popup_menu(
			    -name    => "conf_wiggle_autoscale",
			    -values  => $summary_mode ? [qw(none local)] : [qw(none z_score local chromosome global clipped_global)],
			    -labels  => {none      =>'fixed',
					 z_score   =>'scale to SD multiples',
					 local     =>'scale to local min/max',
					 chromosome=>'scale to chromosome min/max',
					 global    =>'scale to genome min/max',
					 clipped_global   =>'clip to +/- SDs shown below'
			    },
			    -default => $autoscale,
			    -current => $override->{autoscale},
			    -scripts => {-onChange => 'track_configure.autoscale_select(this,$(\'glyph_picker_id\'))',
					 -id       => "conf_wiggle_autoscale"
			    }
		       )));

    push @rows,TR({-class=>'wiggle vista_plot autoscale',
		   -id   => 'wiggle_z_fold'},
		    th( { -align => 'right' },$render->translate('SD_MULTIPLES')),
		    td( $picker->popup_menu(
			    -name    => "conf_z_score_bound",
			    -values  => [qw(1 2 3 4 5 6 8 10 20)],
			    -labels  => {1   =>'1 SD',
					 2   =>'2 SD',
					 3   =>'3 SD',
					 4   =>'4 SD',
					 5   =>'5 SD',
					 6   =>'6 SD',
					 8   =>'8 SD',
					 10   =>'10 SD',
					 20   =>'20 SD',
					 },
			    -default => $sd_fold,
			    -current => $override->{z_score_bound}
			)));

    push @rows,TR( {-class=> 'xyplot density whiskers vista_plot autoscale',
		    -id   => 'fixed_minmax'
		   },
		   th( { -align => 'right' },$render->translate('SCALING')),
		   td( textfield(-name  => 'conf_min_score',
				 -class => 'score_bounds',
				 -size  => 5,
				 -value => defined $override->{min_score} ? $override->{min_score}
				                                          : $summary_mode ? 0 : $min_score),
		   '-',
		   textfield(-name  => 'conf_max_score',
			     -class => 'score_bounds',
			     -size  => 5,
			     -value => defined $override->{max_score} ? $override->{max_score}
			                                              : $summary_mode ? 10 : $max_score)))
	if $quantitative;

    push @rows,TR({-class=>'xyplot'},
		  th( { -align => 'right' }, $render->translate('SHOW_VARIANCE')),
		  td(
		      hidden(-name=>'conf_variance_band',-value=>0),
		      checkbox(
			  -name    => 'conf_variance_band',
			  -override=> 1,
			  -value   => 1,
			  -checked => defined $override->{'variance_band'} 
			  ? $override->{'variance_band'} 
			  : $variance_band,
			  -label   => '',
		      )
		  )
        );

    push @rows,TR( {-class=>'features'},
		   th( { -align => 'right' }, $render->translate('LINEWIDTH') ),
		   td( $picker->popup_menu(
			   -name    => 'conf_linewidth',
			   -current => $override->{'linewidth'},
			   -default => $width || 1,
			   -values  => [ sort { $a <=> $b } ( $width, 1 .. 5 ) ]
		       )
		   )
	);

    push @rows,TR( {-class=>'general'},
		   th(
		       { -align => 'right' }, $render->translate('HEIGHT') ),
		   td( $picker->popup_menu(
			   -name    => 'conf_height',
			   -id      => 'conf_height',
			   -current => $override->{'height'},
			   -default => $height,
			   -values  => [
				sort { $a <=> $b }
				( $height, map { $_ * 5 } ( 1 .. 20 ) )
			   ],
		       )
		   )
        );
    
    push @rows,TR({-class=>'features'},
		  th( { -align => 'right' }, $render->translate('Limit') ),
		  td( $picker->popup_menu(
			  -name     => 'conf_feature_limit',
			  -values   => [ 0, 5, 10, 25, 50, 100, 200, 500, 1000 ],
			  -labels   => { 0 => $render->translate('NO_LIMIT') },
			   -current  => $override->{feature_limit},
			  -override => 1,
			  -default  => $limit,
		       )
		  )
        );
    
    push @rows,TR({-class=>'features'},
		  th( { -align => 'right' }, $render->translate('STRANDED') ),
		  td( hidden(-name=>'conf_stranded',-value=>0),
		      checkbox(
			  -name    => 'conf_stranded',
			  -override=> 1,
			 -value   => 1,
			  -checked => defined $override->{'stranded'} 
			  ? $override->{'stranded'} 
			  : $stranded,
			  -label   => '',
		      )
		  )
        );

    my ($low,$hi)   = $render->find_override_bounds($state->{features}{$label}{semantic_override},$scaled_length);
    $low = $semantic_level unless defined $low;
    $hi  ||= MAX;
    my $mult = $render->details_mult;
    push @rows,TR({-class=>'general'},
		  th( {-align => 'right' }, 
		      $render->translate('APPLY_CONFIG')
		      ),
		  td(
		      $self->region_size_menu('apply_semantic_low',$scaled_length,[$low/$mult,MIN],$low/$mult),
		      '-',
		      $self->region_size_menu('apply_semantic_hi',$scaled_length,[$hi/$mult,MAX],$hi/$mult),
		  )
	) unless $summary_mode;

    my $summ = defined $state->{features}{$label}{summary_mode_len}
                         ?$state->{features}{$label}{summary_mode_len}
                         :$summary_length;
    push @rows,TR({-class=>'general'},
		  th( { -align => 'right' }, $render->translate('SHOW_SUMMARY')),
		  td(
		      $self->region_size_menu('summary_mode',$summ)
		  )
	) if $can_summarize && $summary_length;

    my $submit_script = <<END;
Element.extend(this);
var ancestors    = this.ancestors();
var form_element = ancestors.find(function(el) {return el.nodeName=='FORM'; });
Controller.reconfigure_track('$label',form_element,'$mode')
END

    push @rows,TR({-class=>'general'},
		  td({-colspan=>2},
		     button(
			 -style   => 'background:pink',
			 -name    => $render->translate('Revert'),
			 -onClick => $reset_js
		     ), br, 
		     button(
			 -name    => $render->translate('Cancel'),
			 -onClick => 'Balloon.prototype.hideTooltip(1)'
		     ),
		     button(
			 -name    => $render->translate('Change'),
			 -onClick => $submit_script
		     ),
		     hidden(-name=>'segment_length',-value=>$length),
		  )
    );

    $form .= table({-id=>'config_table',-border => 0 },@rows);
    $form .= end_form();
    $return_html
        .= table( TR( td( { -valign => 'top' }, [ $form ] ) ) );

    $return_html .= script({-type=>'text/javascript'},"track_configure.init($opacity)");
    $return_html .= end_html();
    return $return_html;
}

sub setting {
    my $self = shift;
    my ($label,$option,$length,$is_summary) = @_;
    my $data_source = $self->render->data_source();

    # bad hack
    if ($is_summary) {
	if ($data_source->Bio::Graphics::FeatureFile::setting("$label:summary")) {
	    return $data_source->semantic_fallback_setting("$label:summary",$option,$length);
	} else {
	    return 'wiggle_density' if $option eq 'glyph';
	    return 15               if $option eq 'height';
	    return 0                if $option eq 'min_score';
	    return 'local'          if $option eq 'autoscale';
	}
    }

    return $data_source->semantic_fallback_setting($label,$option,$length);
}

sub region_size_menu {
  my $self = shift;
  my ($name,$length,$extra_vals,$default) = @_;
  $extra_vals ||= [];

  my $source =  $self->render->data_source;
  my %seen;
  my @r         = sort {$a<=>$b} ($source->get_ranges(),$length,@$extra_vals);
  my @ranges	= grep {!$seen{$source->unit_label($_)}++} @r;
  my %labels    = map  {$_=> scalar $source->unit_label($_)} @ranges;

  $labels{MIN()}   = $self->render->translate('MIN');
  $labels{MAX()}   = $self->render->translate('MAX');
  @ranges  = sort {$b||0<=>$a||0} @ranges;
  $default = $length unless defined $default;

  return popup_menu(-name    => $name,
		    -values  => \@ranges,
		    -labels  => \%labels,
		    -default => $default,
		    -force   => 1,
		   );
}

1;
