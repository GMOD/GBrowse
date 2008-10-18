#!/usr/bin/perl

use strict;
use warnings;
use FindBin '$Bin';

use lib "$Bin/install_util";
use File::Copy;
use GBrowseInstall;

my $build = GBrowseInstall->new(
    module_name  => 'GBrowse',
    dist_version => '2.00',
    dist_author  => 'Lincoln Stein <lincoln.stein@gmail.com>',
    dist_abstract=> 'The GMOD Generic Genome Browser',
    license      => 'perl',

    requires     => {
	'perl'                => '5.008',
	'Bio::Root::Version'  => '1.005002',
	'GD'                  => '2.07',
	'IO::String'          => 0,
	'CGI::Session'        => '4.02',
	'File::Temp'          => 0,
	'Digest::MD5'         => 0,	
	'Storable'            => 0,
	'JSON'                => 0,
	'LWP'                 => 0,
    },
    script_files => [
	'bin/register_moby_services.pl',
	'bin/make_das_conf.pl',
	'bin/process_wormbase.pl',
	'bin/process_sgd.pl',
	'bin/load_genbank.pl',
    ],

    create_makefile_pl => 'passthrough',

    );

if ($build->have_c_compiler()) {
    foreach ('CAlign.xs','CAlign.pm') {
	copy("./libalign/$_" => "./lib/Bio/Graphics/Browser/$_");
    }
    $build->include_dirs(["$Bin/libalign"]);
}

my $argc=0;
for my $arg (keys %{$build->private_props}) {
    my $value = $build->runtime_params($arg) or next;
    $build->config_data($arg=>$value);
    $argc++;
}
$build->config_done(1) if $argc > 0;

$build->add_build_element('conf');
$build->add_build_element('htdocs');
$build->add_build_element('cgibin');
$build->create_build_script;
print STDERR <<END;
Now run:
  ./Build test
  ./Build config
  ./Build demo    (optional)
  ./Build install (as superuser/administrator)
END

exit 0;

1;
