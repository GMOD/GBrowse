# $Id: GFFhelper.pm,v 1.17 2004-01-24 16:57:58 sheldon_mckay Exp $

=head1 NAME

Bio::Graphics::Browser::GFFhelper -- Helps gbrowse feature editors/loaders handle GFF

=head1 SYNOPSIS
  
  package Bio::Graphics::Browser::Plugin::MyPlugin;

  use vars qw/@ISA $ROLLBACK/;

  @ISA = qw/ Bio::Graphics::Browser::Plugin 
             Bio::Graphics::Browser::GFFhelper /;
  
  $ROLLBACK = '/tmp/';

  # other plugin subs skipped...

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

    # don't save a persistent rb_id, look for a CGI param each time
    my $rollback = $self->config_param('rb_id');
    
    my $gff = $self->rollback($rollback);
    
    # this is a rollback to an earlier version of an existing segment
    # we don't need DNA, just the GFF
    $gff;
  }

  sub gff_from_file {
    my $self = shift;
    my $conf = $self->configuration;
    my $filename = $conf->{file};

    # get a gff string file
    open GFF, "<$filename";
    my $gff = join '', (<GFF>);
    close GFF;  

    # set a flag to add a header to the GFF
    $self->{header} = 1;

    # set sequence name in case the GFF does not have it
    $self->refseq('L16622');
  
    # process the GFF, convert it to GFF3, get the sequence
    my ($newGFF, $dna) = $self->read_gff($gff);
    return ($newGFF, $dna);
  }
  
=head1 DESCRIPTION

This modules helps process GFF prior to loading into the database and provides
rollback capability for feature editors/loaders

=head2 GFF help

This module deals with the different GFF dialects and changes the, to GFF3 format 
to avoid breaking the Bio::DB::GFF parser.  It also allows conversion of Bio::DB::GFF::Feature 
objects to Bio::SeqFeature::Generic objects, which is required for consistent
feature and attribute handling across different input/output formats.

=head2 Sequence Extraction

If DNA is appended to the GFF, it will be extracted.  The read_gff method returns a 
string containing processed GFF and also a sequence string

=head2 Rollbacks

The state of a segment can be captured and saved in case the user wishes to reload 
to an earlier version of the segment after editing/deleting features.  The last 
five states are saved in a round-robin rotation.  In plugins that inherit methods from
this module, the $ROLLBACK variable must be defined with a string containing the 
path to a directory where the web user ('apache', 'nobody', etc.) has write access.  
If $ROLLBACK is undefined, the rollback functionality is disabled.

=head1 FEEDBACK

See the GMOD website for information on bug submission http://www.gmod.org

=head1 AUTHOR - Sheldon McKay

Email smckay@bcgsc.bc.ca

=cut

package Bio::Graphics::Browser::GFFhelper;

use strict;
use Bio::Root::Root;
use Bio::SeqFeature::Generic;
use IO::String;
use Bio::DB::GFF::Homol;

use vars qw/ @ISA /;

@ISA = qw/ Bio::Root::Root /;


