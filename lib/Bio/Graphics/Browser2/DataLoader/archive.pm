package Bio::Graphics::Browser2::DataLoader::archive;

# $Id$
use strict;
use base 'Bio::Graphics::Browser2::DataLoader';
use Bio::DB::BigWigSet;
use File::Spec;

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    $self->{default_track_name} = 'track000';
    $self;
}

sub default_track_name {
    my $self = shift;
    return $self->{default_track_name}++;
}

sub load {
    my $self = shift;
    my ($initial_lines,$fh) = @_;
    
    $self->flag_busy(1);
    eval {
	$self->open_conf;
	$self->set_status('starting load');
	
	mkdir $self->sources_path or die $!;
	$self->{archive} = File::Spec->catfile($self->sources_path,$self->track_name);
	my $source_file = IO::File->new($self->{archive},'>');

	warn "sourcefile=$self->{archive}";

	$self->start_load;

	$self->set_status('load data');
	my $bytes_loaded = 0;
	foreach (@$initial_lines) {
	    $source_file->print($_);
	    $bytes_loaded += length $_;
	}

	my $buffer;
	while ((my $bytes = read($fh,$buffer,8192) > 0)) {
	    $source_file->print($buffer);
	    $bytes_loaded += length $ buffer;
	    $self->set_status("loaded $bytes_loaded bytes") if $bytes++ % 10000;
	}
	$source_file->close();
    
	$self->finish_load;
	$self->check_metadata;
	$self->write_conf;
	$self->close_conf;
	$self->set_processing_complete;
    };

    $self->flag_busy(0);
    die $@ if $@;
    return $self->tracks;
}

sub finish_load {
	my $self = shift;
	$self->set_status("extracting files from archive");
	
	my $archive = $self->{archive};
	my $bin = $archive =~ /\.tar$/i ? $self->search_for_binary('tar') :
		$archive =~ /\.zip$/i ? $self->search_for_binary('unzip') :
		'';
	die "unrecognized file type!" unless $bin;
	
	my $command = $archive =~ /\.tar$/i ? "$bin -tf" : "$bin -l";
	my $fh;
	open $fh, "($command $archive && echo 'success') 2>&1 |";
	my @contents = <$fh>;
	close $fh;
	unless ($contents[-1] =~ /success/) {
		die "ARCHIVE LIST ERROR: @contents";
	}
	pop @contents;
	
	my @to_extract;
	while (@contents) {
		my $item = shift @contents;
		next if ($item =~ /^(Archive\:| Length|\-{5,})/); # unzip headers
		$item = (split / {2,}/, $item)[-1]; # split on two or more spaces
		chomp $item;
		my (undef, undef, $file) = File::Spec->splitpath($item);
		if ($file =~ /^meta/i) {
			push @to_extract, [$item, $file];
		}
		elsif ($file =~ /^\./) {
			next; # skip .files if present
		}
		elsif ($file =~ /\.bw$/i) {
			push @to_extract, [$item, $file];
		}
	}
	die "no recognizable files in archive to extract" unless @to_extract;
	
	# we are trying to be safe here and extract just the file contents
	# without directory paths to avoid ill- or mis-intentioned stray files
	my $path = $self->sources_path;
	my $count;
	$command = $archive =~ /\.tar$/i ? "$bin -x -O -f" : "$bin -p";
	foreach (@to_extract) {
		my $target = File::Spec->catfile($path, $_->[1]);
		# extract file from tar archive and redirect to file in our path
		open my $in, "$command $archive \"$_->[0]\" |" or 
			die "unable to open achive for extraction";
		open my $out, '>', $target or die "unable to open target file";
		while (<$in>) {print $out $_}
		close $in;
		close $out;
		$count++ if -e $target && -s _ ;
	}
	die "not all files could be extracted\n" unless $count == scalar(@to_extract);
	unlink $archive; # no longer need
}

sub search_for_binary {
    my $self   = shift;
    my $target = shift;
    for my $p (split ':', $ENV{PATH}) {
		my $tgt = File::Spec->catfile($p,$target);
		return  $tgt if -e $tgt && -x _;
    }
    return;
}

