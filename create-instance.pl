#!/usr/bin/perl
use lib '../lib';

use VM::EC2;
use MIME::Base64;

my $ec2 = VM::EC2->new(-access_key => '1075adf4a113485d8431af04a781c59c', 
			-secret_key => 'fbe18882bb1a4ce1826340c93823cf1b',
                        -endpoint   => 'http://192.168.1.5:8773/services/Cloud');

#open FILE, "</home/joachim/joastack/context_wo_script.txt";
open FILE, "</home/joachim/joastack/context.txt";
my $user_data = do { local $/; <FILE> };
=pod
my $user_data = qq {
#!/bin/sh
echo Done > /tmp/done
exit
[cernvm]
organisations = alice,atlas
repositories = atlas,alice,grid,atlas-condb,sft
users = panda:atlas:
shell = /bin/bash
};
=pod
my $user_data = qq{
[cernvm]
organisations = cms
repositories = cms
users = testcms:cms:12345678
shell = /bin/bash
services = ntpd
environment = CMS_SITECONFIG=EC2,CMS_ROOT=/opt/cms
};
=cut

print $user_data;

#=pod
my $image = $ec2->describe_images('ami-00000002');

my @instances = $image->run_instances(  -instance_type => 'm1.tiny',
					-min_count => 1,
					-max_count => 1,
					-security_group => 'cernvm-secgroup',
					-key_name => 'joacloud',
					-instance_initiated_shutdown_behavior => 'terminate',
					-user_data => $user_data
					#-user_data_file => '/home/joachim/joastack/context.txt'
				) or die $ec2->error_str;
#$ec2->wait_for_instance($instance);

#=cut

