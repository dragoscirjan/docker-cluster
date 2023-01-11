#! /bin/bash
set -ex

apt install -y curl openssh-server

#
# temporary SSH key
#
cp /opt/swarm/id_rsa ~/.ssh/id_rsa_tmp
cp /opt/swarm/id_rsa.pub ~/.ssh/id_rsa_tmp.pub
chmod 600 ~/.ssh/id_rsa_tmp* 

cat ~/.ssh/id_rsa_tmp.pub >> ~/.ssh/authorized_keys

#
# new SSH key (if required)
#
test -f "$HOME/.ssh/id_rsa" || ssh-keygen -t rsa -C "`hostname`" -f "$HOME/.ssh/id_rsa" -P "" -q

#
# Docker install
#
curl -sSL https://get.docker.com | bash

#
# Minikube install
#

# see https://minikube.sigs.k8s.io/docs/start/

# curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
# sudo install minikube-linux-amd64 /usr/local/bin/minikube

curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube_latest_amd64.deb
sudo dpkg -i minikube_latest_amd64.deb

usermod -g vagrant -G adm,dialout,cdrom,floppy,sudo,audio,dip,video,plugdev,netdev,lxd,docker vagrant
groups vagrant

echo 'alias kubectl="minikube kubectl --"' >> /home/vagrant/.bashrc

sudo -H -u vagrant bash -c 'minikube start'
sleep 5
sudo -H -u vagrant bash -c 'kubectl get po -A'

sudo -H -u vagrant bash -c 'kubectl create deployment hello-minikube --image=kicbase/echo-server:1.0'
sudo -H -u vagrant bash -c 'kubectl expose deployment hello-minikube --type=NodePort --port=8080'
sudo -H -u vagrant bash -c 'kubectl port-forward service/hello-minikube 7080:8080'
