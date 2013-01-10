package Bio::Graphics::Browser2::Render::Slave::AWS_Balancer;

# This module is used to manage GBrowse slaves in an on-demand Amazon EC2
# environment.

use strict;
use Parse::Apache::ServerStatus;
use VM::EC2 1.22;
use VM::EC2::Instance::Metadata;
use VM::EC2::Staging::Manager;
use LWP::Simple 'get','head';
use LWP::UserAgent;
use Parse::Apache::ServerStatus;
use IO::File;
use POSIX 'strftime','setsid','setuid';
use Carp 'croak';
use FindBin '$Bin';

use constant CONFIGURE_SLAVES => "$Bin/gbrowse_configure_slaves.pl";

# arguments:
# ( -conf       => $config_path,
#   -access_key => $aws_access_key,
#   -secret_key => $aws_secret_key,
#   -logfile    => $path_to_logfile,
#   -pidfile    => $path_to_pidfile,
#   -user       => $user_name_to_run_under,# (root only)
#   -daemon     => $daemon_mode,
#   -ssh_key    => $ssh_login_key (optional)
# )

sub new {
    my $class = shift;
    my %args  = @_;
    $args{-conf}     or croak "-conf argument required";
    -e $args{-conf}  or croak "$args{-conf} not found";

    #setup EC2 environment
    $args{-access_key}  ||= $ENV{EC2_ACCESS_KEY};
    $args{-secret_key}  ||= $ENV{EC2_SECRET_KEY};

    my $self = bless {
	access_key => $args{-access_key},
	secret_key => $args{-secret_key},
	logfile    => $args{-logfile},
	pidfile    => $args{-pidfile},
	user       => $args{-user},
	conf_file  => $args{-conf},
	daemon     => $args{-daemon},
	ssh_key    => $args{-ssh_key},
	verbosity  => 2,
    },ref $class || $class;
    $self->initialize();
    return $self;
}

sub logfile    {shift->{logfile}}
sub pidfile    {shift->{pidfile}}
sub pid        {shift->{pid}}
sub user       {shift->{user}}
sub daemon     {shift->{daemon}}
sub ssh_key    {shift->{ssh_key}}
sub ec2_credentials {
    my $self = shift;
    if ($self->running_as_instance) {
	my $credentials = $self->{instance_metadata}->iam_credentials;
	return (-security_token => $credentials) if $credentials;
	$self->log_debug('No instance security credentials. Does this instance have an IAM role?');
    }
    $self->{access_key} ||= $self->_prompt('Enter your EC2 access key:');
    $self->{secret_key} ||= $self->_prompt('Enter your EC2 secret key:');
    return (-access_key => $self->{access_key},
	    -secret_key => $self->{secret_key})
}
sub logfh {
    my $self = shift;
    my $d    = $self->{logfh};
    $self->{logfh} = shift if @_;
    $d;
}

sub verbosity {
    my $self = shift;
    my $d    = $self->{verbosity};
    $self->{verbosity} = shift if @_;
    $d;
}

sub initialize {
    my $self = shift;
    $self->_parse_conf_file;
    $self->_parse_instance_metadata;
}

sub DESTROY {
    my $self = shift;
    $self->cleanup;
}

sub run {
    my $self = shift;
    $self->become_daemon && return 
	if $self->daemon;

    my $killed;
    local $SIG{INT} = local $SIG{TERM} = sub {$self->log_info('Termination signal received');
					      $killed++; };
    $self->{pid} = $$;

    my $poll = $self->master_poll;
    eval {$self->ec2} or croak $@;
    $self->log_info("Monitoring load at intervals of $poll sec\n");
    while (sleep $poll) {
	last if $killed;
	my $load = $self->get_load();
	$self->log_debug("Current load: $load req/s\n");
	$self->adjust_instances($load);
	$self->update_requests();
    }

    $self->log_info('Normal termination');
}

sub stop_daemon {
    my $self = shift;
    my $pid  = $self->pid;
    if (!$pid && (my $pidfile = $self->pidfile)) {
	my $fh = IO::File->new($pidfile) or croak "No PID file; is daemon runnning?";
	$pid   = $fh->getline;
	chomp($pid);
	$fh->close;
    }
    unlink $self->pidfile if -e $self->pidfile;
    kill TERM=>$pid if defined $pid;
}

