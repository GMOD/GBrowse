# BioPerl module for Bio::DB::BioSQL::BioDatabaseAdaptor
#
# Cared for by Ewan Birney <birney@ebi.ac.uk>
#
# Modified by Vsevolod (Simon) Ilyushchenko (simonf@cshl.edu)
#
# Copyright Ewan Birney
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::DB::BioSQL::BioDatabaseAdaptor - Low level interface for Bio::DB::BioDB classes

=head1 SYNOPSIS

This is a low level interface to Bio::DB::BioDB classes

=head1 DESCRIPTION

Private class.

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the evolution of this
and other Bioperl modules. Send your comments and suggestions preferably
 to one of the Bioperl mailing lists.
Your participation is much appreciated.

  bioperl-l@bio.perl.org

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
 the bugs and their resolution.
 Bug reports can be submitted via email or the web:

  bioperl-bugs@bio.perl.org
  http://bio.perl.org/bioperl-bugs/

=head1 AUTHORS - Ewan Birney, Vsevolod (Simon) Ilyushchenko

Emails birney@ebi.ac.uk, simonf@cshl.edu

=cut


# Let the code begin...


package Bio::DB::Das::BioSQL::BioDatabaseAdaptor;
use strict;

use Bio::DB::BioDB;


=head2 new_from_registry

 Title   : new_from_registry
 Usage   :
 Function: Initialize the Bio::DB::BioDB front end class
 Example :
 Returns : 
 Args    :


=cut

sub new_from_registry{
   my ($class, %conf) = @_;
   
   #Add our own directory where DBAdaptor is located.
   Bio::DB::BioDB->add_db_mapping("FastBioSQL", "Bio::DB::Das::BioSQL::");

   my $db = Bio::DB::BioDB->new(
                                -database => 'FastBioSQL',
                                -dbname=>$conf{'dbname'},
                                -host=>$conf{'location'},
                                -driver=>$conf{'driver'},
                                -user=>$conf{'user'},
                                -pass=>$conf{'pass'},
                                -port=>$conf{'port'}
                                );

    my $self = bless {}, ref($class) || $class;

   $self->namespace($conf{'namespace'});
   $self->version($conf{'version'});
   $self->db($db);
   
   return $self;
}


=head2 fetch_Seq_by_accession

 Title   : fetch_Seq_by_accession
 Usage   :
 Function: Return a BioDB object corresponding to the given accession number.
 Example :
 Returns : A segment with the given accession number
 Args    :


=cut

sub fetch_Seq_by_accession{
    my ($self,$acc) = @_;

    use Bio::Seq::SeqFactory;
    use Bio::Seq;
    
    my $seq;
    
    #The difference between using Bio::Seq an Bio::PrimarySeq would have been that the latter
    #will not pull in all the features and thus slow down the retrieval.
    #However, using PartialSeqAdaptor helps to delay loading features even for Bio::Seq.
    
    $seq = Bio::Seq->new(-namespace => $self->namespace, -accession_number => $acc, version => $self->version);
#    $seq = Bio::PrimarySeq->new(-namespace => $self->namespace, -accession_number => $acc, version => $self->version);
    
    my $adp = $self->db->get_object_adaptor($seq);
    my $result = $adp->find_by_unique_key($seq);
    
    return $result;
}

#sub top_SeqFeatures{
#    my ($self,$segment) = @_;
#    
#    return $segment->top_SeqFeatures;
#}

sub db
{
    my $self = shift;
    if (@_) {$self->{db} = shift;}
    return $self->{db};
}

sub namespace
{
    my $self = shift;
    if (@_) {$self->{namespace} = shift;}
    return $self->{namespace};
}

sub version
{
    my $self = shift;
    if (@_) {$self->{version} = shift;}
    return $self->{version};
}

1;
