package Bio::Graphics::Browser::DataLoader;
# $Id: DataLoader.pm,v 1.1.2.3 2009-08-21 20:06:40 idavies Exp $

use strict;
use IO::File;
use Carp 'croak';

sub new {
    my $self = shift;
    my ($track_name,$data_path,$conf_path,$settings) = @_;
    return { name => $track_name,
	     data => $data_path,
	     conf => $conf_path,
	     settings=>$settings,
    },ref $self || $self;
 }

sub track_name { shift->{name} }
sub data_path  { shift->{data} }
sub conf_path  { shift->{conf} }
sub conf_fh    { shift->{conf_fh} }
sub settings   { shift->{settings} }
sub setting {
    my $self   = shift;
    my $option = shift;
    $self->settings->global_setting($option);
}
sub status_path {
    my $self = shift;
    return File::Spec->catfile($self->data_path,'STATUS');
}

sub set_status {
    my $self   = shift;
    my $msg    = shift;

    my $status = $self->status_path;
    open my $fh,">",$status;
    print $fh $msg;
    close $fh;
}

sub get_status {
    my $self = shift;
    my $status = $self->status_path;
    open my $fh,">",$status;
    my $msg = <$fh>;
    close $fh;
    return $msg;
}

sub open_conf {
    my $self = shift;
    $self->{conf_fh} ||= IO::File->new($self->conf_path,">");
    $self->{conf_fh} or die $self->conf_path,": $!";
    $self->{conf_fh};
}
sub close_conf {
    undef shift->{conf_fh};
}

sub load {
    my $self                = shift;
    my ($initial_lines,$fh) = @_;

    $self->status('starting load');
    $self->open_conf;
    $self->start_load;

    $self->status('load data');
    for my $line (@$initial_lines) {
	$self->load_line($_);
    }

    my $count = @$initial_lines;
    while (<$fh>) {
	$self->load_line($_);
	$self->status("loaded $count lines") if $count++ % 1000;
    }
    $self->finish_load;
    $self->close_conf;
    $self->status("READY");
}

sub start_load  { }
sub finish_load { }

sub load_line {
    croak "virtual base class";
}

1;
