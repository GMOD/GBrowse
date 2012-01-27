# $Id: PrimerDesigner.pm,v 1.11 2007-03-31 14:33:36 sheldon_mckay Exp $

=head1 NAME

Bio::Graphics::Browser2::Plugin::PrimerDesigner -- a plugin to design PCR primers with primer3

=head1 SYNOPSIS

This module is not used directly

=head1 DESCRIPTION

PrimerDesigner.pm uses the Bio::PrimerDesigner API for primer3 to design
PCR primers for features or target coordinates in gbrowse.

=head1 PRIMER3
  
Compile a primer3 (v. 0.9 or later) binary executable for your 
OS and copy it to the default path usr/local/bin with the name primer3.
Source code for primer3 can be obtained from
http://frodo.wi.mit.edu/primer3/primer3_code.html.

=head1 Designing Primers

=head2 Targeting a feature or coordinate

The target for PCR primer design is selected by clicking on an image map.
For aggregate features such as gene models, etc, there is a mousover menu
to select the individual part of the whole feature


=head2 Design Paramaters

The Provided  set of reasonable default primer attributes will work in most 
cases.  Product size will vary by target feature size.  A suggested PCR 
product size range is calculated based on the selected feature.  If this field
is left blank, a series of increasing PCR product sizes is cycled until 
products big enough to flank the target feature are found.  This will not 
necessarily find the best primers, just the first ones that produce a big 
enough product to flank the target.  If the primers are flagged as low quality,
more optimal optimal primers may be found by specifying a specific size-range.

=head1 Bio::Graphics::Browser

This plugin contains an additional package Bio::Graphics::Browser2::faux.
This class inherits from  Bio::Graphics::Browser.  Its purpose is to
keep the  Bio::Graphics::Browser funtionality and configuration data
while overriding image_map-related funtions required for this plugin.

=head1 TO-DO

Add support for ePCR-based scanning for false priming

=head1 FEEDBACK

See the GMOD website for information on bug submission http://www.gmod.org.

=head1 AUTHOR - Sheldon McKay

Email mckays@cshl.edi

=head1 SEE ALSO

