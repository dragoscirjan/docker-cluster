#! /bin/bash
set -ex

apt install -y curl \
    jq \
    net-tools \
    openssh-server

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
apt-get install docker-compose-plugin