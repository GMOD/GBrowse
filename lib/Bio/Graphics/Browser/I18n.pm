package Bio::Graphics::Browser::I18n;

# $Id: I18n.pm,v 1.6 2002-09-25 04:39:21 lstein Exp $
# $Log: not supported by cvs2svn $
# Revision 1.5  2002/09/12 01:58:43  lstein
# added undocumented support for non-bp units and fixed language handling
#
# Revision 1.4  2002/09/11 11:42:23  lstein
# fixed language handling
#
# Revision 1.3  2002/09/05 19:25:27  lstein
# tried to fix problems with localization
#
# Revision 1.2  2002/09/05 19:22:59  lstein
# fixed upload bugs and some language parsing problems
#

use strict;

sub new {
  my $class = shift;
  my $dir   = shift;
  my $self  = bless {
		     dir  => $dir,
		     lang => [],
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
  $self->{lang} = [@_] if @_;  # probably could use \@_ here
  @$d;
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
  my @languages = @_;
  my $table;
  for my $lang (@languages) {
    $self->{tr}{$lang} = $self->read_table($lang)
      unless exists $self->{tr}{$lang};
    next unless $self->{tr}{$lang};
    return $self->{tr}{$lang};
  }
  return {};  # language could not be loaded
}

sub read_table {
  my $self = shift;
  my $language  = shift;
  my $path = join '/',$self->dir,"$language.pm";
  my $table = eval "require '$path'";
  unless ($table) {  # try removing the -br part
    $path =~ s/-\w+\.pm$/.pm/;
    $table = eval "require '$path'";
  }
  $table;
}

1;
