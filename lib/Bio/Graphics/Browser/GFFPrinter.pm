package Bio::Graphics::Browser::GFFPrinter;

###################################################################
#
# This package holds the majority of code from the gbgff script.
# It is used to output GFF3 to allow for track sharing.
#
###################################################################

# $Id: GFFPrinter.pm,v 1.7 2009-01-06 07:38:24 lstein Exp $

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

use CGI 'param', 'path_info', 'header';
use Bio::Graphics::FeatureFile;
use Bio::Graphics::Browser::Shellwords;

sub new {
    my $class   = shift;
    my %options = @_;
    my $self    = bless {
        data_source => $options{-data_source},
        segment     => $options{-segment},
        seqid       => $options{-seqid},
        start       => $options{-start},
        segment_end => $options{-end},
        stylesheet  => $options{-stylesheet},
        id          => $options{-id},
        'dump'      => $options{'-dump'},  # in quotes because "dump" is a perl keyword
        labels      => $options{-labels},
        },
        ref $class || $class;

    $self->check_source() or return;
    return $self;
}

sub print_gff3 {
    my $self = shift;

    my $labels = $self->get_labels;
    my $types  = $labels ? $self->labels_to_types($labels) : undef;
    my $files  = $labels ? $self->labels_to_files($labels) : undef;

    if ($self->get_do_stylesheet) {
	$self->print_configuration( $self->data_source(), $labels );
	$self->print_configuration( $_, [ $_->labels ] ) for @$files;
    }

    my %filters
        = map { $_ => $self->data_source->setting( $_ => 'filter' ) || undef }
        @$labels;

    my $date = localtime;
    my $segment = $self->get_segment;
    print "##gff-version 3\n";
    print "##date $date\n";
    print "##source gbrowse gbgff gff3 dumper\n";
    print "##sequence-region ",$segment->seq_id,':',$segment->start,'..',$segment->end,"\n";

    $self->print_gff3_data( $_, $types, \%filters ) for $self->db;
    $self->print_gff3_data($_) for @$files;
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
    my $self = shift;

    # check whether someone called us directly by pasting into location box
    if ($self->{segment} =~ /^\$segment/) { 
        print header('text/plain');
	print "# To share this track, please paste its URL into the \"Enter Remote Annotation\" box\n",
	"# at the bottom of a GBrowse window and not directly into your browser's Location area.\n";
	return;
    }

    my ( $seqid, $start, $end )
        = $self->{segment} =~ /^([^:]+)(?::([\d-]+)(?:\.\.|,)([\d-]+))?/;

    $seqid ||= $self->{'seqid'};
    $start ||= $self->{start} || 1;
    $end   ||= $self->{end};
    unless ( defined $seqid ) {
        print header('text/plain');
	print "# Please provide ref, start and end arguments.\n";
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
    my $dump = $self->{'dump'} || '';
    return 'application/x-gff3'       if $dump eq 'edit';
    return 'application/octet-stream' if $dump eq 'save';
    return 'text/plain';
}

sub labels_to_types {
    my $self        = shift;
    my $labels      = shift;
    my $data_source = $self->data_source;

    # remove dynamic labels, such as uploads
    my @labels = grep { /:(overview|region|detail)$/  # keep overview/region sections
		         || 
                         !/^\w+:/x                    # discard over dynamic sections
                       } @$labels;
    my @types;
    for my $l (@labels) {
        my @f = shellwords( $data_source->setting( $l => 'feature' ) || '' );
	next unless @f;
        push @types, @f;
    }
    return \@types;
}

sub labels_to_files {
    my $self   = shift;
    my $labels = shift;

    my @labels = grep {/^file:/} @$labels;
    @labels or return [];

    # get the feature files, if appropriate
    my $id = $self->get_id or return [];

    # first get the main source
    my $data_source = $self->data_source;
    my $segment     = $self->segment;

    my @files;

    my $dir
        = $data_source->tmpdir( $data_source->source . "/uploaded_file/$id" );
    my $mapper = $data_source->coordinate_mapper( $segment, 1 );
    for my $filename (@labels) {
        my ($base) = $filename =~ /([^:\\\/]+)$/;
        $base =~ tr/-/_/;
        my $path        = "$dir/$base";
        my $featurefile = eval {
            Bio::Graphics::FeatureFile->new(
                -file           => $path,
                -smart_features => 1,
                -map_coords     => $mapper,
            );
        };
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
        next if $l =~ m/^\w+:/ && $l !~ m/:(overview|region}detail)$/;  
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
1;
