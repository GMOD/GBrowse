#!/usr/bin/perl -w
use strict;
use File::Find;
use File::Basename;

#the point here is to generate text documents from pod
#it is really a tool for us (Lincoln and Scott) for generating
#text documentation that will go into a software release

find({wanted => \&wanted, no_chdir=>1}, '.');

sub wanted {
  if (/\.pod$/) {
    if ('INSTALL.pod' eq basename($File::Find::name)) {
      system('pod2text','-l',$File::Find::name,'INSTALL.txt');
    } else {
      my ($basename,undef,undef) = fileparse($File::Find::name,"\.pod");
      if (uc($basename) eq $basename) {
        system('pod2text','-l',$File::Find::name,"./docs/$basename");
      } else {
        system('pod2text','-l',$File::Find::name,"./docs/$basename.txt"); 
      }
    }
  }
}
