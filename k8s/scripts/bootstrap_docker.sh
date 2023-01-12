#! /bin/bash
set -ex


REPOSITORY_ADDR="$1"

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


if [[ "$REPOSITORY_ADDR" != "" ]]; then
  cat /etc/docker/daemon.json | jq ". +{\"insecure-registries\" : [\"$REPOSITORY_ADDR:5000\"]}" | tee /etc/docker/daemon.json
  # rm /etc/docker/daemon.json
  # mv /etc/docker/daemon2.json /etc/docker/daemon.json
fi

systemctl daemon-reload
systemctl enable docker
systemctl restart docker
# systemctl status docker

usermod -g vagrant -G docker vagrant