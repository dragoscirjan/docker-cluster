#! /bin/bash
echo $@ | egrep "\-v" > /dev/null && set -ex

source $(dirname $0)/env.sh

advertiseAddr=$CLUSTER_IP_MASTER
registryAddr=$CLUSTER_IP_REGISTRY
deployMaster=0
deployRegistry=0
deployWorker=0
clusterType=swarm # swarm | k8s

# Function to print help message
do_help() {
  echo "Usage: script-name [options]"
  echo "Options:"
  echo "  --registry"
  echo "  --master"
  echo "  --worker"
  echo "  -c, --cluster <cluster>    Set the advertise address (default: $CLUSTER_IP_MASTER)"
  echo "  --cluster=<cluster>        Set the advertise address"
  echo "  -a, --advertise-address <address>    Set the advertise address (default: $CLUSTER_IP_MASTER)"
  echo "  --advertise-address=<address>        Set the advertise address"
  echo "  --deploy-registry                    Deploy docker registry"
  echo "  -r, --registry-address <address>     Set the registry address (default: $CLUSTER_IP_REGISTRY)"
  echo "  --registry-address=<address>         Set the registry address"
  echo "  -h, --help                           Show help information"
}

# Function to parse command-line arguments
parse_args() {
  POSITIONAL_ARGS=()

  while [[ $# -gt 0 ]]; do
    case $1 in
      --master)
        deployMaster=1
        shift # past argument
        shift # past value
        ;;
      --registry)
        deployRegistry=1
        shift # past argument
        shift # past value
        ;;
      --worker)
        deployWorker=1
        shift # past argument
        shift # past value
        ;;
      -a|--advertise-address)
        advertiseAddr="$2"
        shift # past argument
        shift # past value
        ;;
      --advertise-address=*)
        advertiseAddr="${1#*=}"
        shift # past argument=value
        ;;
      --registry-address)
        registryAddr="$2"
        shift # past argument
        shift # past value
        ;;
      -r|--registry-address=*)
        registryAddr="${1#*=}"
        shift # past argument=value
        ;;
      -h|--help)
        do_help
        exit 0
        ;;
      -v)
        verbose=1
        shift # past argument
        ;;
      -*|--*)
        echo "Unknown option $1"
        exit 1
        ;;
      *)
        POSITIONAL_ARGS+=("$1") # save positional arg
        shift # past argument
        ;;
    esac
  done

  set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters
}

# Function for verbose output
verbose_output() {
  if [[ $verbose -eq 1 ]]; then
    echo "deployMaster=$deployMaster"
    echo "deployRegistry=$deployRegistry"
    echo "deployWorker=$deployWorker"
    echo "advertiseAddr=$advertiseAddr"
    echo "registryAddr=$registryAddr"
  fi
}

# Main function that executes the script
main() {
  parse_args "$@"
  verbose_output

  source $(dirname "$0")/lib/utils.sh
  deploy_utils
  deploy_certificate

  source $(dirname "$0")/lib/docker.sh
  deploy_docker
  if [[ $deployRegistry -eq 1 ]]; then deploy_docker_registry; test_docker_registry; fi

  # source $(dirname "$0")/lib/cluster/${clusterType}.sh
  # [[ $deployMaster -eq 1 ]] && deploy_master
  # [[ $deployWorker -eq 1 ]] && deploy_worker

}

# Call to main function
main "$@"
