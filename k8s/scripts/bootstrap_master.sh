#! /bin/bash
set -ex

config_path="/vagrant/configs"

REPOSITORY_ADDR="$1"

ADVERTISE_ADDR="$2"

# if [ "$ADVERTISE_ADDR" == "" ]; then
#     # ADVERTISE_ADDR=$(ip addr show | grep -E "inet [0-9]" | grep -Ev " (lo|docker)" | tail -n 1 | awk '{print $2}' | awk -F'/' '{print $1}')
#     ADVERTISE_ADDR="$(ip --json a s | jq -r '.[] | if .ifname == "enp0s8" then .addr_info[] | if .family == "inet" then .local else empty end else empty end')"
# fi


#
# Install necessary packages
#

bash $(dirname $0)/bootstrap.sh $REPOSITORY_ADDR

#
# Configure master
#

kubeadm init \
    --apiserver-advertise-address=$ADVERTISE_ADDR \
    --apiserver-cert-extra-sans=$ADVERTISE_ADDR \
    --pod-network-cidr=192.168.0.0/16 \
    --node-name "$(hostname -s)" \
    --cri-socket=/var/run/crio/crio.sock \
    --ignore-preflight-errors Swap

#
# Configure Local K8S
#
mkdir -p "$HOME"/.kube
sudo cp -i /etc/kubernetes/admin.conf "$HOME"/.kube/config
sudo chown "$(id -u)":"$(id -g)" "$HOME"/.kube/config

#
# Create K8S Node Join Script
#

mkdir -p $config_path

cp -i /etc/kubernetes/admin.conf $config_path/config
touch $config_path/join.sh
chmod +x $config_path/join.sh

tee $config_path/join.sh <<EOF 
#! /bin/bash
set -ex

$(kubeadm token create --print-join-command) --cri-socket=/var/run/crio/crio.sock
EOF

#
# Install Calico Network Plugin
#

# curl https://docs.projectcalico.org/manifests/calico.yaml -O
# kubectl apply -f calico.yaml


#
# Installing Flannel Network Plugin
#

kubectl apply -f /vagrant/scripts/kube-flannel.yml

#
# Install Metrics Server
#

kubectl apply -f https://raw.githubusercontent.com/scriptcamp/kubeadm-scripts/main/manifests/metrics-server.yaml

#
# Install Kubernetes Dashboard
#

kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.5.1/aio/deploy/recommended.yaml

# Create Dashboard User

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
EOF

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF

sleep 10

kubectl -n kubernetes-dashboard get secret "$(kubectl -n kubernetes-dashboard get sa/admin-user -o jsonpath="{.secrets[0].name}")" -o go-template="{{.data.token | base64decode}}" >> $config_path/token

sudo -i -u vagrant bash << EOF
whoami
mkdir -p /home/vagrant/.kube
sudo cp -i $config_path/config /home/vagrant/.kube/
sudo chown 1000:1000 /home/vagrant/.kube/config
EOF

#
# Private registry (comment if not required)
# @see https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/1
#

sudo -i -u vagrant bash << EOF
kubectl delete secret regcred || true

kubectl create secret docker-registry regcred --docker-server=$REPOSITORY_ADDR --docker-username=testuser --docker-password=testpassword

kubectl get secret regcred --output=yaml
EOF

#
# Install ArgoCD
#
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

tee $config_path/configs/get-argocd-pwd.sh <<EOF
# /bin/bash
set -ex

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
EOF