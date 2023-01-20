#! /bin/bash
set -ex

source $(dirname $0)/../scripts/.env

config_path="/vagrant/configs"

back_to=$(pwd)

# 
# @see https://docs.docker.com/registry/deploying/
#

REGISTRY_PORT=$(kubectl describe service registry-service -n docker-registry | grep NodePort | awk '{print $3}' | awk -F '/' '{print $1}')

# docker login $REGISTRY_ADDR:$REGISTRY_PORT -u testuser -p testpassword
docker login registry.$HOST_ROOT_FQDN:$REGISTRY_PORT -u testuser -p testpassword

cd $(dirname $0)

docker build -t py-app .

# docker tag py/app $REGISTRY_ADDR:$REGISTRY_PORT/py-app
docker tag py-app registry.$HOST_ROOT_FQDN:$REGISTRY_PORT/py-app

# docker push $REGISTRY_ADDR:$REGISTRY_PORT/py-app
docker push registry.$HOST_ROOT_FQDN:$REGISTRY_PORT/py-app

# yq -i ".spec.template.spec.containers[0].image = \"$REGISTRY_ADDR:$REGISTRY_PORT/py-app\"" ./py-app-deployment.yml
yq -i ".spec.template.spec.containers[0].image = \"registry.$HOST_ROOT_FQDN:$REGISTRY_PORT/py-app\"" ./py-app-deployment.yml

kubectl delete secret private-registry-credentials
kubectl apply -f $config_path/private-registry-credentials.yaml
# kubectl apply -f $config_path/../scripts/private-registry-credentials-clear.yaml

kubectl --insecure-skip-tls-verify apply -f ./py-app-deployment.yml
kubectl get deployment

kubectl --insecure-skip-tls-verify apply -f ./py-app-service.yml
kubectl get service

kubectl describe service py-app-service

kubectl get pods -A

kubectl get pods -A | grep py-app- | head -n 1 | awk '{print $2}' | xargs kubectl describe pod

cd $back_to