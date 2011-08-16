package Bio::DB::Synteny::Store;

use strict;
use Carp;

use base 'Bio::Root::Root';

use Bio::DB::GFF::Util::Rearrange qw(rearrange);
use Bio::DB::Synteny::Block;

sub new {
    my $class = shift;
    my ($adaptor,$debug,$create,$args);
    if (@_ == 1) {
        $args = {DSN => shift}
    } else {
        ($adaptor,$debug,$create) =
            rearrange(['ADAPTOR',
                       'DEBUG',
                       'CREATE',
                       ],@_);
    }
    $adaptor ||= 'DBI::mysql';
    $args->{WRITE}++  if $create;
    $args->{CREATE}++ if $create;

    my $driver_class = "Bio::DB::Synteny::Store::$adaptor";
    eval "require $driver_class" or croak $@;
    my $obj = $driver_class->new_instance( @_ );
    $obj->debug($debug) if defined $debug;
    $obj->init($args);
    $obj->post_init($args);
    $obj;
}

sub debug {
  my $self = shift;
  my $d = $self->{debug};
  $self->{debug} = shift if @_;
  $d;
}

sub init {
}
sub post_init {
}

sub invert {
    my ( $self, $strand1, $strand2 ) = @_;
    $$strand1 = $$strand1 eq '+' ? '-' : '+';
    $$strand2 = $$strand2 eq '+' ? '-' : '+';
}


1;
