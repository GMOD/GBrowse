# $Id: ImportFeatures.pm,v 1.3 2003-10-16 07:29:14 sheldon_mckay Exp $

=head1 NAME

Bio::Graphics::Browser::Plugin::ImportFeatures -- a plugin to 
import features into the Generic Genome Browser

=head1 SYNOPSIS

This modules is not used directly

=head1 DESCRIPTION

ImportFeatures.pm processes external features and loads them 
into the GFF database.  It will accept a flat files in GenBank, 
EMBL or GFF2 format or download and accession from NCBI/EBI.  

=head2 Loading new sequences

This plugin can be used to download accessions from GenBank 
or EMBL and load them into the GFF database.  Segmented features 
in the Genbank or EMBL file or accession (example mRNA or CDS) 
will be unflattened and the resulting containment hierarchies 
can be used to display aggregate features.  For example, an 
aggregate transcript feature can be assembled using mRNA and 
CDS features.  See the gbrowse tutorial for more information 
on aggregators.

=head2 Editing Features in an External Editor

This plugin can be used to load externally edited features, 
as long as the editor is capable of exporting GenBank, EMBL 
or GFF2. The currently available options are manually editing 
GFF or using Artemis.  Support for Apollo awaits completion 
of a suitable data adapter.  Note that in-place creation, 
deletion and editing of features can also be done from gbrowse
(using the BasicEditor plugin).

=head2  Using Artemis as an External Editor

 1) use the GFFDumper plugin to dump artemis flavor GFF from 
    gbrowse to a file (or directly to Artemis as a 
    helper application configured in the browser)

 2) edit your features 

 3) use "Save as" to create a new GFF file (see below)

 4) load the file via this plugin.  

Attempting to save the record directly or convert between 
formats in Artemis (version 5) may yield unexpected results.  
For best results, use GFF.  Make sure to enable direct 
editing in the Artemis configuration file 'options.txt'.  
See the Artemis documentation for more information on 
setup options.

The production release of Artemis (version 5) supports 
editing/saving of GFF2 features.  Post-v5 development 
snapshots no longer support editing of GFF features, 
so stick to version 5. 

You can also use Artemis to help import features from 
other sources.  Artemis saves features as a tab files, 
which are feature tables with the header information 
stripped away.  All three flavors of Artemis tab files 
can be imported via this plugin if the name of the 
sequence is provided with the file.

=head2  Loading Sequence

If the DNA is included in a new file/accession, it
will be loaded into the database along with the features.
However, if this the sequence for the segment is not
already in the database, it will not be reloaded.


=head2  Loading Features

Overwriting features is not supported with all SQL 
databases, so features within the entire sequence 
range from the input GFF will be deleted from the database 
prior to loading the imported GFF.  This means that any 
feature deleted in the external editor or otherwise 
removed from the GFF will vanish from the database on 
the next load.  Artemis was designed to annotate small 
genomes, so it expects to be given the entire sequence, 
rather than the slice contained in the Bio::DB::GFF::RelSegment 
object.  Artemis uses the sequence itself to define 
the coordinates, so the entire chromosome (or other 
reference sequence) is dumped by GFFDumper.


=head2  Basic Feature Editing

For simple in-place feature editing, deletion, or addition, 
consider using the the BasicEditor plugin from within gbrowse


=head2 Rollbacks

In the highly improbable event that a user regrets editing 
or deleting features, this plugin can be used to roll back 
to an earlier state.  If the rollback functionality is enabled, 
the state of the segment will be saved to a file before 
each database update.  The last five pre-update states will 
be saved in a round-robin rotation and can be accessed via 
the configuration form.

To enable rollback capability, define the $ROLLBACK scalar with
a string containing the path to location where the web user 
('apache', 'nobody', etc) has read/write access.

=head1 FEEDBACK

See the GMOD website for information on bug submission http://www.gmod.org.

=head1 AUTHOR - Sheldon McKay

Email smckay@bcgsc.bc.ca

=head1 CONTRIBUTORS

Mark Wilkinson (markw@illuminae.com)

=head1 SEE ALSO

Bio::Graphics::Browser::Plugin::GFFDumper 

Bio::Graphics::Browser::Plugin::BasicEditor

