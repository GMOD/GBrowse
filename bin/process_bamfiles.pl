#!/usr/bin/perl
#$Id: process_bamfiles.pl,v 1.6 2009-08-27 19:13:18 idavies Exp $

# The purpose of this module is to process a hierarchy of directories containing  sam/bam 
# files and generate automatic GBrowse for them. Ultimately this will be integrated into
# an upload interface for sam/bam.

# directory structure
# DATA_ROOT => /srv/gbrowse/gbrowse/data/bam_db
#                                          /human   -- dsn name
#                                                /category 1
#                                                         /category 2
#                                                               /track_name.sorted.bam.bai
#                                          /elegans -- dsn name
#                                                /etc
#
# REF_ROOT => /srv/gbrowse/gbrowse/data/reference_db
#                                           /human.fa
#                                           /human.fa.fai
#                                           /elegan.fa
#                                           /elegans.fa.fai
#
# CONF_ROOT => /srv/gbrowse/gbrowse/data/conf
#                                           /human -- dsn name
#                                                track_name1.conf
#                                                track_name2.conf
#                                           /elegans -- dsn name
#
# we are going to hard-code these relationships as follows
# ROOT 
# DATA_ROOT = ROOT/bam_db
# REF_ROOT  = ROOT/reference_db
# CONF_ROOT = ROOT/conf
#
# the logic is as follows
# 1. ROOT is defined as the startup argument
# 2. traverse DATA_ROOT looking for sam & bam files
# 3. for each sam/bam file, satisfy this dependency tree
#      basename.sam        => basename.bam
#      basename.bam        => basename.sorted.bam
#      basename.sorted.bam => basename.sorted.bam.bai
# 4. compare modification date of CONF_ROOT/dsn/basename.conf to basename.sorted.bam.bai
#      and rebuild config file if necessary

use strict;
use warnings;
use Getopt::Long;

my $www_root;
my $result = GetOptions('www_root:s' => \$www_root);
my $usage =<<USAGE;
Usage: $0 process_bamfiles.pl [options] /path/to/root/directory

Options:
 
  --www_root  <path>    Specify root path as seen by web server.
  -w

If the web server will see the database files on a different path,
as might happen on an NFS-mounted filesystem, you may specify the
path that the web server sees using -w.
USAGE
    ;

my $root = shift;
$root && $result or die $usage;

$www_root ||= $root;

my $bamfile_processor = BamFileTree->new($root,$www_root);
$bamfile_processor->process();

exit 0;

package BamFileTree;

use File::Find     'find';
use File::Basename 'basename','dirname';
use IO::Dir;
use File::Spec;
use Cwd;
use Carp;

sub new {
    my $class = shift;
    my $root     = shift;
    my $www_root = shift;
    return bless { root     => $root,
		   www_root => $www_root,
    },ref $class || $class;
}

sub root      { shift->{root}     }
sub www_root  { shift->{www_root} }
sub data_root { 
    return File::Spec->catfile(shift->root,'bam_db');
}
sub ref_root {
    return File::Spec->catfile(shift->root,'reference_db');
}
sub conf_root {
    return File::Spec->catfile(shift->root,'conf');
}

sub process {
    my $self = shift;

    my @dsn  = $self->get_data_dirs;
    for my $dsn (@dsn) {
	my @tracks = $self->get_data_tracks($dsn);
	foreach (@tracks) {
	    	eval {
		    $self->process_bamfile($_); 
		    $self->build_conf($_);
		};
		if ($@) {
		    $self->status($_,"ERROR: $@");
		} else {
		    $self->status($_);
		}
	}
	my %track_names = map {$_->name=>1} @tracks;
	my @conf        = $self->config_files($dsn);
	$self->remove_dangling_conf($_,\%track_names) foreach @conf;
    }
}

sub get_faidx {
    my $self   = shift;
    my $dsn    = shift;
    my $fasta    = $self->get_fa($dsn);

    croak "No reference fasta file for $dsn found. Please install $fasta"
        unless -e $fasta;

    my $ref_root = $self->ref_root;
    unless (-e "$fasta.fai" && -M "$fasta.fai" < -M $fasta) {
        $self->invoke_sam('faidx',$fasta) or croak "samtools failed to index $fasta";
    }
        
    return File::Spec->catfile($ref_root,"$dsn.fa.fai");
}

sub get_fa {
    my $self = shift;
    my $dsn  = shift;
    my $ref_root = $self->ref_root;
    my $fasta    = File::Spec->catfile($ref_root,"$dsn.fa");
    return $fasta;
}

sub get_data_dirs {
    my $self = shift;
    my $root = $self->data_root;
    my $dir  = IO::Dir->new($root) or croak "$root is not a directory";
    my @result;
    while (my $d = $dir->read) {
	next     if $d =~ /^\./;
	next unless -d File::Spec->catfile($root,$d);
	push @result,$d;
    }
    $dir->close;
    return @result;
}

sub get_data_tracks {
    my $self    = shift;
    my $dsn     = shift;
    my $root    = File::Spec->catfile($self->data_root,$dsn);
    croak "$root is not a directory" unless -e $root && -d _;

    # do a depth first traversal to get categories and tracks
    my @result;
    my $wanted = sub {
	if (/\.(bam|sam|sam.gz)$/i) {
	    return if /\.sorted\.bam$/;
	    (my $path = $File::Find::dir) =~ s!^$root/?!!;
	    my @categories = File::Spec->splitdir($path);
	    push @result,Track->new(-categories=>\@categories,
				    -path      => $File::Find::dir,
				    -name      => basename($_,'.sam.gz','.sam','.bam'),
				    -dsn       => $dsn,
		);
	}
    };

    find($wanted,$root);
    my %seen;
    return grep {!$seen{$_->name}++} @result;
}

