# $Id: ExportFeatures.pm,v 1.3 2003-10-16 12:48:19 sheldon_mckay Exp $
=head1 NAME

Bio::Graphics::Browser::Plugin::ExportFeatures -- a plugin to export 
annotated sequence to Artemis

=head1 SYNOPSIS

This modules is not used directly

=head1 DESCRIPTION

This plugin dumps specially formatted EMBL annotations 
(an unflattened EMBL feature table) to a file or directly 
to the editor if the browser is configures to launch 
Artemis as a helper application for mime-type 'application/artemis'

Artemis will no longer support direct editing of GFF2 in its
next production release but EMBL feature tables can be edited directly.
After editing, the file can be reloaded into the database using the 
ImportFeatures plugin.

This plugin is specific to EMBL format but should be extensible
to other formats/editors if required

=head1 NOTE

The entire annotated sequence is dumped by this plugin, regardless 
of the segment's coordinate range.  


=head1 FEEDBACK

See the GMOD website for information on bug submission http://www.gmod.org.

=head1 AUTHOR - Sheldon McKay

Email smckay@bcgsc.bc.ca

=head1 CONTRIBUTORS

=cut

package Bio::Graphics::Browser::Plugin::ExportFeatures;
use strict;
use Bio::Graphics::Browser::Plugin;
use Bio::Graphics::Browser::GFFhelper;
use Bio::Seq::RichSeq;
use IO::String;
use CGI ':standard';

use vars '$VERSION','@ISA';
$VERSION = '0.01';

@ISA = qw / Bio::Graphics::Browser::Plugin Bio::Graphics::Browser::GFFhelper/;

sub name { 
    'Artemis Feature Table' 
}

sub verb {
    'Export'
}

sub description {
  p("The Artemis dumper plugin dumps out the features in the current segment as an EMBL",
    " feature table suitable for editing in Artemis"),
  p("This plugin was written by Sheldon McKay.");
}

sub mime_type {
    my $conf = shift->configuration;
    if ( $conf->{method} eq 'browser' ) {
        return 'text/plain';
    }
    else {
        return 'application/artemis';
    }
}

sub config_defaults {
    { method => 'browser' }
}

sub reconfigure {
    my $self = shift;
    my $conf = $self->configuration;
    $conf->{'method'} = $self->config_param('method');
}

sub configure_form {
    my $self = shift;
    my $conf = $self->configuration;
    my $html = h3('Dump features to:') .
	radio_group( -name    => $self->config_name('method'),
                     -values  => ['*Artemis', 'browser'],
		     -default => $conf->{method} ) .
        p( super('*'),"To edit, install a helper application for MIME type",
	                cite('application/artemis') );

}

sub dump {
    my ($self, $segment, @more_feature_sets) = @_;
    my $conf      = $self->configuration;
    my $db        = $self->database;
    my $ref       = $segment->ref;
    $segment      = $db->segment($ref);
 
    my @feats = $segment->features;

    for my $set ( @more_feature_sets ) {
        if ( $set->can('get_seq_stream') ) {
	    my $iterator = $set->get_seq_stream;
	    while ( my $f = $iterator->next_seq ) {
		push @feats, $f;
	    }
	}  
    }

    my $ft = $self->write_ft( $segment, @feats );

    for ( split "\n", $ft ) {
	# strip away junk
	next if /^[^FIS\s]/;
	s/(ID\s+\S+).+/$1/;
	# Uppercase key confuses Artemis
	s/Note/note/;
	print $_, "\n";
    }
}

sub write_ft {
    my $self    = shift;
    my $segment = shift;
    my @feats   = @_;
    my $table   = '';

    my $seq  = Bio::Seq::RichSeq->new( -id  => $segment->refseq,
				       -seq => $segment->seq );

    for ( @feats ) {
	next if $_->primary_tag =~ /component/i;
	$seq->add_SeqFeature( $self->gff2Generic($_) );
    }
    
    my $out = Bio::SeqIO->new( -format => 'embl' );
    my $io = IO::String->new($table);
    tie *STDOUT, $io;
    $out->write_seq($seq);
    untie *STDOUT;
    $table;
}

1;
