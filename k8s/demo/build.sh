#! /bin/bash

back_to=$(pwd)

ADVERTISE_ADDR="$1"
if [ "$ADVERTISE_ADDR" == "" ]; then
    # ADVERTISE_ADDR=$(ip addr show | grep -E "inet [0-9]" | grep -Ev " (lo|docker)" | tail -n 1 | awk '{print $2}' | awk -F'/' '{print $1}')
    ADVERTISE_ADDR="$(ip --json a s | jq -r '.[] | if .ifname == "enp0s8" then .addr_info[] | if .family == "inet" then .local else empty end else empty end')"
fi

# 
# @see https://docs.docker.com/registry/deploying/
#

docker login $ADVERTISE_ADDR:5000 -u testuser -p testpassword

cd $(dirname $0)

docker build -t py/app .

docker tag py/app $ADVERTISE_ADDR:5000/py-app

docker push $ADVERTISE_ADDR:5000/py-app

cd $back_to