#######################
# configuration
######################

sub conf_file {shift->{conf_file}}

sub load_table {
    return shift->{options}{'LOAD TABLE'};
}

sub option {
    my $self = shift;
    my ($stanza,$option) = @_;
    return $self->{options}{uc $stanza}{$option};
}

# given load, returns two element list of min_instances, max_instances
sub slaves_wanted {
    my $self = shift;
    my $load = shift;

    my $lt   = $self->load_table or croak 'no load table!';
    my ($min,$max) = (0,0);
    for my $l (sort {$a<=>$b} keys %$lt) {
	($min,$max) = @{$lt->{$l}} if $load >= $l;
    }
    return ($min,$max);
}

sub slave_instance_type { shift->option('SLAVE','instance_type') || 'm1.large' }
sub slave_spot_bid      { shift->option('SLAVE','spot_bid')      || 0.08       }
sub slave_ports         { my $p = shift->option('SLAVE','ports');
			  my @p = split /\s+/,$p;
			  return @p ? @p : (8101); }
sub slave_endpoint {
    my $self = shift;
    if ($self->running_as_instance) {
	my $zone =  $self->{instance_metadata}->endpoint;
	return $zone;
    } else {
	my $region = $self->option('SLAVE','region') || 'us-east-1';
	return "http://ec2.$region.amazonaws.com";
    }
}

sub slave_zone {
    my $self = shift;
    if ($self->running_as_instance) {
	return $self->{instance_metadata}->availabilityZone;
    } else {
	$self->option('SLAVE','availability_zone');
    }
}

sub slave_image_id {
    my $self = shift;
    if ($self->running_as_instance) {
	return $self->{instance_metadata}->imageId;
    } else {
	$self->option('SLAVE','image_id');
    }
}

sub slave_data_snapshots {
    my $self  = shift;
    return split /\s+/,$self->option('SLAVE','data_snapshots');
}

sub slave_block_device_mapping {
    my $self = shift;
    my $image = $self->ec2->describe_images($self->slave_image_id)
	or die "Could not find image ",$self->slave_image_id;
    my $root    = $image->rootDeviceName;
    my @root    = grep {$_->deviceName eq $root} $image->blockDeviceMapping;
    
    my @snaps = $self->slave_data_snapshots;
    my @bdm;
  DEVICE:
    for my $major ('g'..'z') {
	for my $minor (1..15) {
	    my $snap = shift @snaps or last DEVICE;
	    push @bdm,"/dev/sd${major}${minor}=${snap}::true";
	}
    }
    return [@root,@bdm];
}

sub slave_subnet {
    my $self = shift;
    if ($self->running_as_instance) {
	return eval {(values %{$self->{instance_metadata}->interfaces})[0]{subnetId}};
    } else {
	$self->option('SLAVE','subnet');
    }
}

sub slave_ssh_key {
    my $self = shift;
    my $key  = $self->ssh_key;
    $key   ||= $self->option('SLAVE','ssh_key');
    return $key;
}

sub slave_security_group {
    my $self = shift;
    my $sg   = $self->{slave_security_group};
    return $sg if $sg;
    my $ec2 = $self->ec2;
    $sg =   $ec2->describe_security_groups(-name     =>  "GBROWSE_SLAVE_$$");
    $sg ||= $ec2->create_security_group(-name        =>  "GBROWSE_SLAVE_$$",
					-description => 'Temporary security group for slave communications');
    my $ip = $self->running_as_instance ? $self->internal_ip : $self->master_ip;
    
    $self->log_debug(
	$sg->authorize_incoming(-protocol  => 'tcp',
				-port      => $_,
				-source_ip => "$ip/32")
	) foreach $self->slave_ports;
    $self->log_debug(
	$sg->authorize_incoming(-protocol => 'tcp',
				-port     => 22,
				-source_ip=> "$ip/32"))
	if $self->slave_ssh_key;
    
    $sg->update or croak $ec2->error_str;
    return $self->{slave_security_group} = $sg;
}

