package InstallUtil;
use strict;
use base qw(Exporter);

use File::Basename qw( basename fileparse );
use Carp qw(cluck croak);
use IO::Dir;
use File::Path qw(mkpath);
use Bio::Root::IO;
use Cwd;
use FindBin '$Bin';
use Term::ANSIColor;

use vars qw(@EXPORT %options);
@EXPORT = qw(copy_tree copy_with_substitutions);
$InstallUtil::options = {};

my %options;

sub copy_tree {
  my(%arg) = @_;
  my ($src,$dest,$indent) = @_;

  my $src          = $arg{source};
  my $dest         = $arg{target};
  my $indent       = $arg{indent} || 2;
  my $substitute   = $arg{substitute};
  my $flatten      = $arg{flatten};

  #warn join ' ', caller();

  %options = %{ $arg{options} };

  $indent ||= 2;

  if (-f $src) {
    copy_with_substitutions($src,$dest) or croak colored("copy_with_substitutions($src,$dest): $!","red");
    return 1;
  }
  croak colored("$src doesn't exist","red") unless -e $src;
  croak colored("Usage: copy_tree(\$src,\$dest).  Can't copy a directory into a file or vice versa","red")
    unless -d $src && -d $dest;
  croak colored("Can't read from $src","red") unless -r $src;
  croak colored("Can't write to $dest","red") unless -w $dest;
  my $tgt = $flatten ? '.' : basename($src);

  # create the dest if it doesn't exist
  mkdir ("$dest/$tgt",0755) or croak colored("mkdir($dest/$tgt): $!","red") unless -d "$dest/$tgt";
  my $d = IO::Dir->new($src) or croak colored("opendir($src): $!","red");
  while (my $item = $d->read) {
    # bunches of things to skip
    next if $item =~ /CVS$/;
    next if $item =~ /\.PLS$/;
    next if $item =~ /^\./;
    next if $item =~ /~$/;
    next if $item =~ /^\#/;
    if (-f "$src/$item") {
      if($substitute){
        copy_with_substitutions("$src/$item","$dest/$tgt/$item",$indent) or croak colored("copy_with_substitutions('$src/$item','$dest/$tgt'): $!","red");
      } else {
        copy_without_substitutions("$src/$item","$dest/$tgt/$item",$indent) or croak colored("copy_with_substitutions('$src/$item','$dest/$tgt'): $!","red");
      }
    } elsif (-d "$src/$item") {
      print colored((" " x $indent)."[copy dir] $src/$item -> $dest/$tgt","blue"),"\n";
      copy_tree(
                source => "$src/$item",
                target => "$dest/$tgt",
                indent => $indent + 2,
                substitute => $substitute,
                options => \%options,
               );
    }
  }
  1;
}

sub copy_with_substitutions {
  my ($localfile,$install_file,$indent) = @_;
  $indent ||= 2;

  print colored((" " x $indent)."[sub file] $localfile -> $install_file","blue"),"\n";

  open (IN,$localfile) or cluck colored("Couldn't open $localfile: $!","orange");
  my $basename = basename($localfile);
  my $dest = -d $install_file ? "$install_file/$basename" : $install_file;
  open (OUT,">$dest") or croak colored("Couldn't open $install_file for writing: $!","red");
  if (-T IN) {
    while (<IN>) {
      s/\$(\w+)/$options{$1}||"\$$1"/eg;
      print OUT;
    }
  }
  else {
    binmode OUT;
    my $buffer;
    print OUT $buffer while read(IN,$buffer,5000);
  }
  close OUT;
  close IN;
  chmod (0755, $install_file);
}

sub copy_without_substitutions {
  my ($localfile,$install_file,$indent) = @_;
  $indent ||= 2;

  print colored((" " x $indent)."[cpy file] $localfile -> $install_file","blue"),"\n";

  open (IN,$localfile) or cluck colored("Couldn't open $localfile: $!","orange");
  my $basename = basename($localfile);
  my $dest = -d $install_file ? "$install_file/$basename" : $install_file;
  open (OUT,">$dest") or croak colored("Couldn't open $install_file for writing: $!","red");
  if (-T IN) {
    while (<IN>) {
      ###FIXME refactor, these two functions are the same except this line
      print OUT;
    }
  }
  else {
    binmode OUT;
    my $buffer;
    print OUT $buffer while read(IN,$buffer,5000);
  }
  close OUT;
  close IN;
  chmod (0755, $install_file);
}

1;