Bio::PrimerDesigner (www.cpan.org)
primer3 (http://frodo.wi.mit.edu/primer3/primer3_code.html)

=cut
package Bio::Graphics::Browser2::Plugin::PrimerDesigner;

use strict;
use Data::Dumper;
use POSIX qw/isdigit/;
use Bio::Graphics::Panel;
use Bio::PrimerDesigner;
use Bio::PrimerDesigner::Tables;
use Bio::Graphics::Browser2::Plugin;
use Bio::Graphics::Browser2::Util;
#use Bio::Graphics::Browser; #No longer available in Gbrowse 2
use Bio::Graphics::Feature;
use Bio::Graphics::FeatureFile;
use CGI qw/:standard escape/;
use CGI::Pretty 'html3';
use CGI::Carp 'fatalsToBrowser';
use CGI::Toggle;
use Math::Round 'nearest';
use Carp qw/cluck/;

use constant BINARY            => 'primer3';
use constant BINPATH           => '/usr/local/bin';
use constant METHOD            => 'local';
use constant IMAGE_PAD         => 25;
use constant MAXRANGE          => 300;
use constant IMAGEWIDTH        => 800;
use constant DEFAULT_SEG_SIZE  => 10000;
use constant STYLE             => '/gbrowse2/css/gbrowse.css';

#use vars '@ISA';
use vars qw/@ISA $PNG $CALL/;

@ISA = qw/Bio::Graphics::Browser2::Plugin/;


# Arg, modperl
END {
	
  CGI::Delete_all();
}



sub name {
  'PCR primers';
}

sub description {

  p(      "This plugin uses PRIMER3 to pick PCR primers to amplify selected "
	.  "features or sequences."
	. " This plugin was written by Sheldon McKay (mckays\@cshl.edu)" );

}

sub type {
   'dumper';
}

sub verb {

#Remove the Configure button when designing primers. The plugin doesn't need 
#the option anyway, and it will only confuse people if left on the page.

#$CALL keeps track of how many times the module is run so it doesn't attach 
#multiple events. Otherwise, the javascript will run about 3 times.

#This is a cheat. Since there's no way to make javascript calls from ajax, 
#code gets inserted here instead because GBrowse runs this no matter what.
    #unless ($CALL) {

#my $detail_select_menu = detail_select_menu();

#print <<JS;


    #<script type="text/javascript"> 

	#var oPrimerDesigner = { };

	#oPrimerDesigner.removeConfigureButton = function () {
	    #var plugin_select = document.getElementById('plugin');
	    #var config_button = document.getElementsByName('plugin_action')[0];

	    #var i = plugin_select.selectedIndex;
	    #if (plugin_select.options[i].text == 'Design PCR primers')
		#config_button.style.display = 'none';

	    #plugin_select.onchange = function () { 

		#var i = this.selectedIndex;
		#if (this.options[i].text == 'Design PCR primers') {
		    #config_button.style.display = 'none';
		#} else {
		    #config_button.style.display = 'inline';
		#}

	    #}

	#}
	#if (window.addEventListener) {  // W3C standard
	    #window.addEventListener('load', oPrimerDesigner.removeConfigureButton, false); // NB **not** 'onload'
	#} 
	#else if (window.attachEvent) {  // Microsoft
	    #window.attachEvent('onload', oPrimerDesigner.removeConfigureButton);
	#}
    #</script>
#JS
	#$CALL++;
    #}

  'Design';
}

sub mime_type {

  'text/html';
}

sub is_zoom {
  return param('span') unless param('configured'); 
}

sub reconfigure {
  my $self = shift;
  my $conf = $self->configuration;

  $conf->{size_range} = undef;
  $conf->{target}     = undef;
  $conf->{lb}         = undef;
  $conf->{rb}         = undef;

  my $target = $self->config_param('target');
  my $lb     = $self->config_param('lb');
  my $rb     = $self->config_param('rb');

  if ($lb && $rb) {
    my $min_size = $rb - $lb + 40;
    my $max_size = $min_size + MAXRANGE;

    # round to nearest 50 bp
    $conf->{size_range} = join '-', map {$_||=50} nearest(50, $min_size, $max_size);


    # make sure target is within the selected region
    if (!$target || $target < $lb || $target > $rb) {
      $target = int( ($lb+$rb)/2 );
    }
  }

  $conf->{target}  = $target;
  $conf->{lb}      = $lb;
  $conf->{rb}      = $rb;
  $conf->{span}    = is_zoom;
  $conf->{name}    = $self->config_param('name');
  $self->configuration($conf);
}

sub my_url {
  my $self = shift;
  my $url  = $self->{url};
  return $url if $url;
  $url = self_url();
  $url =~ s/\?.+//;
  return $self->{url} = $url;
}

sub configure_form {
  my $self    = shift;
  my ($segment,$target,$lb,$rb,$feats) = @_;


  #($segment) = @{ $self->segments } unless $segment;
  ($segment) = $self->segments unless $segment;
  $segment ||= fatal_error("This plugin requires a sequence region");
  my $browser = $self->browser_config;
  my $conf = $self->configuration;

  my $no_buttons = 1 if !($lb || $rb)  || $feats;
  
  # make sure the target is not stale for the initial config
  delete $conf->{target} if !($lb || $rb); 

  my @feature_types = $self->selected_features;
  my @args          = ( -types => \@feature_types );
  
  $target ||= $self->focus($segment);
  $rb     ||= $target;
  $lb     ||= $target;

  # primer design params
  my $atts = $self->primer3_params($lb,$rb) unless $no_buttons;

  my $table_width = IMAGEWIDTH + 50;

  my ( $image, $map, $zoom_menu )
      = $self->new_segment_map( $segment, $feats, $lb, $rb );

  my $message = '';

  my $start  = $segment->start;
  my $end    = $segment->end;
  my $ref    = $segment->ref;
  my $name   = $conf->{name} || "$ref:$start..$end";

  my $length = unit_label( $segment->length );

 my $html   =  h2("Showing $length from $ref, positions $start to $end");

  $html .= hidden( -name => 'plugin',        -value => 'PrimerDesigner' )
	. hidden( -name => 'plugin_action', -value => 'Go' )
	. hidden( -name => 'ref', -value => $segment->ref )
	. hidden( -name => 'start', -value => $segment->start )
	. hidden( -name => 'stop', -value => $segment->stop );
  $html .= hidden( -name => $self->config_name('lb'), -value => $lb) if $lb;
  $html .= hidden( -name => $self->config_name('rb'), -value => $rb) if $rb;
  $html .= hidden( -name => $self->config_name('target'), -value => $target) if $target;

  my $map_text = $self->map_header;

  my $on = 1 unless $feats;
  my $no_target = li("There currently is no target region selected.")
      if ($rb - $lb) < 3;
  #my $no_target = li("Click and drag on the ruler to select a PCR target.");
  my $has_buttons = li("The size of potential PCR products can be adjusted via the 'Product size range' option below")
      unless $no_buttons;
  my $flanked = $no_target ? 'red line' : 'shaded region';
  my $boundaries = li("The boundaries of the shaded target region can be adjusted by clicking on the lower scalebar")
      unless $no_target;
  my $click_feat = $no_target ? li("Click on a sequence feature to select")
      : li("Click on a different sequence feature to change the selection");
      
  my $zone = 
	    $self->toggle( { on => $on, override => 0 },
		     'Targetting information',
		     font( {-size => -1},
			   ul( $no_target, 
			       li("PCR primers will flank the $flanked."),
			       $click_feat,
			       $boundaries,
			       $has_buttons
			   ) )
		     ) 
		    . br;


  $html .= table(
		 { -style => "width:${table_width}px" },
    Tr(
       { -class => 'searchtitle' },
      [ 
#NML: map text does nothing at the moment. not even sure what it's supposed to do
#It doesn't appear in the functional 1.7 version
	#th($map_text) . 
	th($zoom_menu),
	td( { -class => 'searchbody', -colspan => 2 }, $image . br),
	td( { -class => 'searchbody', -colspan => 2}, $zone )
      ]
    )
		 );


  unless ($no_buttons) {
    my @col1 = grep {/Primer|Tm|Product/} keys %$atts;
    my @col2 = grep { !/Primer|Tm|Product/ } keys %$atts;

    @col1 = (
	     ( grep { $atts->{$_} =~ /Opt\./ } @col1 ),
	     ( grep { $atts->{$_} !~ /Opt\./ } @col1 )
	     );
    
    my @rows = ( td( { -colspan => 4 }, h3($message) ),
		 td( { -colspan => 4 }, hr ) );
    
    for ( 0 .. 4 ) {
      push @rows, td(
		     [ $col1[$_], $atts->{ $col1[$_] }, $col2[$_], $atts->{ $col2[$_] } ] );
    }
    
    $html .= table( { -style => "width:${table_width}px" }, Tr( \@rows ) );
    $html .= br
	  . submit( -name => 'configured', -value => 'Design Primers' )
	  . '&nbsp;'
	  . reset('Reset Parameters')
	  . '&nbsp;'
	  . $self->back_button;
  }
  
  (my $action = self_url()) =~ s/\?.+//;
  $html = start_form(
		     -method => 'POST',
		     -name   => 'mainform',
		     -action => $action
		     ).
	$html
	.  end_form;
	#die Dumper  $html;

  # if this is the first config, exit before form and buttons
  # are printed by gbrowse
  if ($no_buttons && !$feats) {
    my $style = $browser->setting('stylesheet') || STYLE;
    print start_html( -style => $style, -title => 'PCR Primers'),
      $html, $map, $browser->footer;
    exit;
  }



    #my $form = textfield(-name  => $self->config_name('foo'),
			#-value => $conf->{foo})
		#.
		#textfield(-name  => $self->config_name('bar'),
			#-value => $conf->{bar});
    #return $form;

  return $feats ? ($html,$map) : $html.$map;
}

sub map_header {
  my $recenter = a(
    { -href  => '#',
      -title => 'Click the top scale-bar to recenter the image'
    },
    'recenter'
  );
  my $select_t = a(
    { -href  => '#',
      -title => 'Click a sequence feature below to select a target'
    },
    'select a PCR target'
  );

  return "Click on the map to $recenter or $select_t";
}

sub dump {
  my ( $self, $segment ) = @_;
  my $conf = $self->configuration;
  #print Dumper $conf;
  $self->reconfigure;

  #print Dumper $conf;
  # dumpers provide their own headers, so make sure boiler plate
  # stuff is included
  #my $style_sheet = $self->browser_config->setting('stylesheet') || STYLE;
  my $style_sheet = $self->browser_config->plugin_setting('stylesheet') || STYLE;
  print start_html( -style => $style_sheet, -title => 'PCR Primers' );
  print $self->browser_config->header_html;

  # reset off-scale target if required
  delete $conf->{target} if $conf->{target} 
    && ($conf->{target} > $segment->end - 1000 || $conf->{target} < $segment->start + 1000);
  delete $conf->{lb} if $conf->{lb} 
    && ($conf->{lb} > $segment->end - 1000 || $conf->{lb} < $segment->start);
  delete $conf->{rb} if $conf->{rb} 
    && ($conf->{rb} < $segment->start + 1000 || $conf->{rb} > $segment->end);
  delete $conf->{target} unless $conf->{lb} && $conf->{rb};
  #print Dumper $conf;

  my $target = $self->focus($segment);
  my $lb = $conf->{lb} || $target;
  my $rb = $conf->{rb} || $target;

  # check for a zoom request
  my $segment_size = $self->is_zoom;

  # Make room if target region is too close to the ends
  my ($new_start,$new_end);
  if ($rb >= $segment->end - 500) {
    $new_end = $rb + 500;
  }
  if ($lb <= $segment->start + 500) {
    $new_start = $lb - 500;
  }
  #print 'dump 1: '.$segment->start.' '.$segment->end.'<br>';

# NML: this is causing the panel to zoom beyond the segment boundaries
  #if ($new_start || $new_end) {
    #$segment = $self->database->segment( -name  => $segment->ref,
					 #-start => ($new_start || $segment->start),
					 #-end   => ($new_end   || $segment->end) );
    #$segment_size = $segment->length;
  #}

    #NML: kludgy fix to get details panel to draw at an appropriate length
    #Otherwise, it spills past the browser window
    $self->renderer->set_details_multiplier(1);

my $maxrange = MAXRANGE;
print <<JS;
<script type="text/javascript">

    var oPrimerDesigner = { };

    oPrimerDesigner.removePanButtons = function () {

	/*Get rid of panleft and panright buttons         */
	/*until I can figure out a way to get them working*/
	var imgs = document.getElementsByTagName('img');

	for (i=0; i<imgs.length; i++) {
	    if (imgs[i].className == 'panleft' 
		|| imgs[i].className == 'panright' 
		) {
		imgs[i].style.display='none';
	    }
	}
    }

    oPrimerDesigner.scroll = function (direction,length_units) {

	oPrimerDesigner.unselectRegion();

	var plugin = document.getElementsByName('plugin')[0].value;

	var detail_start = parseInt(Controller.segment_info.detail_start) 
	var detail_stop = parseInt(Controller.segment_info.detail_stop) 

	var overview_start = Controller.segment_info.overview_start;
	var overview_stop = Controller.segment_info.overview_stop;

	var view_length = 
	    (
	    parseInt(Controller.segment_info.detail_stop) 
	    - parseInt(Controller.segment_info.detail_start)
	    ) 
	    / parseFloat(Controller.segment_info.details_mult);

	var bits = Math.round(length_units*view_length);

	var action = direction + ' ' + bits;
	var mainform = document.getElementsByName('mainform')[0];

	var newStart, newStop;

	if (direction == 'left') {
	    newStart = Math.round(detail_start - bits);
	    newStop = Math.round(detail_stop - bits);
	    if (newStart < overview_start) {
		newStart = overview_start;
		newStop = view_length;
		newStop = Math.round(overview_start + view_length);
	    }
	}
	else if (direction == 'right') {
	    newStart = Math.round(detail_start + bits);
	    newStop = Math.round(detail_stop + bits);
	    if (newStop > overview_stop) {
		newStart = Math.round(overview_stop - view_length);
		newStop = overview_stop;
	    }

	}
	else { 
	    if (direction == 'zoom') {

		var detail_length = detail_stop - detail_start;
		var value = detail_length * length_units;

		var addMargin = Math.round((value - detail_length)/2);

		newStart = Math.round(detail_start - addMargin);
		newStop = Math.round(detail_stop + addMargin);

	    }	
	    else if (direction == 'set span') {
		var value = length_units*1;
		var addMargin = Math.floor((value - (detail_stop - detail_start))/2);

		newStart = Math.round(detail_start - addMargin);
		newStop = Math.round(detail_stop + addMargin);

	    }

	    if ((newStop - newStart) > (overview_stop - overview_start)) {
		newStart = overview_start;
		newStop = overview_stop;
	    }

	    if (newStart < overview_start ) {
		newStart = overview_start;
		newStop = newStart + value - 1; 
	    }
	    else if (newStop > overview_stop ) {
		newStart = overview_stop - value + 1; 
		newStop = overview_stop;
	    }
	}

	oPrimerDesigner.createNewFormElement(mainform, "view_start", newStart);
	oPrimerDesigner.createNewFormElement(mainform, "view_stop", newStop);

	mainform.action = mainform.action 
	    + '?plugin='+plugin+';action=Go;view_start='+newStart+';view_stop='+newStop;

	mainform.submit();


    }

    oPrimerDesigner.designPrimers = function () {
	//var mainform = document.getElementsByName('mainform')[0];
	//var conf = oPrimerDesigner.createNewFormElement(mainform, "configured", "Design Primers");

	//mainform.setAttribute("target", "_blank");
	//mainform.submit();

	/*Remove these after submit or else will generate a bug where user*/
	/*tries to scroll or zoom without closing rubber band menu first, */
	/*causing form to unintentionally be resubmitted                  */
	//mainform.removeChild(conf);
	//mainform.removeAttribute("target");
    }

    oPrimerDesigner.selectRegion = function () {

	SelectArea.prototype.cancelRubber();

	var size_range = document.getElementById('product_size_range');

	var plugin = document.getElementsByName('plugin')[0].value;

	var select_start = currentSelectArea.selectSequenceStart;
	var select_end = currentSelectArea.selectSequenceEnd;

	var min_size = select_end - select_start + 40;
	var max_size = min_size + $maxrange;

	var x = [];
	var sizes = [min_size, max_size];
	for (i=0;i < sizes.length;i++) {
	    var n = sizes[i];
	    x.push(Math.ceil(sizes[i]/50.0) * 50);

	}

	var lb = document.getElementsByName(plugin+'.lb')[0]
	var rb = document.getElementsByName(plugin+'.rb')[0];
	var target = document.getElementsByName(plugin+'.target')[0];


	oPrimerDesigner.lb = lb.value;
	oPrimerDesigner.rb = rb.value;
	oPrimerDesigner.target = target.value;
	oPrimerDesigner.size_range = size_range.value;

	size_range.value = x[0]+'-'+x[1];

	lb.value = select_start;
	rb.value = select_end;

	if (target.value == undefined || target.value < select_start || target.value > select_end) {
	    target.value = parseInt( (select_start+select_end)/2 );
	}

	var mainform = document.getElementsByName('mainform')[0];
	mainform.submit();
    }

    oPrimerDesigner.unselectRegion = function () {

	var plugin = document.getElementsByName('plugin')[0].value;
	var size_range = document.getElementById('product_size_range');

	if (oPrimerDesigner.size_range != undefined) {
	    size_range.value = oPrimerDesigner.size_range;
	}

	if (oPrimerDesigner.lb != undefined) {
	    document.getElementsByName(plugin+'.lb')[0].value = oPrimerDesigner.lb;
	}
	if (oPrimerDesigner.rb != undefined) {
	    document.getElementsByName(plugin+'.rb')[0].value = oPrimerDesigner.rb;
	}
	if (oPrimerDesigner.target != undefined) {
	    document.getElementsByName(plugin+'.target')[0].value = oPrimerDesigner.target;
	}

	SelectArea.prototype.cancelRubber();
    }

    if (window.addEventListener) {  // W3C standard
	window.addEventListener('load', oPrimerDesigner.removePanButtons, false); // NB **not** 'onload'
    } 
    else if (window.attachEvent) {  // Microsoft
	window.attachEvent('onload', oPrimerDesigner.removePanButtons);
    }

</script>
JS
#if (param('configured') ) {
#print 'param configured<br>';
#}
#if ($self->get_primer3_params()) {
    #print 'got primer3 params<br>';
#} else {
    #print Dumper param();
#}
#if (param('configured') && $self->get_primer3_params()) {
  #print Dumper $conf;
  #}


  # design the primers if required
  $self->design_primers( $segment, $lb, $rb)
      if param('configured') && $self->get_primer3_params();


  # or print the config form
  print $self->configure_form($segment,$target,$lb,$rb);

    my $render = $self->renderer;

    my $segment_info = $render->segment_info_object;

    my $div = $render->render_search_form_objects();
    $div = join('', split("\n", $div));
    $div =~ s/'/\\'/g;

    my $segment_info_string = 
    join(',', map { 
	my $val = $segment_info->{$_};
	$val = isdigit($val) ? $val : "\'$val\'";
	"'$_': $val"
    } (keys %$segment_info) );

#my $detail_select_menu = detail_select_menu();

print <<JS;


<script type="text/javascript">


    Controller.segment_info = { $segment_info_string };

    /*helper function to create a form*/
    oPrimerDesigner.getNewSubmitForm = function (){
	var submitForm = document.createElement("form");
	document.body.appendChild(submitForm);
	submitForm.method = "post";
	return submitForm;
    }

    /*helper function to add elements to the form*/
    oPrimerDesigner.createNewFormElement = function (inputForm, elementName, elementValue){
	var newElement = document.createElement('input');
	newElement.name = elementName;
	newElement.type = 'hidden';
	newElement.value= elementValue
	inputForm.appendChild(newElement);
	return newElement;
    }

    /*Create submit form to get rubberband working*/
    //oPrimerDesigner.submitForm = oPrimerDesigner.getNewSubmitForm();
    //oPrimerDesigner.createNewFormElement(oPrimerDesigner.submitForm, "force_submit", "0");
    //oPrimerDesigner.createNewFormElement(oPrimerDesigner.submitForm, "plugin_action", "Go");

    //oPrimerDesigner.createNewFormElement(oPrimerDesigner.submitForm, "plugin", document.getElementsByName('plugin')[0].value);
    //oPrimerDesigner.submitForm.style.display = 'none';

    //var div = document.createElement('div');
    //div.innerHTML = '$div';
    //div.setAttribute('id', 'search_form_objects');
    //oPrimerDesigner.submitForm.appendChild(div);

    //document.searchform = oPrimerDesigner.submitForm;

    oPrimerDesigner.details_panel = document.getElementById('primer_panel');

    if (window.addEventListener) {  // W3C standard
	oPrimerDesigner.details_panel.addEventListener('mouseup', oPrimerDesigner.selectRegion, false); 
    } 
    else if (window.attachEvent) {  // Microsoft
	oPrimerDesigner.details_panel.attachEvent('onmouseup', oPrimerDesigner.selectRegion);
    }

</script>
JS



}

sub detail_select_menu {

<<DETAILS;
<div id="detailSelectMenu">
    <table style="width:100%">
	<tr>
	<th style="background:lightgrey;cell-padding:5">
	    SELECTION
	    <a style="right:0px;position:absolute;color:blue;cursor:pointer" 
		onclick="oPrimerDesigner.unselectRegion()">
	    [X]
	    </a> 
	</th>
	</tr>
	<tr>
	<td>
	    <a style="color:blue;cursor:pointer" onclick="oPrimerDesigner.designPrimers()" target="_BLANK">
	    Design primers for this region
	    </a>
	</td>
	</tr>
	<tr>
	<td>
	    <a style="color:blue;cursor:pointer" onclick="SelectArea.prototype.clearAndSubmit()">
	    Zoom in
	    </a>
	</td>
	</tr>
	<tr>
	<td>
	    <a style="color:blue;cursor:pointer" onclick="SelectArea.prototype.clearAndRecenter()">
	    Recenter on this region
	    </a>
	</td>
	</tr>
    </table>
</div>
DETAILS

}

sub design_primers {
  my ( $self, $segment, $lb, $rb ) = @_;
  my $conf    = $self->configuration;
  my %atts    = $self->get_primer3_params($lb,$rb);
  my $target  = $self->focus($segment);
  my $tlength = $rb - $lb || 1;
  my $offset  = $segment->start - 1;
  my $tstart  = $lb - $offset;
  my $exclude = join ',', $tstart, $tlength if $tlength > 1;

  $tstart += int(($rb - $lb)/2);
  my $ptarget = join ',', $tstart,1;
  
  # make the segment a manageable size 
  if (!$ptarget && $segment->length > DEFAULT_SEG_SIZE) {
    $segment = $self->refocus($segment, $target, DEFAULT_SEG_SIZE);
  }

  my $dna = $segment->seq;
  if ( ref $dna && $dna->can('seq') ) {
    $dna = $dna->seq;
  }
  elsif ( ref $dna ) {
    fatal_error(
	"Unsure what to do with object $dna. I was expecting a sequence string"
	)
  }
  elsif ( !$dna ) {
    fatal_error("There is no DNA sequence in the database");
  }

  # unless a product size range range is specified, just keep looking
  # until we find some primers that flank the target
  my $size_range = $conf->{size_range} || join ' ', qw/
      100-300 301-400 401-500 501-600 601-700 701-800 801-900
      901-1000 1001-1200 1201-1400 1401-1600 1601-1800 1801-2000
      2001-2400 2401-2600 2601-2800 2801-3200 3201-3600 3601-4000/;

  $atts{seq}                       = $dna;
  $atts{id}                        = $segment->ref;
  $atts{target}                    = $ptarget;
  $atts{excluded}                  = $exclude if $exclude;
  $atts{PRIMER_PRODUCT_SIZE_RANGE} = $size_range;

  # get a PCR object
  my $pcr = Bio::PrimerDesigner->new( program => BINARY,
				      method  => METHOD );
  $pcr or fatal_error(pre(Bio::PrimerDesigner->error));

  my $binpath = BINPATH;
  my $method = $binpath =~ /http/i ? 'remote' : METHOD;

  if ( $method eq 'local' && $binpath ) {
    $pcr->binary_path($binpath) or fatal_error(pre($pcr->error));
  }
  else {
    $pcr->url($binpath) or fatal_error(pre($pcr->error));
  }

  my $res = $pcr->design(%atts) or fatal_error(pre($pcr->error));

  $self->primer_results( $res, $segment, $lb, $rb );
}

sub primer_results {
  my ( $self, $res, $segment, $lb, $rb ) = @_;
  my $conf = $self->configuration;
  my $target = $self->focus($segment);
  my $offset = $segment->start;
  my $ref    = $segment->ref;
  my $num    = grep {/^\d+$/} keys %$res;
  
  my $raw_output = pre($res->raw_output);
  $raw_output =~ s/^(SEQUENCE=\w{25}).+$/$1... \(truncated for display only\)/m;

  # Give up if primer3 failed
  fatal_error("No primers found:".pre($raw_output)) unless $res->left;

  my @attributes = qw/ left right startleft startright tmleft tmright
      qual lqual rqual leftgc rightgc lselfany lselfend rselfany rselfend/;
  
  my ( @rows, @feats );
  
  my $text = "This value should be less than 1 for best results but don\'t worry too much";
  #my $Primer_Pair_Quality = 'Primer_Pair_Quality '.a( { -href => 'javascript:void(0)', -title => $text}, '[?]'); 
  my $Primer_Pair_Quality = 'Primer_Pair_Quality '.a( { -href => "javascript:alert(\"$text\")" }, '[?]'); 
  my $spacer = td( {-width => 25}, '&nbsp;');
  
  for my $n ( 1 .. $num ) {
    my %r;
    for (@attributes) {
      $r{$_} = $res->$_($n);
    }
    next unless $r{left};

    $r{prod} = $r{startright} - $r{startleft};
    $r{startleft}  += $offset;
    $r{startright} += $offset;

    for (qw/ qual lqual rqual /) {
      $r{$_} =~ s/^(\S{6}).+/$1/;

      # low primer pair quality warning
      if ( $r{$_} > 1 ) {
        my $msg = quality_warning();
        $msg = "alert('$msg')";
        $r{$_} = a(
          { -href    => 'javascript:void(0)',
            -title   => 'Low quality warning',
            -onclick => $msg
          },
          b( font( { -color => 'red' }, $r{$_} ) )
        );

      }
    }

    push @feats,
        Bio::Graphics::Feature->new(
				    -start => $r{startleft}-20,
				    -stop  => $r{startright}+20,
				    -type  => 'Primer',
				    -name  => "PCR primer set $n" );

    push @rows,
    Tr(
      [ 
	$spacer .
	th(
          { -class => 'searchtitle', -align => 'left' },
          [ qw/Set Primer/, "Sequence (5'->3')", qw/Tm %GC Coord Quality Product/, $Primer_Pair_Quality ]
        ),
	$spacer .
        td(
          [ $n,         'left',        $r{left},  $r{tmleft},
            $r{leftgc}, $r{startleft}, $r{lqual}, '&nbsp;',
            '&nbsp;'
          ]
        ),
	$spacer .
        td(
          [ '&nbsp;',    'right',        $r{right}, $r{tmright},
            $r{rightgc}, $r{startright}, $r{rqual}, $r{prod},
            $r{qual}
          ]
        ),
	$spacer .
        td(
          { -colspan => 9 },
          $self->toggle( {on => 0, override => 1},
		  "PRIMER3-style report for set $n", 
		  primer3_report( $self, $segment, $res, \%r )).br
	   )
	]
       );
  }

  my $featurefile = Bio::Graphics::FeatureFile->new();
  my $options     = {
    bgcolor => 'red',
    glyph   => 'primers',
    height  => 10,
    label   => 1
  };

 $featurefile->set('primers',glyph=>'primers');
 $featurefile->set('primers',label=>'1');
 $featurefile->set('primers',height=>'10');
 $featurefile->set('primers',bgcolor=>'red');


  #$featurefile->add_type( 'Primers' => $options );

  for my $f (@feats) {
    $featurefile->add_feature( $f => 'Primers' );
  }

  my $width = IMAGEWIDTH;
  my $back = Tr( $spacer . td( { -colspan => 9,}, $self->back_button ));
  unshift @rows, $back if @rows > 3;

  my $tlength = $rb - $lb;
  my ($config_html, $map) = $self->configure_form($segment,$target,$lb,$rb,$featurefile);

  unshift @rows, Tr( [ $spacer . td(h1({-align => 'center'},"Predicted PCR primers ") ),
		    $spacer . td($config_html) ] );

  print table(
	      { -style => "width:900px" },
	      [ @rows,
		Tr( $spacer . td( { -colspan => 9, -class => 'searchtitle' }, 
				  $self->toggle( {on => 0, override => 1}, 'PRIMER3 raw output', $raw_output))
		    ),
		$back
		]
	      ), $map;
  exit(0);
}

# GENERATE A PRIMER_3-STYLE REPORT
# contributed by Russell Smithies
# russell.smithies@agresearch.co.nz
sub primer3_report { 
  my $self        = shift;
  my $sub_segment = shift;
  my $sub_res     = shift;
  my %sub_r       = %{ shift @_ };
  my @target      = split( /\,/, $sub_res->TARGET );
  my $start       = $sub_segment->start;
  my $end         = $sub_segment->end;
  my $ref         = $sub_segment->ref;

  # tweak the names to be coords for the target rather than the displayed region
  my $start_name = $start + $target[0];
  my $end_name   = $end + $target[0] + $target[1];
  my $name = "$ref:$start_name..$end_name";

  my $offset;
  if ( ( $sub_r{startright} - $start ) < length( $sub_res->SEQUENCE ) ) {
    $offset = 100;
  }
  else {
    $offset = 0;
  }

  # trim this much off the front of the displayed sequence to keep it a reasonable size
  my $trunc = $sub_r{startleft} - $start - $offset;

  my $rs;
  $rs = "<pre>";
  $rs .= "\n\n";
  $rs .= "No mispriming library specified\n";
  $rs .= "Using 1-based sequence positions\n\n";

  # set width of name field
  my $max_name_length = length( $name . '|RIGHT  ' );
  $rs .= sprintf(
    sprintf( "%s ", '%-' . $max_name_length . 's' )
        . " %5s %5s %4s %5s %5s %4s  %-30s\n",
    'OLIGO', 'start', 'len', 'tm', 'gc%', 'any', '3\'', 'seq', );
  $rs .= sprintf(
    sprintf( "%s ", '%-' . $max_name_length . 's' )
        . " %5d %5d %4s %5s %5s %4s  %-30s\n",
    $name . '|LEFT',        $sub_r{startleft} - $start - $trunc,
    length( $sub_r{left} ), $sub_r{tmleft},
    $sub_r{leftgc},         $sub_r{lselfany},
    $sub_r{lselfend},       $sub_r{left}
  );
  $rs .= sprintf(
    sprintf( "%s ", '%-' . $max_name_length . 's' )
        . " %5d %5d %4s %5s %5s %4s  %-30s\n",
    $name . '|RIGHT',        $sub_r{startright} - $start - $trunc,
    length( $sub_r{right} ), $sub_r{tmright},
    $sub_r{rightgc},         $sub_r{rselfany},
    $sub_r{rselfend},        $sub_r{right}
  );
  $rs .= "\n";
  $rs .= sprintf( "PRODUCT SIZE  : %-4d\n", $sub_r{prod} );
  $rs .= sprintf( "TARGET REGION : %s\n", "$ref:$start_name..$end_name" );
  $rs .= sprintf(
    "TARGETS (start\, len)\*: %d\,%d\n",
    $target[0] - $trunc,
    $target[1]
  );
  $rs .= "\n";

  # mark the primers and target on the alignments track
  my $sub_alignments .= " " x ( $sub_r{startleft} - $start - $trunc );

  # left primer
  $sub_alignments .= ">" x length( $sub_r{left} );
  $sub_alignments .= " " x ( $target[0] - length($sub_alignments) - $trunc );

  # target area
  $sub_alignments .= "*" x $target[1];
  $sub_alignments
      .= " " x ( $sub_r{startright} - $start - length($sub_alignments) -
        length( $sub_r{right} ) - $trunc + 1 );

  # right primer
  $sub_alignments .= "<" x length( $sub_r{right} );

  my $dna = $sub_res->SEQUENCE;

  # trim displayed sequence
  $dna = substr( $dna, $trunc );
  $dna = substr( $dna, 0, ( $sub_r{prod} + $offset + $offset ) );

  # hack to place alignment track below sequence
  $dna =~ s/(.{1,60})/$1;/g;
  my @dna_bits = split( /;/, $dna );
  $sub_alignments =~ s/(.{1,60})/$1;/g;
  my @alignment_bits = split( /;/, $sub_alignments );

  my $i = 0;

  # print sequence and alignments
  while ( $i <= $#dna_bits ) {
    $alignment_bits[$i] ||= '';
    $rs .= sprintf( "%3d %s\n", ( $i * 60 + 1 ), $dna_bits[$i] );
    $rs .= "    " . $alignment_bits[$i] . "\n";
    $rs .= "\n";
    $i++;
  }
  $rs .= "</pre>";
  return $rs;
}

sub unit_label {
  my $value = shift;
        $value >= 1e9 ? sprintf( "%.4g Gbp", $value / 1e9 )
      : $value >= 1e6 ? sprintf( "%.4g Mbp", $value / 1e6 )
      : $value >= 1e3 ? sprintf( "%.4g kbp", $value / 1e3 )
      : sprintf( "%.4g bp", $value );
}

sub new_segment_map {
  my ( $self, $segment, $feats, $lb, $rb ) = @_;

  my $render = $self->renderer;

    my $seg = $render->region->seg;

  #my @tracks      = grep !/overview/, $self->selected_tracks;

  my $config = $self->browser_config;
  my $zoom_levels = $config->setting('zoom levels') || '1000 10000 100000 200000';
  my @zoom_levels = split /\s+/, $zoom_levels;
  my %zoom_labels;
  for my $zoom (@zoom_levels) {
    $zoom_labels{$zoom} = $render->unit_label($zoom);
  }

  my $zoom_menu = $self->zoom_menu($segment);
 
  # if the primer design is done, zoom in to the PCR products
  my $target;

  my @extra_args;

  if ($feats) {

    $zoom_menu = '';

   
    my @feature_types = $feats->types;

    for my $type (@feature_types) {
        my $features = $feats->features($type);
        my %options  = $feats->style($type);
    }    
 

    push @extra_args, ('tracks', $feats);

    $target = $self->focus($segment);
    my ($longest)
        = map {$_->length} sort { $b->length <=> $a->length } $feats->features('Primers');
    $segment = $self->refocus( $segment, $target, $longest+2000 );

  }
  else {

    $target = $self->focus($segment);
  }

  my $postgrid_callback = sub {
    my $gd     = shift;
    my $panel  = shift;
    my $left   = $panel->pad_left;
    my $top    = $panel->top;
    my $bottom = $panel->bottom;

    my ($mstart, $mend) = $panel->location2pixel($target, $target+1);
    my ($hstart, $hend) = $panel->location2pixel($lb,$rb);

    # first shaded
    #if ($feats) {
	unless ( $hend-$hstart < 2 ) {
	$gd->filledRectangle( $left + $hstart,
				$top, $left + $hend,
				$bottom, $panel->translate_color('lightgrey'));
	}
    #}

    # then the red center line
    $gd->filledRectangle( $left + $mstart,
			  $top, $left + $mend,
			  $bottom, $panel->translate_color('red'));
  };

    push @extra_args, ('postgrid', $postgrid_callback);


    #my $panel = $render->render_panel($segment,\%args);
    my $panel = $render->render_panel($segment,\@extra_args);
    
    return ($panel, ' ', $zoom_menu);

}


# center the segment on the target coordinate
sub refocus {
  my ( $self, $segment, $target, $window ) = @_;
  my $db      = $self->database;
  my ($whole_seq) = $db->segment( $segment->ref );
  my $abs_end = $whole_seq->end;

  $window ||= $self->configuration->{span} || $segment->length;

  my $half = int( $window / 2 + 0.5 );
  $target = int( $target + 0.5 );

  # We must not  fall of the ends of the ref. sequence
  my $nstart = $target < $half ? 1 : $target - $half;
  my $nend = $target + $half - 1;
  $nend = $abs_end if $nend > $abs_end;

  ($segment) = $db->segment(
			    -name  => $segment->ref,
			    -start => $nstart,
			    -end   => $nend );
  return $segment;
}

sub _target {
  my $segment = shift;
  my $span    = abs( $segment->end - $segment->start );
  return int( $span / 2 + 0.5 ) + $segment->start;
}

# find the target
sub focus {
  my ( $self, $segment ) = @_;
  my $conf = $self->configuration;
  my $target;

  if ( $target = $conf->{target} ) {
    return $target;
  }

  return $conf->{target} = _target($segment);
}

# slurp the BOULDER_IO params
sub get_primer3_params {
  my $self = shift;

  return %{ $self->{atts} } if $self->{atts};

  for ( grep {/PRIMER_/} param() ) {
    $self->{atts}->{$_} = param($_) if param($_);
    param( $_, '' );
  }

  return %{ $self->{atts} } if $self->{atts};
}

# form elements stolen and modified from the primer3 website
sub primer3_params {
  my $self   = shift;
  my $conf   = $self->configuration;
  my $target = shift;

  my $help = 'http://frodo.wi.mit.edu/cgi-bin/primer3/primer3_www_help.cgi';
  my $msg  = "Format xxx-xxx\\nBy default, the smallest "
      . "product size to flank the feature will be selected\\n"
      . "Use this option to force a particular amplicon size and.or "
      . "reduce computation time";

  my $sr = $conf->{size_range} || '';

  my %table = (
    b(qq(<a name="PRIMER_NUM_RETURN_INPUT" target="_new" href="$help\#PRIMER_NUM_RETURN">
       Primer sets:</a>)
    ),
    qq(<input type="text" size="4" name="PRIMER_NUM_RETURN" value="3">),
    b(qq(<a name="PRIMER_OPT_SIZE_INPUT" target="_new" href="$help\#PRIMER_SIZE">
          Primer Size</a>)
    ),
    qq(Min. <input type="text" size="4" name="PRIMER_MIN_SIZE" value="18">
       Opt. <input type="text" size="4" name="PRIMER_OPT_SIZE" value="20">
       Max. <input type="text" size="4" name="PRIMER_MAX_SIZE" value="27">),
    b(qq(<a name="PRIMER_OPT_TM_INPUT" target="_new" href="$help\#PRIMER_TM">
          Primer Tm</a>)
    ),
    qq(Min. <input type="text" size="4" name="PRIMER_MIN_TM" value="57.0">
       Opt. <input type="text" size="4" name="PRIMER_OPT_TM" value="60.0">
       Max. <input type="text" size="4" name="PRIMER_MAX_TM" value="63.0">),
    b(qq(<a name="PRIMER_PRODUCT_SIZE_RANGE" href="javascript:void(0)"
           onclick="alert('$msg')">Product size range:</a>)
    ),
    qq(<input type="text" size="8" id="product_size_range" name="PRIMER_PRODUCT_SIZE_RANGE" value=$sr>),
    b(qq(<a name="PRIMER_MAX_END_STABILITY_INPUT" target="_new" href="$help\#PRIMER_MAX_END_STABILITY">
       Max 3\' Stability:</a>)
    ),
    qq(<input type="text" size="4" name="PRIMER_MAX_END_STABILITY" value="9.0">),
    b(qq(<a name="PRIMER_PAIR_MAX_MISPRIMING_INPUT" target="_new" href="$help\#PRIMER_PAIR_MAX_MISPRIMING">
       Pair Max Mispriming:</a>)
    ),
    qq(<input type="text" size="4" name="PRIMER_PAIR_MAX_MISPRIMING" value="24.00">),
    b(qq(<a name="PRIMER_GC_PERCENT_INPUT" target="_new" href="$help\#PRIMER_GC_PERCENT">
       Primer GC%</a>)
    ),
    qq(Min. <input type="text" size="4" name="PRIMER_MIN_GC" value="20.0">
       Opt. <input type="text" size="4" name="PRIMER_OPT_GC_PERCENT" value="">
       Max. <input type="text" size="4" name="PRIMER_MAX_GC" value="80.0">),
    b(qq(<a name="PRIMER_SELF_ANY_INPUT" target="_new" href="$help\#PRIMER_SELF_ANY">
       Max Self Complementarity:</a>)
    ),
    qq(<input type="text" size="4" name="PRIMER_SELF_ANY" value="8.00">),
    b(qq(<a name="PRIMER_SELF_END_INPUT" target="_new" href="$help\#PRIMER_SELF_END">
       Max 3\' Self Complementarity:</a>)
    ),
    qq(<input type="text" size="4" name="PRIMER_SELF_END" value="3.00">),
    b(qq(<a name="PRIMER_MAX_POLY_X_INPUT" target="_new" href="$help\#PRIMER_MAX_POLY_X">
       Max Poly-X:</a>)
    ),
    qq(<input type="text" size="4" name="PRIMER_MAX_POLY_X" value="5">)
  );
  return \%table;
}

sub toggle {
  my $self = shift;
  my ($state,$section_head,@body) = @_;
  #my ($label) = $self->browser_config->tr($section_head) || $section_head;
  my ($label) = $self->renderer->tr($section_head) || $section_head;
  #return $self->renderer->toggle_section($state,$label,b($label),@body);
  return $self->toggle_section($state,$label,b($label),@body);
}


#Gbrowse's toggle function isn't displaying the $show_ctrl html for 
#PrimerDesigner when hidden. When a section is minimized, everything 
#including the header disappears making it impossible to re-toggle
#This fixes the problem.
{
no warnings 'redefine';
    sub toggle_section {

    my $self = shift;
    my %config = ref $_[0] eq 'HASH' ? %{shift()} : ();
    my ($name,$section_title,@section_body) = @_;

    my $visible = $config{on};

    my $buttons = $self->renderer->data_source->button_url;
    my $plus  = "$buttons/plus.png";
    my $minus = "$buttons/minus.png";
    my $break = div({-id=>"${name}_break",
		    -style=>$visible ? 'display:none' : 'display:block'
		    },'&nbsp;');

    my $show_ctl = div({-id=>"${name}_show",
			-class=>'ctl_hidden',
			-style=>$visible ? 'display:none' : 'display:inline',
			-onClick=>"visibility('$name',1)"
			},
			img({-src=>$plus,-alt=>'+'}).'&nbsp;'.span({-class=>'tctl'},$section_title));

    my $js = <<"JS";

var d = document.getElementById('$name').style.display;
var i = this.childNodes[1];
if (d == 'inline' || d == 'block') {
    document.getElementById('$name').style.display = 'none';
    i.src = '$plus';
} else {
    document.getElementById('$name').style.display = 'inline';
    i.src = '$minus';
}

JS

    my $hide_ctl = div({-id=>"${name}_hide",
			-class=>'ctl_visible',
			-style=>$visible ? 'display:inline' : 'display:none',
			#-onClick=>"visibility('$name',0)"
			-onClick=> $js
			},
			img({-src=>$minus,-alt=>'-'}).'&nbsp;'.span({-class=>'tctl',-id=>"${name}_title"},$section_title));
    my $content  = div({-id    => $name,
			-style=>$visible ? 'display:inline' : 'display:none',
			-class => 'el_visible'},
			@section_body);
    my @result =  $config{nodiv} ? (div({-style=>'float:left'},
					$show_ctl.$hide_ctl),$content)
		    :$config{tight}? (div({-style=>'float:left;position:absolute;z-index:10'},
					$show_ctl.$hide_ctl).$break,$content)
		    : div($show_ctl.$hide_ctl,$content);
    return wantarray ? @result : "@result";
    }
}

sub quality_warning {
  my $msg = <<END;
Primer-pair penalty (quality score) warning.
BREAK
For best results, a primer-pair should have a quality
score < 1.
BREAK
The score for the pair is the the sum of the scores
for each individual primer.
BREAK
If the high score is due to a departure from optimal primer
GC-content or Tm, the primers are probably OK.
Otherwise, more optimal primers can often be obtained
by adjusting the design parameters (especially
the product size range).
END
  $msg =~ s/\n/ /gm;
  $msg =~ s/BREAK/\\n/g;

  return $msg;
}

sub zoom_menu {
  my $self    = shift;
  my $segment = shift;
  #my $render  = $self->renderer($segment);
  my $render  = $self->renderer;
  return $render->slidertable($segment);
}

sub renderer {
  my $self    = shift;
  my $segment = shift;
  my $config  = $self->browser_config || {};
  my $render  = $self->{render};
  if ($render) {
    $render->current_segment($segment);
    return $render;
  }
  

  my $globals = Bio::Graphics::Browser2->open_globals;

  $self->{render} = PrimerDesigner::Render->new($config);



  $self->{render} = bless $segment, 'PrimerDesigner::Render';

  $self->{render}->current_segment($segment);
  return $self->{render};
}

sub back_button {
  my $url = shift->my_url;
  button( -onclick => "window.location='$url'",
          -name    => 'Return to Browser' );
}

sub fatal_error {
    #my $self = shift;
    print CGI::header('text/plain'),"@_\n";
    exit 0;
}


1;


# A package to override some Bio::Graphics::Browser2::Render
# image mapping methods
#package Bio::Graphics::Browser2::faux;
package PrimerDesigner::Render;
use CGI qw/:standard unescape/;
use warnings;
use strict;
use Carp qw/cluck/;
use Bio::Root::Storable;
use Data::Dumper;

use vars '@ISA';

# controls the resolution of the recentering map
use constant RULER_INTERVALS => 100;
use constant DEFAULT_SEG_SIZE  => 10000;
use constant DEFAULT_FINE_ZOOM => '20%';
use constant BUTTONSDIR        => '/gbrowse/images/buttons';
use constant OVERVIEW_RATIO    => 0.9;
use constant DEBUG             => 0;
use constant DEFAULT_RANGES      => q(100 500 1000 5000 10000 25000 100000 200000 400000);

@ISA = qw/Bio::Graphics::Browser2::Render::HTML/;

sub new {
  my $class    = shift;
  my $browser  = shift;
  my %browser_data = %{$browser};  # just the config data, not the object
  return bless \%browser_data, $class;
}


sub error {
  '';
}

sub make_feat_link {
  my $self = shift;
  my $feat = shift;
  my ($start, $end ) = @_;
  my $fref   = $feat->ref;
  my $fstart = $feat->start;
  my $fend   = $feat->stop;
  $start ||= $fstart;
  $end   ||= $fend;

  # segment >= DEFAULT_SEG_SIZE
  my $padding = int((DEFAULT_SEG_SIZE - $feat->length)/2) + 1;
  my ($pad) = sort {$b<=>$a} 1000, $padding;

  $start  -= $pad;
  $end    += $pad;

  my $p = 'PrimerDesigner';
  my $url = "?plugin=$p;plugin_action=Go;ref=$fref;start=$start;stop=$end;";
  $url   .= "$p.lb=$fstart;$p.rb=$fend";
  
  return $url;
}

sub make_map {
  my $self = shift;
  my ( $boxes, $centering_map, $panel ) = @_;
  my $map = qq(\n<map name="hmap" id="hmap">\n);

  my $topruler = shift @$boxes;
  $map .= $self->make_centering_map($topruler);

  my $bottomruler = pop @$boxes;
  $map .= $self->make_boundary_map($bottomruler);

  my @link_sets;
  my $link_set_idx = 0;

  for my $box (@$boxes) {
    my ( $feat, $x1, $y1, $x2, $y2, $track ) = @$box;
    next unless $feat->can('primary_tag');
    next if $feat->primary_tag eq 'Primer';
    my $fclass = $feat->class || 'feature';
    my $fname  = $feat->name  || 'unnamed';
    my $fstart = $feat->start;
    my $fend   = $feat->stop;
    my $pl     = $panel->pad_left;
    my $half   = int(($topruler->[5]->length/2) + 0.5);

    my $link = $self->make_feat_link( $feat );
    my $href = qq{href="$link"};

    # give each subfeature its own link
    my @parts = $feat->sub_SeqFeature if $feat->can('sub_SeqFeature');
    if ( @parts > 1 ) {
      my $last_end;
      for my $part (sort {$a->start <=> $b->start} @parts) {
        my $pstart = $part->start;
        my $pend   = $part->end;
	my $ptype  = lc $part->primary_tag;

	my $no_overlap = 0;
	# intervals between parts select the whole (aggregate) feature
	$last_end ||= $pend;
	if ($pstart > $last_end) {
	  my $istart    = $last_end + 1;
	  my $iend      = $pstart   - 1;
	  my ($ix1,$ix2) = map { $_ + $pl } $panel->location2pixel( $istart, $iend );

	  # skip it if the box will be less than 2 pixels wide
	  if ($ix2 - $ix1 > 1) {
	    my $title = qq{title="select $fclass $fname"};
	    $map .= qq(<area shape="rect" coords="$ix1,$y1,$ix2,$y2" $href $title/>\n);
	    $no_overlap   = $ix2;
	  }
	}

        my ( $px1, $px2 ) = map { $_ + $pl } $panel->location2pixel( $pstart, $pend );
	$px1++ if $px1 == $no_overlap;

        my $phref = $self->make_feat_link( $part, $pstart, $pend );
        $phref     = qq{href="$phref"};
	my $title  = qq{title="select this $ptype"};
	$map .= qq(<area shape="rect" coords="$px1,$y1,$px2,$y2" $phref $title/>\n);

	$last_end = $pend;
      }
    }
    else {
      my $title = qq{title="select $fclass $fname"};
      $map .= qq(<area shape="rect" coords="$x1,$y1,$x2,$y2" $href $title/>\n);
    }
  }

  $map .= "</map>\n";

  return $map;
}

sub make_centering_map {
  my $self   = shift;
  my $ruler  = shift;
  my $bottom = shift; # true if this is the lower scale-bar

  my ( $rfeat, $x1, $y1, $x2, $y2, $track ) = @$ruler;

  my $rlength = $x2 - $x1 or return;
  my $length  = $rfeat->length;
  my $start   = $rfeat->start;
  my $stop    = $rfeat->stop;
  my $panel   = $track->panel;
  my $pl      = $panel->pad_left;
  my $middle;

  if ($bottom) {
    $middle = param('PrimerDesigner.target');
    $middle ||= int(($start+$stop)/2 + 0.5);
  }

  # divide into RULER_INTERVAL intervals
  my $portion  = $length / RULER_INTERVALS;
  my $rportion = $rlength / RULER_INTERVALS;

  my $ref    = $rfeat->seq_id;
  my $source = $self->source;
  my $plugin = 'PrimerDesigner';
  my $offset = $start - int( $length / 2 );

  my @lines;

  while (1) {
    my $end    = $offset + $length;
    my $center = $offset + $length/2;
    my $sstart = $center - $portion/2;
    my $send   = $center + $portion/2;
    
    $_ = int $_ for ($start,$end,$center,$sstart,$send);

    my ( $X1, $X2 )
        = map { $_ + $pl } $panel->location2pixel( $sstart, $send );

    # fall of the end...
    last if $center >= $stop + ($length / 2);

    my ($url,$title_text);

    my $p = 'PrimerDesigner';
    my $rb = param("$p.rb");
    $rb = $1 if $rb && $rb =~ /\=(\d+)/;
    my $lb = param("$p.lb");
    $lb = $1 if $lb && $lb =~ /\=(\d+)/;
    my $target = param("$p.target");
    
    # left side of the lower ruler
    if ($middle && $sstart <= $middle) {
      $url = "?ref=$ref;start=$start;stop=$stop;plugin=$plugin;plugin_action=Go;$p.lb=$center;";
      $url .= "$p.rb=$rb;" if $rb;
      $url .= "$p.target=$target;" if $target;
      $url = qq(href="$url");
      $title_text = "set left target boundary to $center";
    }
    # right side of the lower ruler
    elsif ($middle) {
      $url = "?ref=$ref;start=$start;stop=$stop;plugin=$plugin;plugin_action=Go;$p.rb=$center";
      $url .= ";$p.lb=$lb" if $lb;
      $url .= "$p.target=$target;" if $target;
      $url = qq(href="$url");
      $title_text = "set right target boundary to $center";
    }
    # top ruler
    else {
      $url = "?ref=$ref;start=$offset;stop=$end;plugin=$plugin;plugin_action=Go;";

      # We can retain an off-center target if it is still reasonable
      if ($target && $target > $offset + 1000 && $target < $end - 1000 ) {
	$url .= "$p.target=$target;";
      }
      if ($lb  && $lb > $offset + 500) {
	$url .= "$p.lb=$lb;";
      }
      if ($rb  && $rb < $end - 500) {
        $url .= "$p.rb=$rb;";
      }

      $url = qq(href="$url");
      $title_text = "recenter at $center";
    }
    my $map_line
        = qq(<area shape="rect" coords="$X1,$y1,$X2,$y2" $url );
    $map_line .= qq(title="$title_text" alt="recenter" />\n);
    push @lines, $map_line;

    $offset += int $portion;
  }

  return join '', @lines;
}

sub make_boundary_map {
  my $self = shift;
  $self->make_centering_map(@_, 1);
}

sub current_segment {
  my $self = shift;
  my $segment = shift;
  return $self->{segment} = $segment if $segment;
  return $self->{segment};
}

sub unit_label {
  my ( $self, $value ) = @_;
  my $unit    = $self->setting('units')        || 'bp';
  my $divider = $self->setting('unit_divider') || 1;
  $value /= $divider;
  my $abs = abs($value);
  my $label;
        $label = $abs >= 1e9 ? sprintf( "%.4g G%s", $value / 1e9, $unit )
      : $abs >= 1e6  ? sprintf( "%.4g M%s", $value / 1e6, $unit )
      : $abs >= 1e3  ? sprintf( "%.4g k%s", $value / 1e3, $unit )
      : $abs >= 1    ? sprintf( "%.4g %s",  $value,       $unit )
      : $abs >= 1e-2 ? sprintf( "%.4g c%s", $value * 100, $unit )
      : $abs >= 1e-3 ? sprintf( "%.4g m%s", $value * 1e3, $unit )
      : $abs >= 1e-6 ? sprintf( "%.4g u%s", $value * 1e6, $unit )
      : $abs >= 1e-9 ? sprintf( "%.4g n%s", $value * 1e9, $unit )
      : sprintf( "%.4g p%s", $value * 1e12, $unit );
  if (wantarray) {
    return split ' ', $label;
  }
  else {
    return $label;
  }
}

sub slidertable {
  my $self    = shift;
  my $state   = $self->state;
  my $segment    = shift;

  # try to avoid reopening the database -- recover segment
  # and whole segment lengths from our stored state if available
  my $span  = $state->{view_stop} - $state->{view_start} + 1;
  my $max   = $self->thin_whole_segment->length;

  my $buttonsDir    = $self->data_source->button_url;

  my $half_title = $self->data_source->unit_label(int $span/2);
  my $full_title = $self->data_source->unit_label($span);
  my $half       = int $span/2;
  my $full       = $span;
  my $fine_zoom  = $self->get_zoomincrement();

  my $fine_point = do { no warnings 'numeric'; $fine_zoom/100 };

  my $show   = $self->translate('Show').' ';

  my @lines =
    (image_button(
		    -src     => "$buttonsDir/green_l2.gif",
		  -name=>"left $full",
		  -title   => "left $full_title",
		  #-onClick => "Controller.scroll('left', 1)"
		  -onClick => "oPrimerDesigner.scroll('left', 1)"
     ),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/green_l1.gif",-name=>"left $half",
		  -title=>"left $half_title",
		  #-onClick => "Controller.scroll('left', 0.5)"
		  -onClick => "oPrimerDesigner.scroll('left', 0.5)"
     ),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/mminus.png",
		  -name=>"zoom out $fine_zoom",
		  -style=>'background-color: transparent',
		  -title=>"zoom out $fine_zoom",
		  #-onClick => "Controller.update_coordinates(this.name)"
		  -onClick => "oPrimerDesigner.scroll('zoom', $fine_point+1)" 
     ),
     '&nbsp;',
     $self->zoomBar($span,$max,$show),
     #$self->zoomBar($segment),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/mplus.png",
		  -name=>"zoom in $fine_zoom",
		  -style=>'background-color: transparent',
		  -title=>"zoom in $fine_zoom",
		  #-onClick => "Controller.update_coordinates(this.name)",
		  -onClick => "oPrimerDesigner.scroll('zoom',1-$fine_point)" 
     ),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/green_r1.gif",-name=>"right $half",
		  -title=>"right $half_title",
		  #-onClick => "Controller.scroll('right', 0.5)"
		  -onClick => "oPrimerDesigner.scroll('right', 0.5)"
     ),
     '&nbsp;',
     image_button(-src=>"$buttonsDir/green_r2.gif",-name=>"right $full",
		  -title=>"right $full_title",
		  #-onClick => "Controller.scroll('right', 1)"
		  -onClick => "oPrimerDesigner.scroll('right', 1)"
     ),
     '&nbsp;',
    );

  my $str	= join('', @lines);
  return span({-id=>'span'},$str);

}

