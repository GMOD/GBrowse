# $Id: GFFhelper.pm,v 1.1 2003-10-05 06:17:08 sheldon_mckay Exp $

=head1 NAME

Bio::Graphics::Browser::GFFhelper -- Helps gbrowse feature editors/loaders handle GFF

=head1 SYNOPSIS
  
  use Bio::Graphics::Browser::Plugin::Group;
  
  my $refseq = 'L16622';
 
  # get a database handle
  my $db = $self->database;
  my $segment = $db->segment($refseq) || '';

  # get a gff string from somewhere
  open GFF, "</path/to/gff_file";
  my $gff = join '', (<GFF>);
  close GFF;  

  my $loader = Bio::Graphics::Browser::GFFhelper->new( refseq => $refseq, 
			                               gff    => $gff,
			                               header => 1 );
  
  # parse the GFF 
  my ($gff_string, $dna) = $loader->read_gff 
    || die $loader->error;
  
=head1 DESCRIPTION

This modules helps massage GFF before loading into the database.  

It is not designed for external use.

Attribute order may not be consistent in GFF from various sources
but Bio::DB::GFF wants the first key-value pair in column 9 to be class => name.  To avoid 
spurious group assignments, this module goes through each feature's attributes and tries to guess 
the appropriate group to preserve feature containment hierarchies (eg gene->mRNA->CDS).

=head1 FEEDBACK

See the GMOD website for information on bug submission http://www.gmod.org.

=head1 AUTHOR - Sheldon McKay

Email smckay@bcgsc.bc.ca

=cut

package Bio::Graphics::Browser::GFFhelper;

use strict;
use Bio::Root::Root;
use Bio::Tools::GFF;
use CGI ':standard';
use IO::String;

use vars qw/$VERSION @ISA/;

$VERSION = '0.01';
@ISA = qw/ Bio::Root::Root /;


sub new {
    my $caller = shift;
    my %args = @_;
    my $self = \%args;
    $self->{gff} || die "No GFF to process";
    return bless $self;
}

sub read_gff {
    my $self  = shift;
    my $seqid = $self->{refseq} || '';
    my $text  = $self->{gff};
    $self->throw("No GFF to parse") unless $text;

    my (@seq, $gff) = ();

    $self->throw("This does not look like GFF to me")
	if $text !~ /^(\S+\s+){7}\S+/m || $text =~ /^LOCUS|^FT|\.\./m;
    
    for ( split "\n", $text ) {
	# save the sequence
	push @seq, $_ if />/ || !/\S\s+\S/;
	
	# interpret the header
	if ( /##sequence-region\s+(\S+)\s+(-?\d+)\s+(-?\d+)/ ) {
	     $self->{refseq} = $1;
	     $self->{start}  = $2;
	     $self->{end}    = $3;
	}
        
        # no point going on with no sequence ID
	if ( !/##/ && !$self->{refseq} && !$seqid ) {
	     if ( /^(\S+)/ && $1 !~ /\.|SEQ/ ) {
		 $self->{refseq} = $1;
	     }
	     else {
		 $self->throw("A Sequence ID is required for this GFF file");
	     }
	}

        # save the GFF
	$gff .= $_ . "\n" if /\S\s+\S/ && !/>|##/;
    }

    $self->{refseq} ||= $seqid;
    
    # dump fasta header and assemble the sequence
    shift @seq if $seq[0] =~ />/;
    $self->{seq} = join '', @seq;

    # massage the GFF
    $gff =~ s/^\./$self->{refseq}/gm;
    $self->{gff} = $self->fix_gff($gff);
    return $self->{seq} ? ($self->{gff}, $self->{seq}) : $self->{gff};
}

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

sub new_gff_string {
    my ($self, $f) = @_;
    my ($class, $name) = $self->guess_name($f);

    $name =~ s/\"//g if $name !~ /\s+/;
    $name = qq("$name") if $name =~ /\s+/;
    
    my $gff = $f->gff_string;
    my @gff = split "\t", $gff; 
    @gff = @gff[0..7];
    $gff = join "\t", @gff;
    $gff =~ s/^SEQ/$self->{refseq}/gm;    
    
    my @att;
    for ( $f->all_tags ) {
        my ($v) = $f->get_tag_values($_);        
        next if $_ eq $class && $v eq $name;
        $v = qq("$v") if $v =~ /\s/ && $v !~ /\"/;
        push @att, "$_ $v"
    }

    $gff .= "\t$class $name";
    $gff .= ' ; ' . (join ' ; ', @att) if @att;

    $gff;
}

sub fix_gff {
    my ($self, $gff) = @_;

    # find the sequence range if is was not defined
    unless ( $self->{start} && $self->{end} ) {
	my @nums = ();
	for ( split /\n/, $gff ) {
	    my @fields = split /\t/, $_;
	    push @nums, @fields[3..4];
	}
        @nums = sort { $a <=> $b } @nums;
        $self->{start} = $nums[0];
	$self->{end}   = $nums[-1];
    }

    # convert the GFF lines to Bio::SeqFeature objects
    my @feats = $self->parse_gff($gff);

    # rebuild the GFF
    my @gff = map { $self->new_gff_string($_) } @feats;    
    
   # add a header if required
    unshift @gff, $self->gff_header unless $gff[0] =~ /^##/;
    
    return join "\n", @gff;
}

sub gff_header {
    my $self = shift;
    my $date = localtime; 
    
    return '' unless $self->{header};    
    my $header = 
    "##gff-version 2\n" .
    "##date $date\n" .
    "##sequence-region " . 
    (join ' ', ($self->{refseq}, $self->{start}, $self->{end})) . "\n";
    
    return $header if $self->{segment};
    my @row = ($self->{refseq}, 'Reference', 'component', $self->{start}); 
    push @row, ($self->{end}, '.', '.', '.', 'Accession ' . $self->{refseq});
    $header .= join "\t", @row;
    $header;
}

sub guess_name {
    my ($self, $f) = @_;
    my ($class, $name);

    for ( qw/ gene locus_tag standard_name / ) {
        if ( $f->has_tag($_) && !$f->has_tag($f->primary_tag) ) {
            next if $class && $name;
            $class = 'gene';
            ($name) = $f->get_tag_values($_);
        }
    }
    if ( $f->primary_tag =~ /source|origin|component/i ) {
	$class = 'Sequence';
	$name  = $self->{refseq};
    }
    if ( !$name && $f->has_tag($f->primary_tag) ) {
        $class = $f->primary_tag;
        ($name) = $f->get_tag_values($f->primary_tag);
    }
    # kind of nasty but we have to call it something!
    if ( !$name ) {
        $class = $name = $f->primary_tag;
    }
    ($class, $name);
}

1;
