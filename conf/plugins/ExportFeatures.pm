# $Id: ExportFeatures.pm,v 1.7 2003-11-10 05:36:55 sheldon_mckay Exp $
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

=head1 NOTE 'Selected' vs. 'All' features

If 'Selected' is chosen in the popup menu, only the currently displayed
features (and any child features) will be dumped for editing.
A 'database_id' attribute is automatically added to each feature.
After editing, this attribute will be intercepted and removed by the
ImportFeatures plugin.  Features in the database with the corresponding IDs
will be deleted prior to reloading the selected features.


=head1 NOTE

The entire annotated sequence is dumped by this plugin, regardless 
of the segment's coordinate range.  This may be revised in a future version.y


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
use IO::Scalar;
use CGI qw/:standard *sup/;

use vars '$VERSION','@ISA';
$VERSION = '0.01';

@ISA = qw / Bio::Graphics::Browser::Plugin Bio::Graphics::Browser::GFFhelper/;

sub name { 
    'Edit Features (Artemis)' 
}

# don't use a verb in the plugin menu
sub verb {
    ' '
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
    { method => 'browser',
      mode   => 'all' }
}

sub reconfigure {
    my $self = shift;
    my $conf = $self->configuration;
    $conf->{method} = $self->config_param('method');
    $conf->{mode}   = $self->config_param('mode');
}

sub configure_form {
    my $self = shift;
    my $conf = $self->configuration;
    my $html = 'Dump ' .
       popup_menu(-name   => $self->config_name('mode'),
                  -values  => ['selected','all'],
                  -default => $conf->{mode},
                  -override => 1 ) . ' features' . br .
       h3('Dump features to:') .
       radio_group( -name    => $self->config_name('method'),
                     -values  => ['*Artemis', 'browser'],
		     -default => $conf->{method} ) .
        p( "<SUP>*</SUP>To edit, install a helper application for MIME type",
	                cite('application/artemis') );
    $html;
}

sub dump {
    my ($self, $segment) = @_;
    my $conf      = $self->configuration;
    my $mode      = $conf->{mode};
    my $db        = $self->database;
    my $ref       = $segment->ref;
    $segment      = $db->segment(Accession => $ref) || $db->segment($ref);
 
    # don't use an iterator here because we don't want aggregate features
    my $feats = join '', $self->selected_features;
    my @feats;

    if ( $mode eq 'selected' ) {
        for my $f ( $segment->features ) {
            my $type = $f->primary_tag;
	    if ($feats =~ /$type/) {
		push @feats, $f;
		$self->{seen}->{$f->id}++;
		my $name  = $f->name;
                # get all gene parts
		push @feats, grep { 
		    $_->class eq $f->class && 
                    $_->name =~ /$name/ && # may be alt-spliced
                    ! $self->{seen}->{$_->id}++;
		} $f->contained_features;
	    }
	}
    }
    else {
	@feats = $segment->features;
    }

#    for my $set ( @more_feature_sets ) {
#        if ( $set->can('get_seq_stream') ) {
#	    my $iterator = $set->get_seq_stream;
#	    while ( my $f = $iterator->next_seq ) {
#		push @feats, $f;
#	    }
#	}  
#    }

    my $ft = $self->write_ft( $segment, @feats );

    for ( split "\n", $ft ) {
	# strip away junk
	next if /^[^FIS\s]/;
	s/(ID\s+\S+).+/$1/;
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
    
    # write the data to a scalar instead of STDOUT
    tie *STDOUT, 'IO::Scalar', \$table;
    $out->write_seq($seq);
    untie *STDOUT;
    $table;
}

1;
