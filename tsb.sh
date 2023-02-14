#!/usr/bin/env bash

ACTION=${1}

MGMT_CLUSTER_PROFILE=mgmt-cluster-m1
ACTIVE_CLUSTER_PROFILE=active-cluster-m2
STANDBY_CLUSTER_PROFILE=standby-cluster-m3

# Patch deployment still using dockerhub: tsb/ratelimit-redis
function patch_dockerhub_dep_redis {
  while ! kubectl --context ${MGMT_CLUSTER_PROFILE} -n tsb set image deployment/ratelimit-redis redis=containers.dl.tetrate.io/redis:7.0.5-alpine &>/dev/null;
  do
    sleep 1 ;
  done
  echo "Deployment tsb/ratelimit-redis sucessfully patched"
}

# Patch deployment still using dockerhub: istio-system/ratelimit-server
function patch_dockerhub_dep_ratelimit {
  while ! kubectl --context ${MGMT_CLUSTER_PROFILE} -n istio-system set image deployment/ratelimit-server ratelimit=containers.dl.tetrate.io/ratelimit:5e9a43f9 &>/dev/null;
  do
    sleep 1 ;
  done
  echo "Deployment istio-system/ratelimit-server sucessfully patched"
}

# Create cacert secret in istio-system namespace
#   args:
#     (1) cluster name
function create_cert_secret {
  if ! kubectl get ns istio-system &>/dev/null; then kubectl create ns istio-system ; fi ;
  if ! kubectl -n istio-system get secret cacerts &>/dev/null; then
    kubectl create secret generic cacerts -n istio-system \
    --from-file=./certs/${1}/ca-cert.pem \
    --from-file=./certs/${1}/ca-key.pem \
    --from-file=./certs/${1}/root-cert.pem \
    --from-file=./certs/${1}/cert-chain.pem
  fi
}

# Login as admin into tsb
#   args:
#     (1) organization
function login_tsb_admin {
  expect <<DONE
  spawn tctl login --username admin --password admin --org ${1}
  expect "Tenant:" { send "\\r" }
  expect eof
DONE
}

# Remove tsb installation
#   args:
#     (1) cluster profile (kubernetes context)
function remove_tsb {
  kubectl config use-context ${1} ;

  # Put operators to sleep
  for NS in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl get deployments -n ${NS} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl scale deployment {} -n ${NS} --replicas=0 ; 
  done

  sleep 5 ;

  # Clean up namespace specific resources
  for NS in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl get deployments -n ${NS} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl delete deployment {} -n ${NS} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl delete --all deployments -n ${NS} --timeout=10s --wait=false ;
    kubectl delete --all jobs -n ${NS} --timeout=10s --wait=false ;
    kubectl delete --all statefulset -n ${NS} --timeout=10s --wait=false ;
    kubectl get deployments -n ${NS} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl patch deployment {} -n ${NS} --type json \
      --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
    kubectl delete --all deployments -n ${NS} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl delete namespace ${NS} --timeout=10s --wait=false ;
  done 

  # Clean up cluster wide resources
  kubectl get mutatingwebhookconfigurations -o custom-columns=:metadata.name \
    | xargs -I {} kubectl delete mutatingwebhookconfigurations {}  --timeout=10s --wait=false ;
  kubectl get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl delete crd {} --timeout=10s --wait=false ;
  kubectl get validatingwebhookconfigurations -o custom-columns=:metadata.name \
    | xargs -I {} kubectl delete validatingwebhookconfigurations {} --timeout=10s --wait=false ;
  kubectl get clusterrole -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
    | xargs -I {} kubectl delete clusterrole {} --timeout=10s --wait=false ;
  kubectl get clusterrolebinding -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
    | xargs -I {} kubectl delete clusterrolebinding {} --timeout=10s --wait=false ;

  # Cleanup custom resource definitions
  kubectl get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl delete crd {} --timeout=10s --wait=false ;
  sleep 5 ;
  kubectl get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl patch crd {} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
  sleep 5 ;
  kubectl get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl delete crd {} --timeout=10s --wait=false ;

  # Clean up pending finalizer namespaces
  kubectl proxy &
  PID_KP=$!
  sleep 5
  for NS in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    curl -k -H "Content-Type: application/json" -X PUT \
      -d "{ \"apiVersion\": \"v1\", \"kind\": \"Namespace\", \"metadata\": { \"name\": \"${NS}\" }, \"spec\": { \"finalizers\": [] } }" \
      http://127.0.0.1:8001/api/v1/namespaces/${NS}/finalize ;
  done
  kill ${PID_KP} ;

}

