=head1 NAME

Bio::DB::Das::BioSQL::PartialSeqAdaptor - class that helps to use custom object adaptors

=head1 SYNOPSIS

    This is a private class.

=head1 DESCRIPTION

This is a custom driver class for sequence objects retrieved from BioDB.
We don't want to retrieve all the features at initialization time, because
it may be slow. Thus, they are fetched by calling slow_attach_children 
if necessary.

=head1 CHANGES

=head2 Mon Mar 15 10:21:17 EST 2004

=over 1

=item Fixed slow_attach_children() to retrieve partially overlapping features.

=back

=head1 AUTHOR - Vsevolod (Simon) Ilyushchenko

Email simonf@cshl.edu

=cut

package Bio::DB::Das::BioSQL::PartialSeqAdaptor;

use strict;
use base 'Bio::DB::BioSQL::SeqAdaptor';

sub new
{
    my ($proto, @args) = @_;
    my $self = $proto->SUPER::new(@args);
    
    $self->dbd()->objrel_map->{$proto} = "bioentry";

    return $self;
}

sub attach_foreign_key_objects
{
    my ($self, @args) = @_;
    $self->SUPER::attach_foreign_key_objects(@args);
}

sub attach_children{
    my ($self,$obj) = @_;
    
    my $ok = $self->Bio::DB::BioSQL::PrimarySeqAdaptor::attach_children($obj);
    # we need to associate annotation
    my $annadp = $self->db()->get_object_adaptor("Bio::AnnotationCollectionI");
    my $qres = $annadp->find_by_association(-objs => [$annadp,$obj]);
    my $ac = $qres->next_object();
    if($ac) {
	$obj->annotation($ac);
    }
    # done
    return $ok;
}

#We will only retrive features that lie within a certain range.
sub slow_attach_children
{
    my ($self, $obj, $start, $end) = @_;
    
    return if $obj->{children_attached};

    my $where = ["AND", "t1.entire_seq = ?"];
    my $values = [$obj->primary_key];
    if ($start && $end)
    {
        push @$where, ("t2.start < ?",  "t2.end > ?");
        push @$values, ($end+1, $start-1);
    }
    my $query = Bio::DB::Query::BioQuery->new(
        -datacollections => ["Bio::SeqFeatureI t1", "Bio::LocationI t2", "Bio::SeqFeatureI=>Bio::LocationI"],
        -where => $where);
    
    $query->querytype("select distinct"); #New code - does not work yet.
    $query->flag("distinct", 1); #Old code - works
    
    my $adp = $self->db()->get_object_adaptor("Bio::SeqFeatureI");    
    my $qres = $adp->find_by_query($query,
        -name => "FIND FEATURE BY SEQ",
        -values => $values);
    
    while(my $feat = $qres->next_object()) {
	$obj->add_SeqFeature($feat);
	# try to cleanup a possibly redundant namespace in remote location
	# seq IDs - we don't usually print that although we should
	if(my $ns = $obj->namespace()) {
	    my @locs = $feat->location->each_Location();
	    foreach my $subloc (@locs) {
		if($subloc->is_remote()) {
		    my $seqid = $subloc->seq_id();
		    if($seqid =~ s/^$ns://) {
			$subloc->seq_id($seqid);
		    }
		}
	    }
	    # set top object seqid
	    my $toploc = $feat->location();
	    if($toploc && 
	       (! $toploc->is_remote()) && (! $toploc->seq_id())) {
		$toploc->seq_id($obj->accession_number().
				($obj->version ? ".".$obj->version : ""));
	    }
	}
    }
    $obj->{children_attached} = 1;
}

1;
