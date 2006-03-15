# $Id: PrimerDesigner.pm,v 1.5 2006-03-15 11:18:04 sheldon_mckay Exp $

=head1 NAME

Bio::Graphics::Browser::Plugin::PrimerDesigner -- a plugin to design PCR primers with primer3

=head1 SYNOPSIS

This module is not used directly

=head1 DESCRIPTION

PrimerDesigner.pm uses the Bio::PrimerDesigner API for primer3 to design
PCR primers for features or target coordinates in gbrowse.

=head1 PRIMER3 is *nix-specific
  
On unix-like systems, compile a primer3 (v. 0.9) binary executable for your 
OS and copy it to the default path '/usr/local/bin'.  An alternate path can be 
specified as follows in the configuration file


[PrimerDesigner:plugin]
binpath = /usr/local/mybin
method  = local

=head1 primer3 for other platforms

Primer3 can be used in a platform independent manner via the Bio::PrimerDesigner
API.  To specify remote access to primer3:

[PrimerDesigner:plugin]
url    = http://some_host/cgi-bin/primerdesigner.cgi
mrthod = remote

The URL should point to a *nix host that has Bio::PrimerDesigner and the
script "primerdesigner.cgi" (a CGI wrapper for the primer3 binary) installed.

=head1 Designing Primers

=head2 Targeting a feature or coordinate

The target for PCR primer design is selected by clicking on an image map and 
(optionally) further refined by selecting an individual feature that overlaps the 
selected sequence coordinate.

=head2 Design Paramaters

The Provided  set of reasonable default primer attributes will work in most 
cases.  Product size will vary by target feature size.  A suggested size-range
is added to the form based on the sixe of the nearest target feature.  If this field
is left black,  a series of increasing PCR product sizes is cycled until 
products big enough to flank the target feature are found.  This will not 
necessarily find the best primers, just the first ones that produce a big 
enough product to flank the target.  If the primers are flagged as low quality,
more optimal optimal primers may be found by specifying a specific size-range.

=head1 FEEDBACK

See the GMOD website for information on bug submission http://www.gmod.org.

=head1 AUTHOR - Sheldon McKay

Email smckay@bcgsc.bc.ca

=head1 CONTRIBUTORS - Russel Smithies

Email russell.smithies@agresearch.co.nz

=head1 SEE ALSO

