#! /bin/bash

configure_docker_registry() {
    #
    # Auth File
    #

    docker ps -a | grep registry:2 | awk '{ print $1 }' | xargs docker rm -f || true

    mkdir -p $config_path/auth

    docker pull httpd:2

    docker run \
    --entrypoint htpasswd \
    httpd:2 -Bbn testuser testpassword > $config_path/auth/htpasswd

    docker ps -a | grep httpd:2 | awk '{ print $1 }' | xargs docker rm -f || true

    #
    # Certificate
    #

    mkdir -p $config_path/certs
    rm -rf $config_path/certs/*.*
    bash $(dirname $0)/generate-ssc.sh \
    --ip $REGISTRY_ADDR \
    --fqdn registry.$HOST_ROOT_FQDN \
    --output $config_path/certs \
    --subj "/C=FR/ST=NoOne/L=NoOne/O=NoOne/OU=NoOne/CN=*.$HOST_ROOT_FQDN/emailAddress=noone@$HOST_ROOT_FQDN"

    cp $config_path/certs/leaf.crt /usr/local/share/ca-certificates/$HOST_ROOT_FQDN.crt

    #
    # Registry
    #

    docker run -d \
    -p 5000:5000 \
    --restart=always \
    --name registry \
    -v $config_path/auth:/auth \
    -e "REGISTRY_AUTH=htpasswd" \
    -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
    -v $config_path/certs:/certs \
    -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/leaf.crt \
    -e REGISTRY_HTTP_TLS_KEY=/certs/leaf.key \
    registry:2
}

# #
# # Kubernetes stuff
# #

# mkdir -p $config_path
# cat > $config_path/k8s-configure-private-registry.sh << EOF
# #! /bin/bash
# set -ex

# kubectl delete secret private-registry-credentials || true

# # docker login --username=testuser --password=testpassword $REGISTRY_ADDR:5000
# docker login --username=testuser --password=testpassword registry.$HOST_ROOT_FQDN:5000

# kubectl create secret generic private-registry-credentials --from-file=.dockerconfigjson=/home/vagrant/.docker/config.json --type=kubernetes.io/dockerconfigjson --from-file=registry-ca=$config_path/certs/root.crt

# kubectl get secret private-registry-credentials --output=yaml > $config_path/private-registry-credentials.yaml
# EOF