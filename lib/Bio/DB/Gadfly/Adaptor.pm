package Bio::DB::Gadfly::Adaptor;

# $Version$

use strict;
use Bio::DasI;
use Bio::Root::Root;
use Bio::DB::GFF::Util::Rearrange;
use GxAdapters::ConnectionManager;

use vars '@ISA','$VERSION';
@ISA     = qw(Bio::Root::Root Bio::DasI);
$VERSION = '0.01';

=head1 Bio::DB::Gadfly::Adaptor - DasI adaptor for GadFly database

=head1 SYNOPSIS

=head1 METHODS

Methods follow

=cut

=head2 $db = Bio::DB::Gadfly::Adaptor->new(@args)

Create a connection to the indicated database.  Arguments are
identical to
GxAdapters::ConnectionManager->get_adapter(). e.g. "mysql:gadfly@localhost".
Returns a Bio::DB::Gadfly::Adaptor object.

=cut

sub new {
  my $class = shift;
  my $self  = bless {},ref($class) || $class;
  my $db    = GxAdapters::ConnectionManager->get_adapter(@_)
    or $self->throw("GxAdapters::ConnectionManager failed to establish connection to @_");
  $self->gx($db);
}

=head2 $gx_adaptor = $db->gx([$new_adaptor])

Get or set the underlying GxAdapter (note spelling difference).

=cut

sub gx {
  my $self = shift;
  my $d    = $self->{gx};
  $self->{gx} = shift if @_;
  $d;
}

=head2 $dbh = $db->dbh

Get the underlying database

=cut

sub dbh {
  my $self = shift;
  my $gx   = $self->gx or return;
  return $gx->dbh;
}

=head2 @segments = $db->segment(@args);

Return a series of Bio::Das::SegmentI objects.

Arguments are -option=>value pairs as follows:

        -name         ID of the landmark sequence.

        -start        Start of the segment relative to landmark.  Positions
                      follow standard 1-based sequence rules.  If not specified,
                      defaults to the beginning of the landmark.

        -end          End of the segment relative to the landmark.  If not specified,
                      defaults to the end of the landmark.

=cut

sub segment {
  my $self = shift;
  my ($name,$start,$end) = rearrange([qw(NAME START END)]);
  my $gx   = $self->gx;

  defined $name or $self->throw('usage: segment(-name=>$name,-start=>$start,-end=>$end)');

  # corresponds to a primary seq
  if (my $obj = gx->get_Seq({name=>$name})) {
    $start = 1             unless defined $start;
    $end   = $obj->length  unless defined $length;
    return Bio::DB::GadFly::Segment->new($obj->name,$start,$end,$gx);
  }

  # corresponds to a feature
  if (my $obj = $gx->get_SeqFeature({name=>$name})) {
    $name  = $obj->src_seq->name;
    return Bio::DB::Gadfly::Segment->new($name,$start,$end,$gx) if defined $start && defined $end;
    $start = 1            unless defined $start;
    $end   = $obj->length unless defined $end;

    if ($obj->strand > 0) {   # relative coordinate calculation made easy
      return Bio::DB::Gadfly::Segment->new($name,$obj->start+$start-1,$obj->start+$end-1,$gx);
    } else {
      return Bio::DB::Gadfly:::Segment->new($name,$obj->start-($end-1),$obj->start-($start-1),$gx);
    }
  }

  # corresponds to something else, but we don't know how to fetch it, so retreat.
  return;
}

=head2 @classes = $db->classes;

Return the namespaces known to the database.

=cut

# hard-coded classes
sub classes {
  return qw(name symbol);
}

=head2 @result = $db->search_notes('search string')

Perform a text search on database.  Result is an array of [$name,$description,$score].

=cut

sub search_notes {
  my $self   = shift;
  my $term   = shift;
  my @terms  = split /\s+/,$term;
  my $search = join 'OR',map {"description=?"} @terms;
  my $sql    = "select name,description from seq where $search";
  my $dbh    = $self->dbh;
  my $sth    = $dbh->prepare($sql) or $self->throw(DBI->errstr);
  $sth->execute(@terms) or $self->throw(DBI->errstr);

  my @result;
  my $term = '('.join('|',@terms).')';
  while (my($name,$description) = $sth->fetchrow_array) {
    my @h = $description =~ /$term/g;
    my $score = 10 * @h;
    push @result,[$name,$description,$score];
  }
  return @result;
}

1;

__END__

=head1 AUTHOR

=head1 SEE ALSO

L<Bio::DB::GFF>,
L<Bio::DasI>,
