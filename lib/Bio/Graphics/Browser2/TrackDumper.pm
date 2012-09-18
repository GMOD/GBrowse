package Bio::Graphics::Browser2::TrackDumper;

###################################################################
#
# This package holds the majority of code from the gbgff script.
# It is used to output GFF3 to allow for track sharing.
#
###################################################################

# $Id$

# Simple track dumper, suitable for a lightweight replacement to DAS.
# Call this way:
#    http://my.host/cgi-bin/gb2/gbrowse/volvox?gbgff=1;q=ctgA:1..2000;l=Genes%5EExampleFeatures
#
# From within the "Add Remote Annotations" section, you can say:
#     http://my.host/cgi-bin/gb2/gbrowse/volvox?gbgff=1;q=$segment;l=Genes%5EExampleFeatures
#
# Note that the track name delimiter has changed to %5E, and the option is "l".
# The old method of separating with + signs had to abandoned because of spaces in the
# track label names.
#
# To share uploads, do this:
#     http://my.host/cgi-bin/gb2/gbrowse/volvox?gbgff=1;q=ctgA:1..2000;\
#           l=Genes%5EExampleFeatures%5Efile:my_upload.txt;id=session_id

use strict;

use CGI 'param', 'path_info', 'header';
use Bio::Graphics::Browser2;
use Bio::Graphics::FeatureFile;
use Bio::Graphics::Browser2::RegionSearch;
use Bio::Graphics::Browser2::Shellwords;
use Bio::Graphics::Browser2::Util 'modperl_request';
use Bio::Graphics::Browser2::TrackDumper::RichSeqMaker;
use Bio::SeqIO;

sub new {
    my $class   = shift;
    my %options = @_;
    my $self    = bless {
        data_source => $options{-data_source},
        stylesheet  => $options{-stylesheet},
        'dump'      => $options{'-dump'},  # in quotes because "dump" is a perl keyword
        labels      => $options{-labels},
	mimetype    => $options{-mimetype},
	format      => $options{-format},
	requested_segment     => $options{-segment},
        },
        ref $class || $class;

    $self->check_source()                  or return;
    $self->get_segment($options{-segment}) or return
	if $options{-segment};

    return $self;
}

sub forced_format { shift->{format} }

sub add_prefix {
    my $self = shift;
    return $self->{'.prefix'} if exists $self->{'.prefix'};
    my $datasource = $self->data_source;
    return $self->{'.prefix'} = $datasource->seqid_prefix;
}

sub print_stylesheet {
    my $self = shift;
    my ($segment,$labels) = @_;

    $segment||= $self->get_segment;
    $labels ||= $self->get_labels;
    my $types  = $labels ? $self->labels_to_types($labels,eval{$segment->length}) : undef;
    my $files  = $labels ? $self->labels_to_files($labels,eval{$segment->length}) : undef;

    $self->print_configuration( $self->data_source(), $labels );
    $self->print_configuration( $_, [ $_->labels ] ) for @$files;
}

sub dump_track {
    my $self   = shift;
    my ($label,$segment)  = @_;

    my $source = $self->data_source;
    my $key    = $source->setting($label=>'key');
    my $db     = $source->open_database($label);
    my @types  = shellwords($source->setting($label=>'feature'));

    my $dump_method = $self->guess_dump_method($db,$label);
    local $SIG{PIPE} = sub {die 'aborted track dump due to sigPIPE'};
    $self->$dump_method($db,$segment,\@types,$label);
}

sub dump_gff3_autowig {
    shift->_dump_gff3(@_,1);
}

sub dump_gff3 {
    shift->_dump_gff3(@_);
}

sub dump_vista_peaks {
    shift->_dump_gff3(@_,1,1);  # magic number==1 means print peaks only
}

sub dump_vista_wiggle {
    shift->_dump_gff3(@_,1,2);  # magic number==2 means print signal data only
}

sub dump_vista {
    shift->_dump_gff3(@_,1,3); # magic number==3 means print peaks + signal data
}

sub dump_fasta {
    my $self = shift;
    my ($db,$segment,$types,$label) = @_;
    my $out = new Bio::SeqIO(-format=>'fasta',-fh=>\*STDOUT);
    for my $seg ($self->get_segs($db,$segment)) {
	my $seq = $seg->seq;
	$out->write_seq($seq);
    }
}

