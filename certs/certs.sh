#!/usr/bin/env bash

if [[ $1 = "root-ca" ]]; then
  make -f Makefile.selfsigned.mk root-ca 
  exit 0
fi

if [[ $1 = "mgmt-cluster" ]]; then
  make -f Makefile.selfsigned.mk mgmt-cluster-cacerts
  exit 0
fi

if [[ $1 = "active-cluster" ]]; then
  make -f Makefile.selfsigned.mk active-cluster-cacerts
  exit 0
fi

if [[ $1 = "standby-cluster" ]]; then
  make -f Makefile.selfsigned.mk standby-cluster-cacerts
  exit 0
fi

if [[ $1 = "vm-onboarding-client" ]]; then
  DOMAIN=vm-onboarding.tetrate.prod
  mkdir -p ./vm-onboarding
  openssl req -out ./vm-onboarding/client.${DOMAIN}.csr -newkey rsa:4096 -sha512 -nodes -keyout ./vm-onboarding/client.${DOMAIN}.key -subj "/CN=client.${DOMAIN}/O=Customer/C=US/ST=CA"
  openssl x509 -req -sha512 -days 3650 -CA ./root-cert.pem -CAkey ./root-key.pem -set_serial 1 -in ./vm-onboarding/client.${DOMAIN}.csr -out ./vm-onboarding/client.${DOMAIN}.pem
  exit 0
fi

if [[ $1 = "vm-onboarding-server" ]]; then
  DOMAIN=vm-onboarding.tetrate.prod
  mkdir -p ./vm-onboarding
  openssl req -out ./vm-onboarding/server.${DOMAIN}.csr -newkey rsa:4096 -sha512 -nodes -keyout ./vm-onboarding/server.${DOMAIN}.key -subj "/CN=${DOMAIN}/O=Tetrate/C=US/ST=CA"
  openssl x509 -req -sha512 -days 3650 -CA ./root-cert.pem -CAkey ./root-key.pem -set_serial 0 -in ./vm-onboarding/server.${DOMAIN}.csr -out ./vm-onboarding/server.${DOMAIN}.pem -extfile <(printf "subjectAltName=DNS:${DOMAIN},DNS:*.${DOMAIN},DNS:localhost")
  cat ./vm-onboarding/server.${DOMAIN}.pem ./root-cert.pem >> ./vm-onboarding/server.${DOMAIN}-bundle.pem
  exit 0
fi

if [[ $1 = "app-abc-client" ]]; then
  DOMAIN=abc.tetrate.prod
  mkdir -p ./app-abc
  openssl req -out ./app-abc/client.${DOMAIN}.csr -newkey rsa:4096 -sha512 -nodes -keyout ./app-abc/client.${DOMAIN}.key -subj "/CN=client.${DOMAIN}/O=Customer/C=US/ST=CA"
  openssl x509 -req -sha512 -days 3650 -CA ./root-cert.pem -CAkey ./root-key.pem -set_serial 1 -in ./app-abc/client.${DOMAIN}.csr -out ./app-abc/client.${DOMAIN}.pem
  exit 0
fi

if [[ $1 = "app-abc-server" ]]; then
  DOMAIN=abc.tetrate.prod
  mkdir -p ./app-abc
  openssl req -out ./app-abc/server.${DOMAIN}.csr -newkey rsa:4096 -sha512 -nodes -keyout ./app-abc/server.${DOMAIN}.key -subj "/CN=${DOMAIN}/O=Tetrate/C=US/ST=CA"
  openssl x509 -req -sha512 -days 3650 -CA ./root-cert.pem -CAkey ./root-key.pem -set_serial 0 -in ./app-abc/server.${DOMAIN}.csr -out ./app-abc/server.${DOMAIN}.pem -extfile <(printf "subjectAltName=DNS:${DOMAIN},DNS:*.${DOMAIN},DNS:localhost")
  cat ./app-abc/server.${DOMAIN}.pem ./root-cert.pem >> ./app-abc/server.${DOMAIN}-bundle.pem
  exit 0
fi

