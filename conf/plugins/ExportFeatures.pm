# $Id: ExportFeatures.pm,v 1.9 2004-01-24 16:57:26 sheldon_mckay Exp $
=head1 NAME

Bio::Graphics::Browser::Plugin::ExportFeatures -- a plugin to export 
annotated sequence to Artemis

=head1 SYNOPSIS

This modules is not used directly

=head1 DESCRIPTION

This plugin dumps specially formatted EMBL annotations 
(an EMBL feature table) to a file or directly 
to the editor if the browser is configured to launch 
Artemis as a helper application for mime-type 'application/artemis'

Artemis will no longer support direct editing of GFF2 in its
next production release but EMBL feature tables can be edited directly.
After editing, the file can be reloaded into the database using the 
ImportFeatures plugin.

Similar functionality is available for dumping GAME-XML to Apollo.
In this case, all features will be dumped in order to facilitate
proper uflattening of containment hierarchies

=head1 NOTE 'Selected' vs. 'All' features

If 'Selected' is chosen in the popup menu, only the currently displayed
features (and any child features) will be dumped for editing.
'Selected' feature dumps are not available for GAME-XML


=head1 NOTE

The entire annotated sequence is dumped by this plugin, regardless 
of the segment's coordinate range.  This will be revised in a future version.


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

use vars '$VERSION','@ISA';
$VERSION = '0.01';

@ISA = qw / Bio::Graphics::Browser::Plugin Bio::Graphics::Browser::GFFhelper/;

sub name { 
    'Edit Features (Apollo/Artemis)' 
}

# don't use a verb in the plugin menu
sub verb {
    ' '
}

sub description {
  p("The Artemis dumper plugin dumps out the features in the current segment as an EMBL",
    " feature table suitable for editing in Artemis or GAME-XML for Apollo"),
  p("This plugin was written by Sheldon McKay.");
}

sub mime_type {
    my $conf = shift->configuration;
    if ( $conf->{method} eq 'browser' || param('demo_script') ) {
        return 'text/plain';
    }
    elsif ($conf->{destination} eq 'Artemis' ) {
        return 'application/artemis';
    }
    elsif ($conf->{destination} eq 'Apollo' ){
	return 'application/apollo';
    }
}

sub config_defaults {
    { method => 'browser',
      mode   => 'all',
      destination => 'Artemis'}
}

sub reconfigure {
    my $self = shift;
    my $conf = $self->configuration;
    $conf->{method} = $self->config_param('method');
    $conf->{mode}   = $self->config_param('mode');
    $conf->{destination}   = $self->config_param('destination');
}

sub configure_form {
    my $self = shift;
    my $conf = $self->configuration;
    my $html = 'Editor ' .
       radio_group (-name   => $self->config_name('destination'),
		    -values  => [ qw/Apollo Artemis/ ],
		    -default => $conf->{destination} ) . 
       br . br . 'Export ' .
       popup_menu(-name   => $self->config_name('mode'),
                  -values  => ['selected','all'],
                  -default => $conf->{mode},
                  -override => 1 ) . ' features' . br . br .
       'Destination: ' .
       radio_group( -name    => $self->config_name('method'),
		    -values  => ['*Editor', 'browser'],
		    -default => $conf->{method} ) .
       p("*To edit, install a helper application for MIME type " .
       cite('application/apollo') . " or " . cite('application/artemis'));
    my $url = $self->demo_script_url;
    $html .= p("To save your edited features back into gbrowse automatically, " .
               "you will need to use a " . a( {-href => $url, -target => '_new'},
               "helper script") . ".<br>Otherwise, upload your annotations via the " .
               "feature import plugin\n");

    $html;
}

