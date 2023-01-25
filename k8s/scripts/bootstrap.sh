#! /bin/bash
set -ex

source $(dirname $0)/.env

#
# install utils
#

apt-get update -y
apt install -y apt-transport-https \
  ca-certificates \
  curl \
  jq \
  net-tools

curl -L -o /usr/bin/yq https://github.com/mikefarah/yq/releases/download/v4.30.8/yq_linux_amd64
chmod 755 /usr/bin/yq

#
# parse options
#
IS_VERBOSE=0
ADVERTISE_ADDR="$(ip --json a s | jq -r '.[] | if .ifname == "enp0s8" then .addr_info[] | if .family == "inet" then .local else empty end else empty end')"
DEPLOY_MASTER=0
DEPLOY_WORKER=0
USE_CRI_O=0
KUBADM_ADDITIONAL_ARGS=""

POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --advertise-address)
      ADVERTISE_ADDR="$2"
      shift # past argument
      shift # past value
      ;;
    --advertise-address=*)
      ADVERTISE_ADDR="${1#*=}"
      shift # past argument=value
      ;;
    -m|--master)
      DEPLOY_MASTER=1
      shift # past argument
      ;;
    -w|--worker)
      DEPLOY_WORKER=1
      shift # past argument
      ;;
    -v|--verbose)
      IS_VERBOSE=1
      shift # past argument
      ;;
    --use-cri-o)
      USE_CRI_O=1
      KUBADM_ADDITIONAL_ARGS="${KUBADM_ADDITIONAL_ARGS} --cri-socket=/var/run/crio/crio.sock"
      shift # past argument
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

if [[ $IS_VERBOSE -eq 1 ]]; then
  echo "ADVERTISE_ADDR=$ADVERTISE_ADDR"
fi

#
# Hosts
#

function write_hosts() {
  echo "${HOST_IP_RANGE/\*/101} registry.$HOST_ROOT_FQDN" >> /etc/hosts
  count=1
  while [ $count -lt $(($K8S_MAX_NODES + 1)) ]; do
    ipEnd=$(($count + 100))
    echo "${HOST_IP_RANGE/\*/$ipEnd} k8s-$count.$HOST_ROOT_FQDN" >> /etc/hosts
    count=$(($count + 1))
  done
}

#
# Cri-o Install
#

function cri_o_install() {
  # Create the .conf file to load the modules at bootup
  cat <<EOF | sudo tee /etc/modules-load.d/crio.conf
overlay
br_netfilter
EOF

  sudo modprobe overlay
  sudo modprobe br_netfilter


  
  @see https://scriptcrunch.com/install-cri-o-ubuntu/
  

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
  sudo systemctl restart crio
  systemctl status crio

  crictl info

  echo
}

#
# Docker install & configure
#

function docker_install() {
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

  # cat /etc/docker/daemon.json | jq ". +{\"insecure-registries\" : [\"registry.$HOST_ROOT_FQDN:5000\"]}" | tee /etc/docker/daemon.json

  systemctl daemon-reload
  systemctl enable docker
  sudo systemctl restart docker
  # systemctl status docker

  usermod -g vagrant -G docker vagrant
}

#
# Helm install
#

function helm_install() {
  curl https://baltocdn.com/helm/signing.asc \
    | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
  sudo apt-get install apt-transport-https --yes
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" \
    | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
  sudo apt-get update
  sudo apt-get install helm -y
}

#
# Wait for all pods to be ready
#
function k8s_wait_all_pods_ready() {
  count=0
  stop=0
  while [ $stop -eq 0 ]; do
    if kubectl get pods -A | grep "0/1" > /dev/null; then
      echo "⚠   ($count) Pods not ready. Please wait ..."
      
      k8s_taint_nodes_if_needed
      
      sleep 10
    else
      echo "ⓘ   All pods ready."
      stop=1
    fi
    count=$(($count + 1))
    if [ $count -ge 100 ]; then exit 1; fi
  done

  echo
}

