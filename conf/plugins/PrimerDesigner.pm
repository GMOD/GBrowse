# $Id: PrimerDesigner.pm,v 1.3 2004-03-19 05:45:32 sheldon_mckay Exp $

=head1 NAME

Bio::Graphics::Browser::Plugin::PrimerDesigner -- a plugin to design PCR primers with primer3

=head1 SYNOPSIS

This module is not used directly

=head1 DESCRIPTION

PrimerDesigner.pm uses the Bio::PrimerDesigner API for primer3 to design
PCR primers for features or target coordinates in gbrowse.

=head1 PRIMER3 is *nix-specific
  
On unix-like systems, compile a primer3 (v. 0.9) binary executable for your 
OS and copy it to the default path 'usr/local/bin'.  An alternate path can be 
specified as follows

  my $binpath = '/path/to/primer3'; 

=head1 primer3 for other platforms

Primer3 can be used in a platform independent manner via the Bio::PrimerDesigner
API.  To specify remote access to primer3:

  my $method = 'remote';
  my $url    = 'http://your_url/cgi-bin/primerdesigner.cgi';

The URL should point to a *nix host that has Bio::PrimerDesigner and the
script "primerdesigner.cgi" (a CGI wrapper for the primer3 binary) installed.

=head1 Designing Primers


=head2 Targeting a feature or coordinate

The target for PCR primer design is selected by clicking on an image map and 
(optionally) further refined by selecting an individual feature that overlaps the 
selected sequence coordinate.

=head2 Design Paramaters

The Provided  set of reasonable default primer attributes will work in most 
cases.  Product size will vary by target feature size.  Rather than providing
a default size-range, a series of increasing PCR product sizes is cycled until 
products big enough to flank the target feature are found.  This will not 
necessarily find the best primers, just the first ones that produce a big 
enough product to flank the target.  If the primers are flagged as low quality,
more optimal optimal primers may be found by specifying a specific size-range.

head1 TO-DO

Add support for ePCR-based scanning for false priming

=head1 FEEDBACK

See the GMOD website for information on bug submission http://www.gmod.org.

=head1 AUTHOR - Sheldon McKay

Email smckay@bcgsc.bc.ca

=head1 SEE ALSO

