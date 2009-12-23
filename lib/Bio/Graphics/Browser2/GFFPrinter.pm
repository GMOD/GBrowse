package Bio::Graphics::Browser2::GFFPrinter;

###################################################################
#
# This package holds the majority of code from the gbgff script.
# It is used to output GFF3 to allow for track sharing.
#
###################################################################

# $Id$

# Dirt simple GFF3 dumper, suitable for a lightweight replacement to DAS.
# Call this way:
#    http://my.host/cgi-bin/gbrowse/volvox?gbgff=1;q=ctgA:1..2000;t=Genes+ExampleFeatures
#
# From within the "Add Remote Annotations" section, you can say:
#     http://my.host/cgi-bin/gbrowse/volvox?gbgff=1;q=$segment;t=Genes+ExampleFeatures
#
# To share uploads, do this:
#     http://my.host/cgi-bin/gbrowse/volvox?gbgff=1;q=ctgA:1..2000;\
#           t=Genes+ExampleFeatures+file:my_upload.txt;id=session_id

use strict;

use CGI 'param', 'path_info', 'header';
use Bio::Graphics::Browser2;
use Bio::Graphics::FeatureFile;
use Bio::Graphics::Browser2::RegionSearch;
use Bio::Graphics::Browser2::Shellwords;

sub new {
    my $class   = shift;
    my %options = @_;
    my $self    = bless {
        data_source => $options{-data_source},
        stylesheet  => $options{-stylesheet},
        id          => $options{-id},
        'dump'      => $options{'-dump'},  # in quotes because "dump" is a perl keyword
        labels      => $options{-labels},
	mimetype    => $options{-mimetype},
        },
        ref $class || $class;

    $self->check_source()                  or return;
    $self->get_segment($options{-segment}) or return
	if $options{-segment};

    return $self;
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

sub print_gff3 {
    my $self = shift;

    warn "print_gff3()";

    my $segment= $self->get_segment;
    my $labels = $self->get_labels;
    my $types  = $labels ? $self->labels_to_types($labels,eval{$segment->length}) : undef;
    my $files  = $labels ? $self->labels_to_files($labels,eval{$segment->length}) : undef;

    if ($self->get_do_stylesheet) {
	$self->print_stylesheet($segment,$labels);
    }

    my %filters
        = map { $_ => $self->data_source->setting( $_ => 'filter' ) || undef }
        @$labels;

    my $date = localtime;
    print "##gff-version 3\n";
    print "##date $date\n";
    print "##source gbrowse gbgff gff3 dumper\n";
    print "##sequence-region ",$segment->seq_id,':',$segment->start,'..',$segment->end,"\n";

    $self->print_gff3_data( $_, $types, \%filters ) for $self->db;
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

    # Find the segment - it may be hiding in any of the databases.
    my (%seenit,$s,$db);
    for my $track ('general',@$tracks) {
	$db = $datasource->open_database($track) or next;
	next if $seenit{$db}++;
	($s) = $db->segment(-name  => $seqid,
			    -start => $start,
			    -stop  => $end);
	last if $s;
    }
    $self->segment($s);
    return $s;
}

sub all_databases {
    my $self   = shift;
    my $source = $self->data_source;
    return [map {"$_:database"} $source->databases];
}

sub get_labels {
    my $self = shift;
    my @labels = @{ $self->{labels} || [] };
    return unless @labels;
    @labels = shellwords(@labels);
    for (@labels) { tr/$;/-/ }
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

sub get_mime_type {
    my $self = shift;
    return $self->{mimetype} if defined $self->{mimetype};
    my $dump = $self->{'dump'} || '';
    return 'application/x-gff3'       if $dump eq 'edit';
    return 'application/octet-stream' if $dump eq 'save';
    return 'text/plain';
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
	    state  => { },
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
	my $key      = $config->code_setting($l => 'key');
	my $citation = $config->code_setting($l => 'citation');
	my (undef,@subtracks) = shellwords($config->code_setting($l => 'select'));
	$result .=  <<END;
[$l]
key      = $key
END
    ;
    $result .=  "select   = @subtracks\n" if @subtracks;
    $result .=  "citation = $citation\n"  if $citation;
    $result .=  "\n";
    }
return $result;
}

1;