sub read_gff {
    my ($self, $text) = @_;
    $self->throw("No GFF to parse") unless $text;
    my $seqid = $self->refseq;

    my (@seq, $gff) = ();

    # give up if the GFF is not correctly formatted
    $self->throw("This does not look like GFF to me\n$text")
	if $text !~ /^(\S+\s+){7}\S+/m || $text =~ /^LOCUS|^FT/m;
    
    for ( split "\n", $text ) {
	# save the sequence
	push @seq, $_ and next if /^>/ || !/\S\s+\S/;

	# interpret the header
	if ( /\#\#sequence-region\s+(\S+)\s+(-?\d+)\s+(-?\d+)/ ) {
	     $self->refseq($1);
	     $self->start($2);
	     $self->end($3);
	}
        
        # save the GFF
	$gff .= $_ . "\n" if /\S\s+\S/ && !/^(>|##)/;
    }

    # dump fasta header and assemble the sequence
    shift @seq if @seq && $seq[0] =~ />/;
    $self->seq(join '', @seq);

    # make sure the sequence name and range are defined
    unless ( $self->start && $self->end && $self->refseq) {
        $self->get_range($gff);
    }

    return $self->fix_gff($gff);
}

# Create a list of pseudo Bio::DB::GFF::Feature objects
# the attributes will be saved as a hash rather
# than a canned database query
sub parse_gff {
    my ($self, $gff) = @_;
    my @feats = ();
    for ( split "\n", $gff ) {
	next if /^\#\#/ || !/\t/ || /reference\tcomponent/i;
        push @feats, $self->parse_gff_line($_);
    }    
    @feats;
}

sub parse_gff_line {
    my ($self, $gff_line) = @_;
    my $groupobj;
    my $seqid = $self->refseq;
    my $db = $self->database;
    $gff_line =~ s/\"//g;

    my ( $ref, $source, $method, $start, $stop, 
         $score, $strand, $phase, $group) = split "\t", $gff_line;
    next unless defined($ref) && defined($method) && defined($start) && defined($stop);
    foreach (\$score,\$strand,\$phase) {
	undef $$_ if $$_ eq '.';
    }
    
    $seqid ||= $ref;

    my ($gclass,$gname,$tstart,$tstop,$attributes) = $db->split_group($group);
    
    # create a group or target object
    if ( $tstart && $tstop ) {
	$groupobj = FakeHomol->new($gclass,$gname,$tstart,$tstop);
    }
    elsif ( $gname && $gclass ) {
	$groupobj = Bio::DB::GFF::Featname->new($gclass,$gname);
    }

    # create a Bio::DB::GFF::Feature
    my @args = ( undef, $seqid, $start, $stop, $method );
    push @args, ($source, $score, $strand, $phase, undef );
    
    my $f = Bio::DB::GFF::Feature->new(@args);
    
    $f->group($groupobj) if $groupobj;
    
    # save the attributes!
    $f->{attributes} = $attributes;
    $f;
}


# rework the GFF feature attributes into GFF3
sub new_gff_string {
    my ($self, $f, $version) = @_;
    $f->version($version || 3);
    my @gff = split "\t", $f->gff_string(1);
    my $segment = $self->segments->[0];
    my $source = $self->{source} || $f->source_tag;
    my $refseq = $self->refseq   || $segment->ref;
    my $atts   = $f->{attributes};
    
    $gff[1] = $source if $source;
    $gff[0] = $refseq if $refseq;
    chomp $gff[-1];

    my @group_field;
    for ( @$atts ) {
	push @group_field, _escape($_->[0]) . '=' . _escape($_->[1]);
    }    
    my $group_field = join ';', @group_field;

    my $gff = join "\t", @gff;
    
    if ( $group_field ) {
	$gff .= $f->class ? ";$group_field" : "\t$group_field";
    }

    $gff;
}

sub fix_gff {
    my ($self, $gff) = @_;

    # convert features to Bio::SeqFeature::Generic objects
    my @feats = $self->parse_gff($gff);

    # rebuild the GFF as GFF3
    my @gff = map { $self->new_gff_string($_) } @feats;    
    
    # add a header if required
    unshift @gff, $self->gff_header(3) if $self->{header};
    return (join "\n", @gff) . "\n";
}

sub gff_header {
    my $self  = shift;
    my $ver   = shift || 3;
    my $exists = shift;
    my $date  = localtime;
    my $start = $self->start || 0; 
    my $end   = $self->end;
    my $ref   = $self->refseq;
    my $seq   = $self->seq || '';
    $start = 1 if $start > 1;
    $end   = (length $seq) + 1 if $end < length $seq;

    my $header = "##gff-version $ver\n##date $date\n";
    
    # don't give GFF.pm this line if the segment exists
    $header   .= "##sequence-region $ref $start $end\n" unless $exists;
    
    $header .= "##source Bio::Graphics::Browser::GFFhelper.pm";
    $header;
}

sub origin {
    my ($self, $gff) = @_;
    my $desc  = $self->{desc};
    my $start = 1;
    my $end   = length $self->seq;
    my $ref   = $self->refseq;
    my $src   = $self->{source};
    
    my $group = "ID=Accession:$ref";
    $group .= ';Note=' . _escape($desc) if $desc;
    $gff . join ("\t", $ref, $src, 'origin', $start, $end, '.', '.', '.', $group);
}

# add a reference component for new sequences
# not currently used, will probably be deprecated
sub component {
    my ($self, $gff) = @_;
    chomp $gff;
    my $seq   = $self->seq;
    my $start = 1;
    my $end   = length $seq;

    my @row = ($self->refseq, 'reference', 'Component', $start); 
    push @row, ($end, '.', '.', '.', 'ID=Sequence:' . $self->refseq);
    
    #$gff .= "\n" . join "\t", @row;
    my $row = join "\t", @row;
    my $ref = $self->refseq;
    $gff =~ s/^($ref.+)/$row\n$1/m;
    $gff;
}

# convert the feature segment into a Bio::SeqFeature::Generic object
sub gff2Generic {
    my ($self, $f) = @_;

    my $feat = Bio::SeqFeature::Generic->new( -primary_tag => $f->primary_tag,
					      -source_tag  => $f->source_tag,
					      -phase       => $f->phase,
					      -score       => $f->score,
					      -start       => $f->start,
					      -end         => $f->end,
					      -strand      => $f->strand );

    my $att = $self->process_attributes($f);
    for my $t ( keys %$att ) {
	for my $v ( @{$att->{$t}} ) {
	    $feat->add_tag_value( $t => $v );
	}
    }
    
    $feat;
}


sub process_attributes {
    my ($self, $f) = @_;
    my $mode = $self->configuration->{mode};
    my $att = $f->attributes;

    # add database identifiers for select mode
    $att->{database_id} = [$f->id] if $mode eq 'selected';
    
    # handle GFF2.5 targets
    if ( my $t = $f->target ) {
	my $tclass = $t->class;
	my $tname  = $t->name;
	$att->{Target} = "$tclass:$tname";
	$att->{tstart} = [$t->start];
	$att->{tend}   = [$t->end];
    }
    elsif ( $f->group )  {
	my $class = $f->class;
	my $name  = $f->name;
	push @{$att->{$class}}, $name if $class && $name;
    }
    for ( keys %$att ) { 
	for my $v ( @{$att->{$_}} ) {
	    $v =~ s/;/,/g;
	    $v =~ s/\"|\s+$//g;
	}
    }

    $att;
}


####################################
# Sequence attribute getter/setters 
####################################
*ref = *refseq;
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

# we need to get the sequence name and range if it was not specified
# elsewhere
sub get_range {
    my ($self, $gff) = @_;
    my @nums = ();


    for ( split "\n", $gff ) {
        next if /\#/;
	my @word = split "\t", $_;
	next if !$word[3] || !$word[4];
        $self->refseq($word[0]) 
	    unless $word[0] =~ /\.|SEQ/ || $self->refseq;
	push @nums, @word[3,4] if $word[3] =~ /^\d+$/ && $word[4] =~ /^\d+$/;
    }

    # give up if the sequence has no name
    $self->throw("A Sequence ID is required for this GFF file")
	unless $self->refseq;
    
    my @sorted = sort { $a <=> $b } @nums if @nums;
    $self->start($sorted[0]);
    $self->end($sorted[-1]);
}
####################################


###################################
# Rollback functions
###################################

sub save_state {
    my ($self, $segment) = @_;
    return unless $segment;
    my $conf = $self->configuration;
    my $loc  = $self->{rb_loc};
    my $outfile = $loc . 'rollback_' . time;
    my $date = localtime;

    # save the rollback info 
    open OUT, ">$outfile"
        || $self->throw("Unable to save state; Does the web user " .
                        "have write permission for the rollback location?");

    print OUT "##$outfile \"$date\" $segment\n";
    for ( $segment->features ) {
	$_->version(3);
	print OUT $_->gff_string unless $_->method =~ /Component/i;
    }
    close OUT;
    
    my $rbfiles = $loc . 'rollback_*';
    my $lister = $^O !~ /win32/i ? '\ls' : 'dir /B';
    my @list = sort `$lister $rbfiles`;

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
	$self->throw("Rollback file '$file' not found") unless -e $file;

	open FILE, "<$file";
	my @gff = <FILE>;
        close FILE;
        
	shift @gff;
	my $gff = join '', @gff;
	$self->get_range($gff);
        $gff =  $self->gff_header(3,1) . "\n$gff"; # 1 flag means no sequence region line
	return $gff;
    }
    else {
	my $rbfiles = $loc . 'rollback_*';
	my $typer = $^O !~ /win32/i ? 'cat' : 'type';
	my @list = sort `$typer $rbfiles`;

	my @file = `cat ${loc}rollback_* | grep '##' |grep rollback`;
	
	my $rb = {};
	for ( @file ) {
	    my ($file, $time, $segment) = /^\#\#(\S+)\s+"(.+)"\s+(\S+)/;
	    $rb->{$file}->{time} = $time;
	    $rb->{$file}->{segment} = $segment;
	}

	return $rb;
    }
}


