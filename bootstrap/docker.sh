#! /bin/bash
source $(dirname $0)/docker-args.sh

#
# Utils install
#

apt-get update
apt-get install -y \
    curl \
    jq \
    net-tools \
    openssh-server

jq_version=$(curl -s https://github.com/mikefarah/yq/releases | grep "tag\/" | head -n 1 | awk -F '[/"]' '{print $11}')
curl -L -o /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/${jq_version}/yq_linux_arm64

# #
# # temporary SSH key
# #
# cp /opt/swarm/id_rsa ~/.ssh/id_rsa_tmp
# cp /opt/swarm/id_rsa.pub ~/.ssh/id_rsa_tmp.pub
# chmod 600 ~/.ssh/id_rsa_tmp* 

# cat ~/.ssh/id_rsa_tmp.pub >> ~/.ssh/authorized_keys

# #
# # new SSH key (if required)
# #
# test -f "$HOME/.ssh/id_rsa" || ssh-keygen -t rsa -C "`hostname`" -f "$HOME/.ssh/id_rsa" -P "" -q

#
# Docker install
#
curl -sSL https://get.docker.com | bash


#
# Docker Compose
#
apt-get update -y
apt-get install -y docker-compose-plugin

#
# Docker Registry
#

if [[ $configureRegistry -eq 1 ]]; then
    source $(dirname $0)/docker-registry.sh
fi