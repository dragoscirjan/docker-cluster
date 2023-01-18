#! /bin/bash

back_to=$(pwd)

REGISTRY_ADDR="$1"
if [ "$REGISTRY_ADDR" == "" ]; then
    # REGISTRY_ADDR=$(ip addr show | grep -E "inet [0-9]" | grep -Ev " (lo|docker)" | tail -n 1 | awk '{print $2}' | awk -F'/' '{print $1}')
    REGISTRY_ADDR="$(ip --json a s | jq -r '.[] | if .ifname == "enp0s8" then .addr_info[] | if .family == "inet" then .local else empty end else empty end')"
fi

# 
# @see https://docs.docker.com/registry/deploying/
#

docker login $REGISTRY_ADDR:5000 -u testuser -p testpassword

cd $(dirname $0)

docker build -t py/app .

docker tag py/app $REGISTRY_ADDR:5000/py-app

docker push $REGISTRY_ADDR:5000/py-app


# yq -i ".spec.selector.app = \"$REGISTRY_ADDR:5000/py-app\"" ./py-app-service.yml
# yq -i ".spec.selector.matchLabels.app = \"$REGISTRY_ADDR:5000/py-app\"" ./py-app-deployment.yml
# yq -i ".spec.template.metadata.labels.app = \"$REGISTRY_ADDR:5000/py-app\"" ./py-app-deployment.yml
yq -i ".spec.template.spec.containers[0].image = \"$REGISTRY_ADDR:5000/py-app\"" ./py-app-deployment.yml

kubectl apply -f ./py-app-deployment.yml
kubectl get deployment

kubectl apply -f ./py-app-service.yml
kubectl get service

kubectl describe service py-app-service

cd $back_to