package Bio::Graphics::Browser::ConfigIO;

# $Id: ConfigIO.pm,v 1.1.2.1 2003-05-23 16:38:06 pedlefsen Exp $
# This package parses a simple tab-delimited format for features into
# a Config object.  It is simpler than GFF, but still has a lot of
# expressive power.
# See __END__ for the file format

=head1 NAME

Bio::Graphics::Browser::ConfigIO -- IO for Config files for gbrowse

=head1 SYNOPSIS

 use Bio::Graphics::Browser::ConfigIO;
 my $config_io =
   Bio::Graphics::Browser::ConfigIO->new( -file => 'features.txt' );

 # create a new panel and render contents of the file onto it
 my $features = $data_provider->getCollection();
 my ( $tracks_rendered, $panel ) =
   new Bio::Graphics::Renderer()->render(
     $features,
     $config_io->getCollection()
   );
 my $tracks_rendered = $data->render( $panel );

 # get individual settings
 my $est_fg_color =
  $config_io->getCollection( @args )->setting( EST => 'fgcolor' );

=head1 DESCRIPTION

The Bio::Graphics::Browser::ConfigIO module reads and parses files
that describe sequence features and their renderings.  It accepts both
GFF format and a more human-friendly file format described below.
Once a ConfigIO object has been initialized, you can get a Config
object from it and interrogate it for its consistuent features and
their settings, or render the entire file onto a Bio::Graphics::Panel.

=head2 The File Format

There are two types of entry in the file format: feature entries, and
formatting entries.  They can occur in any order.  See the Appendix
for a full example.

Feature entries can take several forms.  At their simplest, they look
like this:

 Gene	B0511.1	516-11208

This means that a feature of type "Gene" and name "B0511.1" occupies
the range between bases 516 and 11208.  A range can be specified
equally well using a hyphen, or two dots as in 516..11208.  Negative
coordinates are allowed, such as -187..1000.

A discontinuous range ("split location") uses commas to separate the
ranges.  For example:

 Gene B0511.1  516-619,3185-3294,10946-11208

Alternatively, the locations can be split by repeating the features
type and name on multiple adjacent lines:

 Gene	B0511.1	516-619
 Gene	B0511.1	3185-3294
 Gene	B0511.1	10946-11208

A comment can be added to features by adding a fourth column.  These
comments will be rendered as under-the-glyph descriptions by those
glyphs that honor descriptions:

 Gene  B0511.1  516-619,3185-3294,10946-11208 "Putative primase"

Columns are separated using whitespace, not (necessarily) tabs.
Embedded whitespace can be escaped using quote marks or backslashes in
the same way as in the shell:

 'Putative Gene' my\ favorite\ gene 516-11208

Features can be grouped so that they are rendered by the "group" glyph
(so far this has only been used to relate 5' and 3' ESTs).  To start a
group, create a two-column feature entry showing the group type and a
name for the group.  Follow this with a list of feature entries with a
blank type.  For example:

 EST	yk53c10
 	yk53c10.3	15000-15500,15700-15800
 	yk53c10.5	18892-19154

This example is declaring that the ESTs named yk53c10.3 and yk53c10.5
belong to the same group named yk53c10.  

=cut

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

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2003 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=head1 CONTRIBUTORS

Paul Edlefsen E<lt>paul@systemsbiology.orgE<gt>.
Robert Hubley E<lt>rhubley@systemsbiology.orgE<gt>.

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut

# Let the code begin...

# Object preamble - inherits from Bio::Root::IO
use strict;
use Bio::Root::IO;
use vars qw( @ISA $VERSION );
@ISA = qw( Bio::Root::IO );
$VERSION = '1.04';

use Bio::DB::GFF::Util::Rearrange; # for rearrange()
use Bio::Graphics::Browser::Config;
use Bio::Graphics::Feature;
use Bio::SeqFeature::Collection;
use Text::Shellwords;

if( Bio::Graphics::Browser::DEBUG ) {
  use Data::Dumper;
}

=head2 new

 Title   : new
 Usage   : my $config_io =
              new Bio::Graphics::Browser::ConfigIO( $filename );
 Function: Builds a new Bio::Graphics::Browser::ConfigIO object 
 Returns : The new ConfigIO
 Args    : See below
 Status  : Public

  Argument         Value
  --------         -----

   -file           Read data from a file path.  Use "-" to read from standard
                   input.

   -fh             Read data from an open filehandle.

   -text           Read data from a string.

   -coordinate_mapper  Coderef containing a subroutine to use for 
                       remapping all coordinates.

   -safe           Indicates that the contents of this file is trusted.
                   Any option value that begins with the string "sub {"
                   will be evaluated as a code reference.

