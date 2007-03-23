# BioPerl module for Bio::DB::BioSQL::BioDatabaseAdaptor
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

 http://bugzilla.bioperl.org

=head1 AUTHORS - Ewan Birney, Vsevolod (Simon) Ilyushchenko

Emails birney@ebi.ac.uk, simonf@cshl.edu

=cut


# Let the code begin...


package Bio::DB::Das::BioSQL::BioDatabaseAdaptor;
use strict;

use Bio::DB::BioDB;
use Bio::DB::Query::BioQuery;

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

sub fetch_Seq_by_accession
{
  my ( $self, $acc ) = @_;
  my $namespace = $self->namespace;
  my $version   = $self->version;
  my $query = Bio::DB::Query::BioQuery->new(
       -datacollections =>
         [ "Bio::SeqI seq", "Bio::DB::Persistent::BioNamespace=>Bio::SeqI db" ],
       -where => [ "db.namespace ='$namespace'", "seq.accession_number = '$acc'", $version && $version < 100 ? ("seq.version = '$version'") : () ]
  );

  my $adp     = $self->db->get_object_adaptor("Bio::Seq");
  my @results = @{$adp->find_by_query($query)->each_Object};

  return  wantarray ? @results : $results[0];
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
