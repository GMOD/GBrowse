# $Id: ImportFeatures.pm,v 1.15 2004-02-27 19:31:17 sheldon_mckay Exp $

=head1 NAME

ImportFeatures -- a plugin to import annotated sequences

=head1 SYNOPSIS

This modules is not used directly

=head1 DESCRIPTION

ImportFeatures.pm processes external features and loads them 
into the GFF database.  It will accept flat files in GenBank, 
EMBL, GFF2/3 or GAME-XML formats and can download accessions 
directly from NCBI/EBI.  

=head2 Loading new sequences

This plugin can be used to download accessions from GenBank 
or EMBL and load them into the GFF database.  Segmented features 
in the Genbank or EMBL file or accession (example mRNA or CDS) 
will be unflattened via Bio::SeqFeature::Tools::Unflattener and
loaded as containment hierarchies via GFF3.

=head2 Editing Features in an External Editor

This plugin can be used to load externally edited features, 
as long as the editor is capable of exporting GenBank, EMBL 
or GAME-XML. GFF2 is not recommended due to dialectic 
differences and lack of semantic constraint.
Support for Apollo GAME-XML is still experimental pending 
further testing/debugging of the Bio::SeqIO::game modules.  
Note that in-place creation, deletion and editing of features 
can also be done from gbrowse (using the BasicEditor plugin).

=head2  Using an External Editor

 1) use the ExportFeatures plugin to dump an EMBL 
    feature table or GAME-XML to a file (or directly 
    to the editor as a helper application 
    configured in the browser)

 2) edit your features 

 3) Save the changes to a file, then exit

 4) load the file via this plugin.  Steps 1-4 can be automated 
    with a perl wrapper using HTTP::Request::Common and
    LWP::UserAgent (see the helper script included in the
    Artemis/Apollo plugin)   

Make sure to enable direct editing in the Artemis configuration 
file 'options.txt'.  See the Artemis and Apollo documentation 
for more information on setup options.

=head2 Apollo

Apollo curently supports GAME-XML as its interchange format.
The round trip is still a bit tempermental but it is possible
to export gene and other features in GAME-XML and browse them,
do simple edit operation, then upload the changes via this
plugin.


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
the next load.  

NOTE: the exception to this is if the incoming feature file 
has features with the 'database_id' attribute.  In this case,
the file is treated as a selected feature file.  Only the 
features with the corresponding IDs in the database will be 
deleted. The database_id attributes are added automatically 
by ExportFeatures.pm if the dump mode is set to 'selected'


=head2 Partial Segments and relative coordinates
The segment offset wi;; be retrieved from a special
id_holder feature and used to remap the feature coordinates 
back to the absolute coordinates for the reference sequence.


=head2  Basic Feature Editing

For simple in-place feature editing, deletion, or addition, 
consider using the the BasicEditor plugin from within gbrowse

=head2 Rollbacks

This plugin can be used to roll back to an earlier state.  
If the rollback functionality is enabled, the state of the 
segment will be saved to a file before each database update.  
The last 10 pre-update states will be saved in a round-robin 
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
use CGI::Carp qw/fatalsToBrowser/;
use Bio::Graphics::Browser::Plugin;
use Bio::Graphics::Browser::GFFhelper;
use Bio::SeqFeature::Tools::Unflattener;

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
    'Annotations'
}

sub description {
  p("This plugin imports features and sequences to the GFF database."  .
    "GenBank/EMBL/GFF files or direct downloads from NCBI/EBI are supported."),
  p("This plugin was written by Sheldon McKay");
}

sub type {     
    'dumper'
}

