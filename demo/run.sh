#! /bin/bash
set -ex

#
# @see https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/
#


back_to=$(pwd)

cd $(dirname $0)

kubectl delete pod py-app || true

kubectl apply -f pod.yml
kubectl get pod py-app


cd $back_to