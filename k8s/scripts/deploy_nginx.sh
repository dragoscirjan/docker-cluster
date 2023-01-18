#! /bin/bash

scripts_path="/vagrant/scripts"

kubectl apply -f $scripts_path/nginx-deployment.yml
kubectl get deployment

kubectl apply -f $scripts_path/nginx-service.yml
kubectl get service

kubectl describe service nginx-service