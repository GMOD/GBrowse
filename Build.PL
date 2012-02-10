#!/usr/bin/perl

use strict;
use warnings;
use FindBin '$Bin';

use lib "$Bin/install_util";
use File::Copy;
use GBrowseInstall;

my $build = GBrowseInstall->new(
    module_name        => 'GBrowse',
    dist_version_from  => 'lib/Bio/Graphics/Browser2.pm',
    dist_author        => 'Lincoln Stein <lincoln.stein@gmail.com>',
    dist_abstract      => 'The GMOD Generic Genome Browser',
    license            => 'perl',

    requires     => {
	'perl'                => '5.008',
	'Bio::Root::Version'  => '1.0069',
	'Bio::Graphics'       => '2.24',
	'CGI::Session'        => '4.02',
	'Digest::MD5'         => 0,	
        'ExtUtils::CBuilder'  => 0,
	'File::Temp'          => 0,
	'GD'                  => '2.07',
	'Text::ParseWords'    => '3.27',
	'IO::String'          => 0,
	'JSON'                => 0,
	'LWP'                 => 0,
	'Statistics::Descriptive'  => 0,
	'Storable'            => 0,
        'Time::HiRes'         => 0,
        'Digest::SHA'         => 0,
        'Date::Parse'         => 0,
        'Term::ReadKey'       => 0,
    },
    build_requires => {'Capture::Tiny'       => 0,},
    recommends  => {
	'Bio::Das'                 => 0,
	'Bio::DB::Sam'             => 1.20,
	'Bio::DB::BigFile'         => 1.00,
	'Crypt::SSLeay'            => 0,
	'DB_File::Lock'            => 0,
	'DBI'                      => 0,
	'DBD::mysql'               => 0,
	'DBD::Pg'                  => 0,
	'DBD::SQLite'              => 0,
	'Digest::SHA'              => 0,	
	'FCGI'                     => 0,
	'File::NFSLock'            => 0,
	'GD::SVG'                  => 0,
	'Math::BigInt'             => 0,
	'Net::OpenID::Consumer'    => 0,
	'Net::SMTP::SSL'           => 0,
	'Plack'                    => 0,  	# Plack prereqs
	'Plack::App::CGIBin'       => 0,
	'Plack::App::WrapCGI'      => 0,
	'Plack::Builder'           => 0,
	'Plack::Middleware::ReverseProxy' => 0,
	'Plack::Middleware::Debug' => 0,
	'CGI::Emulate::PSGI'       => 0,
	'CGI::Compile'             => 0,
        'Module::Versions'         => 0,        
	$] <= 5.008 ? ('Safe::World'  => 0)
                    : ()               ,
	'Template'                 => 2.20,
        'Term::ReadKey'            => 0,
    },
    script_files => [
	'bin/gbrowse_clean.pl',
	'bin/gbrowse_set_admin_passwd.pl',
	'bin/gbrowse_create_account.pl',
	'bin/gbrowse_change_passwd.pl',
	'bin/gbrowse_metadb_config.pl',
	'bin/gbrowse_slave',
        'bin/gbrowse_syn_load_alignment_database.pl',
        'bin/gbrowse_syn_load_alignments_msa.pl',
	'bin/make_das_conf.pl',
	'bin/scan_gbrowse.pl',
	'bin/wiggle2gff3.pl',
	'bin/gtf2gff3.pl',
	'bin/bed2gff3.pl',
	'bin/ucsc_genes2gff.pl',
	'bin/load_genbank.pl',
    ],

    create_makefile_pl => 'passthrough',

    );

print STDERR <<END;
**** WARNING *****************************************************************************************
If you are upgrading from an earlier version of GBrowse and wish to use named user accounts, please 
set "user_accounts" to 1 in /etc/gbrowse2/GBrowse.conf and run bin/gbrowse_metadb_config.pl to 
create/update your user account database.

See /etc/gbrowse2/GBrowse.conf.new for suggested settings.
******************************************************************************************************
END

#print STDERR "Continue? [y/n] ";
#my $line = <>;
#exit 0 unless $line =~ /[yY]/;

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
$build->config_data(OpenIDConsumerSecret=>int(1e15*rand()));
$build->config_done(1) if $argc > 0;

$build->add_build_element('conf');
$build->add_build_element('htdocs');
$build->add_build_element('cgibin');
$build->add_build_element('etc');
$build->add_build_element('database');

$build->create_build_script;
print STDERR <<END;
Now run:
  ./Build test
  ./Build demo          (optional)
  ./Build install       (as superuser/administrator)
        -or-
  ./Build install_slave (optional, for slave installations)

Other useful targets:
  ./Build register      (to register your copy of GBrowse)
  ./Build reconfig      (to reconfigure install locations)
  ./Build demostop      (to stop the demo)
END

exit 0;

1;
