#! /bin/bash
set -ex

config_path="/vagrant/configs"

REPOSITORY_ADDR="$1"

# ADVERTISE_ADDR="$2"

# if [ "$ADVERTISE_ADDR" == "" ]; then
#     # ADVERTISE_ADDR=$(ip addr show | grep -E "inet [0-9]" | grep -Ev " (lo|docker)" | tail -n 1 | awk '{print $2}' | awk -F'/' '{print $1}')
#     ADVERTISE_ADDR="$(ip --json a s | jq -r '.[] | if .ifname == "enp0s8" then .addr_info[] | if .family == "inet" then .local else empty end else empty end')"
# fi


#
# Install necessary packages
#

bash $(dirname $0)/bootstrap.sh $REPOSITORY_ADDR

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
# @see https://docs.docker.com/registry/insecure/
#
sudo -i -u vagrant bash << EOF
whoami
mkdir -p /home/vagrant/.kube
sudo cp -i $config_path/config /home/vagrant/.kube/
sudo chown 1000:1000 /home/vagrant/.kube/config
NODENAME=$(hostname -s)
kubectl label node $(hostname -s) node-role.kubernetes.io/worker=worker
EOF

#
# Private registry (comment if not required)
#

# bash /varant/scripts/registry.sh

kubectl delete secret regcred || true

kubectl create secret docker-registry regcred --docker-server=$REPOSITORY_ADDR --docker-username=testuser --docker-password=testpassword

kubectl get secret regcred --output=yaml