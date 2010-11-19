#!/usr/bin/perl

# this is just a development tool that I use to find missing language-specific
# tags when I update POSIX.pm

chdir '..' unless -d 'conf';
chdir "conf/languages" or die "Can't cd to languages directory: $!";
my $posix = require "./POSIX.pm";

print "Missing tags:\n";
for my $file (<*.pm>) {
  next if $file =~ /^POSIX/;
  my $contents = require "./$file";
  my @missing = sort grep {!$contents->{$_}} keys %$posix;
  next unless @missing;
  print "$file: @missing\n\n";
}
