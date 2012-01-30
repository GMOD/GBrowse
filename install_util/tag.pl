#!/usr/bin/perl

# just a utility to assist developers in tagging new releases in SVN

use strict;
my $revision = shift or die "Usage: tag.pl \$revision";

exec "svn copy -m'release tag' https://gmod.svn.sourceforge.net/svnroot/gmod/Generic-Genome-Browser/trunk https://gmod.svn.sourceforge.net/svnroot/gmod/Generic-Genome-Browser/tags/$revision";