#
# @link https://stackoverflow.com/questions/59484509/node-had-taints-that-the-pod-didnt-tolerate-error-when-deploying-to-kubernetes
#
function k8s_taint_nodes_if_needed() {
  kubectl get pods -A | grep "0/1" | awk '{print $2 " -n " $1;}' | while read pod_log; do 
    if kubectl describe pod $pod_log \
      | grep "node(s) had taint {node-role.kubernetes.io/master: }, that the pod didn't tolerate" \
      > /dev/null; then
      for node in $(kubectl get nodes --selector='node-role.kubernetes.io/master' | awk 'NR>1 {print $1}' ); do
        kubectl taint node $node node-role.kubernetes.io/master- || true
      done
      sleep 5
      return
    fi
  done
}

#
# K8s install
#

function k8s_install() {

  # Set up required sysctl params, these persist across reboots.
  cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

  sudo sysctl --system

  #
  # Kubectl install
  #

  curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg \
    https://packages.cloud.google.com/apt/doc/apt-key.gpg

  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" \
    | tee /etc/apt/sources.list.d/kubernetes.list

  apt-get update
  apt install -y kubelet="$KUBERNETES_VERSION" kubectl="$KUBERNETES_VERSION" kubeadm="$KUBERNETES_VERSION"
  apt-mark hold kubelet kubeadm kubectl

  kubectl version --client && kubeadm version

  sudo systemctl daemon-reload
  sudo systemctl enable kubelet
  sudo systemctl restart kubelet
  sudo systemctl status kubelet

  # enp0s8 => current network name

  local_ip="$(ip --json a s | jq -r '.[] | if .ifname == "enp0s8" then .addr_info[] | if .family == "inet" then .local else empty end else empty end')"
  cat > /etc/default/kubelet <<EOF
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
EOF

}

#
# Configure master
#
function k8s_init_master() {

  kubeadm init \
      --apiserver-advertise-address=$ADVERTISE_ADDR \
      --apiserver-cert-extra-sans=$ADVERTISE_ADDR \
      --pod-network-cidr=192.168.0.0/16 \
      --node-name "$(hostname -s)" \
      --ignore-preflight-errors Swap $KUBADM_ADDITIONAL_ARGS

  #
  # Configure Local K8S
  #
  mkdir -p "$HOME"/.kube
  cp /etc/kubernetes/admin.conf "$HOME"/.kube/config
  chown "$(id -u)":"$(id -g)" "$HOME"/.kube/config

  #
  # Create K8S Node Join Script
  #

  rm -rf $K8S_CONFIG_PATH
  mkdir -p $K8S_CONFIG_PATH

  cp -i /etc/kubernetes/admin.conf $K8S_CONFIG_PATH/config
  touch $K8S_CONFIG_PATH/join.sh
  chmod +x $K8S_CONFIG_PATH/join.sh

  tee $K8S_CONFIG_PATH/join.sh <<EOF 
#! /bin/bash
set -ex

$(kubeadm token create --print-join-command) $KUBADM_ADDITIONAL_ARGS
EOF

  sudo -i -u vagrant bash << EOF
whoami
mkdir -p /home/vagrant/.kube
sudo cp $K8S_CONFIG_PATH/config /home/vagrant/.kube/
sudo chown 1000:1000 /home/vagrant/.kube/config
EOF

}

#
# Join the Cluster
#
function k8s_init_worker() {
  bash $K8S_CONFIG_PATH/join.sh -v

  #
  # Configure default user
  # @see https://docs.docker.com/registry/insecure/
  #
  KUBECTL_ARGS=--overwrite
  sudo -i -u vagrant bash << EOF
whoami
mkdir -p /home/vagrant/.kube
sudo cp $K8S_CONFIG_PATH/config /home/vagrant/.kube/
sudo chown 1000:1000 /home/vagrant/.kube/config
NODENAME=$(hostname -s)
kubectl label node $(hostname -s) node-role.kubernetes.io/worker=worker $KUBECTL_ARGS
EOF

}

