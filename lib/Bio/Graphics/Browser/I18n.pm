package Bio::Graphics::Browser::I18n;

# $Id: I18n.pm,v 1.2 2002-09-05 19:22:59 lstein Exp $
# $Log: not supported by cvs2svn $

use strict;

sub new {
  my $class = shift;
  my $dir   = shift;
  my $self  = bless {
		     dir  => $dir,
		     lang => 'POSIX',
		    },ref $class || $class;
}

sub dir {
  my $self = shift;
  my $d    = $self->{dir};
  $self->{dir} = shift if @_;
  $d;
}

sub language {
  my $self = shift;
  my $d    = $self->{lang};
  $self->{lang} = shift if @_;
  $d;
}

sub tr {
  my $self       = shift;
  my $symbol     = uc shift;
  my $lang_table = $self->tr_table($self->language);
  my $def_table  = $self->tr_table('POSIX');
  my $translated = $lang_table->{$symbol} || $def_table->{$symbol};
  return unless $translated;
  return @_ ? sprintf($translated,@_) : $translated;
}

sub tr_table {
  my $self = shift;
  my $language = shift;
  $self->{tr}{$language} ||= $self->read_table($language);
}

sub read_table {
  my $self = shift;
  my $language  = shift;
  my $path = join '/',$self->dir,"$language.pm";
  my $table = require $path;
  $table;
}

1;
