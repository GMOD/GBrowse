package Bio::Graphics::Browser::Constants;
use strict;

BEGIN {
  use Exporter;
  use base qw(Exporter);
  use vars qw(@EXPORT);

  #these are all prefixed by 'GBROWSE_' in the export
  my %constants = (
                   # if you change the zoom/nav icons, you must change this as well.
                   MAG_ICON_HEIGHT        => 20,
                   MAG_ICON_WIDTH         => 8,
                   # had-coded values for segment sizes
                   # many of these can be overridden by configuration file entries
                   MAX_SEGMENT            => 1_000_000,
                   MIN_SEG_SIZE           => 20,
                   TINY_SEG_SIZE          => 2,
                   EXPAND_SEG_SIZE        => 5000,
                   TOO_MANY_SEGMENTS      => 5_000,
                   TOO_MANY_FEATURES      => 100,
                   TOO_MANY_REFS          => TOO_MANY_FEATURES,
                   DEFAULT_SEGMENT        => 100_000,
                   OVERVIEW_RATIO         => 0.9,
                   ANNOTATION_EDIT_ROWS   => 25,
                   ANNOTATION_EDIT_COLS   => 100,
                   URL_FETCH_TIMEOUT      => 5,  # five seconds max!
                   URL_FETCH_MAX_SIZE     => 1_000_000,  # don't accept any files larger than 1 Meg
                   MAX_KEYWORD_RESULTS    => 1_000,     # max number of results from keyword search
                   DEFAULT_RANGES         => q(100 500 1000 5000 10000 25000 100000 200000 400000),
                   DEFAULT_FINE_ZOOM      => '10%',
                   GBROWSE_HELP           => '/gbrowse',
                   DEFAULT_PLUGINS        => 'FastaDumper RestrictionAnnotator SequenceDumper',
                   # if true, turn on surrounding rectangles for debugging the image map
                   DEBUG                  => 0,
                   DEBUG_EXTERNAL         => 0,
                   DEBUG_PLUGINS          => 0,
                   # amount of time to remember persistent settings
                   REMEMBER_SETTINGS_TIME => '+7d',  # 7 days
                   REMEMBER_SOURCE_TIME   => '+3M',  # 3 months
                   GLOBAL_TIMEOUT         => 60,  # 60 seconds to failure unless overridden in config

                  );

  foreach my $tmp (keys %constants) {
    no strict 'refs';
    my $mangle = "GBROWSE_$tmp";
    my $symbol = __PACKAGE__."::$mangle";
    *$symbol = sub { return $constants{$tmp} };
  }
  push @EXPORT, (keys %constants);
}

1;