function k8s_add_utils__calico() {
  kubectl delete -f https://docs.projectcalico.org/manifests/calico.yaml || true

  kubectl create -f https://docs.projectcalico.org/manifests/calico.yaml
 
  k8s_wait_all_pods_ready

  sleep 10

  echo
}

#
# Installing Flannel Network Plugin
# @link https://github.com/projectcalico/calico
#
function k8s_add_utils__flannel() {
  yamlUrl="https://raw.githubusercontent.com/coreos/flannel/bc79dd1505b0c8681ece4de4c0d86c5cd2643275/Documentation/kube-flannel.yml"

  kubectl delete -f $yamlUrl || true

  prop="net.bridge.bridge-nf-call-iptables=1"
  if ! cat /etc/sysctl.conf | grep $prop; then
    echo $prop | tee -a /etc/sysctl.conf
    sysctl -p
  fi
  
  kubectl apply -f $yamlUrl

  kubectl get nodes

  echo
}

#
# @link https://cert-manager.io/docs/
#
function k8s_add_utils__cert_manager() {
  helm delete cert-manager || true
  kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.crds.yaml || true
  kubectl delete namespace cert-manager || true

  kubectl create namespace cert-manager
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.crds.yaml
  helm repo add jetstack https://charts.jetstack.io
  helm install cert-manager --namespace cert-manager \
    --version v$K8S_CERT_MANAGER_VERSION jetstack/cert-manager || true

  echo
}

#
# Install Kubernetes Dashboard
#
function k8s_add_utils__dashboard() {
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

  kubectl -n kubernetes-dashboard get secret \
    "$(kubectl -n kubernetes-dashboard get sa/admin-user -o jsonpath="{.secrets[0].name}")" \
    -o go-template="{{.data.token | base64decode}}" >> $K8S_CONFIG_PATH/token

  echo
}

#
# Install ArgoCD
#
function k8s_add_utils__argo_cd() {
  kubectl delete -n argocd -f \
    https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml || true
  kubectl delete namespace argocd || true

  kubectl create namespace argocd
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  k8s_wait_all_pods_ready

  tee $K8S_CONFIG_PATH/get-argocd-pwd.sh <<EOF
# /bin/bash
set -ex

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
EOF

  echo
}

#
# K8s Master Utils
#
function k8s_add_utils() {
  # # TODO: create option to select between calico and flannel
  if [ $K8S_USE_FLANNEL -eq 0 ]; then
    k8s_add_utils__calico
  else
    k8s_add_utils__flannel
  fi

  if [ $K8S_USE_REGISTRY_WITH_CERT_MANAGER -eq 1 ]; then
    k8s_add_utils__cert_manager
  fi

  k8s_add_utils__dashboard

  k8s_add_utils__argo_cd

  echo

}

function k8s_registry_namespace() {
  #
  # name space
  #
  kubectl delete namespace $K8S_REGISTRY_NAMESPACE || true
  kubectl create namespace $K8S_REGISTRY_NAMESPACE
}