sub ec2 {
    my $self = shift;
    # create a new ec2 each time because security credentials may expire
    my @credentials = $self->ec2_credentials;
    return $self->{ec2} = VM::EC2->new(-endpoint    => $self->slave_endpoint,
				       -raise_error => 1,
				       @credentials);
}

sub internal_ip {
    my $self = shift;
    return unless $self->running_as_instance;
    return $self->{instance_metadata}->privateIpAddress;
}

sub master_security_group {
    my $self = shift;
    return unless $self->running_as_instance;
    my $sg = ($self->{instance_metadata}->securityGroups)[0];
    $sg    =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    return $sg;
}

sub master_ip {
    my $self = shift;
    my $ip   = $self->option('MASTER','external_ip');
    $ip ||= $self->_get_external_ip;
    return $ip;
}

# poll interval in seconds
sub master_poll {
    my $self = shift;
    my $pi   = $self->option('MASTER','poll_interval');
    return $pi * 60;
}

sub master_server_status_url {
    my $self = shift;
    return $self->option('MASTER','server_status_url') 
	|| 'http://localhost/server-status';
}

sub running_as_instance {
    my $self = shift;
    return -e '/var/lib/cloud/data/previous-instance-id' 
	&& head('http://169.254.169.254');
}


# update conf file with new snapshot images
sub update_data_snapshots {
    my $self = shift;
    my @snapshot_ids = @_;
    my $timestamp     = 'synchronized with local filesystem on '.localtime;
    my $conf_file     = $self->conf_file;
    my ($user,$group) = (stat($conf_file))[4,5];
    open my $in,'<',$conf_file        or die "Couldn't open $conf_file: $!";
    open my $out,'>',"$conf_file.new" or die "Couldn't open $conf_file: $!";
    while (<$in>) {
	chomp;
	s/^(data_snapshots\s*=).*/$1 @snapshot_ids # $timestamp/;
	print $out "$_\n";
    }
    close $in;
    close $out;
    rename "$conf_file","$conf_file.bak" or die "Can't rename $conf_file: $!";
    rename "$conf_file.new","$conf_file" or die "Can't rename $conf_file.new: $!";
    chown $user,$group,$conf_file;
}

#######################
# status
######################

# return true if slave is listening on at least one of the designated ports
sub ping_slave {
    my $self      = shift;
    my $instance  = shift;
    my $ip        = $self->running_as_instance?$instance->privateIpAddress:$instance->ipAddress;
    my ($port) = $self->slave_ports;
    my $ua     = LWP::UserAgent->new;
    my $req    = HTTP::Request->new(HEAD => "http://$ip:$port");
    my $res    = $ua->request($req);
    return $res->code == 403;
}

# returns list of slave instances as VM::EC2::Instance objects
sub running_slaves {
    my $self = shift;
    $self->{running_slaves} ||= {};
    return values %{$self->{running_slaves}};
}

sub add_slave {
    my $self = shift;
    my $instance = shift;
    $self->{running_slaves}{$instance}=$instance;
}

sub remove_slave {
    my $self = shift;
    my $instance = shift;
    delete $self->{running_slaves}{$instance};
}

# given an instance ID, returns the slave VM::EC2::Instance object
sub id2slave {
    my $self = shift;
    my $id   = shift;
    return $self->{running_slaves}{$id};
}

# spot requests - only tracks pending requests
sub pending_spot_requests {
    my $self = shift;
    $self->{pending_requests} ||= {};
    return values %{$self->{pending_requests}};
}

sub add_spot_request {
    my $self = shift;
    my $sr   = shift;
    $self->{pending_requests}{$sr} = $sr;
}

sub remove_spot_request {
    my $self = shift;
    my $sr   = shift;
    delete $self->{pending_requests}{$sr};
}

sub id2_spot_request {
    my $self = shift;
    my $id   = shift;
    return $self->{pending_requests}{$id};
}