# must preserve this verb so gbrowse knows how to handle this
# special class of dumper plugin
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
    ($conf->{format}) = $conf->{format} =~ /\((\S+)\)/
	if $conf->{format} =~ /\(/;
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

    my $msg = 'Usually not required unless the uploaded file is a headerless ' .
              'feature table from Artemis.  Use with caution, as you may end up ' .
	      'renaming your sequence';
    my $html = 
      table (
	     [
	      Tr( 
		  { -class => 'searchtitle' }, 
                  td( $f, 'Upload a file' )
		), 
              Tr( td( { -class => 'searchbody' },
	          p('Format: ',
	          radio_group( -name    => $self->config_name('format'),
			       -values  => [ qw/GFF GENBANK EMBL GAME/ ],
			       -default => $conf->{format} || $self->config_param('format'))),
		  p(
		     'Sequence ID: ', 
		     textfield( -name  => $self->config_name('seqid'),
				-size  => 10 ), ' ', _js_help($msg)
                    ),
	          p(
		     'Name of file to upload: ',
	             filefield( -name    =>  $self->config_name('file'),
				-size    => 40 )
                    )
		  )
	        )
	     ]
	   );

    $msg = "Use a GenBank/EMBL accession number (not GI)\\n" .
	      "Note: this will override file uploading";
	      
    $html .= 
             table([
		    Tr( { -class => 'searchtitle' }, 
                        td( $f, 'Direct Download from NCBI/EBI' ) 
                       ),
		    Tr( 
                        td( { class => 'searchbody' },
		            p( 'Accession ',
				textfield( -name    =>  $self->config_name('acc'),
					   -size    => '15'), ' ', _js_help($msg))
			  )
		       )
		    ]
		  );

    # add a rollback table if required
    if ( $ROLLBACK ) {
        $msg = "Selecting rollback will override loading of files or accessions";
        my $rb_form = br . "\n" . $self->rollback_form($msg);
        $rb_form =~ s/<h3>/<p>/igm;
	$rb_form =~ s/<\/h3>/<\/p>/igm;
        $html .= $rb_form;
    }
    
    $msg = "If the data being loaded affect an existing segment, select one of " .
	   "these options to specify how existing features should be handled:\\n" .
	   "colliding -- remove any features of the same type and coordinates as " .
	   "the incoming features.\\n\\nspecified --  if only selected features for a " .
	   "segment were exported to the external editor, the annotation file will " .
	   "contain the original feature ids, which will allow targeted deletion " .
	   "of the old features prior to loading.  If deleting features by id fails, " .
	   "colliding features will automatically be removed.\\n\\nall -- this option will ".
	   "wipe the affected coordinate range free of all contained features before loading";

    $msg = _js_help($msg);

    $html .= p(checkbox ( -name    => $self->config_name('debug'),
			   -value   => 'debug',
			   -label   => '' ), 'Verbose Reporting',
	     _js_help("Report on database loading progress;\\n" .
		      "provides debugging information")) .
	     p(checkbox ( -name    => $self->config_name('reload'),
			   -value   => 'reload',
			   -label   => '',
			   -checked => 1 ) . 'Reload browser after database update') .
             p("Method for deleting existing in-range features $msg " .
                '&nbsp;&nbsp;&nbsp;' .
		radio_group ( -name    => $self->config_name('erase'),
			      -values  => [ qw/colliding selected all/ ],
		              -default => $conf->{erase} )
	       );

    # ensure that the config page is loaded before the database update
    # can be performed
    $html .= hidden( -name    => $self->config_name('configured'),
                     -value   => 1 );
}

sub _js_help {
    my $msg = shift;
    a( { -href    => 'javascript:void(0)',
         -title   => 'help',
         -onclick => "alert('$msg')" }, "[?]" );
}



