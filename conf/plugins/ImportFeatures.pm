# $Id: ImportFeatures.pm,v 1.14 2004-01-24 16:57:31 sheldon_mckay Exp $

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
will be unflattened via Bio::SeqFEature::Tools::Unflattener and
loaded as containment hierarchies via GFF3.

=head2 Editing Features in an External Editor

This plugin can be used to load externally edited features, 
as long as the editor is capable of exporting GenBank, EMBL 
or GAME-XML. GFF2 is not recommended.  The currently available
options are manually editing GFF, Artemis.  Support for Apollo 
is still experimental pending further testing/debugging of the
Bio::SeqIO::game modules.  Note that in-place creation, 
deletion and editing of features can also be done from gbrowse
(using the BasicEditor plugin).

=head2  Using Artemis as an External Editor

  NOTE: GFF2 editing via artemis will not be supported in the 
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
    LWP::UserAgent (see the helper script included in the
    Artemis/Apollo plugin)   

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

This plugin can be used to roll back to an earlier state.  
If the rollback functionality is enabled, the state of the 
segment will be saved to a file before each database update.  
The last five pre-update states will be saved in a round-robin 
rotation and can be accessed via the configuration form.

To enable rollback capability, define the $ROLLBACK scalar 
variable with a string containing the path to location where 
the web user ('apache', 'nobody', etc) has read/write access.

=head1 FEEDBACK

See the GMOD website for information on bug submission http://www.gmod.org.

=head1 AUTHOR - Sheldon McKay

Email smckay@bcgsc.bc.ca

=head1 CONTRIBUTORS

Scott Cain (cain@cshl.org)
Mark Wilkinson (markw@illuminae.com)

=head1 SEE ALSO

Bio::Graphics::Browser::Plugin::GFFDumper 

Bio::Graphics::Browser::Plugin::BasicEditor

