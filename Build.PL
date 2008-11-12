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
	'bin/gbrowse_slave',
	'bin/make_das_conf.pl',
	'bin/gbrowse_slave',
# not sure if these still work
#	'bin/register_moby_services.pl',
#	'bin/process_wormbase.pl',
#	'bin/process_sgd.pl',
#	'bin/load_genbank.pl',
    ],

    create_makefile_pl => 'passthrough',

    );

if(-e '/proc/filesystems' 
   && `grep selinux /proc/filesystems`) {
    print STDERR <<'END';
**** WARNING *********************************************************
You appear to have SELinux installed on this computer. This can
interfere with GBrowse operation. Please read the file
README.fedora_and_selinux in order to perform additional configuration
operations that may be necessary to run on this computer.
**********************************************************************
END
}

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
$build->add_build_element('etc');
$build->add_build_element('database');

$build->create_build_script;
print STDERR <<END;
Now run:
  ./Build config
  ./Build test
  ./Build demo          (optional)
  ./Build install       (as superuser/administrator)
  ./Build apache_conf   (to get appropriate config file)
        -or-
  ./Build install_slave (optional, for slave installations)
END

exit 0;

1;
