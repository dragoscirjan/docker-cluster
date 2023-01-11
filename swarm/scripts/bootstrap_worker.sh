#! /bin/bash
set -ex

config_path="/vagrant/configs"


#
# Install necessary packages
#
bash $(dirname $0)/bootstrap.sh

#
# Wait for master
#
while true; do
    if [[ -f $config_path/join.sh ]]; then
        break;
    fi
    echo "Waiting 5 secconds for swarm to finish on master..."
    sleep 5
done

#
# Join the Cluster
#
/bin/bash $config_path/join.sh