The -text and -file and -fh arguments are mutually exclusive.

Note that, as a side-effect, this method will open a filehandle to
the named file if there is one.

The optional -coordinate_mapper argument points to a coderef with the
following signature:

  ($newref,[$start1,$end1],[$start2,$end2]....)
            = coderef($ref,[$start1,$end1],[$start2,$end2]...)

See the Bio::Graphics::Browser (part of the generic genome browser
package) for an illustration of how to use this to do wonderful stuff.

A true -safe argument will set the 'safe' flag of the Config object
generated hereby to true.

TODO: Add code to make sure at least one of the three 
      datasources has been correctly specified

=cut

sub new {
  my $caller = shift;
  my $self = $caller->SUPER::new( @_ );

  my ( $text, $coordinate_mapper, $safe );
  if( $_[ 0 ] =~ /^-/ ) {
    ( $text, $coordinate_mapper,  $safe ) =
      rearrange([
                 [qw(TEXT STRING)],
                 [qw(COORDINATE_MAPPER MAP MAPCOORDS MAP_COORDS)],
                 'SAFE'
                ], @_ );
  }

  $self->text( $text ) if defined( $text );
  $self->coordinate_mapper( $coordinate_mapper )
    if defined( $coordinate_mapper );
  $self->safe( $safe ) if defined( $safe );

  return $self;
} # new(..)

=head2 text

 Title   : text
 Usage   : my $text = $config_io->text( $new_val );
 Function: Getter/Setter for the text string.
 Returns : The current (or old, when setting) value of the text string.
 Args    : optional new string
 Status  : Public

=cut

sub text {
  my $self = shift;
  my $d = $self->{ '_text' };
  $self->{ '_text' } = shift if @_;
  $d;
} # text(..)

=head2 coordinate_mapper

 Title   : coordinate_mapper
 Usage   : my $coordinate_mapper = $config_io->coordinate_mapper( $new_val );
 Function: Getter/Setter for the coordinate_mapper code ref.
 Returns : The current (or old, when setting) value of the coordinate_mapper ref.
 Args    : optional new code ref
 Status  : Public

The coordinate_mapper is a coderef with the following signature:

  ($newref,[$start1,$end1],[$start2,$end2]....)
            = coderef($ref,[$start1,$end1],[$start2,$end2]...)

=cut

sub coordinate_mapper {
  my $self = shift;
  my $d = $self->{ '_coordinate_mapper' };
  $self->{ '_coordinate_mapper' } = shift if @_;
  $d;
} # coordinate_mapper(..)

=head2 safe

 Title   : safe
 Usage   : my $safe = $config_io->safe( $new_val );
 Function: Getter/Setter for the safe flag.
 Returns : The current (or old, when setting) value of the safe flag.
 Args    : optional new boolean value
 Status  : Public

If the safe flag is set when a Config object is generated by
this ConfigIO then its safe flag will also be set.

=cut

sub safe {
  my $self = shift;
  my $d = $self->{ '_safe' };
  $self->{ '_safe' } = shift if @_;
  $d;
} # safe(..)

=head2

 Title   : read_config
 Usage   : my $config = $config_io->read_config();
 Function: Read a config file and parse its contents
 Returns : A L<Bio::Graphics::Browser::Config> object.
 Args    : None
 Status  : Public

=cut

sub read_config {
  my $self = shift;

  # Create a new configurator
  my $config = new Bio::Graphics::Browser::Config( '-safe' => $self->safe() );

  my $parse_state = $self->_init_parse( $config );
  if ( my $text = $self->text() ) {
    foreach ( split /\r?\n|\r\n?/, $text ) {
      $self->_parse_line( $parse_state, $_ );
    }
  } elsif( defined ( my $fh = $self->_fh() ) ) {
    while( <$fh> ) {
      chomp;
      $self->_parse_line( $parse_state, $_ );
    }
  } else {
    $self->throw( "Ack! ConfigIO::read_config() - I do not have any datasources to read from!" );
  }
  $self->_finish_parse( $parse_state );

  return $config;
} # read_config(..)

=head2

 Title   : _init_parse
 Usage   : my $parse_state =
                $config_io->_init_parse( [$config [, $parse_state ]] );
 Function: Create a parse state object.
 Returns : A L<Bio::Grahics::Browser::ConfigIO_ParseState> object.
 Args    : [optional] The L<Bio::Grahics::Browser::Config> object to build,
           [optional] A L<Bio::Grahics::Browser::ConfigIO_ParseState> to use.
 Status  : Protected

  If no Config object is provided then one will be created with its
  safe() attribute set to the safe() attribute of this ConfigIO
  object.

