#! /bin/bash
set -ex

source $(dirname $0)/../scripts/.env

config_path="/vagrant/configs"

back_to=$(pwd)

# 
# @see https://docs.docker.com/registry/deploying/
#

REGISTRY_PORT=$(kubectl describe service registry -n docker-registry | grep NodePort | awk '{print $3}' | awk -F '/' '{print $1}')

# docker login $REGISTRY_ADDR:$REGISTRY_PORT -u $DOCKER_REGISTRY_USERNAME -p $DOCKER_REGISTRY_PASSWORD 
docker login registry.$HOST_ROOT_FQDN:$REGISTRY_PORT -u $DOCKER_REGISTRY_USERNAME -p $DOCKER_REGISTRY_PASSWORD

cd $(dirname $0)

docker build -t py-app .

# docker tag py/app $REGISTRY_ADDR:$REGISTRY_PORT/py-app
docker tag py-app registry.$HOST_ROOT_FQDN:$REGISTRY_PORT/py-app

# docker push $REGISTRY_ADDR:$REGISTRY_PORT/py-app
docker push registry.$HOST_ROOT_FQDN:$REGISTRY_PORT/py-app

# yq -i ".spec.template.spec.containers[0].image = \"$REGISTRY_ADDR:$REGISTRY_PORT/py-app\"" ./py-app-deployment.yml
yq -i ".spec.template.spec.containers[0].image = \"registry.$HOST_ROOT_FQDN:$REGISTRY_PORT/py-app\"" ./py-app-deployment.yml

kctlns=" -n py-app"

# kubectl get service -n py-app | awk '{print $1}' | xargs kubectl delete service -n py-app
# kubectl get deployment -n py-app | awk '{print $1}' | xargs kubectl delete deployment -n py-app

kubectl delete secret registry-auth $kctlns || true
kubectl delete -f ./py-app-service.yml || true
kubectl delete -f ./py-app-deployment.yml || true
kubectl delete namespace py-app || true

# namespace
kubectl create namespace py-app

# reg secret
kubectl create secret generic registry-auth $kctlns \
  --from-file=.dockerconfigjson=/home/vagrant/.docker/config.json \
  --type=kubernetes.io/dockerconfigjson
kubectl get secret registry-auth $kctlns \
  --output=yaml \
  > $K8S_CONFIG_PATH/registry-auth.yaml

# deployment
kubectl apply -f ./py-app-deployment.yml
kubectl get deployment $kctlns
kubectl get deployment $kctlns | grep "1/1" | awk '{print $1}' | xargs kubectl describe deployment $kctlns

# service
kubectl apply -f ./py-app-service.yml
kubectl get service $kctlns
kubectl get service $kctlns | grep -v NAME | awk '{print $1}' | xargs kubectl describe service $kctlns

# pods
kubectl get pods $kctlns
# kubectl get pods $kctlns | grep py-app- | head -n 1 | awk '{print $2}' | xargs kubectl describe pod $kctlns

sleep 5

PY_APP_PORT=$(kubectl describe service py-app-service -n py-app | grep "NodePort:" | awk '{print $3}' | awk -F '/' '{print $1}')
curl -sL http://k8s-1.$HOST_ROOT_FQDN:$PY_APP_PORT

cd $back_to