Artemis (http://www.sanger.ac.uk/Software/Artemis)

=cut

package Bio::Graphics::Browser::Plugin::ImportFeatures;

use strict;
use Bio::SeqIO;
use Bio::DB::EMBL;
use Bio::Tools::GFF;
use Bio::DB::GenBank;
use Bio::DB::GFF::Feature;
use CGI qw/:standard escape/;
use CGI::Carp 'fatalsToBrowser';
use Bio::Graphics::Browser::Plugin;
use Bio::Graphics::Browser::GFFhelper;
use Bio::SeqFeature::Tools::Unflattener;

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
    $conf->{erase}  = $self->config_param('erase') || 'selected';
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

    my $html = join ( "\n", "<table>\n" ,
	Tr( { -class => 'searchtitle' }, td( $f, 'Upload a file' ) ) ,
		      "<tr><td class='searchbody'>" ,
		      h3('Format: ',
			 radio_group( -name    => $self->config_name('format'),
				      -values  => [ qw/GFF GENBANK EMBL GAME/ ],
				      -default => $conf->{format} || $self->config_param('format'))),
		      h3('Sequence ID: ', 
			 textfield( -name  => $self->config_name('seqid'),
				    -size  => 10,
				    -value => $conf->{seqid}), ' ',
			 a( {-onclick => 'alert("Required for headerless feature tables")',
			     -href => "javascript:void(0)"}, '[?]')),
		      h3('Name of file to upload: ',
			 filefield( -name    =>  $self->config_name('file'),
				    -size    => 40,
				    -default => $conf->{file} )),
		      "</td></tr></table>" );
    
    $html .= join ( "\n", h3(' - OR - '), "<table>\n" ,
		    Tr( { -class => 'searchtitle' }, td( $f, 'Direct Download from NCBI/EBI' ) ),
		    "<tr><td class='searchbody'>",
		    h3( 'Accession ',
			textfield( -name    =>  $self->config_name('acc'),
				   -size    => '15'), ' ',
			a( {-onclick => 'alert("Use a GenBank/EMBL accession number (not GI)\\n' .
				'Note: this will override file uploading")',
				-href => "javascript:void(0)"}, '[?]')),
		    "</td></tr></table>\n" );

    # add a rollback table if required
    my $msg = "Selecting rollback will override loading of files or accessions";
    $html .= "\n" . h3(' - OR - ') . "\n" . $self->rollback_form($msg) if $ROLLBACK;
    $html =~ s|searchbody>(.+)</td>|searchbody><h3>$1</h3></td>|sm;
    
    $msg = "If the data being loaded affect an existing segment, select one of " .
	"these options to specify how existing features should be handled:\\n" .
	"colliding -- remove any features of the same type and coordinates as " .
	"the incoming features.\\n\\nspecified --  if only selected features for a " .
	"segment were exported to the external editor, the annotation file will " .
	"contain the original feature ids, which will allow targeted deletion " .
	"of the old features prior to loading.  If deleting features by id fails, " .
	"colliding features will automatically be removed.\\n\\nall -- this option will ".
	"wipe the affected coordinate range free of all contained features before loading";

    $msg = a( {-onclick => "alert('$msg')", -href => "javascript:void(0)"}, '[?]' );

    $html .= h4(checkbox ( -name    => $self->config_name('debug'),
			   -value   => 'debug',
			   -label   => '' ), 'Verbose Reporting',
	     a( {-onclick => 'alert("Report on database loading progress;\\n' .
		             'provides debugging information")',
                 -href => "javascript:void(0)" }, '[?]')) . 
	     h4(checkbox ( -name    => $self->config_name('reload'),
			-value   => 'reload',
			-label   => '',
			-checked => 1 ) . 'Reload browser after database update') .
             h4("Method for deleting existing in-range features $msg " .
                '&nbsp;&nbsp;&nbsp;' .
		radio_group ( -name    => $self->config_name('erase'),
			      -values  => [ qw/colliding selected all/ ],
		              -default => $conf->{erase} || 'all' ));
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

    # make sure we know our sequence name and range
    unless ( $self->refseq && $self->start && $self->end ) {
	$self->get_range($gff);
    }

    # Oracle is case sensitive for attributes
    $gff =~ s/note=/Note=/gm if ref($db) =~ /Oracle/i;    

    if ( $conf->{debug} ) {
	print h2("Rolling back to previous state...", br )
          if $rollback;
	print h2("The input features:"), pre($gff);
    }
    
    my $segment  = $db->segment( Sequence => $self->refseq )
                || $db->segment( Accession => $self->refseq );

    my $nodna = 0;
    
    if ( $segment ) {
	# make sure we know not to try to add sequence later
	$nodna++ if $segment->seq;

        # adjust segment coordinates to match GFF range
        $segment->start($self->start);
        $segment->end($self->end);
        
        # save the state of the segment in case we want to roll back later 
        if ( $ROLLBACK ) {
	    $self->{rb_loc} ||= $ROLLBACK;
 	    $self->save_state($segment);
	}

	my @killme;
        if ( $conf->{erase} eq 'all' && ! $self->{database_ids} ) {
            # wipe the segment clean
            $self->_print("Removing all features from $segment");
	    @killme = grep { 
		$_->start >= $self->start &&
                $_->end   <= $self->end  
	    } $segment->features; 
	}
	elsif ( $conf->{erase} eq 'selected' && $self->{database_ids} ) {
            # remove features by database id
	    $self->_print("Removing selected features (by id) from $segment");
	    @killme = @{$self->{database_ids}};
	}
	else {
            # just remove colliding features
	    $self->_print("Removing colliding features from $segment");
	    @killme = $self->kill_list($gff, $segment);
	}        

	my $killed = $db->delete_features( @killme );
        
	# stale database ids?
	if ( !ref $killme[0] && $killed < @killme ) {
            $self->_print("That did not work, looking for colliding features instead...");
	    @killme = $self->kill_list($gff, $segment);
	    $killed += $db->delete_features( @killme );
	}

	$killed ||= 'No';

	$self->_print("I removed $killed features from the database" . 
                      pre(join "\n", @killme) ); 

    }
	
    # don't try loading sequence if the sequence is already in
    # the database
    if ( $self->seq && !$nodna ) {
	$gff .= "\n>" . $self->refseq . "\n" . $self->seq;
    }

    # load tge GFF into the database
    my $gff_fh  = IO::String->new($gff);
    my $result  = $db->load_gff($gff_fh) || 'No';
    my $remark = $result =~ /No/ ? br ."This can't be good..." : ''; 

    print h2("$result features were loaded into the database.$remark");

    unless ( $result =~ /^\d+$/ ) {
	print h2("Features (below) not loaded correctly") . pre($gff);
        exit;
    }

    if ( $conf->{reload} ) {
        $self->_print(h2("The Browser in 10 seconds..."));
        sleep 10;
    }

    $self->load_page($gff);
}

# reload gbrowse or make a reload button
sub load_page {
    my ($self, $gff) = @_;
    my $conf = $self->configuration;
    $self->get_range($gff);

    my $url = self_url();
    $url =~ s/\?.+$//g;
    my $name = $self->refseq. ':';
    $name .= $self->start . '..' . $self->end;
    print start_form( -name   => 'f1', 
		      -method => 'POST',
		      -action => $url );
    
    print qq(<input type=hidden name=name value="$name">);

    if ( $conf->{reload} ) {
	print body( { -onLoad => "document.f1.submit()" } );
    }
    else {
	print submit( -name => "Return to Browser ($name)" );
    }
}

