#$Id: ExportFeatures.pm,v 1.10 2004-02-27 19:31:17 sheldon_mckay Exp $

=head1 NAME

ExportFeatures -- Export Annotations to Apollo or Artemis

=head1 SYNOPSIS

This modules is not used directly

=head1 DESCRIPTION

This plugin dumps specially formatted annotations
to the Artemis and Apollo genome annotation browser/editors.
It works best for smaller segments derived from GenBank/EMBL-style
annotations and is happiest when SO-compliant gene containment
hierarchies are employed.  Although it is possible in theory to
dump whole chromosomes, etc, this plugin is best suited for
on-the-fly export of smaller chunks.

=head1 ARTEMIS

Artemis accepts features in a few formats but its native format 
is EMBL, which is what is produced by this plugin.  Artemis is fairly 
flexible with respect to what kind of features it will accept, 
although it always throws a non-fatal warning when 'illegal' feature 
types or qualifiers are encountered on loading.  These can be 
legitimized by editing the external Artemis configuration 
files (options or options.txt).  Artemis offers flexible feature 
creation and editing but is best suited for small and/or 
simple genomes.  Feature display options are highly configurable via
external configuration files.

=head1 APOLLO

Apollo supports import of features via GAME-XML.  It can cope 
with very large annotated sequences but has a more constrained 
suite of annotation-based editing capabilities.
As with Artemis, feature display options are highly configurable 
via external configuration files.  

The version of GAME-XML produced by this plugin is somewhat crippled 
in that it lacks the Computational_Analysis tree that is used in 
full-featured GAME-XML. This may be added if there is a demand
for it. Gene containment hierarchies must be unflattened into 
rigidly formatted annotation trees to make GAME-XML.  This is 
facilitated by using a SO-compliant transcript aggregator and
mildly controlled attribute vocabulary in the Data loading
plugin 'ImportFeatures.pm', which is designed to work with this
module to aid round-tripping.  This works for simple feature
editing in Apollo but more robust interoperability will require 
further testing and feedback from the user community. 

=head1 THE 'id_holder' FEATURE

The id_holder is a synthetic feature designed to facilitate
the return trip to gbrowse. It holds the database IDs of all 
dumped features.  It also contains the coordinate offset for 
subseqments (always dumped with relative coordinates).  The 
id_holder also contains a qualifier specifying whether dis-
aggregated features were exported.  Deleting the id_holder
feature is not recommended.

=head1 RELATIVE COORDINATES

The sequence coordinates are always 1-based, relative to the 
segment start.  This is mandatory to avoid killing Artemis with out 
of range features.  Dumping to Apollo with absolute coordinates may 
be supported later if anyone asks for it.  The segment's offset 
it saved in the id_holder, so that features are re-mapped to 
the reference sequence on the return trip.

=head1 DATABASE IDS

The database IDs of all features dumped into the annotated 
sequence file are saved in the id_holder.  This will make 
it possible to selectively delete features by ID on the 
round-trip.  This way, deletion of selectively dumped features 
in an external editor will be reflected when the database is 
updated on the return trip.  If the IDS go stale or are not 
supported, then colliding features (same type, strand and 
coordinates as the incoming features). There is also a 
user-specified option to delete all in-range features for 
the segment.  -- Caveat emptor --

=head1 GENES ARE TREATED DIFFERENTLY

There is a bias towards gene-based annotations, which are what
the genome annotation editors are focused on, especially Apollo.
Nevertheless, any features can be dumped as a generic annotations.  
Gene-based features are collected via a SO-compliant aggregator to 
facilitate unflattenening into segmented transcripts and CDSs.  
Other features can be selected for dumping as desired but gene 
components are mandatory.  The aggregation can be disabled 
(EMBL/Artemis only).  The result is a GFF_like EMBL feature 
table that has each gene component as a stand-alone feature. The
feature importer is made aware of disaggregated features via the 
id_holder


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
use Bio::SeqFeature::Generic;
use Bio::Location::Split;
use Bio::Seq::RichSeq;
use CGI qw/:standard *sup/;
use CGI::Carp qw/croak fatalsToBrowser/;
use Data::Dumper;
use vars '$VERSION','@ISA';

