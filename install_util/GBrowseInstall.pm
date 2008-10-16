package GBrowseInstall;

use base 'Module::Build';
use ExtUtils::CBuilder;

sub ACTION_demo {
    warn "this target runs a demo";
}

sub ACTION_realclean {
    my $self = shift;
    $self->SUPER::ACTION_realclean;
    foreach ('CAlign.xs','CAlign.pm') {
	unlink "./lib/Bio/Graphics/Browser/$_";
    }
}

# sub cleanup {
#     my $self  = shift;
#     my @files = $self->SUPER::cleanup;
#     # don't cleanup contents of libalign
#     return grep {!/^libalign/} @files;
# }
# sub up_to_date {
#     my ($self,$source,$derived) = @_;
#     print STDERR "up to date check for $source -> $derived...";
#     my $up = $self->SUPER::up_to_date($source,$derived);
#     print STDERR $up,"\n";
#     return $up
# }

1;