sub check_metadata {
	my $self = shift;
	$self->set_status('checking metadata');
	my $path = $self->sources_path;
	
	my $count = Bio::DB::BigWigSet->index_dir($path);
	die "two or more BigWig files are required" unless $count > 1;
	
	my $bws = Bio::DB::BigWigSet->new(-dir => $path);
	my $md = $bws->metadata;
	my $default = $self->track_name; # default type
	my %types; # metadata types, not required to be unique
	my %names; # metadata display_names, required to be unique
	my $flag; # for updated metadata
	foreach my $i (keys %$md) {
		if (exists $md->{$i}{'type'}) {
			$types{ $md->{$i}{'type'} }++;
		}
		elsif (exists $md->{$i}{'method'} && exists $md->{$i}{'source'}) {
			$types{ $md->{$i}{'method'} . ':' . $md->{$i}{'source'} }++;
		}
		elsif (exists $md->{$i}{'method'}) {
			$types{ $md->{$i}{'method'} }++;
		}
		elsif (exists $md->{$i}{'primary_tag'}) {
			$types{ $md->{$i}{'primary_tag'} }++;
		}
		else {
			$types{$default}++;
			my (undef, undef, $filename) = File::Spec->splitpath( $md->{$i}{'dbid'} );
			$bws->set_bigwig_attributes($md->{$i}{'dbid'}, {'type'=>$default});
			$flag++;
		}
		
		if (exists $md->{$i}{'display_name'}) {
			 if (exists $names{ $md->{$i}{'display_name'} }) {
			 	# must make the name unique
				my (undef, undef, $name) = File::Spec->splitpath( $md->{$i}{'dbid'} );
			 	$name =~ s/\.bw$//i;
			 	$bws->set_bigwig_attributes(
			 		$md->{$i}{'dbid'}, {'display_name'=>$name} );
			 	$names{$name}++;
			 	$flag++;
			 }
			 else {
			 	$names{ $md->{$i}{'display_name'} }++;
			 }
		}
		else {
			my (undef, undef, $name) = File::Spec->splitpath( $md->{$i}{'dbid'} );
			$name =~ s/\.bw$//i;
			$bws->set_bigwig_attributes(
				$md->{$i}{'dbid'}, {'display_name'=>$name} );
			$names{$name}++;
			$flag++;
		}
	}
	
	$self->write_new_metadata($bws) if $flag;
	$self->typelist(keys %types);
	$self->namelist(keys %names);
}

sub typelist {
	my $self = shift;
	$self->{typelist} ||= [];
	@{ $self->{typelist} } = @_ if @_;
	return @{ $self->{typelist} };
}

sub namelist {
	my $self = shift;
	$self->{namelist} ||= [];
	@{ $self->{namelist} } = @_ if @_;
	return @{ $self->{namelist} };
}

sub write_new_metadata {
	# Bio::DB::BigWigSet does not have a method to write out updated metadata
	# so we will do it here
	my $self = shift;
	my $bws = shift;
	my $path = $self->sources_path;
	foreach my $f (glob($path)) {
		unlink $f if $f =~ /^meta/i;
	}
	my $index = File::Spec->catfile($path, 'metadata.index');
	open my $fh, ">", $index or return;
	my $md = $bws->metadata;
	foreach my $i (sort {$a <=> $b} keys %$md) {
		my (undef, undef, $file) = File::Spec->splitpath( $md->{$i}{'dbid'} );
		my $string = "[$file]\n";
		foreach my $k (keys %{$md->{$i}}) {
			next if $k eq 'dbid';
			$string .= "$k = " . $md->{$i}{$k} . "\n";
		}
		print $fh "$string\n";
	}
	close $fh;
}

sub write_conf {
	my $self = shift;
    my $name   = $self->track_name;
    my $path   = $self->sources_path;
    my $loadid = $self->loadid;
    my $conf   = $self->conf_fh;
    my $dbid   = $self->new_track_label;
    my @types  = $self->typelist;
    my $table;
    foreach my $n ($self->namelist) {
    	$table .= "\n   :\"$n\" \"$n\" ;";
    }
    
    print $conf <<END;
[$dbid:database]
db_adaptor    = Bio::DB::BigWigSet
db_args       = -dir '$path'
                -feature_type summary

#>>>>>>>>>> cut here <<<<<<<<
    
[$dbid]
database = $dbid
feature  = @types
subtrack select = Name tag_value display_name
subtrack table = $table
glyph    = wiggle_whiskers
# change glyph to wiggle_xyplot to use semi-transparent overlap
fgcolor  = black
height   = 50
autoscale = chromosome
key      = $name
description = 

END
;

}

1;

__END__

=head1 NAME

Bio::Graphics::Browser2::DataLoader::archive

=head1 DESCRIPTION

A data loader to work with archives of BigWig files to generate a BigWigSet 
database. Two or more BigWig files may be combined into an archive file and 
uploaded. The files are extracted, a metadata index generated if required, and 
a configuration written using subtracks for each BigWig file. This allows a 
fast, convenient option to bundle multiple data files together and provide a 
concise, organized interface to multiple data tracks.

Supported archives include TAR (.tar, .tar.gz, .tgz, .tbz2, .tar.bz2) and 
ZIP (.zip) files. Archives should include only BigWig files (which must have 
a .bw extension) and optionally a metadata text file. Extraneous files and 
directory paths are ignored. 

Subtrack tables are set up using the display_name tag value.

See the documentation for Bio::DB::BigWigSet for more information.

=head1 SETUP

The Bio-BigFile (Bio::DB::BigWigSet) Perl module must be installed.

Archives are processed through external tar and unzip utilities. These 
are located by searching the default environment PATH.

=head1 AUTHOR

 Timothy J. Parnell, PhD
 Dept of Oncological Sciences
 Huntsman Cancer Institute
 University of Utah
 Salt Lake City, UT, 84112

This package is free software; you can redistribute it and/or modify
it under the terms of the GPL (either version 1, or at your option,
any later version) or the Artistic License 2.0.  

