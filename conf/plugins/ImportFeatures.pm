# $Id: ImportFeatures.pm,v 1.12 2003-11-13 14:55:47 sheldon_mckay Exp $

=head1 NAME

Bio::Graphics::Browser::Plugin::ImportFeatures -- a plugin to 
import features into the Generic Genome Browser

=head1 SYNOPSIS

This modules is not used directly

=head1 DESCRIPTION

ImportFeatures.pm processes external features and loads them 
into the GFF database.  It will accept flat files in GenBank, 
EMBL or GFF2 format or can download accessions from NCBI/EBI.  

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

  NOTE: GFF editing via artemis will not be supported in the 
        next release and in the current version (version 5)
        GFF handling is broken.  Trying to save a GFF default 
        entry in Artemis results is an unusable GFF/EMBL hybrid.
        For best results, use the native Artemis format (EMBL) 
        dumped by the ExportFeatures plugin.  This format is supported
        by version 5 and the development releases.

 1) use the ExportFeatures plugin to dump an EMBL 
    feature table to a file (or directly to Artemis as a 
    helper application configured in the browser)

 2) edit your features 

 3) Save the default record in Artemis, then exit

 4) load the file via this plugin.  This can be automated 
    with a perl wrapper using HTTP::Request::Common and
    LWP::UserAgent   

Make sure to enable direct editing in the Artemis configuration 
file 'options.txt'.  See the Artemis documentation for more 
information on setup options.

You can also use Artemis to help import features from 
other sources.  Artemis saves features as a tab files, 
which are feature tables with the header information 
stripped away.  All three flavors of Artemis tab files 
can be imported via this plugin if the name of the 
sequence is provided with the file.

=head2  Loading Sequence

If the DNA is included in a new file/accession, it
will be loaded into the database along with the features.
However, if this the sequence for the segment is
already in the database, it will not be reloaded.
Editing/Changing the sequence is not currently supported.


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
reference sequence) is dumped by GFFDumper and ExportFeatures.

NOTE: the exception to this is if the incoming feature file 
has features with the 'database_id' attribute.  In this case,
the file is treated as a selected feature file.  Only the 
features with the corresponding IDs in the database will be 
deleted. The database_id attributes are added automatically 
by ExportFeatures.pm if the dump mode is set to 'selected'


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
use Data::Dumper;

use vars qw /@ISA $ROLLBACK/;

@ISA = qw/ Bio::Graphics::Browser::Plugin 
           Bio::Graphics::Browser::GFFhelper /;


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
        reload => 1
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

    # web browsers won't let us force a filename in a filefield
    # give the user some text to cut and paste of this information is
    # passed in via the URL
    my $sorry = '';
    if ( my $filename = $self->config_param('file') ) {
	my $len = (length $filename) + 20;
        $filename = "<input name=null value='$filename' size=$len>";
	$sorry = br . br ."<font size=-1>This browser does not support direct file " .
                          "loading from an external editor. <br>Please copy and paste " .
                          "the following text into the file upload field " . br .
                          "or use the 'Browse' button to navigate to the saved annotation file" .
                 br . $filename; 
    }                         

    my $html = join ( "\n", 
	"<table>\n" ,
	Tr( { -class => 'searchtitle' }, td( $f, 'Upload External Annotations' ) ) ,
        "<tr><td class='searchbody'>" ,
        h3('Format: ',
	   radio_group( -name    => $self->config_name('format'),
			-values  => [ qw/GFF GENBANK EMBL/ ],
			-default => $conf->{format} || $self->config_param('format'))),
	h3('Sequence ID: ', 
            textfield( -name  => $self->config_name('seqid'),
		       -size  => 10,
		       -value => $conf->{seqid}), ' ',
	   a( {-onclick => 'alert("Required for headerless feature tables")'}, '[?]')),
	h3('Name of file to upload: ',
            filefield( -name    =>  $self->config_name('file'),
		       -size    => 40,
		       -default => $conf->{file} || $self->config_param('file') ), $sorry),
        "</td></tr></table>" );
    unless ( $self->config_param('filesource') && $self->config_param('filesource') eq 'external' ) {
        $html =~ s/External Annotations/a GenBank\/EMBL\/GFF File/m;
	$html .= join ( "\n", h3(' - OR - '), "<table>\n" ,
	         Tr( { -class => 'searchtitle' }, td( $f, 'Direct Download from NCBI/EBI' ) ),
                 "<tr><td class='searchbody'>",
                 h3( 'Accession ',
	         textfield( -name    =>  $self->config_name('acc'),
		            -size    => '15'), ' ',
	         a( {-onclick => 'alert("Use a GenBank/EMBL accession number (not GI)\\n' .
                                  'Note: this will override file uploading")'}, '[?]')),
                 "</td></tr></table>\n" );

        # add a rollback table if required
        my $msg = "Selecting rollback will override loading of files or accessions";
        $html .= "\n" . h3(' - OR - ') . "\n" . $self->rollback_form($msg) if $ROLLBACK;
        $html =~ s|searchbody>(.+)</td>|searchbody><h3>$1</h3></td>|sm;
    }
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
    $self->refseq($conf->{seqid}) if $conf->{seqid};
    
    # look for a rollback request
    my $rollback = $self->config_param('rb_id');
    
    my $gff = $rollback ? $self->rollback($rollback) : $self->gff;
    
    # add an origin feature if req'd
    $gff = $self->origin($gff) if $self->{source} && 
                                  $gff !~ /\torigin\t/i &&
				  !$self->{database_ids};
    
    # Oracle is case sensitive for attributes
    $gff =~ s/note=/Note=/gm;    

    if ( $conf->{debug} ) {
	print h2("Rolling back to previous state...", br )
          if $rollback;
	print h2("The input features:"), pre($gff);
    }
    
    my $segment  = $db->segment( 'Sequence', $self->refseq )  ||
	           $db->segment( 'Accession', $self->refseq );

    my $nodna = 0;
    
    if ( $segment ) {
	# make sure we know not to try to add sequence later
	$nodna++ if $segment->seq;
        
        # save the state of the segment in case we want to roll back later 
        if ( $ROLLBACK ) {
	    $self->{rb_loc} ||= $ROLLBACK;
 	    $self->save_state($segment);
	}

        my (@killme, @killme2);

        if ( $self->{database_ids} ) {
	    # kill features by database id
	    @killme = @{$self->{database_ids}};
	    
	    # remove any full length Component:reference features
	    # (GFF.pm will add a new one)
	    my $iterator = $segment->get_seq_stream('Component');
	    while ( my $comp = $iterator->next_seq ) {
		if ( $comp->length == $segment->length ) {
		    push @killme2, $comp;
		}
	    }
	}
	else {
	    @killme = $segment->features;
	}
	
        my $killed = $db->delete_features( @killme );
	
	# look out for stale database ids
	if ( $killed && $killed == 0 ) {
	    print h3("Problem deleting features by database ID" . br .
		     "The IDs may be stale. 'Selected' feature edits must " .
		     "be loaded immediately upon completion");
	    exit;
	}

        $killed += $db->delete_features(@killme2) if @killme2;

	print h2("I removed $killed features from the database"), pre(join "\n", @killme) 
	    if $conf->{debug}; 
    }
	
    # don't try loading sequence if the sequence is already in
    # the database
    if ( $self->seq && !$nodna ) {
	$gff .= "\n>" . $self->refseq . "\n" . $self->seq;
    }

    my $gff_fh  = IO::String->new($gff);
    my $result = $db->load_gff($gff_fh);

    print h2($result, " new features loaded into the database");

    unless ( $result ) {
	print h2("Features from not loaded correctly");
        exit;
    }

    if ( $conf->{debug} && $conf->{reload} ) {
        print h2("This browser will be reloaded with the new sequence in 10 seconds...");
        sleep 10;
    }

    $self->load_page();
}

