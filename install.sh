#!/bin/bash

# Dersom etterpåklokskapen skulle si at cinder-volumes burde vært større:
# sudo losetup -a
# finn /dev/loopX på samme linje som cinder-volumes
# sudo pvresize /dev/loopX --setphysicalvolumesize <antall gigabytes>G

function joalog() {
	echo -e "[JOASTACK] - $1"
}

# Look for cernVM-image
# download if it doesn't exist

joalog "Looking for CernVM-image in images/"
if [ ! -d images/ ]; then
	mkdir images
fi

cd images

if [ ! -f cernvm-basic-2.6.0-4-1-x86_64.vdi ]; then
	echo "Can't find the CernVM-image. Starting download..."
	wget http://cernvm.cern.ch/releases/17/cernvm-basic-2.6.0-4-1-x86_64.vdi.gz
	gunzip cernvm-basic-2.6.0-4-1-x86_64.vdi.gz
fi

# return
cd ..

# read info
source include/input.sh

cp packstack-answers.txt.repl packstack-answers.txt
ANSWER_FILE="packstack-answers.txt"
IMAGE_LOCATION="images/cernvm-basic-2.6.0-4-1-x86_64.vdi"
VOLUME_SIZE=10 # This is the "minimum" size for cernvm volumes
MIN_RAM=256
MIN_DISK=10
SECGROUP_NAME="cernvm-secgroup"
VOLUME_NAME="cernvm-volume"
IMAGE_NAME="cernvm"
FLAVOR_NAME="cernvm-machine"
INST_NAME="cernvm-inst"
FLOATING_IP_RANGE="192.168.1.56/29"

# Install RDO
sudo yum install -y http://rdo.fedorapeople.org/openstack/openstack-grizzly/rdo-release-grizzly.rpm

# Install packstack
# A tool for quickly installing openstack
# with a few predefined configurations, ie "All in one" etc.
sudo yum install -y openstack-packstack

# Insert variables into packstack-answers-file
TEMPFILE="temp.txt"
sed "s/##MYSQL_USER##/$MYSQL_USER/g" $ANSWER_FILE > $TEMPFILE
cp $TEMPFILE $ANSWER_FILE
sed "s/##MYSQL_PW##/$MYSQL_PW/g" $ANSWER_FILE > $TEMPFILE
cp $TEMPFILE $ANSWER_FILE
sed "s/##ADMIN_PW##/$ADMIN_PW/g" $ANSWER_FILE > $TEMPFILE
cp $TEMPFILE $ANSWER_FILE
sed "s/##CINDER_VOLUMES_SIZE##/$CINDER_VOLUMES_SIZE/g" $ANSWER_FILE > $TEMPFILE
cp $TEMPFILE $ANSWER_FILE
rm $TEMPFILE

# Install openstack with preconfigured settings
# To install with default settings:
# 	sudo packstack --allinone --os-quantum-install=n
sudo packstack --answer-file=$ANSWER_FILE
#sudo packstack --allinone --os-quantum-install=n --mysql-pw=$MYSQL_PW --cinder-volumes-size=$CINDER_VOLUMES_SIZE 
# Add keystone auth envvars
sudo cp /root/keystonerc_admin $(pwd)/
source $(pwd)/keystonerc_admin

# Upload CernVM image
joalog "Creating CernVM Image"
glance image-create --name="$IMAGE_NAME" --is-public=true --disk-format=vdi --container-format=bare --min-ram=$MIN_RAM --min-disk=$MIN_DISK < $IMAGE_LOCATION &> /dev/null

# Create volume from disk
IMAGE_ID=$(nova image-list | awk '/ '${IMAGE_NAME}' / { print $2 }')
joalog "Creating Volume from CernVM Image"

nova volume-create --display-name=$VOLUME_NAME --image-id=$IMAGE_ID $VOLUME_SIZE &> /dev/null

# Create a machine flavor <display-name> <id> <ram mb> <disk gb> <vCPUs>
nova flavor-create $FLAVOR_NAME auto 512 10 1 &> /dev/null

# Create a group of security rules for cernvm
nova secgroup-create $SECGROUP_NAME $SECGROUP_NAME &> /dev/null
nova secgroup-add-rule $SECGROUP_NAME tcp 22 22 0.0.0.0/0 &> /dev/null	# SSH
nova secgroup-add-rule $SECGROUP_NAME tcp 8003 8003 0.0.0.0/0 &> /dev/null	# CernVM WebAdmin

# Create instance from disk and image
FLAVOR_ID=$(nova flavor-list | awk '/ '${FLAVOR_NAME}' / { print $2 }')
VOLUME_ID=$(nova volume-list | awk '/ '${VOLUME_NAME}' / { print $2 }')
IMAGE_ID=$(nova image-list | awk '/ '${IMAGE_NAME}' / { print $2 }')

joalog "Waiting for volume to become available"
while [ $(nova volume-list | awk '/ '${VOLUME_NAME}' / { print $4 }') != "available" ]; do 
	sleep 5
done
joalog "Creating instance"
nova boot --image=$IMAGE_ID --flavor=$FLAVOR_ID --block_device_mapping hda=$VOLUME_ID:::0 $INST_NAME --security-groups $SECGROUP_NAME &> /dev/null

INST_ID=$(nova list | awk '/ '${INST_NAME}' / { print $2 }')

# Assign floating IP to instance
# `nova floating-ip-pool-list` then `nova floating-ip-create $POOL_NAME` ?
# By default, POOL_NAME can only be "nova"

# Not really necessary as its configurable in the answers-file
# First we should delete the default floating IP-range and add our own IP-range
# nova floating-ip-bulk-delete 10.3.4.0/22
# nova floating-ip-bulk-create $FLOATING_IP_RANGE

# Then we can assign a new floating IP to our instance
# POOL_NAME="nova"
# INST_IP=$(nova floating-ip-create $POOL_NAME | awk '/ nova / { print $2 }')
# nova add-floating-ip $INST_ID $INST_IP

joalog "Installation \"complete\". The first instance should start in a while."
joalog "When it has started it is time to configure CernVM:"
joalog "Go to the first IP of the specified floating IP-range on port 8003 and follow the steps"
joalog "Default login is admin password"
