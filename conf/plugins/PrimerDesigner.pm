# $Id: PrimerDesigner.pm,v 1.6 2006-08-18 02:31:37 sheldon_mckay Exp $

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

This plugin contains an additional package Bio::Graphics::Browser::faux.
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

# A package to override some Bio::Graphics::Browser
# image mapping methods
package Bio::Graphics::Browser::faux;
use Bio::Graphics::Browser::Render;
use CGI qw/:standard unescape/;
use warnings;
use strict;

use vars '@ISA';

# controls the resolution of the recentering map
use constant RULER_INTERVALS => 100;

@ISA = qw/Bio::Graphics::Browser::Render/;

sub new {
  my $class = shift;
  my $self  = shift;
  return bless $self, $class;
}

sub make_link {
  my $self = shift;
  my ( $feat, $class, $name, $start, $end ) = @_;
  my $fstart = $feat->start;
  my $fend   = $feat->stop;
  my $ref    = $feat->seq_id;
  my $type   = $feat->primary_tag;
  $class ||= $feat->class;
  $name  ||= $feat->name;
  $start ||= $fstart;
  $end   ||= $fend;
  $type  ||= 'null';

  my $p = 'PrimerDesigner';
  my $url = "?plugin=$p;plugin_action=Go;ref=$ref;start=$start;stop=$end;";
  $url   .= "$p.tfeat=$type+$class+$name+$fstart..$fend;$p.lb=$fstart;$p.rb=$fend";
  
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
    my $ftype  = $feat->primary_tag;
    my $fstart = $feat->start;
    my $fend   = $feat->stop;
    my $fclass = $feat->class;
    my $flabel = ucfirst $ftype;
    my $fname  = $feat->name;
    my $pl     = $panel->pad_left;
    my $half   = int( $topruler->[5]->length / 2 + 0.5 );

    my $link = $self->make_link( $feat, $fclass, $fname );
    my $href = qq{href="$link"};

    # give each subfeature its own link
    my @parts = $feat->sub_SeqFeature if $feat->can('sub_SeqFeature');
    if ( @parts > 1 ) {
      my $last_end;
      for my $part (sort {$a->start <=> $b->start} @parts) {
        my $ptype  = $part->primary_tag;
        my $pstart = $part->start;
        my $pend   = $part->end;

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

        my $phref = $self->make_link( $part, $fclass, $fname, $pstart, $pend );
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
  my $bottom = shift;

  my ( $rfeat, $x1, $y1, $x2, $y2, $track ) = @$ruler;

  my $rlength = $x2 - $x1 or return;
  my $length  = $rfeat->length;
  my $start   = $rfeat->start;
  my $stop    = $rfeat->stop;
  my $scale   = $length / $rlength;
  my $panel   = $track->panel;
  my $pl      = $panel->pad_left;
  my $middle  = int(($start+$stop)/2 + 0.5) if $bottom;

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
    my $center = $offset + int( $length / 2 );
    my $sstart = $center - int( $portion / 2 );
    my $send   = $center + int( $portion / 2 );
    my ( $X1, $X2 )
        = map { $_ + $pl } $panel->location2pixel( $sstart, $send );

    last if $center >= $stop + $length / 2;
    my ($url,$title_text);

    if ($middle && $sstart <= $middle) {
      my $rb = param('PrimerDesigner.rb');
      my $pname = "PrimerDesigner.lb";
      $url = "?ref=$ref;start=$start;stop=$stop;plugin=$plugin;plugin_action=Go;$pname=$center";
      $url .= ";PrimerDesigner.rb=$rb" if $rb;
      $title_text = "set left target boundary to $center";
    }
    elsif ($middle) {
      my $lb = param('PrimerDesigner.lb');
      my $pname = "PrimerDesigner.rb";
      $url = "?ref=$ref;start=$start;stop=$stop;plugin=$plugin;plugin_action=Go;$pname=$center";
      $url .= ";PrimerDesigner.lb=$lb" if $lb;
      $title_text = "set right target boundary to $center";
    }
    else {
      $url = "?ref=$ref;start=$offset;stop=$end;plugin=$plugin;plugin_action=Go;recenter=1";
      $title_text = "recenter at $center";
    }
    my $map_line
        = qq(<area shape="rect" coords="$X1,$y1,$X2,$y2" href="$url" );
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

1;

package Bio::Graphics::Browser::Plugin::PrimerDesigner;

use strict;
use Bio::PrimerDesigner;
use Bio::PrimerDesigner::Tables;
use Bio::Graphics::Browser::Plugin;
use Bio::Graphics::Browser::Util;
use Bio::Graphics::Browser::Render;
use Bio::Graphics::Feature;
use Bio::Graphics::FeatureFile;
use CGI qw/:standard escape/;
use CGI::Pretty 'html3';
use CGI::Carp 'fatalsToBrowser';
use CGI::Toggle;
use Math::Round 'nearest';

use constant BINARY            => 'primer3';
use constant BINPATH           => '/usr/local/bin';
use constant METHOD            => 'local';
use constant IMAGE_PAD         => 25;
use constant MAXRANGE          => 300;                # max product size range
use constant IMAGEWIDTH        => 800;
use constant DEFAULT_SEG_SIZE  => 10000;
use constant DEFAULT_FINE_ZOOM => '10%';
use constant BUTTONSDIR => '/gbrowse/images/buttons/';
use constant FINEZOOM   => '20%';

use vars '@ISA';

@ISA = qw / Bio::Graphics::Browser::Plugin /;

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
  'Design';
}

sub mime_type {
  'text/html';
}

sub is_pan {
  return 1 if grep /^left\s+\d+|^right\s+\d+/, param();
  return 1 if param('recenter');
}

sub is_zoom {
  return param('span') unless param('configured'); 
}

sub reconfigure {
  my $self = shift;
  my $conf = $self->configuration;
    
  $conf->{target_region} = undef;
  $conf->{lb}            = undef;
  $conf->{rb}            = undef;

  my $tfeat  = $self->config_param('tfeat') unless is_pan();
  my $lb     = $self->config_param('lb')    unless is_pan();
  my $rb     = $self->config_param('rb')    unless is_pan();

  if ($lb && $rb) {
    $tfeat = qq(null null null $lb..$rb);
  }

  if ($tfeat) {
    my ( $type, $class, $name, $coords ) = split /\s+/, $tfeat;

    # backslash creeping into URL -- have to track this down...
    $coords =~ s/[^0-9.]//g;

    my ( $tstart, $tend ) = split /\.\./, $coords;
    ( $tstart, $tend ) = ( $tend, $tstart ) if $tstart > $tend;
    my $min_size = abs( $tend - $tstart ) + 40;
    my $max_size = $min_size + MAXRANGE;

    # round to nearest 50 bp
    $conf->{size_range} = join '-', map {$_||=50} nearest(50, $min_size, $max_size);
    $conf->{target_region} = [$class, $name, $tstart,$tend];
    
    $lb ||= $tstart;
    $rb ||= $tend;
  }

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
  my ($segment) = @{ $self->segments };

  unless ( $segment and ref $segment ) {
    my $url = $self->my_url;
    error "No sequence region selected";

    print p(
      button(
        -onclick => "window.location='$url'",
        -name    => 'Return to Browser'
      )
    );
    exit;
  }

  my $start  = $segment->start;
  my $end    = $segment->end;
  my $name   = $segment->ref;
  my $length = unit_label( $segment->length );

  my $browser = $self->browser($segment);
  my $header  = $browser->header;
  my $html    = $header if $header;

  my ( $image, $map, $zoom_menu ) = $self->segment_map($segment);
  my $map_text = $self->map_header;
  
  
  $html .= h2("Showing $length from $name, positions $start to $end");
  $html .= table(
    Tr(
      { -class => 'searchtitle' },
      [ th($map_text) . th($zoom_menu), 
	td( { -colspan => 2 }, $image ) ]
    )
  );
  $html .= $map;

  print $html;
  exit;
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
  $self->reconfigure;
  my $target_region  = $conf->{target_region};
  my ($exclude, $ptarget);

  # redefine the segment to center the target and trim excess DNA
  my $segment_size;
  if ( $conf->{span} && !param('configured')) {
    $segment_size = $conf->{span};
  }
  elsif ($target_region) {
    my $len = $target_region->[3] - $target_region->[2];
    ($segment_size) = sort {$b<=>$a} ($len+2000, DEFAULT_SEG_SIZE);
  }
  else {
    $segment_size = DEFAULT_SEG_SIZE;
  }

  my $target       = $self->focus($segment);
  $segment = $self->refocus( $segment, $target, $segment_size );
  $target_region ||= ['null', 'null', $target, $target];
  my $tfeat_length = $target_region->[3] - $target_region->[2];
  $tfeat_length ||= 1;

  my $offset = $segment->start - 1;
  my $tstart = $target_region->[2] - $offset;
  $ptarget = join ',', $tstart,1;
  $exclude = join ',', $tstart, $tfeat_length;

  # boiler plate
  my $style_sheet = $self->browser_config->setting('stylesheet')
      || '/gbrowse/gbrowse.css';
  print start_html( -style => $style_sheet, -title => 'PCR Primers' );
  my $banner = $self->browser_config->header || '';
  print $banner;

  # design the primers
  $self->design_primers( $segment, $ptarget, $exclude, $target_region )
      if param('configured') && $self->get_primer3_params();

  # or print the second config form
  my @feature_types = $self->selected_features;
  my @args          = ( -types => \@feature_types );
  my @feats         = $segment->features(@args);

  # primer design parameters
  my $atts = $self->primer3_params($target_region);

  # sort by distance from target
  @feats = map { $_->[1] }
      sort { abs( $a->[0] - $target ) <=> abs( $b->[0] - $target ) }
      map { [ ( ( $_->end - $_->start ) / 2 + $_->start ), $_ ] } @feats;

  my $start  = $segment->start;
  my $end    = $segment->end;
  my $ref    = $segment->ref;
  my $name   = "$ref:$start..$end";

  my $length = unit_label( $segment->length );
  my $html  = h2("Showing $length from $ref, positions $start to $end");

  my $width = IMAGEWIDTH;
  my ( $image, $map, $zoom_menu )
      = $self->segment_map( $segment, undef, $target_region );

  my $message = '';
  my $action = self_url();
  $action =~ s/\?.+//;

  my $tfeat = $conf->{tfeat} || "null null ".$target_region->[2].'..'.$target_region->[3];
  undef $tfeat if $target_region->[3] - $target_region->[2] < 2;

  my $lb    = $conf->{lb};
  my $rb    = $conf->{rb};

  $html .= start_form(
    -method => 'POST',
    -name   => 'mainform',
    -action => $action
      )
      . hidden( -name => 'plugin',        -value => 'PrimerDesigner' )
      . hidden( -name => 'plugin_action', -value => 'Go' )
      . hidden( -name => 'ref', -value => $segment->ref )
      . hidden( -name => 'start', -value => $segment->start )
      . hidden( -name => 'stop', -value => $segment->stop )
      . hidden( -name => $self->config_name('tfeat'), -value => $tfeat)
      . hidden( -name => $self->config_name('lb'), -value => $lb)
      . hidden( -name => $self->config_name('rb'), -value => $rb);

  my $map_text = $self->map_header;

  my $zone;
  if ($tfeat_length && $tfeat_length > 1) {
    $zone = toggle( 'Targetting information', 
		    font( {-size => -1}, 
			  ul( li("PCR primers will flank the shaded region."),
			      li("The size of the PCR product can be controlled via the 'Product size range' option below"),
			      li("Click on the bottom scalebar to adjust the target region; ".
			         "clicking to the left or right of the red line will change the boundary ".
			         "on that side"),
			      li(),
			      li("Clicking on a sequence will focus the target region on that feature"),
			      li("For aggregate features (eg gene models or spliced transcripts), click on an ".
				 "individual part of the feature will select that part"),
			      li("Clicking on the connecter between parts will select the whole feature"))
			  ),
		    1,     # default to 'on'
		    'OFF'  # do not override cookies
		    ) . br;
  }

  $html .= table(
    { -style => "width:" . ( $width + 20 ) . "px" },
    Tr(
      { -class => 'searchtitle' },
      [ th($map_text) . th($zoom_menu),
        td( { -class => 'searchbody', -colspan => 2 }, $image . br),
	td( { -class => 'searchbody', -colspan => 2}, $zone )
      ]
    )
  );
  $html .= $map;

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

  $html .= table( { -style => "width:${width}px" }, Tr( \@rows ) );

  my $url = $self->my_url;

  $html .= br
      . submit( -name => 'configured', -value => 'Design Primers' )
      . '&nbsp;'
      . reset
      . '&nbsp;'
      . $self->back_button
      . end_form();

  print $html;

}

sub back_button {
  my $url = shift->my_url;
  button( -onclick => "window.location='$url'",
	  -name    => 'Return to Browser' );
}

sub design_primers {
  my ( $self, $segment, $ptarget, $exclude, $target_region ) = @_;
  my $conf   = $self->configuration;
  my %atts   = $self->get_primer3_params($target_region);
  my $target = $self->focus($segment);

  if (!$ptarget && $segment->length > DEFAULT_SEG_SIZE) {
    $segment = refocus($segment, $target, DEFAULT_SEG_SIZE);
    my $offset = $segment->start - 1;
    $ptarget = ($target-$offset).",1";
  }

  $exclude ||= $ptarget;
  
  # API change alert!!
  my $dna = $segment->seq;
  if ( ref $dna && $dna->can('seq') ) {
    $dna = $dna->seq;
  }
  elsif ( ref $dna ) {
    print h1(
      "Unsure what to do with object $dna. I was expecting a sequence string"
    );
    exit;
  }
  elsif ( !$dna ) {
    print h1("Error: There is no DNA sequence in the database");
    exit;
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
  my $pcr = Bio::PrimerDesigner->new(
    program => BINARY,
    method  => METHOD
      )
      or die Bio::PrimerDesigner->error;

  my $binpath = BINPATH;
  my $method = $binpath =~ /http/i ? 'remote' : METHOD;

  if ( $method eq 'local' && $binpath ) {
    $pcr->binary_path($binpath) or die $pcr->error;
  }
  else {
    $pcr->url($binpath) or die $pcr->error;
  }

  my $res = $pcr->design(%atts) or die $pcr->error;

  $self->primer_results( $res, $segment, $target_region );
  exit;
}

# PRINT THE RESULTS
sub primer_results {
  my ( $self, $res, $segment, $target_region ) = @_;
  my $offset = $segment->start;
  my $ref    = $segment->ref;
  my $num    = grep {/^\d+$/} keys %$res;
  
  my $conf = $self->configuration;
  my $raw_output = pre($res->raw_output);
  $raw_output =~ s/^(SEQUENCE=\w{25}).+$/$1... \(truncated for display only\)/m;
  fatal_error "No primers found:<br>$raw_output" unless $res->left;

  my @attributes = qw/ left right startleft startright tmleft tmright
      qual lqual rqual leftgc rightgc /;
  
  my ( @rows, @feats );
  
  my $text = "This value should be less than 1 for best results but don\'t worry too much";
  my $Primer_Pair_Quality = 'Primer_Pair_Quality '.a( { -href => '#', -title => $text}, '[?]'); 
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
          toggle( font({-color=>'green'},
		       "PRIMER3-style report for set $n"), 
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

  $featurefile->add_type( 'Primers' => $options );

  for my $f (@feats) {
    $featurefile->add_feature( $f => 'Primers' );
  }

  my $width = IMAGEWIDTH;
  my $back = Tr( $spacer . td( { -colspan => 9,}, $self->back_button ));
  unshift @rows, $back if @rows > 3;

  if (@rows) {
    my ( $img, $map )
        = $self->segment_map( $segment, $featurefile, $target_region );
    print table(
      { -width => $width+100 },
      [ Tr(
          td(
            { -colspan => 9, align => 'center' },
            h1("Predicted PCR primers ")
          )
        ),
        Tr( td( { -colspan => 10, align => 'center' }, $img ) ),
        @rows,
        Tr( $spacer . td( { -colspan => 9, -class => 'searchtitle' }, 
			  toggle('PRIMER3 raw output', $raw_output))
	    ),
	$back
      ]
    ), $map;
  
  }

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
  my @target_feat = split( /\s/, $self->config_param('tfeat') );
  my $name;

  # tweak the names to be coords for the target rather than the displayed region
  my $start_name = $start + $target[0];
  my $end_name   = $end + $target[0] + $target[1];

  # if a target was selected from a chebckbox, use it as the identifier
  if ( $target_feat[0] ) {
    $name = $target_feat[0];
  }
  else {
    # otherwise, use the coords as the identifier
    $name = "$ref:$start_name..$end_name";
  }
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

# cooerce the browser object into a new class to override
# some image map-related methods
sub browser {
  my $self    = shift;
  my $segment = shift;
  if ($self->{browser}) {
    $self->{browser}->current_segment($segment);
    return $self->{browser};
  }

  my $br = $self->browser_config;
  eval { require Bio::Graphics::Browser::faux; 1 };
  $self->{browser} = Bio::Graphics::Browser::faux->new($br);
  $self->{browser}->current_segment($segment); 
  return $self->{browser};
}

sub segment_map {
  my ( $self, $segment, $feats, $target ) = @_;

  my @tracks      = grep !/overview/, $self->selected_tracks;
  my $browser     = $self->browser($segment);
  my $zoom_levels = $browser->setting('zoom levels') || '1000 10000 100000 200000';
  my @zoom_levels = split /\s+/, $zoom_levels;
  my %zoom_labels;
  for my $zoom (@zoom_levels) {
    $zoom_labels{$zoom} = $browser->unit_label($zoom);
  }
  my $zoom_menu = $self->zoom_menu($segment);
  my $lb = $self->configuration->{lb};
  my $rb = $self->configuration->{rb};

  # if the primer design is done, zoom in to the PCR products
  my $bullseye;
  if ($feats) {
    $bullseye = int( $segment->length / 2 ) + $segment->start;
    my ($longest)
        = sort { $b->length <=> $a->length } $feats->features('Primers');
    $segment = $self->refocus( $segment, $bullseye, $longest->length + 2000 );
  }
  elsif ( !$target ) {
    $bullseye = $self->focus($segment);
    $target = [ 'null', 'null', $bullseye, $bullseye ];
  }
  else {
    $bullseye = $self->focus($segment);
  }

  unshift @tracks, 'Primers' if $feats;
  my ( $target_region, $postgrid_callback, $hilite_callback );

  my ( $class, $name, $tstart, $tend ) = @$target;
  my $ref          = $segment->ref;

  if ($lb || $rb) {
    $lb ||= $bullseye;
    $rb ||= $bullseye;

    $postgrid_callback = sub {
      my $gd     = shift;
      my $panel  = shift;
      my $left   = $panel->pad_left;
      my $top    = $panel->top;
      my $bottom = $panel->bottom;

      my ($mstart, $mend) = $panel->location2pixel($bullseye, $bullseye+1);
      my ($hstart, $hend) = $panel->location2pixel($lb, $rb);

      # order matters
      $gd->filledRectangle( $left + $hstart,
                            $top, $left + $hend,
                            $bottom, $panel->translate_color('#DCDCDC'));

      $gd->filledRectangle( $left + $mstart,
			    $top, $left + $mend,
			    $bottom, $panel->translate_color('red'));
    };
  }
  else {
    $tstart ||= $bullseye;
    $tend   ||= $bullseye;
    my $hcolor = $tstart == $tend ? 'red' : '#DCDCDC';
    $postgrid_callback = sub {
      my $gd     = shift;
      my $panel  = shift;
      my $left   = $panel->pad_left;
      my $top    = $panel->top;
      my $bottom = $panel->bottom;
      my ( $start, $end ) = $panel->location2pixel( $tstart, $tend );
      $gd->filledRectangle( $left + $start,
			    $top, $left + $end,
			    $bottom, $panel->translate_color($hcolor));
    };
  }

  my $hilite_color = $browser->setting('hilite color') || 'slateblue';

  $hilite_callback = sub {
    my $f = shift or return;
    return unless $f->class eq $class;
    return unless $f->name  eq $name;
    return $hilite_color;
  };

  # we aill be adding custom scale_bars ourselves
  my %feature_files;
  $feature_files{Primers} = $feats if $feats;
  my $topscale    = Bio::Graphics::FeatureFile->new;
  my $bottomscale = Bio::Graphics::FeatureFile->new;
  $feature_files{topscale} = $topscale;
  $feature_files{bottomscale} = $bottomscale;

  my $options     = { glyph   => 'arrow',
		      double  => 1,
		      tick    => 2,
		      label   => 1,
		      units        => $browser->setting('units') || '',
		      unit_divider => $browser->setting('unit_divider') || 1 };

  my $options2 = {%$options};
  $options2->{no_tick_label} = 1 if @tracks < 3;

  $topscale->add_type( topscale => $options );
  $bottomscale->add_type( bottomscale => $options2 );

  my $toptext = 'Click on this scalebar to recenter the image';
  my $bottomtext = 'Click on this scalebar to create or adjust the target boundaries';

  my $scalebar1 = Bio::Graphics::Feature->new( -start => $segment->start,
					       -stop  => $segment->end,
					       -type  => 'topscale',
					       -name  => $toptext,
					       -ref   => $segment->ref );
  my $scalebar2 = Bio::Graphics::Feature->new( -start => $segment->start,
                                               -stop  => $segment->end,
                                               -type  => 'bottomscale',
					       -name  => $bottomtext,
					       -ref   => $segment->ref );
  
  $topscale->add_feature( $scalebar1 => 'topscale' );
  $bottomscale->add_feature( $scalebar2 => 'bottomscale' );
  unshift @tracks, 'topscale';
  push @tracks, 'bottomscale';

  my @options = ( segment          => $segment,
		  do_map           => 1,
		  do_centering_map => 1,
		  tracks           => \@tracks,
		  postgrid         => $postgrid_callback,
		  hilite_callback  => $hilite_callback,
		  noscale          => 1,
		  keystyle         => 'beneath');
  
  push @options, ( feature_files => \%feature_files );
  
  my ( $image, $image_map ) = $browser->render_html(@options);

  my $url = 'plugin=PrimerDesigner;plugin_action=Go;';

  my @map = split "\n", $image_map;
  for (@map) {
    next;
    next unless /href/;
    s/href=\"\S*\?/href=\"/;
    my ($seg) = my ($old_href) = /href="(\S+?)"/;
    my ($name) = /(\S+?:\d+\.\.\d+)/;
    $seg =~ s/nav4.+//;
    my $new_href = $url . ( $name ? "name=$name" : $seg );
    s/$old_href/\?$new_href/;
  }

  return ( $image, join( "\n", @map ), $zoom_menu );
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
  my ( $self, $segment, $target ) = @_;
  my $conf = $self->configuration;
  delete $conf->{tfeat};
  delete $conf->{target};

  if ($target) {
    return $conf->{target} = $target;
  }

  if ( $target = $self->config_param('target') ) {
    return $conf->{target} = $target;
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
  my $label = shift;
  my $text  = shift;
  my $on = shift || 0;
  my $or = shift || 1; # default is ON
  undef $or if $or eq 'OFF';

  return toggle_section( { on => $on, override => $or }, b($label), $text);
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
  my $browser = $self->browser($segment);

  $browser->setting(
    BUTTONSDIR => ( $browser->setting('buttons') || BUTTONSDIR ) );

  return $browser->slidertable;
}

