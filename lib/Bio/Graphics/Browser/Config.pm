package Bio::Graphics::Browser::Config;

# $Id: Config.pm,v 1.1.2.3 2003-06-30 20:24:59 pedlefsen Exp $
# Configuration data for gbrowse.

=head1 NAME

Bio::Graphics::Browser::Config -- Configuration data for gbrowse

=head1 SYNOPSIS

 use Bio::Graphics::Browser::Config;
 use Bio::Graphics::Browser::ConfigIO;

 my $config_io  =
   Bio::Graphics::Browser::ConfigIO->new( -file => 'features.txt' );

 my $config = $config_io->read_config();

 # create a new panel and render the config data onto it.
 my $features = $config->get_collection();
 my ( $tracks_rendered, $panel ) =
   new Bio::Graphics::Renderer()->render(
     $features,
     $config
   );
 my $tracks_rendered = $data->render( $panel );

=head1 DESCRIPTION

The Bio::Graphics::Browser::Config module stores the data necessary to
render a gbrowse image.  Once a Config object has been initialized,
you can get settings data via its
Bio::Graphics::Browser::ConfiguratorI interface, you can get a
Bio::SeqFeature::CollectionI object from it via its
Bio::SeqFeature::CollectionProviderI interface and interrogate it for its
consistuent features, or you can render it all onto a
Bio::Graphics::Panel using a Bio::Graphics::RendererI.

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the evolution of this and other
Bioperl modules. Send your comments and suggestions preferably to
the Bioperl mailing list.  Your participation is much appreciated.

  bioperl-l@bioperl.org              - General discussion
  http://bioperl.org/MailList.shtml  - About the mailing lists

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
of the bugs and their resolution. Bug reports can be submitted via
email or the web:

  bioperl-bugs@bioperl.org
  http://bugzilla.bioperl.org/

=head1 AUTHOR

Paul Edlefsen E<lt>paul@systemsbiology.orgE<gt>.
Copyright (c) 2003 Institute for Systems Biology

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=head1 CONTRIBUTORS

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut

# Let the code begin...

use strict;
use vars qw( @ISA $VERSION );

use Bio::DB::CompoundSegmentProvider;
use Bio::Graphics::SimpleConfigurator;
use Bio::DB::SegmentProviderI;
use Bio::LocallyIdentifiableI;
@ISA = qw( Bio::DB::CompoundSegmentProvider
           Bio::Graphics::SimpleConfigurator
           Bio::LocallyIdentifiableI );
$VERSION = '1.00';

use Carp;
use Text::Shellwords;

=head2 new

 Title   : new
 Usage   : my $config =
              new Bio::Graphics::Browser::Config( @args );
 Function: Builds a new Bio::Graphics::Browser::Config object 
 Returns : The new Config
 Args    : See below
 Status  : Public

  Argument  Value
  --------  -----
  -safe     Indicates that the contents of this config are trusted.  Any
            option value that begins with the string "sub {" will be
            evaluated as a code reference.  If safe is set, the
            get_and_eval(..) method will work, and calls to get(..)
            will be delegated thereto.  If safe is not set (the
            default), then get_and_eval will throw an exception.

=cut

sub new {
  my $caller = shift;
  my $self = $caller->SUPER::new( @_ );

  $self->_initialize_config( @_ );
  return $self;
} # new(..)

sub _initialize_config {
  my $self = shift;
  my @args = @_;

  return if( $self->{ '_config_initialized' } );

  $self->_initialize_simple_segment_provider( @args );
  $self->_initialize_simple_configurator( @args );

  my ( $safe );
  if( scalar( @args ) && ( $args[ 0 ] =~ /^-/ ) ) {
    ( $safe ) =
      $self->_rearrange( [ 'SAFE' ], @args );
  }

  $self->safe( $safe ) if defined( $safe );

  $self->{ '_config_initialized' }++;
  return $self;
} # _initialize_config(..)

=head2 unique_id

 Title   : unique_id
 Usage   : my $unique_id = $config->unique_id( [$new_unique_id] )
 Function: This is a unique identifier that identifies this Config object.
           If not set, will return undef per L<Bio::LocallyIdentifiableI>
           If a value is given, the unique_id will be set to it, unless that
           value is the string 'undef', in which case the unique_id will
           become undefined.
 Returns : The current (or former, if used as a set method) value of unique_id
 Args    : [optional] a new string unique_id or 'undef'

=cut

sub unique_id {
  my ( $self, $value ) = @_;
  my $current_value = $self->{ '_unique_id' };
  if ( defined $value ) {
    if( !$value || ( $value eq 'undef' ) ) {
      $self->{ '_unique_id' } = undef;
    } else {
      $self->{ '_unique_id' } = $value;
    }
  }
  return $current_value;
} # unique_id()

=head2 safe

 Title   : safe
 Usage   : my $safe = $config->safe( $new_val );
 Function: Getter/Setter for the safe flag.
 Returns : The current (or old, when setting) value of the safe flag.
 Args    : optional new boolean value
 Status  : Public

  If safe is set, the get_and_eval(..) method will work (any option
  value that begins with the string "sub {" will be evaluated as a
  code reference), and calls to get(..) will be delegated thereto.  If
  safe is not set (the default), then get_and_eval will throw an
  exception when a value begins with the string "sub {".

