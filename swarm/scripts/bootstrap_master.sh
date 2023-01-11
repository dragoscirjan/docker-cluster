#! /bin/bash
set -ex

config_path="/vagrant/configs"


#
# Install necessary packages
#
bash $(dirname $0)/bootstrap.sh

#
# Configure master
#

ADVERTISE_ADDR="$1"
if [ "$ADVERTISE_ADDR" == "" ]; then
    # ADVERTISE_ADDR=$(ip addr show | grep -E "inet [0-9]" | grep -Ev " (lo|docker)" | tail -n 1 | awk '{print $2}' | awk -F'/' '{print $1}')
    ADVERTISE_ADDR="$(ip --json a s | jq -r '.[] | if .ifname == "enp0s8" then .addr_info[] | if .family == "inet" then .local else empty end else empty end')"
fi

docker swarm init --advertise-addr $ADVERTISE_ADDR --listen-addr $ADVERTISE_ADDR

#
# Create Swarm Node Join Script
#
if [ -d $config_path ]; then
  rm -f $config_path/*
else
  mkdir -p $config_path
fi

touch $config_path/join.sh
chmod +x $config_path/join.sh

echo "docker swarm join --token $(docker swarm join-token worker -q) $ADVERTISE_ADDR:2377" > $config_path/join.sh