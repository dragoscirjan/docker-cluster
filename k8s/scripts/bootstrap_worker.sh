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
    echo "Waiting 5 secconds for k8s to finish on master..."
    sleep 5
done

#
# Join the Cluster
#
/bin/bash $config_path/join.sh -v

#
# Configure default user
#
sudo -i -u vagrant bash << EOF
whoami
mkdir -p /home/vagrant/.kube
sudo cp -i $config_path/config /home/vagrant/.kube/
sudo chown 1000:1000 /home/vagrant/.kube/config
NODENAME=$(hostname -s)
kubectl label node $(hostname -s) node-role.kubernetes.io/worker=worker
EOF