# $Id: GFFhelper.pm,v 1.5 2003-10-13 19:01:45 sheldon_mckay Exp $

=head1 NAME

Bio::Graphics::Browser::GFFhelper -- Helps gbrowse feature editors/loaders handle GFF

=head1 SYNOPSIS
  
  package Bio::Graphics::Browser::Plugin::MyPlugin;

  use vars qw/@ISA $ROLLBACK/;

  @ISA = qw/ Bio::Graphics::Browser::Plugin 
             Bio::Graphics::Browser::GFFhelper /;
  
  $ROLLBACK = '/tmp/';

  sub reconfigure {
     #get the rollback id and other config options...
  }

  sub save_segment {
    my ($self, $segment) = @_;
    return 0 unless $ROLLBACK;
    $self->{rb_loc} ||= $ROLLBACK;
    $self->save_state($segment);
    1;
  }

  sub gff_from_rollback {
    my $self = shift;
    my $conf = $self->configuration;
    my $rollback = $conf->{rb_id};
    my $gff = $self->rollback($rollback);
    $gff;
  }

  sub gff_from_file {
    my $self = shift;
    my $conf = $self->configuration;
    my $filename = $conf->{file};

    # get a gff string from somewhere
    open GFF, "<$filename";
    my $gff = join '', (<GFF>);
    close GFF;  

    # set a flag to add a header to the GFF (if req'd)
    $self->{header} = 1;

    # set sequence name in case the GFF does not have it
    $self->refseq('L16622');
  
    # massage and return the gff and sequence
    my ($newGFF, $dna) = $self->read_gff($gff);
    return ($newGFF, $dna);
  }
  
=head1 DESCRIPTION

This modules helps process GFF prior to loading into the database and provides
rollback capability for feature editors/loaders

=head2 Group Assignments

Attribute order may not be consistent in GFF from various sources. To avoid 
spurious group assignments, this module goes through each feature's attributes 
and tries to guess the appropriate group to preserve feature containment 
hierarchies (eg gene->mRNA->CDS), then places the class:name key value pair in 
the first slot of column 9.  It also adds a header and Component:reference feature
to the GFF if required.

=head2 Sequence Extraction

If DNA is appended to the GFF, it will be extracted.  The read_gff method returns a 
string containing processed GFF and a sequence string

=head2 Rollbacks

The state of a segment can be captured and saved in case the user wishes to rollback 
to an earlier version of the segment.  The last five states are saved in a round robin 
rotation.  The $ROLLBACK variable must be defined with a string containing the path
to a directory where the web user ('apache', 'nobody', 'etc') has write access.  if 
$ROLLBACK is undefined, the rollback functionality is disabled.

=head1 FEEDBACK

See the GMOD website for information on bug submission http://www.gmod.org.

=head1 AUTHOR - Sheldon McKay

Email smckay@bcgsc.bc.ca

=cut

package Bio::Graphics::Browser::GFFhelper;

use strict;
use Bio::Root::Root;
use Bio::Tools::GFF;
use IO::String;

use vars qw/@ISA/;

@ISA = qw/ Bio::Root::Root /;


sub read_gff {
    my $self  = shift;
    my $seqid = $self->refseq || '';
    my $text  = shift;
    $self->throw("No GFF to parse") unless $text;

    my (@seq, $gff) = ();

    # give up if the GFF is not correctly formatted
    $self->throw("This does not look like GFF to me\n$text")
	if $text !~ /^(\S+\s+){7}\S+/m || $text =~ /^LOCUS|^FT/m;
    
    for ( split "\n", $text ) {
	# save the sequence
	push @seq, $_ and next if />/ || !/\S\s+\S/;
	
	# interpret the header
	if ( /##sequence-region\s+(\S+)\s+(-?\d+)\s+(-?\d+)/ ) {
	     $self->refseq($1);
	     $self->start($2);
	     $self->end($3);
	}
        
        # save the GFF
	$gff .= $_ . "\n" if /\S\s+\S/ && !/>|##/;
    }

    # dump fasta header and assemble the sequence
    shift @seq if $seq[0] =~ />/;
    $self->seq(join '', @seq);

    # make sure the sequence name and range are defined
    unless ( $self->start && $self->end && $self->refseq) {
        $self->get_range($gff);
    }

    # fix Artemis-style GFF
    my $refseq = $self->refseq;
    $gff =~ s/^\./$refseq/gm;
    
    return $self->fix_gff($gff);
}