sub dump {
    my ($self, $segment) = @_;

    # is this a request for the demo script?
    if ( param('demo_script') ) {
	print while (<DATA>);
	exit;
    }

    my $conf  = $self->configuration;
    my $mode  = $conf->{mode};
    my $db    = $self->database;
    my $ref   = $segment->ref;
    my $dest  = $conf->{destination};
    #$mode     = 'all' if $dest eq 'Apollo';
    
    my $whole_seg  = $db->segment(Accession => $ref) || $db->segment($ref);
 
    my $feats = join '', $self->selected_features;
    my (@feats, @ids);

    if ( $mode eq 'selected' ) {
        for my $f ( $segment->contained_features ) {
            my $type = $f->primary_tag;
	    if ($feats =~ /$type/) {
		push @feats, $f;
		$self->{seen}->{$f->id}++;
	    }
	}

	# get all gene parts if genes are selected
	if ( $feats =~ /gene|CDS|exon|RNA|transcript/ ) {
	    push @feats, grep {
		! $self->{seen}->{$_->id} &&
		$_->class =~ /gene|RNA/   
	    } $segment->contained_features;
	}

        # save the ids for database updating
        @ids = map { $_->id } @feats;
    }
    else {
	@feats = grep {
	    $_->start >= $segment->start - 1 &&
            $_->end   <= $segment->end + 1
        } $segment->features;
    }

    my $ft = $self->write_ft( $segment, $whole_seg, \@feats, @ids );

}

sub write_ft {
    my ($self, $segment, $whole_segment, $feats, @ids) = @_;
    my @feats = @$feats;
    my $dest    = $self->configuration->{destination};
    my $table   = '';

    # make a Seq object
    my $seq  = Bio::Seq::RichSeq->new( -id  => $segment->refseq,
				       -seq => $whole_segment->seq ); 
    $seq->accession($segment->refseq);

    # if we are in selected mode, we will need an id_holder;
    my $holder;
    if ( @ids ) {
        $holder = Bio::SeqFeature::Generic->new ( -primary => 'misc_feature',
						  -start   => $segment->start,
						  -end     => $segment->start + 1 );
	$holder->add_tag_value( note => "GFF database id container; do not delete" );
        $holder->add_tag_value( database_ids => join ',', @ids );
    }

    # convert the features to generic SeqFeatures
    for ( @feats ) {
	next if $_->primary_tag =~ /component/i;
	$_ = $self->gff2Generic($_);
	$self->strandfix($_);
        $self->tagfix($_);
    }

    push @feats, $holder if $holder;

    # flatten segmented features
    my @add = $self->flatten_segmented_feats(@feats);
    $seq->add_SeqFeature(@add);
    

    my $format = $dest eq 'Artemis' ? 'embl' : 'game';
    #$format = 'asciitree';
    my $out = Bio::SeqIO->new( -format => $format );
    $out->write_seq($seq);
}