Artemis (http://www.sanger.ac.uk/Software/Artemis)

=cut

package Bio::Graphics::Browser::Plugin::ImportFeatures;

use strict;
use Bio::DB::GenBank;
use Bio::DB::EMBL;
use Bio::DB::GFF::Feature;
use Bio::Tools::GFF;
use CGI ':standard';
use CGI::Carp 'fatalsToBrowser';
use IO::String;
use Bio::SeqIO;
use Bio::Graphics::Browser::Plugin;
use Bio::Graphics::Browser::GFFhelper;

use vars qw /@ISA $ROLLBACK/;

@ISA = qw/Bio::Graphics::Browser::Plugin Bio::Graphics::Browser::GFFhelper/;


####################################################################
# Edit this list IP addresses of trusted hosts for database access
####################################################################
my $ips = <<END;
END
####################################################################


###################################################################
# Edit this line to change the rollback path.  Comment it out to
# switch off the rollback functionality
$ROLLBACK = '/tmp/';
###################################################################


$| = 1;

sub name { 
    'external features'
}

sub description {
  p("This plugin imports features and sequences to the GFF database."  .
    "GenBank/EMBL/GFF files or direct downloads from NCBI/EBI are supported."),
  p("This plugin was written by Sheldon McKay");
}

sub type {     
    'dumper'
}

sub verb {
    'Import'
}

sub mime_type {
    'text/html'
}

sub config_defaults {
    { 
	format => 'GFF',
        text   => undef,
        file   => undef,
        acc    => undef,
        debug  => undef,
        reload => 1,
        rb_id  => undef,
        seq_id => undef
    }
}

sub reconfigure {
    my $self = shift;
    my $conf = $self->configuration;

    $conf->{file}   = upload( 'ImportFeatures.file' );
    $conf->{format} = $self->config_param('format');
    $conf->{seqid}  = $self->config_param('seqid');
    $conf->{acc}    = $self->config_param('acc');
    $conf->{debug}  = $self->config_param('debug');
    $conf->{reload} = $self->config_param('reload');
    $conf->{rb_id}  = $self->config_param('rb_id');
    $conf;
}

sub configure_form {
    my $self  = shift;
    my $conf  = $self->configuration;
    $self->{rb_loc} = $ROLLBACK;
    
    # is this a trusted host?
    if ( forbid() ) {
        return h1("Sorry, access to the database is not allowed from your location");
    }
    
    my $f = "<font color=black><b>";
    my $html = 
	"<table>\n" .
	Tr( { -class => 'searchtitle' }, td( $f, 'Upload a GenBank/EMBL/GFF Flatfile' ) ) . 
        "<tr><td class='searchbody'>" .
        h3('Format: ',
	   radio_group( -name    => $self->config_name('format'),
			-values  => [ qw/GFF GENBANK EMBL/ ],
			-default => $conf->{format} )) . "\n" .
	h3('Sequence ID: ', 
            textfield( -name  => $self->config_name('seqid'),
		       -size  => 10,
		       -value => $conf->{seqid}), ' ',
	   a( {-onclick => 'alert("Required for headerless feature tables")'}, '[?]')) . "\n" .
	h3('Name of file to upload: ',
            filefield( -name  =>  $self->config_name('file'),
		       -size  => 40,
		       -value => $conf->{file} )) . "\n" .
        "</td></tr></table>" . "\n" . h3(' - OR - ') . 
        "<table>\n" .
	Tr( { -class => 'searchtitle' }, td( $f, 'Direct Download from NCBI/EBI' ) ) .
        "<tr><td class='searchbody'>\n" .
        h3( 'Accession ',
	    textfield( -name    =>  $self->config_name('acc'),
		       -size    => '15'), ' ',
	    a( {-onclick => 'alert("Use a GenBank/EMBL accession number (not GI)\\n' .
                            'Note: this will override file uploading")'}, '[?]')) .
        "</td></tr></table>\n";

    # add a rollback table if required
    my $msg = "Selecting rollback will override loading of files or accessions";
    $html .= "\n" . h3(' - OR - ') . "\n" . $self->rollback_form($msg) if $ROLLBACK;

    $html .= h4(checkbox ( -name    => $self->config_name('debug'),
			   -value   => 'debug',
			   -label   => '' ), 'debug ',
		a( {-onclick => 'alert("Report on database loading progress;\\n' .
			        'provides debugging information")' }, '[?]'), '&nbsp;&nbsp;',
		checkbox ( -name    => $self->config_name('reload'),
			   -value   => 'reload',
			   -label   => '',
			   -checked => 1 ), 'reload browser after database update') . "\n";

    $html;
}

sub dump {
    my $self = shift;
    my $conf = $self->configuration;
    my $db   = $self->database;
    my $rollback = $conf->{rb_id};
    $self->refseq($conf->{seqid}) if $conf->{seqid};
    
    # set the parser type to Bio::DB::GFF
    $self->{parser} = 'Bio::DB::GFF';

    my $gff = $rollback ? $self->rollback($rollback) : $self->gff;

    if ( $conf->{debug} ) {
	print h2("Rolling back to previous state...", br )
          if $rollback;
	print h2("The input features:"), pre($gff);
    }


    my $segment  = $db->segment( $self->refseq );

    if ( $segment ) {
	# save the state of the segment in case we want to roll back later 
        if ( $ROLLBACK ) {
	    $self->{rb_loc} ||= $ROLLBACK;
	    $self->save_state($segment);
	}

	my @killme = $segment->features;
	my $killed;

        my $killed = $db->delete( $segment->ref );
	
        print h2("I removed $killed features from the database"), pre(join "\n", @killme) 
	    if $conf->{debug}; 
    }
	
    # $gff = $self->component($gff);

    # don't try loading sequence if the sequence is already in
    # the database
    if ( $self->seq && !( $segment && $segment->seq ) ) {
	$gff .= "\n>" . $self->refseq . "\n" . $self->seq;
    }

    my $gff_fh  = IO::String->new($gff);
    my $result = $db->load_gff($gff_fh);

    print h2($result, " new features loaded into the database");

    my $source = $conf->{acc} ? "Sequence " . $conf->{acc}
                              : $conf->{format} . ' file ' . $conf->{file};
    
    unless ( $result ) {
	print h2("Features from $source not loaded correctly");
        exit;
    }

    if ( $conf->{debug} && $conf->{reload} ) {
        print h2("This browser will be reloaded with the new sequence in 10 seconds...");
        sleep 10;
    }

    $self->load_page();
}

# relaod gbrowse or make a reload button
sub load_page {
    my $self = shift;
    my $conf = $self->configuration;
    my $url = self_url();
    $url =~ s/\?.+$//g;
    my $name = $self->refseq . ':';
    $name .= $self->start . '..' . $self->end;
    print start_form( -name   => 'f1', 
		      -method => 'POST',
		      -action => $url );
    print hidden( name => $name );

    if ( $conf->{reload} ) {
	print body( { -onLoad => "document.f1.submit()" } );
    }
    else {
	print submit( -name => 'Return to Browser' );
    }
}

sub gff {
    my $self = shift;
    my $conf = $self->configuration;
    my $format = $conf->{format};
    my $file = $conf->{file};
    my $text = '';
    $self->{header} = 1;

    if ( $conf->{acc} ) {
        $self->refseq($conf->{acc});
	return $self->get_embl($conf->{acc});
    }    

    unless ( $file ) {
        print h2("Error: No file was selected");
	exit;
    }
    else {
	while ( <$file> ) {
	    $text .= $_;
	}
    }

    if ( $format eq 'GENBANK' ) {
	$self->{source} = 'GenBank';
	return $self->read_genbank($text);
    }
    elsif ( $format eq 'EMBL' ) {
	$self->{source} = 'EMBL';
	return $self->read_embl($text);
    }
    elsif ( $format eq 'GFF' ) {
        return $self->read_gff($text);
    }
    else {
	$self->bad_format("Unrecognized format $format:", $text);
	exit;
    }
    
}

sub bad_format {
    my ($self, $msg, $text) = @_;
    print h2($msg);
    print pre($text);
    exit;
}

sub get_embl {
    my ($self, $acc) = @_;
    my $gb = Bio::DB::GenBank->new;
    my $eb = Bio::DB::EMBL->new;

    my $seqobj = '';
    if ( $seqobj = eval{$gb->get_Seq_by_acc($acc)} ) {
	$self->{source} = 'Genbank';
    }
    elsif ( $seqobj = eval{$eb->get_Seq_by_acc($acc)} ) {
	$self->{source} = 'EMBL';
    }
    else {
	print h1("Error: unable to retrieve accession '$acc' from GenBank or EMBL");
        exit;
    }
    
    return $self->seq2GFF($seqobj);
}

sub read_genbank {
    my ($self, $text) = @_;
    my $conf  = $self->configuration;
    my $seqid = $conf->{seqid};
    $self->{source} = 'GenBank';    
    
    $self->bad_format("This does not look like GenBank to me:", $text)
	if $text !~/^BASE COUNT/m;

    unless ( $text =~ /^LOCUS/ ) {
	unless ( $seqid ) {
	    print h1('Error: No sequence ID', br,
		     'A sequence ID is required if the GenBank',
		     ' record has no header');
	    exit;
	}
        $text = "LOCUS       $seqid\nFEATURES             Location/Qualifiers\n" . $text;
        $conf->{file} = '';
    }

    my $in = Bio::SeqIO->new( -fh => IO::String->new($text), -format => 'genbank')
      || $self->parsefail(Bio::SeqIO->error);
    my $seqobj    = $in->next_seq || $self->parsefail($in->error);
    
    $seqobj || $self->bad_format("Problem reading GenBank:", $text); 
    
    return $self->seq2GFF($seqobj);
}

sub read_embl {
    my ($self, $text) = @_;
    my $conf  = $self->configuration;
    my $seqid = $conf->{seqid};
    $self->{source} = 'GenBank';

    $self->bad_format("This does not look like EMBL to me:", $text)
        if $text !~/^FT\s+\S+/m;

    unless ( $text =~ /^ID/ ) {
        unless ( $seqid ) {
            print h1('Error: No sequence ID', br,
                     'A sequence ID is required if the EMBL',
                     ' record has no header');
            exit;
        }
        $text = "ID   $seqid\nFH   Key             Location/Qualifiers\n" . $text;
	$conf->{file} = '';
    }
    elsif ( $text =~ /^ID\s+(\S+)/ ) {
	$self->refseq($1);
    }

    my $in = Bio::SeqIO->new( -fh => IO::String->new($text), -format => 'embl')
	|| $self->parsefail(Bio::SeqIO->error);
    my $seqobj    = $in->next_seq || $self->parsefail($in->error);

    $seqobj || $self->bad_format("Problem reading EMBL:", $text);

    return $self->seq2GFF($seqobj);
}

sub seq2GFF {
    my ($self, $seq) = @_;
    my $conf = $self->configuration;

    my @feats = $seq->all_SeqFeatures;

    
    # make the 'Note' key lowercase and
    # crush evil embedded semicolons
    for ( @feats ) {
        for my $t ( $_->all_tags ) {
	    my @v = $_->remove_tag($t);
	    
	    for my $v ( @v ) {
		$v =~ s/;/,/g;
		$_->add_tag_value( $t => $v );
	    }
	}
    }

    my $seqid = $self->refseq || $conf->{seqid};
  
    my $gff;
    
    for ( @feats ) {
	
	if ( ref $_->location eq 'Bio::Location::Split' ) {
	    $gff .= $self->unflatten($_);
	}
	else {
	    $gff .= $_->gff_string . "\n";
	}
    }    
    
    $gff          =~ s|SEQ|$seqid|gm;

    $self->seq( $seq->seq );
    $self->refseq( $seqid );
    

    for my $gene ( @{$self->{unflattened}} ) {
	$gff =~ s/(CDS.+$gene\b)/${1}a/gm;
    }
    
    return $self->read_gff($gff);
}

sub parsefail {
    my ($self, $reason) = @_;
    my $method = $self->configuration->{method};
    print h2("$method parse failure:", br, "Reason: ", pre($reason));
    exit;
}

sub unflatten {
    my ($self, $feat) = @_;
    my $conf = $self->configuration;

    print h3("Unflattening ", $feat->primary_tag, ':', 
             $feat->start, '..', $feat->end) if $conf->{debug}; 

    my $gff = '';    
    my $location = $feat->location;
    my $str = $feat->strand;
    $str = '+' if $str  > 0;
    $str = '-' if $str  < 0;
    $self->{unflattened} ||= [];
    my $newname = '';

    my ($class, $name) = $self->guess_name($feat);
    
    if ( $self->{seen}->{$class}->{$name} && $feat->primary_tag =~ /mRNA|CDS/i ) {
	my $lett = shift @{$self->{alpha}};
        $newname = $name . $lett;
    }
    
    $self->{seen}->{$class}->{$name}++;
    $self->{alpha} = [ 'b'..'z' ] if $self->{seen}->{$class}->{$name} == 1;
    push @{$self->{unflattened}}, $name if $self->{seen}->{$class}->{$name} == 2;    

    my @segments = map { [$_->start, $_->end] }
        $location->can('sub_Location') ? $location->sub_Location : $location;

    $feat->primary_tag('mRNA') if $feat->primary_tag eq 'CDS';
    my $parttype;
    
    if ( $feat->primary_tag eq 'gene' ) {
	$parttype = 'exon';
    }
    elsif ( $feat->primary_tag eq 'mRNA' ) {
	$parttype = 'CDS';
    }
    else {
	$parttype = $feat->primary_tag;
    }
 
    $gff = $self->new_gff_string($feat) . "\n";
    
    $name  = $newname if $newname;
    
    for my $segment (@segments) {
        my $start = $segment->[0];
	my $stop  = $segment->[1];
	$gff .= join "\t", 
	    ($self->refseq,  $self->{source}, $parttype, $start, $stop, '.', $str, '.');
        
	$gff .= "\t$class $name\n";
    }

    $gff;

}

sub forbid {
    my $self = shift;
    $ips || return 0;
    my $fatal = shift;
    my $host = remote_addr();

    return $ips =~ /$host/m ? 0 : 1;

}

1;