sub dump_genbank {
    my $self = shift;
    my ($db,$segment,$types,$label) = @_;
    my $out = new Bio::SeqIO(-format=>'genbank',-fh=>\*STDOUT);
    for my $seg ($self->get_segs($db,$segment)) {
	my $seq = $self->get_rich_seq($db,$seg,$types);
	$out->write_seq($seq);
    }
}

sub get_segs {
    my $self = shift;
    my ($db,$segment) = @_;
    return $segment if $segment;
    my @segs = eval {
	map {$db->segment($_)} $db->seq_ids;
    };
    return @segs if @segs;
    my $default = $self->data_source->open_database(); # try default
    return eval {
	map {$default->segment($_)} $default->seq_ids;
    };
}

sub get_rich_seq {
    my $self = shift;
    my ($db,$segment,$types) = @_;
    my @args = $segment ? (-seq_id=> $segment->seq_id,
			   -start => $segment->start,
			   -end   => $segment->end)
	                : ();

    my $iterator = $db->get_seq_stream(@args,-type=>$types);
    return Bio::Graphics::Browser2::TrackDumper::RichSeqMaker->stream_to_rich_seq($segment,$iterator);
}

sub _dump_gff3 {
    my $self = shift;
    my ($db,$segment,$types,$label,$autowig,$vista) = @_;

    my @args = $segment ? (-seq_id=> $segment->seq_id,
			   -start => $segment->start,
			   -end   => $segment->end)
	                : ();

    my $iterator = $db->get_seq_stream(@args,-type=>$types);

    # The logic here is as follows:
    # 1) if the features contain the 'wigfile' attribute, then we
    #    defer printing to the end and produce a facsimile of 
    #    a UCSC wigfile upload (using bedgraph format).
    # 2) otherwise we print out a valid gff3 file
    my ($gff3_header,$bed_header,%peaks,%wigs,%bigwigs);
    while (my $f = $iterator->next_seq) {
	if (($autowig || $vista) && (my ($wig) = $f->get_tag_values('wigfile'))) {
	    my ($start,$end) = ($f->start,$f->end);
	    $start           = $segment->start if $segment && $start < $segment->start;
	    $end             = $segment->end   if $segment && $end   > $segment->end;
	    if (my $base = $self->data_source->setting($label=>'basedir')) {
		$wig = File::Spec->rel2abs($wig,$base);
	    }
	    my $w = $wig =~ /\.bw$/ ? \%bigwigs : \%wigs;
	    my $trackname = $f->display_name || $f->type;
	    $trackname    .= " (Signal)" if $vista;
	    $w->{$trackname}{$f->seq_id}{$wig} = [$start,$end];
	} else {
	    $self->print_gff3_header($segment) unless $gff3_header++;
	    $self->print_feature($f);
	}
	if ($vista && (my ($peaks) = $f->get_tag_values('peak_type'))) {
	    $peaks{$f->display_name || $f->type}{$peaks} = [$segment->seq_id,$segment->start,$segment->end];
	}
    }

    $vista ||= 3;
    $self->print_peaks($db,\%peaks,$label)        if %peaks   && $vista==1 or $vista == 3;
    $self->print_bio_graphics_wigs(\%wigs,$label) if %wigs    && $vista==2 or $vista == 3;
    $self->print_bigwigs(\%bigwigs,$label)        if %bigwigs && $vista==2 or $vista == 3;
}