sub flatten_segmented_feats {
    my ($self, @feats) = @_;
    my (@add, @parts, @rnas, %first);

    @parts = grep { $_->primary_tag =~ /exon|intron|UTR|poly|codon|CDS/ } @feats;
    @rnas  = grep { $_->primary_tag =~ /RNA|transcript/ } @feats;
    @add   = grep { 
	$_->primary_tag !~ /exon|intron|UTR|poly|codon|CDS|RNA|transcript/
    } @feats;

    # organize the features
    my %feats;
    for ( @parts ) {
	my ($class) = grep { /RNA|transcript/ } $_->all_tags;
	my ($name) = $_->get_tag_values($class);
        $feats{$name} ||= [];
	push @{$feats{$name}}, $_;
    }

    # flatten mRNAs and CDSs
    for my $name ( keys %feats ) {
	my $f = $feats{$name};
        my $num;
	for ( @$f ) {
	    $self->strandfix($_);

	    my ($class) = grep { /RNA|transcript/ } $_->all_tags;
            for my $rna ( @rnas ) {
		if ( $rna->has_tag( 'standard_name' ) ) {
		    my ($sn) = $rna->get_tag_values('standard_name');
		    if ( $sn eq $name ) {
			$self->{curr_RNA} = $rna;
			last;
		    }
		}
	    }

	    if ( ++$num == 1  ) {
		%first = ( CDS_locs => [], exon_locs => [] );
	    }
	    
	    if ( $_->primary_tag eq 'CDS' ) {
		$_->remove_tag($class);

		if ( !$first{CDS} ) {
		    $first{CDS} = $_;

		    # tie them to the gene	    
		    unless ( $_->has_tag('gene') ) {
                        my $gname = $name;
			$gname =~ s/_.+$//;
			$_->add_tag_value( gene => $gname );
		    }
		}
		
		push @{$first{CDS_locs}}, $_->location;
	    }
	    else {
		if ( !$first{RNA} ) {
		    my $rna = $self->{curr_RNA} || $_;
		    $_->primary_tag($class);  
		    $first{RNA} = $self->{curr_RNA} || $_;
		    
		    unless ( $_->has_tag('gene') ) {
			my $gname = $name;
                        $gname =~ s/_.+$//;
                        $_->add_tag_value( gene => $gname );
		    }	    
		}
		
		push @{$first{RNA_locs}}, $_->location;
	    }

	    $self->add_split_location( \%first, \@add, $class, $name ) if $num == @$f;
	}

    }

    # manipulate feature order
    @add = sort { $a->start <=> $b->start || $a->end <=> $b->end } @add;
    my @sources = grep { $_->primary_tag =~ /source|origin|region/ } @add;
    for (@add) { $_->primary_tag('source') if $_->primary_tag eq 'region' }

    my @genes   = grep { $_->has_tag('gene') } @add;
    my @others  = grep { 
	$_->primary_tag !~ /source|origin/ && !$_->has_tag('gene') 
    } @add;
    
    # genes come first
    my (%genes, @sorted_genes);
    my @mRNAs = grep { $_->primary_tag =~ /RNA|transcript/ } @genes;
    my @CDSs  = grep { $_->primary_tag eq 'CDS' } @genes;
    my @other = grep { $_->primary_tag !~ /RNA|transcript|CDS|gene/ } @genes;
    @genes = grep { $_->primary_tag eq 'gene' } @genes;    

    for ( @genes ) {
	my ($v) = $_->get_tag_values('gene');
	push @sorted_genes, $_;
	for my $part (@mRNAs, @CDSs, @other) {
            my ($g) = $part->get_tag_values('gene');
	    push @sorted_genes, $part if $g eq $v;
	}
    }
    

    return (@sources, @sorted_genes, @others);
}

sub strandfix {
    my ($self, $feat) = @_;
    my $start = $feat->start;
    my $end = $feat->end;
    if ($start > $end) {
	$feat->start($end);
	$feat->end($start);
	$feat->strand(-1);
    }
}

sub add_split_location {
    my ($self, $first, $add, $class, $name) = @_;
    return 0 unless $first and ref $first;

    my $cds = $self->_add_loc('CDS', $first);
    push @$add, $cds if $cds;
    
    my $rna = $self->_add_loc('RNA', $first);
    

    # unless there are UTRs, or the it has < 3 tags,
    # the mRNA is probably synthetic
    if ( $rna && $cds ) {
        push @$add, $rna if $rna->location && $cds->location &&
                            $rna->start < $cds->start || 
                            $rna->end > $cds->end ||
                            ($rna->all_tags && $rna->all_tags > 2);
    }
    # unless, of course, there is no CDS
    elsif ( $rna ) {
	push @$add, $rna;
    }
}

sub _add_loc {
    my ($self, $f, $first) = @_;
    return 0 unless $first->{$f};
    my $loc  = Bio::Location::Split->new;
    my @locs = sort { $a->start <=> $b->start } @{$first->{"${f}_locs"}};
    $loc->add_sub_Location( @locs );
    $first->{$f}->location( $loc );
    return $first->{$f};
}

