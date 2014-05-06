#!/bin/bash

# Dersom etterpåklokskapen skulle si at cinder-volumes burde vært større:
# sudo losetup -a
# finn /dev/loopX på samme linje som cinder-volumes
# sudo pvresize /dev/loopX --setphysicalvolumesize <antall gigabytes>G

PUBKEY=$HOME/.ssh/id_rsa.pub
ANSWER_FILE="packstack-answers.txt"

function joalog() {
	echo -e "[JOASTACK] - $1"
}

GEN_ANSWER=1
EXIT_AFTER_GEN=0
IFACE="eth0"
IP=$(ifconfig $IFACE | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')

while getopts "ag" opt; do
    case $opt in
        a)
            joalog "using existing answer-file"
            GEN_ANSWER=0
            
	        if [ ! -f $ANSWER_FILE ]; then
		        joalog "answer file not found"
		        exit 1
	        fi
            ;;
        g)
            joalog "exiting after generation of answer file"
            EXIT_AFTER_GEN=1
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done



if [ $EXIT_AFTER_GEN -eq 0 ]; then
    # Install RDO
    joalog "Installing PackStack"
    sudo yum install -y http://rdo.fedorapeople.org/openstack/openstack-grizzly/rdo-release-grizzly.rpm

    # Install packstack
    # A tool for quickly installing openstack
    # with a few predefined configurations, ie "All in one" etc.
    sudo yum install -y openstack-packstack
else
    joalog "Skipping packstack installation"
fi

if [ $GEN_ANSWER -eq 1 ]; then
	cp packstack-answers.txt.repl packstack-answers.txt

    # read info
    source include/input.sh

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
	sed "s/##IP##/$IP/g" $ANSWER_FILE > $TEMPFILE
	cp $TEMPFILE $ANSWER_FILE
	sed "s/##ETH##/$IFACE/g" $ANSWER_FILE > $TEMPFILE
	cp $TEMPFILE $ANSWER_FILE
	rm $TEMPFILE
	
	if [ $EXIT_AFTER_GEN -eq 1 ]; then
	    joalog "Answer-file generated. Exiting"
	    exit 0
    fi
else
    joalog "Skipping answer-file gen"
fi

if [ ! -f $PUBKEY ] 
then
    joalog "No pubkey found. Creating new."
    ssh-keygen
else
    joalog "Using public key $PUBKEY"
fi

# Look for cernVM-image
# download if it doesn't exist

CERNVM_IMAGE="cernvm-batch-node-2.7.2-1-2-x86_64.hdd"
joalog "Looking for CernVM-image in images/"
if [ ! -d images/ ]; then
	mkdir images
fi

cd images

if [ ! -f $CERNVM_IMAGE ]; then
	joalog "Can't find the CernVM-image. Starting download..."
	wget http://cernvm.cern.ch/releases/25/$CERNVM_IMAGE.gz
	joalog "Unzipping the archive"
	gunzip $CERNVM_IMAGE.gz
fi

# return
cd ..


IMAGE_LOCATION="images/$CERNVM_IMAGE"
VOLUME_SIZE=10 # This is the "minimum" size for cernvm volumes
MIN_RAM=256
MIN_DISK=10
SECGROUP_NAME="cernvm-secgroup"
VOLUME_NAME="cernvm-volume"
IMAGE_NAME="cernvm"
FLAVOR_NAME="cernvm-machine"
INST_NAME="cernvm-inst"
FLOATING_IP_RANGE="192.168.1.56/29"

# Install openstack with preconfigured settings
# To install with default settings:
# 	sudo packstack --allinone --os-quantum-install=n
joalog "Starting the packstack installer"
sudo packstack --answer-file=$ANSWER_FILE
#sudo packstack --allinone --os-quantum-install=n --mysql-pw=$MYSQL_PW --cinder-volumes-size=$CINDER_VOLUMES_SIZE 
# Add keystone auth envvars

joalog "Copying /root/keystonerc_admin to $(pwd)"

sudo cp /root/keystonerc_admin $(pwd)/
sudo chown $USER:$USER $(pwd)/keystonerc_admin
source $(pwd)/keystonerc_admin

# Upload CernVM image
joalog "Creating CernVM Image"
glance image-create --name="$IMAGE_NAME" --is-public=true --disk-format=qcow2 --container-format=bare < $IMAGE_LOCATION &> /dev/null

# Create volume from disk
IMAGE_ID=$(nova image-list | awk '/ '${IMAGE_NAME}' / { print $2 }')
#joalog "Creating Volume from CernVM Image"

#nova volume-create --display-name=$VOLUME_NAME --image-id=$IMAGE_ID $VOLUME_SIZE &> /dev/null

# Create a machine flavor <display-name> <id> <ram mb> <disk gb> <vCPUs>
nova flavor-create $FLAVOR_NAME auto 1024 10 1 &> /dev/null

# Create a group of security rules for cernvm
nova secgroup-create $SECGROUP_NAME $SECGROUP_NAME &> /dev/null
nova secgroup-add-rule $SECGROUP_NAME tcp 22 22 0.0.0.0/0 &> /dev/null	# SSH
#nova secgroup-add-rule $SECGROUP_NAME tcp 8003 8003 0.0.0.0/0 &> /dev/null	# CernVM WebAdmin

# Create instance from disk and image
FLAVOR_ID=$(nova flavor-list | awk '/ '${FLAVOR_NAME}' / { print $2 }')
VOLUME_ID=$(nova volume-list | awk '/ '${VOLUME_NAME}' / { print $2 }')
IMAGE_ID=$(nova image-list | awk '/ '${IMAGE_NAME}' / { print $2 }')

joalog "Adding keypair to OpenStack with name $USER"

nova keypair-add --pub-key $PUBKEY $USER &> /dev/null

joalog "Waiting for volume to become available"
while [ $(nova volume-list | awk '/ '${VOLUME_NAME}' / { print $4 }') != "available" ]; do 
	sleep 5
done
joalog "Creating instance"

nova boot --key-name=$USER --image=$IMAGE_ID --flavor=$FLAVOR_ID $INST_NAME --security-groups $SECGROUP_NAME &> /dev/null

INST_ID=$(nova list | awk '/ '${INST_NAME}' / { print $2 }')

joalog "Waiting for instance to start up"
while [ $(nova list | awk '/ '${INST_NAME}' / { print $6 }') != "ACTIVE" ]; do
	sleep 5
done

joalog "Instance started."
# Assign floating IP to instance
# `nova floating-ip-pool-list` then `nova floating-ip-create $POOL_NAME` ?
# By default, POOL_NAME can only be "nova"

# Not really necessary as its configurable in the answers-file
# First we should delete the default floating IP-range and add our own IP-range
# nova floating-ip-bulk-delete 10.3.4.0/22
# nova floating-ip-bulk-create $FLOATING_IP_RANGE

# Then we can assign a new floating IP to our instance
#POOL_NAME="nova"
#INST_IP=$(nova floating-ip-create $POOL_NAME | awk '/ nova / { print $2 }')
#nova add-floating-ip $INST_ID $INST_IP

#joalog "Assigned IP $INST_IP to instance."
joalog "Installation \"complete\". The first instance should be ready in a while."
