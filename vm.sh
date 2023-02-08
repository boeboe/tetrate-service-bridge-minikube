#!/usr/bin/env bash

ACTION=${1}

ACTIVE_CLUSTER_PROFILE=active-cluster-m2
ACTIVE_CLUSTER_CONFDIR=./config/active-cluster

VM_ONBOARDING_CERTDIR=./certs/vm-onboarding
VM_CONFDIR=./config/vm-aws
VM_K8S_CONFDIR=${VM_CONFDIR}/k8s


if [[ ${ACTION} = "on-minikube-host" ]]; then

  # Check if this is not accidently running on vm host
  if ! which minikube &>/dev/null ; then
    echo "Minikube seems not to be installed on this system. Sure this is the minikube host?"
    exit 1
  fi

  # Check if VM_GW_IP is set
  if [[ -z "${VM_GW_IP}" ]]; then
    echo "Could not find ENV variable VM_GW_IP, please set this to the IP address of the host running minikube"
    exit 1
  fi

  # Patch metallb pool so the vmgateway gets an AWS routable ip (host ip)
  envsubst < ${ACTIVE_CLUSTER_CONFDIR}/metallb-configmap-patch-template.yaml > ${ACTIVE_CLUSTER_CONFDIR}/metallb-configmap-patch.yaml
  kubectl apply ${ACTIVE_CLUSTER_CONFDIR}/metallb-configmap-patch.yaml
  kubectl -n metallb-system rollout restart deploy

  # Create secret for vm-onboarding gateway https
  kubectl config use-context ${ACTIVE_CLUSTER_PROFILE} ;
  if ! kubectl get secret vm-onboarding -n istio-system &>/dev/null ; then
    kubectl create secret tls vm-onboarding -n istio-system \
      --key ${VM_ONBOARDING_CERTDIR}/server.vm-onboarding.tetrate.prod.key \
      --cert ${VM_ONBOARDING_CERTDIR}/server.vm-onboarding.tetrate.prod.pem ;
  fi

  # Apply vm onboarding patch to create a VM gateway and allow jwt based onboarding
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/quickstart/on-premise/configure-workload-onboarding#allow-workloads-to-authenticate-themselves-by-means-of-a-jwt-token
  kubectl -n istio-system patch controlplanes controlplane --patch-file ${ACTIVE_CLUSTER_CONFDIR}/onboarding-vm-patch.yaml --type merge ;

  # Create WorkloadGroup, Sidecar and OnboardingPolicy for app
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/quickstart/on-premise/configure-workload-onboarding
  kubectl apply -f ${VM_K8S_CONFDIR} ;

  echo "Going to patch metallb pool for vmgateway"
  while ! $(kubectl annotate svc -n istio-system vmgateway metallb.universe.tf/address-pool=vmgateway --overwrite &>/dev/null) ; do
    sleep 2
    echo -n "."
  done
  echo "DONE"

  echo "Getting vm gateway external ip address"
  while ! VM_GW_IP=$(kubectl get svc -n istio-system vmgateway --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ; do
    echo -n "."
  done
  echo "DONE"

  # Installing systemd service for tsb-gui, vw-gateway and vm-repo exposure
  export KUBECTL=$(which kubectl)
  envsubst < ./config/tsb-gui-template.service > ./config/tsb-gui.service ;
  sudo cp ./config/tsb-gui.service /etc/systemd/system ;
  if systemctl is-active tsb-gui.service &>/dev/null ; then sudo systemctl stop tsb-gui 2>/dev/null && sudo systemctl daemon-reload ; fi
  sudo systemctl enable tsb-gui ;
  sudo systemctl start tsb-gui ;
  sleep 3

  envsubst < ./config/vm-gateway-template.service > ./config/vm-gateway.service ;
  sudo cp ./config/vm-gateway.service /etc/systemd/system ;
  if systemctl is-active vm-gateway.service &>/dev/null ; then sudo systemctl stop vm-gateway 2>/dev/null && sudo systemctl daemon-reload ; fi
  sudo systemctl enable vm-gateway ;
  sudo systemctl start vm-gateway ;
  sleep 3

  envsubst < ./config/vm-repo-template.service > ./config/vm-repo.service ;
  sudo cp ./config/vm-repo.service /etc/systemd/system ;
  if systemctl is-active vm-repo.service &>/dev/null ; then sudo systemctl stop vm-repo 2>/dev/null && sudo systemctl daemon-reload ; fi
  sudo systemctl enable vm-repo ;
  sudo systemctl start vm-repo ;

  exit 0
fi


if [[ ${ACTION} = "on-vm-host" ]]; then

  # Check if this is not accidently running on minikube host
  if which minikube &>/dev/null ; then
    echo "Minikube seems to be installed on this system. Sure this is the vm host to be onboarded?"
    exit 1
  fi

  # Check if VM_GW_IP is set
  if [[ -z "${VM_GW_IP}" ]]; then
    echo "Could not find ENV variable VM_GW_IP, please set this to the IP address of the host running minikube"
    exit 1
  fi

  # Check if we can login to tsb docker registry
  if ! docker login -u ${TSB_DOCKER_USERNAME} -p ${TSB_DOCKER_PASSWORD} containers.dl.tetrate.io ; then
    echo "Could not find ENV variables TSB_DOCKER_USERNAME or TSB_DOCKER_PASSWORD. Please set them first."
    exit 1
  fi

  # Pull the demo image container
  if ! docker image inspect containers.dl.tetrate.io/obs-tester-server:1.0 &>/dev/null ; then
    echo "Pulling demo application image"
    docker pull containers.dl.tetrate.io/obs-tester-server:1.0 ;
  fi

  # Add /etc/host entries for egress
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/guides/setup#workload-configuration-egress
  if ! cat /etc/hosts | grep "The following lines are insterted for istio" &>/dev/null ; then
    cat ${VM_CONFDIR}/hosts | sudo tee -a /etc/hosts ;
  fi

  # Start app in a container (listen on host network)
  if ! docker ps | grep containers.dl.tetrate.io/obs-tester-server:1.0 &>/dev/null ; then
    docker run -d --restart=always --net=host --name app-b \
        -e SVCNAME=app-b \
      containers.dl.tetrate.io/obs-tester-server:1.0 \
        --log-output-level=all:debug \
        --http-listen-address=:8080 \
        --health-address=127.0.0.1:7777 \
        --ep-duration=0 \
        --ep-errors=0 \
        --ep-headers=0 \
        --zipkin-reporter-endpoint=http://zipkin.istio-system:9411/api/v2/spans \
        --zipkin-sample-rate=1.0 \
        --zipkin-singlehost-spans ;
  fi


  # Install istio sidecar, onboarding agent and sample jwt credential plugin
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/quickstart/on-premise/configure-vm#install-istio-sidecar
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/quickstart/on-premise/configure-vm#install-workload-onboarding-agent
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/quickstart/on-premise/configure-vm#install-sample-jwt-credential-plugin
  sudo mkdir -p /var/run/secrets/onboarding-agent-sample-jwt-credential-plugin
  sudo cp ${VM_CONFDIR}/sample-jwt-issuer.jwk /var/run/secrets/onboarding-agent-sample-jwt-credential-plugin/jwt-issuer.jwk
  sudo chmod 400 /var/run/secrets/onboarding-agent-sample-jwt-credential-plugin/jwt-issuer.jwk
  sudo chown onboarding-agent: -R /var/run/secrets/onboarding-agent-sample-jwt-credential-plugin/

  sudo mkdir -p /etc/onboarding-agent
  sudo cp ${VM_CONFDIR}/agent.config.yaml /etc/onboarding-agent/agent.config.yaml

  cat ${VM_CONFDIR}/install-onboarding-template.sh | sed s/__TSB_VM_ONBOARDING_ENDPOINT__/${VM_GW_IP}/g > ${VM_CONFDIR}/install-onboarding.sh ;
  chmod +x ${VM_CONFDIR}/install-onboarding.sh
  sudo ${VM_CONFDIR}/install-onboarding.sh
  sudo chown onboarding-agent: -R /var/run/secrets/onboarding-agent-sample-jwt-credential-plugin/

  # Configure OnboardingConfiguration
  # REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/workload_onboarding/quickstart/on-premise/onboard-vm
  cat ${VM_CONFDIR}/onboarding.config-template.yaml | sed s/__TSB_VM_ONBOARDING_ENDPOINT__/${VM_GW_IP}/g > ${VM_CONFDIR}/onboarding.config.yaml ;
  sudo mkdir -p /etc/onboarding-agent
  sudo cp ${VM_CONFDIR}/onboarding.config.yaml /etc/onboarding-agent/onboarding.config.yaml

  ### START ONBOARDING AGENT ###
  if systemctl is-active onboarding-agent.service &>/dev/null ; then
    sudo systemctl stop onboarding-agent
  fi
  sudo systemctl enable onboarding-agent
  sudo systemctl start onboarding-agent

  exit 0
fi

echo "Please specify one of the following action:"
echo "  - on-minikube-host"
echo "  - on-vm-host"
exit 1