#
# @link https://cert-manager.io/docs/configuration/selfsigned/
#
function k8s_registry_certificate_cert_manager() {
  kubectl delete -f /tmp/cert.yaml || true
  kubectl delete -f /tmp/ca.yaml || true
  
  
  # keep secrets clean also
  kubectl get secret -n $K8S_REGISTRY_NAMESPACE \
    | grep -v NAME | awk '{print $1}' \
    | xargs kubectl delete secret -n $K8S_REGISTRY_NAMESPACE || true


  # @link https://cert-manager.io/docs/reference/api-docs/#cert-manager.io/v1.Issuer
  # @link https://cert-manager.io/docs/reference/api-docs/#cert-manager.io/v1.Certificate
  cat > /tmp/ca.yaml <<EOF
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: registry-ca-issuer
  namespace: $K8S_REGISTRY_NAMESPACE
spec:
  # TODO: Add passphrase to CA
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: registry-ca-certificate
  namespace: $K8S_REGISTRY_NAMESPACE
spec:
  secretName: registry-ca-secret
  issuerRef:
    name: registry-ca-issuer
    kind: Issuer
  commonName: registry-ca
  isCA: true
EOF

  # @link https://cert-manager.io/docs/reference/api-docs/#cert-manager.io/v1.Certificate
  cat > /tmp/cert.yaml <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: registry-certificate
  namespace: $K8S_REGISTRY_NAMESPACE
spec:
  secretName: registry-com-tls
  issuerRef:
    name: registry-ca-issuer
    kind: Issuer
  commonName: registry.$HOST_ROOT_FQDN
  dnsNames:
    - registry.$HOST_ROOT_FQDN
  ipAddresses:
    - $ADVERTISE_ADDR
  subject:
    organizations:
      - NoOne
    organizationalUnits:
      - NoOne
    countries:
      - FR
    localities:
      - NoOne
EOF

  kubectl apply -f /tmp/ca.yaml
  kubectl apply -f /tmp/cert.yaml

  rm -rf $K8S_CONFIG_PATH/certs
  mkdir -p $K8S_CONFIG_PATH/certs

  kubectl get secret -n docker-registry registry-ca-secret \
    -o jsonpath='{.data.ca\.crt}' | base64 -d \
    > $K8S_CONFIG_PATH/certs/root.crt

  kubectl get secret -n docker-registry registry-ca-secret \
    -o jsonpath='{.data.tls\.crt}' | base64 -d \
    >> $K8S_CONFIG_PATH/certs/root.crt

  kubectl get secret -n docker-registry registry-ca-secret \
    -o jsonpath='{.data.tls\.key}' | base64 -d \
    > $K8S_CONFIG_PATH/certs/root.key

  echo
}

function k8s_registry_certificate_openssl() {
  rm -rf $K8S_CONFIG_PATH/certs
  mkdir -p $K8S_CONFIG_PATH/certs
  
  bash $(dirname $0)/generate-ssc.sh \
    --ip $ADVERTISE_ADDR \
    --fqdn registry.$HOST_ROOT_FQDN \
    --output $K8S_CONFIG_PATH/certs \
    --subj "/C=FR/ST=NoOne/L=NoOne/O=NoOne/OU=NoOne/CN=*.$HOST_ROOT_FQDN/emailAddress=noone@$HOST_ROOT_FQDN"
    
  echo
}

function k8s_registry_certificate() {
  if [ $K8S_REGISTRY_CERT_WITH_CERT_MANAGER -eq 1 ]; then
    k8s_registry_certificate_cert_manager
  else
    k8s_registry_certificate_openssl
  fi

  k8s_registry_publish_certificate

  echo 
}

function k8s_registry_publish_certificate() {
  # TODO: will need adaptation for cert-manager

  sudo cp $K8S_CONFIG_PATH/certs/root.* /usr/local/share/ca-certificates/
  sudo update-ca-certificates

  sudo systemctl restart docker
  sudo systemctl restart kubelet

  k8s_wait_all_pods_ready

  echo
}

function k8s_registry_auth() {
  mkdir -p $K8S_CONFIG_PATH/auth

  docker pull httpd:2

  docker run \
    --entrypoint htpasswd \
    httpd:2 -Bbn $DOCKER_REGISTRY_USERNAME $DOCKER_REGISTRY_PASSWORD > $K8S_CONFIG_PATH/auth/htpasswd
}