# use Bio::Tools::GFF to create a list of Bio::SeqI compliant objects
sub parse_gff {
    my ($self, $gff) = @_;
    my $fh = IO::String->new($gff);
    my $in = Bio::Tools::GFF->new(-fh => $fh);
    my @feats = ();
    while ( my $f = $in->next_feature ) {
        push @feats, $f;
    }
    return @feats;
}

# rework the GFF feature attributes
sub new_gff_string {
    my ($self, $f) = @_;

    # don't touch similiarity features
    return $f->gff_string if $f->gff_string =~/Target/;

    my ($class, $name) = $self->guess_name($f);
    my $source = $self->{source} || '';

    $name = qq("$name") if $name =~ /\s+/;
    
    # strip away attributes
    my $gff = $f->gff_string;
    my @gff = split "\t", $gff; 
    @gff = @gff[0..7];
    $gff = join "\t", @gff;

    # fix column 1
    my $refseq = $self->refseq;
    $gff =~ s/^SEQ/$refseq/gm;    
    
    # manipulate attributes
    my @att;
    for ( $f->all_tags ) {
        my ($v) = $f->get_tag_values($_);        
        
        # skip the class attribute
        next if $_ eq $class && $v eq $name;

        $v = qq("$v") if $v =~ /\s/ && $v !~ /\"/;
        push @att, "$_ $v"
    }

    # add the group assignment
    push @att, "$class $name" if $class && $name;
    $gff .= "\t" . (join ' ; ', @att) if @att;
    
    # fix the source field
    if ( $source ) {
	my $gff_src = (split /\s+/, $gff)[1];
	$gff =~ s/$gff_src/$source/;
    }		
    
    $gff;
}

sub fix_gff {
    my ($self, $gff) = @_;

    # convert the GFF lines to Bio::SeqFeature objects
    my @feats = $self->parse_gff($gff);

    # rebuild the GFF
    my @gff = map { $self->new_gff_string($_) } @feats;    
    
    # add a header if required
    unshift @gff, $self->gff_header if $self->{header};
    return join "\n", @gff;
}

# add a GFF header if required
sub gff_header {
    my $self = shift;
    my $date = localtime; 
    
    my $header = 
    "##gff-version 2\n" .
    "##date $date\n" .
    "##sequence-region " . 
    (join ' ', ($self->refseq, $self->start, $self->end));
    
    return $self->database->segment($self->refseq) 
	? $header : $self->component($header); 
}


# add a reference component for new sequences
sub component {
    my ($self, $header) = @_;
    my @row = ($self->refseq, 'reference', 'Component', $self->start); 
    push @row, ($self->end, '.', '.', '.', 'Sequence ' . $self->refseq);
    $header .= join "\t", @row;
    $header;
}

# handle group assignments
sub guess_name {
    my ($self, $f) = @_;
    my ($class, $name);

    # is the feature part of a gene?
    for ( qw/ Gene gene Locus_tag locus_tag Standard_name standard_name / ) {
        if ( $f->has_tag($_) && !$f->has_tag($f->primary_tag) ) {
            next if $class && $name;
            $class = 'gene';
            ($name) = $f->get_tag_values($_);
        }
    }

    # is it a scaffold or source feature?
    if ( $f->primary_tag =~ /source|origin|component/i ) {
	$class = 'Sequence';
	$name  = $self->{refseq};
    }

    # is the class name the same as the feature name?
    if ( !$name && $f->has_tag($f->primary_tag) ) {
        $class = $f->primary_tag;
        ($name) = $f->get_tag_values($f->primary_tag);
    }

    ($class, $name);
}


