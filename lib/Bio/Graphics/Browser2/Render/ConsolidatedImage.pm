package Bio::Graphics::Browser2::Render::ConsolidatedImage;
use strict;
use warnings;

use constant DEBUG => 0;

sub new {
    my $class   = shift;
    my $globals = shift;
    my $render  = Bio::Graphics::Browser2::Render::HTML->new($globals);
    return bless {render => $render},ref $class || $class;
}

sub render  { shift->{render}               }
sub session { shift->render->session        }
sub cookie  { shift->render->create_cookie  }
sub source  { shift->render->data_source    }

sub render_multiple {
    my $self = shift;
    my ($renderer,$format,$flip,$embed) = @_;
    my $features = $self->render->region->features;
    my $karyotype = Bio::Graphics::Karyotype->new(source   => $self->render->data_source,
						  language => $self->render->language);
    $karyotype->add_hits($features);
    my $panels = $karyotype->generate_panels($format);
    my (@gds,@seqids);
    for my $seqid (keys %$panels) {
	push @gds,$panels->{$seqid}{panel}->gd;
	push @seqids,$seqid;
    }
    my $img_data = $self->consolidate_images(\@gds,undef,undef,'horizontal',\@seqids);
    return ($img_data,undef);
}

sub render_tracks {
    my $self = shift;
    my ( $renderer, $format, $flip, $embed, $track_types ) = @_;

    my $render   = $self->render;

    my $external = $render->external_data;
    warn 'visible = ',join ' ',$render->visible_tracks if DEBUG;
    my @labels   = $render->expand_track_names($render->detail_tracks);

    warn "labels = ",join ',',@labels if DEBUG;
    my @track_types = @$track_types;

    # If no tracks specified, we want to see all tracks with this feature
    if (!@track_types) { @track_types = @labels; } 
    unshift @track_types,'_scale';

    my $result   = $renderer->render_track_images(
						  {
						      labels            => \@track_types,
						      external_features => $external,
						      section           => 'detail',
						      cache_extra       => [$format],
						      image_class       => $format,
						      flip              => $flip,
						      -key_style        => 'between',
						      }
						  );

    warn "returned labels = ",join ',',%$result if DEBUG;

    # Previously - @labels (caused drawing more tracks than asked for)
    my @image_data      = @{$result}{grep {$result->{$_}} @track_types};
    my @gds             = map {$_->{gd} } @image_data;
    my @map_data        = map {$_->{map}} @image_data;

    my $img_data  = $self->consolidate_images(\@gds);
    my $map       = $self->consolidate_maps  (\@map_data, \@gds) if $embed;

    return ($img_data,$map);

}

sub calculate_composite_bounds {
    my $self = shift;
    my ($gds,$orientation)  = @_;

    warn "consolidating ",scalar @$gds," GD objects" if DEBUG;

    my $height = 0;
    my $width  = 0;
    if ($orientation eq 'vertical') {
	for my $g (@$gds) {
	    warn "g=$g" if DEBUG;
	    next unless $g;
	    $height +=   ($g->getBounds)[1];  # because GD::SVG is missing the width() and height() methods
	    $width   ||= ($g->getBounds)[0];
	}
    } elsif ($orientation eq 'horizontal') {
	for my $g (@$gds) {
	    warn "g=$g" if DEBUG;
	    next unless $g;
	    $height    = ($g->getBounds)[1] if $height < ($g->getBounds)[1];
	    $width    += ($g->getBounds)[0];
	}
    }
    
    return ($width,$height);
}

sub consolidate_images {
    my $self = shift;
    my ($gds,$width,$height,$orientation,$labels) = @_;
    $orientation ||= 'vertical';

    ($width,$height) = $self->calculate_composite_bounds($gds,$orientation) 
	unless defined $width && defined $height;

    warn "consolidating ",scalar @$gds," GD objects" if DEBUG;

    my $format = ref($gds->[0]);
    warn "format = $format" if DEBUG;

    return $format =~ /^GD::SVG/ ? $self->_consolidate_svg($width,$height,$gds,$orientation,$labels)
                                 : $self->_consolidate_gd ($width,$height,$gds,$orientation,$labels);
}