#
# K8s Registry Deployment
# @see https://archive-docs.d2iq.com/dkp/kaptain/1.2.0/sdk/0.3.x/private-registries/
#
function k8s_registry_deployment_v2() {
  mkdir -p $K8S_CONFIG_PATH/registry

  kubectl delete deployment registry -n $K8S_REGISTRY_NAMESPACE || true
  
  cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: registry
  namespace: $K8S_REGISTRY_NAMESPACE
  labels:
    app: registry
spec:
  replicas: 1
  selector:
    matchLabels:
      app: registry
  template:
    metadata:
      labels:
        app: registry
    spec:
      volumes:
      - name: auth-vol
        hostPath:
          path: $K8S_CONFIG_PATH/auth
          type: Directory
      - name: certs-vol
        hostPath:
          path: $K8S_CONFIG_PATH/certs
          type: Directory
      - name: registry-vol
        hostPath:
          path: $K8S_CONFIG_PATH/registry
          type: Directory

      containers:
        - image: registry:2
          name: registry
          imagePullPolicy: IfNotPresent
          env:
          - name: REGISTRY_HTTP_TLS_CERTIFICATE
            value: "/certs/leaf.crt"
          - name: REGISTRY_HTTP_TLS_KEY
            value: "/certs/leaf.key"
          - name: REGISTRY_AUTH
            value: htpasswd
          - name: REGISTRY_AUTH_HTPASSWD_REALM
            value: Registry Realm
          - name: REGISTRY_AUTH_HTPASSWD_PATH
            value: /auth/htpasswd
          ports:
            - containerPort: 5000
          volumeMounts:
          - name: auth-vol
            mountPath: /auth
          - name: certs-vol
            mountPath: /certs
          - name: registry-vol
            mountPath: /var/lib/registry
EOF

  kubectl get deployments -n $K8S_REGISTRY_NAMESPACE
  kubectl describe deployment registry -n $K8S_REGISTRY_NAMESPACE
  
  kubectl get pods -n $K8S_REGISTRY_NAMESPACE
  kubectl get pods -n $K8S_REGISTRY_NAMESPACE  | grep registry | awk '{print $1}' \
    | xargs kubectl describe pod -n $K8S_REGISTRY_NAMESPACE

  count=0
  stop=0
  while [ $stop -eq 0 ]; do
    if kubectl get pods -n $K8S_REGISTRY_NAMESPACE  \
      | grep registry | awk '{print $1}' \
      | xargs kubectl describe pod -n $K8S_REGISTRY_NAMESPACE \
      | grep "Started container registry" > /dev/null; then

      echo "ⓘ   Registry started."
      stop=1
    else
      echo "⚠   ($count) Registry not started yet. Please wait..."
      k8s_taint_nodes_if_needed
      sleep 10
    fi
    count=$(($count + 1))
    if [ $count -ge 100 ]; then exit 1; fi
  done

  echo
}

#
# K8s Docker Registry
# @see https://rpi4cluster.com/k3s/k3s-docker-tls/
#

#
# registry service
#
function k8s_registry_service() {
  kubectl delete service registry -n $K8S_REGISTRY_NAMESPACE || true
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: registry
  namespace: $K8S_REGISTRY_NAMESPACE
spec:
  selector:
    app: registry
  type: LoadBalancer
  ports:
    - name: docker-port
      protocol: TCP
      port: 5000
      targetPort: 5000
  loadBalancerIP: $ADVERTISE_ADDR
EOF
  kubectl get services -n $K8S_REGISTRY_NAMESPACE
  kubectl describe service registry -n $K8S_REGISTRY_NAMESPACE

  sleep 5

  REGISTRY_PORT=$(kubectl describe service registry -n $K8S_REGISTRY_NAMESPACE | grep NodePort | awk '{print $3}' | awk -F '/' '{print $1}')

  sudo -i -u vagrant bash <<EOF
docker login registry.$HOST_ROOT_FQDN:$REGISTRY_PORT \
  -u $DOCKER_REGISTRY_USERNAME -p $DOCKER_REGISTRY_PASSWORD
EOF
}


function k8s_registry() {
  sleep 30
  
  k8s_registry_namespace

  k8s_registry_certificate
  k8s_registry_auth

  # # k8s_registry_deployment_v1
  k8s_registry_deployment_v2

  k8s_registry_service

  echo
}

function k8s_registry__worker() {
  k8s_registry_publish_certificate

  echo
}

######################################################

#
# disable swap & keep the swap off during reboot
#

sudo swapoff -a
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true

write_hosts


if [ $USE_CRI_O -eq 1]; then
  cri_o_install
else
  docker_install
fi

k8s_install

helm_install

if [ $DEPLOY_MASTER -eq 1 ]; then
  k8s_init_master
  
  k8s_add_utils
  k8s_registry
else
  k8s_init_worker

  k8s_registry__worker
fi