sub get_load {
    my $self      = shift;
    $self->{pr} ||= Parse::Apache::ServerStatus->new(url=>$self->master_server_status_url);
    if (-e '/tmp/gbrowse_load') {
	open my $fh,'/tmp/gbrowse_load';
	chomp (my $load = <$fh>);
	return $load;
    }
    my $stats = $self->{pr}->get or $self->fatal("couldn't fetch load from Apache status: ",$self->{pr}->errstr);
    return $stats->{rs};
}


###########################################
# state change
###########################################

# this is called to update the number of live and pending slaves
# according to the load
sub adjust_instances {
    my $self = shift;
    my $load = shift;
    my ($min,$max) = $self->slaves_wanted($load);
    my $current    = $self->pending_spot_requests + $self->running_slaves;
    
    if ($current < $min) {
	$self->log_debug("Need to add more slave spot instances (have $current, wanted $min)\n");
	$self->request_spot_instance while $current++ < $min;
    }

    elsif ($current > $max) {
	$self->log_debug("Need to delete some slave spot instances (have $current, wanted $max)\n");
	my $reconfigure;
	my $ec2        = $self->ec2;
	my @candidates = ($self->pending_spot_requests,$self->running_slaves);
	while ($current-- > $max) {
	    my $c = shift @candidates;
	    if ($c->isa('VM::EC2::Spot::InstanceRequest')) {
		$self->log_debug("Cancelling spot instance request $c\n");
		$ec2->cancel_spot_instance_requests($c);
		$self->remove_spot_request($c);
		$reconfigure++;
	    } elsif ($c->isa('VM::EC2::Instance')) {
		$self->log_debug("Terminating slave instance $c\n");
		$ec2->terminate_instances($c);
		$self->remove_slave($c);
		$reconfigure++;
	    }
	}
	# we reconfigure master immediately to avoid calling instance that were terminated
	$self->reconfigure_master() if $reconfigure;
    }
}

# this is called to act on state changes in spot requests and instances
sub update_requests {
    my $self = shift;
    my @requests = $self->pending_spot_requests;
    for my $sr (@requests) {
	my $state    = $sr->current_status;
	$self->log_debug("Status of $sr is $state");
	my $instance = $sr->instance;
	if ($state eq 'fulfilled' && $instance && $instance->instanceState eq 'running') {
	    $instance->add_tag(Name => 'GBrowse Slave');
	    $self->log_debug("New instance $instance; testing readiness");
	    next unless $self->ping_slave($instance);   # not ready - try again on next poll
	    $self->log_debug("New slave instance is ready");
	    $self->add_slave($instance);
	    $self->remove_spot_request($sr);            # we will never check this request again
	    $self->reconfigure_master();
	} elsif ($sr->current_state =~ /cancelled|failed/ ) {
	    $self->remove_spot_request($sr);
	}
    }
}

# launch a spot instance request
sub request_spot_instance {
    my $self = shift;
    my $ec2  = $self->ec2;

    my $subnet = $self->slave_subnet;
    my @ports  = $self->slave_ports;
    my $key    = $self->slave_ssh_key;

    my @options = (
	-image_id             => $self->slave_image_id,
	-instance_type        => $self->slave_instance_type,
	-instance_count       => 1,
	-security_group_id    => $self->slave_security_group,
	-spot_price           => $self->slave_spot_bid,
	-block_device_mapping => $self->slave_block_device_mapping,
	-user_data         => "#!/bin/sh\nexec /opt/gbrowse/etc/init.d/gbrowse-slave start @ports",
	$subnet? (-subnet_id  => $subnet)          : (),
	$key   ? (-key_name   => $key)             : (),
	);

    my @debug_options;
    for (my $i = 0;$i<@options;$i+=2) {
	my $a  = $options[$i];
	my $v  = $options[$i+1];
	if (ref $v && ref $v eq 'ARRAY') {
	    push @debug_options,($a=>$_) foreach @$v;
	} else {
	    push @debug_options,($a=>$v);
	}
    }
    

    my $debug_options = "@debug_options";
    $debug_options    =~ tr/\n/ /;

    $self->log_debug("Launching a spot request with options: $debug_options\n");
    my @requests = $ec2->request_spot_instances(@options);
    @requests or croak $ec2->error_str;

    $_->add_tag(Requestor=>'GBrowse AWS Balancer') foreach @requests;
    $self->add_spot_request($_) foreach @requests;
}

