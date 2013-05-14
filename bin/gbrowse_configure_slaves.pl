#!/usr/bin/perl

use strict;
use Bio::Graphics::Browser2;
use File::Spec;
use Text::ParseWords 'shellwords';
use Getopt::Long;

my (@to_add,@to_remove,@to_set);

GetOptions(
    'add=s'    => \@to_add,
    'remove=s' => \@to_remove,
    'set=s'    => \@to_set
    ) or die <<USAGE;
Usage: gbrowse_add_slaves.pl [--options]

Options:

  --add     Add server to list of renderers.
  --remove  Remove server from list of renderers.
  --set     Set renderer list to the given set.

Each option can be specified multiple times:

 gbrowse_update_renderers.pl --add http://coyote.acme.com:8081 \
                             --add http://roadrunner.acme.com:8081

This script does not actually provision new slaves. It is called after slaves
are provisioned (or deprovisioned) to update the configuration on the master and
restart the server.

Use --set '' to disable the renderfarm completely.
USAGE
    ;
if (@ARGV && !@to_add && !@to_remove) {
    push @to_set,@ARGV;
}

my $globals     = Bio::Graphics::Browser2->open_globals;
my $render_conf = File::Spec->catfile($globals->config_base,'renderfarm.conf');
-e $render_conf or system 'touch',$render_conf;
my $conf        = Bio::Graphics::FeatureFile->new(-file=>$render_conf) or die "Couldn't open $render_conf: $!";
my $use_renderfarm     = $conf->setting(general=>'renderfarm');
my @remote_renderers   = shellwords($conf->setting(general=>'remote renderer'));
my %remote_renderers   = map {$_=>1} @remote_renderers;
my %original_renderers = %remote_renderers;

for my $add (@to_add) {
    next unless $add;
    $remote_renderers{$add}++;
}
for my $sub (@to_remove) {
    next unless $sub;
    delete $remote_renderers{$sub};
}
if (@to_set) {
    %remote_renderers = map {$_=>1} grep {$_} @to_set;
}

my $orig = join ' ',sort keys %original_renderers;
my $new  = join ' ',sort keys %remote_renderers;
my $changed = $orig ne $new;

if ($changed) {
    # write out
    $use_renderfarm = keys %remote_renderers > 0 ? 1 : 0;

    open my $f,'>',"$render_conf.new" or die "Couldn't open $conf.new: $!";
    print $f "[GENERAL]\n";
    print $f "renderfarm = $use_renderfarm\n";
    print $f "remote renderer = \n";
    for my $s (keys %remote_renderers) {
	print $f "\t",$s,"\n" or die "Couldn't write: $!";
    }
    close $f or die "Couldn't write: $!";
    rename "$render_conf.new",$render_conf;

    system "sudo /etc/init.d/apache2 graceful";
}

exit 0;