sub dump_sam {
    my $self = shift;
    my ($db,$segment,$types,$label) = @_;

    my @args = $segment ? (-seq_id => $segment->seq_id,
			   -start  => $segment->start,
			   -end    => $segment->end)
	                : ();

    my $key       = $self->data_source->setting($label=>'key');
    $key        ||= $label;

    my $header = $db->header;

    my $prefix = $self->add_prefix;

    print $header->text;
    print "\@CO\t$key\n";
    print "\@CO\tGenerated by GBrowse from ",$self->origin($label),"\n";
    if ($segment) {
	my $seq_id  = $segment->seq_id;
	$seq_id     = "$prefix$seq_id" if $prefix;
	print "\@CO\tSequence-region ",$seq_id,':',$segment->start,'..',$segment->end,"\n" if $segment;
    }

    # there are problems with the filehandle-based conversion of 
    # BAM to TAM because the low-level functions write to STDOUT directly
    # which are munged in modperl and fastcgi environments.

    # in the case of modperl, we revert to doing the conversion at the perl level
    # which may be slower
    if (modperl_request()) {
	if (Bio::DB::Bam::AlignWrapper->can('tam_line')) {
	    my $iterator = $db->features(@args,-iterator=>1);
	    while ($_ = $iterator->next_seq) {
		my $tam_line = $_->tam_line;
		$tam_line =~ s/^([^\t]+)\t([^\t}+)\t([^\t+])/$1\t$2\t$prefix$3/ if $prefix;
		print $tam_line,"\n";
	    }
	} else {
	    print "## Bio::DB::SamTools 1.19 or higher required for printing SAM data when running under mod_perl\n";
	}
	return;
    }


    # With FastCGI, we can handle this by piping the result to ourselves.
    if (Bio::Graphics::Browser2::Render->fcgi_request()) {
	eval "use IO::Pipe" unless IO::Pipe->can('new');
	my $pipe = IO::Pipe->new;
	my $child = Bio::Graphics::Browser2::Render->fork();
	if ($child) {
	    $pipe->reader();
	    while (<$pipe>) {
		s/^([^\t]+)\t([^\t]+)\t([^\t]+)/$1\t$2\t$prefix$3/ if $prefix;
		print $_;
	    }
	} else {
	    $pipe->writer();
	    my $fh = $db->features(@args,-fh  => 1);
	    while (<$fh>) {
		print $pipe $_ ;
	    }
	    exit 0;
	}
	return;
    }

    # CGI scripts simply do it directly.
    my $fh = $db->features(@args,-fh  => 1);
	while (<$fh>) {
		s/^([^\t]+)\t([^\t]+)\t([^\t]+)/$1\t$2\t$prefix$3/ if $prefix;
	    print $_;
	}
}

sub dump_bigwig {
    my $self = shift;
    my ($db,$segment,$types,$label) = @_;
    my @types     = shellwords($self->data_source->setting($label=>'feature'));
    my $key       = $self->data_source->setting($label=>'key');
    $key        ||= $label;

    my @location_args = $segment ? (-seq_id => $segment->seq_id,
				    -start  => $segment->start,
				    -end    => $segment->end)
	                         : ();

    my @type_args     = @types   ? (-type => \@types) 
                                 : ();

    my $iterator = $db->get_seq_stream(@location_args,@type_args);

    my $origin = $self->origin($label);

    my $last_type = '';
    my $last_name = '';

    while (my $f = $iterator->next_seq) {
	my $type = $f->type;
	my $name = $f->display_name;

	if ($type ne $last_type or $name ne $last_name) {
	    print "\n" if $last_type or $last_name;
	    $name ||= $type;
	    print qq(track type=bedGraph name="$key ($name)" description="Generated by GBrowse from $origin"\n);
	    $last_type = $type;
	}

	if ($f->can('get_seq_stream')) {  # a summary type; need to do recursive iteration
	    my $i = $f->get_seq_stream(@location_args);
	    while (my $g = $i->next_seq) { $self->print_bed_score($g) }
	}
	else {
	    $self->print_bed_score($f);
	}
    }
}

sub print_peaks {
    my $self           = shift;
    my ($db,$peaks,$label) = @_;
    for my $trackname (keys %$peaks) {
	$self->print_bed_header("$trackname (Peaks)");
	for my $type (keys %{$peaks->{$trackname}}) {
	    my ($seqid,$start,$end) = @{$peaks->{$trackname}{$type}};
	    my $iterator            = $db->get_seq_stream(-seq_id=> $seqid,
							  -start => $start,
							  -end   => $end,
							  -type  => $type,
							  );
	    while (my $f = $iterator->next_seq) {
		$self->print_bed_score($f);
	    }
	    
	}
	print "\n";
    }
}

sub print_bed_header {
    my $self = shift;
    my $label = shift;
    print "track name=\"$label\"\n";
}

sub print_bed_score {
    my $self = shift;
    my $f    = shift;
    my $score = defined $f->score ? sprintf("%.4f",$f->score) : '';
    $score =~ s/\.?0+$//;
    my $seq_id = $f->seq_id;
    if (my $prefix = $self->add_prefix) {
	$seq_id    = "$prefix$seq_id";
    }
	
    print join ("\t",$seq_id,$f->start,$f->end,$score),"\n";
}

