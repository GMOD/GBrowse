package Bio::Graphics::Browser::Karyotype;

# support for drawing karyotypes

use strict;
use Carp 'croak';
use Bio::Graphics::Panel;
use Bio::Graphics::Browser;

sub new {
    my $class  = shift;
    my $args   = shift;
    croak 'usage: new({source=>$source,state=>$state,db=>$db})'
	unless exists $args->{source} &&
	       exists $args->{db} &&
	       exists $args->{state};

    return bless {source=> $args->{source},
		  db    => $args->{db},
		  state => $args->{state}
    },ref $class || $class;
}

sub data_source { shift->{source} }
sub state       { shift->{state}  }
sub db          { shift->{db}     }

sub chromosomes {
    my $self     = shift;
    my $chr_type = $self->data_source->karyotype_setting('chromosome');
    my @chr      = $self->db->features($chr_type);
    return @chr;
}



1;