=cut

sub _init_parse {
  my $self = shift;
  my $config = shift ||
    Bio::Graphics::Browser::Config->new( '-safe' => $self->safe() );

  # Set the unique_id, if it isn't already set, to the filename, if
  # there is one.
  ## TODO: This might be dangerous, because it is conceivable that the filename won't be a *unique* unique_id ( although it really should be, I think ).
  if( $self->file() &&
      !defined( $config->unique_id() ) &&
      ( $self->file() ne '-' ) ) {
    $config->unique_id( $self->file() );
  }

  my $parse_state = shift;
  if( defined( $parse_state ) ) {
    $parse_state->reset();
    $parse_state->config( $config );
  } else {
    $parse_state =
      Bio::Graphics::Browser::ConfigIO_ParseState->new( $config );
  }
  return $parse_state;
} # _init_parse(..)

=head2

 Title   : _parse_line
 Usage   : $config_io->_parse_line( $parse_state, $string );
 Function: Parses a line of a config file.
 Returns : nothing
 Args    : a L<Bio::Grahics::Browser::ConfigIO_ParseState> object and a string.
 Status  : Protected

=cut

## TODO: At some point we should probably switch to using Bio::Tools::GFF for parsing the GFF lines.  I'm not sure if that supports the strange multi-line grouping, though.  See Bio::Tools::GFF->from_gff_string( $feature, $gff_line );
sub _parse_line {
  my $self = shift;
  my $parse_state = shift;
  local $_ = shift; # For the lazy programmer.

  # Get rid of carriage returns left over by MS-DOS/Windows systems
  s/\r//g;

  return if /^\s*[\#]/; # Comment line

  ## TODO: REMOVE
  #warn "_parse_line( '$_' )\n" if Bio::Graphics::Browser::DEBUG;

  my $config = $parse_state->config();
  my $current_section = $parse_state->current_section() || 'general';
  my $current_tag = $parse_state->current_tag();
  if( /^\s+(.+)/ && $current_tag ) { # Continuation line
    ## TODO: REMOVE
    #warn "CONTINUATION\n" if Bio::Graphics::Browser::DEBUG;

    my $tag_value;
    if ( $current_section eq 'general' ) {
      $tag_value = $config->get( $current_tag );
    } else {
      $tag_value = $config->get( $current_section, $current_tag );
    }
    # Append to the current value
    $tag_value .= ' ' . $1;

    # Respect newlines in code subs only.
    $tag_value .= "\n" if( $tag_value =~ /^sub\s*\{/ );
    if ( $current_section eq 'general' ) {
      $config->set( $current_tag, $tag_value );
    } else {
      $config->set( $current_section, $current_tag, $tag_value );
    }
    return;
  } # End if this is a continuation line

  if( /^\s*\[([^\]]+)\]/ ) { # New section
    ## TODO: REMOVE
    #warn "NEW SECTION: $1\n" if Bio::Graphics::Browser::DEBUG;

    my $label = $1;
    # normalize
    $current_section =
      ( ( $label =~ /^(general|default)$/i ) ? 'general' : $label );
    $parse_state->current_section( $current_section );
    $parse_state->current_tag( 'undef' );
    return;
  } # End if this is the beginning of a new section

  if( /^([\w: -]+?)\s*=\s*(.*)/ ) { # Key/value pair
    ## TODO: REMOVE
    #warn "KEY/VALUE: '$1' = '$2'\n" if Bio::Graphics::Browser::DEBUG;

    $current_tag = lc $1;
    my $tag_value = ( ( defined $2 ) ? $2 : '' );
    if( $current_section ne 'general' ) {
      $config->set( $current_section, $current_tag, $tag_value );
    } else {
      $config->set( $current_tag, $tag_value );
    }
    $parse_state->current_tag( $current_tag );
    return;
  }

  if( /^$/ ) { # Empty line
    ## TODO: REMOVE
    #warn "EMPTY\n" if Bio::Graphics::Browser::DEBUG;

    $parse_state->current_tag( 'undef' );
    return;
  }

  # parse data lines
  my @tokens = eval { shellwords( $_ || '' ) };
  unshift @tokens, '' if /^\s+/;

  # close any open group
  $parse_state->group_feature( 'undef' ) if( ( length $tokens[ 0 ] ) > 0 );

  if( @tokens < 3 ) { # short line; assume a group identifier
    ## TODO: REMOVE
    #warn "SHORT LINE, GROUP ID\n" if Bio::Graphics::Browser::DEBUG;

    $parse_state->group_type( shift @tokens );
    $parse_state->group_name( shift @tokens );

    my $ref = $parse_state->reference();
    unless( defined( $ref ) ) {
      # Make a new reference sequence.
      my $id  = ( $config->get( $current_section, 'reference' ) ||
                  $config->get( 'reference' ) );
      unless( $id ) {
        $parse_state->reference( '' );
      } else {
        my $len = ( $config->get( $current_section, 'bases' ) ||
                    $config->get( 'bases' ) );
        ( $len ) = ( $len =~ /^.+?-?(\d+)$/ );
        ## TODO: REMOVE
        #warn "\$len for '$id' is $len" if Bio::Graphics::Browser::DEBUG;
        $parse_state->reference(
          Bio::PrimarySeq->new(
            '-unique_id'  => $id,
            '-primary_id' => $id,
            '-display_id' => $id,
            '-accession'  => $id,
            '-alphabet'   => 'dna',
            '-seq'        => ( $len ? ( 'n' x $len ) : '' )
          )
        );
      }
      $ref = $parse_state->reference();
      ## TODO: REMOVE
      #warn "'$id' is $ref" if Bio::Graphics::Browser::DEBUG;
    }
    $parse_state->group_feature(
      Bio::Graphics::Feature->new(
        '-name'   => $parse_state->group_name(),
        '-type'   => $parse_state->group_type(),
        '-seq_id' => $ref
      )
    );
    ## TODO: REMOVE
    #warn "Adding group feature ", $parse_state->group_feature(), " with name ", $parse_state->group_feature()->name(), ", type ", $parse_state->group_feature()->type(), ", and seq_id ", $parse_state->group_feature()->seq_id(), "\n" if Bio::Graphics::Browser::DEBUG;
    unless( $parse_state->add_features( $parse_state->group_feature() ) ) {
      warn "Ignoring duplicate feature ", $parse_state->group_feature(), ".\n";
    }
    return;
  }

  my ( $ref, $type, $name, $strand, $bounds, $description, $url );
  my ( $source, $method, $start, $stop, $score, $phase,
       $target, $target_start, $target_end );
  if( @tokens >= 8 ) { # conventional GFF file
    ## TODO: REMOVE
    #warn "CONVENTIONAL GFF LINE\n" if Bio::Graphics::Browser::DEBUG;

    my ( @rest );
    ( $ref, $source, $method, $start, $stop, $score, $strand, $phase, @rest ) =
      @tokens;
    my $group = join ' ', @rest;
    $type     = join( ':', $method, $source );
    $bounds   = join( '..', $start, $stop );

    if( $group ) {
      my ( $notes, @notes );
      ## TODO: Use $target_start and $target_end somehow.
      ( undef, $target, $target_start, $target_end, $notes ) =
        $self->_split_group( $group );
      ## TODO: I removed the following because full GFF lines shouldn't start groups the way that short lines do, I think.
      #$parse_state->group_name( $target );
      ## TODO: If we undo my target changes, remove the following line.
      $name = $target;
      foreach ( @$notes ) {
        if( m!^(http|ftp)://! ) {
          $url = $_;
        } else {
          push( @notes, $_ );
        }
      }
      $description = join( '; ', @notes ) if @notes;
    }
    ## TODO: I removed the following because full GFF lines shouldn't inherit groups, I think..
    #$name = $parse_state->group_name();
  } elsif( $tokens[ 2 ] =~ /^([+-.]|[+-]?[01])$/ ) { # Old simplified version
    ## TODO: REMOVE
    #warn "OLD SIMPLE GFF LINE\n" if Bio::Graphics::Browser::DEBUG;

    ( $type, $name, $strand, $bounds, $description, $url ) = @tokens;
  } else {                                           # New simplified version
    ## TODO: REMOVE
    #warn "NEW SIMPLE GFF LINE\n" if Bio::Graphics::Browser::DEBUG;

    ( $type, $name, $bounds, $description, $url ) = @tokens;
  }

  $type ||= ( $parse_state->group_type() || '' );
  $type =~ s/\s+$//;  # Get rid of excess whitespace

  # the reference is specified by the GFF reference line first,
  # or the last reference line we saw,
  # or the reference line in the "general" section.
  my $ps_reference = $parse_state->reference();
  if( defined( $ps_reference ) &&
      ( $ref ? ( $ps_reference->seq_id() eq $ref ) : 1 )
    ) {
    $ref = $ps_reference;
  } else {
    # Make a new reference sequence.
    my $id  = ( $ref ||
                $config->get( $current_section, 'reference' ) ||
                $config->get( 'reference' ) );
    unless( $id ) {
      $parse_state->reference( '' );
    } else {
      my $len = ( $config->get( $current_section, 'bases' ) ||
                  $config->get( 'bases' ) );
      ( $len ) = ( $len =~ /^.+?-?(\d+)$/ );
      ## TODO: REMOVE
      #warn "\$len for '$id' is $len" if Bio::Graphics::Browser::DEBUG;
      $parse_state->reference(
        Bio::PrimarySeq->new(
          '-unique_id'  => $id,
          '-primary_id' => $id,
          '-display_id' => $id,
          '-accession'  => $id,
          '-alphabet'   => 'dna',
          '-seq'        => ( $len ? ( 'n' x $len ) : '' )
        )
      );
    }
    $ref = $parse_state->reference();
    ## TODO: REMOVE
    #warn "'$id' is $ref" if Bio::Graphics::Browser::DEBUG;
  }

  ## TODO: Was this being used by anyone?
  # $parse_state->refs->{ $ref }++ if defined $ref;

  my @parts;
  if( defined( $bounds ) ) {
    @parts = map { [/(-?\d+)(?:-|\.\.)(-?\d+)/] } split /(?:,| )\s*/, $bounds;
    ## TODO: REMOVE
    #warn "Got parts ( " if Bio::Graphics::Browser::DEBUG;
    #foreach my $part ( @parts ) {
    #  warn " [ ", join( ", ", @$part ), " ], " if Bio::Graphics::Browser::DEBUG;
    #}
    #warn " ) by parsing bounds '$bounds'.  ref is $ref.\n" if Bio::Graphics::Browser::DEBUG;
  } else {
    @parts = ( [ $start, $stop ] );
  }
  if( $self->coordinate_mapper() && $ref ) {
    ## TODO: REMOVE
    #warn "Using coordinate_mapper to fixup parts.  Before: ( ", join( ", ", @parts ), " )\n" if Bio::Graphics::Browser::DEBUG;
    ( $ref, @parts ) = $self->coordinate_mapper()->( $ref, @parts );
    ## TODO: REMOVE
    #warn "After: ( ", join( ", ", @parts ), " )\n" if Bio::Graphics::Browser::DEBUG;
    return unless $ref;
  }

  $type = '' unless defined $type;
  $name = '' unless defined $name;
  # Either create a new feature or add a segment to it
  ## TODO: This will lose some of its former efficiency if features can be part of more than one group.
  my ( $feature ) =
    ( $parse_state->group_feature() ?
      $parse_state->group_feature()->features(
        '-type' => $type,
        '-name' => $name
      ) :
      $parse_state->features( '-type' => $type, '-name' => $name ) );
  if( defined $feature ) {
    ## TODO: REMOVE
    #warn "Adding parts ( ", join( ", ", @parts ), " ) to feature $feature" if Bio::Graphics::Browser::DEBUG;
    if( $feature->feature_count() == 0 ) {
      # The current range is now just a subpart, like the others.
      $feature->add_features( $self->_feature_strings( [ $feature->seq_id(), $feature->start(), $feature->end() ] ) );
    }
    my @feature_strings = $self->_feature_strings( $ref, @parts );
    foreach my $feature_string ( @feature_strings ) {
      unless( $feature->add_features( $feature_string ) ) {
        warn "Ignoring duplicate feature $feature_string.";
      }
    }
  } elsif( scalar( @parts ) > 1 ) {
    my @feature_strings = $self->_feature_strings( $ref, @parts );
    my @args =
      (
       '-name'       => $name,
       '-type'       => $type,
       ( $strand ?
         ( '-strand' => $strand ) :
         () ),
       '-features'   => \@feature_strings,
       '-desc'       => $description,
       '-seq_id'     => $ref,
       ( defined( $score ) ?
         ( '-score' => $score ) :
         () ),
       ( defined( $url ) ?
         ( '-url'    => $url ) :
         () )
      );
    ## TODO: REMOVE
    #warn "Creating feature with args { " . join( ', ', @args ) . ' }' if Bio::Graphics::Browser::DEBUG;
    $feature = Bio::Graphics::Feature->new( @args );
    if( $parse_state->group_feature() ) {
      ## TODO: REMOVE
      #warn "Adding feature $feature to group feature " . $parse_state->group_feature() if Bio::Graphics::Browser::DEBUG;
      unless( $parse_state->group_feature()->add_features( $feature ) ) {
        warn "Ignoring duplicate feature $feature.";
      }
    } else {
      ## TODO: REMOVE
      #warn "Adding feature $feature" if Bio::Graphics::Browser::DEBUG;
      unless( $parse_state->add_features( $feature ) ) {
        warn "Ignoring duplicate feature $feature." if Bio::Graphics::Browser::DEBUG;
      }
    }
  } else {
    ( $start, $stop ) = @{ $parts[ 0 ] };
    my @args =
      (
       '-name'       => $name,
       '-type'       => $type,
       '-start'      => $start,
       '-end'        => $stop,
       ( $strand ?
         ( '-strand' => $strand ) :
         () ),
       '-desc'       => $description,
       '-seq_id'     => $ref,
       ( defined( $score ) ?
         ( '-score' => $score ) :
         () ),
       ( defined( $url ) ?
         ( '-url'    => $url ) :
         () )
      );
    ## TODO: REMOVE
    #warn "Creating feature with args { " . join( ', ', @args ) . ' }' if Bio::Graphics::Browser::DEBUG;
    $feature = Bio::Graphics::Feature->new( @args );
    if( $parse_state->group_feature() ) {
      ## TODO: REMOVE
      #warn "Adding feature $feature to group feature " . $parse_state->group_feature() if Bio::Graphics::Browser::DEBUG;
      unless( $parse_state->group_feature()->add_features( $feature ) ) {
        warn "Ignoring duplicate feature $feature.";
      }
    } else {
      ## TODO: REMOVE
      #warn "Adding feature $feature" if Bio::Graphics::Browser::DEBUG;
      unless( $parse_state->add_features( $feature ) ) {
        warn "Ignoring duplicate feature $feature.";
      }
    }
  }
} # _parse_line(..)

=head2

 Title   : _finish_parse
 Usage   : my $config = config_io->finish_parse( $parse_state );
 Function: Completes parsing and returns the new Config object.
 Returns : a L<Bio::Graphics::Browser::Config> object.
 Args    : a L<Bio::Grahics::Browser::ConfigIO_ParseState> object.
 Status  : Protected

=cut

sub _finish_parse {
  my $self = shift;
  my $parse_state = shift;

  # Convert all code-type tag values into CODE (from strings)
  my $config = $parse_state->config();
  foreach my $section ( undef, $config->get_sections() ) {
    foreach my $tag ( $config->get_tags( $section ) ) {
      if( defined( $section ) ) {
        $config->set(
          $section,
          $tag,
          $config->get_and_eval( $section, $tag )
        );
      } else { # 'general' section.
        $config->set(
          $tag,
          $config->get_and_eval( $tag )
        );
      }
    } # End foreach $tag
  } # End foreach $section

  # Make sure that all of the features are appropriately sized to hold
  # their subfeatures.
  $parse_state->features( '-callback' => \&__adjust_bounds );

  my @sequences =
    grep { $_ && ref( $_ ) && $_->isa( 'Bio::PrimarySeqI' ) }
         $parse_state->references();

  ## TODO: REMOVE
  #warn "Adding ", scalar( @sequences ), " sequences to the config." if Bio::Graphics::Browser::DEBUG;

  # Add all of the reference sequences.
  $config->add_sequences( @sequences );

  ## TODO: REMOVE
  #warn "Adding ", $parse_state->feature_count(), " features to the config." if Bio::Graphics::Browser::DEBUG;

  # Make sure that the Config object has all of the features.
  $config->insert_or_update_collection( $parse_state );

  # If the config specifies any other data sources, get those set up.
  $config->initialize_segment_providers();

  # Now reset the parse state, just for sanity.
  $parse_state->reset();

  return $config;
} # _finish_parse(..)

sub __adjust_bounds {
  my $feature = shift;
  ## TODO: REMOVE
  #warn "adjusting bounds of feature $feature" if Bio::Graphics::Browser::DEBUG;
  $feature->adjust_bounds( 1 );
  ## TODO: REMOVE
  #warn "now it is $feature" if Bio::Graphics::Browser::DEBUG;
  return 1;
} # __adjust_bounds

=head2

 Title   : _feature_strings
 Usage   : my @feature_strings =
              $config_io->_feature_strings( [ $ref, $start, $end ], @more );
           OR
           my @feature_strings =
              $config_io->_feature_strings( $ref, [ $start, $end ], @more );
 Function: Create feature strings of the form "$seq_id:$start-$end"
           from triples of the form [ $seq_id, $start, $end ],
           or from a $seq_id and doubles of the form [ $start, $end ].
 Returns : A list of strings
 Args    : A list of triple refs or a $seq_id string/object and double refs.
 Status  : Protected

=cut

sub _feature_strings {
  my $self = shift;
  my $seq_id = shift;
  if( ref( $seq_id ) eq 'ARRAY' ) {
    unshift( @_, $seq_id );
    return map { $_->[ 0 ].':'.$_->[ 1 ].'-'.$_->[ 2 ] } @_;
  } else {
    return map { $seq_id.':'.$_->[ 0 ].'-'.$_->[ 1 ] } @_;
  }
} # _feature_strings(..)

=head2

 Title   : _split_group
 Usage   : my ( $gclass, $gname, $tstart, $tstop, $notes_list_ref ) =
              $config_io->_split_group( $group_string );
 Function: Split a group config file line into its data elements
 Returns : A quintuple
 Args    : A string
 Status  : Protected

=cut

sub _split_group {
  my $self = shift;
  my ( $group ) = @_;

  $group =~ s/\\\;/$;/g;  # protect embedded semicolons in the group
  $group =~ s/( \"[^\"]*);([^\"]*\")/$1$;$2/g;
  my @groups = split( /\s*;\s*/, $group );
  foreach ( @groups ) { s/$;/;/g }

  my ( $gclass, $gname, $tstart, $tstop, @notes );

  foreach ( @groups ) {
    my ( $tag, $value ) = /^(\S+)\s*(.*)/;
    $value =~ s/\\t/\t/g;
    $value =~ s/\\r/\r/g;
    $value =~ s/^\"//;
    $value =~ s/\"$//;

    # if the tag is "Note", then we add this to the
    # notes array
    if( $tag eq 'Note' ) { # just a note, not a group!
      push( @notes, $value );
    }

    # if the tag eq 'Target' then the class name is embedded in the ID
    # (the GFF format is obviously screwed up here)
    elsif( ( $tag eq 'Target' ) && ( $value =~ /([^:\"]+):([^\"]+)/ ) ) {
      ( $gclass, $gname ) = ( $1, $2 );
      if( $gname =~ /^(.+) (\d+) (\d+)$/ ) {
        ( $gname, $tstart, $tstop ) = ( $1, $2, $3 );
      }
    } elsif( !$value ) {
      push( @notes, $tag );  # e.g. "Confirmed_by_EST"
    }

    # otherwise, the tag and value correspond to the
    # group class and name
    else {
      ( $gclass, $gname ) = ( $tag, $value );
    }
  } # End foreach group line $_

  return ( $gclass, $gname, $tstart, $tstop, \@notes );
} # _split_group(..)

## Inner class ##############################################################
#============================================================================
# Bio::Graphics::Browser::ConfigIO_ParseState: A
# Bio::SeqFeature::SimpleCollection for storing the features in a file
# being parsed, with additional storage of the Config object being
# built and some parse state data.
#============================================================================
package Bio::Graphics::Browser::ConfigIO_ParseState;
use Bio::SeqFeature::SimpleCollection;
use vars qw( @ISA );

@ISA = qw( Bio::SeqFeature::SimpleCollection );

=head2 new

 Title   : new
 Usage   : my $parse_state = Bio::Graphics::Browser::ConfigIO_ParseState->new(
                               $config
                             );
 Function: Instantiates a new ParseState object.
 Returns : a new Bio::Graphics::Browser::ConfigIO_ParseState object.
 Args    : A L<Bio::Graphics::Browser::Config> object
 Status  : Public

=cut

sub new {
  my $caller = shift;
  my $config = shift;
  my $self = $caller->SUPER::new( @_ );

  $self->reset();
  $self->config( $config );

  return $self;
} # new(..)

sub reset {
  my $self = shift;

  $self->config( 'undef' );
  $self->current_section( 'undef' );
  $self->current_tag( 'undef' );
  $self->group_feature( 'undef' );
  $self->group_name( 'undef' );
  $self->group_type( 'undef' );
  $self->reference( 'undef' );

  return $self;
} # reset()

sub config {
  my $self = shift;
  my $new_value = shift;
  my $old_value = $self->{ '_cips_config' };
  if( defined( $new_value ) ) {
    if( $new_value eq 'undef' ) {
      undef $self->{ '_cips_config' };
    } else {
      $self->{ '_cips_config' } = $new_value;
    }
  }
  return $old_value;
} # config(..)

sub current_section {
  my $self = shift;
  my $new_value = shift;
  my $old_value = $self->{ '_cips_current_section' };
  if( defined( $new_value ) ) {
    if( $new_value eq 'undef' ) {
      undef $self->{ '_cips_current_section' };
    } else {
      $self->{ '_cips_current_section' } = $new_value;
    }
  }
  return $old_value;
} # current_section(..)

sub current_tag {
  my $self = shift;
  my $new_value = shift;
  my $old_value = $self->{ '_cips_current_tag' };
  if( defined( $new_value ) ) {
    if( $new_value eq 'undef' ) {
      undef $self->{ '_cips_current_tag' };
    } else {
      $self->{ '_cips_current_tag' } = $new_value;
    }
  }
  return $old_value;
} # current_tag(..)

sub reference {
  my $self = shift;
  my $new_value = shift;
  my $old_value =
    $self->{ '_cips_references' }{ $self->current_section() } ||
    $self->{ '_cips_references' }{ '_general' };

  if( defined( $new_value ) ) {
    if( $new_value eq 'undef' ) { # Undefine all of them.
      undef $self->{ '_cips_references' };
    } else {
      $self->{ '_cips_references' }{ $self->current_section() } = $new_value;
    }
  }
  return $old_value;
} # reference(..)

# return the list of all references.
sub references {
  my $self = shift;

  return values %{ $self->{ '_cips_references' } };
} # references()

sub group_feature {
  my $self = shift;
  my $new_value = shift;
  my $old_value = $self->{ '_cips_group_feature' };
  if( defined( $new_value ) ) {
    if( $new_value eq 'undef' ) {
      undef $self->{ '_cips_group_feature' };
    } else {
      $self->{ '_cips_group_feature' } = $new_value;
    }
  }
  return $old_value;
} # group_feature(..)

sub group_name {
  my $self = shift;
  my $new_value = shift;
  my $old_value = $self->{ '_cips_group_name' };
  if( defined( $new_value ) ) {
    if( $new_value eq 'undef' ) {
      undef $self->{ '_cips_group_name' };
    } else {
      $self->{ '_cips_group_name' } = $new_value;
    }
  }
  return $old_value;
} # group_name(..)

sub group_type {
  my $self = shift;
  my $new_value = shift;
  my $old_value = $self->{ '_cips_group_type' };
  if( defined( $new_value ) ) {
    if( $new_value eq 'undef' ) {
      undef $self->{ '_cips_group_type' };
    } else {
      $self->{ '_cips_group_type' } = $new_value;
    }
  }
  return $old_value;
} # group_type(..)

#============================================================================
## This is the end of ConfigIO_ParseState, an inner class of ConfigIO
#============================================================================
## End Inner class ##########################################################

1;

__END__

=head1 Appendix -- Sample Feature File

 # file begins
 [general]
 pixels = 1024
 bases = 1-20000
 reference = Contig41
 height = 12

 [Cosmid]
 glyph = segments
 fgcolor = blue
 key = C. elegans conserved regions

 [EST]
 glyph = segments
 bgcolor= yellow
 connector = dashed
 height = 5

 [FGENESH]
 glyph = transcript2
 bgcolor = green
 description = 1

 Cosmid	B0511	516-619
 Cosmid	B0511	3185-3294
 Cosmid	B0511	10946-11208
 Cosmid	B0511	13126-13511
 Cosmid	B0511	11394-11539
 EST	yk260e10.5	15569-15724
 EST	yk672a12.5	537-618,3187-3294
 EST	yk595e6.5	552-618
 EST	yk595e6.5	3187-3294
 EST	yk846e07.3	11015-11208
 EST	yk53c10
 	yk53c10.3	15000-15500,15700-15800
 	yk53c10.5	18892-19154
 EST	yk53c10.5	16032-16105
 SwissProt	PECANEX	13153-13656	'Swedish fish'
 FGENESH	'Predicted gene 1'	1-205,518-616,661-735,3187-3365,3436-3846	Pfam domain
 FGENESH	'Predicted gene 2'	5513-6497,7968-8136,8278-8383,8651-8839,9462-9515,10032-10705,10949-11340,11387-11524,11765-12067,12876-13577,13882-14121,14169-14535,15006-15209,15259-15462,15513-15753,15853-16219	Mysterious
 FGENESH	'Predicted gene 3'	16626-17396,17451-17597
 FGENESH	'Predicted gene 4'	18459-18722,18882-19176,19221-19513,19572-19835	Transmembrane protein
 # file ends

=head1 SEE ALSO

L<Bio::Graphics::Browser::Config>,
L<Bio::Graphics::Panel>,
L<Bio::Graphics::Glyph>,
L<Bio::Graphics::Feature>

=cut
