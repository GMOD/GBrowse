#!/usr/bin/perl -w
use strict;
use File::Find;
use File::Basename;


#the point here is to generate text documents from pod
#it is really a tool for us (Lincoln and Scott) for generating
#text documentation that will go into a software release

#the appending of '.txt' to the file name is temporary for testing,
#after this method of generating text documentation is finalized,
#that will be changed to strip '.pod' from the text file name.

find({wanted => \&wanted, no_chdir=>1}, '.');

unlink './pod2htmd.x~~';
unlink './pod2htmi.x~~';

sub wanted {
  if (/\.pod$/) {
    if ('INSTALL.pod' eq basename($File::Find::name)) {
      system('pod2text','-l',$File::Find::name,'INSTALL.txt');
    } else {
      my $basename = basename($File::Find::name);
      system('pod2text','-l',$File::Find::name,"./docs/$basename.txt"); 
    }
  }
}
