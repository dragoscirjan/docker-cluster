#! /bin/bash
echo $@ | egrep "\-v" > /dev/null && set -ex

source $(dirname $0)/../env.sh
source $(dirname $0)/args.sh

#
# Install necessary packages
#
source $(dirname $0)/../docker.sh

#
# /etc/hosts
#

printf "%s\n" "$ETC_HOSTS" >> /etc/hosts

#
# Configure master
#

docker swarm init --advertise-addr $advertiseAddr --listen-addr $advertiseAddr

#
# Create Swarm Node Join Script
#
rm -rf $WORKERS_CONFIG_PATH
mkdir -p $WORKERS_CONFIG_PATH

touch $WORKERS_CONFIG_PATH/join.sh
chmod +x $WORKERS_CONFIG_PATH/join.sh

echo "docker swarm join --token $(docker swarm join-token worker -q) $advertiseAddr:2377" > $WORKERS_CONFIG_PATH/join.sh