$VERSION = '0.01';

@ISA = qw / Bio::Graphics::Browser::Plugin Bio::Graphics::Browser::GFFhelper/;

sub name { 
    'Export Annotations' 
}

# don't use a verb in the plugin menu
sub verb {
    ' '
}

sub description {
  p("This plugin dumps out the features in the current " .
    "segment as GAME-XML suitable for export to Apollo or as an EMBL " .
    "file suitable for Artemis"),
  p("This plugin was written by Sheldon McKay.");
}

sub mime_type {
    my $self = shift;
    my $conf = $self->configuration;

    if ( !param('configured') ) {
        return 'text/html';
    }

    if ( $conf->{method} eq 'browser' || param('demo_script') ) {
        return 'text/plain';
    }
    
    if ($conf->{format} eq 'EMBL' ) {
        return 'application/artemis';
    }
    
    if ($conf->{format} eq 'GAME' ){
        return 'application/apollo';
    }
}


sub config_defaults {
    { 
      method => 'browser',
      format => 'EMBL' 
    }
}

sub reconfigure {
    my $self = shift;
    my $conf = $self->configuration;
    my $format = $self->config_param('format');
    ($conf->{format}) = $format =~ /(GAME|EMBL)/;
    
    $conf->{method} = $self->config_param('method');
    $conf->{types}  = [ $self->config_param('type') ];
    $conf->{expand} = $self->config_param('expand');
    
    # Artemis-specific
    if ( $conf->{format} eq 'EMBL' ) {
	$conf->{disaggregate} = param('disaggregate') ? 1 : 0;
    }
}

