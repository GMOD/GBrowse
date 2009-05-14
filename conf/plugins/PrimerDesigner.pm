# $Id: PrimerDesigner.pm,v 1.3.6.1.6.22 2009-05-14 21:43:47 sheldon_mckay Exp $

=head1 NAME

Bio::Graphics::Browser::Plugin::PrimerDesigner -- a plugin to design PCR primers with primer3

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
For aggregate features such as gene models, etc, there is a mouseover menu
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
package Bio::Graphics::Browser::Plugin::PrimerDesigner;

use strict;

use Bio::PrimerDesigner;
use Bio::PrimerDesigner::Tables;
use Bio::Graphics::Browser::Plugin;
use Bio::Graphics::Browser::Util;
use Bio::Graphics::Feature;
use Bio::Graphics::FeatureFile;
use CGI qw/:standard escape html3/;
use CGI::Carp 'fatalsToBrowser';
use CGI::Toggle;

use constant PROGRAM          => 'primer3';
use constant BINPATH          => '/usr/local/bin';
use constant METHOD           => 'local';
use constant MAXRANGE         => 300;
use constant IMAGEWIDTH       => 800;
use constant DEFAULT_SEG_SIZE => 10000;
use constant ZOOM_INCREMENT   => 1000;
use constant JS               => '/gbrowse/js';
use constant IMAGES           => '/gbrowse/images/buttons';
use constant CSS              => '/gbrowse/gbrowse.css';
use constant MAX_SEGMENT      => 1_000_000;

use vars '@ISA';

@ISA = qw / Bio::Graphics::Browser::Plugin /;

# modperl cleanup
END {
  CGI::Delete_all();
}