sub kill_slave {
    my $self     = shift;
    my $instance = shift;
    $self->remove_slave($instance);
    $self->reconfigure_master();
    $instance->terminate();
}

sub reconfigure_master {
    my $self   = shift;
    my @slaves = $self->running_slaves;
    my @ips    = map {$self->running_as_instance?$_->privateIpAddress:$_->ipAddress} @slaves;
    my @a;
    for my $i (@ips) {
	for my $p ($self->slave_ports) {
	    push @a,"http://$i:$p";
	}
    }
    if (@a) {
	system 'sudo',CONFIGURE_SLAVES,(map {('--set'=>$_)} @a);
    } else {
	system 'sudo',CONFIGURE_SLAVES,'--set','';
    }
	
}

sub log_debug {shift->_log(3,@_)}
sub log_info  {shift->_log(2,@_)}
sub log_warn  {shift->_log(1,@_)}
sub log_crit  {shift->_log(0,@_)}
sub fatal {
    my $self = shift;
    my @msg  = shift;
    $self->log_crit(@msg);
    die;
}

sub _log {
    my $self = shift;
    my ($level,@msg) = @_;
    return unless $level <= $self->verbosity;
    my $ts = strftime('%d/%b/%Y:%H:%M:%S %z',localtime);
    my $msg = ucfirst "@msg";
    chomp($msg);
    print STDERR "[$ts] $msg\n";
}

sub cleanup {
    my $self = shift;
    return if !$self->{pid} || $self->{pid} != $$;

    my $ec2 = eval{$self->ec2} or return;
    $self->log_debug('Running cleanup routine');

    my @requests  = $self->pending_spot_requests;
    my @instances = ($self->running_slaves,grep {$_} map {$_->instance} @requests);

    if (@instances) {
	$self->log_debug("terminating spot instances @instances\n");
	delete $self->{running_slaves};
	$self->reconfigure_master();
	$ec2->terminate_instances(@instances);
    }

    if (my @requests  = grep {$_->current_state eq 'open'} $self->pending_spot_requests) {
	$self->log_debug("cancelling spot instance requests @requests\n");
	$ec2->cancel_spot_instance_requests(@requests);
	delete $self->{pending_requests};
    }

    if (my $sg = $self->{slave_security_group}) {
	if (@instances) {
	    $self->log_debug('waiting for running instances to terminate');
	    $ec2->wait_for_instances(@instances);
	}
	$self->ec2->delete_security_group($sg);
	delete $self->{slave_security_group};
	$self->log_debug("deleting security group $sg\n");
    }

    unlink $self->pidfile if $self->pidfile;
}



#######################
# Synchronization
#######################

sub launch_staging_server {
    my $self = shift;
    my $ec2     = $self->ec2;
    my $staging = $self->{staging} ||= $ec2->staging_manager(-on_exit=>'run',
							     -verbose=>3);
    my $server  = $staging->get_server(-name          => 'slave_staging_server',
				       -username      => 'admin',
				       -instance_type => $self->slave_instance_type,
				       -image_name    => $self->slave_image_id,
				       -block_devices => $self->slave_block_device_mapping,
				       -server_class  => 'Bio::Graphics::Browser2::Render::Slave::StagingServer', # this is defined at the bottom of this .pm file
				       -architecture  => undef
	);
    $server->{manager} = $staging; # avoid global destruction issues
    return $server;
}

#######################
# Daemon stuff
#######################

# BUG - redundant code cut-and-paste from Slave.pm
sub become_daemon {
    my $self = shift;

    my $child = fork();
    croak "Couldn't fork: $!" unless defined $child;
    return $child if $child;  # return child PID in parent process

    umask(0);
    $ENV{PATH} = '/bin:/sbin:/usr/bin:/usr/sbin';

    setsid();   # become process leader

    # write out PID file if requested
    if (my $l = $self->pidfile) {
	my $fh = IO::File->new($l,">") 
	    or $self->log_crit("Could not open pidfile $l: $!");
	$fh->print($$)
	    or $self->log_crit("Could not write to pidfile $l: $!");
	$fh->close();
    }
    $self->open_log;
    open STDERR,">&",$self->logfh if $self->logfh;

    chdir '/';  # don't hold open working directories
    open STDIN, "</dev/null";
    open STDOUT,">/dev/null";

    $self->set_user;
    return;
}

