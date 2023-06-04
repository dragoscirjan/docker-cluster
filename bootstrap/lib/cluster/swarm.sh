

deploy_master() {
  echo "Deploying Docker Swarm Master..."

  register_docker_registry

  docker swarm init --advertise-addr $advertiseAddr --listen-addr $advertiseAddr

  rm -rf $WORKERS_CONFIG_PATH/join.sh
  touch $WORKERS_CONFIG_PATH/join.sh
  chmod +x $WORKERS_CONFIG_PATH/join.sh

  echo "docker swarm join --token $(docker swarm join-token worker -q) $advertiseAddr:2377" > $WORKERS_CONFIG_PATH/join.sh
}

deploy_worker() {
  echo "Deploying Docker Swarm Worker..."

  register_docker_registry

  # Wait for master
  while true; do
      if [[ -f $WORKERS_CONFIG_PATH/join.sh ]]; then
          break;
      fi
      echo "Waiting 5 secconds for swarm to finish on master..."
      sleep 5
  done

  # join the Cluster
  /bin/bash $WORKERS_CONFIG_PATH/join.sh

  # mark last worker registered
  if [[ "$workerId" == "$CLUSTER_SIZE" ]]; then
    echo "############################################"
    echo "For testing, run the following command under your master machine:"
    echo "bash /vagrant/bootstrap/bootstrap.sh -v --test-cluster"
    echo "############################################"
  fi
}

test_cluster() {
  cat > /tmp/docker-compose.yml <<EOF
version: "3.9"

services:
  web:
    image: registry.$CLUSTER_FQDN_ROOT:5000/py-app
    build: .
    ports:
      - "8000:8000"
    deploy:
      replicas: 3  # Specify the desired number of replicas

  redis:
    image: redis:alpine
EOF

  # docker pull registry.$CLUSTER_FQDN_ROOT:5000/py-app

  docker login registry.$CLUSTER_FQDN_ROOT:5000 \
    -u $DOCKER_REGISTRY_USER -p $DOCKER_REGISTRY_PASS \
  && docker stack deploy --compose-file /tmp/docker-compose.yml \
    --with-registry-auth test --prune

  docker service ls

  count=0

  while true; do
    docker service ps test_web | grep Running \
      && curl http://master.$CLUSTER_FQDN_ROOT:8000 > /dev/null \
      && break;

    count=$(($count + 1))
    if [[ $count -eq 10 ]]; then
      echo "Test failed"
      exit $EXIT_CODE_CLUSTER_TEST_FAILED
    fi
    sleep 5
  done

  for i in {1..10}; do
    curl http://master.$CLUSTER_FQDN_ROOT:8000 \
      || exit $exit $EXIT_CODE_CLUSTER_TEST_FAILED
  done

  for i in {1..10}; do
    curl http://node2.$CLUSTER_FQDN_ROOT:8000 \
      || exit $exit $EXIT_CODE_CLUSTER_TEST_FAILED
  done

  docker stack rm test
  sleep 10
  docker image ls -aq | xargs docker image rm -f
}



