package Bio::Graphics::Browser2::DataLoader::generic;

# $Id$
use strict;
use Bio::DB::SeqFeature::Store;
use Carp 'croak';
use File::Basename 'basename';
use base 'Bio::Graphics::Browser2::DataLoader';

use constant TOO_SMALL_FOR_SUMMARY_MODE => 10000;  # don't go into summary mode

my @COLORS = qw(blue red orange brown mauve peach green cyan 
                black yellow cyan papayawhip coral);

my $DUMPING_FIXED;  # flag that we patched Bio::SeqFeature::Lite

sub start_load {
    my $self = shift;
    my $track_name = $self->track_name;
    my $data_path  = $self->data_path;

    my $db     = $self->create_database($data_path);
    my $loader_class = $self->Loader;
    my $fast         = $self->do_fast;
    eval "require $loader_class" unless $loader_class->can('new');
    my $loader = $loader_class->new(-store=> $db,
				    -fast => $fast,
				    -summary_stats    => 1,
				    -verbose          => 0,
				    -index_subfeatures=> 0,
	);
    $loader->start_load();
    $self->{loader}    = $loader;
    $self->{conflines} = [];
    $self->state('starting');
}

sub do_fast { 1 };

sub Loader {
    croak "The Loader() class method must be implemented in a subclass";
}

sub finish_load {
    my $self = shift;
    my $line_count = shift;

    $self->set_status('creating database');
    $self->loader->finish_load();
    my $db        = $self->loader->store;
    my $conf      = $self->conf_fh;
    my $trackname = $self->track_name;
    my $dsn       = $self->dsn;
    my $backend   = $self->backend;

    $self->write_gff3($db,$dsn) if $backend eq 'memory';

    my $trackno   = 0;
    my $loadid    = $self->loadid;
    my $inhibit_summary = $line_count < TOO_SMALL_FOR_SUMMARY_MODE;
    eval {
	$self->set_status('calculating summary statistics');
	$self->loader->build_summary;
    } unless $inhibit_summary;
    warn $@ if $@;

    $self->set_status('creating configuration');
    
    print $conf <<END;
[$loadid:database]
db_adaptor = Bio::DB::SeqFeature::Store
db_args    = -adaptor $backend
             -dsn     $dsn
search options = default +wildcard +stem

#>>>>>>>>>> cut here <<<<<<<<
END

    if (my @lines = @{$self->{conflines}}) {  # good! user has provided some config hints
	my ($old_trackname,$seen_feature);
	my $category = $self->category;
	for my $line (@lines) {
	    chomp $line;
	    if ($line =~ /^\s*database/) {
		next;   # disallowed
	    }
	    elsif ($line =~ /^\[([^\]]+)\]/) { # overwrite track names to avoid collisions
		$old_trackname = $1;
		undef $seen_feature;
		my $trackname = $self->new_track_label;
		print $conf "[$trackname]\n";
		print $conf "database = $loadid\n" ;
		print $conf "category = $category\n";
		print $conf "show summary = 0\n" if $inhibit_summary;
	    } elsif ($line =~ /^feature/) {
		$seen_feature++;
		print $conf $line,"\n";
	    } elsif ($line !~ /\S/ && $old_trackname && !$seen_feature) {
		print $conf "feature = $old_trackname\n\n";
		undef $old_trackname;
		undef $seen_feature;
	    } else {
		print $conf $line,"\n";
	    }
	}
	if ($old_trackname && !$seen_feature) {
	    print $conf "feature = $old_trackname\n\n";
	}
    } else {  # make something up
	my @types = eval {$db->toplevel_types};
	@types    = $db->types unless @types;

	my $filename = $self->track_name;
	for my $t (@types) {
	    my $trackname = $self->new_track_label($t);

	    my ($glyph,$stranded);
	    # start of a big heuristic section
	    if ($t =~ /gene|cds|exon|mRNA|transcript/i) {
		$glyph    = 'gene';
		$stranded = 0;
	    } else {
		$glyph    = 'segments';
		$stranded = 1;
	    }

	    my $color = $COLORS[rand @COLORS];
	    my $category  = $self->category;
	    my $summary   = $inhibit_summary ? 'show summary = 0' : '';
	    print $conf <<END;
[$trackname]
database = $loadid
feature   = $t
glyph     = $glyph
bgcolor   = $color
fgcolor   = $color
label     = 1
stranded  = $stranded
connector = solid
balloon hover = \$description
category    = $category
key         = $t
$summary

END
	}
    }
}

