

deploy_master() {
  echo "Deploying Docker Swarm Master..."
}

deploy_registry() {
  echo "Deploying Docker Registry..."
}

deploy_worker() {
  echo "Deploying Docker Swarm Worker..."
}


# #! /bin/bash
# echo $@ | egrep "\-v" > /dev/null && set -ex

# export CLUSTER_ENVSH_PATH=$(dirname $0)/..
# export CLUSTER_ENV_PATH=$(dirname $0)/../..
# source $CLUSTER_ENVSH_PATH/env.sh
# source $(dirname $0)/../args.sh

# #
# # Install necessary packages
# #
# source $(dirname $0)/../docker.sh

# #
# # /etc/hosts
# #

# printf "%s\n" "$ETC_HOSTS" >> /etc/hosts

# #
# # Configure master
# #

# docker swarm init --advertise-addr $advertiseAddr --listen-addr $advertiseAddr

# #
# # Create Swarm Node Join Script
# #
# touch $WORKERS_CONFIG_PATH/join.sh
# chmod +x $WORKERS_CONFIG_PATH/join.sh

# echo "docker swarm join --token $(docker swarm join-token worker -q) $advertiseAddr:2377" > $WORKERS_CONFIG_PATH/join.sh

# //////////////////////

# #! /bin/bash
# echo $@ | egrep "\-v" > /dev/null && set -ex

# export CLUSTER_ENVSH_PATH=$(dirname $0)/..
# export CLUSTER_ENV_PATH=$(dirname $0)/../..
# source $CLUSTER_ENVSH_PATH/env.sh
# source $(dirname $0)/../args.sh

# #
# # Install necessary packages
# #
# source $(dirname $0)/../docker.sh

# #
# # /etc/hosts
# #

# printf "%s\n" "$ETC_HOSTS" >> /etc/hosts

# #
# # Wait for master
# #
# while true; do
#     if [[ -f $WORKERS_CONFIG_PATH/join.sh ]]; then
#         break;
#     fi
#     echo "Waiting 5 secconds for swarm to finish on master..."
#     sleep 5
# done

# #
# # Join the Cluster
# #
# /bin/bash $WORKERS_CONFIG_PATH/join.sh
