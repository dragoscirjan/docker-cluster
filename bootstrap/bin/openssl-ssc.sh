#!/bin/bash
echo $@ | egrep "\-v" > /dev/null && set -ex

fqdns=("localhost")
ips=("127.0.0.1")
rootPassword='testpassword'
output='./cert'
subj="/C=IL/OU=RND/L=Antarctica/ST=PT/O=FooCom/CN=FooComSelfSigned"
verbose=0

POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -o|--output)
      output="$2"
      shift # past argument
      shift # past value
      ;;
    --output=*)
      output="${1#*=}"
      shift # past argument=value
      ;;
    -p|--password)
      rootPassword="$2"
      shift # past argument
      shift # past value
      ;;
    --password=*)
      rootPassword="${1#*=}"
      shift # past argument=value
      ;;
    -s|--subj)
      subj="$2"
      shift # past argument
      shift # past value
      ;;
    --subj=*)
      subj="${1#*=}"
      shift # past argument=value
      ;;
    --fqdn)
      fqdns+=("$2")
      shift # past argument
      shift # past value
      ;;
    --fqdn=*)
      fqdns+=("${1#*=}")
      shift # past argument=value
      ;;
    --ip)
      ips+=("$2")
      shift # past argument
      shift # past value
      ;;
    --ip=*)
      ips+=("${1#*=}")
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

output=$(realpath $output)
echo $subj | grep "CN=" > /dev/null || subj="$subj/CN=${fqdns[0]}"

if [[ $verbose -eq 1 ]]; then
  echo "fqdns=${fqdns[@]}"
  echo "root-password=$rootPassword"
  echo "output=$output"
  echo "subj=$subj"
fi


mkdir -p $output

if [[ ! -f $output/root.crt ]]; then
  openssl genrsa -des3 -out $output/root.key -passout pass:$rootPassword 4096
  openssl req -x509 -new -nodes -key $output/root.key -sha512 -days 3660 -out $output/root.crt -passin pass:$rootPassword -subj $subj
fi

openssl x509 -in $output/root.crt -text -noout


openssl genrsa -out $output/leaf.key 2048
openssl req -new -sha512 -key $output/leaf.key -subj $subj -out $output/leaf.csr
openssl req -text -noout -verify -in $output/leaf.csr


cat > $output/v3.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
nsCertType = server
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
EOF

count=1
pos=0
for fqdn in ${fqdns[@]}; do
  echo "DNS.$count = ${fqdns[$pos]}" >> $output/v3.ext
  count=$(($count + 1))
  pos=$(($pos + 1))
done
pos=0
for ip in ${ips[@]}; do
  echo "IP.$count = ${ips[$pos]}" >> $output/v3.ext
  count=$(($count + 1))
  pos=$(($pos + 1))
done



# openssl x509 -req -in $output/leaf.csr -CA $output/root.crt -CAkey $output/root.key -CAcreateserial -out $output/leaf.crt -days 3650 -sha512 -extfile $output/v3.ext -passin pass:$rootPassword
# openssl x509 -in $output/leaf.crt -text -noout

openssl x509 -req -in $output/leaf.csr -CA $output/root.crt -CAkey $output/root.key -CAcreateserial -out $output/leaf.crt -days 3650 -sha512 -extfile $output/v3.ext -passin pass:$rootPassword
openssl x509 -in $output/leaf.crt -text -noout

cat $output/root.crt >> $output/leaf.crt