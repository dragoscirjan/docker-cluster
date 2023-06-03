
# check if binary is present
check_binary() {
  local binary=$1
  local exit_code=${2:-1}  # use 1 as the default exit code

  if ! command -v $binary &> /dev/null; then
    echo "Error: $binary was not found." >&2
    exit $exit_code
  fi
}

ERROR_CODE_MISSING_OPENSSL=2

# Utils install
deploy_utils() {
  printf "%s\n" "$ETC_HOSTS" >> /etc/hosts

  apt-get update
  apt-get install -y \
      curl \
      jq \
      net-tools \
      openssh-server \
      openssl

  jq_version=$(curl -s https://github.com/mikefarah/yq/releases | grep "tag\/" | head -n 1 | awk -F '[/"]' '{print $11}')
  curl -L -o /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/${jq_version}/yq_linux_arm64
}


# Certificate
deploy_certificate() {
  check_binary openssl $ERROR_CODE_MISSING_OPENSSL

  mkdir -p $WORKERS_CONFIG_PATH

  rootCert=$WORKERS_CONFIG_PATH/certs/root.crt
  if [[ ! -f $rootCert ]]; then
    mkdir -p $WORKERS_CONFIG_PATH/certs

    bash $(dirname $0)/bin/openssl-ssc.sh \
      --ip $registryAddr \
      --fqdn registry.$CLUSTER_FQDN_ROOT \
      --output $WORKERS_CONFIG_PATH/certs \
      --subj "/C=FR/ST=NoOne/L=NoOne/O=NoOne/OU=NoOne/CN=*.$CLUSTER_FQDN_ROOT/emailAddress=no-one@$CLUSTER_FQDN_ROOT"
  fi

  cp $rootCert /usr/local/share/ca-certificates/$CLUSTER_FQDN_ROOT.crt
}
