# $Id: Type.pm,v 1.2 2005-01-11 22:22:51 allenday Exp $
#
# BioPerl module for Bio::DB::Das::Chado::Type
#
# Cared for by Allen Day <allenday@ucla.edu>
#
# Copyright Allen Day
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::DB::Das::Chado::Type - DESCRIPTION of Object

=head1 SYNOPSIS

Give standard usage here

=head1 DESCRIPTION

Describe the object here

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the evolution of this and other
Bioperl modules. Send your comments and suggestions preferably to
the Bioperl mailing list.  Your participation is much appreciated.

  bioperl-l@bioperl.org              - General discussion
  http://bioperl.org/MailList.shtml  - About the mailing lists

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
of the bugs and their resolution. Bug reports can be submitted via
the web:

  http://bugzilla.bioperl.org/

=head1 AUTHOR - Allen Day

Email allenday@ucla.edu

Describe contact details here

=head1 CONTRIBUTORS

Additional contributors names and emails here

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut


# Let the code begin...

package Bio::DB::Das::Chado::Type;
use strict;
#use base qw(Bio::Ontology::Term Bio::Das::FeatureTypeI);
use base qw(Bio::Ontology::Term); #Bio::Das::FeatureTypeI can's use this, why???????????

=head2 new

 Title   : new
 Usage   : my $obj = new Bio::DB::Das::Chado::Type();
 Function: Builds a new Bio::DB::Das::Chado::Type object 
 Returns : an instance of Bio::DB::Das::Chado::Type
 Args    :


=cut

sub new {
  my($class,@args) = @_;
  my $self = $class->SUPER::new(@args);
  return $self;
}

=head1 Bio::Das::FeatureTypeI interface methods

=head2 name

 Title   : name
 Usage   : $obj->name($newval)
 Function: name of the type
 Returns : value of name (a scalar)
 Args    : on set, new value (a scalar or undef, optional)

 This method is inherited from Bio::Ontology::Term

=cut


=head2 accession

 Title   : accession
 Usage   : $obj->accession($newval)
 Function: database accession of the type
 Returns : value of accession (a scalar)
 Args    : on set, new value (a scalar or undef, optional)

 This method is aliased to identifier(), which is inherited
 from Bio::Ontology::Term

=cut

*accession = \&Bio::Ontology::Term::identifier;

=head2 definition

 Title   : definition
 Usage   : $obj->definition($newval)
 Function: definition of the type
 Returns : value of definition (a scalar)
 Args    : on set, new value (a scalar or undef, optional)

 This method is inherited from Bio::Ontology::Term

=cut

=head2 parents

 Title   : parents
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub parents {
  my ($self,$child) = @_;
  return $child->ontology->get_all_parents($child);
}

=head2 children

 Title   : children
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub children {
  my ($self,$parent) = @_;
  return $parent->ontology->get_child_terms($parent);
}

=head2 relationship

 Title   : relationship
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub relationship {
  my ($self,$child) = @_;

  my $ontology = $self->ontology();
  my($rel) = grep {$_ if $self->match($_->object)} $ontology->get_relationships($child);

  if($rel){
    return $rel->predicate();
  }

  return undef;
}

=head2 equals

 Title   : equals
 Usage   : implemented in Bio::Das::FeatureTypeI

=cut

=head2 is_descendent

 Title   : is_descendent
 Usage   : implemented in Bio::Das::FeatureTypeI

=cut

=head2 is_parent

 Title   : is_parent
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub is_parent {
  my ($self,$term,$pred) = @_;

  if($pred){
    #we need to figure out how to handle predicates
    $self->throw_not_implemented();
  }

  my $ontology = $self->ontology();
  #need to change, match() won't be implmented by vanilla Bio::Ontology::Term objects
  my $is_parent = 0;
  $is_parent = grep { $_->match($term) } $ontology->get_parent_terms($self);

  return $is_parent;
}

=head2 match

 Title   : match
 Usage   : implmeented in Bio::Das::FeatureTypeI

=cut

=head2 add_child

 Title   : add_child
 Usage   : defers to Bio::Ontology::Ontology->add_relationship(child,predicate,parent)

=cut

sub add_child {
  my ($self,$child) = @_;

  my $ontology = $self->ontology();
  return $ontology->add_relationship($child,'child_of',$self); #this will fail
}

=head2 delete_child

 Title   : delete_child
 Usage   : not implemented, will defer to Bio::Ontology::Ontology when
           delete_relationship() is implemented.
=cut

sub delete_child {
  my ($self,@args) = @_;
  $self->throw_not_implemented();
}

=head1 Our methods

=head2 cvterm_id

 Title   : cvterm_id
 Usage   : $obj->cvterm_id($newval)
 Function: PK for this object in cvterm table
 Example : 
 Returns : value of cvterm_id (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub cvterm_id{
    my $self = shift;

    return $self->{'cvterm_id'} = shift if @_;
    return $self->{'cvterm_id'};
}

=head2 ontology

 Title   : ontology
 Usage   : $obj->ontology($newval)
 Function: PK for this object in cvterm table
 Example : 
 Returns : value of ontology (a scalar)
 Args    : on set, new value (a scalar or undef, optional)


=cut

sub ontology{
    my $self = shift;

    return $self->{'ontology'} = shift if @_;
    return $self->{'ontology'};
}

1;