sub available_formats {
    my $class  = shift;
    my ($source,$label) = @_;
    my $db  = $source->open_database($label);
    my $glyph = $source->code_setting($label => 'glyph');

    my @formats = qw(fasta);
    push @formats,qw(gff3 genbank) unless $db->isa('Bio::DB::Bam') 
	                               or $db->isa('Bio::DB::Sam')
				       or $db->isa('Bio::DB::BigWig')
                                       or $glyph =~ /wiggle|xyplot|density/;
    push @formats,'vista','vista_wiggle','vista_peaks' if  $glyph =~ /vista/i;
    push @formats,'sam'   if  $db->isa('Bio::DB::Bam')    or $db->isa('Bio::DB::Sam');
    push @formats,'bed'   if  $db->isa('Bio::DB::BigWig') or $db->isa('Bio::DB::BigWigSet');
    push @formats,'bed'   if  $glyph =~ /wiggle|xyplot|density/;
    my %seenit;
    return grep {!$seenit{$_}++} @formats;
}

sub guess_dump_method {
    my $self = shift;
    my $db   = shift;
    my $label= shift;

    return 'dump_gff3'    if $self->forced_format eq 'gff3';
    return 'dump_fasta'   if $self->forced_format eq 'fasta';
    return 'dump_genbank' if $self->forced_format eq 'genbank';
    return 'dump_sam'     if $self->forced_format eq 'sam';
    return 'dump_bigwig'  if $self->forced_format eq 'bed';
    return 'dump_vista'        if $self->forced_format eq 'vista';
    return 'dump_vista_wiggle' if $self->forced_format eq 'vista_wiggle';
    return 'dump_vista_peaks'  if $self->forced_format eq 'vista_peaks';

    return 'dump_vista'   if $self->data_source->code_setting($label => 'glyph') =~ /vista/i;
    return 'dump_gff3_autowig'   if $db->isa('Bio::DB::SeqFeature::Store');
    return 'dump_gff3_autowig'   if $db->isa('Bio::DB::GFF');
    return 'dump_gff3_autowig'   if $db->isa('Bio::DB::Das::Chado');
    return 'dump_gff3_autowig'   if $db->isa('Bio::DB::DasI');

    my $type = $self->guess_file_type();
    return 'dump_sam'    if $type eq 'sam';
    return 'dump_bigwig' if $type eq 'bed';
    return 'dump_gff3_autowig'
}

sub print_gff3_header {
    my $self = shift;
    my $segment = shift;

    my $date = localtime;
    print "##gff-version 3\n";
    print "##date $date\n";
    print "##source gbrowse gbgff gff3 dumper\n";
    if ($segment) {
	my $prefix = $self->add_prefix;
	my $seq_id  = $segment->seq_id;
	$seq_id     = "$prefix$seq_id" if $prefix;
	print "##sequence-region ",$seq_id,':',$segment->start,'..',$segment->end,"\n";
    }
}

sub origin {
    my $self  = shift;
    my $label = shift;

    my $source  = $self->data_source;
    my $origin  = CGI::url(-full=>1);
    $origin    .= "/".$source->name;
    $origin    .= "?l=".CGI::escape($label) if $label;
    return $origin;
}

sub print_bio_graphics_wigs {
    my $self = shift;
    my ($wigs,$label) = @_;

    my $source  = $self->data_source;

    # may need the relative pathname to get the wigs (sometimes)
    my $basedir = $source->code_setting($label=>'basedir');
    $basedir    = $basedir->() if $basedir && ref($basedir) eq 'CODE'; # a bit awkward here

    eval "use Bio::Graphics::Wiggle"
	unless Bio::Graphics::Wiggle->can('new');

    for my $track_name (keys %$wigs) {
	my $origin  = $self->origin($label);
	print qq(track type=bedGraph name="$track_name" description="Generated by GBrowse from $origin; precision limited to 255 levels"\n);
	for my $seqid (keys %{$wigs->{$track_name}}) {
	    for my $wigfile (keys %{$wigs->{$track_name}{$seqid}}) {
		my ($start,$end) = @{$wigs->{$track_name}{$seqid}{$wigfile}};
		my $path = File::Spec->rel2abs($wigfile,$basedir);
		my $wig = Bio::Graphics::Wiggle->new($path) or next;
		$wig->export_to_bedgraph($start,$end,\*STDOUT);
	    }
	}
	print "\n";
    }
}

