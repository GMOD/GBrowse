use strict;
use warnings;

use Test::More;
use Test::WWW::Mechanize;

my $base_url = $ENV{GBROWSE_TEST_URL}
    or plan skip_all => 'set the GBROWSE_TEST_URL environment variable to the URL of a gbrowse_syn instance to run this test';
$base_url =~ s!/+$!!;

my $gbsyn_url = "$base_url/gbrowse_syn";

my $mech = Test::WWW::Mechanize->new;

$mech->get_ok( $gbsyn_url, 'got the default gbrowse_syn page' )
    or diag $mech->content;

# follow the first example link and check that it's OK
$mech->follow_link_ok(
    { url_regex => qr/^?search_src=/ },
    'followed first example link',
   );


my $new_width = change_image_width( $mech );

# follow the second example link and check that it's OK
$mech->follow_link_ok(
    { url_regex => qr/^?search_src=/, n => 2 },
    'followed first example link',
   );

# check that we still have the right image width
is( image_widths_state( $mech )->{selected}, $new_width,
    'still have the right image width' );

# check each of the images on the example view
for my $image ( $mech->images ) {
    $mech->get_ok( $image->url );
}


done_testing;

sub change_image_width {
    my $mech = shift;

    my $width_state = image_widths_state( $mech );

    #use Data::Dumper;
    #diag "current: $width_state->{selected} ".
    #  Dumper( $width_state->{configured} );

    my ($new_image_width) =
        grep { $_ != $width_state->{selected} }
        @{ $width_state->{configured} };

    diag "setting new image width $new_image_width";

    $mech->submit_form_ok({
        form_name => 'mainform',
        fields => {
            imagewidth => $new_image_width,
        },
    });

    return $new_image_width;
}

sub image_widths_state {
    my $mech = shift;

    my @configured_image_widths =
        $mech->content =~ m!type="radio" name="imagewidth" value="(\d+)"!gs;
    my ( $selected_image_width ) = $mech->content =~ m!type="radio" name="imagewidth" value="(\d+)" checked!;

    return {
        selected   => $selected_image_width,
        configured => \@configured_image_widths,
    };
}
