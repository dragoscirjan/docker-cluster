
# deploy docker
deploy_docker() {
  curl -sSL https://get.docker.com | bash

  apt-get update -y
  apt-get install -y docker-compose-plugin
}

# deploy docker registry
deploy_docker_registry() {
  # Auth File

  docker ps -a | grep registry:2 | awk '{ print $1 }' | xargs docker rm -f || true

  mkdir -p $WORKERS_CONFIG_PATH/auth

  docker pull httpd:2

  docker run \
    --entrypoint htpasswd \
    httpd:2 -Bbn testuser testpassword > $WORKERS_CONFIG_PATH/auth/htpasswd

  docker ps -a | grep httpd:2 | awk '{ print $1 }' | xargs docker rm -f || true

  # Registry

  docker run -d \
    -p 5000:5000 \
    --restart=always \
    --name registry \
    -v $WORKERS_CONFIG_PATH/auth:/auth \
    -e "REGISTRY_AUTH=htpasswd" \
    -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
    -v $WORKERS_CONFIG_PATH/certs:/certs \
    -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/leaf.crt \
    -e REGISTRY_HTTP_TLS_KEY=/certs/leaf.key \
    registry:2
}