sub print_bigwigs {
    my $self = shift;
    my ($wigs,$label) = @_;
    my $source  = $self->data_source;

    # may need the relative pathname to get the wigs (sometimes)
    my $basedir = $source->code_setting($label=>'basedir');
    $basedir    = $basedir->() if $basedir && ref($basedir) eq 'CODE'; # a bit awkward here

    eval "use Bio::DB::BigWig"
	unless Bio::DB::BigWig->can('new');

    for my $track_name (keys %$wigs) {
	for my $seqid (keys %{$wigs->{$track_name}}) {
	    for my $wigfile (keys %{$wigs->{$track_name}{$seqid}}) {
		my ($start,$end) = @{$wigs->{$track_name}{$seqid}{$wigfile}};
		my $path = File::Spec->rel2abs($wigfile,$basedir);
		my $wig  = Bio::DB::BigWig->new($path) or next;
		my $segment = Bio::Graphics::Feature->new(-seq_id=>$seqid,-start=>$start,-end=>$end);
		$self->dump_bigwig($wig,$segment,[],$track_name);
		print "\n";
	    }
	}
    }
}

sub print_datafile {
    my $self = shift;

    my $labels = $self->get_labels;
    my $segment= $self->get_segment;

    $self->print_stylesheet($segment,$labels) 
	if $self->get_do_stylesheet;

    if (@$labels == 1) {
	$self->dump_track($labels->[0],$segment);
	return;
    }

    # We don't handle heterogeneous downloads (multiple tracks with different database backends)
    # well, so we default to a uniform GFF3 dump. In the future, this should be replaced with
    # TAR file generation.
    my $types  = $labels ? $self->labels_to_types($labels,eval{$segment->length}) : undef;
    my $files  = $labels ? $self->labels_to_files($labels,eval{$segment->length}) : undef;

    my %filters
        = map { $_ => $self->data_source->setting( $_ => 'filter' ) || undef }
        @$labels;

    $self->print_gff3_header($segment);
    $self->print_gff3_data($_, $types, \%filters ) for $self->db;
    $self->print_gff3_data($_) for @$files;
}

sub print_fasta {
    my $self    = shift;
    my $segment = $self->get_segment;
    my $seq     = $segment->seq;
    eval "require Bio::SeqIO" unless Bio::SeqIO->can('new');
    my $out     = Bio::SeqIO->new(-format => 'Fasta');
    $out->write_seq($seq);
}

sub data_source { shift->{data_source} }

sub db     { 
    my $self = shift;
    return @{$self->{db}} if $self->{db};

    my $source = $self->data_source;
    my $tracks = $self->get_labels;
    $tracks    = $self->all_databases unless $tracks;

    my %seenit;
    my @dbs  = grep {defined($_) && !$seenit{$_}++} 
                     map {$source->open_database($_)} ('general',@$tracks);
    $self->{db} = \@dbs;
    return @dbs;
}

sub segment {
    my $self = shift;
    my $d    = $self->{segment};
    $self->{segment} = shift if @_;
    $d;
}

sub check_source {
    my $self        = shift;
    my $data_source = $self->{data_source};
    my $source_name = $data_source->name();

    $source_name =~ s!^/+!!;    # get rid of leading / from path_info()
    $source_name =~ s!/+$!!;    # get rid of trailing / from path_info() !

    if ($source_name) {
        unless ( $data_source->globals->valid_source($source_name) ) {
            print header('text/plain'), "# Invalid source $source_name; "
                . "you may not have permission to access this data source.\n";
	    return;
        }
    }

    return 1;
}

sub get_segment {
    my $self    = shift;
    return $self->{segment} unless @_;

    my $segment = shift;

    # check whether someone called us directly by pasting into location box
    if ($segment =~ /^\$segment/) { 
        print header('text/plain');
	print "# To share this track, please paste its URL into the \"Enter Remote Annotation\" box\n",
	"# at the bottom of a GBrowse window and not directly into your browser's Location area.\n";
	return;
    }

    my ( $seqid, $start, $end )
        = $segment =~ /^([^:]+)(?::([\d-]+)(?:\.\.|,)([\d-]+))?/;

    unless ( defined $seqid ) {
        print header('text/plain');
	print "# Please provide the segment argument.\n";
	return;
    }

    my $datasource = $self->data_source;
    my $tracks     = $self->get_labels;
    $tracks        = $self->all_databases unless $tracks;

    my $search = Bio::Graphics::Browser2::RegionSearch->new(
	{
	    source => $datasource,
	    state  => $self->state || {},
	}
	);
    $search->init_databases();
    my ($f) = $search->search_features({-search_term=>$segment});
    unless ($f) {
	print header('text/plain'), "# The landmark named $segment was not found.\n";
	return;
    }
    $self->segment($f);
    return $f;
}

