package Bio::Graphics::Browser2::Render::HTML::TrackListing::exhibit;

use strict;
use warnings;
use base 'Bio::Graphics::Browser2::Render::HTML::TrackListing';

use Bio::Graphics::Browser2::Shellwords;
use CGI qw(:standard);
use Carp 'croak';
use constant DEBUG => 0;

sub listing_title {
    my $self = shift;
    $self->render->tr('SEARCH_TRACKS') || 'Search Tracks';
}

sub tab_name {
    return 'faceted_search_page';
}


sub javascript_modules {
    my $self = shift;
    my @jm = $self->SUPER::javascript_modules;
    return @jm,'http://api.simile-widgets.org/exhibit/2.2.0/exhibit-api.js';
}

sub stylesheets {
    my $self = shift;
    my @ss   = $self->SUPER::stylesheets;
    return @ss,'http://www.simile-widgets.org/styles/common.css';
}

sub render_track_listing {
    my $self = shift;

    my $settings = $self->settings;
    my $source   = $self->source;
    my $render   = $self->render;
    return p("This doesn't work yet");
}

1;