Bio::PrimerDesigner (www.cpan.org)
primer3 (http://frodo.wi.mit.edu/primer3/primer3_code.html)

=cut



package Bio::Graphics::Browser::Plugin::PrimerDesigner;

#################################################################################
# Edit these lines to point to the path or URL of the primer3 binary executable
my $binpath = '/usr/local/bin';
my $method  = 'local';
#my $binpath = 'http://aceserver.biotech.ubc.ca/cgi-bin/primer_designer.cgi';
#my $method  = 'remote';
#################################################################################

use Bio::PrimerDesigner;
use Bio::PrimerDesigner::Tables;
use Bio::Graphics::Browser::Plugin;
use CGI::Pretty qw/:standard escape/;
use CGI::Carp qw/fatalsToBrowser/;
use strict;

use vars '@ISA', '$CONFIG';

@ISA = qw / Bio::Graphics::Browser::Plugin /;

sub name {
    'PCR primers'
    }

sub description {
  p("This plugin uses Bio::PrimerDesigner and PRIMER3 to " .
    "design PCR primers to amplify selected features or sequences"),
  p("This plugin was written by Sheldon McKay");
}

sub type {
    'dumper'
    }

sub verb {
    'Design'
    }

sub mime_type {
    'text/html'
    }

sub reconfigure {
    my $self = shift;
    my $conf = $self->configuration;

    my $target = $self->config_param('target');
    my $tfeat  = $self->config_param('tfeat');
    my $exclude;

    if ( $tfeat ) {
	my ($tstart, $tend) = $tfeat =~ /(\d+)\.\.(\d+)/;
	($tstart, $tend) = ($tend, $tstart) if $tstart > $tend;
	$exclude = "$tstart," . ($tend-$tstart);
	$target = $tstart + int(($tend - $tstart)/2);
    }

    $conf->{target}   = $target;
    $conf->{exclude}  = $exclude ? $exclude : '';
    $conf->{name}     = $self->config_param('name');
    $self->configuration($conf);
}

sub configure_form {
    my $self = shift;
    my ($segment) = @{$self->segments};
    my $start  = $segment->start;
    my $end    = $segment->end;
    my $name   = $segment->ref; 
    my $length = unit_label($segment->length) . 'bp';

    my $html = h2("Showing $length from $name, positions $start to $end") .
	       h3(font{-color => 'black'},'Click on a feature or map-location ' .
                  'to select a target region for PCR primers');

    $html .= $self->segment_map($segment);
    print $html;
    exit;
}

sub dump {
    my ($self, $segment) = @_;
    my $conf = $self->configuration;
    my $target = $self->set_focus($segment) || $conf->{target};

    # redefine the segment to center the target and trim excess DNA
    $segment = $self->refocus( $segment, $target );

    # design the primers
    $self->design_primers( $segment, $conf ) 
	if $self->get_primer3_params();

    # or print the form
    print "<head><link rel=stylesheet type=text/css".
	" href=/gbrowse/gbrowse.css /></head>\n";

    my @feats = $segment->contained_features;
    my $start  = $segment->start;
    my $end    = $segment->end;
    my $ref    = $segment->ref;
    my $name   = "$ref:$start..$end";
    my $length = unit_label($segment->length) . 'bp';

    my $html = h2("Showing $length from $ref, positions $start to $end") .
	       '<table style="width:800px"><tr class="searchtitle">'  .
	       '<th>Click on a feature or map-location ' .
	       'to move the target region for PCR primers</th></tr><tr><td>'; 

    $html .= $self->segment_map($segment) . br;

    param( $self->config_name('name'), $name );

    $html .= start_form( -method => 'POST' ) .
             hidden( -name => 'plugin', -value => 'PrimerDesigner' ) .
             hidden( -name => 'plugin_action', -value => 'Go' ) .
             hidden( -name => $self->config_name('name') );
             

    my $target_field = textfield( -size  => 8,
				  -name  => $self->config_name('target'),
				  -value => $target );
    
    $html .= h3( "PCR primers will target position $target_field");

    # feature based target regions
    my @f;
    for my $f (@feats ) {
        my ($s, $e) = ($f->start, $f->end);
        ($s, $e) = ($e, $s) if $s > $e;
        next if $s < ($target - 2000);
        next if $e > ($target + 2000);
        next if $e < $target || $s > $target;
        my $tag  = $f->method;
        my $name = $f->name;
        push @f, "$name $tag: $s..$e Size: " . abs($s - $e). " bp";
    }
    if ( @f ) {
	my $checkbox .= checkbox_group ( -name    => $self->config_name('tfeat'),
					 -values  => \@f,
					 -rows    => 4 );

	# override stylesheet for table width
	my $pixels = 400 + (int((@f/3) + 0.5) * 400) . 'px';
	$checkbox =~ s/table/table style="width:$pixels"/;
	$html .= h3( 'Select a feature to target (optional)...' . br. 
		     $checkbox);
    }


    $html .= '</td></tr><tr class="searchtitle">';

    # primer design parameters
    my $atts = primer3_params();
    my @col1 = grep {  /Primer|Tm|Product/ } keys %$atts;
    my @col2 = grep { !/Primer|Tm|Product/ } keys %$atts;
    
    @col1 = ( ( grep { $atts->{$_} =~ /Opt\./ } @col1 ) ,
              ( grep { $atts->{$_} !~ /Opt\./ } @col1 ) );


    $html .= '<th>Primer3 Parameters</th></tr><tr><td><table style="width:800px">';
    for ( 0..4 ) {
	$html .= Tr( 
		     td( [ 
			   $col1[$_], 
			   $atts->{$col1[$_]}, 
			   $col2[$_],
			   $atts->{$col2[$_]} 
			   ] 
			 ) 
		     );
    }
    $html .= '</table></td></tr></table>';
    
    my $url = self_url();
    $url =~ s/\?.+/\?name=$segment/;

    $html .= br . submit( -name => 'configured', -value => 'Design Primers' ) . 
             '&nbsp;' . reset . '&nbsp;' .
	     button( -onclick => "window.location='$url'", -name => 'Return to Browser') .
	     end_form();

    print $html;

}


sub design_primers {
    my ($self, $segment, $conf) = @_;
    my %atts = $self->get_primer3_params;
    my $exclude = $conf->{exclude};
    my $target  = $conf->{target};
    my $offset  = $segment->start - 1;
    $exclude    =~ s/(\d+)/$1 - $offset/e;
    $target     = $exclude || ($target - $offset) . ',1';
    my $dna     = $segment->seq;

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
    
    # get a PCR object
    my $pcr = Bio::PrimerDesigner->new( program  => 'primer3',
					method   => $method ) 
	or die Bio::PrimerDesigner->error;
    
    if ( $method eq 'local' && $binpath ) {
	$pcr->binary_path( $binpath ) or die $pcr->error;
    }
    else {
	$pcr->url( $binpath ) or die $pcr->error;
    }

    my $res = $pcr->design( %atts ) or die $pcr->error;
   
    $self->primer_results( $res, $segment );
    exit;
}

sub primer_results {
    my ($self, $res, $segment) = @_;
    my $offset = $segment->start;
    my $ref = $segment->ref;
    my $num = grep { /^\d+$/ } keys %$res;

    print h2("No primers found"), pre($res->raw_output) and exit 
	unless $res->left;

    my @attributes = qw/ left right startleft startright tmleft tmright
                         qual lqual rqual leftgc rightgc /;

    my @rows;
 
    my $img = $self->segment_map($segment, $res);
    $img .= ";style=PCR+glyph=primers+bgcolor=red+height=10";

    for my $n ( 1 .. $num ) {
	my %r;
	for ( @attributes ) {
	    $r{$_} = $res->$_($n);
	}
        next unless $r{left};

        $r{prod} = $r{startright} - $r{startleft};
	$r{startleft}  += $offset;
	$r{startright} += $offset;
        for ( qw/ qual lqual rqual / ) {
	    $r{$_} =~ s/^(\S{6}).+/$1/;

        # low primer pair quality warning
	    if ( $r{$_} > 1 ) {
		my $msg = "Primer-pair penalty (quality score) $r{$_}\\n" .
                    "For best results, a primer-pair should have a quality " .
		    "score of < 1.\\nThe score for the pair is the " .
		    "the sum of the score for each individual primer.\\n" .
		    "If the high score is due to a departure from optimal primer " .
                    "GC-content or Tm, the primers are probably OK.  " .
                    "Otherwise, more optimal primers can often be obtained " .
		    "by adjusting the design parameters (especially the product " .
                    "size-range).\\n";
		$msg = "alert('$msg')";
		$r{$_} = a( { -href => 'javascript:void(0)',
			      -onclick => $msg }, b(font({-color=>'red'},$r{$_})));
		
	    }
	}
	
	$img .= ";add=$ref+PCR+Primer_set_$n+$r{startleft}..$r{startright}";

	push @rows, Tr( [
			 td( { -bgcolor => 'blue' },
			     [ map { font( { -color => 'white' }, b($_)) }
			       qw/Set Primer Sequence Tm %GC Coord 
			       Quality Product Primer_Pair_Quality/ ] ), 
			 td( [ $n, 'left', $r{left}, $r{tmleft}, $r{leftgc},
			       $r{startleft}, $r{lqual}, '&nbsp;', '&nbsp;' ]),
			 td( [ '&nbsp;', 'right', $r{right}, $r{tmright}, $r{rightgc},
			       $r{startright}, $r{rqual}, $r{prod}, $r{qual}])
			 ]
			);
    }

    if ( @rows ) {
	$img = img( { -src => $img } );
	print h2("$segment Primer Design Results"),
	table( { -bgcolor => 'lightblue', -width => 810 }, 
	       [
		Tr( td( { -colspan => 9 }, $img )),
		@rows
	       ]
	     );
    }
}


sub unit_label {
    my $value = shift;
    $value >= 1e9  ? sprintf("%.4g G%s",$value/1e9)
	           : $value >= 1e6  ? sprintf("%.4g M%s",$value/1e6)
	           : $value >= 1e3  ? sprintf("%.4g k%s",$value/1e3)
	           : sprintf("%.4g %s", $value);
}

sub segment_map {
    my ($self, $segment, $res) = @_;
    my @tracks = $self->selected_tracks;
    my $offset = $segment->start - 1;
    my $start = $res ? ($res->startleft - 500 + $offset) : $segment->start;
    my $stop  = $res ? ($res->startright + 500 + $offset) : $segment->stop;

    my $name = $segment->ref . ":$start..$stop";
    my $url = self_url();
    $url =~ s/\?.+//g;
    my $furl = $url;
    $url =~ s/gbrowse/gbrowse_img/;
    $url .= "?name=$name;width=800;type=add+" . join '+', @tracks;

    return $url if $res;    

    my $factor = $segment->length/800;
    
    # Unstick sticky CGI parameters
    param('plugin_action', 'Go');
    param('name', $name);
    param('conversion_factor', $factor);

    start_form( -method => 'POST', -action => $furl ) .
    hidden( -name => 'plugin_action' ) .
    hidden( -name => 'plugin' ) .
    hidden( -name => 'name' ) .
    hidden( -name => 'conversion_factor' ) .
    image_button( { -src => $url, -name => 'map', -border => 0 } ) .
    end_form();

}

# center the segment on the target coordinate
sub refocus {
    my ($self, $segment, $target) = @_;
    my $db     = $self->database;
    my $whole  = $db->segment( $segment->ref );
    my $window = $segment->length < 8000 ? int($segment->length/2) : 4000;
    my $nstart = $target < $window ? 1 : $target - $window;
    my $nend   = $target + $window - 1;
    $nend      = $whole->end if $nend > $whole->end;

    $segment = $db->segment( -name  => $segment->ref,
                             -start => $nstart,
                             -end   => $nend );
}

# find the target
sub set_focus {
    my ($self, $segment) = @_;
    my $target;
    my $factor = param('conversion_factor');

    if ( param('map.x') ) {
	$target = int(($factor * param('map.x')) + 0.5);
	$target += $segment->start;
    }
    
    $target;
}

# slurp the BOULDER_IO params
sub get_primer3_params {
    my $self = shift;

    return %{$self->{atts}} if $self->{atts};

    for ( grep { /PRIMER_/ } param() ) {
	$self->{atts}->{$_} = param($_) if param($_);
        param($_, '');
    }

    return %{$self->{atts}} if $self->{atts};
}



# form elements stolen and modified from the primer3 website
sub primer3_params {
    my $help = 'http://frodo.wi.mit.edu/cgi-bin/primer3/primer3_www_help.cgi';
    my $msg  = "Format xxx-xxx\\nSize_range is optional; by default the best " .
	"product size to flank the feature will be selected\\n" .
	"Use this option to force a particular amplicon size class";


    my %table = (
    h3(qq(<a name="PRIMER_NUM_RETURN_INPUT" target="_new" href="$help\#PRIMER_NUM_RETURN">
       Primer sets:</a>)),
    qq(<input type="text" size="4" name="PRIMER_NUM_RETURN" value="1">),
    h3(qq(<a name="PRIMER_OPT_SIZE_INPUT" target="_new" href="$help\#PRIMER_SIZE">
          Primer Size</a>)),
    qq(Min. <input type="text" size="4" name="PRIMER_MIN_SIZE" value="18">
       Opt. <input type="text" size="4" name="PRIMER_OPT_SIZE" value="20">
       Max. <input type="text" size="4" name="PRIMER_MAX_SIZE" value="27">),
    h3(qq(<a name="PRIMER_OPT_TM_INPUT" target="_new" href="$help\#PRIMER_TM">
          Primer Tm</a>)),
    qq(Min. <input type="text" size="4" name="PRIMER_MIN_TM" value="57.0">
       Opt. <input type="text" size="4" name="PRIMER_OPT_TM" value="60.0">
       Max. <input type="text" size="4" name="PRIMER_MAX_TM" value="63.0">),
    h3(qq(<a name="PRIMER_PRODUCT_SIZE_RANGE" href="javascript:void(0)"
           onclick="alert('$msg')">Product size range:</a>)),
    qq(<input type="text" size="8" name="PRIMER_PRODUCT_SIZE_RANGE" value=''>),
    h3(qq(<a name="PRIMER_MAX_END_STABILITY_INPUT" target="_new" href="$help\#PRIMER_MAX_END_STABILITY">
       Max 3\' Stability:</a>)),
    qq(<input type="text" size="4" name="PRIMER_MAX_END_STABILITY" value="9.0">),
    h3(qq(<a name="PRIMER_PAIR_MAX_MISPRIMING_INPUT" target="_new" href="$help\#PRIMER_PAIR_MAX_MISPRIMING">
       Pair Max Mispriming:</a>)),
    qq(<input type="text" size="4" name="PRIMER_PAIR_MAX_MISPRIMING" value="24.00">),
    h3(qq(<a name="PRIMER_GC_PERCENT_INPUT" target="_new" href="$help\#PRIMER_GC_PERCENT">
       Primer GC%</a>)),
    qq(Min. <input type="text" size="4" name="PRIMER_MIN_GC" value="20.0">
       Opt. <input type="text" size="4" name="PRIMER_OPT_GC_PERCENT" value="">
       Max. <input type="text" size="4" name="PRIMER_MAX_GC" value="80.0">),
    h3(qq(<a name="PRIMER_SELF_ANY_INPUT" target="_new" href="$help\#PRIMER_SELF_ANY">
       Max Self Complementarity:</a>)),
    qq(<input type="text" size="4" name="PRIMER_SELF_ANY" value="8.00">),
    h3(qq(<a name="PRIMER_SELF_END_INPUT" target="_new" href="$help\#PRIMER_SELF_END">
       Max 3\' Self Complementarity:</a>)),
    qq(<input type="text" size="4" name="PRIMER_SELF_END" value="3.00">),
    h3(qq(<a name="PRIMER_MAX_POLY_X_INPUT" target="_new" href="$help\#PRIMER_MAX_POLY_X">
       Max Poly-X:</a>)),
    qq(<input type="text" size="4" name="PRIMER_MAX_POLY_X" value="5">)
		 );
    return \%table;
}

1;
