#! /bin/bash



# #
# # Kubernetes stuff
# #

# mkdir -p $WORKERS_CONFIG_PATH
# cat > $WORKERS_CONFIG_PATH/k8s-configure-private-registry.sh << EOF
# #! /bin/bash
# set -ex

# kubectl delete secret private-registry-credentials || true

# # docker login --username=testuser --password=testpassword $REGISTRY_ADDR:5000
# docker login --username=testuser --password=testpassword registry.$CLUSTER_FQDN_ROOT:5000

# kubectl create secret generic private-registry-credentials --from-file=.dockerconfigjson=/home/vagrant/.docker/config.json --type=kubernetes.io/dockerconfigjson --from-file=registry-ca=$WORKERS_CONFIG_PATH/certs/root.crt

# kubectl get secret private-registry-credentials --output=yaml > $WORKERS_CONFIG_PATH/private-registry-credentials.yaml
# EOF