sub state {
    my $self = shift;
    my $d    = $self->{state};
    $self->{state} = shift if @_;
    $d;
}

sub all_databases {
    my $self   = shift;
    my $source = $self->data_source;
    return [map {"$_:database"} $source->databases];
}

sub get_labels {
    my $self = shift;
    my @labels = @{ $self->{labels} || [] };
    return \@labels;
}

sub get_id {
    my $self = shift;
    return $self->{id};
}

sub get_featurefiles {
    my $self = shift;
    my @ff = grep {/^file:/} @{ $self->{labels} || [] };
    return unless @ff;
    return shellwords(@ff);
}

sub get_do_stylesheet {
    my $self = shift;
    my $doit = $self->{stylesheet};
    return 0 if defined $doit && $doit =~ /^(no|off|0)$/i;
    return 1;
}

sub guess_file_type {
    my $self = shift;
    my $labels = $self->get_labels;

    my $forced = $self->forced_format;
    return $forced if defined $forced;

    # Currently we can't deal with heterogeneous  downloads,
    # so if multiple tracks are selected, we default to the
    # common gff3 format. In the future, we should create a
    # TAR file for download.
    if (@$labels > 1) {  
	return 'gff3';
    }
    my $label  = $labels->[0];
    my $source = $self->data_source;
    my $glyph = $source->setting(      $label => 'glyph');
    my $db    = $source->open_database($label);

    if ($glyph && $glyph =~ /vista/i) {
	return 'bed';
    }

    if ($glyph && $glyph =~ /wiggle/) {
	return 'bed';
    }

    if ($db->isa('Bio::DB::Bam') or $db->isa('Bio::DB::Sam')) {
	return 'sam';
    }

    if ($db->isa('Bio::DB::BigWig') or $db->isa('Bio::DB::BigWigSet')) {
	return 'bed';
    }

    return 'gff3';

}

sub get_file_mime_type {
    my $self = shift;
    return $self->{mimetype} if defined $self->{mimetype};
    my $dump = $self->{'dump'} || '';

    my $type = $self->guess_file_type;
    my $x    = "application/x-$type";

    return $type                      if $dump eq 'edit';
    return 'application/octet-stream' if $dump eq 'save';
    return 'text/plain';
}

sub get_file_extension {
    my $self = shift;
    my $type = $self->guess_file_type;
    return $type;
}

sub labels_to_types {
    my $self        = shift;
    my $labels      = shift;
    my $length      = shift;

    my $data_source = $self->data_source;

    # remove dynamic labels, such as uploads
    my @labels = grep { /:(overview|region|detail)$/  # keep overview/region sections
		         || 
                         !/^\w+:/x                    # discard over dynamic sections
                       } @$labels;
    my @types;
    for my $l (@labels) {
        my @f = shellwords( $data_source->semantic_setting( $l => 'feature', $length ) || '' );
	next unless @f;
        push @types, @f;
    }
    return \@types;
}

sub labels_to_files {
    my $self   = shift;
    my $labels = shift;
    @$labels or return [];

    # get the feature files, if appropriate
    my $id = $self->get_id or return [];

    # first get the main source
    my $data_source = $self->data_source;
    my $segment     = $self->segment;

    my @files;

    my $search = Bio::Graphics::Browser2::RegionSearch->new(
	{
	    source => $data_source,
	    state  => $self->state || {},
	}
	);
    $search->init_databases();

    my $mapper = $search->coordinate_mapper( $segment, 1 );
    for my $filename (@$labels) {
	$filename =~ s/:(detail|overview|region).*$//;
	my $path = Bio::Graphics::Browser2::UserData->file2path($data_source,$id,$filename);
        my $featurefile = eval {
            Bio::Graphics::FeatureFile->new(
                -file           => $path,
                -smart_features => 1,
                -map_coords     => $mapper,
            );
        };
	warn "Error while loading remote feature file $filename: $@" if $@;
        push @files, $featurefile if $featurefile;
    }

    return \@files;
}