if [[ ${ACTION} = "install-mgmt-plane" ]]; then

  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;

  # bootstrap cluster with self signed certificate that share a common root certificate
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#intermediate-istio-ca-certificates
  create_cert_secret mgmt-cluster ;

  # start patching deployments that depend on dockerhub asynchronously
  patch_dockerhub_dep_redis &
  patch_dockerhub_dep_ratelimit &

  # install tsb management plane using the demo profile
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/demo-installation
  #   NOTE: the demo profile deploys both the mgmt plane AND the ctrl plane in a demo cluster!
  tctl install demo --registry containers.dl.tetrate.io --admin-password admin ;

  # Wait for the management, control and data plane to become available
  kubectl wait deployment -n tsb tsb-operator-management-plane --for condition=Available=True --timeout=600s ;
  kubectl wait deployment -n istio-system tsb-operator-control-plane --for condition=Available=True --timeout=600s ;
  kubectl wait deployment -n istio-gateway tsb-operator-data-plane --for condition=Available=True --timeout=600s ;
  while ! kubectl get deployment -n istio-system edge &>/dev/null; do sleep 1; done ;
  kubectl wait deployment -n istio-system edge --for condition=Available=True --timeout=600s ;
  kubectl get pods -A ;
      
  exit 0
fi


if [[ ${ACTION} = "onboard-app-clusters" ]]; then

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;

  # Deploy operators
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#deploy-operators
  tctl install manifest cluster-operators --registry containers.dl.tetrate.io \
    > ./config/mgmt-cluster/clusteroperators.yaml ;

  # Demo mgmt plane secret extraction (need to connect application clusters to mgmt cluster)
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets (demo install)
  kubectl get -n istio-system secret mp-certs -o jsonpath='{.data.ca\.crt}' \
    | base64 --decode > ./config/mgmt-cluster/mp-certs.pem ;
  kubectl get -n istio-system secret es-certs -o jsonpath='{.data.ca\.crt}' \
    | base64 --decode > ./config/mgmt-cluster/es-certs.pem ;
  kubectl get -n istio-system secret xcp-central-ca-bundle -o jsonpath='{.data.ca\.crt}' \
    | base64 --decode > ./config/mgmt-cluster/xcp-central-ca-certs.pem ;
  TSB_API_ENDPOINT=$(kubectl get svc -n tsb envoy --output jsonpath='{.status.loadBalancer.ingress[0].ip}') ;

  ##############################
  ### Cluster active-cluster ###
  ##############################
  kubectl config use-context ${ACTIVE_CLUSTER_PROFILE} ;

  # Generate a service account private key for the active cluster
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets
  tctl install cluster-service-account \
    --cluster active-cluster \
    > ./config/active-cluster/cluster-service-account.jwk ;

  # Create control plane secrets
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets
  tctl install manifest control-plane-secrets \
    --cluster active-cluster \
    --cluster-service-account="$(cat ./config/active-cluster/cluster-service-account.jwk)" \
    --elastic-ca-certificate="$(cat ./config/mgmt-cluster/es-certs.pem)" \
    --management-plane-ca-certificate="$(cat ./config/mgmt-cluster/mp-certs.pem)" \
    --xcp-central-ca-bundle="$(cat ./config/mgmt-cluster/xcp-central-ca-certs.pem)" \
    > ./config/active-cluster/controlplane-secrets.yaml ;

  # Generate controlplane.yaml by inserting the correct mgmt plane API endpoint IP address
  cat ./config/active-cluster/controlplane-template.yaml | sed s/__TSB_API_ENDPOINT__/${TSB_API_ENDPOINT}/g \
    > ./config/active-cluster/controlplane.yaml ;

  # bootstrap cluster with self signed certificate that share a common root certificate
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#intermediate-istio-ca-certificates
  create_cert_secret active-cluster ;

  # Applying operator, secrets and control plane configuration
  kubectl apply -f ./config/mgmt-cluster/clusteroperators.yaml ;
  kubectl apply -f ./config/active-cluster/controlplane-secrets.yaml ;
  while ! kubectl get controlplanes.install.tetrate.io &>/dev/null; do sleep 1; done ;
  kubectl apply -f ./config/active-cluster/controlplane.yaml ;

  ###############################
  ### Cluster standby-cluster ###
  ###############################
  kubectl config use-context ${STANDBY_CLUSTER_PROFILE} ;

  # Generate a service account private key for the standby cluster
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets
  tctl install cluster-service-account \
    --cluster standby-cluster \
    > ./config/standby-cluster/cluster-service-account.jwk ;

  # Create control plane secrets
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets
  tctl install manifest control-plane-secrets \
    --cluster standby-cluster \
    --cluster-service-account="$(cat ./config/standby-cluster/cluster-service-account.jwk)" \
    --elastic-ca-certificate="$(cat ./config/mgmt-cluster/es-certs.pem)" \
    --management-plane-ca-certificate="$(cat ./config/mgmt-cluster/mp-certs.pem)" \
    --xcp-central-ca-bundle="$(cat ./config/mgmt-cluster/xcp-central-ca-certs.pem)" \
    > ./config/standby-cluster/controlplane-secrets.yaml ;

  # Generate controlplane.yaml by inserting the correct mgmt plane API endpoint IP address
  cat ./config/standby-cluster/controlplane-template.yaml | sed s/__TSB_API_ENDPOINT__/${TSB_API_ENDPOINT}/g \
    > ./config/standby-cluster/controlplane.yaml ;

  # bootstrap cluster with self signed certificate that share a common root certificate
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#intermediate-istio-ca-certificates
  create_cert_secret standby-cluster ;

  # Applying operator, secrets and control plane configuration
  kubectl apply -f ./config/mgmt-cluster/clusteroperators.yaml ;
  kubectl apply -f ./config/standby-cluster/controlplane-secrets.yaml ;
  while ! kubectl get controlplanes.install.tetrate.io &>/dev/null; do sleep 1; done ;
  kubectl apply -f ./config/standby-cluster/controlplane.yaml ;

  ###############
  ### Extra's ###
  ###############
  # Apply AOP patch for more real time update in the UI (Apache SkyWalking demo tweak)
  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;
  kubectl -n tsb patch managementplanes managementplane --patch-file ./config/oap-deploy-patch.yaml --type merge ;
  kubectl -n istio-system patch controlplanes controlplane --patch-file ./config/oap-deploy-patch.yaml --type merge ;
  kubectl config use-context ${ACTIVE_CLUSTER_PROFILE} ;
  kubectl -n istio-system patch controlplanes controlplane --patch-file ./config/oap-deploy-patch.yaml --type merge ;
  kubectl config use-context ${STANDBY_CLUSTER_PROFILE} ;
  kubectl -n istio-system patch controlplanes controlplane --patch-file ./config/oap-deploy-patch.yaml --type merge ;

  # Wait for the control and data plane to become available
  kubectl config use-context ${ACTIVE_CLUSTER_PROFILE} ;
  kubectl wait deployment -n istio-system tsb-operator-control-plane --for condition=Available=True --timeout=600s ;
  kubectl wait deployment -n istio-gateway tsb-operator-data-plane --for condition=Available=True --timeout=600s ;
  while ! kubectl get deployment -n istio-system edge &>/dev/null; do sleep 1; done ;
  kubectl wait deployment -n istio-system edge --for condition=Available=True --timeout=600s ;
  kubectl get pods -A ;

  kubectl config use-context ${STANDBY_CLUSTER_PROFILE} ;
  kubectl wait deployment -n istio-system tsb-operator-control-plane --for condition=Available=True --timeout=600s ;
  kubectl wait deployment -n istio-gateway tsb-operator-data-plane --for condition=Available=True --timeout=600s ;
  while ! kubectl get deployment -n istio-system edge &>/dev/null; do sleep 1; done ;
  kubectl wait deployment -n istio-system edge --for condition=Available=True --timeout=600s ;
  kubectl get pods -A ;

  exit 0
