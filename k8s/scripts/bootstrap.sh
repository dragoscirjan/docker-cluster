#! /bin/bash
set -ex

REPOSITORY_ADDR="$1"

source $(dirname $0)/.env

# #
# # temporary SSH key
# #
# cp /vagrant/scripts/id_rsa ~/.ssh/id_rsa_tmp
# cp /vagrant/scripts/id_rsa.pub ~/.ssh/id_rsa_tmp.pub
# chmod 600 ~/.ssh/id_rsa_tmp* 

# cat ~/.ssh/id_rsa_tmp.pub >> ~/.ssh/authorized_keys

# #
# # new SSH key (if required)
# #
# test -f "$HOME/.ssh/id_rsa" || ssh-keygen -t rsa -C "`hostname`" -f "$HOME/.ssh/id_rsa" -P "" -q

#
# disable swap
#
sudo swapoff -a

#
# keeps the swaf off during reboot
#
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true


#
# see https://computingforgeeks.com/deploy-kubernetes-cluster-on-ubuntu-with-kubeadm/
#

apt-get update -y
apt install -y apt-transport-https \
  ca-certificates \
  curl \
  jq \
  net-tools \
  openssh-server

curl -L -o /usr/bin/yq https://github.com/mikefarah/yq/releases/download/v4.30.8/yq_linux_amd64
chmod 755 /usr/bin/yq

#
# Docker install
#

bash $(dirname $0)/bootstrap_docker.sh $REGISTRY_ADDR

#
# pre configure
#

# Create the .conf file to load the modules at bootup
cat <<EOF | sudo tee /etc/modules-load.d/crio.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set up required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system


#
# @see https://scriptcrunch.com/install-cri-o-ubuntu/
#

OS=xUbuntu_20.04
CRIO_VERSION=1.23
echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /"|sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$OS/ /" | tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION.list

curl -L https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION/$OS/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers.gpg add -
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers.gpg add -

apt-get update -y
apt-get install cri-o cri-o-runc cri-tools -y

systemctl daemon-reload
systemctl enable crio --now
systemctl restart crio
systemctl status crio

crictl info

#
# Kubectl install
#

curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg \
    https://packages.cloud.google.com/apt/doc/apt-key.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] \
    https://apt.kubernetes.io/ kubernetes-xenial main" \
    | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt install -y kubelet="$KUBERNETES_VERSION" kubectl="$KUBERNETES_VERSION" kubeadm="$KUBERNETES_VERSION"
apt-mark hold kubelet kubeadm kubectl

kubectl version --client && kubeadm version

systemctl daemon-reload
systemctl enable kubelet
systemctl restart kubelet
systemctl status kubelet

# enp0s8 => current network name

local_ip="$(ip --json a s | jq -r '.[] | if .ifname == "enp0s8" then .addr_info[] | if .family == "inet" then .local else empty end else empty end')"
cat > /etc/default/kubelet << EOF
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
EOF