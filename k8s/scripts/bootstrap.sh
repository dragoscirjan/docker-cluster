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
  systemctl restart docker
  # systemctl status docker

  usermod -g vagrant -G docker vagrant
}


#
# K8s install
#

function k8s_install() {

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

  curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg

  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" \
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
      --cri-socket=/var/run/crio/crio.sock \
      --ignore-preflight-errors Swap

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

$(kubeadm token create --print-join-command) --cri-socket=/var/run/crio/crio.sock
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

#
# K8s Master Utils
#
function k8s_add_master_utils() {
  #
  # Install Calico Network Plugin
  #

  curl https://docs.projectcalico.org/manifests/calico.yaml -O
  kubectl apply -f calico.yaml

  rm -f calico.yaml

  # #
  # # Installing Flannel Network Plugin
  # #

  # echo "net.bridge.bridge-nf-call-iptables=1" | tee -a /etc/sysctl.conf
  # sysctl -p
  # kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/bc79dd1505b0c8681ece4de4c0d86c5cd2643275/Documentation/kube-flannel.yml
  # kubectl get nodes

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

  kubectl -n kubernetes-dashboard get secret "$(kubectl -n kubernetes-dashboard get sa/admin-user -o jsonpath="{.secrets[0].name}")" -o go-template="{{.data.token | base64decode}}" >> $K8S_CONFIG_PATH/token

  #
  # Install ArgoCD
  #
  kubectl create namespace argocd
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  tee $K8S_CONFIG_PATH/get-argocd-pwd.sh <<EOF
# /bin/bash
set -ex

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
EOF

}

function k8s_master_configure_registry_certificate() {
  rm -rf $K8S_CONFIG_PATH/certs
  mkdir -p $K8S_CONFIG_PATH/certs
  
  bash $(dirname $0)/generate-ssc.sh \
    --ip $ADVERTISE_ADDR \
    --fqdn registry.$HOST_ROOT_FQDN \
    --output $K8S_CONFIG_PATH/certs \
    --subj "/C=FR/ST=NoOne/L=NoOne/O=NoOne/OU=NoOne/CN=*.$HOST_ROOT_FQDN/emailAddress=noone@$HOST_ROOT_FQDN"
  
  # openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  #   -keyout $K8S_CONFIG_PATH/certs/leaf.key \
  #   -out $K8S_CONFIG_PATH/certs/leaf.crt \
  #   -subj "/CN=registry.$HOST_ROOT_FQDN" \
  #   -addext "subjectAltName=DNS:registry.$HOST_ROOT_FQDN,DNS:*.registry.$HOST_ROOT_FQDN,IP:$ADVERTISE_ADDR"

  k8s_worker_configure_registry_certificate
}

function k8s_worker_configure_registry_certificate() {
  cp $K8S_CONFIG_PATH/certs/root.* /usr/local/share/ca-certificates/
  update-ca-certificates

  systemctl restart docker
  systemctl restart kubelet
}

function k8s_master_configure_registry_auth() {
  mkdir -p $K8S_CONFIG_PATH/auth

  docker pull httpd:2

  docker run \
    --entrypoint htpasswd \
    httpd:2 -Bbn $DOCKER_REGISTRY_USERNAME $DOCKER_REGISTRY_PASSWORD > $K8S_CONFIG_PATH/auth/htpasswd
}

function k8s_registry_namespace() {
  #
  # name space
  #
  kubectl delete namespace docker-registry || true
  kubectl create namespace docker-registry
}

#
# K8s Registry Deployment
# @see https://kubernetes.io/docs/concepts/storage/persistent-volumes/
#
function k8s_master_create_registry_deployment_v1() {
#   kubectl delete pvc docker-registry-persistent-volume -n docker-registry || true
#   cat <<EOF | kubectl apply -f -
# apiVersion: v1
# kind: PersistentVolumeClaim
# metadata:
#   name: docker-registry-persistent-volume
#   namespace: docker-registry
# spec:
#   accessModes:
#     - ReadWriteOnce
#   storageClassName: longhorn
#   resources:
#     requests:
#       storage: 15Gi
# EOF
#   kubectl get pvc -n docker-registry
#   kubectl describe pvc docker-registry-persistent-volume -n docker-registry

  #
  # registry deployment
  #
  kubectl delete deployment registry -n docker-registry || true
  cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: registry
  namespace: docker-registry
spec:
  replicas: 1
  selector:
    matchLabels:
      app: registry
  template:
    metadata:
      labels:
        app: registry
        name: registry
    spec:
      nodeSelector:
        node-type: worker
      containers:
      - name: registry
        image: registry:2
        ports:
        - containerPort: 5000
        env:
        - name: REGISTRY_HTTP_TLS_CERTIFICATE
          value: "/certs/tls.crt"
        - name: REGISTRY_HTTP_TLS_KEY
          value: "/certs/tls.key"
        volumeMounts:
        # - name: lv-storage
        #   mountPath: /var/lib/registry
        #   subPath: registry
        - name: certs
          mountPath: /certs
      volumes:
        # - name: lv-storage
        #   persistentVolumeClaim:
        #     claimName: docker-registry-persistent-volume
        - name: certs
          secret:
            secretName: docker-registry-auth-cert
EOF
  kubectl get deployments -n docker-registry
  kubectl describe deployment registry -n docker-registry
  
  kubectl get pods -n docker-registry
  kubectl get pods -n docker-registry  \
    | grep registry | awk '{print $1}' \
    | xargs kubectl describe pod -n docker-registry
}

#
# K8s Registry Deployment
# @see https://archive-docs.d2iq.com/dkp/kaptain/1.2.0/sdk/0.3.x/private-registries/
#
function k8s_master_create_registry_deployment_v2() {
  mkdir -p $K8S_CONFIG_PATH/registry
  kubectl delete deployment registry -n docker-registry || true
  cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: registry
  namespace: docker-registry
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
  kubectl get deployments -n docker-registry
  kubectl describe deployment registry -n docker-registry
  
  kubectl get pods -n docker-registry
  kubectl get pods -n docker-registry  | grep registry | awk '{print $1}' | xargs kubectl describe pod -n docker-registry
}

#
# K8s Docker Registry
# @see https://rpi4cluster.com/k3s/k3s-docker-tls/
#

#
# registry service
#
function k8s_master_create_registry_service() {
  kubectl delete service registry-service -n docker-registry || true
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: registry-service
  namespace: docker-registry
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
  kubectl get services -n docker-registry
  kubectl describe service registry-service -n docker-registry
}


function k8s_master_configure_registry() {
  sleep 30

  k8s_master_configure_registry_certificate
  k8s_master_configure_registry_auth
  
  k8s_registry_namespace

  # k8s_master_create_registry_deployment_v1
  k8s_master_create_registry_deployment_v2

  k8s_master_create_registry_service

 
  REGISTRY_PORT=$(kubectl describe service registry-service -n docker-registry | grep NodePort | awk '{print $3}' | awk -F '/' '{print $1}')
  
  # https://jamesdefabia.github.io/docs/user-guide/kubectl/kubectl_create_secret_docker-registry/
  kubectl delete secret registry-auth || true
  kubectl create secret docker-registry registry-auth \
    --docker-username=$DOCKER_REGISTRY_USERNAME \
    --docker-password=$DOCKER_REGISTRY_PASSWORD \
    --insecure-skip-tls-verify=true
    # --from-file=registry-ca=$K8S_CONFIG_PATH/certs/root.crt \

  kubectl get secret registry-auth \
    --output=yaml \
    > $K8S_CONFIG_PATH/registry-auth.yaml
}

function k8s_worker_configure_registry() {
  sudo -i -u vagrant bash << EOF
whoami
kubectl delete secret registry-auth || true
kubectl apply -f $K8S_CONFIG_PATH/registry-auth.yaml
EOF
}

######################################################

#
# disable swap & keep the swap off during reboot
#

sudo swapoff -a
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true

write_hosts

docker_install

k8s_install

if [ $DEPLOY_MASTER -eq 1 ]; then
  k8s_init_master
  
  k8s_add_master_utils
  k8s_master_configure_registry
else
  k8s_init_worker

  k8s_worker_configure_registry_certificate
  k8s_worker_configure_registry
fi