# get rid of duplicate qualifiers and game-XML leftovers
# will have to deal with this properly but for now
# I want to avoid killing the EMBL parser
sub tagfix {
    my ($self, $f) = @_;
    my %seen;
    for my $t ( $f->all_tags ) {
        my @v = $f->get_tag_values($t);
	$f->remove_tag($t);
	for my $v( @v ) {
	    next if $seen{"$t:$v"} || $t eq 'product_desc';
            $f->add_tag_value( $t => $v );
            $seen{"$t:$v"} = 1;
	}
    }
}


sub demo_script_url {
    my $self = shift;
    my $url = self_url();
    $url =~ s/(\S+name=\S+?;).+/$1/;
    $url .= 'plugin=ExportFeatures;plugin_action=Go;demo_script=yes';
    $url;
}

1;

__DATA__
#!/usr/bin/perl -w

use strict;
use LWP::UserAgent;
use HTTP::Request::Common;

# This is an example of a client-side script to launch
# Apollo or Artemis, then update the server-side database.
# when the editing session is complete.
# In a *NIX OS, you should be able to use the script directly
# as a helper application (configured in your web browser preferences).
# In Windows, create a one-line batch file (with the .bat extension)
# with the text 'perl c:\annotations\myscript.pl %1' and use the batch
# file as a helper application.
# This will pass the name of the tempfile saved by your browser
# as a command-line argument to the script that will launch the
# editor, update the database, etc.


######################################################
#               USER DEFINED PARAMETERS              #
#     Edit your system specific info here            #
######################################################
# where is your gbrowse web site installed (optional)?
my $URL = 'http://mywebsite/cgi-bin/gbrowse/database';

# where do you want to save files?
my $SAVEDIR = 'c:\annotations';

# where is your editor?
# use single quotes or escape backslashes in windows
my $PROGRAM  = 'C:\Apollo\Apollo.exe';
#my $PROGRAM = 'C:\artemis\artemis_compiled_latest.jar';

# save file locally or update the web site?
#my $METHOD = 'local';
my $METHOD = 'remote';

######################################################


# filename must be passed as a command-line argument
my $file = shift || _die("Error: no input file");

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
    open OUTFILE, ">seqfile.$ext" or _die($!);
    print OUTFILE $text;
    close OUTFILE;
    print "Saving results to to seqfile.$ext\n\n";
    sleep 10 unless $not_good;
}

sub web_update {
    my $text = shift;

    print "\nUpdating website...\n";

    my $format = $PROGRAM =~ /artemis/ ? 'EMBL' : 'GAME';
    my @params = (   'plugin_action' => 'Go',
                     'plugin'        => 'ImportFeatures',
                     'ImportFeatures.format' => $format,
                     'ImportFeatures.debug'  => 'debug' );

    push @params, ('text' => $text);

    my $errmsg = "Automated web update failed.\nAnnotations "  .
                 "are saved in file seqfile.xml\nThere may be " .
                 "something wrong with the annotation file or parser.\n" .
                 "Try uploading the file to the website via\n" .
                 "the ImportFeatures plugin\n\n";

    my $ua = LWP::UserAgent->new ( timeout => 90, keep_alive => 1 );

    my $response = $ua->request( POST $URL, \@params );
    my $output = $response->content
      # Oh No! Something's wrong!
        or save_file($text,1) and _die($errmsg . $response->status_line);


    # just keep the text
    $output =~ s/<\/.+?>/\n/gm;
    $output =~ s/<.+?>//gm;

    print "Output from the wesite will be printed below.\n",
          "It will also be saved as output.txt\n",
	  "Remember to reload the page or hit 'Update Image' to see your changes\n\n";
    sleep 10;


    print $output;

    open OUT, ">output.txt";
    print OUT $output;
    close OUT;
    sleep 10;
}

sub _die {
    print "\n", @_, "\n\n";
    sleep 20;
    exit;
}