sub loader {shift->{loader}}
sub state {
    my $self = shift;
    my $d    = $self->{state};
    $self->{state} = shift if @_;
    $d;
}
sub load_line {
    my $self = shift;
    my $line = shift;

    my $old_state = $self->state;
    my $state     = $self->_state_transition($old_state,$line);
    my $prefix    = $self->strip_prefix;

    if ($state eq 'data') {
	$line =~ s/^$prefix// if $prefix;
	$self->loader->load_line($line);
    } elsif ($state eq 'config') {
	push @{$self->{conflines}},$line;
    } else {
	# ignore it
    }
    $self->state($state) if $state ne $old_state;
}

# This is called to save out the feature file in GFF3 format,
# which is needed when using the memory backend.
sub write_gff3 {
    my $self = shift;
    my ($db,$path) = @_;
    $self->fix_memory_dumping;
    $self->set_status('writing GFF3 file');
    $path .= "/data.gff3";
    open my $f,">",$path or die "Can't open $path: $!";
    print $f "##gff-version 3\n";
    print $f "##Index-subfeatures 0\n\n";
    my $i = $db->get_seq_stream;
    while (my $feature = $i->next_seq) {
	print $f $feature->gff3_string(1),"\n";
    }
    close $f;
}

# This is a hack to patch errors in bioperl feature file loading
sub fix_memory_dumping {
    my $self = shift;
    return if $DUMPING_FIXED++;
    *Bio::SeqFeature::Lite::gff3_string = eval <<'END';
sub {
    my ($self,$recurse,$parent_tree,$seenit,$force_id) = @_;
    $parent_tree ||= {};
    $seenit      ||= {};
    my @rsf      =   ();
    my @parent_ids;

    if ($recurse) {
	$self->_traverse($parent_tree) unless %$parent_tree;  # this will record parents of all children
	my $primary_id = defined $force_id ? $force_id : $self->_real_or_dummy_id;

	@rsf = $self->get_SeqFeatures;
	return if $seenit->{$primary_id}++;
	@parent_ids = keys %{$parent_tree->{$primary_id}};
    }

    my $group      = $self->format_attributes(\@parent_ids,$force_id);
    my $name       = $self->name;

    my $class = $self->class;
    my $strand = ('-','.','+')[$self->strand+1];
    my $p = join("\t",
		 $self->seq_id||'.',
		 $self->source||'.',
		 $self->method||'.',
		 $self->start||'.',
		 $self->stop||'.',
		 defined($self->score) ? $self->score : '.',
		 $strand||'.',
		 defined($self->phase) ? $self->phase : '.',
		 $group||'');
    return join("\n",
		$p,
		map {$_->gff3_string(1,$parent_tree,$seenit)} @rsf);
}
END
}

# shamelessly copied from Bio::Graphics::FeatureFile.
sub _state_transition {
    my $self = shift;
    my ($current_state,$line) = @_;

    if ($current_state eq 'starting') {
	return $current_state unless /\S/;
	$current_state = 'config';
    }

    if ($current_state eq 'data') {
	return 'config' if $line =~ m/^\s*\[([^\]]+)\]/;  # start of a configuration section
    } 
    elsif ($current_state eq 'config') {
	return 'data'   if $line =~ /^\#\#(\w+)/;     # GFF3 meta instruction
	return 'data'   if $line =~ /^reference\s*=/; # feature-file reference sequence directive
	
	return 'config' if $line =~ /^\s*$/;                             #empty line
	return 'config' if $line =~ m/^\[([^\]]+)\]/;                    # section beginning
	return 'config' if $line =~ m/^[\w\s]+=/;                        # arg = value
	return 'config' if $line =~ m/^\s+(.+)/;                         # continuation line
	return 'config' if $line =~ /^\#/;                               # comment -not a meta
	return 'data';
    }
    return $current_state;
}
1;