# change user if requested
sub set_user {
    my $self = shift;
    my $u = $self->user or return;
    my $uid = getpwnam($u);
    defined $uid or $self->log_crit("Cannot change uid to $u: unknown user");
    setuid($uid) or $self->log_crit("Cannot change uid to $u: $!");
}

# open log file if requested
sub open_log {
    my $self = shift;
    my $l = $self->logfile or return;
    my $fh = IO::File->new($l,">>")  # append
	or $self->Fatal("Could not open logfile $l: $!");
    $fh->autoflush(1);
    $self->logfh($fh);
}


#######################
# internal routines
######################

sub _get_external_ip {
    my $self = shift;
    my $ip= get('http://icanhazip.com');
    chomp($ip);
    $self->log_info("Found external IP address $ip");
    return $ip;
}

sub _parse_conf_file {
    my $self = shift;
    return if exists $self->{options}{'LOAD TABLE'};
    open my $f,$self->conf_file or croak "Could not open ",$self->conf_file,": $!";
    $self->{pushback} = [];
    while (defined(my $line = $self->_getline($f))) {
	$self->_parse_stanza($1,$f) if $line =~ /^\[([^]]+)\]/;
    }
    close $f;
    croak "invalid config file; must contain [LOAD TABLE] and [SLAVE] stanzas"
	unless exists $self->{options}{'LOAD TABLE'} and exists $self->{options}{'SLAVE'};
}

sub _parse_stanza {
    my $self = shift;
    my ($stanza,$fh) = @_;
    if (uc $stanza eq 'LOAD TABLE') {
	$self->_parse_load_table($fh);
    } else {
	$self->_parse_regular_stanza($stanza,$fh);
    }
}

sub _parse_load_table {
    my $self = shift;
    my $fh   = shift;
    while (my $line = $self->_get_stanza_line($fh)) {
	my @tokens = split /\s+/,$line;
	@tokens    == 3 or croak "invalid load table line: $line";
	my ($load,$min,$max) = @tokens;
	$self->{options}{'LOAD TABLE'}{$load} = [$min,$max];
    } 
}

sub _parse_regular_stanza {
    my $self = shift;
    my ($stanza,$fh) = @_;
    while (my $line = $self->_get_stanza_line($fh)) {
	my ($option,$value) = $line =~ /^(\S+)\s*=\s*(.+)/ or next;
	$self->{options}{uc $stanza}{$option} = $value;
    }
}