sub get_zoomincrement {
  my $self = shift;
  my $zoom = $self->setting('fine zoom') || DEFAULT_FINE_ZOOM;
  $zoom;
}

sub zoomBar {
  my $self = shift;
  my ($length,$max,$item_label) = @_;
  $item_label ||= '';

  my %seen;
  my @r         = sort {$a<=>$b} $self->data_source->get_ranges();
  $max         *= $self->data_source->unit_divider;

  my @ranges	= grep {!$seen{$self->data_source->unit_label($_)}++ && $_<=$max} sort {$b<=>$a} @r,$length;
  my %labels    = map {$_=>$item_label.$self->data_source->unit_label($_)} @ranges;
  return popup_menu(-class   => 'searchtitle',
		    -name    => 'span',
		    -values  => \@ranges,
		    -labels  => \%labels,
		    -default => $length,
		    -force   => 1,
		    -onChange => "oPrimerDesigner.scroll('set span',this.options[this.selectedIndex].value)",
		   );
}

#NML: holdovers from Bio::Graphics::Browser
#need to see if there are contemporary versions in new modules
sub fatal_error {
    #my $self = shift;
    print CGI::header('text/plain'),"@_\n";
    exit 0;
}

sub render_panel {

    my $render = shift;
    my $segment = shift;
    #my $postgrid = shift;
    my $extra_args = shift;
    my @panels;

    my $region   = $render->region;
    my $features = $region->features;
    my $title    = $render->generate_title($features);
    my $output;
    my @post_load = $render->get_post_load_functions;

    $output .= $render->render_html_start($title,@post_load);
    $output .= $render->render_busy_signal;

    push @panels, $output;

    #my %extra_args = @$extra_args;
    #my $postgrid = $extra_args{'postgrid'};

    my $scale_bar_html = $render->scale_bar( $segment, 'detail', $extra_args );

    push @panels, 
	div({-id=>'primer_panel', -style=>'padding:12px;position:relative'},
	    $scale_bar_html,
	    $render->render_detailview_panels($segment)
	);

    my $main_page = join('',@panels);

    my $tracks        = $render->render_tracks_section;

    return $render->sender_tabbed_pages($main_page,$tracks);

    return $main_page;

}

