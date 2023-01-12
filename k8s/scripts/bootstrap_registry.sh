#! /bin/bash
set -ex

#
# @see https://docs.docker.com/registry/deploying/
#

config_path="/vagrant/configs"

#
# Install necessary packages
#

apt-get update -y
apt install -y apt-transport-https \
  ca-certificates \
  curl \
  jq \
  net-tools \
  openssh-server

#
# Docker install
#

bash $(dirname $0)/bootstrap_docker.sh

#
# Auth File
#

docker ps -a | grep registry:2 | awk '{ print $1 }' | xargs docker rm -f || true

rm -rf $config_path

mkdir -p $config_path/auth
docker run \
  --entrypoint htpasswd \
  httpd:2 -Bbn testuser testpassword > $config_path/auth/htpasswd

docker ps -a | grep httpd:2 | awk '{ print $1 }' | xargs docker rm -f || true

#
# Certificate
#

mkdir -p $config_path/certs
openssl req -new -newkey rsa:4096 -x509 -sha256 -days 365 -nodes \
    -out $config_path/certs/domain.crt \
    -keyout $config_path/certs/domain.key \
    -subj "/C=FR/ST=NoOne/L=NoOne/O=NoOne/OU=NoOne/CN=*.k8s.foo/emailAddress=noone@k8s.foo"

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
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
  registry:2