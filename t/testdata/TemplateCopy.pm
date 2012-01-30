package TemplateCopy;

use strict;
use warnings;

use base 'Exporter';
use IO::File;

our @EXPORT = 'template_copy';

sub template_copy {
    my ($infile,$outfile,$replacements) = @_;
    local $_;

    chmod 0644,$outfile
	unless -w $outfile;
    my $in      = IO::File->new($infile)      or die "$infile: $!";
    my $out     = IO::File->new($outfile,'>') or die "$outfile: $!";
    my $pattern = '('.join('|',map {quotemeta($_)} keys %$replacements).')' if %$replacements;
    while (<$in>) {
	s/$pattern/$replacements->{$1}/ge if $pattern;
	$out->print($_);
    }

}

1;

