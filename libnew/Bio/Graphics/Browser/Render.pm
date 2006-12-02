package Bio::Graphics::Browser::Render;

use strict;
use warnings;

sub new {
  my $class = shift;
  my ($globals,$data_source,$session) = @_;
  my $self = bless {},ref $class || $class;
  $self->globals($globals);
  $self->dsn($data_source);
  $self->session($session);
  $self;
}

sub globals {
  my $self = shift;
  my $d = $self->{globals};
  $self->{globals} = shift if @_;
  $d;
}

sub dsn {
  my $self = shift;
  my $d = $self->{dsn};
  $self->{dsn} = shift if @_;
  $d;
}

sub session {
  my $self = shift;
  my $d = $self->{session};
  $self->{session} = shift if @_;
  $d;
}

###################################################################################
#
# SETTINGS CODE HERE
#
###################################################################################

# the setting method falls through to the globals object, but only
# if it uses the single-argument form
sub setting {
  my $self = shift;

  if (@_ == 1) {
    my $dsn_specific_setting = $self->dsn->setting(general=>$_[0]);
    return $dsn_specific_setting if defined $dsn_specific_setting;
    return $self->globals->setting(general=>$_[0]);
  }

  # otherwise we get the dsn-specific settings
  $self->dsn->setting(@_);
}

sub plugin_setting {
  my $self           = shift;
  my $caller_package = caller();
  my ($last_name)    = $caller_package =~ /(\w+)$/;
  my $option_name    = "${last_name}:plugin";
  $self->setting($option_name => @_);
}

sub karyotype_setting {
  my $self           = shift;
  my $caller_package = caller();
  $self->setting('karyotype' => @_);
}

sub db_settings {
  my $self = shift;

  my $adaptor = $self->setting('db_adaptor') or die "No db_adaptor specified";
  eval "require $adaptor; 1" or die $@;

  my $args    = $self->setting(general => 'db_args');
  my @argv = ref $args eq 'CODE'
        ? $args->()
	: shellwords($args||'');

  # for compatibility with older versions of the browser, we'll hard-code some arguments
  if (my $adaptor = $self->setting('adaptor')) {
    push @argv,(-adaptor => $adaptor);
  }

  if (my $dsn = $self->setting('database')) {
    push @argv,(-dsn => $dsn);
  }

  if (my $fasta = $self->setting('fasta_files')) {
    push @argv,(-fasta=>$fasta);
  }

  if (my $user = $self->setting('user')) {
    push @argv,(-user=>$user);
  }

  if (my $pass = $self->setting('pass')) {
    push @argv,(-pass=>$pass);
  }

  if (defined (my $a = $self->setting('aggregators'))) {
    my @aggregators = shellwords($a||'');
    push @argv,(-aggregator => \@aggregators);
  }

  ($adaptor,@argv);
}


1;