sub _consolidate_gd {
    my $self = shift;
    my ($width,$height,$gds,$orientation,$labels) = @_;

    my $class     = ref($gds->[0]);
    (my $fontclass = $class)=~s/::Image//;

    my $lineheight = $fontclass->gdMediumBoldFont->height;
    my $charwidth  = $fontclass->gdMediumBoldFont->width;
    $height += $lineheight if $orientation eq 'horizontal';

    my $gd = $class->new($width,$height);
    my $white = $gd->colorAllocate(255,255,255);
    my $black = $gd->colorAllocate(0,0,0);

    eval {
	my $bg = $gds->[0]->getPixel(0,0);
	my @bg = $gds->[0]->rgb($bg);
	my $i  = $gd->colorAllocate(@bg);
	$gd->filledRectangle(0,0,$width,$height,$i);
    };

    my $offset = 0;
    if ($orientation eq 'vertical') {
	for my $g (@$gds) {
	    next unless $g;
	    $gd->copy($g,0,$offset,0,0,$g->getBounds);
	    $offset += ($g->getBounds)[1];
	}
    } else {
	for my $g (@$gds) {
	    next unless $g;
	    $gd->copy($g,$offset,$height-($g->getBounds)[1]-$lineheight,0,0,$g->getBounds);
	    if ($labels) {
		my $l = shift @$labels;
		$gd->string($fontclass->gdMediumBoldFont,
			    $offset+(($g->getBounds)[0]-$charwidth*length $l)/2,
			    $height-$lineheight,$l,$black);
	    }
	    $offset += ($g->getBounds)[0];
	}
    }

    return $gd;
}

# because the GD::SVG copy() method is broken
sub _consolidate_svg {
    my $self = shift;
    my ($width,$height,$gds,$orientation,$labels) = @_;

    my $image_height = $height;

    if ($labels) {
	my $font = GD::SVG->gdMediumBoldFont;
	my $charwidth = $font->width;
	my $lineheight=$font->height;
	$image_height += $lineheight;
	for my $gd (@$gds) {
	    my $l     = shift @$labels;
	    my $black = $gd->colorAllocate(0,0,0);
	    $gd->string($font,
			(($gd->getBounds)[0]-$charwidth*length $l)/2,
			($gd->getBounds)[1],
			$l,$black);
	}
    }

    my $svg = qq(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n\n);
    $svg   .= qq(<svg height="$image_height" width="$width" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">\n);

    if ($orientation eq 'vertical') {
	my $offset = 0;
	for my $g (@$gds) {
	    my $s              = $g->svg;
	    my $current_height = 0;
	    foreach (split "\n",$s) {
		if (m!</svg>!) {
		    last;
		}
		elsif (/<svg.+height="([\d.]+)"/) {
		    $current_height = int($1+0.5);
		    $svg .= qq(<g transform="translate(0,$offset)">\n);
		}
		elsif ($current_height) {
		    $svg .= "$_\n";
		}
	    }
	    $svg .= "</g>\n" if $current_height;
	    $offset += $current_height;
	}
	$svg   .= qq(</svg>\n);
 

   } else {
	my $offset = 0;
	for my $g (@$gds) {
	    my $s              = $g->svg;
	    my $current_width = 0;
	    foreach (split "\n",$s) {
		if (m!</svg>!) {
		    last;
		}
		elsif (/<svg.+width="([\d.]+)"/) {
		    $current_width = int($1+0.5);
		    my $height     = $height - ($g->getBounds)[1];
		    $svg .= qq(<g transform="translate($offset,$height)">\n);
		}
		elsif ($current_width) {
		    $svg .= "$_\n";
		}
	    }
	    $svg .= "</g>\n" if $current_width;
	    $offset += $current_width;
	}
	$svg   .= qq(</svg>\n);
    }

    # munge fonts slightly for systems that don't have Helvetica installed
    $svg    =~ s/font="Helvetica"/font="san-serif"/gi;
    $svg    =~ s/font-size="11"/font-size="9"/gi;  
    $svg    =~ s/font-size="13"/font-size="12"/gi;  
    return $svg;
}

sub consolidate_maps {
    my $self = shift;
    my ($maps,$gds) = @_;

    my $offset = 0;
    my @integrated_list = 'gbrowse2_img';
    for (my $i=0;$i<@$maps;$i++) {
	my $data = $maps->[$i];
	shift @$data;
	for (@$data) {
	    my ($name,$x1,$y1,$x2,$y2,@rest) = split "\t";
	    $y1 += $offset;
	    $y2 += $offset;
	    push @integrated_list,join "\t",($name,$x1,$y1,$x2,$y2,@rest);
	}
	$offset += ($gds->[$i]->getBounds)[1];
    }

    return Bio::Graphics::Browser2::RenderPanels->map_html(\@integrated_list);
}

1;

__END__

=head1 NAME

Bio::Graphics::Browser2::ConsolidatedImage - wrapper for
B::G::B2::Render::HTML that makes a consolidated image and imagemap,
for use by frontends that require a consolidated image and imagemap,
as opposed to the standard GBrowse2 single-track images and maps.

=cut
