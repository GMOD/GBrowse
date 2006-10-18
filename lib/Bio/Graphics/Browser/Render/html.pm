package Bio::Graphics::Browser::Render::html;
#$Id: html.pm,v 1.1 2006-10-18 18:38:35 sheldon_mckay Exp $
#
# A class for rendering HTML for gbrowse
# contains non-template-specific methods

use strict;
use Carp 'croak','cluck';
use Bio::Graphics::Browser;
use CGI ':standard';
use Bio::Graphics::Browser::Render;

use vars qw/@ISA/;
@ISA = Bio::Braphics::Browser::Render;


use constant JS         => Bio::Braphics::Browser::Render::JS;
use constant BUTTONSDIR => Bio::Braphics::Browser::Render::BUTTONSDIR;

sub new {
  my $self = shift;
  return bless $self;
}

sub finish {
  my $self   = shift;
  $self->page_settings->flush;
}

sub print_top {
  my $self   = shift;
  my ($title,$reset_all) = @_;

  local $^W = 0;  # to avoid a warning from CGI.pm                                                                                                                                                               
  my $config = $self->config;

  my $js = $config->setting('js') || JS;
  my @scripts = {src=>"$js/buttons.js"};
  if ($config->setting('autocomplete')) {
    push @scripts,{src=>"$js/$_"} foreach qw(yahoo.js dom.js event.js connection.js autocomplete.js);
  }

  print_header(-expires=>'+1m');
  my @args = (-title => $title,
              -style  => {src=>$config->setting('stylesheet')},
              -encoding=>$config->tr('CHARSET'),
	      );
  push @args,(-head=>$config->setting('head'))    if $config->setting('head');
  push @args,(-lang=>($config->language_code)[0]) if $config->language_code;
  push @args,(-script=>\@scripts);
  push @args,(-reset_toggle   => 1)               if $reset_all;
  print start_html(@args) unless $self->{html}++;
}

sub print_bottom {
  my $self    = shift;
  my $version = shift;
  my $config = $self->config;

  print
    $config->footer || '',
      p(i(font({-size=>'small'},
               $config->tr('Footer_1'))),br,
        tt(font({-size=>'small'},$config->tr('Footer_2',$version)))),
      end_html;
}

sub warning {
  my $self = shift;
  my @msg  = @_;
  cluck "@_" if DEBUG;
  $self->print_top();
  print h2({-class=>'error'},@msg);
}


=pod

=head2  source_menu

 Title   : source_menu
 Usage   : my $source_menu = $render->source_menu;
 Function: creates a popup menu of available data sources
 Returns : html-formatted string
 Args    : none

=cut

sub source_menu {
  my $self         = shift;
  my @sources      = $self->config->sources;
  my $show_sources = $self->setting('show sources') || 1;
  my $sources = $show_sources && @sources > 1;

  my $popup = popup_menu(
                         -name     => 'source',
                         -values   => \@sources,
                         -labels   => { map { $_ => $self->description($_) } $self->sources },
                         -default  => $self->source,
                         -onChange => 'document.mainform.submit()'
                         );

  return b( $self->tr('DATA_SOURCE') ) . br
      . ( $sources ? $popup : $self->description( $self->source ) );
}


=pod

=head2 slidertable

 Title   : slidertable
 Usage   : my $navigation_bar = $render->slidertable;
 Function: makes the zoom menu with pan buttons
 Returns : html-formatted text
 Args    : path to button images (optional)

=cut

sub slidertable {
  my $self       = shift;
  my $small_pan  = shift;
  my $buttons    = $self->setting('buttons') || BUTTONSDIR;
  my $segment    = $self->current_segment or fatal_error("No segment defined");
  my $span       = $small_pan ? int $segment->length/2 : $segment->length;
  my $half_title = $self->unit_label( int $span / 2 );
  my $full_title = $self->unit_label($span);
  my $half       = int $span / 2;
  my $full       = $span;
  my $fine_zoom  = $self->get_zoomincrement();
  Delete($_) foreach qw(ref start stop);
  my @lines;
  push @lines,
  hidden( -name => 'start', -value => $segment->start, -override => 1 );
  push @lines,
  hidden( -name => 'stop', -value => $segment->end, -override => 1 );
  push @lines,
  hidden( -name => 'ref', -value => $segment->seq_id, -override => 1 );
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
                '&nbsp;', $self->zoomBar, '&nbsp;',
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

=pod

=head2 zoomBar

 Title   : zoomBar
 Usage   : my $zoombar = $self->zoomBar;
 Function: creates the zoom bar
 Returns : an html popup menu
 Args    : none

=cut

sub zoomBar {
  my $self    = shift;
  my $segment = $self->current_segment;
  my ($show)  = $self->tr('Show');
  my %seen;
  my @ranges = grep { !$seen{$_}++ } sort { $b <=> $a } ($segment->length, $self->get_ranges());
  my %labels = map { $_ => $show . ' ' . $self->unit_label($_) } @ranges;
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

=pod

=head2 make_overview

 Title   : make_overview
 Usage   : my $overview = $render->overview($settings,$featurefiles);
 Function: creates an overview image as an image_button
 Returns : html-formatted text
 Args    : a settings hashref and an (optional) array_ref of featurefile objects

=cut

sub make_overview {
  my ( $self, $settings, $feature_files ) = @_;
  my $segment       = $self->current_segment || return;
  my $whole_segment = $self->whole_segment;

  $self->width( $settings->{width} * OVERVIEW_RATIO );

  my ( $image, $length )
      = $self->overview( $whole_segment, $segment, $settings->{features},
                         $feature_files )
      or return;

  # restore the original width!
  my $restored_width = $self->width/OVERVIEW_RATIO;
  $self->width($restored_width);

  my ( $width, $height ) = $image->getBounds;
  my $url = $self->generate_image($image);

  return image_button(
                      -name   => 'overview',
                      -src    => $url,
                      -width  => $width,
                      -height => $height,
                      -border => 0,
                      -align  => 'middle'
                      )
      . hidden(
               -name     => 'seg_min',
               -value    => $whole_segment->start,
               -override => 1
               )
      . hidden(
               -name     => 'seg_max',
               -value    => $whole_segment->end,
               -override => 1
               );
}

=pod

=head2 overview_panel

 Title   : overview_panel
 Usage   : my $overview_panel = $render->overview_panel($settings,$featurefiles);
 Function: creates a DHTML-toggle panel with the overview image
 Returns : HTML-formatted text
 Args    : a settings hashref and an (optional) array_ref of featurefile objects

=cut

sub overview_panel {
  my ( $self, $page_settings, $feature_files ) = @_;
  my $segment = $self->current_segment || return;
  return '' if $self->section_setting('overview') eq 'hide';
  my $image = $self->make_overview( $page_settings, $feature_files );
  return $self->toggle(
                       'Overview',
                       table(
                             { -border => 0, -width => '100%', },
                             TR( { -class => 'databody' }, td( { -align => 'center' }, $image ) )
                             )
                       );
}