sub name {
  my $self = shift;
  #$self->browser_config->tr('PCR primers') || 'PCR primers'; 
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
  my $self = shift;
  $self->browser_config->tr('Design') || 'Design';
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

  $conf->{width} = $self->browser_config->plugin_setting('image width') || IMAGEWIDTH;
  $conf->{isPCR} = $self->browser_config->plugin_setting('ispcr');  

  $conf->{size_range} = undef;
  $conf->{target}     = undef;
  $conf->{lb}         = undef;
  $conf->{rb}         = undef;

  my $target_region = param('target_region');
  my ($target, $lb,$rb);
  if ($target_region) {
    ($lb,$rb) = $target_region =~ /^\S+\:(-?\d+)\.\.(-?\d+)$/;
  }
  else {
    $lb     = param('lb') || $self->config_param('lb');
    $rb     = param('rb') || $self->config_param('rb');
  }

  if ($lb && $rb) {
    my $max_range = $self->browser_config->plugin_setting('max range') || MAXRANGE; 
    my $min_size = $rb - $lb + 40;
    my $max_size = $min_size + $max_range;

    # round to nearest 50 bp
    $conf->{size_range} = join '-', map {$_||=50} nearest(50, $min_size, $max_size);

    # make sure target is always centered in the selected region
    $target = int( ($lb+$rb)/2 );
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
  my $self = shift;
  my ($segment,$target,$lb,$rb,$feats) = @_;
  ($segment) = @{ $self->segments } unless $segment;
  $segment ||= fatal_error("This plugin requires a sequence region");
  my $browser = $self->browser_config;
  my $conf = $self->configuration;

  my $no_buttons = 1 if !($lb || $rb)  || $feats;
  

  # we need our own headers, so redirect config and go straight to dump
  my $url = url(-query_string => 1);
  my $cfg = $browser->tr('Configure');
  my $go  = $browser->tr('Go');
  if ($url =~ /$cfg/) {
    $url =~ s/$cfg/$go/;
    return "<script type='text/javascript'>window.location='$url';</script>";
  }

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
  my ( $image, $zoom_menu )
      = $self->segment_map( \$segment, $feats, $lb, $rb );
  my $message = '';

  my $start  = $segment->start;
  my $end    = $segment->end;
  my $ref    = $segment->ref;
  my $name   = $conf->{name} || "$ref:$start..$end";

  my $length = $self->browser_config->unit_label( $end - $start );

  my $html = h2("Showing $length from $ref, positions $start to $end");

  $html .= hidden( -name => 'plugin',        -value => 'PrimerDesigner' )
        .  hidden( -name => 'plugin_action', -value => 'Go' )
        .  hidden( -name => 'ref',           -value => $segment->ref )
        .  hidden( -name => 'start',         -value => $segment->start )
        .  hidden( -name => 'stop',          -value => $segment->stop )
	.  hidden( -name => 'nocache',       -value => 1 );
  
  $html .=  hidden( -name => 'lb', -value => $lb||'');
  $html .=  hidden( -name => 'rb', -value => $rb||'');
  $html .=  hidden( -name => 'target', -value => $target||'');

  my $map_text = $self->map_header;

  my $on = $feats ? 0 : 1;
#  my $no_target = li("There currently is no target region selected.")
#      if ($rb - $lb) < 3;
#  my $has_buttons = li("The size of potential PCR products can be adjusted via the 'Product size range' option below")
#      unless $no_buttons;
#  my $flanked = $no_target ? 'red line' : 'shaded region';
#  my $boundaries = li("The boundaries of the shaded target region can be adjusted by clicking on the lower scalebar")
#      unless $no_target;
#  my $click_feat = $no_target ? li("Click on a sequence feature to select")
#      : li("Click on a different sequence feature to change the selection");
      

#  my $zone = $self->toggle( { on => $on, override => 0 },
#		     'Targetting information',
#		     font( {-size => -1},
#			   ul( $no_target || '', 
#			       li("PCR primers will flank the $flanked."),
#			       $click_feat || '',
#			       $boundaries || '',
#			       $has_buttons || ''
#			   ) )
#		     ) . br;

  my $rows;
  if ($map_text) {
    $rows = [th($map_text) . th($zoom_menu),
	     td( { -class => 'searchbody', -colspan => 2 }, $image . br)];
  }
  else {
    $rows = td( { -class => 'searchbody', -colspan => 2 }, $image . br);
  }
  $html .= table(
    { -style => "width:${table_width}px" },
    Tr( { -class => 'searchtitle' }, $rows )
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
    
    my $buttons = br
	. submit( -name => 'configured', -value => 'Design Primers' )
	. '&nbsp;'
	. reset
	. '&nbsp;'
	. $self->back_button;
    $html .= div({-id => 'topButtons'},$buttons) .
	table( { -style => "width:${table_width}px" }, Tr( \@rows ) ).
	$buttons;
  }
  
  (my $action = self_url()) =~ s/\?.+//;
  print start_form(
    -method => 'POST',
    -name   => 'mainform',
    -action => $action
      ), $html;  
  $self->segment_info($segment);
  print end_form, end_html;
}

sub map_header {
  return '' if param('configured');
  return "Press 'Design Primers' or click and drag on the ruler to select a PCR target";
}

sub dump {
  my ( $self, $segment ) = @_;
  my $conf = $self->configuration;
  $self->reconfigure;

  my $js            = $self->browser_config->relative_path_setting('js')     || JS;
  my $img           = $self->browser_config->relative_path_setting('images') || IMAGES;
  my $css           = $self->browser_config->setting('stylesheet')           || CSS;
  $css .= "/gbrowse.css" unless $css =~ /gbrowse.css/;

  # dumpers provide their own headers, so make sure boiler plate
  # stuff is included
  my $head = <<END;
<script src="$js/yahoo-dom-event.js" type="text/javascript"></script>
<script src="$js/rubber.js" type="text/javascript"></script>
<script src="$js/primerSelect.js" type="text/javascript"></script>
<script src="$js/balloon.config.js" type="text/javascript"></script>
<script src="$js/balloon.js" type="text/javascript"></script>
<script>
var balloon = new Balloon;
  balloon.images              = '$img/balloons';
  balloon.delayTime = 200;
</script>
END

  print start_html( 
		    -style  => $css, 
		    -title  => 'PCR Primers', 
		    -onload => "Primers.prototype.initialize()", 
		    -head   => $head,
		    -gbrowse_images => $img,
		    -gbrowse_js     => $js);

  print $self->browser_config->header;

  my $target = $self->focus($segment);
  my $lb = $conf->{lb} || $target;
  my $rb = $conf->{rb} || $target;

  # check for a zoom request
  my $segment_size = $self->is_zoom;

  # Make room if target region is not too close to the ends
  my ($new_start,$new_end);
  my ($edge)  = sort {$a <=> $b} (500,$segment->length/10);
  if ($rb >= $segment->end - $edge) {
    $new_end = $rb + $edge;
  }
  if ($lb <= $segment->start +$edge) {
    $new_start = $lb - $edge;
  }
  if ($new_start || $new_end) {
    ($segment) = $self->database->segment( -name  => $segment->ref,
					 -start => ($new_start || $segment->start),
					 -end   => ($new_end   || $segment->end) );
    $segment_size = $segment->length;
  }

  # design the primers if required
  $self->design_primers( $segment, $lb, $rb)
      if param('configured') && $self->get_primer3_params();

  # or print the config form
  $self->configure_form($segment,$target,$lb,$rb);
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
  my $default_size = $self->browser_config->plugin_setting('default segment') 
      || DEFAULT_SEG_SIZE;
  if (!$ptarget && $segment->length > $default_size) {
    $segment = $self->refocus($segment, $target, $default_size);
  }

  my $dna = $segment->seq;
  if ( ref $dna && $dna->can('seq') ) {
    $dna = $dna->seq;
  }
  elsif ( ref $dna ) {
    fatal_error("Unsure what to do with object $dna. I was expecting a sequence string");
  }

  if ( !$dna ) {
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


  my $binpath = $self->browser_config->plugin_setting('binpath') || BINPATH;
  my $method  = $self->browser_config->plugin_setting('method')  || METHOD;

  $method  = 'remote' if $binpath =~ /http/i;

  my $pcr = Bio::PrimerDesigner->new( program => PROGRAM,
                                      method  => $method );
  $pcr or fatal_error(pre(Bio::PrimerDesigner->error));

  if ( $method eq 'local' && $binpath ) {
    $pcr->binary_path($binpath) or fatal_error(pre($pcr->error));
  }
  else {
    $pcr->url($binpath) or fatal_error(pre($pcr->error));
  }

  my $res = $pcr->design(%atts) or fatal_error(pre($pcr->error));

  $self->primer_results( $res, $segment, $lb, $rb);
}

sub primer_results {
  my ( $self, $res, $segment, $lb, $rb) = @_;
  my $conf = $self->configuration;
  my $isPCR_url = $conf->{isPCR};
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
  
  my $text = "This primer pair quality value should be less than 1 for best results but don&#39;t worry too much";
  my $Primer_Pair_Quality = 'Primer_Pair_Quality '.a( { -style=>"color:blue;cursor:pointer", -onmouseover => "balloon.showTooltip(event,'$text',0,350)"}, '[?]'); 
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


   

   
   push @feats, Bio::Graphics::Feature->new( -ref   => $segment->ref,
					     -start => $r{startleft}-20,
					     -end   => $r{startright}+20,
					     -type  => 'primers',
                                             -name  => "set $n ");

    my $isPCR = '';
    if ($isPCR_url) {
      $isPCR = 
        $spacer .
	td( {-colspan => 9},
	    $self->toggle( {on => 0, override => 1},
                           "UCSC In-Silico PCR results for primer set $n",
			   iframe( {
			     -src => "$isPCR_url&wp_size=10000&wp_target=genome&wp_f=$r{left}&wp_r=$r{right}&Submit=submit",
                             -width => 800,
                             -height => 400,
                             -border => 1
                               },
                                   "Iframes must not be supported in your browser.  Time to upgrade..."
                                   )
                           )
            );
    }

    my $cols = 
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
	 $spacer.
	 td(
	    { -colspan => 9 },
	    $self->toggle( {on => 0, override => 1},
			   "PRIMER3-style report for set $n", 
			   primer3_report( $self, $segment, $res, \%r ))
	    ),
	 $isPCR . br
	 ];

    push @rows, Tr($cols);

  }

  my $featurefile = Bio::Graphics::FeatureFile->new();
  my $options     = {
    bgcolor => 'red',
    glyph   => 'primers',
    height  => 10,
    label   => 1,
    label_position => 'left',
    sort_order => 'name'
  };

  $featurefile->add_type( 'Primers' => $options );

  for my $f (@feats) {
    $featurefile->add_feature( $f => 'Primers' );
  }

  my $width = IMAGEWIDTH;
  my $back = Tr( $spacer . td( { -colspan => 9,}, $self->back_button ));
  unshift @rows, $back if @rows > 3;

  my $tlength = $rb - $lb;
  my $config_html = $self->configure_form($segment,$target,$lb,$rb,$featurefile);

  unshift @rows, Tr( [ $spacer . td(h1({-align => 'center'},"Predicted PCR primers ") ) ] );
#		    $spacer . td($config_html) ] );
  print table(
	      { -style => "width:900px" },
	      [ @rows,
		Tr( $spacer . td( { -colspan => 9, -class => 'searchtitle' }, 
				  $self->toggle( {on => 0, override => 1}, 'PRIMER3 raw output', $raw_output))
		    ),
		$back
		]
	      ), end_html;
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
  $rs = "<pre style='background:whitesmoke;border:1px solid black;padding-left:25px'>";
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

sub segment_map {
  my ( $self, $segment, $feats, $lb, $rb ) = @_;
  my $conf        = $self->configuration;
  my @tracks      = grep !/overview/, $self->selected_tracks;

  my $config = $self->browser_config;

  my $zoom_levels = $config->setting('zoom levels') || '1000 10000 100000 200000';
  my @zoom_levels = split /\s+/, $zoom_levels;
  my %zoom_labels;
  for my $zoom (@zoom_levels) {
    $zoom_labels{$zoom} = $self->browser_config->unit_label($zoom);
  }
  my $zoom_menu = $self->zoom_menu($$segment);

  # if the primer design is done, zoom in to the PCR products
  my $target;
  if ($feats) {
    $target = $self->focus($$segment);
    my ($longest)
        = map {$_->length} sort { $b->length <=> $a->length } $feats->features('Primers');
    $$segment = $self->refocus( $$segment, $target, $longest+2000 );
  }
  else {
    $target = $self->focus($$segment);
  }

  unshift @tracks, 'Primers' if $feats;
  my $postgrid_callback;
  my $ref = $$segment->ref;

  $postgrid_callback = sub {
    my $gd     = shift;
    my $panel  = shift;
    my $left   = $panel->pad_left;
    my $top    = $panel->top;
    my $bottom = $panel->bottom;

    my ($mstart, $mend) = $panel->location2pixel($target, $target+1);
    my ($hstart, $hend) = $panel->location2pixel($lb,$rb);

    # first shaded
    unless ( $hend-$hstart < 2 ) {
      $gd->filledRectangle( $left + $hstart,
			    $top, $left + $hend,
			    $bottom, $panel->translate_color('lightgrey'));
    }

    # then the red center line
    $gd->filledRectangle( $left + $mstart,
			  $top, $left + $mend,
			  $bottom, $panel->translate_color('red'));
  };

  my %feature_files;
  $feature_files{Primers} = $feats if $feats;
  my $panel_options = { 
    -width           => $conf->{width},
    section          => '',
    segment          => $$segment,
    tracks           => \@tracks,
    postgrid         => $postgrid_callback,
    keystyle         => 'none',
    drag_n_drop      => 0,
    feature_files    => \%feature_files
      };
  
  my $html = $config->render_panels($panel_options);

  return (div({-id => 'panels'},$html), $zoom_menu);
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
    qq(<input type="text" size="8" name="PRIMER_PRODUCT_SIZE_RANGE" value=$sr>),
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
  my ($label) = $self->browser_config->tr($section_head) || $section_head;
  return toggle_section($state,$label,b($label),@body);
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
  my $conf = $self->browser_config;
  return $self->slidertable($segment,1);
}

sub back_button {
  my $url = shift->my_url;
  button( -onclick => "window.location='$url'",
          -name    => 'Return to Browser' );
}

sub slidertable {
  my $self       = shift;
  my $segment    = shift;
  my $small_pan  = shift;    
  my $buttons    = $self->browser_config->relative_path_setting('buttons');
  my $span       = $small_pan ? int $segment->length/2 : $segment->length;
  my $half_title = $self->browser_config->unit_label( int $span / 2 );
  my $full_title = $self->browser_config->unit_label($span);
  my $half       = int $span / 2;
  my $full       = $span;
  my $fine_zoom  = $self->get_zoomincrement();
  Delete($_) foreach qw(ref start stop);
  my @lines;
  push @lines, (
		image_button(
			     -src    => "$buttons/green_l2.gif",
			     -name   => "left $full",
			     -border => 0,
			     -title  => "left $full_title"
			     ),
		image_button(
			     -src    => "$buttons/green_l1.gif",
			     -name   => "left $half",
			     -border => 0,
			     -title  => "left $half_title"
			     ),
		'&nbsp;',
		image_button(
			     -src    => "$buttons/minus.gif",
			     -name   => "zoom out $fine_zoom",
			     -border => 0,
			     -title  => "zoom out $fine_zoom"
			     ),
		'&nbsp;', $self->zoomBar($segment), '&nbsp;',
		image_button(
			     -src    => "$buttons/plus.gif",
			     -name   => "zoom in $fine_zoom",
			     -border => 0,
			     -title  => "zoom in $fine_zoom"
			     ),
		'&nbsp;',
		image_button(
			     -src    => "$buttons/green_r1.gif",
			     -name   => "right $half",
			     -border => 0,
			     -title  => "right $half_title"
			     ),
		image_button(
			     -src    => "$buttons/green_r2.gif",
			     -name   => "right $full",
			     -border => 0,
			     -title  => "right $full_title"
			     ),
		);
  return join( '', @lines );
}


sub get_zoomincrement {
  my $self = shift;
  my $zoom = $self->browser_config->setting('zoom increment') || ZOOM_INCREMENT;
  $zoom;
}

sub zoomBar {
  my $self    = shift;
  my $segment = shift;
  my $conf = $self->browser_config;
  my ($show)  = $conf->tr('Show');
  my %seen;
  my @ranges = grep { !$seen{$_}++ } sort { $b <=> $a } ($segment->length, $conf->get_ranges());
  my %labels = map { $_ => $show . ' ' . $conf->unit_label($_) } @ranges;

  return popup_menu(
    -class    => 'searchtitle',
    -name     => 'span',
    -values   => \@ranges,
    -labels   => \%labels,
    -default  => $segment->length,
    -force    => 1,
    -onChange => 'document.mainform.submit()',
  );
}

sub _hide {
  my ($name,$value) = @_;
  print hidden( -name     => $name,
                -value    => $value,
                -override => 1 ), "\n";
}

sub segment_info {
  my ($self,$segment) = @_;
  my $conf     = $self->configuration;
  my $config   = $self->browser_config;
  my $settings = $self->page_settings;
  my $pad_left   = $config->setting('pad_left')  || $config->image_padding;
  my $pad_right  = $config->setting('pad_right') || $config->image_padding;

  _hide(segment              => $segment->ref .':'. $segment->start .'..'. $segment->end);
  _hide(image_padding        => $pad_left);
  _hide(details_pixel_ratio  => $segment->length/$conf->{width});
  _hide(detail_width         => $conf->{width} + $pad_left + $pad_right);
  _hide(max_segment          => MAX_SEGMENT);
}


# nearest function appropriated from Math::Round
sub nearest {
  my $targ = abs(shift);
  my $half = 0.50000000000008;
  my @res  = map {
    if ($_ >= 0) { $targ * int(($_ + $half * $targ) / $targ); }
    else { $targ * POSIX::ceil(($_ - $half * $targ) / $targ); }
  } @_;

  return (wantarray) ? @res : $res[0];
}