sub configure_form {
    my $self = shift;
    my $conf = $self->configuration;

    # use a really generic transcript aggregator
    $self->generic_aggregator;

    # and just deal with selected features
    my ($segment) = @{$self->segments};
    my @types = $self->selected_features;
    my $iterator = $segment->get_seq_stream;    

    # find out what kind of features we have
    my (%seen, @gene_stuff, @other) = ();
    while ( my $f = $iterator->next_seq ) {
        my $method = $f->method;

	# check for transcripts
	if ( my @sf = $f->sub_SeqFeature ) {
	    $method .= " (aggregate feature composed of UTR, CDS, exon, etc.)";
	    push @gene_stuff, $method if ++$seen{$method} == 1;
	    next;
	}

	next if ++$seen{$method} > 1;
        
	if ( $method =~ /RNA|gene|transcript/ ) {
	    push @gene_stuff, $method;
	}
	else {
	    next if $f->start < $segment->start;
	    next if $f->end > $segment->end;
	    push @other, $method;
	}
    }

    # list the gene features first
    my $msg  = "Protein-coding genes are assembled into nested features " .
               "that contain processed transcript components such as " .
	       "UTRs, exons and CDSs";

    my $html = _buttons($segment) . br .
	       table(
		     Tr( { -class => 'searchtitle' },
			 td( b("The following gene-related features will " .
                               "be exported from $segment"),
			     _js_help($msg))
			 )
		     ) . ul( join '', map { li($_) } @gene_stuff );
    
    $html .= hidden ( -name    => $self->config_name('type'),
		      -default => [grep { s/ \(.+\)// || $_ } @gene_stuff] );
   
    # avoid including partial genes
    $msg    = "To avoid dumping partial genes that span the ends, the sequence " .
	      "region will be expanded to contain all gene components.\\n\\n" .
	      "Partial genes will not be included unless this box is checked";
    my $lbl = "Resize the selected region to completely include overlapping " .
	      "genes ";
    $html .= p(checkbox( -name    => $self->config_name('expand'),
			 -checked => 1,
			 -label   => $lbl ) . ' ' . _js_help($msg));

    # give the option to unflatten aggregates
    $msg = "Break apart mRNAs into component parts (UTRs, exons, CDS, etc)\\n\\n" .
	   "NOTE: This option is only available for EMBL format ";
    $lbl = "Disaggregate mRNAs";
    $html .= p(checkbox( -name    => 'disaggregate',
			 -checked => 0,
			 -label   => $lbl ) . ' ' . _js_help($msg));


    # optional other features
    if ( @other ) {
        my $msg = "Generic features are treated differently because they are not " .
	          "in nested containment hierarchies like genes and " .
                  "gene-containing features";
        my $width = 200 + int(@other/10 * 200);
	my $feat_list = checkbox_group ( -name    => $self->config_name('type'),
					 -values  => \@other,
					 -rows    => 5);
	$feat_list =~ s/<table/<table style="width:${width}px"/m;

	$html .= table(
		       Tr( { -class => 'searchtitle' },
			   td( b("Select non-gene features to include "), _js_help($msg)),
			   )
		       ) . $feat_list;
    }

    # dump to browser or helper-app?
    $msg = "For external editors, install a helper application for MIME type " .
	   "application/apollo or application/artemis";
    $html .= p('Destination: ' .
	       radio_group( -name    => $self->config_name('method'),
			    -values  => [ qw/editor browser/ ],
			    -default => $conf->{method} ) . ' ' . _js_help($msg));

    my $default_format = $conf->{format} eq 'GAME' ? 'Apollo (GAME)' : 'Artemis (EMBL)'; 

    $html .= p('Format: ' . 
	       radio_group( -name    => $self->config_name('format'),
			    -values  => [ 'Apollo (GAME)', 'Artemis (EMBL)' ],
			    -default => $default_format ) );

    # give a sample client-side perl wrapper
    my $url = $self->demo_script_url;
    $html .= p("To save your edited features back into gbrowse automatically, " .
               "you will need to use a " . a( {-href => $url, -target => '_new'},
	       "helper script") . ".<br>Otherwise, upload your annotations via the " .
               "'Import Annotations' plugin");

    # advise if the sequence is missing
    unless ( $segment->seq ) {
	print h2( font( { -color => 'red' },
		  'Note: there is no DNA sequence for $segment in the database. ' .
			'It will be replaced with \'N\'s' ) );
    }

    # force config page if dump is hit from browser
    $html .= hidden( -name => 'configured', -value => 1 );
}

sub _js_help {
    my $msg = shift;
    a( { -href    => 'javascript:void(0)',
	 -title   => 'help',
	 -onclick => "alert('$msg')" }, "[?]" );
}

sub dump {
    my ($self, $segment) = @_;

    # is this a request for the demo script?
    if ( param('demo_script') ) {
	print while (<DATA>);
	exit;
    }

    # can't hit 'Go' without configuring first
    $self->load_config_page unless param('configured');

    my $conf  = $self->configuration;
    my $mode  = $conf->{mode};
    my $db    = $self->database;
    my $exp   = $conf->{expand};

    my $whole_segment = $db->segment( $segment->ref ); 
    my $whole = 1 if $segment->start == 1 
                  && abs( $segment->stop - $whole_segment->stop ) < 10;

    # expand the segment to completely contain genes
    # that span the ends
    if ( $exp && !$whole ) {
	my @feats = grep { 
	    $_->method =~ /gene|transcript|RNA/ 
        } $segment->features;
        my ($low, $high) = ($segment->start, $segment->stop);
        for ( @feats ) {
	    my $start = $_->start;
	    my $stop  = $_->end;
	    ($start, $stop) = ($stop, $start) if $start > $stop;
	    $low = $start if $start < $low;
	    $high = $stop if $stop > $high; 
	}
        if ( $low < $segment->start || $high > $segment->end ) {
	    $segment = $db->segment( -name  => $segment->ref,
				     -class => $segment->class,
				     -start => $low, 
				     -stop  => $high );
	    $segment || die "Segment re-size failure" . $db->error;
	}
    }

    # define the offset for sub-segments
    $self->{offset} = $segment->start - 1;

    # use a generic transcript aggregator
    $self->generic_aggregator;
    $self->{genes} = [];
    my ($transcripts, $gff_feats) = $self->get_feats($segment);
    my @transcripts = @$transcripts;
    my @GFF_feats   = @$gff_feats;

    my (@BSG_feats, %seen )  = ();

    for my $f ( @transcripts ) {

	my $transcript = $self->convert($f);
        
	#  find the parent gene...
	my $gene;

	# first, check if the transcript is an alt. splice product
        # for a previously seen gene
	if ( defined $self->{genes}->[0] ) { 
	    ($gene) = grep { 
		_name($_, 'gene') eq $f->name ||
		_name($_, 'standard_name') eq $f->name ||
		( $_->strand == $transcript->strand && 
                 ( $_->start == $transcript->start ||
                  $_->end   == $transcript->end ))   
	    } @{$self->{genes}};
	}                       
        
        # then, look for GFF genes
	if ( !$gene ) { 
	    ($gene) =  grep {
		$_->name eq $f->name ||   
		_name($_, 'standard_name') eq $f->name ||
                _name($_, 'gene') eq $f->name ||    
		( $_->start <= $f->start && 
		  $_->end >= $f->end && 
		  $_->strand eq $f->strand ) 
	    } $segment->features( -types => ['gene'] );
	}

	# convert GFF gene to BSG gene
	if ( $gene && $gene->can('id') ) {
	    $gene = $self->convert($gene);
	}

        # last resort; create a new gene feature
	elsif ( !$gene ) { 
	    $gene = Bio::SeqFeature::Generic->new ( -primary => 'gene' );
	    $gene->location($transcript->location);
	    $gene->add_tag_value( gene => $f->name );
	}

        # convert nested subfeats
	my @sf = map  { $self->convert($_) } $f->get_SeqFeatures;
	
	my @CDS  = _grab('CDS', @sf);
	my @exon = _grab('exon', @sf);
        my @other = grep { $_->primary_tag ne 'CDS' } @sf;

        # clone the CDS chunks as exons if req'd
	if ( @CDS && !@exon ) {
	    for my $cds ( @CDS ) {
		my $exon = _clone($cds);
		$exon->primary_tag('exon');
		push @exon, $exon;
	    }
	}

        # flatten the CDS
	my $meta_cds;
	if ( @CDS ) {
	    $meta_cds = $CDS[0];
            my $meta_loc = Bio::Location::Split->new;
	    
	    for ( @CDS ) {
		$meta_loc->add_sub_Location( $_->location );
	    }

	    $meta_cds->location( $meta_loc );
	}
	
        # strand-specific sort of transcript components
	@sf = (@other, @exon);
        if ( $transcript->strand >= 0 ) {
            @sf = sort { $a->start <=> $b->start } @sf;
        }
        else {
            @sf = sort { $b->start <=> $a->start } @sf;
        }

        # save the CDS, just in case.
        my $gname = _name($gene, 'gene') 
                 || _name($gene, 'standard_name')
                 || _name($gene, 'locus_tag');

        if ( $meta_cds ) {
	    unshift @sf, $meta_cds;
	    $self->{curr_CDS}->{$gname} = $meta_cds;
	}

        # construct nested transcript
	for my $sf ( @sf ) {
	    $transcript->add_SeqFeature( $sf );
	    $transcript->remove_tag('gene') if $transcript->has_tag('gene');
	}

        # construct nested gene
	$gene->add_SeqFeature( $transcript, 'EXPAND' );

        push @BSG_feats, $gene unless grep { $_ eq $gene } @{$self->{genes}};
	push @{$self->{genes}}, $gene;
	
    }

    # survey the genes for CDS-less transcripts (may happen
    # with alt. spliced UTRs)
    for my $g ( @BSG_feats ) {
	my $gname = _name($g, 'gene')
                 || _name($g, 'standard_name')
                 || _name($g, 'locus_tag');

	my @rnas = $g->get_SeqFeatures;
	
	for my $rna ( @rnas ) {
	    my $tname = _name( $rna, 'mRNA' ) || _name( $rna, 'standard_name' );
            my ($cds) = grep { $_->primary_tag eq 'CDS' } $rna->get_SeqFeatures;
            
	    if ( !$cds ) {
		# clone the stored CDS and give it a new parent ID
		$cds = $self->{curr_CDS}->{$gname};
		next unless $cds;
		my $new_cds = _clone($cds);
		$new_cds->remove_tag('mRNA');
		$new_cds->add_tag_value( mRNA => $tname );
		$rna->add_SeqFeature( $new_cds );
	    }

            # to help GAME-XML round-tripping, give the mRNA
            # some CDS tags to link it to the CDS
            for ( qw/product protein_id/ ) {
                next unless $cds && $cds->has_tag($_);
                $rna->add_tag_value( $_, $cds->get_tag_values($_) )
                    unless $rna->has_tag($_);
	    }
	}
    }
    
    # Unflatten mRNAs for Artemis
    if ( $conf->{format} eq 'EMBL' ) {
	my @unflattened;
	for my $g ( @BSG_feats ) {
	    push @unflattened, $g;
            my @rnas = $g->get_SeqFeatures;
            for my $rna ( @rnas ) {
		my ($cds) = grep { $_->primary_tag eq 'CDS' } $rna->get_SeqFeatures;
		my $meta_loc = Bio::Location::Split->new;
		my %seen;    
		for (  grep { $_->primary_tag ne 'CDS' } $rna->get_SeqFeatures ) {
		    next if ++$seen{$_->start . ' ' . $_->end} > 1;
		    $meta_loc->add_sub_Location( $_->location );
		}
		    
		$rna->location( $meta_loc ) if $meta_loc;
                
                # who does the mRNA belong to?
		unless ( $rna->has_tag('gene') ) {
                    my ($gname) = eval {$g->get_tag_values('gene')};
		    $rna->add_tag_value( 'gene', $gname ) if $gname;
		}

                # No UTRs? --No point in having identical mRNA and CDS
		push @unflattened, $rna unless $cds && $cds->start == $rna->start
		                                    && $cds->end   == $rna->end;
		push @unflattened, $cds if $cds;
	    }
	}
	@BSG_feats = @unflattened;
    }


    # other feats (or disaggregated sets)?
    # plain old 1:1 feature conversion
    for my $f ( @GFF_feats ) {
	my $gf = $self->convert($f);
	push @BSG_feats, $gf;
    }

    my $id = $segment->ref;
    my $id_holder = $self->id_holder($segment);

    # relative coords for partial segments
    unless ( $whole ) {
	$self->remap($id_holder);
	$id_holder->add_tag_value( segment_offset => $self->{offset} );
    }

    # warn the importer if features are not aggregated
    if ( $conf->{disaggregate} ) {
	$id_holder->add_tag_value( unflattened => 1 );
    }

    my $seq  = Bio::Seq::RichSeq->new( -id  => $id );
    $seq->seq( $segment->seq ) if $segment->seq;
    $seq->id($id);
    $seq->accession($id);
    $seq->description($id);
    $seq->add_SeqFeature(@BSG_feats, $id_holder);

    # we must have a sequence
    unless ( $seq->seq ) {
	$seq->seq( ('N' x $segment->length) );
    }

    my $format = lc $conf->{format};
    #$format = 'asciitree';
    my $out = eval { Bio::SeqIO->new( -format => $format ) };
    $out || croak("Sequence conversion error: " . join '', @!);
    my $out_ok = eval{ $out->write_seq($seq) };
    $out_ok || croak("Sequence writing error: " . join '', @!);
}

sub get_feats {
    my ($self, $segment) = @_;
    my $conf   = $self->configuration;
    my $disagg = $conf->{disaggregate};
    my $types  = \@{$conf->{types}};
    my $iterator = $segment->get_seq_stream( -types => $types );
    
    my (@GFF_feats, @transcripts);

    while ( my $f = $iterator->next_seq ) {
        # only use contained features
        unless ( $conf->{expand} ) {
            next if $f->start < $segment->start;
            next if $f->end > $segment->end;
        }

	if ( $disagg ) {
	    if ( my @sf = $f->sub_SeqFeature ) {
		push @GFF_feats, ($f, @sf);
	    }
	    else {
		push @GFF_feats, $f;
	    }
	}
	else {
	    if ( $f->sub_SeqFeature && $f->method eq 'mRNA' ) {
		push @transcripts, $f;
	    }
	    elsif ( $f->method !~ /gene|mRNA/ ) {
		push @GFF_feats, $f;
	    }
	}
    }

    return \@transcripts, \@GFF_feats;
}


sub _grab {
    my $thing = shift;
    sort { $a->start <=> $b->start }
    grep { $_->primary_tag eq $thing } @_;    
}

sub _name {
    my ($f, $t) = @_;
    return 0 unless $f->has_tag($t);
    ($f->get_tag_values($t))[0];
}

# GFF->Generic feature
sub convert {
    my ($self, $f) = @_;
    $self->{database_ids} ||= [];
    push @{$self->{database_ids}}, $f->id;
    $f = $self->gff2Generic($f);
    $self->remap($f);
    _strandfix($f);
    _tagfix($f);
    $f;
}

sub _strandfix {
    my $f = shift;
    my $start = $f->start;
    my $end = $f->end;
    if ($start > $end) {
        $f->start($end);
        $f->end($start);
        $f->strand(-1);
    }
}

# get rid of duplicate qualifiers
sub _tagfix {
    my $f = shift;
    my %seen;
    for my $t ( $f->all_tags ) {
        my @v = $f->get_tag_values($t);
        $f->remove_tag($t);
        for my $v( @v ) {
	    $v =~ s/$t://;
            next if ++$seen{"$t:$v"} > 1;
            next if $t eq 'codon_start'; # messes with segment offsets
            $f->add_tag_value( $t => $v );
        }
    }
}

sub generic_aggregator {
    my $self = shift;
    my $db   = $self->database;
    my $aggregator;

    # similar to processed_transcript.pm, but it also uses exons
    my $transcript_parts = join ',', ( qw/ UTR 5_UTR 3_UTR 5'UTR 3'UTR 5'-UTR 3'-UTR 
				       exon CDS TSS transcription_start_site TSS
				       polyA_site five_prime_untranslated_region
				       three_prime_untranslated_region
				       untranslated_region / );
    $aggregator = "mRNA{${transcript_parts}/mRNA}";
    
    
    $db->aggregators( $aggregator  );
    $aggregator;
} 

# required for round-trip
sub id_holder {
    my $self    = shift;
    my $segment = shift;
    my @ids = @{$self->{database_ids}};
    my $holder;

    if ( @ids ) {
        $holder = Bio::SeqFeature::Generic->new ( -primary => 'misc_feature',
						  -start   => $segment->start,
						  -end     => $segment->start + 1 );
        $holder->add_tag_value( note => "GFF database info; do not delete!" );
        my $ids = join ',', @ids; 
	$holder->add_tag_value( database_ids => $ids );
	$self->{id_holder} = $holder;
    }

    $holder;
}

# recursively remap features to relative coordinates
sub remap {
    my ($self, $f) = @_;
    for ( $f, $f->get_SeqFeatures ) {
	$_->start($_->start - $self->{offset});
	$_->end($_->end - $self->{offset});
    }
}

# go to configure page if this is a caught misdirection
sub load_config_page {
    my ($self, $gff) = @_;
    my $url = self_url();
    $url =~ s/plugin_action=Go/plugin_action=Configure.../;
    print h2("One moment, loading configuration form...");
    print body( { -onLoad => "window.location='$url'" } );
    exit;
}


sub demo_script_url {
    my $self = shift;
    my $url = self_url();
    $url =~ s/\?.+//;
    $url .= '?plugin=ExportFeatures;plugin_action=Go;demo_script=yes';
    $url;
}

# shallow clone the CDS feature but give it ownership
# of the copied tags
sub _clone {
    my $obj = shift;
    my %new =  %{$obj};
    my %tags = %{$obj->{_gsf_tag_hash}};
    $new{_gsf_tag_hash} = \%tags;
    return bless \%new, ref($obj);
}

sub _buttons {
    my $s = shift;
    my @loc;


    my $url = self_url();
    $url =~ s/\?.+$/?/g;
    $url .= 'name=' . $s->ref . ':' . $s->start . '..' . $s->stop;
    my $plg = ';plugin=ImportFeatures;plugin_action=Configure...';
    
    button( -onclick => qq(window.location="$url"),
	    -name    => 'Update ' . $s->ref ) . ' ' .
    button( -onclick => qq(window.location="${url}$plg"),
	    -name    => 'Upload Annotations' ) . br; 
}


1;

__DATA__
#!/usr/bin/perl -w

# file edit.pl -- a client side wrapper for Apollo or Artemis

use strict;
use LWP::UserAgent;
use HTTP::Request::Common;

######################################################
#               USER DEFINED PARAMETERS              #
#  -- edit your system specific info here --         #
######################################################
# where is your gbrowse web site installed (optional)?
my $URL = 'http://my_site.com/cgi-bin/gbrowse/my_database';

# where do you want to save files?
my $SAVEDIR = 'c:\annotations';

# where is your editor?
# use single quotes or escape backslashes in win32 scripts
# The implementation of Artemis/Apollo will vary by OS.  
# This is a win32 example
#my $PROGRAM  = 'C:\Apollo\Apollo.exe';
my $PROGRAM = 'C:\artemis\artemis_compiled_latest.jar';

# save file locally or update the web site?
#my $METHOD = 'local';
my $METHOD = 'remote';

######################################################


# filename must be passed as a command-line argument 
my $file = shift or die "Usage: perl edit.pl filename\n";

print "\nProcessing annotation file $file...\n\n";

chdir $SAVEDIR or die $!;
system $PROGRAM =~ /artemis/ ? "java -jar $PROGRAM $file" : "$PROGRAM $file";

open FILE, "<$file";
$/ = undef;
my $text = <FILE>;

if ( $METHOD eq 'local' ) {
    save_file($text);
}
elsif ( $METHOD eq 'remote' ) {
    web_update($text);
}
else {
    print "No save option specified, your annotation file is saved as $file\n\n";
}

sub save_file {
    my $text = shift;
    my $not_good = shift;
    print "Uh Oh....\n" if $not_good;
    my $ext = $PROGRAM =~ /artemis/ ? 'embl' : 'xml';
    open OUTFILE, ">seqfile\.$ext" or die $!;
    print OUTFILE $text;
    close OUTFILE;
    print "Saved results to $SAVEDIR\\seqfile.$ext\n\n";
    sleep 10 unless $not_good;
}


sub web_update {
    my $text = shift;

    print "\nPreparing to update the website...\n";

    my $format = $PROGRAM =~ /artemis/ ? 'Artemis (EMBL)' : 'Apollo (GAME)';
    my @params = (   'ImportFeatures.format'     => $format, 
                     'ImportFeatures.debug'      => 'debug',
                     'ImportFeatures.erase'      => 'selected',
                     'ImportFeatures.configured' => 'true',
                     'plugin'                    => 'ImportFeatures',
                     'plugin_action'             => 'Go',
		     'text'                      => $text );

    my $errmsg = "Automated web update failed.\n" .
                 "It may still be possible to upload your annotations\n" .
                 "via the 'Import Annotations' plugin\n\n";

    print "\nContacting $URL...\n";
    my $ua       = LWP::UserAgent->new;
    my $response = $ua->request( POST $URL, \@params );

    my $output = $response->content
      # Oh No! Something's wrong!
      or save_file($text,1)
      and _die("Error: No response\n" . $response->status_line);

    # look for a successful update
    unless ( $output =~ /Success/m ) {
        save_file($text,1);
        _die($errmsg, $output);
    }
    else {
	print "\nUpdate successful\n";
    }
    print "\nWeb-site output saved in  $SAVEDIR as output.html\n";
    open OUT, ">output.html" or die $!;
    print OUT $output;
    close OUT;
    sleep 10;
}

sub _die {
    print $_[0], "\n";
    my $output = $_[1];

    if ($output) {
	print "\nWeb-site output saved in $SAVEDIR as output.html\n";
	open OUT, ">output.html";
	print OUT $output;
	close OUT;
       
    }

    sleep 20;
    exit;
}