Bio::PrimerDesigner (www.cpan.org)
primer3 (http://frodo.wi.mit.edu/primer3/primer3_code.html)

=cut

package Bio::Graphics::Browser::Plugin::PrimerDesigner;

use Bio::PrimerDesigner;
use Bio::PrimerDesigner::Tables;
use Bio::Graphics::Browser::Plugin;
use CGI::Pretty qw/:standard escape/;
use CGI::Carp qw/fatalsToBrowser/;
use CGI::Toggle;
use strict;

use Data::Dumper;

use constant BINARY => 'primer3';

use vars '@ISA', '$CONFIG';

@ISA = qw / Bio::Graphics::Browser::Plugin /;

sub name {
  'PCR primers';
}

sub description {
  p(      "This plugin uses Bio::PrimerDesigner and PRIMER3 to "
        . "design PCR primers to amplify selected features or sequences.  "
	. "It was written by Sheldon McKay and Russel Smithies" );
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

sub reconfigure {
  my $self = shift;
  my $conf = $self->configuration;

  my $target = $self->config_param('target');
  my $tfeat  = $self->config_param('tfeat');
  my $exclude;

  if ($tfeat) {
    my ( $tstart, $tend ) = $tfeat =~ /(\d+)\.\.(\d+)/;
    ( $tstart, $tend ) = ( $tend, $tstart ) if $tstart > $tend;
    $exclude = "$tstart," . ( $tend - $tstart );
    $target = $tstart + int( ( $tend - $tstart ) / 2 );
  }

  $conf->{target}  = $target;
  $conf->{exclude} = $exclude ? $exclude : '';
  $conf->{name}    = $self->config_param('name');
  $self->configuration($conf);
}

sub configure_form {
  my $self      = shift;
  my ($segment) = @{ $self->segments };
  my $start     = $segment->start;
  my $end       = $segment->end;
  my $name      = $segment->ref;
  my $length    = unit_label( $segment->length ) . 'bp';

  my $html = h2("Showing $length from $name, positions $start to $end")
      . h3(
    font { -color => 'black' },
    'Click on a feature or map-location '
        . 'to select a target region for PCR primers'
      );

  $html .= $self->segment_map($segment);
  print $html;
  exit;
}

sub dump {
  my ( $self, $segment ) = @_;
  my $conf   = $self->configuration;
  my $target = $self->set_focus($segment) || $conf->{target};

  # redefine the segment to center the target and trim excess DNA
  $segment = $self->refocus( $segment, $target );

  # design the primers
  $self->design_primers( $segment, $conf )
      if $self->get_primer3_params();

  # or print the form
  print "<head><link rel=stylesheet type=text/css"
      . " href=/gbrowse/gbrowse.css /></head>\n";

  my @feature_types = $self->selected_features;
  my @args          = ( -types => \@feature_types );
  my @feats         = $segment->contained_features(@args);

  # sort by distance from target
  @feats = map { $_->[1] }
      sort { abs( $a->[0] - $target ) <=> abs( $b->[0] - $target ) }
      map { [ ( ( $_->end - $_->start ) / 2 + $_->start ), $_ ] } @feats;

  my $start  = $segment->start;
  my $end    = $segment->end;
  my $ref    = $segment->ref;
  my $name   = "$ref:$start..$end";
  my $length = unit_label( $segment->length ) . 'bp';

  my $html = h2("Showing $length from $ref, positions $start to $end")
      . '<table style="width:800px"><tr class="searchtitle">'
      . '<th>Click on a feature or map-location '
      . 'to move the target region for PCR primers</th></tr><tr><td>';

  $html .= $self->segment_map($segment) . br;

  param( $self->config_name('name'), $name );

  $html .= start_form( -method => 'POST' )
      . hidden( -name => 'plugin',        -value => 'PrimerDesigner' )
      . hidden( -name => 'plugin_action', -value => 'Go' )
      . hidden( -name => $self->config_name('name') );

  my $target_field = textfield(
    -size  => 8,
    -name  => $self->config_name('target'),
    -value => $target
  );

  $html .= h3("PCR primers will target position $target_field");

  # feature based target regions
  my @f;
  for my $f (@feats) {
    my ( $s, $e ) = ( $f->start, $f->end );
    ( $s, $e ) = ( $e, $s ) if $s > $e;
    next if $e < ( $target - 3000 ) || $s > ( $target + 3000 );
    my $tag  = $f->method;
    my $name = $f->name;
    my $size = $e - $s;
    push @f, "$name $tag: $s..$e Size: $size bp";
    $self->{range} ||= "$size-".($size+500);
  }
  if (@f) {
    my $checkbox .= radio_group(
      -name   => $self->config_name('tfeat'),
      -values => \@f,
      -rows   => 4
    );

    # override stylesheet for table width
    my $pixels = 400 + ( int( ( @f / 3 ) + 0.5 ) * 400 ) . 'px';
    $checkbox =~ s/table/table style="width:$pixels"/;
    $html
        .= h3( 'Select a feature to target (optional)...' . br . $checkbox );
  }

  $html .= '</td></tr><tr class="searchtitle">';

  # primer design parameters
  my $atts = $self->primer3_params();
  my @col1 = grep {/Primer|Tm|Product/} keys %$atts;
  my @col2 = grep { !/Primer|Tm|Product/ } keys %$atts;

  @col1 = (
    ( grep { $atts->{$_} =~ /Opt\./ } @col1 ),
    ( grep { $atts->{$_} !~ /Opt\./ } @col1 )
  );

  $html
      .= '<th>Primer3 Parameters</th></tr><tr><td><table style="width:800px">';
  for ( 0 .. 4 ) {
    $html .= Tr(
      td(
        [ $col1[$_], $atts->{ $col1[$_] }, $col2[$_], $atts->{ $col2[$_] } ]
      )
    );
  }
  $html .= '</table></td></tr></table>';

  my $url = self_url();
  $url =~ s/\?.+/\?name=$segment/;

  $html .= br
      . submit( -name => 'configured', -value => 'Design Primers' )
      . '&nbsp;'
      . reset
      . '&nbsp;'
      . button(
    -onclick => "window.location='$url'",
    -name    => 'Return to Browser'
      )
      . end_form();

  print $html;

}

sub design_primers {
  my ( $self, $segment, $conf ) = @_;
  my %atts    = $self->get_primer3_params;
  my $exclude = $conf->{exclude};
  my $target  = $conf->{target};
  my $offset  = $segment->start - 1;
  $exclude =~ s/(\d+)/$1 - $offset/e;
  $target = $exclude || ( $target - $offset ) . ',1';
  my $dna = $segment->seq;

  # unless a product size range range is specified, just keep looking
  # until we find some primers that flank the target
  my $size_range = join ' ', qw/
      100-300 301-400 401-500 501-600 601-700 701-800 801-900
      901-1000 1001-1200 1201-1400 1401-1600 1601-1800 1801-2000
      2001-2400 2401-2600 2601-2800 2801-3200 3201-3600 3601-4000/;

  $atts{seq}      = $dna;
  $atts{id}       = $segment->ref;
  $atts{target}   = $target;
  $atts{excluded} = $exclude if $exclude;
  $atts{PRIMER_PRODUCT_SIZE_RANGE} ||= $size_range;

  my $browser_conf = $self->browser_config;
  my $binpath      = $browser_conf->plugin_setting('binpath');
  my $method       = $browser_conf->plugin_setting('method');
  my $url          = $browser_conf->plugin_setting('url');
  my $primer3      = $browser_conf->plugin_setting('binary') || BINARY;

  # get a PCR object
  my $pcr = Bio::PrimerDesigner->new(
				     program => $primer3,
				     method  => $method
				     )
      or die Bio::PrimerDesigner->error;

  if ( $method eq 'local' && $binpath ) {
    $pcr->binary_path($binpath) or die $pcr->error;
  }
  elsif ($url) {
    $pcr->url($url) or die $pcr->error;
  }
  else {
    die "Either a path to the primer3 binary or a remote URL must be specified in".
        " the configuration\n";
  }

  my $res = $pcr->design(%atts) or die $pcr->error;

  $self->primer_results( $res, $segment );
  exit;
}

# PRINT THE RESULTS
sub primer_results {
  my ( $self, $res, $segment ) = @_;
  my $offset = $segment->start;
  my $ref    = $segment->ref;
  my $num    = grep {/^\d+$/} keys %$res;

  print start_html('Primer design results');

  my $conf = $self->configuration;

  print h2("No primers found"), pre( $res->raw_output ) and exit
      unless $res->left;

  my @attributes = qw/ left right startleft startright tmleft tmright
      qual lqual rqual leftgc rightgc /;

  my @rows;

  my $img = $self->segment_map( $segment, $res );
  $img .= ";style=PCR+glyph=primers+bgcolor=red+height=10";

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
        my $msg = "Primer-pair penalty (quality score) $r{$_}\\n"
            . "For best results, a primer-pair should have a quality "
            . "score of < 1.\\nThe score for the pair is the "
            . "the sum of the score for each individual primer.\\n"
            . "If the high score is due to a departure from optimal primer "
            . "GC-content or Tm, the primers are probably OK.  "
            . "Otherwise, more optimal primers can often be obtained "
            . "by adjusting the design parameters (especially the product "
            . "size-range).\\n";
        $msg = "alert('$msg')";
        $r{$_} = a(
          { -href    => 'javascript:void(0)',
            -onclick => $msg
          },
          b( font( { -color => 'red' }, $r{$_} ) )
        );

      }
    }

    $img .= ";add=$ref+PCR+Primer_set_$n+$r{startleft}..$r{startright}";

    push @rows,
        Tr(
      [ td(
          { -bgcolor => 'khaki' },
          [ map { font( { -color => 'black' }, b($_) ) }
                qw/Set Primer Sequence Tm %GC Coord Quality Product Primer_Pair_Quality/
          ]
        ),
        td(
          [ $n,         'left',        $r{left},  $r{tmleft},
            $r{leftgc}, $r{startleft}, $r{lqual}, '&nbsp;',
            '&nbsp;'
          ]
        ),
        td(
          [ '&nbsp;',    'right',        $r{right}, $r{tmright},
            $r{rightgc}, $r{startright}, $r{rqual}, $r{prod},
            $r{qual}
          ]
        ),
        td(
          { -bgcolor => 'white', -colspan => 9 },
          [ toggle($n,primer3_report( $self, $segment, $res, \%r )) ]
        )
      ]
        );

  }

  if (@rows) {
    $img = img( { -src => $img } );
    my $region = $segment->ref . ' ' . $segment->start . '..' . $segment->end;
    print h2("Primer Design Results for region $region"),
        table(
	      { -bgcolor => 'khaki', -width => 760 },
      [ Tr( td( { -colspan => 8 }, $img ) ), @rows, ]
        );
  }
}

