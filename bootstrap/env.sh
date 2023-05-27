#! /bin/bash

source $(dirname $0)/../../.env

#
# New Env Variables
#
chunk=$(echo $CLUSTER_IP_RANGE | awk -F '.' '{ print $4 }')
range=$(echo $CLUSTER_IP_RANGE | awk -F '.' '{ print $1 "." $2 "." $3 }')

CLUSTER_IP_REGISTRY="$range.$(($chunk + 1))"
CLUSTER_IP_MASTER="$range.$(($chunk + 2))"

CLUSTER_FQDN_REGISTRY="registry.$CLUSTER_FQDN_ROOT $CLUSTER_IP_REGISTRY"
CLUSTER_FQDN_MASTER="master.$CLUSTER_FQDN_ROOT $CLUSTER_IP_MASTER"

CLUSTER_FQDN_WORKERS=""
for ((i=1; i<$CLUSTER_SIZE; i++)); do
  CLUSTER_FQDN_WORKERS="$CLUSTER_FQDN_WORKERS
node$(($i + 1)).$CLUSTER_FQDN_ROOT "$range.$(($chunk + 2 + $i))""
done

ETC_HOSTS="$CLUSTER_FQDN_REGISTRY
$CLUSTER_FQDN_MASTER$CLUSTER_FQDN_WORKERS"