sub print_feature {
    my $self = shift;
    my $f    = shift;
    eval { $f->version(3) };
    my $s = $f->gff_string(1);    # the flag is for GFF3 subfeature recursion
    chomp $s;
    if (my $prefix = $self->add_prefix) {
	$s =~ s/^/$prefix/gm unless $s =~ /^$prefix/m;
    }
    $s =~ s/\t\t/\t\.\t/g if $s;    # no empty columns
    $self->do_wigfile_substitution( \$s );
    print $s, "\n";
}

sub print_configuration {
    my $self   = shift;
    my $config = shift;
    my $labels = shift;

    my @labels = $labels ? @$labels : $config->labels;

    for my $l (@labels) {

	# a special config setting - don't want it to leak through
        next if $l =~ m/^\w+:/ && $l !~ m/:(overview|region|details?)$/;  
	next if $l =~ m/^_scale/;

        print "[$l]\n";
        my @s = $config->_setting($l);
        for my $s (@s) {
            my $value = $config->setting( $l => $s );
            if ( ref $value eq 'CODE' ) {
                $value
                    = $config->config->can('get_callback_source')
                    ? $config->config->get_callback_source( $l => $s )
                    : $config->setting( 'TRACK DEFAULTS' => $s );
                defined $value or next;
		chomp ($value);
            }
            next if $s =~ /^balloon/;    # doesn't work right
            print "$s = $value\n";
        }
        print "\n";
    }
}

sub print_gff3_data {
    my $self    = shift;
    my $db      = shift;
    my $types   = shift;
    my $filters = shift;

    my $s           = $self->get_segment;
    my $data_source = $self->data_source;
    my $len         = $s->length;

    my @args = (
        -seq_id => $s->seq_id,
        -start  => $s->start,
        -end    => $s->end
    );
    push @args, ( -type => $types ) if $types;
    my $iterator = $db->get_seq_stream(@args);

FEATURE:
    while ( my $f = $iterator->next_seq ) {
        for my $l ( $data_source->feature2label( $f, $len ) ) {
            next FEATURE if $filters->{$l} && !$filters->{$l}->($f);
        }
        $self->print_feature($f);
    }
}

# Because we can't sling whole wigfiles around, we serialize a section
# of the wigfile and send just the data and header information in "wif" format.
sub do_wigfile_substitution {
    my $self = shift;

    my $gff_line_ref = shift;
    $$gff_line_ref =~ /wigfile=/ or return;

    my $segment = $self->segment;
    my ( $start, $end ) = ( $segment->start, $segment->end );

    eval {    # trap all errors, which can be plentiful!
        eval "use Bio::Graphics::Wiggle"
            unless Bio::Graphics::Wiggle->can('new');
        eval "use MIME::Base64" unless MIME::Base64->can('encode');

        $$gff_line_ref =~ s{wigfile=([^;&\n]+)}
	{
          my $wig = Bio::Graphics::Wiggle->new(CGI::unescape($1));
          my $wif = $wig->export_to_wif($start,$end);
          'wigdata='.MIME::Base64::encode_base64($wif,'');
        }exg;
    };
    warn $@ if $@;
}

# Experimental feature: 
# list all the labels that are marked "discoverable" 
sub print_scan {
    my $self   = shift;
    print $self->get_scan;
}

sub get_scan {
    my $self   = shift;
    my $config = $self->data_source;
    my @labels = $config->labels;

    my $result = '';
    $result .=  "# Discoverable tracks from ".CGI->self_url."\n";
    for my $l (@labels) {
	next if $l =~ /^_/;
	next if $l =~ /:\w+/;
	next unless    $config->fallback_setting($l => 'discoverable');
	next if        $config->code_setting($l=>'global feature');
	my $key      = $config->code_setting($l => 'key') || $l;
	my $citation = $config->code_setting($l => 'citation');
	my $data_source  = $config->code_setting($l => 'data source');
	my $track_source = $config->code_setting($l => 'track source');
	my $subtracks = $config->subtrack_scan_list($l);
	$result .=  <<END;
[$l]
key      = $key
END
    ;
    $result .=  "select   = @$subtracks\n" if $subtracks;
    $result .=  "citation = $citation\n"   if $citation;
    $result .=  "data source = $data_source\n"   if $data_source;
    $result .=  "track source = $track_source\n"   if $track_source;
    $result .=  "\n";
    }
return $result;
}

1;
