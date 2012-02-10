package Bio::Graphics::Browser2::Render::HTML::TrackListing;

# This module produces components of the track listing.

use strict;
use warnings;
use Bio::Graphics::Browser2::Util 'citation';
use CGI qw(:standard);
use Carp 'croak';

sub new {
    my $class  = shift;
    my $render = shift;
    return bless {render=>$render},ref $class||$class;
}

sub render    {shift->{render}           }
sub source    {shift->render->data_source}
sub settings  {shift->render->state      }

sub render_track_listing {
    croak 'render_track_listing() must be implemented in a subclass of TrackListing.pm';
}

sub categorize_track {
    my $self  = shift;
    my $label = shift;
    return;      # no categories in parent class
}

# render the label and controls for an individual track,
# used in subclasses. Returns the HTML to be pasted onto
# the page.
sub render_one_track {
    my $self   = shift;
    my $label  = shift;
    my $hilite = shift || [];
    
    my $settings   = $self->settings;
    my $render     = $self->render;
    my $source     = $self->source;
    my $button_url = $source->button_url;

    my $key = $render->label2key($label);
    my ($link,$mouseover);

    if ($label =~ /^plugin:/) {
	$key   = $render->plugin_name($label);
    }

    elsif ($label =~ /^file:/){
	$link = "?Download%20File=$key";
    }

    elsif ($source->setting($label=>'citation')){
	$link = "?display_citation=$label";
	my $cit_txt = citation( $source, $label, $render->language ) || '';
	if ( length $cit_txt > 100) {
	    $cit_txt =~ s/\<[^\>]+\>//g;     # truncate and strip tags for preview
	    $cit_txt =~ s/(.{100}).+/$1/; 
	    $cit_txt =~ s/\s+\S+$//; 
	    $cit_txt =~ s/\'/\&\#39;/g;
	    $cit_txt =~ s/\"/\&\#34;/g;
	    $cit_txt .= '... <i>' . ($render->translate('CLICK_FOR_MORE')||'') . '</i>';
	}
	$mouseover = "<b>$key</b>";
	$mouseover .= ": $cit_txt"  if $cit_txt;
    }

    my $track_on    = $settings->{features}{$label}{visible};
    my $favorite    = $settings->{favorites}{$label};
    my $balloon     = $source->setting('balloon style') || 'GBubble';
    my $cellid      = 'datacell';

    my @classes = 'track_title';
    push @classes,'activeTrack' if $track_on;
    push @classes,'favorite'    if $favorite;
    push @classes,'remote'      if $label =~ /^(http|ftp|file):/;

    # add hilighting if requested
    for my $h (@$hilite) {
	$key =~ s!($h)!<span class='text_match'>$1</span>!gi;
    }

    #if the track has already been favorited, the image source is made into the yellow star
    my $star      = $favorite ? 'ficon_2.png' : 'ficon.png';
    my $class     = $favorite ? 'star favorite' : 'star';
    my $show_fav  = $render->translate('ADDED_TO');
    my $favoriteicon  = img({-class       =>  $class,
			     -id          => "star_$label",
			     -onClick     => "togglestars('$label')",
			     -onMouseOver => "GBubble.showTooltip(event,'$show_fav')",
			     -style       => 'cursor:pointer;',
			     -src         => "$button_url/$star"}
	);

    my $category    = $self->categorize_track($label);
    my $clickaction = "gbToggleTrack('$label')";
    $clickaction   .= ";gbTurnOff('${category}_section')" if $category;

    my @args;
    push @args, (-class       => "@classes");
    push @args, (-onClick     => $clickaction);
    push @args, (-onmouseover => "$balloon.showTooltip(event,'$mouseover')") if $mouseover;

    my $title  = span({-id=>"${label}_check",@args},$key);

    my $checkicon =   img({-id      => "${label}_img",
			   -onClick => "gbToggleTrack('$label')",
			   -src     =>$track_on ? "$button_url/check.png" 
			                        : "$button_url/square.png"});
    my $help     = $link ? a({-href        => $link,
			      -target      => '_new',
			      -onmouseover => "$balloon.showTooltip(event,'$mouseover')",
			     }, '[?]')
	                 : '';
	
    my $html             = join(' ',$favoriteicon,span({-class=>'track_label'},$checkicon,$title),$help);


    if (my ($selected,$total) = $render->subtrack_counts($label)) {
	my $escaped_label = CGI::escape($label);
	$html .= ' ['. span({-class       =>'clickable',
			     -onMouseOver  => "GBubble.showTooltip(event,'".$render->translate('CLICK_MODIFY_SUBTRACK_SEL')."')",
			     -onClick      => "GBox.showTooltip(event,'url:?action=select_subtracks;track=$escaped_label',true)"
			    },i($render->translate('SELECT_SUBTRACKS',$selected,$total))).']';
    }

    return $html;
}


1;