####################################
# Sequence attribute getter/setters 
####################################
sub refseq {
    my ($self, $id) = @_;
    $self->{seq}->{id} ||= $id;
    $self->{seq}->{id};    
}

sub start {
    my ($self, $start) = @_;
    $self->{seq}->{start} ||= $start;
    $self->{seq}->{start};
}

sub end {
    my ($self, $end) = @_;
    $self->{seq}->{end} ||= $end;
    $self->{seq}->{end};
}

sub seq {
    my ($self, $seq) = @_;
    $self->{seq}->{seq} ||= $seq;
    $self->{seq}->{seq};
}

sub get_range {
    my ($self, $gff) = @_;
    my @nums = ();


    for ( split "\n", $gff ) {
	my @word = split "\t", $_;
        $self->{seq}->{id} ||= $word[0] if $word[0] !~ /\.|SEQ/;
	push @nums, @word[3,4];
    }

    # give up if the sequence has no name
    $self->throw("A Sequence ID is required for this GFF file")
	unless $self->{seq}->{id};
    
    my @sorted = sort { $a <=> $b } @nums;
    $self->start($sorted[0]);
    $self->end($sorted[-1]);
}
####################################


sub save_state {
    my ($self, $segment) = @_;
    my $conf = $self->configuration;
    my $loc  = $self->{rb_loc};
    my $outfile = $loc . 'rollback_' . time;
    my $date = localtime;

    # save the rollback info 
    open OUT, ">$outfile"
        || $self->throw("Unable to save state; Does the web user " .
                        "have write permission for the rollback location?");

    print OUT "##$outfile \"$date\" $segment\n";
    print OUT map { $_->gff_string, "\n" } $segment->features;
    close OUT;
    
    my $rbfiles = $loc . 'rollback_*';
    
    # not cross-platform
    my $list = `echo $rbfiles`;
    my @list = sort split /\s+/, $list;

    if ( @list > 5 ) {
	my $file  = shift @list;
	unlink $file || $self->throw("file not deleted", $!);
    }
}


sub rollback {
    my ($self, $file) = @_;
    my $loc = $self->{rb_loc};
    my $conf = $self->configuration;

    if ( $file ) {
	$self->throw("Rollback file not found") unless -e $file;        
	# not cross-platform
	my @gff = `cat $file`;
        
	shift @gff;
        my $gff = join '', @gff;
        $self->get_range($gff);
        return $self->fix_gff($gff);
    }
    else {
	my @file = `cat ${loc}rollback_* | grep '##'`;
	
	my $rb = {};
	for ( @file ) {
	    my ($file, $time, $segment) = /^\#\#(\S+)\s+"(.+)"\s+(\S+)/;
	    $rb->{$file}->{time} = $time;
	    $rb->{$file}->{segment} = $segment;
	}

	return $rb;
    }
}

sub rollback_form {
    my ($self, $msg) = @_;
    my $rb   = $self->rollback;
    my $name = $self->config_name('rb_id');

    return 0 unless $rb;    

    my @out;
    for ( sort keys %{$rb} ) {
        my $seg  = $rb->{$_}->{segment};
        my $date = $rb->{$_}->{time};
        push @out, "<option value=$_>$seg $date</option>\n";
    }

    my $help =  qq(<a onclick="alert('$msg')">[?]</a>);


    return  "\n<table>\n<tr class=searchtitle><td><font color=black><b>" .
	    "Restore saved features</td></tr>\n<tr><td class=" .
	    "searchbody>\n<select name=$name>\n<option value=''> -- Roll " .
            "back to saved features -- </option>\n" .
	    (join '', @out) . "</select> $help\n</td></tr></table>\n";
}

1;


