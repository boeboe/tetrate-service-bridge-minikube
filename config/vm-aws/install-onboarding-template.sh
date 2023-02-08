#!/usr/bin/env bash

# Download and install the onboarding packages
curl -k -fL -o /tmp/onboarding-agent.deb "https://vm-onboarding.tetrate.prod/install/deb/amd64/onboarding-agent.deb" --resolve "vm-onboarding.tetrate.prod:443:__TSB_VM_ONBOARDING_ENDPOINT__"
curl -k -fL -o /tmp/istio-sidecar.deb "https://vm-onboarding.tetrate.prod/install/deb/amd64/istio-sidecar.deb" --resolve "vm-onboarding.tetrate.prod:443:__TSB_VM_ONBOARDING_ENDPOINT__"
apt-get install -o Dpkg::Options::="--force-confold" -y /tmp/onboarding-agent.deb
apt-get install -o Dpkg::Options::="--force-confold" -y /tmp/istio-sidecar.deb
rm /tmp/onboarding-agent.deb
rm /tmp/istio-sidecar.deb

# Allow the Envoy sidecar to bind privileged ports, such as port 80 (needed for the obs-tester egress)
setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/envoy

# Install Sample JWT Credential Plugin
# DOC: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/quickstart/on-premise/configure-vm
# SRC: https://github.com/tetrateio/onboarding-agent-sample-jwt-credential-plugin

curl -fL "https://dl.cloudsmith.io/public/tetrate/onboarding-examples/raw/files/onboarding-agent-sample-jwt-credential-plugin_0.0.1_$(uname -s)_$(uname -m).tar.gz" \
 | tar -xz onboarding-agent-sample-jwt-credential-plugin
mv onboarding-agent-sample-jwt-credential-plugin /usr/local/bin/
