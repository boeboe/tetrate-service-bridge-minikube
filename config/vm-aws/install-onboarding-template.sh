#!/usr/bin/env bash

if which apt-get &>/dev/null ; then 
# Download and install the onboarding packages (DEB)
  curl -k -fL -o /tmp/onboarding-agent.deb "https://vm-onboarding.tetrate.prod/install/deb/amd64/onboarding-agent.deb" --resolve "vm-onboarding.tetrate.prod:443:__TSB_VM_ONBOARDING_ENDPOINT__"
  curl -k -fL -o /tmp/istio-sidecar.deb "https://vm-onboarding.tetrate.prod/install/deb/amd64/istio-sidecar.deb" --resolve "vm-onboarding.tetrate.prod:443:__TSB_VM_ONBOARDING_ENDPOINT__"
  apt-get install -o Dpkg::Options::="--force-confold" -y /tmp/onboarding-agent.deb
  apt-get install -o Dpkg::Options::="--force-confold" -y /tmp/istio-sidecar.deb
  rm /tmp/onboarding-agent.deb
  rm /tmp/istio-sidecar.deb
else
  # Download and install the onboarding packages (RPM)
  curl -k -fL -o /tmp/onboarding-agent.rpm "https://vm-onboarding.tetrate.prod/install/rpm/amd64/onboarding-agent.rpm" --resolve "vm-onboarding.tetrate.prod:443:__TSB_VM_ONBOARDING_ENDPOINT__"
  curl -k -fL -o /tmp/istio-sidecar.rpm "https://vm-onboarding.tetrate.prod/install/rpm/amd64/istio-sidecar.rpm" --resolve "vm-onboarding.tetrate.prod:443:__TSB_VM_ONBOARDING_ENDPOINT__"
  rpm -i /tmp/onboarding-agent.rpm
  rpm -i /tmp/istio-sidecar.rpm
  rm /tmp/onboarding-agent.rpm
  rm /tmp/istio-sidecar.rpm
fi

# Allow the Envoy sidecar to bind privileged ports, such as port 80 (needed for the obs-tester egress)
setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/envoy

# Install Sample JWT Credential Plugin
# DOC: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/quickstart/on-premise/configure-vm
# SRC: https://github.com/tetrateio/onboarding-agent-sample-jwt-credential-plugin

curl -fL "https://dl.cloudsmith.io/public/tetrate/onboarding-examples/raw/files/onboarding-agent-sample-jwt-credential-plugin_0.0.1_$(uname -s)_$(uname -m).tar.gz" \
 | tar -xz onboarding-agent-sample-jwt-credential-plugin
mv onboarding-agent-sample-jwt-credential-plugin /usr/local/bin/