=cut

sub safe {
  my $self = shift;
  my $d = $self->{ '_safe' };
  $self->{ '_safe' } = shift if @_;
  $d;
} # safe(..)

=head2 search_notes

 Title   : search_notes
 Usage   : my @results = $config->search_notes( $search_term, $max_results )
 Function: full-text search on features, ENSEMBL-style
 Returns : an array of [$name,$description,$score]
 Args    : see below
 Status  : public

This routine performs a full-text search on feature attributes (which
attributes depend on implementation) and returns a list of
[$name,$description,$score], where $name is the feature ID,
$description is a human-readable description such as a locus line, and
$score is the match strength.

=cut

## TODO: Make sure that Config supports the special search_notes(..) method.
#my @matches = grep { $match->( $_->[ 1 ] ) }
         #$self->config()->search_notes( $searchterm, $max_keywords );

sub search_notes {
  ## TODO: ERE I AM.  This will only happen when the keyword that the user put into the wee field in gbrowse doesn't correspond to anything real, so we have to go looking in the description... see _do_keyword_search(..) in Browser.pm.
} # search_notes(..)

=head2 get_and_eval

 Title     : get_and_eval
 Usage     : my $value = $configurator->get_and_eval('height');
             or
             my $value = $configurator->get_and_eval('dna','height');
 Function  : This works like get() except that it is
             also able to evaluate code references.  These are
             options whose values begin with the characters
             "sub {".  In this case the value will be passed to
             an eval() and the resulting codereference returned.
 Returns   : A value of the tag or undef.
 Args      : The tag name is required.  If there are two arguments then the
             first will be interpreted as the section name.  If it is
             undef or 'general' or 'default' then the default section
             will be used.
 Exception : "Unsafe to eval" when the safe() flag is not set and the
             value begins with "sub {".

  THIS COULD BE DANGEROUS!  Arbitrarily eval\'ing user code is unwise.
  You have been warned.  See safe().

=cut

# This is overridden to throw an exception when safe() is false and we
# would otherwise eval.
sub get_and_eval {
  my $self = shift;
  my $val = $self->get( @_ );
  return $val unless ( defined( $val ) && ( $val =~ /^sub\s*\{/ ) );
  unless( $self->safe() ) {
    $self->throw( "Unsafe to eval" );
  }
  my $coderef = eval $val;
  warn $@ if $@;
  return $coderef;
} # get_and_eval(..)

## Utility methods ##

# Return just those sections that are not for the overview panel.
sub labels {
  grep { !($_ eq 'overview' || /:(\d+|overview)$/) } shift->get_sections();
}

# Return just those sections that are for the overview panel.
sub overview_tracks {
  grep { $_ eq 'overview' || /:overview$/ } shift->get_sections();
}

# Return the 'feature' tag value for the given section label.
sub label2type {
  my $self = shift;
  my ( $label, $length ) = @_;
  my $semantic_label = $self->semantic_label( $label, $length );

  ## TODO: REMOVE
  #warn "Config::label2type( $label, $length ): semantic label is $semantic_label.\n";

  ## TODO: Note that this used to default to '' instead of to the (semantic) label value.
  return shellwords(
           $self->get( $semantic_label, 'feature' ) ||
           $self->get( $label,          'feature' ) ||
           $semantic_label ||
           $label
         );
} # label2type(..)

## TODO: I dunno.  Does add_track have to take things like it does?
=head2 style

@args = $features-E<gt>style($type)
Given a feature type, returns a list of track configuration arguments
suitable for suitable for passing to the
Bio::Graphics::Panel-E<gt>add_track() method.

=cut

# turn configuration into a set of -name=>value pairs suitable for add_track()
sub _style {
  my $self = shift;
  my $label = shift;

  #my $config  = $self->{config}  or return;
  #my $hashref = $config->{$type} or return;
  my @tags = $self->get_tags( $label );

  return map { ( "-$_" => $self->get( $label, $_ ) ) } @tags;
} # _style(..)

## TODO: ERE I AM.  Must figure out what to do with style..
sub style {
  my ($self,$label,$length) = @_;
  my $l = $self->semantic_label($label,$length);
  return $l eq $label ? $self->_style($l) : ($self->_style($label),$self->_style($l));
}

sub semantic_label {
  my $self = shift;
  my ( $label, $length ) = @_;
  return $label unless( defined( $length ) && ( $length > 0 ) );

  # look for:
  # 1. a section like "Gene:100000" where the cutoff is less than the length of the segment
  #    under display.
  # 2. a section like "Gene" which has no cutoff to use.
  if( my @lowres = map { [ split ':' ] }
      grep { /$label:(\d+)/ && ( $1 <= $length ) }
      $self->get_sections()
    ) {
    ( $label ) = map { join( ':', @$_ ) }
                     sort { $b->[ 1 ] <=> $a->[ 1 ] } @lowres;
    }
  return $label;
} # semantic_label(..)

sub default_labels {
  my $self = shift;
  my $defaults = $self->get( 'default features' );
  return shellwords( $defaults || '' );
}

# return a hashref in which keys are the thresholds, and values are the list of
# labels that should be displayed
sub summary_mode {
  my $self = shift;
  my $summary = $self->get('summary mode') or return {};
  my %pairs = $summary =~ /(\d+)\s+{([^\}]+?)}/g;
  foreach (keys %pairs) {
    my @l = shellwords($pairs{$_}||'');
    $pairs{$_} = \@l
  }
  \%pairs;
}