sub _get_stanza_line {
    my $self = shift;
    my $fh   = shift;
    local $^W=0;
    my $line = $self->_getline($fh);
    if ($line =~ /^\[/) {
	push @{$self->{pushback}},$line;
	return;
    }
    return $line;
}

sub _getline {
    my $self = shift;
    my $fh   = shift;

    if (@{$self->{pushback}}) {
	return pop @{$self->{pushback}};
    }

    while (1) {
	defined(my $line = <$fh>) or return;
	chomp $line;
	$line =~ /^\s*#/ and next;
	$line =~ s/\s+#.*$//;
	$line =~ /\S/    or  next;
	return $line;
    }
}

sub _parse_instance_metadata {
    my $self = shift;
    $self->{instance_metadata} ||= VM::EC2::Instance::Metadata->new();
}

sub _prompt {
    my $self = shift;
    my $msg  = shift;
    -t \*STDIN or return;
    print STDERR $msg;
    my $result = <STDIN>;
    chomp $result;
    return $result;
}

##############################################################################################################
# descendent of VM::EC2::Staging::Server that adds a few tricks
##############################################################################################################

package Bio::Graphics::Browser2::Render::Slave::StagingServer;
use base 'VM::EC2::Staging::Server';
use Sys::Hostname;

use constant GB => 1_073_741_824;
use constant TB => 1_099_511_627_776;

# return the size of the /opt/gbrowse volume in GB
# we intentionally truncate to floor
sub volume_size {
    my $self = shift;
    my $df   = $self->scmd('df -B 1 /opt/gbrowse');
    my ($total,$used,$available) = $df =~ /(\d+)\s+(\d+)\s+(\d+)/;
    return int(0.5 + $total/GB);
}

sub grow_volume {
    my $self = shift;
    my $gig_wanted = shift;

    # get information about the /dev/volumes/gbrowse lv
    my ($lv,$vg,undef,$size) = split /,/,$self->scmd('sudo lvs /dev/volumes/gbrowse --noheadings --units g --nosuffix --separator ,');
    $lv =~ s/^\s+//;
    my $needed = int($gig_wanted-$size);
    return if $needed <= 0;

    $self->info("Resizing /opt/gbrowse to $gig_wanted...\n");

    # get information about the physical volumes that belong to this group
    my %volumes;
    my $fh = $self->scmd_read('sudo pvs --noheadings --units g --nosuffix --separator ,');
    while (<$fh>) {
	chomp;
	s/^\s+//;
	my ($pv,$vg,undef,undef,$used,$free) = split /,/;
	next unless $vg eq 'volumes';
	$volumes{$pv} = $used+$free;
    }
    close $fh;

    # select a volume to resize
    my $to_resize;
    for my $pv (sort {$a<=>$b} keys %volumes) {
	if ($volumes{$pv} + $needed < 1000) {
	    $to_resize  = $pv;
	    last;
	}
    }

    # If we found a pv that we can resize sufficiently, then go ahead and do that.
    # Otherwise, we add a new EBS volume to the volume group.
    $self->info("Unmounting /opt/gbrowse filesystem...\n");
    $self->ssh('sudo umount /opt/gbrowse') or die "Couldn't umount";

    if ($to_resize) {
	$self->_resize_pv($to_resize,int($volumes{$to_resize}+$needed));
    } else {
	$self->_extend_vg('volumes',int($needed));
    }
    
    # If we get here, the volume group has been extended, so we can
    # resize the logical volume and the filesystem
    $self->info("Resizing logical volume...\n");
    $self->ssh('sudo lvextend -l +100%FREE /dev/volumes/gbrowse') or die "Couldn't lvresize";

    $self->info("Checking filesystem prior to resizing...\n");
    $self->ssh('sudo e2fsck -f -p /dev/volumes/gbrowse')          or die "e2fsck failed";

    $self->info("Resizing filesystem...\n");
    $self->ssh('sudo resize2fs -p /dev/volumes/gbrowse')          or die "Couldn't resize2fs";

    $self->info("Remounting filesystem...\n");
    $self->ssh('sudo mount /opt/gbrowse')                         or die "Couldn't mount";

    1;
}

sub terminate {
    my $self = shift;
    $self->manager->unregister_server($self) if $self->manager;
    $self->ec2->terminate_instances($self);
}

sub start_services {
    my $self = shift;
    $self->_start_stop_services('start');
}

sub stop_services {
    my $self = shift;
    $self->_start_stop_services('stop');
}

sub _start_stop_services {
    my $self = shift;
    my $action = shift or die "usage: _start_stop_services(start|stop)";
    $self->info($action eq 'stop' ? "Stopping services...\n":"Starting services...\n");
    foreach ('apache2','mysql','postgresql') {
	$self->ssh("sudo service $_ $action");
    }
}

sub snapshot_data_volumes {
    my $self = shift;

    my %volumes;
    my $fh = $self->scmd_read('sudo pvs --noheadings --units g --nosuffix --separator ,');
    while (<$fh>) {
	chomp;
	s/^\s+//;
	my ($pv,$vg,undef,undef,$used,$free) = split /,/;
	next unless $vg eq 'volumes';
	$pv =~ s!/dev/xvd!/dev/sd!;
	$volumes{$pv}++;
    }
    close $fh;

    my $hostname  = hostname();
    my $timestamp = localtime();

    # get the EBS volumes for this device
    my @vols   = map {$_->volume} grep {$volumes{$_->deviceName}} $self->blockDeviceMapping;
    @vols or die "Could not find the EBS volumes to snapshot";

    $self->info("Unmounting filesystem...\n");
    $self->ssh('sudo umount /opt/gbrowse') or die "Couldn't umount";

    $self->info("Creating snapshots...\n");
    my @snapshots = map {$_->create_snapshot("GBrowse data volume synchronized with $hostname on $timestamp")} @vols;
    $_->add_tag(Name => "GBrowse data from ${hostname}\@${timestamp}") foreach @snapshots;

    $self->info("Remounting filesystem...\n");
    $self->ssh('sudo mount /opt/gbrowse') or die "Couldn't mount";

    return @snapshots;
}

sub _extend_vg {
    my $self = shift;
    my ($vg,$size) = @_;
    
    my ($ebs_device,$local_device) = $self->unused_block_device();
    $self->info("Creating ${size}G EBS volume...\n");
    my $vol = $self->ec2->create_volume(-availability_zone => $self->placement,
					-size              => $size) or die "Couldn't create EBS volume: ",$self->ec2->error_str;
    $self->ec2->wait_for_volumes($vol);
    $vol->current_status eq 'available' or die "EBS volume creation failed: ",$self->ec2->error_str;
    
    my $a = $vol->attach($self => $ebs_device) or die "EBS volume attachment failed: ",$self->ec2->error_str;
    $self->ec2->wait_for_attachments($a);
    $a->current_status eq 'attached'           or die "Volume attachment failed: ",$self->ec2->error_str;

    $a->deleteOnTermination(1);

    $self->info("Creating LVM2 physical device...\n");
    $self->ssh("sudo pvcreate $local_device")          or die "pvcreate failed";

    $self->info("Extending 'volumes' volume group...\n");
    $self->ssh("sudo vgextend volumes $local_device")  or die "vgextend failed";

    1;
}

sub _resize_pv {
    my $self = shift;
    my ($device,$new_size) = @_;

    # get the EBS volume for this device
    my @mapping   = $self->blockDeviceMapping;
    (my $ebs_device = $device) =~ s!/dev/xvd!/dev/sd!;
    my ($mapping) = grep /$ebs_device/,@mapping;
    $mapping or die "Couldn't find an EBS mapping for $device";

    my $volume_id = $mapping->volumeId;
    my $volume    = $mapping->volume;
    
    # disable the volume group
    $self->ssh('sudo vgchange -an volumes') or die "Couldn't vgchange";
    
    # detach the underlying device
    $self->info("Detaching volume $volume...\n");
    my $a = $volume->detach                 or die "Couldn't detach";
    $self->ec2->wait_for_attachments($a);

    # snapshot it
    $self->info("Snapshotting volume $volume...\n");
    my $snapshot = $volume->create_snapshot('created by '.__PACKAGE__) or die "Couldn't snapshot: ",$self->ec2->error_str;
    $self->ec2->wait_for_snapshots($snapshot);
    $snapshot->current_status eq 'completed' or die "Snapshot errored: ",$self->ec2->error_str;
    
    # create a new volume of the appropriate size
    $self->info("Creating new volume from snapshot...\n");
    my $zone = $volume->availabilityZone;
    
    my $new_volume = $self->ec2->create_volume(-availability_zone => $zone,
					       -size              => $new_size,
					       -snapshot_id       => $snapshot) or die "Couldn't create volume: ",$self->ec2->error_str;
    $self->ec2->wait_for_volumes($new_volume);
    $new_volume->current_status eq 'available' or die "Volume error: ",$self->ec2->error_str;

    $self->info("Attaching new volume...\n");
    $a = $self->attach_volume($new_volume => $ebs_device);
    $self->ec2->wait_for_attachments($a);
    $new_volume->deleteOnTermination(1);

    # activate 
    $self->info("Resizing physical volume...\n");
    $self->ssh("sudo pvresize $device")     or die "Couldn't pvresize";
    $self->ssh('sudo vgchange -ay volumes') or die "Couldn't vgchange";

    # get rid of the old volume and the new snapshot (which we no longer need)
    $self->ec2->delete_volume($volume);
    $self->ec2->delete_snapshot($snapshot);

    1;
}

1;

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2012 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