sub gff {
    my $self = shift;
    my $conf = $self->configuration;
    my $format = $conf->{format};
    my $file = $conf->{file};
    print h1($file);
    my $text = '';
    $self->{header} = 1;

    if ( $conf->{acc} ) {
        $self->refseq($conf->{acc});
	return $self->get_embl($conf->{acc});
    }    

    unless ( $file ) {
        # we don't the text ending up as a cookie (will break gbrowse), 
        # so no plugin prefix for the text parameter
        $text = param('text');
    }
    else {
	while ( <$file> ) {
	    $text .= $_;
	}
    }
    
    # do we have some data?
    $self->bad_format("Error: no text to parse") unless $text;

    # beware of DOS line endings!
    $text =~ s/\r//gm;

    if ( $format eq 'GENBANK' ) {
	$self->{source} = 'GenBank';
	return $self->read_genbank($text);
    }
    elsif ( $format eq 'EMBL' ) {
	$self->{source} = 'EMBL';
	return $self->read_embl($text);
    }
    elsif ( $format eq 'GFF' ) {
        return $text =~ /\#gff-version 3/m ? $text : $self->read_gff($text);
    }
    elsif ( $format eq 'GAME' ) {
	return $self->read_game($text);
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

sub read_game {
    my ($self, $text) = @_;
    my $conf  = $self->configuration;
    $self->{source} = 'Apollo';

    my $in = Bio::SeqIO->new( -fh => IO::String->new($text), -format => 'game')
	    || $self->parsefail(Bio::SeqIO->error);
    my $seqobj    = $in->next_seq || $self->parsefail($in->error);

    $seqobj || $self->bad_format("Problem reading GenBank:", $text);

    return $self->seq2GFF($seqobj);
}

sub read_genbank {
    my ($self, $text) = @_;
    my $conf  = $self->configuration;
    my $seqid = $conf->{seqid};
    $self->{source} = 'GenBank';    
    
    $self->bad_format("This does not look like GenBank to me:", $text)
	if $text !~/^ORIGIN/m;

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
    my $gff  = "##gff-version 3\n";
    my $unflattener = Bio::SeqFeature::Tools::Unflattener->new;
    $self->{idcount} = 0;
    my $acc = $conf->{seqid} || $seq->accession || $seq->display_name;
    $self->refseq($acc);
    $self->seq( $seq->seq );
    $self->{desc} = $seq->desc;
    
    $self->{SOFA} = [
                     'region',
                     'gene',
                     'mRNA',
                     'exon',
                     'CDS',
                     'chromosome_variation',
                     'computed_feature_by_similarity',
                     'repeat_region',
                     'STS',
                     'rRNA',
                     'tRNA',
                     'RNA',
                     'SNP'
                     ];

    # get top level unflattended SeqFeatureI objects
    $self->{text} ||= '';
    my @sfs = eval {
	$unflattener->unflatten_seq( -seq => $seq, -use_magic => 1)
    } or $self->_print("Error: The features did not unflatten properly\n"
                       ."Please check your annotation file \n\n", $self->{text}) and exit;
    
    my @skipped_lines;

    my $gene_count;
    for my $sf (@sfs) {
	if ( $sf->has_tag('database_ids') ) {
	    my ($ids) = $sf->get_tag_values('database_ids');
	    $self->{database_ids} = [ split ',', $ids ];
	    next;
	}

        $sf->seq_id($acc);
        $sf->source_tag($self->{source});
        $sf->gff_format( Bio::Tools::GFF->new( -gff_version => 3 ) );

        if ( $sf->primary_tag eq 'source' && !$sf->has_tag('ID') ) {
	    $sf->add_tag_value( 'ID', "Sequence:$acc" );
            $sf->primary_tag('region');
            $self->_print("Setting source type as 'region', which is a more generic");
        }

        next if $sf->primary_tag eq 'CONTIG';

        if ( $sf->primary_tag eq 'misc_feature' ) {
            my $new_primary_tag;
            if ($sf->has_tag('note')) {
                my @values = $sf->get_tag_values('note');
                foreach my $value (@values) {
                    if ($value =~ /similar/) {
                        $new_primary_tag = 'computed_feature_by_similarity';
                    }
                } 
            }
            if ($new_primary_tag) {
                $sf->primary_tag($new_primary_tag);
		$self->_print( "Converting misc_feature to 'computed_feature_by_similarity'\n" .
                               "which will result in this gff line:\n" . $sf->gff_string );
            } 
	    #else {
            #    $self->_print("skipping misc_feature line\n");
            #    push @skipped_lines, $sf->gff_string . "\n";
            #    next;
            #}
        }

        if ( $sf->primary_tag =~ /misc.*rna/i ) {
            $sf->primary_tag('RNA');
        }

	if ( $sf->primary_tag eq 'gene' ) {
            my ($gene_name) = $sf->has_tag('gene') 
                  ? $sf->get_tag_values('gene')
                  : $sf->get_tag_values('locus_tag');
            
	    # some non-word characters causing mischief here
	    # convert to hex escape code
	    $gene_name = escape($gene_name);

	    $sf->add_tag_value( 'ID', "gene:$gene_name" );
            
        }

        if ( $sf->primary_tag eq 'variation' and $sf->length == 1 ) {
            $sf->primary_tag('SNP');
        } elsif ($sf->primary_tag eq 'variation') {
            $sf->primary_tag('chromosome_variation');
        }

        unless ( $sf->has_tag('ID') ) {
	    my @tags = $sf->all_tags;
	    if ( @tags == 1 ) {
		my ($v) = $sf->get_tag_values($tags[0]);
                $sf->add_tag_value( ID => "$tags[0]:$v" );
	    }
	}

	
	$self->validate_tag($sf);
	$self->validate_ID($sf, $acc);
        $self->clean_up_tags($sf);

	$gff .= $sf->gff_string . "\n";

        my $localgeneid = 1;
        foreach my $sf2 ( $sf->get_SeqFeatures ) {
            $sf2->seq_id($acc);
            $sf2->gff_format( Bio::Tools::GFF->new( -gff_version => 3 ) );

            if ( $sf->has_tag('ID') && !$sf2->has_tag('Parent') ) {
                if ( $sf->has_tag('Name') ) {
		    $sf2->add_tag_value( 'Name', $sf->get_tag_values('Name') );
		}
		$sf2->add_tag_value( 'Parent', $sf->get_tag_values('ID') );
            }

            if ( $sf2->primary_tag eq 'variation' and $sf2->length == 1 ) {
                $sf2->primary_tag('SNP');
            } elsif ($sf2->primary_tag eq 'variation') {
                $sf2->primary_tag('chromosome_variation');
            }

            if ( $sf2->primary_tag() =~ /misc.*rna/i ) {
                $sf2->primary_tag('RNA');
            }

            if ( $sf2->primary_tag eq 'misc_feature' ) {
                my $new_primary_tag;
                if ($sf2->has_tag('note')) {
                    my @values = $sf2->get_tag_values('note');
                    foreach my $value (@values) {
                        if ($value =~ /similar/) {
                            $new_primary_tag = 'computed_feature_by_similarity';
                        }
                    }
                }
                if ($new_primary_tag) {
                    $sf2->primary_tag($new_primary_tag);
                    $self->_print( "Converting misc_feature to 'computed_feature_by_similarity'\n" .
				   "which will result in this gff line:\n" . $sf2->gff_string );
                } 
		#else {
                    #$self->_print("skipping misc_feature line");
                    #push @skipped_lines, $sf2->gff_string . "\n";
                    #next;
                #}
            }

            $sf2->source_tag( $self->{source} );
            my @subfeats = $sf2->get_SeqFeatures;

	    my ($sn, $parentID);
	    if (@subfeats > 0) {
                $sn = $self->_sname(@subfeats);
                unless ($sf2->has_tag('ID')) {
                    ($parentID) = $sf->get_tag_values('ID');
                    my $ft = $sf2->primary_tag;
		    unless ( $sn ) {
			$parentID =~ s/(\w+:)/${ft}:/;
			$parentID .= "_$localgeneid";
		    }
                    $parentID =~ s/.+:/$ft\:/;
                    my $id = $sn ? "$ft:$sn" : $parentID;
		    $sf2->add_tag_value( 'ID', $id );
                    $localgeneid++;
                } 

		unless ( $sf2->has_tag('standard_name') ) {
		    $sf2->add_tag_value( standard_name => $sn );
		}
	    }
            
	    $self->validate_tag($sf2);
	    $self->validate_ID($sf2, $acc);
            $self->clean_up_tags($sf2);

            $gff .= $sf2->gff_string . "\n";

            my ($subf_count);
	    foreach my $sf3 ( @subfeats ) {
                $sf3->seq_id($acc);
                $sf3->gff_format( Bio::Tools::GFF->new( -gff_version => 3 ) );
		my ($parentID) = $sf2->get_tag_values('ID');

		# Huh?? Shared exons in alternative splice variants point to
                # the same Bio::SeqFeature object.  We have to recycle.
                $sf3->remove_tag('Parent') if $sf3->has_tag('Parent');
		$sf3->add_tag_value( 'Parent', $parentID );
                $sf3->source_tag( $self->{source} );
                
		if ( $sf3->primary_tag eq 'CDS' && !$sf3->has_tag('standard_name') ) {
		    $sf3->add_tag_value( standard_name => $sn );
		}

		$self->validate_tag($sf3);
		$self->validate_ID($sf3, $acc);
		$self->clean_up_tags($sf3);

		$gff .= $sf3->gff_string . "\n";
            }
        }
    }

    $self->seq($seq->seq);
    $self->start(1);
    $self->end(length $seq->seq);

    if (@skipped_lines) {
        $self->_print( ('-' x 72) . "skipped lines:");
        foreach my $line (@skipped_lines) {
            $self->_print($line);
        }
    }

    $gff;
}

sub validate_tag {
    my ($self,$sf) = @_;
    my $tag = $sf->primary_tag;
    if (! ( grep( /^\Q$tag\E$/, @{$self->{SOFA}}))) {
        $self->_print("$tag is an uncommon (and possibly illegal) feature type\n" .
                      "It will result in a gff line like this:\n" . $sf->gff_string);
    }
}

sub _print {
    my ($self, @text) = @_;
    my $text = join '', @text;
    chomp $text;
    my $conf = $self->configuration;
    return 0 unless $conf->{debug};
    print $text =~ /\n/ ? b(pre($text)) : h2($text);
}

sub parsefail {
    my ($self, $reason) = @_;
    my $method = $self->configuration->{method};
    print h2("$method parse failure:", br, "Reason: ", pre($reason));
    exit;
}

sub forbid {
    my $self = shift;
    $ips || return 0;
    my $fatal = shift;
    my $host = remote_addr();

    return $ips =~ /$host/m ? 0 : 1;
}

sub clean_up_tags {
    my ($self, $f) = @_;
    for ( qw/ID Parent/ ) {
	if ( $f->has_tag($_) ) {
	    my ($id) = $f->get_tag_values($_);
	    my ($tag) = $id =~ /^(.+):/;
	    
	    if ( $tag && $f->has_tag($tag) ) {
		$f->remove_tag($tag);
	    }
	}
    }

    # AARRGGHH!! I have to find where duplicate 
    # qualifiers are coming from (somewhere in SeqIO::game)
    my %seen;
    for my $tag ( $f->all_tags ) {
        my @v = $f->get_tag_values($tag);
        $f->remove_tag($tag);
	for my $v ( @v ) {
	    next if ++$seen{$tag . $v} > 1;
	    $f->add_tag_value( $tag => $v );
	}
    }
}

sub _sname {
    my ($self, @feats) = @_;
    my $sn;
    for ( @feats ) {
        if ( $_->has_tag('standard_name') ) {
	    ($sn) = $_->get_tag_values('standard_name');
	    last;
	}
    }
    $sn;
}

sub validate_ID {
    my ($self, $sf, $acc) = @_;
    unless ( ($sf->has_tag('ID') || $sf->has_tag('Parent')) ) {
        $sf->add_tag_value( 'ID', "GFF_internal_id_$acc-" . ++$self->{idcount} );
    }
}


sub kill_list {
    my ($self, $gff, $segment) = @_;
    my $db = $self->database;
    my @killme;

    for ( split "\n", $gff ) {
	next if /\#/;
        push @killme,  _is_match($_, $segment);
    }
    @killme;
}


sub _is_match {
    my ($gff, $segment) = @_;
    chomp $gff;
    my @gff = split "\t", $gff;
    my @killme;
    my ($pclass,$pname,$iclass,$iname) = ('','','','');
    my ($src, $type, $start, $end, $grp) = @gff[1..4,8];
    my ($igrp) = grep { /ID=/ } split ';', $grp;
    my ($pgrp) = grep { /Parent=/ } split ';', $grp;
    $pgrp =~ s/^\S+=// if $pgrp;
    $igrp =~ s/^\S+=// if $igrp;
    ($pclass,$pname) = split ':', $pgrp if $pgrp;
    ($iclass,$iname) = split ':', $igrp if $igrp;
        
   
    return grep {
          ( ( $_->class eq $pclass || $_->class eq $iclass) && 
            ( $_->name  eq $pname  || $_->name  eq $iname ) ) ||
          ( $_->start == $start && $_->end == $end )
    } $segment->features( -types => ["$type:EMBL", "$type:GenBank", "$type:Apollo"] );
}


1;







