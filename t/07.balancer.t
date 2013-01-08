#!/usr/bin/perl

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'
use strict;
use warnings;
use FindBin '$Bin';
use Test::More;

use constant TESTS      => 12;
use constant CONF_FILE  => "$Bin/testdata/conf/aws_slave.conf";


BEGIN {
      use lib "$Bin/../lib";
      if (!eval {require Parse::Apache::ServerStatus;1}) {
	  plan skip_all => 'Optional module Parse::Apache::ServerStatus not installed';
      } elsif (!eval "use VM::EC2 1.22; 1") {
	  plan skip_all => 'Optional module VM::EC2 (v1.22 or higher) not installed';
      } else {   
	  plan tests => TESTS;
      }
      use_ok('Bio::Graphics::Browser2::Render::Slave::AWS_Balancer');
}

my $b = Bio::Graphics::Browser2::Render::Slave::AWS_Balancer->new(-conf=>CONF_FILE);
$b or BAIL_OUT("Couldn't create balancer");
$b->verbosity(0);
my $instance = $b->running_as_instance;

is_deeply([$b->slaves_wanted(0.1)],[0,1],'load table test 1');
is_deeply([$b->slaves_wanted(0.4)],[0,1],'load table test 2');
is_deeply([$b->slaves_wanted(0.5)],[0,2],'load table test 3');
is_deeply([$b->slaves_wanted(0.6)],[0,2],'load table test 4');
is_deeply([$b->slaves_wanted(1.0)],[1,4],'load table test 5');
is_deeply([$b->slaves_wanted(1.1)],[1,4],'load table test 6');
is_deeply([$b->slaves_wanted(20)],[6,8],'load table test 8');
is($b->slave_instance_type,'m1.large','instance type');
is($b->slave_spot_bid,'0.08','bid price');
is($b->master_poll,30,'poll interval');
like($b->master_ip,qr/^\d+\.\d+\.\d+\.\d+$/,'master ip');



exit;