sub toggle {
  my $n = shift;
  my $title = "Primer3 report for primer set $n";
  my @body    = @_;
  $CGI::Toggle::next_id++;
  return toggle_section( { on => 0, override => 1 }, $title, @body );
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

 #tweak the names to be coords for the target rather than the displayed region
  my $start_name = $start + $target[0];
  my $end_name   = $end + $target[0] + $target[1];

  #if a target was selected from a chebckbox, use it as the identifier
  if ( $target_feat[0] ) {
    $name = $target_feat[0];
  }
  else {

    #otherwise, use the coords as the identifier
    $name = "$ref:$start_name..$end_name";
  }
  my $offset;
  if ( ( $sub_r{startright} - $start ) < length( $sub_res->SEQUENCE ) ) {
    $offset = 100;
  }
  else {
    $offset = 0;
  }

#trim this much off the front of the displayed sequence to keep it a reasonable size
  my $trunc = $sub_r{startleft} - $start - $offset;

  my $rs;
  $rs = "<pre>";
  $rs .= "\n\n";
  $rs .= "No mispriming library specified\n";
  $rs .= "Using 1-based sequence positions\n\n";

  #set width of name field
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

  #mark the primers and target on the alignments track
  my $sub_alignments .= " " x ( $sub_r{startleft} - $start - $trunc );

  #left primer
  $sub_alignments .= ">" x length( $sub_r{left} );
  $sub_alignments .= " " x ( $target[0] - length($sub_alignments) - $trunc );

  #target area
  $sub_alignments .= "*" x $target[1];
  $sub_alignments
      .= " " x ( $sub_r{startright} - $start - length($sub_alignments) -
        length( $sub_r{right} ) - $trunc + 1 );

  #right primer
  $sub_alignments .= "<" x length( $sub_r{right} );

  my $dna = $sub_res->SEQUENCE;

  #trim displayed sequence
  $dna = substr( $dna, $trunc );
  $dna = substr( $dna, 0, ( $sub_r{prod} + $offset + $offset ) );

  #hack to place alignment track below sequence
  $dna =~ s/(.{1,60})/$1;/g;
  my @dna_bits = split( /;/, $dna );
  $sub_alignments =~ s/(.{1,60})/$1;/g;
  my @alignment_bits = split( /;/, $sub_alignments );

  my $i = 0;

  #print sequence and alignments
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
        $value >= 1e9 ? sprintf( "%.4g G", $value / 1e9 )
      : $value >= 1e6 ? sprintf( "%.4g M", $value / 1e6 )
      : $value >= 1e3 ? sprintf( "%.4g k", $value / 1e3 )
      : sprintf( "%.4g ", $value );
}

