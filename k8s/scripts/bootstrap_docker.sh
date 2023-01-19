#! /bin/bash
set -ex

REPOSITORY_ADDR="$1"

source $(dirname $0)/.env

#
# Hosts
#
echo "${HOST_IP_RANGE/\*/101} registry.$HOST_ROOT_FQDN" >> /etc/hosts
count=1
while [ $count -lt $(($K8S_MAX_NODES + 2)) ]; do
  ipEnd=$(($count + 100))
  echo "${HOST_IP_RANGE/\*/$ipEnd} k8s-$count.$HOST_ROOT_FQDN" >> /etc/hosts
  count=$(($count + 1))
done

#
# Docker install
#
curl -sSL https://get.docker.com | bash

mkdir -p /etc/systemd/system/docker.service.d

tee /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF


if [[ "$REGISTRY_ADDR" != "" ]]; then
  cat /etc/docker/daemon.json | jq ". +{\"insecure-registries\" : [\"$REGISTRY_ADDR:5000\", \"registry.$HOST_ROOT_FQDN:5000\"]}" | tee /etc/docker/daemon.json
else
  cat /etc/docker/daemon.json | jq ". +{\"insecure-registries\" : [\"registry.$HOST_ROOT_FQDN:5000\"]}" | tee /etc/docker/daemon.json
fi

systemctl daemon-reload
systemctl enable docker
systemctl restart docker
# systemctl status docker

usermod -g vagrant -G docker vagrant