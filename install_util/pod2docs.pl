#!/usr/bin/perl -w
use strict;
use File::Find;

#the point here is to generate text documents from pod
#it is really a tool for us (Lincoln and Scott) for generating
#text documentation that will go into a software release

#anywhere there is a pod file, create a text file in the same dir.
#start with current dir and recurse.

#the appending of '.txt' to the file name is temporary for testing,
#after this method of generating text documentation is finalized,
#that will be changed to strip '.pod' from the text file name.

find({wanted => \&wanted, no_chdir=>1}, '.');

sub wanted {
  if (/\.pod$/) {
    system('pod2text','-l',$File::Find::name,$File::Find::name.'.txt'); 
    warn "textifying $File::Find::name\n";
  }
}
