#!/usr/bin/perl
use ExtUtils::MakeMaker;
WriteMakefile(
	      NAME     => 'Bio',
	      DISTNAME => 'bioperl',
	      VERSION  => '1.5',
	      INST_LIB     => '../../blib/lib',
	      INST_ARCHLIB => '../../blib/arch',
	      );