# reload gbrowse or make a reload button
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
    
    print qq(<input type=hidden name=name value="$name">);

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
        # we don't the text ending up as a cookie, so not plugin prefix
        # for the text parameter
        $text = param('text');
    }
    else {
	while ( <$file> ) {
	    $text .= $_;
	}
    }

    # do we have some data?
    $self->bad_format("Error: no text to parse") unless $text || $file;

    $self->{database_ids} = []if $text =~ /database_id/m;    

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

    # change Sequence qualifier to Accession
    $text =~ s/\/Sequence/\/Accession/img;

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

    # save the description
    $self->{desc} = $seq->desc;
    
    for ( @feats ) {
        for my $t ( $_->all_tags ) {
            my @v = $_->remove_tag($t);
	    if ($t eq 'database_id') {
		push @{$self->{database_ids}}, $v[0];
		next;
	    }
	    for my $v ( @v ) {
		$v =~ s/;/,/g;
		$_->add_tag_value( $t => $v );
	    }
	}
    }

    my $seqid = $self->refseq || $conf->{seqid} || $seq->id; 
    $self->refseq($seqid);
    $self->seq( $seq->seq );  
    my $gff;
    
    for ( @feats ) {
	if ( ref $_->location eq 'Bio::Location::Split' ) {
	    $gff .= $self->unflatten($_);
	}
	else {
	    $gff .= $_->gff_string . "\n";
	}
    }    

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
    $str = $str > 0 ? '+' : $str < 0 ? '-' : '.';
    $self->{unflattened} ||= [];
    my $newname = '';

    my ($class, $name);
    for ( qw/standard_name gene locus_tag/ ) {
	if ( $feat->has_tag($_) ) {
	    $class  = 'gene';
	    ($name) = $feat->get_tag_values($_); 
	}
	last if $class && $name;
    }
    
    if ( $self->{seen}->{$class}->{$name} && $feat->primary_tag =~ /mRNA|CDS/i ) {
	my $lett = shift @{$self->{alpha}};
        $newname = $name . $lett;
    }
    
    $self->{seen}->{$class}->{$name}++;
    $self->{alpha} = [ 'b'..'z' ] if $self->{seen}->{$class}->{$name} == 1;
    push @{$self->{unflattened}}, $name if $self->{seen}->{$class}->{$name} == 2;    

    my @segments = map { [$_->start, $_->end] }
        $location->can('sub_Location') ? $location->sub_Location : $location;

    if ( $feat->primary_tag eq 'CDS' ) {
	$feat->primary_tag('mRNA');
    }
    
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
 
    $gff = $feat->gff_string . "\n";
    
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