sub dump {
    my $self = shift;
    my $conf = $self->configuration;
    my $db   = $self->database;
    $self->{rb_loc} ||= $ROLLBACK;

    # go to config page if 'Dump' is clicked from the viewer
    unless ( $self->config_param('configured') ) {
	print h2( font( { -color => 'slateblue' },
		  'One moment; redirecting to configuration form...') );
	$self->load_page;
    }

    # look for a rollback request
    my $rollback = $self->config_param('rb_id');
    
    my $gff = $rollback ? $self->rollback($rollback) : $self->gff;

    
    if ( $conf->{seqid} ) {
	$self->refseq($conf->{seqid});
        my $newgff;
	for ( split "\n", $gff ) {
	    $newgff .= $_ . "\n" and next if /#/;
	    my ($id) = /^(\S+)/;
	    s/$id/$conf->{seqid}/g;
	    $newgff .= $_ . "\n";
	}
        $gff = $newgff;
    }

    # adjust to absolute coordinates if req'd
    $gff = $self->remap($gff);

    # adjust the sequence name and range
    $self->get_range($gff);

    # Oracle is case sensitive for attributes
    $gff =~ s/note=/Note=/gm if ref($db) =~ /Oracle/i;    

    if ( $conf->{debug} ) {
	print h2("Rolling back to previous state...", br )
          if $rollback;
	print h2("The input features:"), pre($gff);
    }
    
    my $segment  = $db->segment( $self->refseq )
                || $db->segment( Accession => $self->refseq );

    my $nodna = 0;
    
    if ( $segment ) {
	# make sure we know not to try to add sequence later
	$nodna++ if $segment->seq;

        # adjust segment coordinates to match GFF range
        $segment = $db->segment( -name => $self->refseq, -class => 'Accession',
				 -start => $self->start, -end  => $self->end )
	         || $db->segment( -name => $self->refseq,
				  -start => $self->start, -end  => $self->end );

				 
	$segment->start($self->start);
        $segment->end($self->end);

        # save the state of the segment in case we want to roll back later 
        if ( $ROLLBACK ) {
 	    $self->save_state($segment);
	}

	my @killme;
        if ( $conf->{erase} eq 'all' ) {
            # wipe the segment clean
            $self->_print("Removing all features from $segment");
	    @killme = grep { 
		$_->start >= $self->start &&
                $_->end   <= $self->end  
	    } $segment->features; 
	}
	elsif ( $conf->{erase} eq 'selected' && $self->{database_ids} ) {
            # remove features by database id
	    $self->_print("Attempting to remove selected features (by id) from $segment");
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
            $self->_print("Some of the database ids must have been stale; " . 
                          "I will remove colliding features ...");
	    @killme = $self->kill_list($gff, $segment);
	    $killed = $db->delete_features( @killme );
	}

	$killed ||= 'No';

	$self->_print("I removed $killed features from the database" . 
                      pre(join "\n", @killme) ); 

    }
    # new sequence will need to add a proper header
    else {
          
	my @gff = split "\n", $gff;
        my $skip;
        #check for a full-length source feature
        for ( @gff ) {
	    $skip++ if (split)[3] == $self->start 
		    && (split)[4] == $self->end 
                    && (split)[8] =~ /ID=(Sequence|Accession)/;
	}

	unless ( $skip ) {
	    shift @gff if $gff[0] =~ /^\#/;
	    unshift @gff, $self->gff_header;
	}
        
        print pre($gff);
	$gff = join "\n", @gff;
    }
	
    # don't try loading sequence if the sequence is already in
    # the database
    if ( $self->seq && !$nodna ) {
	$gff .= "\n>" . $self->refseq . "\n" . $self->seq;
    }

    # load the GFF into the database
    my $gff_fh  = IO::String->new($gff);
    my $result  = $db->load_gff($gff_fh) || 'No';
    my $remark = $result =~ /No/ ? br ."This can't be good..." : ''; 

    print h2("Success! $result features were loaded into the database.$remark");

    unless ( $result =~ /^\d+$/ ) {
	print h2("Features (below) not loaded correctly") . pre($gff);
        exit;
    }

    print h2("The Browser will re-load in 5 seconds...") if $conf->{reload};

    $self->load_page($gff);
}