fi


if [[ ${ACTION} = "config-tsb" ]]; then

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;

  # Clusters, organization and tenants
  tctl apply -f ./config/mgmt-cluster/tsb/01-clusters.yaml ;
  tctl apply -f ./config/mgmt-cluster/tsb/02-organization.yaml ;
  tctl apply -f ./config/mgmt-cluster/tsb/03-tenants.yaml ;

  # Namespace for T1 Gateways
  kubectl apply -f ./config/mgmt-cluster/k8s/01-namespaces.yaml ;

  # Installing systemd service for tsb-gui
  export KUBECTL=$(which kubectl)
  envsubst < ./config/tsb-gui-template.service > ./config/tsb-gui.service ;
  sudo cp ./config/tsb-gui.service /etc/systemd/system ;
  if systemctl is-active tsb-gui.service &>/dev/null ; then sudo systemctl stop tsb-gui 2>/dev/null && sudo systemctl daemon-reload ; fi
  sudo systemctl enable tsb-gui ;
  sudo systemctl start tsb-gui ;
  sleep 1

  echo "The tsb gui should be available at https://$(curl -s ifconfig.me):8443"
  exit 0
fi


if [[ ${ACTION} = "reset-tsb" ]]; then

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin tetrate ;

  # Remove all TSB configuration objects
  tctl get all --org tetrate --tenant prod | tctl delete -f - ;

  # Remove all TSB kubernetes installation objects for gateways
  kubectl config use-context ${MGMT_CLUSTER_PROFILE} ;
  kubectl get crds -o custom-columns=:metadata.name | grep "gateways.install.tetrate.io" | xargs -I {} kubectl delete {} ;

  exit 0
fi


if [[ ${ACTION} = "remove-tsb" ]]; then

  # Remove tsb completely from the 3 clusters
  remove_tsb ${STANDBY_CLUSTER_PROFILE} ;
  remove_tsb ${ACTIVE_CLUSTER_PROFILE} ;
  remove_tsb ${MGMT_CLUSTER_PROFILE} ;
  sleep 10 ;

  exit 0
fi


echo "Please specify one of the following action:"
echo "  - install-mgmt-plane"
echo "  - onboard-app-clusters"
echo "  - config-tsb"
echo "  - reset-tsb"
echo "  - remove-tsb"
exit 1
