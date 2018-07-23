#!/bin/bash

# Just the basics of setting a cloud image based instance to be ready for devstack

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Determine which OS
export SERVER_OS=$(awk -F "=" '/^NAME/ {print $2}' /etc/*-release)


if [[ "$SERVER_OS" == '"CentOS Linux"' ]]; then
    export USER=centos
else
    # "Ubuntu"
    export USER=ubuntu
fi


# create and set stack user as sudoer
useradd -s /bin/bash -d /opt/stack -m stack
echo "stack ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/stack

#
mkdir /opt/stack/.ssh
cp /home/$USER/.ssh/authorized_keys /opt/stack/.ssh
chown -R stack:stack /opt/stack/.ssh/
chmod 700 /opt/stack/.ssh
chmod 600 /opt/stack/.ssh/authorized_keys
yum install -y vim git wget || apt-get install -y vim git wget
sudo -u stack sudo git clone https://git.openstack.org/openstack-dev/devstack /opt/stack/devstack
chown -R stack:stack /opt/stack/devstack

echo ""
echo "Now create your local.conf and stack"
echo ""