sub segment_map {
  my ( $self, $segment, $res ) = @_;
  my @tracks = $self->selected_tracks;
  push @tracks, 'target';
  my $offset = $segment->start - 1;
  my $start  = $res ? ( $res->startleft - 500 + $offset ) : $segment->start;
  my $stop   = $res ? ( $res->startright + 500 + $offset ) : $segment->stop;

  my $name = $segment->ref . ":$start..$stop";
  my $url  = self_url();
  $url =~ s/\?.+//g;
  my $furl = $url;
  $url =~ s:cgi-bin/gbrowse:cgi-bin/gbrowse_img:;
  $url .= "?name=$name;width=700;type=add+" . join '+', @tracks;

  return $url if $res;

  my $factor = $segment->length / 800;

  # Unstick sticky CGI parameters
  param( 'plugin_action',     'Go' );
  param( 'name',              $name );
  param( 'conversion_factor', $factor );

  start_form( -method => 'POST', -action => $furl )
      . hidden( -name => 'plugin_action' )
      . hidden( -name => 'plugin' )
      . hidden( -name => 'name' )
      . hidden( -name => 'conversion_factor' )
      . image_button( { -src => $url, -name => 'map', -border => 0 } )
      . end_form();

}

# center the segment on the target coordinate
sub refocus {
  my ( $self, $segment, $target ) = @_;
  my $db     = $self->database;
  my $whole  = $db->segment( $segment->ref );
  my $window = $segment->length < 8000 ? int( $segment->length / 2 ) : 4000;
  my $nstart = $target < $window ? 1 : $target - $window;
  my $nend   = $target + $window - 1;
  $nend = $whole->end if $nend > $whole->end;

  $segment = $db->segment(
    -name  => $segment->ref,
    -start => $nstart,
    -end   => $nend
  );
}

