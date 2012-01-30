package Bio::Graphics::Browser2::I18n;

# $Id$

use strict;
my %TABLES;

sub new {
  my $class = shift;
  my $dir   = shift;
  if (exists $TABLES{$dir}) {
    return $TABLES{$dir};
  } else {
    my $self  = bless {
		       dir  => $dir,
		       lang => [],
		      },ref $class || $class;
    $TABLES{$dir} = $self;
    return $self;
  }
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
  if (@_) {
    my @lang = ();
    for my $l (map {lc $_} @_) {  # lowercase all
      push @lang,$l;
      (my $bare = $l) =~ s/-\w+$//;
      push @lang,$bare if $bare ne $l;
    }
    $self->{lang} = \@lang;
  }
  @$d;
}

sub tr {
  my $self       = shift;
  my $symbol     = uc shift;
  my $lang_table = $self->tr_table($self->language);
  my $def_table  = $self->tr_table('POSIX');
  my $translated = $lang_table->{$symbol} || $def_table->{$symbol};
  return unless $translated;
  local $^W = 0;  # quashing uninit variable warning
  return @_ ? sprintf($translated,map {CGI::escapeHTML($_)} @_) : $translated;
}

sub translate {
    shift->tr(@_);
}

sub tr_table {
  my $self = shift;
  my @languages = @_;
  my $table;
   for my $lang (@languages) {
      $self->{tr}{$lang} = $self->read_table($lang)
	  unless exists $self->{tr}{$lang};
       return $self->{tr}{$lang} if $self->{tr}{$lang};
  }
  return {};  # language could not be loaded
}

sub read_table {
  my $self = shift;
  my $language  = shift;
  my $path = join '/',$self->dir,"$language.pm";
  my $table = do $path;
  $table;
}

1;