# reload gbrowse or make a reload button
sub load_page {
    my ($self, $gff) = @_;
    my $url = self_url();

    # go to configure page if this is a caught misdirection
    unless ( $gff ) {
        $url =~ s/plugin_action=Go/plugin_action=Configure.../;
        print body( { -onLoad => "window.location='$url'" } );
        exit;
    }

    my $conf = $self->configuration;
    $self->get_range($gff);
    $url =~ s/\?.+$//g;
    my $name = $self->refseq. ':';
    $name .= $self->start . '..' . $self->end;
    print start_form( -name   => 'f1', 
		      -method => 'POST',
		      -action => $url );
    
    print qq(<input type=hidden name=name value="$name">);

    if ( $conf->{reload} ) {
	sleep 5;
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
    my $text;
    $self->{header} = 1;

    if ( $conf->{acc} ) {
        $self->refseq($conf->{acc});
	return $self->get_embl($conf->{acc});
    }    

    unless ( $file ) {
        # we don't the text ending up as a cookie,
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
    my $display_text = $text;
    $display_text =~ s/\</&lt;/gm;
    $display_text =~ s/\>/&gt;/gm;
    $self->{display_text} = $display_text;

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
	$self->bad_format("Unrecognized format $format:", $display_text);
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
    $self->{source} = 'GAME';
    
    $self->bad_format("I don't think this is GAME-XML", $self->{display_text}) 
	unless $text =~ /<game/m;

    my $in = eval{
      Bio::SeqIO->new( -fh => IO::String->new($text), -format => 'game')
    } || $self->parsefail( 'Parsing error: ', @! );

    my $seqobj    = $in->next_seq || $self->parsefail($in->error);

    $seqobj || $self->bad_format("Problem reading GenBank:", $text);

    return $self->seq2GFF($seqobj);
}

sub read_genbank {
    my ($self, $text) = @_;
    my $conf  = $self->configuration;
    my $seqid = $conf->{seqid};
    $self->{source} = 'GenBank';    
    
    $self->bad_format("This does not look like GenBank to me:", $self->{display_text})
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

    my $in = eval {
	Bio::SeqIO->new( -fh => IO::String->new($text), -format => 'genbank')
    }  || $self->parsefail( 'Parse error: ', @!);

    my $seqobj    = $in->next_seq || $self->parsefail($in->error);
    
    $seqobj || $self->bad_format("Problem reading GenBank:", $self->{display_text}); 
    
    return $self->seq2GFF($seqobj);
}

sub read_embl {
    my ($self, $text) = @_;
    my $conf  = $self->configuration;
    my $seqid = $conf->{seqid};
    $self->{source} = 'GenBank';

    $self->bad_format("This does not look like EMBL to me:", $self->{display_text})
        if $text !~/^FT\s+\S+/m;

    unless ( $text =~ /^ID/ ) {
        unless ( $seqid ) {
            print h1('Error: No sequence ID<br>A sequence ID is required if ' .
                     'the EMBL record has no header');
            exit;
        }
        $text = "ID   $seqid\nFH   Key             Location/Qualifiers\n" . $text;
	$conf->{file} = '';
    }
    elsif ( $text =~ /^ID\s+(\S+)/ ) {
	$self->refseq($1);
    }

    # Artemis is not wrapping qualifier values in quotes if they are 'illegal'
    # We have to intercept these and quote them or the parser will choke
    _fix_qualifiers(\$text);

    my $in = eval {
	Bio::SeqIO->new( -fh => IO::String->new($text), -format => 'embl')
    } || $self->parsefail( 'Parse error; ', @!);

    my $seqobj    = $in->next_seq || $self->parsefail($in->error);

    $seqobj || $self->bad_format("Problem reading EMBL:", $self->{display_text});

    return $self->seq2GFF($seqobj);
}

sub seq2GFF {
    my ($self, $seq) = @_;
    my $conf = $self->configuration;
    my $gff  = "##gff-version 3\n";
    my $unflattener = Bio::SeqFeature::Tools::Unflattener->new;
    $self->{idcount} = 0;
    my $acc;
    if ( $seq->accession && $seq->accession !~ /unknown/ ) {
	$acc = $seq->accession;
    }
    else {
	$acc = $conf->{seqid} || $seq->display_name;
    }

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

    for my $f ( $seq->remove_SeqFeatures ) {
	my $id_holder = $f 
	    if $f->primary_tag eq 'misc_feature' 
	    && $f->has_tag('database_ids');
	
        # was this derived from a partial segment dump?
	if ( $id_holder ) {
	    my ($ids) = $id_holder->get_tag_values('database_ids');
	    $self->{database_ids} = [ split ',', $ids ];
	
	    ($self->{offset}) = $id_holder->get_tag_values('segment_offset')
		if $id_holder->has_tag('segment_offset');
             
            $self->{unflattened} = 1 if $id_holder->has_tag('unflattened');   

	}
	else {
	    $seq->add_SeqFeature($f);
	}
    }
    
    # get top level unflattended SeqFeatureI objects
    my $text = $self->{display_text} || '';
    my @sfs;

    unless ( $self->{unflattened} ) {
	@sfs = eval {
	    $unflattener->unflatten_seq( -seq => $seq, -use_magic => 1)
	} or $self->_print("Error: The features did not unflatten properly\n"
			   . "Please check your annotation file \n\n", $text) and exit;
    }
    # but only if they are flat
    else {
	@sfs = $seq->all_SeqFeatures;
    }

    my $gene_count;

    for my $sf (@sfs) {
        $sf->seq_id($acc);
        $sf->source_tag($self->{source});
        $sf->gff_format( Bio::Tools::GFF->new( -gff_version => 3 ) );

        if ( $sf->primary_tag eq 'source' && !$sf->has_tag('ID') ) {
	    $sf->add_tag_value( 'ID', "Sequence:$acc" );
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
        }

        if ( $sf->primary_tag =~ /[^m]rna/i ) {
            $sf->primary_tag('RNA');
        }

	if ( $sf->primary_tag eq 'gene' ) {
            my ($gene_name) = $sf->has_tag('gene') 
                  ? $sf->get_tag_values('gene')
                  : $sf->get_tag_values('locus_tag');
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

        my $localgeneid = 0;
	my %seen_id;

        my ($id) = $sf->get_tag_values('ID');
        (my $fname = $id) =~ s/^\S+?://;

        foreach my $sf2 ( $sf->get_SeqFeatures ) {
            $sf2->seq_id( $acc );
            $sf2->gff_format( Bio::Tools::GFF->new( -gff_version => 3 ) );

            # have to find a way to give the mRNA an ID and a link to
            # the parent gene
            if ( $sf2->primary_tag =~/RNA/ ) {
                my $sf_id;
		$sf2->add_tag_value( 'gene', $fname ) unless $sf2->has_tag('gene');
                
                # use the standard_name if one exists
		if ( my $sn = _sname($sf2) ) {
		    $sf_id = $sf2->primary_tag . ':' . $sn;
		}
		else {
		    $sf_id  = $sf2->primary_tag .':'. $fname;
		    $sf_id .= '_' . ++$localgeneid 
			if (grep { $_->primary_tag eq 'mRNA' } $sf->get_SeqFeatures) > 1;
		}		
		$sf2->add_tag_value( 'ID', $sf_id );
	    } 
            elsif ( !$sf2->has_tag('Parent') ) {
                if ( $sf->has_tag('Name') ) {
		    $sf2->add_tag_value( 'Name', $sf->get_tag_values('Name') );
		}
		$sf2->add_tag_value( 'Parent', $id );
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
            }

            $sf2->source_tag( $self->{source} );
            my @subfeats = $sf2->get_SeqFeatures;

	    $self->validate_tag($sf2);
	    $self->validate_ID($sf2, $acc);
            $self->clean_up_tags($sf2);

            $gff .= $sf2->gff_string . "\n";

            my %seen_CDS;

	    foreach my $sf3 ( @subfeats ) {
		$sf3->seq_id($acc);
                $sf3->gff_format( Bio::Tools::GFF->new( -gff_version => 3 ) );
		my ($parentID) = $sf2->get_tag_values('ID');

		# Shared exons in alternative splice variants point to
                # the same Bio::SeqFeature object.  We have to clone.
                $sf3 = _Dolly($sf3) if $sf3->has_tag('Parent');
		for ( qw/ mRNA Parent / ) {
		    $sf3->remove_tag($_) if $sf3->has_tag($_);
		}
		$sf3->add_tag_value( 'Parent', $parentID );
                $sf3->source_tag( $self->{source} );
		$self->validate_tag($sf3);
		next unless $self->validate_ID($sf3, $acc);

                # only the first GFF line for the CDS needs all the tags
		if ( $sf3->primary_tag eq 'CDS' ) {
		    my @gff = split "\n", $sf3->gff_string;
		    $gff .= (shift @gff) . "\n";
		    for ( @gff ) {
			$gff .= (join "\t", (split)[0..7]) . 
                                "\tParent=$parentID\n";
		    }
		}
		else {
		    $gff .= $sf3->gff_string . "\n";
		}
            }
        }
    }

    $self->seq($seq->seq);
    $self->start(1);
    $self->end(length $seq->seq);

    $gff =~ s/\"//gm;
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


# if the class is part of the 'ID', 
# remove any redundant attribute
sub clean_up_tags {
    my ($self, $f) = @_;
    if ( $f->has_tag('ID') ) {
	my ($id) = $f->get_tag_values('ID');
	my ($tag) = $id =~ /^(.+?):/;
	
	if ( $tag && $f->has_tag($tag) ) {
	    $f->remove_tag($tag);
	}
    }
}

sub _sname {
    my $feat = shift;
    my ($match) = grep { $_->primary_tag eq 'CDS' } $feat->get_SeqFeatures;
    $match ||= $feat;
    my ($sn) = $match->get_tag_values('standard_name')
        if $match->has_tag('standard_name');
    $sn;
}

sub validate_ID {
    my ($self, $sf, $acc) = @_;
    unless ( $sf->has_tag('ID') || $sf->has_tag('Parent') ) {
        my $sn = _sname($sf);
	if ( $sf->has_tag('mRNA') ) {
            ($sn) = $sf->get_tag_values('mRNA') unless $sn;
	    $sn     = 'mRNA:' . $sn;
	    $sf->add_tag_value('ID', $sn);
	}
	elsif( $sf->has_tag('gene') ) {
            ($sn) = $sf->get_tag_values('gene') unless $sn;
            $sn = 'gene:' . $sn;
            $sf->add_tag_value('ID', $sn);
	}
	else {
	    my @tags;
	    if ( @tags = $sf->get_all_tags ) {
		for ( @tags ) {
		    my @v =$sf->get_tag_values($_);
		    $sf->add_tag_value('ID' => "$_\:$v[0]" );
		}	    
	    }
	    else {
		$sf->add_tag_value( 'ID', "GFF_internal_id_$acc-" . ++$self->{idcount} );
	    }
	}    
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

# remap features to absolute coordinates
sub remap {
    my ($self, $gff) = @_;
    return $gff unless $self->{offset};

    my $remapped;
    for my $line ( split "\n", $gff ) {
        if ( $line !~ /\S+\t\S+\t\S+/ || $line =~ /^>|^\#/ ) {
	    $remapped .= $line . "\n";
	    next;
	}
        
        my @line = split "\t", $line;
	$line[3] += $self->{offset};
	$line[4] += $self->{offset};
	$remapped .= (join "\t", @line) . "\n" if @line;
    }
    $remapped;
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
    } $segment->features( -types => [ $type ] );
}

# fix unquoted multiline qualifier values created by Artemis
sub _fix_qualifiers {
    my $text = shift;
    my @vals = split /FT.+?\/.+?=/, $$text;
    shift @vals;
    for ( @vals ) {
	s/FT\s{3}\S+.+//gsm;
        chomp;
	next if /\"/ || !/\s+|\n/;
	my $newval = qq("$_");
	$$text =~ s/$_/$newval/gm;
    }    
}

# shallow clone the feature but give it ownership
# of the copied tags
sub _Dolly {
    my $obj = shift;
    my %new =  %{$obj};
    my %tags = %{$obj->{_gsf_tag_hash}};
    $new{_gsf_tag_hash} = \%tags;
    return bless \%new, ref($obj);
}


1;