# find the target
sub set_focus {
  my ( $self, $segment ) = @_;
  my $tfeat = $self->config_param('tfeat');

  my $target;
  my $factor = param('conversion_factor');

  if ( param('map.x') ) {
    $target = int( ( $factor * param('map.x') ) + 0.5 );
    $target += $segment->start;
  }
  elsif ($tfeat) {
    my ( $s, $e ) = $tfeat =~ /(\d+)\.\.(\d+)/;
    $target = int( $s + ( $e - $s ) / 2 );
  }

  $target;
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

# form elements borrowed and modified from the primer3 website
sub primer3_params {
  my $self = shift;
  my $help = 'http://frodo.wi.mit.edu/cgi-bin/primer3/primer3_www_help.cgi';
  my $msg  = "Format xxx-xxx\\nSize_range is optional; by default the best "
      . "product size to flank the feature will be selected\\n"
      . "Use this option to force a particular amplicon size class";

  my %table = (
    h3(
      qq(<a name="PRIMER_NUM_RETURN_INPUT" target="_new" href="$help\#PRIMER_NUM_RETURN">
       Primer sets:</a>)
    ),
    qq(<input type="text" size="4" name="PRIMER_NUM_RETURN" value="3">),
    h3(
      qq(<a name="PRIMER_OPT_SIZE_INPUT" target="_new" href="$help\#PRIMER_SIZE">
          Primer Size</a>)
    ),
    qq(Min. <input type="text" size="4" name="PRIMER_MIN_SIZE" value="18">
       Opt. <input type="text" size="4" name="PRIMER_OPT_SIZE" value="20">
       Max. <input type="text" size="4" name="PRIMER_MAX_SIZE" value="27">),
    h3(
      qq(<a name="PRIMER_OPT_TM_INPUT" target="_new" href="$help\#PRIMER_TM">
          Primer Tm</a>)
    ),
    qq(Min. <input type="text" size="4" name="PRIMER_MIN_TM" value="57.0">
       Opt. <input type="text" size="4" name="PRIMER_OPT_TM" value="60.0">
       Max. <input type="text" size="4" name="PRIMER_MAX_TM" value="63.0">),
    h3(
      qq(<a name="PRIMER_PRODUCT_SIZE_RANGE" href="javascript:void(0)"
           onclick="alert('$msg')">Product size range:</a>)
    ),
    qq(<input type="text" size="8" name="PRIMER_PRODUCT_SIZE_RANGE" value=$self->{range}>),
    h3(
      qq(<a name="PRIMER_MAX_END_STABILITY_INPUT" target="_new" href="$help\#PRIMER_MAX_END_STABILITY">
       Max 3\' Stability:</a>)
    ),
    qq(<input type="text" size="4" name="PRIMER_MAX_END_STABILITY" value="9.0">),
    h3(
      qq(<a name="PRIMER_PAIR_MAX_MISPRIMING_INPUT" target="_new" href="$help\#PRIMER_PAIR_MAX_MISPRIMING">
       Pair Max Mispriming:</a>)
    ),
    qq(<input type="text" size="4" name="PRIMER_PAIR_MAX_MISPRIMING" value="24.00">),
    h3(
      qq(<a name="PRIMER_GC_PERCENT_INPUT" target="_new" href="$help\#PRIMER_GC_PERCENT">
       Primer GC%</a>)
    ),
    qq(Min. <input type="text" size="4" name="PRIMER_MIN_GC" value="20.0">
       Opt. <input type="text" size="4" name="PRIMER_OPT_GC_PERCENT" value="">
       Max. <input type="text" size="4" name="PRIMER_MAX_GC" value="80.0">),
    h3(
      qq(<a name="PRIMER_SELF_ANY_INPUT" target="_new" href="$help\#PRIMER_SELF_ANY">
       Max Self Complementarity:</a>)
    ),
    qq(<input type="text" size="4" name="PRIMER_SELF_ANY" value="8.00">),
    h3(
      qq(<a name="PRIMER_SELF_END_INPUT" target="_new" href="$help\#PRIMER_SELF_END">
       Max 3\' Self Complementarity:</a>)
    ),
    qq(<input type="text" size="4" name="PRIMER_SELF_END" value="3.00">),
    h3(
      qq(<a name="PRIMER_MAX_POLY_X_INPUT" target="_new" href="$help\#PRIMER_MAX_POLY_X">
       Max Poly-X:</a>)
    ),
    qq(<input type="text" size="4" name="PRIMER_MAX_POLY_X" value="5">)
  );
  return \%table;
}

1;
