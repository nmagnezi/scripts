#!/usr/bin/env bash

LB_NAME="lb_"$RANDOM
MEM_CHECK_INTERVAL=10
LISTENERS_AMOUNT=50
ITERATIONS=100

source /opt/stack/devstack/openrc admin admin

echo "Before we created a loadbalancer" > mem_usage_create_delete.txt
./memexplore.py all neutron-server | grep Total | awk '{print $3}' >> mem_usage_create_delete.txt

neutron lbaas-loadbalancer-create --name $LB_NAME private-subnet
sleep 5
echo "After we created a loadbalancer" >> mem_usage_create_delete.txt
./memexplore.py all neutron-server | grep Total | awk '{print $3}' >> mem_usage_create_delete.txt

echo "Starting to create listeners" >> mem_usage_create_delete.txt

for i in `seq 1 $ITERATIONS`
do
  ./memexplore.py all neutron-server | grep Total | awk '{print $3}' >> mem_usage_create_delete.txt

  for j in `seq 1 $LISTENERS_AMOUNT`
  do
    neutron lbaas-listener-create --loadbalancer $LB_NAME --protocol HTTP --protocol-port $j --name "$LB_NAME"_listener_"$j" -c name --format value >> mem_usage_create_delete.txt
    sleep 2
  done
  for k in `seq 1 $LISTENERS_AMOUNT`
  do
    neutron lbaas-listener-delete "$LB_NAME"_listener_"$k" >> mem_usage_create_delete.txt
    sleep 2
  done
done
neutron lbaas-loadbalancer-delete $LB_NAME >> mem_usage_create_delete.txt
echo "All Done"  >> mem_usage_create_delete.txt
./memexplore.py all neutron-server | grep Total | awk '{print $3}' >> mem_usage_create_delete.txt