if [[ $1 = "app-def-client" ]]; then
  DOMAIN=def.tetrate.prod
  mkdir -p ./app-def
  openssl req -out ./app-def/client.${DOMAIN}.csr -newkey rsa:4096 -sha512 -nodes -keyout ./app-def/client.${DOMAIN}.key -subj "/CN=client.${DOMAIN}/O=Customer/C=US/ST=CA"
  openssl x509 -req -sha512 -days 3650 -CA ./root-cert.pem -CAkey ./root-key.pem -set_serial 1 -in ./app-def/client.${DOMAIN}.csr -out ./app-def/client.${DOMAIN}.pem
  exit 0
fi

if [[ $1 = "app-def-server" ]]; then
  DOMAIN=def.tetrate.prod
  mkdir -p ./app-def
  openssl req -out ./app-def/server.${DOMAIN}.csr -newkey rsa:4096 -sha512 -nodes -keyout ./app-def/server.${DOMAIN}.key -subj "/CN=${DOMAIN}/O=Tetrate/C=US/ST=CA"
  openssl x509 -req -sha512 -days 3650 -CA ./root-cert.pem -CAkey ./root-key.pem -set_serial 0 -in ./app-def/server.${DOMAIN}.csr -out ./app-def/server.${DOMAIN}.pem -extfile <(printf "subjectAltName=DNS:${DOMAIN},DNS:*.${DOMAIN},DNS:localhost")
  cat ./app-def/server.${DOMAIN}.pem ./root-cert.pem >> ./app-def/server.${DOMAIN}-bundle.pem
  exit 0
fi

########################################
### Print the generated certificates ###
########################################

if [[ $1 = "print-root-ca" ]]; then
  openssl x509 -in ./root-cert.pem -text
  exit 0
fi

if [[ $1 = "print-mgmt-cluster" ]]; then
  openssl x509 -in ./mgmt-cluster/ca-cert.pem -text
  exit 0
fi

if [[ $1 = "print-active-cluster" ]]; then
  openssl x509 -in ./active-cluster/ca-cert.pem -text
  exit 0
fi

if [[ $1 = "print-standby-cluster" ]]; then
  openssl x509 -in ./standby-cluster/ca-cert.pem -text
  exit 0
fi

if [[ $1 = "print-vm-onboarding-client" ]]; then
  DOMAIN=vm-onboarding.tetrate.prod
  openssl x509 -in ./vm-onboarding/client.${DOMAIN}.pem -text
  exit 0
fi

if [[ $1 = "print-vm-onboarding-server" ]]; then
  DOMAIN=vm-onboarding.tetrate.prod
  openssl x509 -in ./vm-onboarding/server.${DOMAIN}.pem -text
  exit 0
fi

if [[ $1 = "print-app-abc-client" ]]; then
  DOMAIN=abc.tetrate.prod
  openssl x509 -in ./app-abc/client.${DOMAIN}.pem -text
  exit 0
fi

if [[ $1 = "print-app-abc-server" ]]; then
  DOMAIN=abc.tetrate.prod
  openssl x509 -in ./app-abc/server.${DOMAIN}.pem -text
  exit 0
fi

if [[ $1 = "print-app-def-client" ]]; then
  DOMAIN=def.tetrate.prod
  openssl x509 -in ./app-def/client.${DOMAIN}.pem -text
  exit 0
fi

if [[ $1 = "print-app-def-server" ]]; then
  DOMAIN=def.tetrate.prod
  openssl x509 -in ./app-def/server.${DOMAIN}.pem -text
  exit 0
fi

echo "Please specify one of the following action:"
echo "  - root-ca"
echo "  - mgmt-cluster"
echo "  - active-cluster"
echo "  - standby-cluster"
echo "  - vm-onboarding-client"
echo "  - vm-onboarding-server"
echo "  - app-abc-client"
echo "  - app-abc-server"
echo "  - app-def-client"
echo "  - app-def-server"
echo "  - print-root-ca"
echo "  - print-mgmt-cluster"
echo "  - print-active-cluster"
echo "  - print-standby-cluster"
echo "  - print-vm-onboarding-client"
echo "  - print-vm-onboarding-server"
echo "  - print-app-abc-client"
echo "  - print-app-abc-server"
echo "  - print-app-def-client"
echo "  - print-app-def-server"
exit 1