sub process_bamfile {
    my $self  = shift;
    my $track = shift;

    my $path  = $track->path;
    my $base  = $track->name;
    my $dsn   = $track->dsn;

    my $cwd   = getcwd;
    chdir $path;
    my $faidx = $self->get_faidx($dsn);

    $self->status($track,'importing');
    $self->satisfy_sam_dependencies("$base.sam","$base.bam",
				    'import',$faidx,"$base.sam","$base.bam");

    $self->status($track,'importing');
    $self->satisfy_sam_dependencies("$base.sam.gz","$base.bam",
				    'import',$faidx,"$base.sam.gz","$base.bam");

    $self->status($track,'sorting');
    $self->satisfy_sam_dependencies("$base.bam","$base.sorted.bam",
				    'sort',"$base.bam","$base.sorted");

    $self->status($track,'indexing');
    $self->satisfy_sam_dependencies("$base.sorted.bam","$base.sorted.bam.bai",
				    'index',"$base.sorted.bam");
    chdir $cwd;
}

sub config_files {
    my $self = shift;
    my $dsn  = shift;
    my $croot= $self->conf_root;
    my $dir  = IO::Dir->new(File::Spec->catfile($croot,$dsn));
    my @results;
    while (my $entry = $dir->read) {
	next unless $entry =~ /\.conf$/;
	push @results,$entry;
    }
    $dir->close;
    return map {File::Spec->catfile($croot,$dsn,$_)} @results;
}

sub remove_dangling_conf {
    my $self = shift;
    my ($conf_path,$track_names) = @_;
    my $basename = basename($conf_path,'.conf');
    return if $track_names->{$basename};
    unlink $conf_path;
}

sub build_conf {
    my $self  = shift;
    my $track = shift;

    my $dsn       = $track->dsn;
    my $name      = $track->name;
    my $category  = $track->category;
    my $bam_path  = File::Spec->catfile($track->path,"$name.sorted.bam");
    my $fa_path   = $self->get_fa($dsn);
    my $conf_file = File::Spec->catfile($self->conf_root,$dsn,"$name.conf");

    my $read_category  = $category ? "$category:Reads" : 'Reads';
    my $pairs_category = $category ? "$category:Read Pairs" : 'Read Pairs';

    return if -e $conf_file && -M $conf_file <= -M $bam_path;  # already there

    warn "building configuration file for $bam_path\n";
    $self->status($track,'building config');

    my $www_root = $self->www_root;
    my $root     = $self->root;
    unless ($www_root eq $root) {
	$www_root .= '/' unless $www_root =~ m!/$!;
	foreach ($fa_path,$bam_path) { s/$root/$www_root/ };
    }
    
    open my $cf,'>',$conf_file or die "Couldn't open $conf_file: $!";
    print $cf <<END;
[$name:database]
db_adaptor  = Bio::DB::Sam
db_args     = -fasta "$fa_path"
              -bam   "$bam_path"
              -split_splices 1
search options = none

[${name}_pairs]
database      = $name
feature       = read_pair
glyph         = segments
draw_target   = 1
show_mismatch = 1
mismatch_color= red
bgcolor       = green
fgcolor       = green
height        = 10
label         = sub {shift->display_name}
label density = 50
bump          = fast
maxdepth      = 2
connector     = sub {
		my \$glyph = pop;
	        \$glyph->level == 0 ? 'dashed' : 'solid';
   }
category      = $pairs_category
feature_limit = 250
key           = $name Read Pairs

[${name}_pairs:10001]
feature       = coverage:1000
glyph         = wiggle_xyplot
height        = 80
min_score     = 0
autoscale     = local

[$name]
database      = $name
feature       = match
glyph         = segments
draw_target   = 1
show_mismatch = 1
mismatch_color= red
bgcolor       = blue
fgcolor       = blue
height        = 5
label         = sub {shift->display_name}
label density = 10
bump          = fast
category      = $read_category
feature_limit = 250
key           = $name Alignments

[$name:10001]
feature       = coverage:1000
glyph         = wiggle_xyplot
height        = 80
min_score     = 0
autoscale     = local

END
    close $cf;
}

sub satisfy_sam_dependencies {
    my $self = shift;
    my ($source,$target,@args) = @_;
    return unless -e $source;
    my $source_mod = -M $source;  # number of days BEFORE script started up 
    my $target_mod = -M $target;
    if (!$target_mod or $source_mod < $target_mod) { # source more recent than target
	$self->invoke_sam(@args) or croak "Samtools failed: $!";
    }
}

sub invoke_sam {
    my $self = shift;
    my @args = @_;
    warn "samtools @args...\n";
    my $status = system 'samtools',@args;
    return $status == 0;
}

sub status {
    my $self    = shift;
    my $track   = shift;
    my $message = shift;

    my $name    = $track->name;

    $track or croak "Usage: \$self->status(\$track,\$message)";
    my $file    = File::Spec->catfile($track->path,"$name.STATUS");
    unless (defined $message) {
	unlink $file;
	return;
    }
    open my $fh,'>',$file or die "Couldn't open status file: $!";
    print $fh $message;
    close $fh;
}


package Track;

sub new {
    my $self = shift;
    my %args = @_;
    return bless {categories => $args{-categories},
		  path       => $args{-path},
		  name       => $args{-name},
		  dsn        => $args{-dsn},
    },ref $self || $self;
}

sub category {
    my $self = shift;
    my $c    = $self->{categories} or return;

    return $c unless ref $c && ref $c eq 'ARRAY';
    return join ':',@$c;
}

sub dsn { shift->{dsn} }

sub path { shift->{path}  }

sub name { shift->{name}  }

__END__

