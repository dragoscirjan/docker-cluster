#! /bin/bash
source $(dirname $0)/../env.sh

do_help() {
  echo "Usage: script-name [options]"
  echo "Options:"
  echo "  -a, --advertise-address <address>    Set the advertise address (default: $CLUSTER_IP_MASTER)"
  echo "  --advertise-address=<address>        Set the advertise address"
  echo "  --registry-address <address>         Set the registry address (default: $CLUSTER_IP_REGISTRY)"
  echo "  -r, --registry-address=<address>     Set the registry address"
  echo "  -h, --help                           Show help information"
}

advertiseAddr=$CLUSTER_IP_MASTER
registryAddr=$CLUSTER_IP_REGISTRY

POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
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