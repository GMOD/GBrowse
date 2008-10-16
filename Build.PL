#!/usr/bin/perl

use strict;
use warnings;
use FindBin '$Bin';

use lib "$Bin/install_util";
use File::Copy;
use GBrowseInstall;

my $build = GBrowseInstall->new(
    module_name  => 'Generic-Genome-Browser',
    dist_version => '2.00',
    dist_author  => 'Lincoln Stein <lincoln.stein@gmail.com>',
    dist_abstract=> 'The GMOD Generic Genome Browser',
    license      => 'perl',

    requires     => {
	'perl'                => '5.6.1',
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

    );

if ($build->have_c_compiler()) {
    foreach ('CAlign.xs','CAlign.pm') {
	copy("./libalign/$_" => "./lib/Bio/Graphics/Browser/$_");
	# $build->add_to_cleanup("./lib/Bio/Graphics/Browser/$_");
    }
    $build->include_dirs(["$Bin/libalign"]);
}

$build->create_build_script;
exit 0;

package GBrowse::Install;
use base 'Module::Build';

sub ACTION_demo {
    warn "this target runs a demo";
}

1;
