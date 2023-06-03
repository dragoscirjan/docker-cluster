
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

  # registry

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

# test docker registry authentication
test_docker_registry() {
  cat >> /tmp/Dockerfile <<EOF
# syntax=docker/dockerfile:1
FROM python:3.4-alpine
ADD . /code
WORKDIR /code
RUN pip install -r requirements.txt
CMD ["python", "app.py"]
EOF

  cat >> /tmp/app.py <<EOF
from flask import Flask
from redis import Redis
from socket import gethostname


app = Flask(__name__)
redis = Redis(host='redis', port=6379)

@app.route('/')
def hello():
    count = redis.incr('hits')
    return 'Hello World! I have been seen, on {}, {} times.\n'.format(gethostname(), count)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=True)
EOF

  cat >> /tmp/requirements.txt <<EOF
flask
redis
EOF

  # docker login $registryAddr:5000 -u testuser -p testpassword
  docker login registry.$CLUSTER_FQDN_ROOT:5000 -u testuser -p testpassword

  cd $(dirname $0)

  docker build -t py/app /tmp

  # docker tag py/app $registryAddr:5000/py-app
  docker tag py/app registry.$CLUSTER_FQDN_ROOT:5000/py-app

  # docker push $registryAddr:5000/py-app
  docker push registry.$CLUSTER_FQDN_ROOT:5000/py-app
}
