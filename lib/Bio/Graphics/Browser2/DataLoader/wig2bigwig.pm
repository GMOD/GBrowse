package Bio::Graphics::Browser2::DataLoader::wig2bigwig;

# $Id$
use strict;
use base 'Bio::Graphics::Browser2::DataLoader';
use Bio::DB::BigWig;
use Bio::Graphics::Browser2::Util 'shellwords';
use File::Basename 'basename','dirname';

# we will sort out the sections corresponding to each track line
sub load_line { 
    my $self = shift;
    my $line = shift;

    my $prefix = $self->strip_prefix;
    if ($prefix) {
	$line =~ s/^$prefix//;
	$line =~ s/chrom=$prefix/chrom=/;
    }

    if ($line =~ /^track/) {  # starting or ending a section
	$self->finish_track_declaration;
	$self->start_track_declaration($line);
    } elsif ($line =~ /\S/ && $line !~ /^#/ && !$self->{current_track}) {
	warn "no track declaration; faking it";
	$self->start_default_track_declaration();
	$self->write_line($line);
    }
    else {
	$self->write_line($line);
    }
}


sub start_track_declaration {
    my $self = shift;
    my $line = shift;
    my (undef,@pairs) = shellwords($line);
    my %options = map{split '='} @pairs;
    $self->{current_track}{options}     = \%options;
    $self->{current_track}{name}      ||= $self->default_track_name;

    my $dest = File::Spec->catfile($self->data_path,$self->{current_track}{name}).'.wig';
    $self->{current_track}{wigfile}    = $dest;

    open my $fh,'>',$dest or die "Can't open $dest for writing: $!";
    $self->{current_track}{fh}         = $fh;
}

sub start_default_track_declaration {
    my $self = shift;
    $self->start_track_declaration('track type=wiggle_0');
}

sub finish_track_declaration {
    my $self = shift;
    return unless $self->{current_track};
    if ($self->{current_track}{fh}) {
	close  $self->{current_track}{fh} 
	   or die "Error closing wig file $self->{current_track}{wigfile}:$!";
    }
    $self->wig2bigwig($self->{current_track}{wigfile});
    push @{$self->{tracks}},$self->{current_track};
    delete $self->{current_track};
}

sub write_line {
    my $self = shift;
    my $line = shift;
    my $fh   = $self->{current_track}{fh} or return;
    print $fh $line or die "Couldn't write to $self->{current_track}{wigfile}: $!";
}

sub wig2bigwig {
    my $self = shift;
 
    my $src          = $self->{current_track}{wigfile} or return;
    (my $dest=$src)  =~ s/\.wig$/\.bw/;
    my $cs           = $self->chrom_sizes;

    $self->{current_track}{bigwig} = $dest;

    $self->set_status('creating bigwig file');
    # the cause for this complicated code is that we first look for the
    # external wigToBigWig and run that in a fashion that allows us to
    # recover its stderr. Otherwise we fork (safely) and call our internal
    # library routine from Bio::DB::BigFile. This can exit out in an 
    # uncatchable way so we have to capture stderr as well.
    {
	local $SIG{CHLD} = 'DEFAULT';
	my $fh;
	if (my $wigtobigwig = $self->wigtobigwig_path) {
	    open $fh,"($wigtobigwig -clip '$src' '$cs' '$dest' && echo success) 2>&1 |";
	} else {
	    eval "use IO::Pipe" unless IO::Pipe->can('new');
	    $fh  = IO::Pipe->new;
	    my $child = Bio::Graphics::Browser2::Render->fork();
	    die "Couldn't fork" unless defined $child;
	    if (!$child) { # child process
		$fh->writer();
		my $fileno = fileno($fh);
		open STDERR,">&$fileno";
		open STDOUT,">&$fileno";
		Bio::DB::BigFile->createBigWig($src,$cs,$dest,
					       {clipDontDie=>1});
		print STDERR "success";
		exit 0;
	    } else {
		$fh->reader;
	    }
	}
	my @lines = <$fh>;
	close $fh;
	unless ($lines[-1] =~ /success/) {
	    die "PROCESSING ERROR: @lines";
	}
    }

    unlink $self->{current_track}{wigfile};
}

sub finish_load {
    my $self = shift;

    $self->finish_track_declaration;
    die "no tracks defined!" unless $self->{tracks};

    my $loadid     = $self->loadid;

    $self->set_status('creating configuration');
    my $conf      = $self->conf_fh;
    my @tracks = @{$self->{tracks}};
    for my $track (@tracks) {
	my $dbid       = $self->new_track_label;
	my $bigwig     = $track->{bigwig} or die "no bigwig for $track->{wigfile}";
	$track->{dbid} = $dbid;
	print $conf <<END;
[$dbid:database]
db_adaptor    = Bio::DB::BigWig
db_args       = -bigwig '$bigwig'

END
    ;
    }
    print $conf "#>>>>>>>>>> cut here <<<<<<<<\n";

    my $trackno = 1;
    for my $track (@tracks) {
	my $dbid = $track->{dbid};
	my $options = $track->{options};
	my $description = $options->{description};
	$options->{name}       ||= sprintf("%s.%03d",$self->track_name,$trackno++);
	$options->{visibility} ||= 'full';
        $options->{maxHeightPixels} ||= $options->{visibility} eq 'full' ? 50 : 20;
	$options->{autoScale}  ||= 'off';
	my @options;
	push @options,"database = $dbid";
	push @options,"feature  = summary";
	push @options,"key      = $options->{name}";
	push @options,'glyph = '. ($options->{visibility} eq 'pack' 
	                               ? 'wiggle_density' 
				       : 'wiggle_whiskers' );
	push @options,'autoscale = '.($options->{autoScale}  eq 'on'   
	                               ? 'local' 
				       : 'chromosome');
	if (exists $options->{viewLimits} && 
	    (my ($low,$hi) = split ':',$options->{viewLimits})) {
	    push @options,"min_score = $low";
	    push @options,"max_score = $hi";
	}

	if (exists $options->{maxHeightPixels} &&
	    (my ($max,$default,$min) = split ':',$options->{maxHeightPixels})) {
	    $default ||= $max;
	    push @options,"height  = $default";
	}
        push @options,"description = $description";
	my $config_lines = join "\n",@options;
        print $conf <<END;
[$dbid]
$config_lines

END
    }
    
}

sub wigtobigwig_path {
    my $self = shift;
    return $self->{_wig2bigwig_path} if exists $self->{_wig2bigwig_path};
    return $self->{_wig2bigwig_path} ||= $self->search_for_binary('wigToBigWig');
}

sub search_for_binary {
    my $self   = shift;
    my $target = shift;
    my @path   = split ':',$ENV{PATH};
    for my $d (@path) {
	my $tgt = File::Spec->catfile($d,$target);
	return  $tgt if -e $tgt && -x _;
    }
    return;
}

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

1;