sub sender_tabbed_pages {
    my $self = shift;
    my ($main_html,$tracks_html,$community_tracks_html,$custom_tracks_html,$settings_html,) = @_;
    my $uses_database = $self->user_tracks->database;
    
    my $main_title             = $self->translate('MAIN_PAGE');
    my $tracks_title           = $self->translate('SELECT_TRACKS');
    my $community_tracks_title = $self->translate('COMMUNITY_TRACKS_PAGE') if $uses_database;
    my $custom_tracks_title    = $self->translate('CUSTOM_TRACKS_PAGE');
    my $settings_title         = $self->translate('SETTINGS_PAGE');

    my $html = '';
    $html   .= div({-id=>'tabbed_section', -class=>'tabbed'},
		   #div({-id=>'tabbed_menu',-class=>'tabmenu'},
	           span({style=>'display:none', id=>'main_page_select'},               $main_title),
	           span({style=>'display:none', id=>'track_page_select'},              $tracks_title),
		   #$uses_database? span({id=>'community_tracks_page_select'},   $community_tracks_title) : "",
		   #span({id=>'custom_tracks_page_select'},      $custom_tracks_title),
		   #span({id=>'settings_page_select'},           $settings_title),
	       #),
	   div({-id=>'main_page',            -class=>'tabbody'}, $main_html),
	   #div({-id=>'track_page',           -class=>'tabbody'}, $tracks_html),
	   #$uses_database?div({-id=>'community_tracks_page',-class=>'tabbody'}, $community_tracks_html) : "",
	   #div({-id=>'custom_tracks_page',   -class=>'tabbody'}, $custom_tracks_html),
	   #div({-id=>'settings_page',        -class=>'tabbody'}, $settings_html),
	);
    return $html;
}

1;