# called by configure_form methods if req'd
sub rollback_form {
    my ($self, $msg, $filter) = @_;
    my $rb   = $self->rollback;
    my $name = $self->config_name('rb_id');

    return 0 unless $rb;    

    my @out;
    for ( sort {$b cmp $a} keys %{$rb} ) {
        my $seg  = $rb->{$_}->{segment};
        # just get relevent segments if the filter it defined
        next if $filter && $seg !~ /$filter/i;
	my $date = $rb->{$_}->{time};
        push @out, "<option value=$_>$seg $date</option>\n";
    }

    my $help =  qq(<a onclick="alert('$msg')" href="javascript:void(0)">[?]</a>);

    return  "\n<table>\n<tr class=searchtitle><td><font color=black><b>" .
	    "Restore saved features</td></tr>\n<tr><td class=" .
	    "searchbody>\n<select name=$name>\n<option value=''> -- Roll " .
            "back to saved features -- </option>\n" .
	    (join '', @out) . "</select> $help\n</td></tr></table>\n";
}

###################################################

# internal method stolen from Bio::DB::GFF
# GFF3-ify our attributes
sub _escape {
    my $toencode = shift;
    $toencode    =~ s/([^a-zA-Z0-9_. :?^*\(\)\[\]@!-])/uc sprintf("%%%02x",ord($1))/eg;
    $toencode    =~ tr/ /+/;
    $toencode;
}


1;


package FakeHomol;

sub new {
    my $caller = shift;
    my ( $class, $name, $start, $stop ) = @_;
    my $self   = { class => $class,
                   name  => $name,
	           start => $start,
                   stop  => $stop };
    return bless $self;
}

sub start {
    my ($self, $start) = @_;
    $self->{start} ||= $start;
    $self->{start};
}

*stop = *end;
sub end {
    my ($self, $end) = @_;
    $self->{stop} ||= $end;
    $self->{stop};
}

sub class {
    my ($self, $class) = @_;
    $self->{class} ||= $class;
    $self->{class};
}

sub name {
    my ($self, $name) = @_;
    $self->{name} ||= $name;
    $self->{name};
}

1;
