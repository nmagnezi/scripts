#!/usr/bin/env bash
set -ex

# Sample ``local.sh`` that configures two simple webserver instances and sets
# up a Neutron LBaaS Version 2 loadbalancer backed by Octavia.

# Keep track of the DevStack directory
TOP_DIR="/opt/stack/devstack"
BOOT_DELAY=40
PROJECT_NAME="admin"
LB_NUMBER=$RANDOM
LB_NAME="lb_"$LB_NUMBER
LISTENER_NAME="listener_"$LB_NUMBER
POOL_NAME="pool_"$LB_NUMBER

# Import common functions
source ${TOP_DIR}/functions

# Use openrc + stackrc for settings
source ${TOP_DIR}/stackrc

# Destination path for installation ``DEST``
DEST=${DEST:-/opt/stack}

# Polling functions
function wait_for_loadbalancer_active() {
  lb_name=$1
  while [ $(openstack loadbalancer show $lb_name -f value -c provisioning_status) != "ACTIVE" ]; do
    sleep 2
  done
}

# Copy webserver.sh to devstack dir
cp /opt/stack/octavia/devstack/samples/singlenode/webserver.sh ${TOP_DIR}

# Unset DOMAIN env variables that are not needed for keystone v2 and set OpenStack admin user auth
unset OS_USER_DOMAIN_ID
unset OS_PROJECT_DOMAIN_ID
source ${TOP_DIR}/openrc ${PROJECT_NAME} ${PROJECT_NAME}

# Create loadbalancer
SUBNET_ID=$(openstack subnet show private-subnet -f value -c id)
openstack loadbalancer create --name $LB_NAME --vip-subnet-id $SUBNET_ID

# Create an SSH key to use for the instances
DEVSTACK_LBAAS_SSH_KEY_NAME="DEVSTACK_LBAAS_SSH_KEY"_$LB_NUMBER
DEVSTACK_LBAAS_SSH_KEY_DIR=${TOP_DIR}
DEVSTACK_LBAAS_SSH_KEY=${DEVSTACK_LBAAS_SSH_KEY_DIR}/${DEVSTACK_LBAAS_SSH_KEY_NAME}
rm -f ${DEVSTACK_LBAAS_SSH_KEY}.pub ${DEVSTACK_LBAAS_SSH_KEY}
ssh-keygen -b 2048 -t rsa -f ${DEVSTACK_LBAAS_SSH_KEY} -N ""
openstack keypair create --public-key=${DEVSTACK_LBAAS_SSH_KEY}.pub ${DEVSTACK_LBAAS_SSH_KEY_NAME}

# Add tcp/22,80 and icmp to default security group

PROJECT_ID=$(openstack project show ${PROJECT_NAME} -f value -c id)
DEFAULT_SEC_GROUP_ID=$(openstack security group list --project ${PROJECT_ID} | awk '/default/ {print $2}')
openstack security group rule create --protocol tcp --dst-port 22:22 ${DEFAULT_SEC_GROUP_ID}
openstack security group rule create --protocol tcp --dst-port 80:80 ${DEFAULT_SEC_GROUP_ID}
openstack security group rule create --protocol icmp ${DEFAULT_SEC_GROUP_ID}
# Boot some instances
NOVA_BOOT_ARGS="--key-name ${DEVSTACK_LBAAS_SSH_KEY_NAME} --image $(openstack image show cirros-0.4.0-x86_64-disk -f value -c id) --flavor 1 --nic net-id=$(openstack network show private -f value -c id)"

openstack server create ${NOVA_BOOT_ARGS} node1
openstack server create ${NOVA_BOOT_ARGS} node2

echo "Waiting ${BOOT_DELAY} seconds for instances to boot"
sleep ${BOOT_DELAY}

IP1=$(openstack server show node1 | awk '/private/ {ip = substr($4, 9, length($4)-9) ; if (ip ~ "\\.") print ip ; else print $5}')
IP2=$(openstack server show node2 | awk '/private/ {ip = substr($4, 9, length($4)-9) ; if (ip ~ "\\.") print ip ; else print $5}')

touch ~/.ssh/known_hosts

# Get Neutron router namespace details
NAMESPACE_NAME='qrouter-'$(openstack router show router1 -f value -c id)
NAMESPACE_CMD_PREFIX='sudo ip netns exec'

# Run a simple web server on the instances
chmod 0755 ${TOP_DIR}/webserver.sh
$NAMESPACE_CMD_PREFIX $NAMESPACE_NAME scp -i ${DEVSTACK_LBAAS_SSH_KEY} -o StrictHostKeyChecking=no ${TOP_DIR}/webserver.sh cirros@${IP1}:webserver.sh
$NAMESPACE_CMD_PREFIX $NAMESPACE_NAME scp -i ${DEVSTACK_LBAAS_SSH_KEY} -o StrictHostKeyChecking=no ${TOP_DIR}/webserver.sh cirros@${IP2}:webserver.sh
$NAMESPACE_CMD_PREFIX $NAMESPACE_NAME ssh -o UserKnownHostsFile=/dev/null -i ${DEVSTACK_LBAAS_SSH_KEY} -o StrictHostKeyChecking=no -q cirros@${IP1} "screen -d -m sh webserver.sh"
$NAMESPACE_CMD_PREFIX $NAMESPACE_NAME ssh -o UserKnownHostsFile=/dev/null -i ${DEVSTACK_LBAAS_SSH_KEY} -o StrictHostKeyChecking=no -q cirros@${IP2} "screen -d -m sh webserver.sh"


wait_for_loadbalancer_active $LB_NAME
openstack loadbalancer listener create $LB_NAME --protocol HTTP --protocol-port 80 --name $LISTENER_NAME
wait_for_loadbalancer_active $LB_NAME
openstack loadbalancer pool create --lb-algorithm ROUND_ROBIN --listener $LISTENER_NAME --protocol HTTP --name $POOL_NAME
wait_for_loadbalancer_active $LB_NAME
openstack loadbalancer member create --subnet-id $SUBNET_ID --address $IP1 --protocol-port 80 $POOL_NAME
wait_for_loadbalancer_active $LB_NAME
openstack loadbalancer member create --subnet-id $SUBNET_ID --address $`IP2 --protocol-port 80 $POOL_NAME

a
echo "How to test load balancing:"
echo ""
echo "${NAMESPACE_CMD_PREFIX} ${NAMESPACE_NAME} curl $(openstack loadbalancer show ${LB_NAME} -f value -c vip_address)"
echo ""