# return language-specific options
sub i18n_style {
  my $self      = shift;
  my ($label,$lang,$length) = @_;
  return $self->style($label,$length) unless $lang;

  my $charset   = $lang->tr('CHARSET');

  # GD can't handle non-ASCII/LATIN scripts transparently
  return $self->style($label,$length) 
    if $charset && $charset !~ /^(us-ascii|iso-8859)/i;

  my @languages = $lang->language;

  push @languages,'';
  # ('fr_CA','fr','en_BR','en','')

  my $idx = 1;
  my %priority = map {$_=>$idx++} @languages;
  # ('fr-ca'=>1, 'fr'=>2, 'en-br'=>3, 'en'=>4, ''=>5)

  my %options  = $self->style($label,$length);
  my %lang_options = map { $_->[1] => $options{$_->[0]} }
  sort { $b->[2]<=>$a->[2] }
  map { my ($option,undef,$lang) = /^(-[^:]+)(:(\w+))?$/; [$_ => $option, $priority{$lang}||99] }
  keys %options;

  %lang_options;
}

sub add_config {
  ## TODO: Do something.
} # add_config(..)

sub remove_config {
  ## TODO: Do something.
} # remove_config(..)

## TODO: ERE I AM
sub initialize_segment_providers {
  my $self = shift;

  ## TODO: Make this better...
  my $db_adaptor = $self->get_and_eval( 'db_adaptor' ) || 'Bio::DB::GFF';
  my $db_args    = $self->get_and_eval( 'db_args' );
  my $db_user    = $self->get_and_eval( 'user' );
  my $db_pass    = $self->get_and_eval( 'pass' );

  return unless $db_args;

  unless( eval "require $db_adaptor; 1" ) {
    warn $@;
    return;
  }
  my @argv =
    ( ( ref $db_args eq 'CODE' ) ?
      $db_args->() :
      shellwords( $db_args || '' ) );

  # for compatibility with older versions of the browser, we'll
  # hard-code some arguments
  if( my $adaptor = $self->get( 'adaptor' ) ) {
    push( @argv, ( '-adaptor' => $adaptor ) );
  }
  if( my $dsn = $self->get( 'database' ) ) {
    push( @argv, ( '-dsn' => $dsn ) );
  }

  if( my $fasta = $self->get( 'fasta_files' ) ) {
    push( @argv, ( '-fasta' => $fasta ) );
  }

  if( $db_user ) {
    push( @argv, ( '-user' => $db_user ) );
  }

  if( $db_pass ) {
    push( @argv, ( '-pass' => $db_pass ) );
  }

  ## TODO: Here is where we should add the special aggregators for the
  ## per-section "group pattern" entries.

  my @aggregators = shellwords( $self->get( 'aggregators' ) || '' );
  if( my @auto_aggregator_factory_classes =
      $self->get( 'auto_aggregators' ) ) {
    ## TODO: REMOVE
    #warn "auto aggregator factory: ".$auto_aggregator_factory_classes[ 0 ];
    my @auto_aggregator_factories;
    foreach my $class ( @auto_aggregator_factory_classes ) {
      ## TODO: Why is this line necessary?
      next unless $class;
      ## TODO: REMOVE
      #warn "Loading $class";
      unless( eval( "require $class" ) ) {
        warn $@ if $@;
        next;
      }
      ## TODO: REMOVE
      #warn "Instantiating $class";
      push( @auto_aggregator_factories, $class->new() );
    }
    if( @auto_aggregator_factories ) {
      foreach my $section ( $self->get_sections() ) {
        foreach my $factory ( @auto_aggregator_factories ) {
          ## TODO: REMOVE
          #warn "applying $factory to section $section";
          push( @aggregators, $factory->create_aggregator( $self, $section ) );
        }
      }
    }
  }
  if( @aggregators ) {
    ## TODO: REMOVE
    #warn "The aggregators are ( ".join( ', ', @aggregators )." )";
    push( @argv, ( '-aggregator' => \@aggregators ) );
  }

  my $segment_provider = eval{ $db_adaptor->new( @argv ) };
  if( $@ ) {
    warn $@;
    return;
  }
  ## TODO: REMOVE
  #warn "Adding segment provider $segment_provider.\n";
  $self->add_next_provider( $segment_provider );
} # initialize_segment_providers(..)

## TODO: Everything should delegate.  These are just reminders...

## TODO: seq_ids() in Config should delegate.
#my @seq_ids      = sort $config->seq_ids();

## TODO: types() in Config should delegate...
#my @types = $self->config()->types();

1;

__END__
