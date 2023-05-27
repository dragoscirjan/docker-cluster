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
# Wait for master
#
while true; do
    if [[ -f $WORKERS_CONFIG_PATH/join.sh ]]; then
        break;
    fi
    echo "Waiting 5 secconds for swarm to finish on master..."
    sleep 5
done

#
# Join the Cluster
#
/bin/bash $WORKERS_CONFIG_PATH/join.sh
